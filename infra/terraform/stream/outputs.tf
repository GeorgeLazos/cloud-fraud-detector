# STREAM STACK: OUTPUTS.

# Instance name
output "instance_name" {
  description = "Name of the stream VM."
  value       = google_compute_instance.stream_vm.name
}

# Instance zone
output "instance_zone" {
  description = "Zone of the stream VM."
  value       = google_compute_instance.stream_vm.zone
}

# Command to SSH into the stream VM via IAP (no public IP).
output "iap_ssh_command" {
  description = "SSH command via IAP."
  value       = "gcloud compute ssh ${google_compute_instance.stream_vm.name} --zone ${google_compute_instance.stream_vm.zone} --tunnel-through-iap"
}

# Command to tail the startup log on the stream VM (useful for debugging).
output "tail_startup_log_command" {
  description = "Command to tail the streaming log."
  value       = "gcloud compute ssh ${google_compute_instance.stream_vm.name} --zone ${google_compute_instance.stream_vm.zone} --tunnel-through-iap --command 'sudo tail -f /var/log/startup.log'"
}

# Path on the VM where the stream consumer writes the final fraud report.
output "report_path_on_vm" {
  description = "Where the stream consumer writes the final fraud report."
  value       = "/opt/fraud-stream/output/fraud_report.json"
}

# Pub/Sub topic
output "pubsub_topic" {
  description = "Pub/Sub topic ID."
  value       = google_pubsub_topic.transactions.name
}

# Pub/Sub subscription
output "pubsub_subscription" {
  description = "Pub/Sub subscription ID."
  value       = google_pubsub_subscription.transactions_sub.name
}
