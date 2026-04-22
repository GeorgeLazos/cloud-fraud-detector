# DATA STACK: VARIABLES FOR SHARED RESOURCES.

# project_id
variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

# region
variable "region" {
  description = "Region for the bucket and the Artifact Registry repository."
  type        = string
  default     = "europe-west2"
}

# Dataset bucket name
variable "dataset_bucket_name" {
  description = "Optional explicit bucket name. Defaults to <project_id>-fraud-dataset."
  type        = string
  default     = null
}

# Dataset object name
variable "dataset_object_name" {
  description = "Object name used for the uploaded fraud dataset."
  type        = string
  default     = "creditcard.csv"
}

# Stream subset object name
variable "stream_subset_object_name" {
  description = "Object name used for the pre-baked streaming subset CSV."
  type        = string
  default     = "transactions_stream.csv"
}

# Artifact Registry repository ID
variable "artifact_repo_id" {
  description = "Artifact Registry repository ID for fraud detection images."
  type        = string
  default     = "fraud-detection-images"
}

# Service account ID for the shared SA used by both VMs.
variable "vm_service_account_id" {
  description = "Service account ID shared by train and stream VMs."
  type        = string
  default     = "fraud-vm-sa"
}
