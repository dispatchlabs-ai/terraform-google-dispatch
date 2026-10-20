variable "project_id" {
  description = "Existing billed project; enable the Service Usage API before running this root."
  type        = string
}

variable "name" {
  description = "Installation resource prefix. Use a distinct prefix for every installation."
  type        = string
  default     = "dispatch"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.name))
    error_message = "Use 3–20 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "region" {
  description = "Region for the network, database, registry and artifacts."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone within region for the single-zone GKE/database foundation."
  type        = string
  default     = "us-central1-a"
}

variable "initial_kubernetes_version" {
  description = "Supported STABLE GKE patch, for example 1.x.y-gke.z. Used at creation; GKE owns subsequent node upgrades."
  type        = string
}

variable "network_cidrs" {
  description = "Non-overlapping IPv4 ranges, reviewed against your connected networks."
  type = object({
    nodes          = string
    pods           = string
    services       = string
    control_plane  = string
    private_access = string
  })
  default = {
    nodes          = "10.60.0.0/20"
    pods           = "10.61.0.0/16"
    services       = "10.62.0.0/20"
    control_plane  = "10.63.0.0/28"
    private_access = "10.64.0.0/16"
  }
}

variable "api_access_cidrs" {
  description = "Private operator/node/Pod ranges allowed on the private API. Provide private operator routing separately."
  type        = set(string)
  default     = ["10.60.0.0/20", "10.61.0.0/16"]
}

variable "maintenance_start_time" {
  description = "UTC daily maintenance window start."
  type        = string
  default     = "03:00"
}

variable "maintenance_exclusions" {
  description = "Bounded RFC3339 exclusion windows. Coordinate expiry with application drain and upgrades."
  type        = map(object({ start_time = string, end_time = string, scope = string }))
  default     = {}
}

variable "artifacts_bucket" {
  description = "Globally unique name for a new installation-owned artifact bucket."
  type        = string
}

variable "artifacts_prefix" {
  description = "Installation object prefix without leading/trailing slashes."
  type        = string
  default     = "dispatch"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9/_-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$", var.artifacts_prefix))
    error_message = "Use letters, digits, slash, underscore or hyphen, starting and ending with a letter or digit."
  }
}

variable "namespace" {
  description = "Kubernetes namespace used when installing the application chart."
  type        = string
  default     = "dispatch"
}

variable "release_name" {
  description = "Helm release name; the chart derives its backend ServiceAccount from this value."
  type        = string
  default     = "dispatch"
  validation {
    condition     = length(var.release_name) <= 53 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "Use 1–53 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
}

variable "labels" {
  description = "Caller labels for cloud resources."
  type        = map(string)
  default     = {}
}
