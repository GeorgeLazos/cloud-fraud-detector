# STREAM STACK - INFRASTRUCTURE FOR THE STREAMING COMPONENT OF THE TUTORIAL

# Initialize TF and google provider.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Create a data source to read outputs from the data stack's terraform state file.
data "terraform_remote_state" "data" {
  backend = "local"
  config = {
    path = "${path.module}/../data/terraform.tfstate"
  }
}

# Create shorter local variables for easier access to the data stack outputs.
locals {
  project_id                = data.terraform_remote_state.data.outputs.project_id
  region                    = data.terraform_remote_state.data.outputs.region
  dataset_bucket_name       = data.terraform_remote_state.data.outputs.dataset_bucket_name
  stream_subset_object_name = data.terraform_remote_state.data.outputs.stream_subset_object_name
  artifact_repo_url         = data.terraform_remote_state.data.outputs.artifact_repo_url
  service_account_email     = data.terraform_remote_state.data.outputs.service_account_email
  scoring_image_url         = "${local.artifact_repo_url}/fraud-scoring:v4"
}

# Configure provider
provider "google" {
  project = local.project_id
  region  = local.region
  zone    = var.zone
}

# Configure latest Ubuntu 22.04 LTS image from the public image family.
data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# Create custom VPC
resource "google_compute_network" "stream_vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

# Create private subnet for stream VM
resource "google_compute_subnetwork" "stream_subnet" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr_range
  region                   = local.region
  network                  = google_compute_network.stream_vpc.id
  private_ip_google_access = true
}

# Create Cloud Router
resource "google_compute_router" "stream_router" {
  name    = "${var.vpc_name}-router"
  region  = local.region
  network = google_compute_network.stream_vpc.id
}

# Create Cloud NAT for outbound internet access from the stream VM without a public IP.
resource "google_compute_router_nat" "stream_nat" {
  name                               = "${var.vpc_name}-nat"
  router                             = google_compute_router.stream_router.name
  region                             = local.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Allow SSH access from IAP only (no public access)
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "${var.instance_name}-allow-iap-ssh"
  network     = google_compute_network.stream_vpc.name
  description = "Allow SSH from IAP only."

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["ssh-iap"]
}

# Create a pub/sub topic 
resource "google_pubsub_topic" "transactions" {
  name = var.pubsub_topic_id

  labels = {
    tutorial = "fraud-stream"
    course   = "cloud-hpc"
  }
}

# Create pub/sub subscription for the topic
resource "google_pubsub_subscription" "transactions_sub" {
  name  = var.pubsub_subscription_id
  topic = google_pubsub_topic.transactions.name

  ack_deadline_seconds = 60
 
  expiration_policy {
    ttl = "" 
  }

  labels = {
    tutorial = "fraud-stream"
    course   = "cloud-hpc"
  }
}

# Create stream VM with access to the private subnet and the service account for pulling the scoring image and publishing to Pub/Sub.
resource "google_compute_instance" "stream_vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["ssh-iap", "fraud-stream"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 20
      type  = "pd-balanced"
    }
  }

  # Connect the VM to the private subnet (no public IP)
  network_interface {
    subnetwork = google_compute_subnetwork.stream_subnet.id
  }

  # Grant the VM's service account permissions to pull the scoring image and publish to Pub/Sub.
  service_account {
    email  = local.service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Startup script
  metadata_startup_script = templatefile("${path.module}/startup.sh", {
    publish_script_py         = file("${path.module}/../../../scripts/publish_transactions.py")
    dataset_bucket_name       = local.dataset_bucket_name
    stream_subset_object_name = local.stream_subset_object_name
    scoring_image_url         = local.scoring_image_url
    region                    = local.region
    project_id                = local.project_id
    pubsub_topic_id           = google_pubsub_topic.transactions.name
    pubsub_subscription_id    = google_pubsub_subscription.transactions_sub.name
  })

  labels = {
    tutorial = "fraud-stream"
    course   = "cloud-hpc"
  }

  # Ensure the VM is created after the Pub/Sub subscription to avoid startup script errors.
  depends_on = [
    google_pubsub_subscription.transactions_sub,
  ]
}
