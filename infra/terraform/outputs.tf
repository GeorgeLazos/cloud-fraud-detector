# VM name
output "instance_name" {
  description = "Name of the provisioned VM."
  value       = google_compute_instance.ml_vm.name
}

# VM zone
output "instance_zone" {
  description = "Zone of the provisioned VM."
  value       = google_compute_instance.ml_vm.zone
}

# External IP address for SSH access
output "external_ip" {
  description = "Ephemeral public IP assigned to the VM."
  value       = google_compute_instance.ml_vm.network_interface[0].access_config[0].nat_ip
}

# ID of the custom VPC network created for the tutorial
output "network_id" {
  description = "ID of the custom VPC network created for the tutorial."
  value       = google_compute_network.custom_vpc.id
}

# ID of the public subnet attached to the VM
output "subnetwork_id" {
  description = "ID of the public subnet attached to the VM."
  value       = google_compute_subnetwork.public_subnet.id
}

# SSH command for the provisioned VM
output "gcloud_ssh_command" {
  description = "Convenient SSH command for the provisioned VM."
  value       = "gcloud compute ssh ${google_compute_instance.ml_vm.name} --zone ${google_compute_instance.ml_vm.zone}"
}

# Path to the tutorial directory on the VM
output "tutorial_directory" {
  description = "Location of the auto-staged tutorial files on the VM."
  value       = "/opt/vm-ml-tutorial"
}

# Dataset path
output "dataset_target_path" {
  description = "Path where creditcard.csv is downloaded automatically on the VM."
  value       = "/opt/vm-ml-tutorial/data/creditcard.csv"
}

# Bucket name used for the automated dataset upload
output "dataset_bucket_name" {
  description = "Name of the GCS bucket used to stage the fraud dataset."
  value       = google_storage_bucket.dataset.name
}

# Command to rerun the containerized fraud detection workload after the automatic setup.
output "run_fraud_detection_command" {
  description = "Command to rerun the containerized fraud detection workload after the automatic setup."
  value       = "run_fraud_detection.sh"
}
