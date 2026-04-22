# DATA STACK: OUTPUTS CONSUMED BY THE TRAIN AND STREAM STACKS VIA REMOTE STATE.

# Project_id 
output "project_id" {
  description = "Pass-through of the GCP project ID."
  value       = var.project_id
}

# Region
output "region" {
  description = "Pass-through of the region."
  value       = var.region
}

# Dataset bucket name
output "dataset_bucket_name" {
  description = "Name of the GCS bucket holding the dataset."
  value       = google_storage_bucket.dataset.name
}

# Dataset object name
output "dataset_object_name" {
  description = "Object key of the uploaded dataset."
  value       = google_storage_bucket_object.creditcard_dataset.name
}

# Stream subset object name
output "stream_subset_object_name" {
  description = "Object key of the pre-baked streaming subset CSV."
  value       = google_storage_bucket_object.stream_subset.name
}

# Artifact Registry repository ID
output "artifact_repo_id" {
  description = "Artifact Registry repository ID."
  value       = google_artifact_registry_repository.images.repository_id
}

# Artifact registry repository URL
output "artifact_repo_url" {
  description = "Fully-qualified registry URL prefix used for image push and pull."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

# Service account email
output "service_account_email" {
  description = "Email of the shared service account used by train and stream VMs."
  value       = google_service_account.fraud_vm_sa.email
}
