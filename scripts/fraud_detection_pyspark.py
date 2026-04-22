import argparse
import csv
import json
from pathlib import Path
from pyspark.ml import Pipeline
from pyspark.ml.classification import LogisticRegression
from pyspark.ml.evaluation import BinaryClassificationEvaluator
from pyspark.ml.feature import VectorAssembler
from pyspark.sql import SparkSession

SEED = 2003

TRAIN_SPLIT = 0.8
TEST_SPLIT = 0.2

#Function to build argument parser for the script
def build_arg_parser():

    # Create an argument parser for the fraud detection script
    parser = argparse.ArgumentParser(
        description="Run a PySpark credit card fraud detection prototype."
    )

    # Add an argument for the data path
    parser.add_argument(
        "--data-path",
        default="data/creditcard.csv",
        help="Path to the credit card fraud CSV file.",
    )

    # Add an argument for the output directory
    parser.add_argument(
        "--output-dir",
        default="output",
        help="Directory where summary files and sample predictions will be written.",
    )

    # Add an argument for the maximum iterations for Logistic Regression
    parser.add_argument(
        "--max-iter",
        type=int,
        default=10,
        help="Maximum iterations for LogisticRegression.",
    )

    # Add an argument for the sample fraction to allow for faster prototype runs
    parser.add_argument(
        "--sample-fraction",
        type=float,
        default=1.0,
        help="Optional fraction of rows to use for a faster prototype run.",
    )
    parser.add_argument(
        "--decision-threshold",
        type=float,
        default=0.1,
        help="Classification threshold applied by LogisticRegression for the fraud class.",
    )
    return parser


def main():
    args = build_arg_parser().parse_args()      # Parse command-line arguments
    data_path = Path(args.data_path)            # Create path for the dataset
    output_dir = Path(args.output_dir)          # Create path for the output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    if not data_path.exists():
        raise FileNotFoundError(
            f"Dataset not found at {data_path}. Copy creditcard.csv into the data directory first."
        )

    # Initialize Spark session
    spark = (
        SparkSession.builder.master("local[*]")
        .appName("CreditCardFraudDetection")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    try:
        # Load the dataset into a Spark DataFrame
        raw_df = spark.read.csv(str(data_path), header=True, inferSchema=True)

        working_df = raw_df
        # If a sample fraction is specified, take a random sample of the data for faster processing
        if args.sample_fraction < 1.0:
            working_df = raw_df.sample(
                withReplacement=False,
                fraction=args.sample_fraction,
                seed=SEED,
            )

        # Count the number of rows before cleaning
        rows_before = working_df.count()

        # Perform basic data cleaning: drop rows with null values and duplicates, and rename the target column to "label"
        clean_df = (
            working_df.na.drop()
            .dropDuplicates()
            .withColumnRenamed("Class", "label")
        )

        # Cache the cleaned DataFrame to optimize subsequent operations and count the number of rows after cleaning
        clean_df.cache()
        rows_after = clean_df.count()

        # Create temporary transactions table for SQL view
        clean_df.createOrReplaceTempView("transactions")

        # Write summary showing dataset statistics
        sql_summary = spark.sql(
            """
            SELECT
                label,
                COUNT(*) AS transaction_count,
                ROUND(AVG(Amount), 2) AS avg_amount,
                ROUND(MAX(Amount), 2) AS max_amount
            FROM transactions
            GROUP BY label
            ORDER BY label
            """
        )

        # Select feature columns for the model
        feature_cols = [column for column in clean_df.columns if column != "label"]

        # Split the cleaned DataFrame into training and test sets using a random split
        train_df, test_df = clean_df.randomSplit([TRAIN_SPLIT, TEST_SPLIT], seed=SEED)

        # Assembler to combine feature columns into a single vector column for the model
        assembler = VectorAssembler(
            inputCols=feature_cols,
            outputCol="features",
        )

        # Initialize a Logistic Regression model for binary classification
        lr = LogisticRegression(
            featuresCol="features",
            labelCol="label",
            maxIter=args.max_iter,
            threshold=args.decision_threshold,
        )

        # Create Pipeline to connect layers
        pipeline = Pipeline(stages=[assembler, lr])

        # Fit the model on the training data and make predictions on the test data
        model = pipeline.fit(train_df)
        predictions = model.transform(test_df)

        #Initialize and use Binary Classification Evaluator to evaluate the model's performance using Area Under ROC metric
        evaluator = BinaryClassificationEvaluator(
            labelCol="label",
            rawPredictionCol="rawPrediction",
            metricName="areaUnderROC",
        )
        auc = evaluator.evaluate(predictions)

        # Build confusion matrix
        confusion_matrix = (
            predictions.groupBy("label", "prediction")
            .count()
            .orderBy("label", "prediction")
        )

        # Write a sample of predictions to a CSV file for manual inspection
        sample_predictions_path = output_dir / "sample_predictions.csv"

        # Collect a sample of predictions and write them to a CSV file with headers "label" and "prediction"
        sample_prediction_rows = (
            predictions.select("label", "prediction").limit(50).collect()
        )

        # Write the sample predictions to a CSV file
        with sample_predictions_path.open("w", encoding="utf-8", newline="") as csv_file:
            writer = csv.writer(csv_file)
            writer.writerow(["label", "prediction"])
            for row in sample_prediction_rows:
                writer.writerow([int(row["label"]), int(row["prediction"])])

        #Create a summary dictionary to hold all the relevant statistics and evaluation results for the fraud detection
        summary = {
            "dataset_path": str(data_path),
            "rows_before_cleaning": rows_before,
            "rows_after_cleaning": rows_after,
            "train_rows": train_df.count(),
            "test_rows": test_df.count(),
            "sample_fraction": args.sample_fraction,
            "max_iter": args.max_iter,
            "decision_threshold": args.decision_threshold,
            "area_under_roc": round(auc, 4),
            "sql_summary": [
                {
                    "label": int(row["label"]),
                    "transaction_count": int(row["transaction_count"]),
                    "avg_amount": float(row["avg_amount"]),
                    "max_amount": float(row["max_amount"]),
                }
                for row in sql_summary.collect()
            ],
            "confusion_matrix": [
                {
                    "label": int(row["label"]),
                    "prediction": int(row["prediction"]),
                    "count": int(row["count"]),
                }
                for row in confusion_matrix.collect()
            ],
        }

        # Create a summary JSON file and write the summary statistics and evaluation results
        summary_path = output_dir / "summary.json"
        summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

        # Print summary statistics to the console for quick reference
        print("Fraud detection prototype completed successfully.")
        print(f"Rows before cleaning: {rows_before}")
        print(f"Rows after cleaning: {rows_after}")
        print(f"Training rows: {summary['train_rows']}")
        print(f"Test rows: {summary['test_rows']}")
        print(f"Area Under ROC: {summary['area_under_roc']:.4f}")
        print(f"Summary written to: {summary_path}")
        print(f"Sample predictions written to: {sample_predictions_path}")
    
    # End the Spark session in a finally block to ensure it happens even if an error occurs
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
