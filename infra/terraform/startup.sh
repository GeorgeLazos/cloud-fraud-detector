#!/usr/bin/env bash
set -euxo pipefail   # Exit on error, treat unset variables as errors, and print commands as they are executed.

# Stops interactive prompts
export DEBIAN_FRONTEND=noninteractive

#Variables
WORKDIR="/opt/vm-ml-tutorial"             # Main folder of the VM
LOG_PATH="$WORKDIR/startup.log"           # Path to the startup log
IMAGE_NAME="fraud-pyspark:v1.0"           # Name of the built docker image
CONTAINER_NAME="fraud-pyspark"            # Name of running container instance
DATA_PATH="$WORKDIR/data/creditcard.csv"  # Path where the downloaded dataset will be stored
DATA_BUCKET="${dataset_bucket_name}"      # GCS bucket that stores the dataset
DATA_OBJECT="${dataset_object_name}"      # GCS object name for the dataset

#Install Docker and Git
apt-get update
apt-get install -y docker.io git curl jq
systemctl enable --now docker

#Create folders inside WORKDIR
mkdir -p "$WORKDIR/docker" "$WORKDIR/scripts" "$WORKDIR/data" "$WORKDIR/output"

# Write dockerignore to the VM
cat > "$WORKDIR/.dockerignore" <<'EOF_DOCKERIGNORE'
${dockerignore_txt}
EOF_DOCKERIGNORE

# Write Dockerfile to the VM
cat > "$WORKDIR/docker/Dockerfile" <<'EOF_DOCKERFILE'
${dockerfile_txt}
EOF_DOCKERFILE

# Write requirements.txt to the VM
cat > "$WORKDIR/requirements.txt" <<'EOF_REQUIREMENTS'
${requirements_txt}
EOF_REQUIREMENTS

# Write the fraud detection script to the VM
cat > "$WORKDIR/scripts/fraud_detection_pyspark.py" <<'EOF_SCRIPT'
${fraud_script_py}
EOF_SCRIPT

# Write script to create and run the docker container to the VM
cat > /usr/local/bin/run_fraud_detection.sh <<'EOF_RUNNER'
#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/opt/vm-ml-tutorial"
IMAGE_NAME="fraud-pyspark:v1.0"
CONTAINER_NAME="fraud-pyspark"
DATA_PATH="$WORKDIR/data/creditcard.csv"

if [ "$(id -u)" -eq 0 ]; then
  DOCKER_CMD=(docker)
else
  DOCKER_CMD=(sudo docker)
fi

if [ ! -f "$DATA_PATH" ]; then
  echo "Dataset not found at $DATA_PATH" >&2
  echo "Upload creditcard.csv to /opt/vm-ml-tutorial/data/creditcard.csv before running this command." >&2
  exit 1
fi

"$${DOCKER_CMD[@]}" build -f "$WORKDIR/docker/Dockerfile" -t "$IMAGE_NAME" "$WORKDIR"
"$${DOCKER_CMD[@]}" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
"$${DOCKER_CMD[@]}" run \
  --name "$CONTAINER_NAME" \
  --rm \
  -v "$WORKDIR/data:/app/data:ro" \
  -v "$WORKDIR/output:/app/output" \
  "$IMAGE_NAME" | tee "$WORKDIR/output/run.log"
EOF_RUNNER

# Wait for Docker to be fully operational before proceeding
until docker info >/dev/null 2>&1; do
  sleep 2
done

# Set permissions for the runner script and the WORKDIR
chmod 755 /usr/local/bin/run_fraud_detection.sh         # Make the runner script executable
chmod -R a+rX "$WORKDIR"                                # Set read and execute permissions for all users on the WORKDIR and its contents
chmod a+rwx "$WORKDIR/data" "$WORKDIR/output"           # Make data and output directories writable for all users

# Download the dataset from GCS and run the workload automatically
ENCODED_OBJECT="$(jq -rn --arg value "$DATA_OBJECT" '$value|@uri')"
ACCESS_TOKEN="$(curl --fail --silent --show-error -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r '.access_token')"
curl --fail --location --silent --show-error \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -o "$DATA_PATH" \
  "https://storage.googleapis.com/storage/v1/b/$DATA_BUCKET/o/$ENCODED_OBJECT?alt=media"
run_fraud_detection.sh

#Startup Log
cat > "$LOG_PATH" <<'EOF'
Terraform startup script completed successfully.

- Docker was installed and started
- application files were staged in /opt/vm-ml-tutorial
- creditcard.csv was downloaded automatically from GCS to /opt/vm-ml-tutorial/data/creditcard.csv
- the fraud detection container was run automatically once
- use run_fraud_detection.sh to rerun the container later
EOF

#README
cat > "$WORKDIR/README.txt" <<'EOF'
Terraform startup script completed successfully.

This VM has already been prepared for the tutorial:
- Docker was installed and started automatically
- Application files and docker/ packaging files were staged at /opt/vm-ml-tutorial
- Fraud detection script was staged at /opt/vm-ml-tutorial/scripts/fraud_detection_pyspark.py
- Dataset was downloaded automatically to /opt/vm-ml-tutorial/data/creditcard.csv
- Output directory was created at /opt/vm-ml-tutorial/output
- Startup log is stored at /opt/vm-ml-tutorial/startup.log

Helpful commands:
1. cat /opt/vm-ml-tutorial/startup.log
2. ls -la /opt/vm-ml-tutorial
3. ls -la /opt/vm-ml-tutorial/output
4. run_fraud_detection.sh
EOF
