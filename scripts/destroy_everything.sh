#!/usr/bin/env bash

# ONE-COMMAND TEARDOWN OF ALL THREE STACKS IN THE CORRECT ORDER.
# DESTROYS stream -> train -> data SO REMOTE-STATE DEPENDENCIES UNWIND CLEANLY.
# AFTER THIS RUNS SUCCESSFULLY, ZERO FRAUD-DETECTION RESOURCES REMAIN IN GCP.

set -uo pipefail

#Get  path to repo root and terraform directories
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_ROOT="$REPO_ROOT/infra/terraform"

# Destroy stream stack
echo "=== Destroying stream stack ==="
if [ -d "$TF_ROOT/stream/.terraform" ]; then
  (cd "$TF_ROOT/stream" && terraform destroy -auto-approve) || echo "stream destroy reported issues - continuing"
else
  echo "stream stack never initialised - skipping"
fi

# Destroy train stack
echo "=== Destroying train stack ==="
if [ -d "$TF_ROOT/train/.terraform" ]; then
  (cd "$TF_ROOT/train" && terraform destroy -auto-approve) || echo "train destroy reported issues - continuing"
else
  echo "train stack never initialised - skipping"
fi

# Destroy data stack
echo "=== Destroying data stack (this removes the bucket + registry) ==="
if [ -d "$TF_ROOT/data/.terraform" ]; then
  (cd "$TF_ROOT/data" && terraform destroy -auto-approve)
else
  echo "data stack never initialised - skipping"
fi

# Verify no resources remain
echo
echo "=== VERIFICATION ==="
echo "If the next three commands print no fraud-detection resources, teardown succeeded."
echo
echo "VMs:"
gcloud compute instances list --filter="name~fraud" 2>&1 || true
echo
echo "Buckets:"
gcloud storage buckets list --filter="name~fraud-detection" 2>&1 || true
echo
echo "Artifact Registry repos:"
gcloud artifacts repositories list --filter="name~fraud-detection" 2>&1 || true
echo
echo "Pub/Sub topics:"
gcloud pubsub topics list --filter="name~fraud" 2>&1 || true
