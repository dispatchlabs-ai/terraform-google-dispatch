resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = "${var.name}-postgres"
  region              = var.region
  database_version    = "POSTGRES_17"
  deletion_protection = true
  # No root_password, user resources, secret-version reads or SQL provisioners.
  # Adoption preserves the operator credential and initialized databases.
  settings {
    tier                        = var.postgres.tier
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.postgres.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.postgres.disk_autoresize_limit
    deletion_protection_enabled = true
    enable_dataplex_integration = true
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.postgres.transaction_log_days
      backup_retention_settings { retained_backups = var.postgres.retained_backups }
    }
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.this.id
      server_ca_mode  = "GOOGLE_MANAGED_CAS_CA"
      ssl_mode        = "ENCRYPTED_ONLY"
    }
    location_preference { zone = var.zone }
    dynamic "database_flags" {
      for_each = {
        log_statement                      = "none"
        log_min_duration_statement         = "-1"
        log_min_error_statement            = "panic"
        log_error_verbosity                = "terse"
        log_parameter_max_length           = "0"
        log_parameter_max_length_on_error  = "0"
        password_encryption                = "scram-sha-256"
        "pg_stat_statements.track_utility" = "off"
        "pgaudit.log"                      = "none"
      }
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
  depends_on = [google_service_networking_connection.sql]
  lifecycle { prevent_destroy = true }
}
