#TRAIN STACK: OUTPUTS.

# Instance name
output "instance_name" {
  description = "Name of the train VM."
  value       = google_compute_instance.train_vm.name
}

# Instance zone
output "instance_zone" {
  description = "Zone of the train VM."
  value       = google_compute_instance.train_vm.zone
}

# SSH command via IAP 
output "iap_ssh_command" {
  description = "SSH command (via IAP - no public IP needed)."
  value       = "gcloud compute ssh ${google_compute_instance.train_vm.name} --zone ${google_compute_instance.train_vm.zone} --tunnel-through-iap"
}

# Scoring image URL
output "scoring_image_url" {
  description = "Fully-qualified URL of the scoring image the train VM will push to Artifact Registry."
  value       = local.scoring_image_url
}

# Log of outputs from the startup script
output "tail_startup_log_command" {
  description = "Command to tail the startup log on the train VM."
  value       = "gcloud compute ssh ${google_compute_instance.train_vm.name} --zone ${google_compute_instance.train_vm.zone} --tunnel-through-iap --command 'sudo tail -f /var/log/startup.log'"
}
