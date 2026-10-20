resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = var.node_identity_display_name
  lifecycle { prevent_destroy = true }
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project                  = var.project_id
  name                     = "${var.name}-cluster"
  location                 = var.zone
  network                  = google_compute_network.this.id
  subnetwork               = google_compute_subnetwork.this.id
  min_master_version       = var.adopt_existing_cluster ? var.minimum_master_version : coalesce(var.minimum_master_version, var.node_version)
  datapath_provider        = "ADVANCED_DATAPATH"
  networking_mode          = "VPC_NATIVE"
  enable_shielded_nodes    = true
  deletion_protection      = true
  resource_labels          = var.labels
  initial_node_count       = var.adopt_existing_cluster ? null : 1
  remove_default_node_pool = var.adopt_existing_cluster ? null : true

  dynamic "node_config" {
    for_each = var.adopt_existing_cluster ? [] : [1]
    content {
      service_account = google_service_account.nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
      workload_metadata_config { mode = "GKE_METADATA" }
    }
  }

  # The imported default-pool is managed by the separate node-pool resource.
  # Never remove/recreate it to imitate a greenfield cluster example.
  release_channel { channel = "STABLE" }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.network_cidrs.control_plane
  }
  control_plane_endpoints_config {
    dns_endpoint_config { allow_external_traffic = false }
    ip_endpoints_config { enabled = true }
  }
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled      = false
    private_endpoint_enforcement_enabled = true
    dynamic "cidr_blocks" {
      for_each = var.api_access_cidrs
      content { cidr_block = cidr_blocks.value }
    }
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = "${var.name}-pods"
    services_secondary_range_name = "${var.name}-services"
    stack_type                    = "IPV4"
  }
  workload_identity_config { workload_pool = "${var.project_id}.svc.id.goog" }
  addons_config {
    dns_cache_config { enabled = true }
    gce_persistent_disk_csi_driver_config { enabled = true }
    network_policy_config { disabled = true }
  }
  logging_config { enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"] }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus { enabled = true }
  }
  maintenance_policy {
    daily_maintenance_window { start_time = "03:00" }
    dynamic "maintenance_exclusion" {
      for_each = var.maintenance_exclusions
      content {
        exclusion_name = maintenance_exclusion.key
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time
        exclusion_options { scope = maintenance_exclusion.value.scope }
      }
    }
  }
  depends_on = [google_project_iam_member.nodes]
  lifecycle { prevent_destroy = true }
}

resource "google_container_node_pool" "this" {
  project           = var.project_id
  name              = "default-pool"
  location          = var.zone
  cluster           = google_container_cluster.this.name
  node_count        = var.node_count
  node_locations    = [var.zone]
  version           = var.node_version
  max_pods_per_node = 110
  management {
    auto_repair  = false
    auto_upgrade = true
  }
  node_config {
    machine_type    = var.node_machine_type
    disk_size_gb    = 30
    disk_type       = "pd-balanced"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata        = { disable-legacy-endpoints = "true" }
    resource_labels = merge(var.labels, { goog-gke-node-pool-provisioning-model = "on-demand" })
    workload_metadata_config { mode = "GKE_METADATA" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    kubelet_config {
      insecure_kubelet_readonly_port_enabled = "FALSE"
      max_parallel_image_pulls               = 3
    }
  }
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }
  lifecycle { prevent_destroy = true }
}
