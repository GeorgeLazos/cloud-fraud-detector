# Derive a bucket name for the automated fraud dataset upload
locals {
  dataset_bucket_name = var.dataset_bucket_name != null ? var.dataset_bucket_name : "${var.project_id}-fraud-dataset"
}

# Create a GCS bucket to hold the fraud dataset for automated VM downloads
resource "google_storage_bucket" "dataset" {
  name                        = local.dataset_bucket_name
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  labels = {
    tutorial = "fraud-dataset"
    course   = "cloud-hpc"
  }
}

# Upload the local credit card fraud dataset into the GCS bucket
resource "google_storage_bucket_object" "creditcard_dataset" {
  name   = var.dataset_object_name
  bucket = google_storage_bucket.dataset.name
  source = "${path.module}/../../data/creditcard.csv"
}
