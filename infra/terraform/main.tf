# Set up the Terraform and provider configuration
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Fetch the latest Ubuntu 22.04 LTS image from the public image family
data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# Create a custom VPC network
resource "google_compute_network" "custom_vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

#Creates a public subnet in the custom VPC
resource "google_compute_subnetwork" "public_subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr_range
  region        = var.region
  network       = google_compute_network.custom_vpc.id
}
#Create a firewall rule to allow SSH access to the VM
resource "google_compute_firewall" "allow_ssh" {
  name        = "${var.instance_name}-allow-ssh"
  network     = google_compute_network.custom_vpc.name
  description = "Allow SSH access to the tutorial VM. Restrict the source range in real deployments."

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["ssh-enabled"]
}

# Main resource: Create a Compute Engine VM instance with the specified machine type and boot disk image.
resource "google_compute_instance" "ml_vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["ssh-enabled", "terraform-tutorial"]

  # Configure the boot disk with the Ubuntu image and specify the size and type of the disk.
  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 20
      type  = "pd-balanced"
    }
  }

  #Connect the VM to the public subnet and assign an external IP address for SSH access.
  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.id

    access_config {}
  }

  # Attach a service account so the VM can download the dataset from GCS
  service_account {
    email  = google_service_account.vm_dataset_reader.email
    scopes = ["https://www.googleapis.com/auth/devstorage.read_only"]
  }

  #When the VM starts, it will execute the startup script
  metadata_startup_script = templatefile("${path.module}/startup.sh", {
    dockerfile_txt      = file("${path.module}/../../docker/Dockerfile")
    dockerignore_txt    = file("${path.module}/../../docker/.dockerignore")
    requirements_txt    = file("${path.module}/../../requirements.txt")
    fraud_script_py     = file("${path.module}/../../scripts/fraud_detection_pyspark.py")
    dataset_bucket_name = google_storage_bucket.dataset.name
    dataset_object_name = google_storage_bucket_object.creditcard_dataset.name
  })

  #Labels for organization
  labels = {
    tutorial = "terraform-vm-ml"
    course   = "cloud-hpc"
  }

  # Wait for the dataset object and IAM grant before bootstrapping the VM
  depends_on = [
    google_storage_bucket_object.creditcard_dataset,
    google_storage_bucket_iam_member.dataset_reader,
  ]
}
