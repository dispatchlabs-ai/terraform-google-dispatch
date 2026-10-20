locals {
  backend_service_account = "${var.release_name}-backend"
}

terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.7" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# The project and protected state backend already exist. These API registrations
# contain no credentials and are retained if this example is removed.
resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com", "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com", "container.googleapis.com", "dns.googleapis.com",
    "iam.googleapis.com", "iamcredentials.googleapis.com",
    "servicenetworking.googleapis.com", "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "foundation" {
  source = "../.."

  project_id             = var.project_id
  name                   = var.name
  region                 = var.region
  zone                   = var.zone
  node_version           = var.initial_kubernetes_version
  network_cidrs          = var.network_cidrs
  api_access_cidrs       = var.api_access_cidrs
  maintenance_start_time = var.maintenance_start_time
  maintenance_exclusions = var.maintenance_exclusions
  labels                 = var.labels
  depends_on             = [google_project_service.required]
}

# The shared-CA certificate hostname is not an automatically resolvable PSA
# endpoint. Its private zone and A record are necessary for verify-full TLS.
resource "google_dns_managed_zone" "postgres" {
  project     = var.project_id
  name        = "${var.name}-postgres"
  dns_name    = module.foundation.distributed_postgres.hostname
  description = "Verified private Cloud SQL endpoint for Dispatch"
  visibility  = "private"
  private_visibility_config {
    networks { network_url = module.foundation.network_id }
  }
}

resource "google_dns_record_set" "postgres" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.postgres.name
  name         = google_dns_managed_zone.postgres.dns_name
  type         = "A"
  ttl          = 60
  rrdatas      = [module.foundation.distributed_postgres.private_ip]
}

# Cloud Storage encrypts objects with Google-managed keys by default. Retain
# current/noncurrent versions; expiration needs a coordinated restore policy.
resource "google_storage_bucket" "artifacts" {
  project                     = var.project_id
  name                        = var.artifacts_bucket
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = var.labels
  versioning { enabled = true }
  soft_delete_policy { retention_duration_seconds = 604800 }
  lifecycle { prevent_destroy = true }
  depends_on = [google_project_service.required]
}

resource "google_service_account" "backend" {
  project      = var.project_id
  account_id   = "${var.name}-backend"
  display_name = "Dispatch backend artifact identity"
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_custom_role" "artifacts" {
  project     = var.project_id
  role_id     = "${replace(var.name, "-", "_")}_artifact_read_create"
  title       = "Dispatch ${var.name} artifact read/create"
  permissions = ["storage.objects.create", "storage.objects.get"]
  depends_on  = [google_project_service.required]
}

resource "google_storage_bucket_iam_member" "backend" {
  bucket = google_storage_bucket.artifacts.name
  role   = google_project_iam_custom_role.artifacts.name
  member = "serviceAccount:${google_service_account.backend.email}"
  condition {
    title      = "installation-prefix"
    expression = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.artifacts.name}/objects/${var.artifacts_prefix}/\")"
  }
}

resource "google_service_account_iam_member" "backend" {
  service_account_id = google_service_account.backend.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${local.backend_service_account}]"
  depends_on         = [module.foundation]
}

resource "google_artifact_registry_repository" "runtime" {
  project       = var.project_id
  location      = var.region
  repository_id = var.name
  format        = "DOCKER"
  depends_on    = [google_project_service.required]
}

resource "google_artifact_registry_repository_iam_member" "nodes" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.runtime.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.foundation.node_service_account}"
}

resource "google_compute_address" "gateway" {
  project    = var.project_id
  name       = "${var.name}-gateway"
  region     = var.region
  depends_on = [google_project_service.required]
}
