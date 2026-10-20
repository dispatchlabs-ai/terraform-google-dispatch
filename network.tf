resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  lifecycle { prevent_destroy = true }
}

resource "google_compute_subnetwork" "this" {
  project                  = var.project_id
  name                     = "${var.name}-subnet"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.network_cidrs.nodes
  private_ip_google_access = true
  stack_type               = "IPV4_ONLY"
  secondary_ip_range {
    range_name    = "${var.name}-pods"
    ip_cidr_range = var.network_cidrs.pods
  }
  secondary_ip_range {
    range_name    = "${var.name}-services"
    ip_cidr_range = var.network_cidrs.services
  }
  lifecycle { prevent_destroy = true }
}

resource "google_compute_global_address" "sql" {
  project       = var.project_id
  name          = "${var.name}-sql-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", var.network_cidrs.private_access)[0]
  prefix_length = tonumber(split("/", var.network_cidrs.private_access)[1])
  network       = google_compute_network.this.id
  lifecycle { prevent_destroy = true }
}

resource "google_service_networking_connection" "sql" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.sql.name]
  lifecycle { prevent_destroy = true }
}

resource "google_compute_router" "this" {
  project = var.project_id
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.this.id
  lifecycle { prevent_destroy = true }
}

resource "google_compute_router_nat" "this" {
  project                             = var.project_id
  name                                = "${var.name}-nat"
  region                              = var.region
  router                              = google_compute_router.this.name
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "LIST_OF_SUBNETWORKS"
  enable_endpoint_independent_mapping = false
  subnetwork {
    name                    = google_compute_subnetwork.this.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  lifecycle { prevent_destroy = true }
}
