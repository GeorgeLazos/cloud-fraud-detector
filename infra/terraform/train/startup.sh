#!/usr/bin/env bash
#STARTUP SCRIPT (TRAIN VM): BUILD BASE -> TRAIN -> BUILD SCORING -> PUSH SCORING IMAGE.

set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# VARIABLES INJECTED BY TERRAFORM
WORKDIR="/opt/fraud-train"
LOG_PATH="/var/log/startup.log"
DATA_BUCKET="${dataset_bucket_name}"
DATA_OBJECT="${dataset_object_name}"
ARTIFACT_REPO_URL="${artifact_repo_url}"
BASE_IMAGE_URL="${base_image_url}"
SCORING_IMAGE_URL="${scoring_image_url}"
REGION="${region}"

# REDIRECT ALL STDOUT/STDERR TO THE STARTUP LOG SO THE WORKFLOW IS INSPECTABLE OVER IAP SSH
exec > >(tee -a "$LOG_PATH") 2>&1

echo "=== Train VM startup begin: $(date -u) ==="

# Install dependencies
apt-get update
apt-get install -y docker.io git curl jq
systemctl enable --now docker

# Wait for docker to be ready before proceeding
until docker info >/dev/null 2>&1; do
  sleep 2
done

# STAGE PROJECT FILES INTO WORKDIR (TERRAFORM TEMPLATEFILE INJECTS CONTENTS BELOW)
mkdir -p "$WORKDIR/docker" "$WORKDIR/scripts" "$WORKDIR/data" "$WORKDIR/output"

# Write dockerignore
cat > "$WORKDIR/.dockerignore" <<'EOF_DOCKERIGNORE'
${dockerignore_txt}
EOF_DOCKERIGNORE

# Write Dockerfiles
cat > "$WORKDIR/docker/Dockerfile" <<'EOF_DOCKERFILE'
${dockerfile_txt}
EOF_DOCKERFILE

# Write scoring Dockerfile
cat > "$WORKDIR/docker/Dockerfile.scoring" <<'EOF_DOCKERFILE_SCORING'
${dockerfile_scoring_txt}
EOF_DOCKERFILE_SCORING

# Write requirements.txt
cat > "$WORKDIR/requirements.txt" <<'EOF_REQUIREMENTS'
${requirements_txt}
EOF_REQUIREMENTS

# Write training script
cat > "$WORKDIR/scripts/fraud_detection_pyspark.py" <<'EOF_TRAIN_SCRIPT'
${fraud_script_py}
EOF_TRAIN_SCRIPT

# Write scoring script
cat > "$WORKDIR/scripts/score_stream.py" <<'EOF_SCORE_SCRIPT'
${score_script_py}
EOF_SCORE_SCRIPT

# Write publish transactions script
cat > "$WORKDIR/scripts/publish_transactions.py" <<'EOF_PUBLISH_SCRIPT'
${publish_script_py}
EOF_PUBLISH_SCRIPT

# Download dataset from Cloud Storage (GCS Bucket) on the VM 
ENCODED_OBJECT="$(jq -rn --arg value "$DATA_OBJECT" '$value|@uri')"
ACCESS_TOKEN="$(curl --fail --silent --show-error -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r '.access_token')"
curl --fail --location --silent --show-error \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -o "$WORKDIR/data/creditcard.csv" \
  "https://storage.googleapis.com/storage/v1/b/$DATA_BUCKET/o/$ENCODED_OBJECT?alt=media"

echo "=== Dataset downloaded: $(ls -la $WORKDIR/data/creditcard.csv) ==="

# Build docker image on the VM
docker build \
  -f "$WORKDIR/docker/Dockerfile" \
  -t "$BASE_IMAGE_URL" \
  "$WORKDIR"

echo "=== Base image built: $BASE_IMAGE_URL ==="

# Run training script in the countainer, mounting the data and output directories as volumes.
docker run \
  --rm \
  -v "$WORKDIR/data:/app/data:ro" \
  -v "$WORKDIR/output:/app/output" \
  "$BASE_IMAGE_URL" \
  python scripts/fraud_detection_pyspark.py \
    --data-path /app/data/creditcard.csv \
    --output-dir /app/output \
    --max-iter 10 \
    --model-output-dir /app/output/model

echo "=== Training complete. Model files: ==="
ls -la "$WORKDIR/output/model"

# Build the scoring image
docker build \
  -f "$WORKDIR/docker/Dockerfile.scoring" \
  --build-arg "BASE_IMAGE=$BASE_IMAGE_URL" \
  -t "$SCORING_IMAGE_URL" \
  "$WORKDIR/output"

echo "=== Scoring image built: $SCORING_IMAGE_URL ==="

# Upload scoring image to Artifact Registry so it can be deployed later by prediction service.
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
docker push "$SCORING_IMAGE_URL"

echo "=== Scoring image pushed to Artifact Registry ==="

# Upload summary.json to GCP bucket if it exists (contains training metrics and metadata about the training run)
if [ -f "$WORKDIR/output/summary.json" ]; then
  curl --fail --silent --show-error \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "@$WORKDIR/output/summary.json" \
    "https://storage.googleapis.com/upload/storage/v1/b/$DATA_BUCKET/o?uploadType=media&name=summaries/summary.json" \
    > /dev/null
  echo "=== summary.json uploaded to gs://$DATA_BUCKET/summaries/summary.json ==="
fi

echo "=== Train VM startup complete: $(date -u) ==="
