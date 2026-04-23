# STREAMING FRAUD INFERENCE FOR TUTORIAL 2.

import argparse
import json
import os
import threading
import time
from pathlib import Path

from google.cloud import pubsub_v1
from pyspark.ml import PipelineModel
from pyspark.sql import SparkSession
from pyspark.sql.types import DoubleType, StructField, StructType

# Build an argument parser for command-line configuration of the streaming scoring job.
def build_arg_parser():

    # Initialize the argument parser with a description of the script's purpose.
    parser = argparse.ArgumentParser(
        description="Stream-score Pub/Sub transactions through a saved Spark PipelineModel."
    )

    # Add an argument for directory where model is saved
    parser.add_argument(
        "--model-dir",
        required=True,
        help="Directory holding the saved Spark PipelineModel.",
    )

    # Add arguments for GCP project id
    parser.add_argument(
        "--project-id",
        required=True,
        help="GCP project ID.",
    )

    # Add an argument for Pub/Sub subscription ID (not full path)
    parser.add_argument(
        "--subscription",
        required=True,
        help="Pub/Sub subscription ID (not full path) to consume from.",
    )

    # Add an argument for where to write the final fraud report once the sentinel arrives
    parser.add_argument(
        "--report-path",
        default="/app/output/fraud_report.json",
        help="Where to write the final fraud report once the sentinel arrives.",
    )

    # Add an argument for a hard cap on runtime to prevent a hung subscription from running indefinitely
    parser.add_argument(
        "--max-runtime-seconds",
        type=int,
        default=600,
        help="Hard cap so a hung subscription does not run forever (default 10 minutes).",
    )
    return parser

#Define schema: what coloumns and types the model expects as input. Should match training dataset schema.
def feature_schema():
    fields = [StructField("Time", DoubleType(), True)]
    fields += [StructField(f"V{i}", DoubleType(), True) for i in range(1, 29)]
    fields += [StructField("Amount", DoubleType(), True)]
    return StructType(fields)


