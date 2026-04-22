# Create a VM service account that can read the dataset bucket
resource "google_service_account" "vm_dataset_reader" {
  account_id   = var.vm_service_account_id
  display_name = "Fraud Detection VM Dataset Reader"
}

# Grant the VM service account read access to the dataset bucket
resource "google_storage_bucket_iam_member" "dataset_reader" {
  bucket = google_storage_bucket.dataset.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.vm_dataset_reader.email}"
}
