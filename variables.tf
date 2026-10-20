variable "project_id" {
  description = "Existing caller-owned Google project."
  type        = string
}

variable "name" {
  description = "Foundation name prefix; changing it replaces named infrastructure."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.name))
    error_message = "Use 3–24 lowercase letters, digits and hyphens, starting with a letter; the derived node service-account ID must fit Google's 30-character limit."
  }
}

variable "region" {
  description = "Region for the private network, NAT and Cloud SQL."
  type        = string
}

variable "zone" {
  description = "Zone for this single-zone cluster and database."
  type        = string
}

variable "network_cidrs" {
  description = "Non-overlapping IPv4 ranges for nodes, Pods, Services, control plane and private services."
  type = object({
    nodes          = string
    pods           = string
    services       = string
    control_plane  = string
    private_access = string
  })
  validation {
    condition = alltrue([
      for cidr in values(var.network_cidrs) : can(cidrnetmask(cidr))
    ])
    error_message = "Supply valid IPv4 CIDRs; review all five ranges for overlap before creation."
  }
}

variable "api_access_cidrs" {
  description = "Explicit private operator/node/Pod CIDRs authorized on the private API endpoint."
  type        = set(string)
  validation {
    condition = length(var.api_access_cidrs) > 0 && alltrue([
      for cidr in var.api_access_cidrs :
      can(cidrnetmask(cidr)) &&
      try(tonumber(split("/", cidr)[1]) >= 16, false) &&
      can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.)", cidr))
    ])
    error_message = "Authorize explicit RFC1918 IPv4 CIDRs with /16 or narrower prefixes."
  }
}

variable "node_version" {
  description = "Supported GKE version used as the initial control-plane minimum for new clusters. New nodes inherit that version; STABLE owns subsequent node upgrades. This is not a continuing node-version pin."
  type        = string
  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+-gke\\.[0-9]+$", var.node_version))
    error_message = "Use an explicit supported GKE patch version."
  }
}

variable "minimum_master_version" {
  description = "Optional control-plane version minimum. Null uses node_version for new clusters and leaves the minimum unset when preserving established bootstrap settings."
  type        = string
  default     = null
}

variable "adopt_existing_cluster" {
  description = "Preserve established cluster bootstrap settings. Leave false for new clusters, which replace the bootstrap pool with the separately managed pool. Never toggle this on a running cluster."
  type        = bool
  default     = false
}

variable "node_count" {
  description = "Fixed node count; no cluster autoscaler."
  type        = number
  default     = 2
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 5 && floor(var.node_count) == var.node_count
    error_message = "Choose 1–5 whole nodes and review singleton maintenance before scaling."
  }
}

variable "node_machine_type" {
  description = "AMD64 node machine type."
  type        = string
  default     = "e2-standard-2"
}

variable "node_identity_display_name" {
  description = "Display name of the scoped node service account."
  type        = string
  default     = "Dispatch GKE node identity"
}

variable "labels" {
  description = "Cluster and node resource labels."
  type        = map(string)
  default     = {}
}

variable "maintenance_start_time" {
  description = "Start of the daily GKE maintenance window in UTC, HH:MM. Arrange application drain before maintenance; this window does not disable emergency or end-of-support upgrades."
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "Use a UTC time from 00:00 through 23:59."
  }
}

variable "maintenance_exclusions" {
  description = "Explicit bounded GKE maintenance exclusions. Review fencing before expiry or node maintenance."
  type = map(object({
    start_time = string
    end_time   = string
    scope      = string
  }))
  default = {}
  validation {
    condition = alltrue([
      for exclusion in values(var.maintenance_exclusions) :
      contains(["NO_UPGRADES", "NO_MINOR_UPGRADES", "NO_MINOR_OR_NODE_UPGRADES"], exclusion.scope) &&
      try(timecmp(exclusion.start_time, exclusion.end_time) < 0, false)
    ])
    error_message = "Each exclusion needs valid RFC3339 start/end timestamps in order and a supported GKE exclusion scope."
  }
}

variable "postgres" {
  description = "Private PostgreSQL 17 capacity and retention. Credentials and seven application stores belong to the separate initializer."
  type = object({
    tier                  = optional(string, "db-custom-1-3840")
    disk_size_gb          = optional(number, 20)
    disk_autoresize_limit = optional(number, 100)
    retained_backups      = optional(number, 7)
    transaction_log_days  = optional(number, 7)
  })
  default = {}
}
