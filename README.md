# Dispatch Kubernetes foundation on Google Cloud

A reusable Terraform and OpenTofu module for a private GKE Standard cluster and
PostgreSQL 17. It owns a dedicated VPC/subnet, Cloud NAT, Private Services Access,
GKE Dataplane V2, a scoped node identity and private Cloud SQL.

The caller owns the project, API enablement, provider credentials, state backend,
artifact storage and backend identity, image registry, operator access, DNS and
gateway address. The application is installed separately with the shared
[Dispatch Helm chart](https://github.com/dispatchlabs-ai/dispatch/tree/experiment/kubernetes/charts/dispatch).
This module has no Helm or Kubernetes provider dependency. Application databases,
passwords, Secret Manager payloads and Kubernetes-generated infrastructure remain
outside its ownership.

## Usage

Use Terraform or OpenTofu 1.11 or newer, below 2.0, and the Google provider
8.x starting at 8.7. The caller configures the provider and backend and locks the
exact provider version. No Dispatch caller repository is required.

Enable the Compute, Kubernetes Engine, IAM, Service Networking and Cloud SQL
Admin APIs before creating the foundation. Replace `<commit>` with a full
reviewed Git commit, choose a supported STABLE-channel GKE patch version, and
review the example ranges against all connected networks.

```hcl
terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7"
    }
  }
}

variable "project_id" {
  type = string
}

variable "gke_node_version" {
  type = string
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
}

module "dispatch" {
  source = "git::https://github.com/dispatchlabs-ai/terraform-google-dispatch.git?ref=<commit>"

  project_id   = var.project_id
  name         = "dispatch"
  region       = "us-central1"
  zone         = "us-central1-a"
  node_version = var.gke_node_version
  network_cidrs = {
    nodes          = "10.60.0.0/20"
    pods           = "10.61.0.0/16"
    services       = "10.62.0.0/20"
    control_plane  = "10.63.0.0/28"
    private_access = "10.64.0.0/16"
  }
  api_access_cidrs = ["10.60.0.0/20", "10.61.0.0/16"]
}
```

The caller must provide a private route for operators to the cluster and
database. The example API allowlist covers the node/operator subnet and Pod
range; add the actual operator range if access originates elsewhere.

New clusters briefly use a bootstrap pool with the scoped node service account,
then replace it with the separately managed `default-pool`. The node identity
receives GKE telemetry permissions only. Grant private image pulls separately;
application artifact permissions belong to the backend workload identity.

## Inputs and outputs

| Required input | Purpose |
| --- | --- |
| `project_id` | Existing caller-owned project. |
| `name` | Resource prefix, 3–24 lowercase letters, digits or hyphens, starting with a letter. |
| `region`, `zone` | Region and a zone within it for this single-zone foundation. |
| `network_cidrs` | Non-overlapping IPv4 ranges for nodes, Pods, Services, control plane and Private Services Access. |
| `api_access_cidrs` | Explicit RFC1918 operator/node/Pod ranges allowed on the private API, each /16 or narrower. |
| `node_version` | Explicit supported GKE patch version such as `1.x.y-gke.z`. |

| Optional input | Default and behavior |
| --- | --- |
| `node_count`, `node_machine_type` | Two `e2-standard-2` nodes; fixed count from 1 to 5, without autoscaling. |
| `minimum_master_version` | `null`; new clusters use `node_version` as the control-plane minimum. |
| `adopt_existing_cluster` | `false`; `true` preserves established bootstrap settings and leaves an unset control-plane minimum unchanged. Never toggle this setting on a running cluster. |
| `node_identity_display_name`, `labels` | Node identity display name and cluster/node labels. |
| `maintenance_exclusions` | Empty map; optional bounded windows with start/end timestamps and scope. |
| `postgres` | PostgreSQL tier `db-custom-1-3840`, 20 GiB disk with growth capped at 100 GiB, seven retained backups and seven days of transaction logs. |

See [variables.tf](variables.tf) for complete types and defaults.

| Output | Contents |
| --- | --- |
| `network_id`, `subnetwork_id` | Identifiers for caller-owned networking integrations. |
| `node_service_account` | Node identity for separately scoped registry access. |
| `cluster` | Name, location, private endpoint, observed control-plane version and workload identity pool. |
| `distributed_postgres` | Instance/connection names, hostname, private IP and port; no credentials. |

## Operation

This is a fixed-size, single-zone foundation, not an HA deployment. Cloud NAT,
the GKE release channel, node auto-upgrades and Cloud SQL maintenance retain their
managed-service behavior. Node auto-repair is disabled. A bounded GKE maintenance
exclusion postpones upgrades; it does not disable them permanently. Review its
expiry and perform the application's authenticated drain, positive worker
termination and controller settlement before maintenance. Never force-delete a
worker or create a replacement owner while previous execution is uncertain.

The private control plane admits only the supplied private CIDRs. Dataplane V2
provides NetworkPolicy enforcement, but the chart owns the actual Pod policies.
Qualify fresh ownerless worker Pods, DNS including NodeLocal DNS, Service and
private API addresses, workload metadata denial and allowed callbacks on the
actual cluster. A private API address is required because general public worker
egress must not expose an active public control-plane endpoint.

The caller binds only the backend Kubernetes ServiceAccount to its artifact
identity and grants immutable object create/read within the installation prefix.
It also supplies the chart's metadata allowance, native GCS values, PostgreSQL CA
and hostname, role-separated Secrets, application TLS and exact image digests.

Cloud SQL uses private addressing, a regional shared CA, required TLS, seven
retained backups and seven-day PITR by default, and credential-safe logging flags.
Clients must verify the CA and the exported hostname. `log_min_duration_sample` is not
configurable through the Cloud SQL flags API; the runtime initializer must
independently verify its inherited safe value. A separate trusted operator
establishes the administrative credential and initializes/verifies the seven
isolated stores.

Cloud deletion protections and Terraform `prevent_destroy` guard the cluster,
database and network. They do not replace backups or paired database/object/key
restore qualification. Secret escrow and artifact versions remain caller-owned.

## Validation

Run `terraform fmt -check`, `terraform init` and `terraform validate`, then review
the complete caller plan before applying. The equivalent `tofu` commands are
supported. Static compatibility is checked with Terraform 1.11.0/1.14.5 and
OpenTofu 1.11.0/1.13.1 against Google provider 8.7.0.

The new-cluster creation path is source-reviewed and statically validated; a
complete fresh Terraform or OpenTofu deployment has not been exercised.
