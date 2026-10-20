output "network_id" {
  description = "Dedicated VPC identifier."
  value       = google_compute_network.this.id
}
output "subnetwork_id" {
  description = "Private node/operator subnet identifier."
  value       = google_compute_subnetwork.this.id
}
output "node_service_account" {
  description = "Node identity; caller may grant image pull access, never application artifact access."
  value       = google_service_account.nodes.email
}
output "cluster" {
  description = "Observed private cluster identity and control-plane version."
  value = {
    name           = google_container_cluster.this.name
    location       = google_container_cluster.this.location
    endpoint       = google_container_cluster.this.endpoint
    master_version = google_container_cluster.this.master_version
    node_version   = google_container_node_pool.this.version
    workload_pool  = "${var.project_id}.svc.id.goog"
  }
}
output "distributed_postgres" {
  description = "Private database metadata only. Credentials and application stores remain operator-owned."
  value = {
    name            = google_sql_database_instance.this.name
    connection_name = google_sql_database_instance.this.connection_name
    hostname = one([
      for dns in google_sql_database_instance.this.dns_names :
      dns.name if dns.connection_type == "PRIVATE_SERVICES_ACCESS" && dns.dns_scope == "INSTANCE"
    ])
    private_ip = google_sql_database_instance.this.private_ip_address
    port       = 5432
  }
}
