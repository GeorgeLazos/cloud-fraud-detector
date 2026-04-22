# TRAIN STACK: VARIABLES.

# Zone
variable "zone" {
  description = "Compute zone for the train VM."
  type        = string
  default     = "europe-west2-a"
}

# Instance name
variable "instance_name" {
  description = "Name of the train VM."
  type        = string
  default     = "fraud-train-vm"
}

# Machine type
variable "machine_type" {
  description = "Machine type for the train VM."
  type        = string
  default     = "e2-medium"
}

# VPC name
variable "vpc_name" {
  description = "Name of the VPC for the train stack."
  type        = string
  default     = "fraud-train-vpc"
}

# Subnet name
variable "subnet_name" {
  description = "Name of the private train subnet."
  type        = string
  default     = "fraud-train-subnet"
}

# Subnet CIDR range
variable "subnet_cidr_range" {
  description = "CIDR range for the train subnet."
  type        = string
  default     = "10.10.0.0/24"
}
