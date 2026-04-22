# PUB/SUB PUBLISHER FOR TUTORIAL 2.

# Simulation of streaming credit card transactions

import argparse
import csv
import json
import time

from google.cloud import pubsub_v1

#Build argument parser for command-line arguments
def build_arg_parser():

    #Initialize the argument parser
    parser = argparse.ArgumentParser(
        description="Publish credit-card transactions to Pub/Sub for streaming inference."
    )

    # Add argument for the path to the pre-baked streaming subset CSV
    parser.add_argument(
        "--csv-path",
        required=True,
        help="Path to the pre-baked streaming subset CSV (downloaded from GCS).",
    )

    # Add argument for the GCP project ID
    parser.add_argument(
        "--project-id",
        required=True,
        help="GCP project ID.",
    )

    # Add argument for the Pub/Sub topic ID to publish to
    parser.add_argument(
        "--topic",
        required=True,
        help="Pub/Sub topic ID (not full path).",
    )

    # Add argument for the target publish rate in messages per second
    parser.add_argument(
        "--rate",
        type=float,
        default=10.0,
        help="Target publish rate in messages per second.",
    )
    return parser

def main():
    # Parse command-line arguments
    args = build_arg_parser().parse_args()

    # Read the dataset for simulated streaming from the specified CSV file
    with open(args.csv_path, "r", encoding="utf-8") as csv_file:
        rows = list(csv.DictReader(csv_file))

    # Initialize the Pub/Sub publisher client and construct the topic path
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(args.project_id, args.topic)
    sleep_seconds = 1.0 / args.rate if args.rate > 0 else 0.0 # Calculate sleep time between messages

    print(f"Publishing {len(rows)} transactions to {topic_path} at ~{args.rate} msg/s")

    # Publish each transaction as a JSON message to the specified Pub/Sub topic
    futures = []
    for idx, row in enumerate(rows):
        # PUB/SUB MESSAGES ARE BYTES - JSON IS THE WIRE FORMAT
        payload = dict(row)
        payload["__id"] = idx
        data = json.dumps(payload).encode("utf-8")
        future = publisher.publish(topic_path, data=data)
        futures.append(future)
        if sleep_seconds:
            time.sleep(sleep_seconds)
        if (idx + 1) % 500 == 0:
            print(f"  ... published {idx + 1} messages")

    # Publish a sentinel message to signal the end of the stream, including the total number of published transactions
    sentinel = json.dumps({"__sentinel": "DONE", "total_published": len(rows)}).encode("utf-8")
    futures.append(publisher.publish(topic_path, data=sentinel))

    # Wait for all publish futures to complete, with a timeout to avoid hanging indefinitely
    for future in futures:
        future.result(timeout=60)

    print(f"Done. Published {len(rows)} transactions + 1 sentinel.")


if __name__ == "__main__":
    main()
