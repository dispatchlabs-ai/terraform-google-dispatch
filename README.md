# Dispatch Kubernetes foundation on Google Cloud

This module owns a dedicated private VPC/subnet, Cloud NAT, Private Services
Access, GKE Standard with Dataplane V2 and a scoped node identity, and private
PostgreSQL 17 on Cloud SQL. The caller owns the project, API enablement, provider
credentials, state backend, artifact storage and backend identity, image registry,
operator access, DNS, gateway address and installation evidence.

The application uses the same application-owned `dispatch/charts/dispatch` chart
on Google and Azure. Terraform does not run Helm, configure Kubernetes providers,
initialize application databases, read passwords or Secret Manager versions, or
manage Kubernetes-generated infrastructure.

## Consumption

Use a pinned Git commit. Supply the caller's Google provider, project, region,
zone, non-overlapping IPv4 ranges, explicit private API allowlist, a supported GKE
node version and maintenance exclusions. Enable the required Compute, GKE, IAM,
Service Networking and Cloud SQL APIs before the foundation is created.

Fresh creation uses `adopt_existing_cluster = false`: GKE creates a temporary
bootstrap pool with the scoped node service account, removes it, then Terraform
creates the separately managed `default-pool`. The node service account receives
only GKE node telemetry permissions here; caller-owned registry IAM supplies
private image pulls. It receives no application storage permissions.

For an existing matching cluster, set `adopt_existing_cluster = true` and import
both the cluster and its existing `default-pool` at their separate resource
addresses. The module then leaves the Terraform-only initial-count and
remove-default-pool inputs unset. It must never remove the imported pool to
simulate a fresh installation. Do not toggle adoption mode on a live cluster.
`minimum_master_version = null` preserves import state: the API cannot recover
the historical Terraform-only minimum. The observed control-plane version is
exported separately; node version and STABLE release channel remain explicit.

Live qualification covers adoption of an existing installation. The fresh
Terraform creation path has been source-reviewed and validated, but has not been
provisioned end to end.

## Ownership and maintenance

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

Cloud SQL uses private addressing, verified regional-CA TLS, seven-day backups
and PITR by default, and credential-safe logging flags. `log_min_duration_sample`
is not configurable through the Cloud SQL flags API; the runtime initializer
must independently verify its inherited safe value. No root password or SQL user
resource belongs in this module. A separate trusted operator establishes the
administrative credential and initializes/verifies the seven isolated stores.
The PSA DNS name is selected from the provider's `dns_names` list; `dns_name`
alone covers other connection types and can be empty for PSA.

Cloud deletion protections and Terraform `prevent_destroy` guard the cluster,
database and network. They do not replace backups or paired database/object/key
restore qualification. Secret escrow and artifact versions remain caller-owned.

## Validation

Use Terraform 1.14 or newer, `terraform fmt`, provider initialization/validation
and a full reviewed caller plan. The caller locks the exact Google provider; this
module declares its compatible minor line. No automated tests or cloud-changing
provisioners are included.

An imported cluster can initially report a label-ownership update even when its
effective cloud labels are unchanged. Inspect the exact pinned provider's update
path and the complete saved plan before treating such an operation as state
bookkeeping. Do not hide it with `ignore_changes`, omit intended labels or edit
state manually. Require a subsequent full no-change plan.
