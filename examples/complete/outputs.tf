output "installation" {
  description = "Non-secret metadata to configure the platform, chart and database initializer."
  value = {
    release                 = var.release_name
    namespace               = var.namespace
    backend_service_account = local.backend_service_account
    cluster                 = module.foundation.cluster
    postgres                = module.foundation.distributed_postgres
    artifacts = {
      provider         = "gcs"
      project_id       = var.project_id
      bucket           = google_storage_bucket.artifacts.name
      prefix           = var.artifacts_prefix
      credentials_mode = "workloadIdentity"
      backend_identity = google_service_account.backend.email
      service_account_annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.backend.email
      }
    }
    registry = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.runtime.repository_id}"
    gateway = {
      address      = google_compute_address.gateway.address
      address_name = google_compute_address.gateway.name
      region       = var.region
    }
  }
  depends_on = [google_dns_record_set.postgres, google_storage_bucket_iam_member.backend, google_service_account_iam_member.backend]
}

output "helm_values" {
  description = "Partial Dispatch chart values. Export as JSON and merge with reviewed platform/application values; no credentials are included."
  value = {
    postgres = {
      host = trimsuffix(module.foundation.distributed_postgres.hostname, ".")
      port = module.foundation.distributed_postgres.port
    }
    artifacts = {
      kind            = "gcs"
      projectId       = var.project_id
      bucket          = google_storage_bucket.artifacts.name
      prefix          = var.artifacts_prefix
      credentialsMode = "workloadIdentity"
    }
    backend = {
      serviceAccount = {
        annotations = { "iam.gke.io/gcp-service-account" = google_service_account.backend.email }
      }
    }
    networkPolicy = {
      databaseCidrs         = ["${module.foundation.distributed_postgres.private_ip}/32"]
      workloadIdentityCidrs = ["169.254.169.254/32"]
      workloadIdentityPorts = [80, 8080]
    }
  }
}
