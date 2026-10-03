# E-Commerce DevOps on AWS EKS

An AWS DevOps portfolio reconstruction using **OpenTelemetry Astronomy Shop
1.12.0**. The application and its instrumentation are the work of the
[OpenTelemetry Authors](https://github.com/open-telemetry/opentelemetry-demo/tree/1.12.0).
The upstream [Apache-2.0 license](LICENSE), attribution, and generated Kubernetes
manifest are preserved. The original project README is available as
[README.upstream.md](README.upstream.md).

The author reports completing the original AWS implementation in **January 2025**.
This repository was **reconstructed for public publication in October 2026**.
That historical completion date is author-reported; it is not evidence that this
reconstruction has been deployed or validated on AWS. The infrastructure and
delivery additions are separate from the inherited application implementation.

## What is included

- Terraform for a two-AZ VPC, public/private subnets, EKS managed nodes, frontend
  ECR repository, and IAM; a separate S3 state-bucket bootstrap root and native
  S3 state locking configuration.
- A manually triggered GitHub Actions frontend publisher using AWS OIDC,
  restricted repository/branch trust, and immutable full commit-SHA image tags.
- An EKS Kustomize overlay selecting verified 1.12.0 application images and
  adding the upstream flagd UI wiring while retaining existing third-party images.
- Scoped Argo CD project/application examples. Delivery requires an operator to
  publish the frontend, update its GitOps image reference, commit/push that change,
  and manually sync Argo CD. Automatic sync, pruning, and self-healing are disabled.

See [infrastructure setup](docs/infra.md) and [image publishing and delivery](docs/delivery.md)
for configuration, placeholders, private API access, and the manual handoff.
Inherited workflows are preserved in [.github/upstream-workflows](.github/upstream-workflows)
outside GitHub's active workflow directory. Only the manual publisher remains active.

## Validation and deployment status

Completed checks include Terraform formatting, backend-disabled initialization,
and validation for both roots; workflow YAML parsing, Bash syntax, trigger and
permission checks; and verification of official action commit pins. Kustomize
rendered 74 resources, with checks for images, namespace/RBAC consistency, Argo
resource allowlists, flagd UI service/volume wiring, and frontend-only ECR replacement.
Public registry metadata confirmed Linux/AMD64 application-image availability;
image layers were not pulled. `actionlint` was unavailable.

**This reconstruction has not been deployed or runtime-tested.** AWS provisioning,
remote-state operation, OIDC publishing, ECR pulls, Argo CD synchronization, and
application behavior remain unverified. Configure the documented placeholders
before any separately authorized deployment.

**Deploying AWS resources incurs charges**, including EKS, worker nodes and disks,
NAT gateway, public IPv4, S3 state storage/requests, ECR storage, logs, and data transfer.
