#!/usr/bin/env bash

# STARTUP SCRIPT (STREAM VM): PULL SCORING IMAGE -> RUN CONSUMER -> RUN PUBLISHER -> DISPLAY REPORT.

set -euxo pipefail

# Disable interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive

# Variables (injected from Terraform)
WORKDIR="/opt/fraud-stream"
LOG_PATH="/var/log/startup.log"
DATA_BUCKET="${dataset_bucket_name}"
DATA_OBJECT="${stream_subset_object_name}"
LOCAL_CSV_NAME="transactions_stream.csv"
SCORING_IMAGE_URL="${scoring_image_url}"
REGION="${region}"
PROJECT_ID="${project_id}"
PUBSUB_TOPIC="${pubsub_topic_id}"
PUBSUB_SUBSCRIPTION="${pubsub_subscription_id}"

# Setup logging to file and console
exec > >(tee -a "$LOG_PATH") 2>&1

# Prints current timestamp for logging purposes
echo "=== Stream VM startup begin: $(date -u) ==="

#Install dependencies
apt-get update
apt-get install -y docker.io git curl jq python3-pip
systemctl enable --now docker

#Wait for docker to be ready
until docker info >/dev/null 2>&1; do
  sleep 2
done

# Create working directories
mkdir -p "$WORKDIR/data" "$WORKDIR/output" "$WORKDIR/scripts"

# write publisher script
cat > "$WORKDIR/scripts/publish_transactions.py" <<'EOF_PUBLISH'
${publish_script_py}
EOF_PUBLISH

# Download dataset from GCS to local VM storage
ENCODED_OBJECT="$(jq -rn --arg value "$DATA_OBJECT" '$value|@uri')"
ACCESS_TOKEN="$(curl --fail --silent --show-error -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r '.access_token')"
curl --fail --location --silent --show-error \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -o "$WORKDIR/data/$LOCAL_CSV_NAME" \
  "https://storage.googleapis.com/storage/v1/b/$DATA_BUCKET/o/$ENCODED_OBJECT?alt=media"

# Install Pub/Sub client library for the publisher script (consumer image has it pre-installed)
pip3 install --quiet google-cloud-pubsub==2.21.5

# Pull scoring image from Artifact Registry (this will also authenticate Docker to pull from the private registry)
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
docker pull "$SCORING_IMAGE_URL"

echo "=== Scoring image pulled. Starting consumer. ==="

# Start the streaming consumer in the background.
docker run -d \
  --name fraud-scoring \
  -v "$WORKDIR/output:/app/output" \
  "$SCORING_IMAGE_URL" \
  python scripts/score_stream.py \
    --model-dir /app/model \
    --project-id "$PROJECT_ID" \
    --subscription "$PUBSUB_SUBSCRIPTION" \
    --report-path /app/output/fraud_report.json \
    --max-runtime-seconds 600

# Wait a bit to ensure the consumer is up and subscribed before we start publishing messages.
sleep 10

# Run publisher from the VM host (not containerised) - simpler, fewer moving parts.
python3 "$WORKDIR/scripts/publish_transactions.py" \
  --csv-path "$WORKDIR/data/$LOCAL_CSV_NAME" \
  --project-id "$PROJECT_ID" \
  --topic "$PUBSUB_TOPIC" \
  --rate 25

echo "=== Publisher finished. Waiting for consumer to flush... ==="

# Wait for the consumer to finish processing and write its report (with a timeout to avoid waiting indefinitely if something goes wrong).
for i in $(seq 1 60); do
  if [ -f "$WORKDIR/output/fraud_report.json" ]; then
    break
  fi
  sleep 5
done

# Display the report to the startup log so it is visible without SSHing into the VM.
if [ -f "$WORKDIR/output/fraud_report.json" ]; then
  echo "=== FRAUD REPORT ==="
  cat "$WORKDIR/output/fraud_report.json"

  # ALSO upload the report back to GCS for permanent storage and easier access
  ACCESS_TOKEN="$(curl --fail --silent --show-error -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r '.access_token')"
  curl --fail --silent --show-error \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "@$WORKDIR/output/fraud_report.json" \
    "https://storage.googleapis.com/upload/storage/v1/b/$DATA_BUCKET/o?uploadType=media&name=reports/fraud_report.json" \
    > /dev/null
  echo "=== Report uploaded to gs://$DATA_BUCKET/reports/fraud_report.json ==="
else
  echo "=== WARNING: fraud_report.json not produced within timeout ==="
  docker logs fraud-scoring || true
fi

echo "=== Stream VM startup complete: $(date -u) ==="
