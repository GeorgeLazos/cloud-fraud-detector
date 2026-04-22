# DATA: SHARED, LONG-LIVED RESOURCES USED BY BOTH TRAIN AND STREAM STACKS.

#Define the required Terraform version and providers.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

#Configure provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Define bucket name as local variable
locals {
  dataset_bucket_name = var.dataset_bucket_name != null ? var.dataset_bucket_name : "${var.project_id}-fraud-dataset"
}

# Create a shared GCS bucket to hold the dataset and any output reports.
resource "google_storage_bucket" "dataset" {
  name                        = local.dataset_bucket_name
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  # Rule to auto-delete objects after 7 days, keeping the bucket tidy and cost low after the demo.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7
    }
  }

  labels = {
    tutorial = "fraud-dataset"
    course   = "cloud-hpc"
  }
}

# Upload the full credit card dataset CSV to the bucket.
resource "google_storage_bucket_object" "creditcard_dataset" {
  name   = var.dataset_object_name
  bucket = google_storage_bucket.dataset.name
  source = "${path.module}/../../../data/creditcard.csv"
}

# Upload the streaming subset (simulated for demonstration) CSV to the bucket.
resource "google_storage_bucket_object" "stream_subset" {
  name   = var.stream_subset_object_name
  bucket = google_storage_bucket.dataset.name
  source = "${path.module}/../../../data/transactions_stream.csv"
}

# Create a private Docker registry inside project
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = var.artifact_repo_id
  description   = "Fraud detection container images (base + scoring)."
  format        = "DOCKER"

  labels = {
    tutorial = "fraud-images"
    course   = "cloud-hpc"
  }
}

# Service account used by both VMs to access the dataset bucket, push/pull images, and interact with Pub/Sub.
resource "google_service_account" "fraud_vm_sa" {
  account_id   = var.vm_service_account_id
  display_name = "Fraud Detection VM (shared, used by train and stream)"
}

# Bucket-scoped IAM: SA gets full object-level control (read/write/delete) on this bucket only.
# Needed for: train VM downloads CSV + uploads summary.json; stream VM uploads fraud_report.json.
resource "google_storage_bucket_iam_member" "dataset_admin" {
  bucket = google_storage_bucket.dataset.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.fraud_vm_sa.email}"
}

# Create IAM binding to allow the SA to push/pull images from the Artifact Registry repository.
resource "google_artifact_registry_repository_iam_member" "image_writer" {
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.fraud_vm_sa.email}"
}

# Grant the SA Pub/Sub Publisher role at the project level 
resource "google_project_iam_member" "pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.fraud_vm_sa.email}"
}

# Grant the SA Pub/Sub Subscriber role at the project level.
resource "google_project_iam_member" "pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.fraud_vm_sa.email}"
}
