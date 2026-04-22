# NEW (STREAM STACK): VARIABLES.

variable "zone" {
  description = "Compute zone for the stream VM."
  type        = string
  default     = "europe-west2-a"
}

variable "instance_name" {
  description = "Name of the stream VM."
  type        = string
  default     = "fraud-stream-vm"
}

variable "machine_type" {
  description = "Machine type for the stream VM."
  type        = string
  default     = "e2-medium"
}

variable "vpc_name" {
  description = "Name of the VPC for the stream stack."
  type        = string
  default     = "fraud-stream-vpc"
}

variable "subnet_name" {
  description = "Name of the private stream subnet."
  type        = string
  default     = "fraud-stream-subnet"
}

variable "subnet_cidr_range" {
  description = "CIDR range for the stream subnet (must not overlap train subnet)."
  type        = string
  default     = "10.20.0.0/24"
}

variable "pubsub_topic_id" {
  description = "Pub/Sub topic ID for the transaction stream."
  type        = string
  default     = "fraud-transactions"
}

variable "pubsub_subscription_id" {
  description = "Pub/Sub subscription ID consumed by the stream VM."
  type        = string
  default     = "fraud-transactions-sub"
}
