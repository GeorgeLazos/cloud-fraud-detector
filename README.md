# Cloud Fraud Detection — Train and Deploy on GCP

Three-notebook PySpark fraud-detection portfolio deployed on Google Cloud with Terraform, Docker, and Pub/Sub.

[tutorial_1.ipynb](tutorial_1.ipynb) introduces the problem, walks through the shared **data stack** (bucket, registry, service account), and sets up prerequisites (`gcloud`, Terraform, tfvars).

[tutorial_2.ipynb](tutorial_2.ipynb) applies the **train stack** — a private VM that builds the base image, runs PySpark training, layers the trained `PipelineModel` into `fraud-scoring:v5`, and pushes it to Artifact Registry. Includes the vulnerability scan and output-inspection commands.

[tutorial_3.ipynb](tutorial_3.ipynb) applies the **stream stack** — a private VM that pulls `fraud-scoring:v5`, publishes CSV rows to a Pub/Sub topic, runs a pull-loop consumer that scores each batch through the saved Spark model, writes a fraud report to GCS, and tears everything down to zero cloud state.

## Architecture in one paragraph

Three Terraform stacks share one bucket and one private container registry. 

The **data stack** creates the bucket (with the dataset uploaded) and the Artifact Registry repository — these are the only resources that survive between tutorials. 

The **train stack** spins up a private VM with Cloud NAT and IAP access, builds a Docker base image, runs PySpark training inside it, then layers the trained `PipelineModel` into a derived `fraud-scoring:v5` image and pushes it to the registry. 

The **stream stack** spins up a separate private VM, pulls `fraud-scoring:v5`, runs a Python publisher that replays test transactions to a Pub/Sub topic, and runs a Python pull-loop consumer that scores each batch through the saved Spark model and writes a fraud report.

## What lives where

```
Tutorial1/
├── data/creditcard.csv             source dataset (uploaded to GCS by data stack)
├── docker/
│   ├── Dockerfile                  base image: PySpark + scripts (no model)
│   └── Dockerfile.scoring          derived image: base + trained model
├── scripts/
│   ├── fraud_detection_pyspark.py  training (saves PipelineModel)
│   ├── publish_transactions.py     T2 publisher: CSV → Pub/Sub
│   ├── score_stream.py             T2 consumer: Pub/Sub → Spark model → report
│   └── destroy_everything.sh       single-command teardown of all 3 stacks
├── infra/terraform/
│   ├── data/                       bucket + registry + service account + IAM
│   │   └── terraform.tfvars.example  copy to terraform.tfvars and fill in project_id
│   ├── train/                      VPC + private subnet + NAT + IAP + train VM
│   │   └── terraform.tfvars.example  copy to terraform.tfvars and fill in project_id
│   └── stream/                     VPC + private subnet + NAT + IAP + stream VM + Pub/Sub
│       └── terraform.tfvars.example  copy to terraform.tfvars and fill in project_id
├── tutorial_1.ipynb                walkthrough part 1: problem + data stack + prereqs
├── tutorial_2.ipynb                walkthrough part 2: train stack + scoring image
├── tutorial_3.ipynb                walkthrough part 3: stream stack + teardown
└── requirements.txt                Python deps (PySpark + google-cloud-* clients)
```

## End-to-end lifecycle

```
1. cd infra/terraform/data   && terraform init && terraform apply   # bucket + registry + SA
2. cd ../train               && terraform init && terraform apply   # train VM trains model and pushes scoring image
3. cd ../train               && terraform destroy                    # train compute gone, registry image stays
4. cd ../stream              && terraform init && terraform apply   # stream VM pulls image, scores Pub/Sub, writes report
5. cd ../stream              && terraform destroy                    # stream compute gone
6. cd ../data                && terraform destroy                    # bucket + registry gone — zero cloud state
```

Or run `scripts/destroy_everything.sh` or `scripts/destroy_everything.ps1` once at the end to do steps 3+5+6 in one go and verify nothing remains.

## Inspecting each phase

```bash
# After step 2 — watch training/build/push complete
gcloud compute ssh fraud-train-vm --zone europe-west2-a --tunnel-through-iap \
  --command 'sudo tail -f /var/log/startup.log'

# Verify scoring image landed in the registry
gcloud artifacts docker images list \
  europe-west2-docker.pkg.dev/<project_id>/fraud-detection-images

# Pretty-print training metrics from GCS (AUC-ROC, AUC-PR, confusion matrix)
gcloud storage cat gs://<bucket>/summaries/summary.json | jq

# List vulnerability findings from Container Analysis for the scoring image
gcloud artifacts docker images list \
  europe-west2-docker.pkg.dev/<project_id>/fraud-detection-images/fraud-scoring \
  --show-occurrences --occurrence-filter='kind="VULNERABILITY"'

# Confirm the scoring image is tagged correctly and check size
gcloud artifacts docker images describe \
  europe-west2-docker.pkg.dev/<project_id>/fraud-detection-images/fraud-scoring:v5

# After step 4 — watch streaming inference and the fraud report
gcloud compute ssh fraud-stream-vm --zone europe-west2-a --tunnel-through-iap \
  --command 'sudo tail -f /var/log/startup.log'

# Pretty-print the fraud report from GCS (no SSH needed)
gcloud storage cat gs://<bucket>/reports/fraud_report.json | jq

# Count fraudulent transactions flagged
gcloud storage cat gs://<bucket>/reports/fraud_report.json | jq '.frauds_flagged_count'

# See just the unique frauds (deduped on Time, since Pub/Sub may redeliver)
gcloud storage cat gs://<bucket>/reports/fraud_report.json | jq '[.frauds[] | {Time, Amount, prediction}] | unique_by(.Time)'

# List everything in the bucket (dataset, summary, report all in one place)
gcloud storage ls -r gs://<bucket>/

# Check the consumer container is alive on the VM (debug only)
gcloud compute ssh fraud-stream-vm --zone europe-west2-a --tunnel-through-iap \
  --command 'sudo docker ps -a && sudo docker logs fraud-scoring | tail -50'

# Cross-phase — quick "what's deployed?" check
gcloud compute instances list --filter="labels.course=cloud-hpc"
gcloud pubsub topics list --filter="labels.course=cloud-hpc"
```

## Vulnerability scanning

Container Analysis (`containerscanning.googleapis.com`) can scan images in Artifact Registry on demand. After `fraud-scoring:v5` was pushed, the command below was run once and returned 2 CRITICAL, 32 HIGH, 35 MEDIUM, 28 LOW and 26 MINIMAL findings — all inherited from the `python:3.12-slim` base.

```bash
# List the findings
gcloud artifacts docker images list \
  europe-west2-docker.pkg.dev/<project_id>/fraud-detection-images/fraud-scoring \
  --show-occurrences --occurrence-filter='kind="VULNERABILITY"'
```
