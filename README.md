# Cloud Fraud Detection — Train and Deploy on GCP

Two-tutorial PySpark fraud-detection portfolio deployed on Google Cloud with Terraform, Docker, and Pub/Sub. Tutorial 1 trains a model on the cloud and pushes a versioned scoring image to Artifact Registry. Tutorial 2 spins up a private VM that pulls that image and scores a Pub/Sub stream of transactions, producing a fraud report. Final teardown leaves zero cloud state.

## Architecture in one paragraph

Three Terraform stacks share one bucket and one private container registry. The **data stack** creates the bucket (with the dataset uploaded) and the Artifact Registry repository — these are the only resources that survive between tutorials. The **train stack** spins up a private VM with Cloud NAT and IAP access (Doc 1 defence-in-depth), builds a Docker base image, runs PySpark training inside it (Doc 4), then layers the trained `PipelineModel` into a derived `fraud-scoring:v1` image and pushes it to the registry (Doc 2). The **stream stack** spins up a separate private VM, pulls `fraud-scoring:v1`, runs a Python publisher that replays test transactions to a Pub/Sub topic, and runs a Python pull-loop consumer that scores each batch through the saved Spark model and writes a fraud report.

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
│   ├── train/                      VPC + private subnet + NAT + IAP + train VM
│   └── stream/                     VPC + private subnet + NAT + IAP + stream VM + Pub/Sub
├── tutorial.ipynb                  notebook walkthrough (legacy, will be split)
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

Or run `scripts/destroy_everything.sh` once at the end to do steps 3+5+6 in one go and verify nothing remains.

## Inspecting each phase

```bash
# After step 2 — watch training/build/push complete
gcloud compute ssh fraud-train-vm --zone europe-west2-a --tunnel-through-iap \
  --command 'sudo tail -f /var/log/startup.log'

# Verify scoring image landed in the registry
gcloud artifacts docker images list \
  europe-west2-docker.pkg.dev/<project_id>/fraud-detection-images

# After step 4 — watch streaming inference and the fraud report
gcloud compute ssh fraud-stream-vm --zone europe-west2-a --tunnel-through-iap \
  --command 'sudo tail -f /var/log/startup.log'
```

## Mapping to lecture content

| Component | Slide reference |
|---|---|
| GCS bucket, Pub/Sub topic + subscription | Doc 1 (Cloud foundations) |
| Private subnet, Private Google Access, Cloud NAT, IAP-only SSH | Doc 1 (defence in depth) |
| Docker base + derived scoring image, Artifact Registry | Doc 2 (containers + private registries) |
| Three independent Terraform stacks reading via remote state | Doc 3 (modules + state separation) |
| PySpark training (`PipelineModel.save`) and inference (`PipelineModel.load`) | Doc 4 (PySpark) |

## Cost

A full apply→destroy run costs about 10p (two e2-medium VMs running ~5 minutes each, Pub/Sub pennies, bucket and registry essentially free at this size). The bucket has a 7-day object lifecycle rule as a backstop in case `terraform destroy` is forgotten.

## Cleanup

```bash
./scripts/destroy_everything.sh
```

This destroys all three stacks in dependency order (stream → train → data) and prints verification commands so you can confirm nothing fraud-detection remains in the project.
