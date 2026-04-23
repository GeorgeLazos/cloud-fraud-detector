# STREAM STACK: VARIABLES.

# Zone for the stream VM.
variable "zone" {
  description = "Compute zone for the stream VM."
  type        = string
  default     = "europe-west2-a"
}

# Name of the stream VM.
variable "instance_name" {
  description = "Name of the stream VM."
  type        = string
  default     = "fraud-stream-vm"
}

# Machine type for the stream VM.
variable "machine_type" {
  description = "Machine type for the stream VM."
  type        = string
  default     = "e2-medium"
}

# Name of the VPC for the stream stack.
variable "vpc_name" {
  description = "Name of the VPC for the stream stack."
  type        = string
  default     = "fraud-stream-vpc"
}

# Name of the private subnet 
variable "subnet_name" {
  description = "Name of the private stream subnet."
  type        = string
  default     = "fraud-stream-subnet"
}

# CIDR range for the private subnet (must not overlap with train subnet).
variable "subnet_cidr_range" {
  description = "CIDR range for the stream subnet (must not overlap train subnet)."
  type        = string
  default     = "10.20.0.0/24"
}

# Pub/Sub topic ID for the transaction stream.
variable "pubsub_topic_id" {
  description = "Pub/Sub topic ID for the transaction stream."
  type        = string
  default     = "fraud-transactions"
}

# Pub/Sub subscription ID consumed by the stream VM.
variable "pubsub_subscription_id" {
  description = "Pub/Sub subscription ID consumed by the stream VM."
  type        = string
  default     = "fraud-transactions-sub"
}