def main():
    # PARSE ARGUMENTS
    args = build_arg_parser().parse_args()

    # Initialize SparkSession for scoring. We use local mode since this is a single-machine streaming job, and disable the UI for cleanliness.
    spark = (
        SparkSession.builder.master("local[*]")
        .appName("FraudStreamScoring")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    #Load saved model 
    print(f"Loading PipelineModel from {args.model_dir}")
    model = PipelineModel.load(args.model_dir)

    # Get schema from the models input data
    schema = feature_schema()
    feature_cols = [f.name for f in schema.fields]

    # Create a shared state dict and lock for communication between the Pub/Sub callback and the main scoring loop.
    state = {
        "buffer": [],         # ROWS WAITING TO BE SCORED
        "frauds": [],         # ROWS THE MODEL FLAGGED AS FRAUD
        "total_messages": 0,  # ALL NON-SENTINEL MESSAGES SEEN
        "done": False,        # SET WHEN SENTINEL ARRIVES OR TIMEOUT
        "sentinel_total": None,
    }
    lock = threading.Lock() # Set up a lock to ensure thread-safe access to the shared state dictionary

    # Function to handle incoming Pub/Sub messages
    def callback(message):
        try:
            # Load and parse the Pub/Sub message payload as JSON.
            payload = json.loads(message.data.decode("utf-8"))

            # If the payload contains the sentinel value, 
            # update the state to indicate we're done and store the total published count
            if payload.get("__sentinel") == "DONE":
                with lock:
                    state["sentinel_total"] = int(payload.get("total_published", 0))
                    state["done"] = True
                message.ack()
                return
            
            # Add the payload to the buffer and increment the message count
            with lock:
                state["buffer"].append(payload)
                state["total_messages"] += 1
            message.ack()

        # Log any error that occurs during message processing and nack the message to indicate it was not processed successfully.
        except Exception as exc:
            print(f"Callback error: {exc}")
            message.nack()

    #Intialize Pub/Sub subscriber and subscribe to the specified subscription with the callback function.
    subscriber = pubsub_v1.SubscriberClient()
    subscription_path = subscriber.subscription_path(args.project_id, args.subscription)
    print(f"Subscribing to {subscription_path}")
    streaming_pull = subscriber.subscribe(subscription_path, callback=callback)

    # Record the start time of the streaming scoring job to enforce the maximum runtime limit.
    start_time = time.time()
    last_drain = start_time

    try:
        while True:

            # Calculate the elapsed time and check if it exceeds the maximum runtime specified.
            elapsed = time.time() - start_time
            if elapsed > args.max_runtime_seconds:
                print(f"Hit max runtime ({args.max_runtime_seconds}s) - finalising")
                break

            # Determine if we should drain the buffer (score the accumulated messages)
            should_drain = False
            with lock:
                # Check how many messages currently in buffer and if the sentinel has arrived
                buffered = len(state["buffer"])
                done = state["done"]

            # If there are at least 50 messages buffered, 
            # or if the sentinel has arrived and there are any messages buffered, 
            # or if it's been more than 1 second since the last drain and there are messages buffered,
            #  then we should drain the buffer and score the messages.
            if buffered >= 50 or (buffered > 0 and time.time() - last_drain > 1.0) or (done and buffered > 0):
                should_drain = True

            # Drain buffer and score transactions
            if should_drain:

                # Reset the buffer and record the time of this drain to enforce the 1-second drain interval.
                with lock:
                    batch = state["buffer"]
                    state["buffer"] = []
                last_drain = time.time()

                # Converts payload to Spark DataFrame rows
                rows = []
                for payload in batch:
                    try:
                        rows.append(tuple(float(payload[col]) for col in feature_cols))
                    except (KeyError, ValueError):
                        # Skip bad rows
                        continue

                if rows:
                    # Create Spark DataFrame from the processed buffered rows
                    df = spark.createDataFrame(rows, schema=schema)

                    # Score the DataFrame 
                    scored = model.transform(df)

                    # Collect transactions flagged as fraud
                    flagged = scored.filter(scored.prediction == 1.0).select(*feature_cols, "prediction").collect()
                    
                    # If any transaction flagged as fraud, add it to the state and print a message with the transaction details.
                    if flagged:
                        with lock:
                            for r in flagged:
                                fraud_record = {col: r[col] for col in feature_cols}
                                fraud_record["prediction"] = float(r["prediction"])
                                state["frauds"].append(fraud_record)
                                print(f"FRAUD FLAGGED: time={r['Time']:.1f} amount={r['Amount']:.2f}")

            # If sentinel arrived and buffer is empty break loop and finalise report
            with lock:
                if state["done"] and not state["buffer"]:
                    break

            time.sleep(0.2)
    
    finally:
        # Tell subscriber to stop listening and begin shutdown process.
        streaming_pull.cancel()
        try:
            # Wait for subscriber to fully shut down 
            streaming_pull.result(timeout=10)

        except Exception:
            print("Subscriber shutdown timed out, exiting anyway.")
            pass

    # Create a path for the report
    report_path = Path(args.report_path)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with lock:
        report = {
            "total_messages_seen": state["total_messages"],
            "sentinel_total_published": state["sentinel_total"],
            "frauds_flagged_count": len(state["frauds"]),
            "frauds": state["frauds"][:100],  # CAP REPORT SIZE
            "elapsed_seconds": round(time.time() - start_time, 2),
        }
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    # Print summary and stop SparkSession
    print("=== STREAM SCORING COMPLETE ===")
    print(f"Messages seen:    {report['total_messages_seen']}")
    print(f"Frauds flagged:   {report['frauds_flagged_count']}")
    print(f"Report written:   {report_path}")
    spark.stop()


if __name__ == "__main__":
    main()
