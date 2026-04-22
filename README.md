# Reproducible Machine Learning Deployment on GCP with Terraform and Docker

This repository contains a PySpark credit card fraud detection notebook and a matching cloud deployment prototype. The notebook in `tutorial.ipynb` is the main file, while Terraform and Docker are used to provision a VM inside a custom GCP VPC and run the same fraud workflow on Google Cloud.

## What lives where

- `tutorial.ipynb` is the main submission artefact and contains the PySpark fraud-detection walkthrough.
- `scripts/fraud_detection_pyspark.py` is the script version of the notebook workflow used for deployment.
- `docker/` contains the container packaging files for the fraud prototype.
- `infra/terraform/` contains the infrastructure code that provisions a custom VPC, subnet, firewall rule, GCS dataset bucket, and the VM bootstrap process.
- `data/creditcard.csv` is the source dataset used locally and uploaded automatically to GCS during `terraform apply`.

## Terraform workflow

From the repository root:

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

## What happens after `terraform apply`

Terraform creates a custom-mode VPC, a regional subnet, an SSH firewall rule, a GCS bucket/object for `creditcard.csv`, and the VM. It then passes a startup script to the VM. That startup script:

- installs Docker on the Ubuntu VM
- writes `docker/Dockerfile`, `.dockerignore`, `requirements.txt`, and `scripts/fraud_detection_pyspark.py` to `/opt/vm-ml-tutorial`
- downloads `creditcard.csv` automatically into `/opt/vm-ml-tutorial/data`
- prepares `/opt/vm-ml-tutorial/output` for results
- runs the fraud workload automatically once after the dataset download completes

## After provisioning

Connect to the VM with the Terraform output:

```bash
cd infra/terraform
terraform output -raw gcloud_ssh_command
```

Then connect to the VM and inspect the automated run:

```bash
cat /opt/vm-ml-tutorial/startup.log
ls -la /opt/vm-ml-tutorial
ls -la /opt/vm-ml-tutorial/output
run_fraud_detection.sh
```

The first container run happens automatically during provisioning, and reruns write a JSON summary and sample predictions into `/opt/vm-ml-tutorial/output`.

## Clean up

When finished, destroy the infrastructure:

```bash
cd infra/terraform
terraform destroy
```

## Notes

- `terraform destroy` is intentionally left manual because teardown is destructive and should remain an explicit decision.
