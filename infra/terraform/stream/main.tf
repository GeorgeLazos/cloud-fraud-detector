# NEW STACK (STREAM): TUTORIAL 2 INFRASTRUCTURE.
# DOC 1: PRIVATE SUBNET + PGA + NAT + IAP (SAME DEFENCE-IN-DEPTH PATTERN AS TRAIN STACK).
# DOC 1: PUB/SUB TOPIC + SUBSCRIPTION FOR THE TRANSACTION STREAM.
# DOC 2: VM PULLS THE PRE-BUILT SCORING IMAGE FROM ARTIFACT REGISTRY (NO REBUILD).
# DOC 4: PIPELINEMODEL LOADED INSIDE THE CONTAINER PROCESSES STREAMED MESSAGES.
# DOC 3: READS BUCKET / REGISTRY / SA FROM THE DATA STACK VIA REMOTE STATE.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# DOC 3: REUSE THE DATA STACK'S OUTPUTS - SAME PATTERN AS THE TRAIN STACK
data "terraform_remote_state" "data" {
  backend = "local"
  config = {
    path = "${path.module}/../data/terraform.tfstate"
  }
}

locals {
  project_id                = data.terraform_remote_state.data.outputs.project_id
  region                    = data.terraform_remote_state.data.outputs.region
  dataset_bucket_name       = data.terraform_remote_state.data.outputs.dataset_bucket_name
  stream_subset_object_name = data.terraform_remote_state.data.outputs.stream_subset_object_name
  artifact_repo_url         = data.terraform_remote_state.data.outputs.artifact_repo_url
  service_account_email     = data.terraform_remote_state.data.outputs.service_account_email
  scoring_image_url         = "${local.artifact_repo_url}/fraud-scoring:v3"
}

provider "google" {
  project = local.project_id
  region  = local.region
  zone    = var.zone
}

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# DOC 1: SECOND CUSTOM VPC - ISOLATED FROM THE TRAIN STACK'S NETWORK
resource "google_compute_network" "stream_vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "stream_subnet" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr_range
  region                   = local.region
  network                  = google_compute_network.stream_vpc.id
  private_ip_google_access = true
}

resource "google_compute_router" "stream_router" {
  name    = "${var.vpc_name}-router"
  region  = local.region
  network = google_compute_network.stream_vpc.id
}

resource "google_compute_router_nat" "stream_nat" {
  name                               = "${var.vpc_name}-nat"
  router                             = google_compute_router.stream_router.name
  region                             = local.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

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

# DOC 1: PUB/SUB TOPIC - THE TRANSACTION STREAM
resource "google_pubsub_topic" "transactions" {
  name = var.pubsub_topic_id

  labels = {
    tutorial = "fraud-stream"
    course   = "cloud-hpc"
  }
}

# DOC 1: PULL SUBSCRIPTION - THE STREAM CONSUMER PULLS MESSAGES FROM HERE
resource "google_pubsub_subscription" "transactions_sub" {
  name  = var.pubsub_subscription_id
  topic = google_pubsub_topic.transactions.name

  # ACK DEADLINE GIVES THE CONSUMER 60s TO PROCESS A MESSAGE BEFORE IT IS REDELIVERED
  ack_deadline_seconds = 60

  # MESSAGE_RETENTION_DURATION DEFAULTS TO 7 DAYS - LIFECYCLE DELETION OF THIS SUB AT destroy IS THE CLEANUP
  expiration_policy {
    ttl = "" # NEVER EXPIRE WHILE THE STACK IS UP - GETS DESTROYED EXPLICITLY BY terraform destroy
  }

  labels = {
    tutorial = "fraud-stream"
    course   = "cloud-hpc"
  }
}

# DOC 1 + DOC 2: STREAM VM - PRIVATE, NO PUBLIC IP, RUNS DOCKER + PUBLISHER
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

  network_interface {
    subnetwork = google_compute_subnetwork.stream_subnet.id
  }

  service_account {
    email  = local.service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

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

  depends_on = [
    google_pubsub_subscription.transactions_sub,
  ]
}
