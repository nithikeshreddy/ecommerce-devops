# E-Commerce DevOps on AWS EKS

An AWS deployment project using **OpenTelemetry Astronomy Shop**, a microservices-based e-commerce application. My work focuses on infrastructure provisioning, container delivery, and Kubernetes deployment using Terraform, GitHub Actions, Amazon ECR, and Argo CD.

I completed the original AWS implementation in **January 2025**. I recreated the deployment configuration for this public repository in **October 2026**, including updates to authentication, state locking, and application configuration.

## Project Overview

This project brings together the infrastructure and deployment configuration needed to run Astronomy Shop on Amazon EKS.

The application comes from OpenTelemetry. The AWS infrastructure, frontend publishing workflow, EKS overlay, and Argo CD configuration are the focus of this repository.

## Infrastructure

- **Terraform:** Configures a VPC across two availability zones, public and private subnets, an EKS managed node group, IAM roles, and a frontend ECR repository.
- **Remote state:** Includes a separate S3 bucket configuration with versioning, encryption, and native state locking.
- **Access control:** Uses private EKS API access by default and restricted GitHub OIDC trust for image publishing.

## Image Publishing and Deployment

The delivery process has four steps:

1. Manually trigger the GitHub Actions workflow to build the frontend image.
2. Authenticate to AWS through OIDC and publish the image to ECR with a full Git commit-SHA tag.
3. Update the frontend image reference in the Kubernetes configuration and push the change.
4. Manually sync the application through Argo CD.

The EKS overlay uses Kustomize to configure the application namespace, application image versions, frontend image replacement, and flagd UI integration. Argo CD examples define the repository source, deployment destination, and allowed resources.

## Repository Structure

| Path | Purpose |
|---|---|
| `infra/bootstrap/` | Terraform state-bucket configuration |
| `infra/terraform/` | AWS infrastructure and publishing permissions |
| `kubernetes/eks/` | EKS deployment overlay |
| `argocd/` | Argo CD project and application examples |
| `.github/workflows/` | Manual frontend publishing workflow |
| `docs/infra.md` | Infrastructure setup instructions |
| `docs/delivery.md` | Image publishing and deployment instructions |

## Getting Started

Start with the [infrastructure guide](docs/infra.md), then follow the [delivery guide](docs/delivery.md). Replace the documented configuration placeholders with your own environment settings.

Terraform validation, workflow syntax checks, and Kubernetes manifest rendering have passed. **This published version has not yet been redeployed or runtime-tested on AWS.**

## Application Credit

The application and its instrumentation are provided by the [OpenTelemetry Astronomy Shop project](https://github.com/open-telemetry/opentelemetry-demo/tree/1.12.0).

The upstream [Apache-2.0 license](LICENSE), contributor attribution, and generated Kubernetes manifest are preserved. See [README.upstream.md](README.upstream.md) for the original application documentation.