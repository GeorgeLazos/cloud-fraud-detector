# Project id
variable "project_id" {
  description = "Google Cloud project ID used for the tutorial deployment."
  type        = string
}

# Region
variable "region" {
  description = "Region for the tutorial resources."
  type        = string
  default     = "europe-west2"
}

#Zone
variable "zone" {
  description = "Zone for the Compute Engine instance."
  type        = string
  default     = "europe-west2-a"
}

#Instance name
variable "instance_name" {
  description = "Name of the Compute Engine instance."
  type        = string
  default     = "ml-vm-1"
}

#Machine type
variable "machine_type" {
  description = "Machine type for the VM."
  type        = string
  default     = "e2-medium"
}

#VPC name
variable "vpc_name" {
  description = "Name of the custom VPC network."
  type        = string
  default     = "fraud-detection-vpc"
}

#Subnet name
variable "subnet_name" {
  description = "Name of the public subnet used by the VM."
  type        = string
  default     = "fraud-public-subnet"
}

# Subnet CIDR range
variable "subnet_cidr_range" {
  description = "CIDR range for the custom public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

# Bucket name for dataset upload
variable "dataset_bucket_name" {
  description = "Optional custom bucket name for the fraud dataset object."
  type        = string
  default     = null
}

# Object name for the uploaded dataset
variable "dataset_object_name" {
  description = "Object name used for the uploaded fraud dataset."
  type        = string
  default     = "creditcard.csv"
}

# Service account ID for the VM
variable "vm_service_account_id" {
  description = "Service account ID attached to the VM for dataset download access."
  type        = string
  default     = "fraud-vm-sa"
}

# IP ranges allowed to connect over SSH
variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to connect over SSH."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
