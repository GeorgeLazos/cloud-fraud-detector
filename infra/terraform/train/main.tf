# TRAIN: TUTORIAL 1 INFRASTRUCTURE.

# Initilize TF and google provider.
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
  project_id            = data.terraform_remote_state.data.outputs.project_id
  region                = data.terraform_remote_state.data.outputs.region
  dataset_bucket_name   = data.terraform_remote_state.data.outputs.dataset_bucket_name
  dataset_object_name   = data.terraform_remote_state.data.outputs.dataset_object_name
  artifact_repo_url     = data.terraform_remote_state.data.outputs.artifact_repo_url
  service_account_email = data.terraform_remote_state.data.outputs.service_account_email
  base_image_url        = "${local.artifact_repo_url}/fraud-detection:base"
  scoring_image_url     = "${local.artifact_repo_url}/fraud-scoring:v5"
}

# Configure provider
provider "google" {
  project = local.project_id
  region  = local.region
  zone    = var.zone
}

# Confifure latest Ubuntu 22.04 LTS image from the public image family.
data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# Create custom VPC
resource "google_compute_network" "train_vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

# Create private subnet for train VM
resource "google_compute_subnetwork" "train_subnet" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr_range
  region                   = local.region
  network                  = google_compute_network.train_vpc.id
  private_ip_google_access = true
}

# Create Cloud Router
resource "google_compute_router" "train_router" {
  name    = "${var.vpc_name}-router"
  region  = local.region
  network = google_compute_network.train_vpc.id
}

# Create Cloud NAT for outbound internet access from the private subnet (for pulling base image, pushing scoring image, etc.)
resource "google_compute_router_nat" "train_nat" {
  name                               = "${var.vpc_name}-nat"
  router                             = google_compute_router.train_router.name
  region                             = local.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Allow SSH access from IAP only (no public access)
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "${var.instance_name}-allow-iap-ssh"
  network     = google_compute_network.train_vpc.name
  description = "Allow SSH from IAP only (no public 0.0.0.0/0)."

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["ssh-iap"]
}

# Create the training VM 
resource "google_compute_instance" "train_vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["ssh-iap", "fraud-train"]

  # Configure boot disk
  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 20
      type  = "pd-balanced"
    }
  }

  # Configure network interface with access to the private subnet
  network_interface {
    subnetwork = google_compute_subnetwork.train_subnet.id
  }

  # Use shared service account from the data stack with appropriate permissions for accessing GCS and Artifact Registry
  service_account {
    email  = local.service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Startup script to set up the while project (building and pushing images, training and deploying the model)
  metadata_startup_script = templatefile("${path.module}/startup.sh", {
    dockerfile_txt         = file("${path.module}/../../../docker/Dockerfile")
    dockerfile_scoring_txt = file("${path.module}/../../../docker/Dockerfile.scoring")
    dockerignore_txt       = file("${path.module}/../../../docker/.dockerignore")
    requirements_txt       = file("${path.module}/../../../requirements.txt")
    fraud_script_py        = file("${path.module}/../../../scripts/fraud_detection_pyspark.py")
    score_script_py        = file("${path.module}/../../../scripts/score_stream.py")
    publish_script_py      = file("${path.module}/../../../scripts/publish_transactions.py")
    dataset_bucket_name    = local.dataset_bucket_name
    dataset_object_name    = local.dataset_object_name
    artifact_repo_url      = local.artifact_repo_url
    base_image_url         = local.base_image_url
    scoring_image_url      = local.scoring_image_url
    region                 = local.region
  })

  labels = {
    tutorial = "fraud-train"
    course   = "cloud-hpc"
  }
}
