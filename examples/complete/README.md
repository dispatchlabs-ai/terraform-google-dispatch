# Complete Google Cloud infrastructure example

This root composes the foundation with a private, versioned GCS artifact bucket,
backend-only Workload Identity, an Artifact Registry repository, a gateway IP,
and the private Cloud SQL DNS record needed for verified TLS. It uses the local
module source, so it works from a reviewed Git checkout before registry
publication. It is a single-zone installation, without automatic application
failover.

## Prepare

Use Terraform or OpenTofu 1.11 or later, below 2.0. The project must already exist,
have billing and Service Usage enabled, and permit the APIs in `main.tf`.
The provisioning identity needs permission to manage these APIs and resources,
including IAM roles/bindings. Authentication belongs to the Google provider:
use workload federation, Application Default Credentials or your usual secure
provider authentication.

Copy `terraform.tfvars.example` to a private `terraform.tfvars`, replace its
project, globally unique bucket and illustrative GKE version, and review all
network ranges. Discover a supported STABLE version with
`gcloud container get-server-config --region=REGION`. Set a maintenance window
and any bounded exclusions appropriate to your installation.

Configure a protected remote backend in this root before applying. The example
deliberately does not select your state bucket or credentials. Commit the
provider dependency lockfile in your calling repository.

```sh
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=foundation.plan
terraform apply foundation.plan
terraform output -json installation
terraform output -json helm_values > cloud-values.json
```

`cloud-values.json` is a non-secret partial Helm values file. Merge it with
your application and platform values; it deliberately omits image digests,
private keys, database credentials, public hostname and activation.

Use `tofu` in place of `terraform` for the same commands. Review the full plan
before apply. Do not use this fresh-installation example against existing
resource state.

## Install the application

1. Arrange private operator routing to the cluster and PostgreSQL (for example,
   VPN/peering or an operator host). The `api_access_cidrs` must include that
   operator source as well as the selected node/Pod ranges.
2. Copy the reviewed backend, launcher and worker images into the output
   `registry` and record their immutable digests. Node identity has repository
   pull access; it has no artifact-bucket permission.
3. Fetch the Cloud SQL shared CA bundle from Google and verify it. The output
   `postgres.hostname` resolves through the created private zone; use this
   hostname and CA for `verify-full`, not just the private IP. Provision the
   administrative password through a trusted operator outside Terraform, then
   initialize the seven isolated databases and retain the role-separated
   application credentials and encryption/signing keys outside Pods.
4. Install the shared Dispatch chart and the reusable Kubernetes platform
   gateway/policies from the same reviewed release. Keep application activation
   disabled until initialization and network checks pass. Use `namespace` and `release` from the output. The backend
   ServiceAccount is derived as `<release>-backend` in both the chart and
   workload identity binding.
5. Configure chart artifacts with `kind: gcs`, output `artifacts.bucket`,
   `projectId`, `prefix` and `credentialsMode: workloadIdentity`. Copy
   `service_account_annotations` to the backend ServiceAccount only. GKE
   Dataplane V2 metadata access for that backend uses `169.254.169.254/32` on ports 80 and 8080 across supported versions;
   worker and launcher policies must continue to deny it.
6. Use `gateway.address` for the gateway Service/DNS. Supply your application
   hostname, TLS and backend callback certificates separately. Verify allowed
   callbacks and denied metadata/database/artifact access using actual worker
   Pods before activation.

The artifact identity can create/read only within the configured prefix. It
cannot list, delete, or overwrite existing objects (GCS replacement also
requires delete permission). Bucket versioning and soft deletion are enabled;
no lifecycle rule expires retained versions.

## Ownership and recovery

This example creates infrastructure metadata only. It does not place database
passwords, Kubernetes credentials, application Secrets, object contents or
private keys in Terraform state. Public object access is blocked; GCS access
uses its authenticated public HTTPS endpoint.

GKE STABLE owns node versions after creation. Terraform never writes the old
initial version back to the node pool. Use bounded maintenance exclusions and
the application's authenticated drain/worker termination procedure before
planned maintenance; exclusions cannot postpone emergency/end-of-support
maintenance indefinitely.

Back up the PostgreSQL stores, artifact versions and matching keys together and
qualify a restore before relying on the installation. Deletion protections and
versioning are safeguards, not a whole-application backup.

For existing infrastructure, compose the foundation and your existing bucket,
identity, registry or gateway in your own root instead of adopting this example
blindly. The foundation itself does not require these example resource names.
This example has static CLI/provider validation; a fresh cloud apply and
end-to-end application qualification remain required.

Install Helm with the output `installation.release` and `installation.namespace`.
The `release_name` input derives the backend ServiceAccount name used by workload
identity; changing it also requires a deliberately reviewed Helm release migration.
