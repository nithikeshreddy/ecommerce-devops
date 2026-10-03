# AWS infrastructure scaffold

This Terraform configuration has not been deployed or AWS-verified. It is a
portfolio foundation, not a production-readiness or performance claim.
The application remains the OpenTelemetry Authors' Astronomy Shop release
1.12.0 from the [official upstream repository](https://github.com/open-telemetry/opentelemetry-demo/tree/1.12.0).
The upstream Apache-2.0 license and attribution remain unchanged. These files
add infrastructure configuration; they do not claim authorship of the application.

## Resources

- One `10.0.0.0/16` VPC in the first two available standard availability zones,
  selected by sorted zone name. Confirm this CIDR does not overlap future networks.
- Two public `/24` subnets, an internet gateway, and load-balancer discovery tags.
  No load balancer or load-balancer controller is installed.
- Two private `/20` subnets for EKS nodes, with outbound access through one NAT
  gateway and its Elastic IP in the first public subnet. This single gateway is
  an availability dependency and can cause cross-zone data-transfer charges.
- One EKS cluster and one on-demand, AL2023 x86_64 managed node group. Counts are
  configurable; the maximum count does not install or enable an autoscaler.
- EKS-managed VPC CNI, CoreDNS, and kube-proxy add-ons; compatible add-on versions
  are resolved by the module at deployment time. Control-plane API, audit, and
  authenticator logs have seven-day CloudWatch retention.
- One private ECR repository, `<project_name>/frontend`, with immutable tags,
  AES256 encryption, and scan-on-push. It starts empty and refuses forced deletion
  of images. Image publishing and application deployment are separate future work.

Deploying this configuration incurs AWS charges, including the EKS control
plane, worker nodes and disks, NAT gateway hours and data processing, public IPv4,
ECR storage, CloudWatch logs, and applicable data transfer. No paid resources were
created during scaffold validation. The separate state bucket also incurs S3
storage and request charges, including retained object versions.

## Versions and configuration

Run commands from `infra/terraform/`. The configuration uses Terraform 1.11.x
(minimum 1.11.4), with exact provider pins: AWS 6.59.0, Time 0.13.1, and TLS 4.1.0.
The provider lockfile also fixes the modules' Cloudinit 2.4.1 and Null 3.3.2 dependencies.
Module requirements were checked against their maintainers' official sources:

- [EKS module 21.26.0 requirements](https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v21.26.0/versions.tf):
  Terraform >= 1.5.7 and AWS provider >= 6.59.
- [VPC module 6.7.3 requirements](https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/v6.7.3/versions.tf):
  Terraform >= 1.0 and AWS provider >= 6.28.
- [AWS EKS version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html):
  the example selects Kubernetes 1.35; check support and regional availability
  again before deployment. Compatibility with this older application release
  has not been tested.

Copy `terraform.tfvars.example` to a local `terraform.tfvars` and review:

| Input | Purpose |
| --- | --- |
| `region` | AWS region; default `us-east-1` |
| `project_name` | Resource prefix; default `astronomy-shop` |
| `kubernetes_version` | Required explicit EKS minor version |
| `node_instance_type` | x86_64 instance type; default `t3.medium` |
| `node_counts` | Positive integer `min`, `desired`, `max`, in that order |
| `allowed_cluster_access_cidrs` | Trusted IPv4 API client networks, or `[]` |

Example node sizing is illustrative; capacity for the full Astronomy Shop and
observability stack has not been established. No AWS account, credentials, domain,
or personal GitHub URL is embedded. Supply AWS credentials through your normal
credential chain only when deployment is separately authorized.

## Access and IAM

The API is private by default. An empty CIDR list disables the public endpoint.
A nonempty list enables it only for the listed IPv4 ranges; validation permits
at most ten `/24` through `/32` CIDRs and rejects world-open ranges and IPv6.
Use fixed, trusted egress `/32` addresses where possible. Private endpoint access
stays enabled so nodes do not depend on public API routing. For private-only
administration, arrange connectivity and DNS from within the VPC or a connected
network; this scaffold does not create a VPN, bastion, or public SSH access.

The EKS module creates distinct control-plane and EC2 node IAM roles with its
standard AWS-managed service policies. The node role receives
`AmazonEKSWorkerNodePolicy` and `AmazonEC2ContainerRegistryReadOnly`, allowing
ECR reads and pulls (including AWS system images), but no publishing. These
managed policies include some
wildcard resources required by their service operations; they are not custom
account-administrator policies.

VPC CNI permissions are removed from the node role and assigned to a dedicated
IRSA role. Its federation trust matches only this cluster's OIDC provider,
the STS audience, and `system:serviceaccount:kube-system:aws-node`, following
[AWS node-role guidance](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html).
Nodes require IMDSv2 with hop limit one to reduce ordinary pods' access to node
credentials. There are no application IAM permissions or public ECR policies.

The Terraform execution principal receives cluster-administrator access through
an EKS access entry for initial administration. This is scoped to this cluster,
not account-wide AWS administrator access. Review that principal before any
deployment; add explicit role-based access entries for future operators.
The IAM permissions needed by the infrastructure deployment identity itself are
not provisioned here. No GitHub federation or ECR publishing role is included.

## Bootstrap and remote state

`infra/bootstrap/` is a separate Terraform root that manages only the state bucket.
It reuses Terraform `~> 1.11.4` and AWS provider `6.59.0`. The bucket name and region
are configurable. Versioning, AES256 server-side encryption, all four public-access
blocks, and a bucket policy denying non-TLS requests protect the bucket.
`prevent_destroy = true` and `force_destroy = false` guard against accidental
Terraform deletion; they do not prevent deletion outside Terraform or after
removing the resource configuration. No automatic version expiration is configured.

Bootstrap state stays **local**, separate from the bucket it creates. Restrict file
access to its operator, use encrypted local storage, and keep encrypted, access-controlled
backups of `terraform.tfstate` and its backups outside the repository after every
bootstrap change. Test recovery and serialize bootstrap operations; local state
does not coordinate separate machines. Do not store its only backup in this bucket.

`infra/terraform/` manages the application infrastructure (VPC, EKS, IAM, ECR) and
now declares a partial S3 backend. Its state goes to the key in `backend.hcl`, not
the bootstrap state file. **The bucket has not been created, and remote state has
not been tested against AWS.** Provisioning the bucket, granting backend access,
and initializing or migrating state remain future setup.

Native S3 locking (`use_lockfile = true`) is a **reconstruction-time modernization**,
not an inherited feature of Astronomy Shop 1.12.0. Both roots retain the compatible
Terraform 1.11.x requirement. There is no DynamoDB table.
See [HashiCorp's S3 backend documentation](https://developer.hashicorp.com/terraform/language/backend/s3).

### Future setup commands — not executed

These commands are instructions for a separately authorized AWS setup. The
bootstrap apply creates a billable bucket. Use your normal AWS credential chain;
never put credentials in `.tfvars` or backend files. Run from the repository root:

```sh
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
# Edit bucket_name and region; select a globally unique, valid S3 bucket name.
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan
terraform -chdir=infra/bootstrap apply
# Secure and back up the resulting local bootstrap state before continuing.
cp infra/terraform/backend.hcl.example infra/terraform/backend.hcl
# Replace bucket and region with the bootstrap outputs; review the state key.
```

Keep `encrypt = true` and `use_lockfile = true`. Backend region must match the
bucket's region and is independent of the EKS provider region. Use a distinct
state key for each independently managed environment; this scaffold documents
only the default Terraform workspace.

Choose **one** initialization path from the repository root:

- **Fresh infrastructure, with no existing local state:**

  ```sh
  terraform -chdir=infra/terraform init -backend-config=backend.hcl
  ```

- **Existing local application infrastructure state:** stop concurrent Terraform
  operations and make a secure backup first. Preserve the original local state
  and backend metadata, then run:

  ```sh
  terraform -chdir=infra/terraform init -migrate-state -backend-config=backend.hcl
  ```

  Review Terraform's migration prompt and verify the remote state before resuming
  work. Do not use `-reconfigure` as a substitute for migration: it does not copy
  existing state. Do not migrate the bootstrap root into the application state key.
  Keep the secure local backup until recovery from remote state has been verified.

### Backend permissions

Grant the infrastructure execution role these permissions separately from the
bucket-management privileges used for bootstrap. For bucket `BUCKET` and key
`astronomy-shop/infrastructure/terraform.tfstate` in the default workspace:

| Resource | Required actions |
| --- | --- |
| `arn:aws:s3:::BUCKET` | `s3:ListBucket`, restricted to the state prefix |
| `arn:aws:s3:::BUCKET/astronomy-shop/infrastructure/terraform.tfstate` | `s3:GetObject`, `s3:PutObject` |
| `arn:aws:s3:::BUCKET/astronomy-shop/infrastructure/terraform.tfstate.tflock` | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` |

Ordinary backend access does not require deleting the state object. Restrict
lockfile deletion to its exact key. Recovery of older versions requires separately
authorized version-list/read permissions. These grants are documented, not created
by the bootstrap root; the bucket policy only denies insecure transport. AES256
uses S3-managed encryption, so this configuration needs no customer KMS permissions.
Adjust ARN partitions where necessary. Permission details follow the
[official S3 backend reference](https://developer.hashicorp.com/terraform/language/backend/s3#permissions-required).

## Checks and remaining setup

Each directory-local `.gitignore` preserves existing repository rules and excludes
Terraform working directories, state and backups, real `.tfvars` files, crash
logs, and plans named `*.tfplan`, `*.plan`, `tfplan`, `plan.out`, or stored in
`plans/`. Actual `backend.hcl` and `*.backend.hcl` files are also ignored. Any future
saved plan must follow one of these naming conventions.
Keep the examples and each root's `.terraform.lock.hcl` in version control;
the latter records provider versions and checksums, not infrastructure state.

Run these checks from each Terraform root. They require no AWS credentials,
do not initialize a real backend, and do not deploy resources:

```sh
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

Both roots passed checks with Terraform 1.11.4: formatting, initialization with
the backend disabled, and validation. Sandbox DNS and provider startup
restrictions required retries outside the sandbox. Ignore checks confirmed that
local artifacts are excluded while the example and provider lockfile remain trackable.
No plan, apply, destroy, or AWS CLI command was run.

Initialization downloads modules and provider binaries from their official
registries; it is not an AWS connectivity check. Validation checks configuration
and provider schemas, not regional quotas, IAM authorization, node readiness,
image availability, costs, or application behavior. Before a separately approved
deployment, complete remote-state setup, review the execution identity and access
networks, confirm regional versions and instance availability, and review costs.
ECR publishing, load-balancer setup, Argo CD, application manifests, and workload
verification remain outside this foundation.
