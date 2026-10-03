# Frontend publishing to ECR

The new `publish-frontend-ecr.yml` workflow publishes the inherited OpenTelemetry
Astronomy Shop frontend. Application source, its Apache-2.0 attribution, and the
upstream build workflows are unchanged. Publishing has **not been tested against
AWS**. No image was built or pushed during this work.

## Configure the publishing identity

The existing infrastructure root now accepts an optional `frontend_publishing`
object. Its default is `null`, which creates neither a publishing role nor a
GitHub OIDC provider. In your ignored local Terraform values, configure the exact
repository and branch you control, for example:

```hcl
frontend_publishing = {
  github_repository         = "YOUR-OWNER/YOUR-REPOSITORY"
  publishing_branch         = "main"
  existing_oidc_provider_arn = "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
}
```

Replace all placeholders. Reuse the account's GitHub OIDC provider when one exists;
it must use `https://token.actions.githubusercontent.com`, accept the audience
`sts.amazonaws.com`, and belong to the account containing the role and ECR repository.
This configuration does not modify an existing provider. If an authorized operator
has confirmed that no provider exists, omit `existing_oidc_provider_arn` and set
`create_oidc_provider = true` explicitly. Terraform rejects selecting both or neither
when publishing is enabled. Creation is never assumed by default.

Trust uses `StringEquals` for the audience and the exact subject
`repo:OWNER/REPOSITORY:ref:refs/heads/BRANCH`. Use the branch name, not a full ref.
No pull-request, tag, environment, other repository, or wildcard branch subject
is accepted. Do not add a GitHub environment to this job without redesigning its
trust policy. Protect the publishing branch and review workflow changes: any
workflow with matching repository/branch claims can request this role.

For repositories using GitHub's immutable subject format, additionally set
`github_owner_id` and `github_repository_id` to the actual numeric IDs as strings.
The subject then includes `OWNER@ID/REPOSITORY@ID`; both IDs must be supplied.
Check which format your repository issues, especially for newly created repositories.
This follows [GitHub's AWS OIDC guidance](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

The role grants ECR upload operations plus repository/image inspection only on
the existing frontend repository. `ecr:GetAuthorizationToken` requires `Resource = "*"`;
this does not grant pushes to other repositories. There are no EKS, S3 state,
IAM administration, image-deletion, or tag-mutability permissions. The action uses
short-lived OIDC credentials; do not configure stored AWS access keys.
The push permissions follow the [AWS ECR reference](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-push-iam.html).

Provisioning these IAM changes remains a separately authorized infrastructure
operation using the remote-state setup in `infra.md`. The publishing workflow
does not execute Terraform or have access to its state.

## Repository variables and outputs

After future provisioning, configure **Settings → Secrets and variables → Actions
→ Variables** in the exact trusted GitHub repository:

| Repository variable | Terraform output | Meaning |
| --- | --- | --- |
| `AWS_REGION` | `frontend_publishing_region` | Region containing ECR |
| `AWS_ROLE_ARN` | `frontend_publishing_role_arn` | Dedicated publishing role; null while disabled |
| `ECR_REPOSITORY` | `frontend_ecr_repository_name` | Repository name, such as `astronomy-shop/frontend`, not its URL |

`frontend_publishing_oidc_subject` exposes the exact trust subject for review.
The existing `frontend_repository_url` output identifies the eventual image URL.
These outputs must come from the separately provisioned infrastructure; do not
invent an account ID or role ARN. No publishing branch repository variable is
required: IAM enforces the configured branch. Required values are checked before
AWS authentication, and missing or malformed values fail the workflow.

## Manual execution and reruns

Once the workflow exists on the repository's default branch, open **Actions →
Publish frontend to ECR → Run workflow** and select the exact trusted branch.
The workflow has only `workflow_dispatch`; commits, pull requests, and schedules
do not trigger it. Selecting an untrusted branch fails AWS role assumption.

Checkout is pinned to the dispatched commit and does not persist Git credentials.
The build uses `src/frontend/Dockerfile` with the repository root as context
because it copies both `src/frontend` and `pb`. The Dockerfile declares no build
arguments, so none are passed. `linux/amd64` matches the foundation's fixed
`AL2023_x86_64_STANDARD` worker AMI. Changing workers to ARM requires a coordinated
workflow and infrastructure change, not just a different instance-type value.

The only image tag is the full 40-character Git commit SHA. Before building, the
workflow requires the repository to be fully immutable, with no tag exclusions.
If the SHA already exists, it reports its digest and skips both build and push.
Only an explicit ECR `ImageNotFoundException` permits a new build; authorization,
network, missing-repository, and other errors fail the run. Workflow concurrency
serializes this publisher. An external writer racing the check can still cause
the push to fail; that failure is not suppressed. Rerun to detect the existing tag.
There is no `latest` tag, overwrite, deletion, or retry with a different tag.
To publish changed content, create a new commit. Rebuilding the same SHA does not
update its existing image even if upstream base images have changed.

Both official actions are pinned to full commits verified against their release
tags using `git ls-remote`:

- [actions/checkout v4.2.2](https://github.com/actions/checkout/tree/11bd71901bbe5b1630ceea73d27597364c9af683)
- [aws-actions/configure-aws-credentials v4.3.1](https://github.com/aws-actions/configure-aws-credentials/tree/7474bc4690e29a8392af63c5b98e7449536d5c3a)

## Verification and remaining work

Local checks cover Terraform formatting/schema validation, YAML parsing, shell
syntax, and the workflow's trigger, permission, and action-pin structure. These
checks passed. `actionlint` was unavailable and was not installed; Ruby's YAML
parser and `bash -n` provided the available syntax checks. They do
not verify GitHub execution, OIDC exchange, AWS permissions, image build success,
or registry behavior. Publishing consumes GitHub runner time and ECR storage.
The publishing workflow does not update GitOps references or deploy to EKS. The
overlay and Argo CD examples below provide a manual handoff, not fully automated CD.

## Kubernetes baseline and image choice

`kubernetes/opentelemetry-demo.yaml` remains unchanged, including attribution.
It was compared byte-for-byte with the official file at the
[1.12.0 release commit](https://github.com/open-telemetry/opentelemetry-demo/blob/2d4661e4897aa7b2d2ddbb5ef8c4824ca8a1b88d/kubernetes/opentelemetry-demo.yaml).
Both use `1.11.1-<service>` application images, and the official release's `.env`
still sets `IMAGE_VERSION=1.11.1`. The
[1.12.0 release notes](https://github.com/open-telemetry/opentelemetry-demo/releases/tag/1.12.0)
describe application changes, including a feature-flag UI absent from this manifest.
Therefore the release tag alone does not establish that changing image tags
produces a compatible 1.12.0 Kubernetes deployment.

The overlay now selects 1.12.0 application images and adds the directly required
flagd UI configuration described below. All existing third-party image references
remain unchanged. This resolves the identified manifest wiring gap at configuration
level; **runtime compatibility remains untested**. Inherited version labels and
telemetry attributes on existing resources still describe the base's 1.11.1
configuration; image references are the release selection, not those labels.

### Version decision after registry and release checks

On October 2, 2026, public GHCR manifest metadata confirmed a `linux/amd64`
descriptor for **all 17** exact application-service tags below. Only registry
authentication and manifest JSON were requested; no image layers were fetched.
Each tag has the prefix `ghcr.io/open-telemetry/demo:1.12.0-`:

| Service suffix | Linux/AMD64 available |
| --- | --- |
| accountingservice | Yes |
| adservice | Yes |
| cartservice | Yes |
| checkoutservice | Yes |
| currencyservice | Yes |
| emailservice | Yes |
| frauddetectionservice | Yes |
| frontend | Yes |
| frontendproxy | Yes |
| imageprovider | Yes |
| kafka | Yes |
| loadgenerator | Yes |
| paymentservice | Yes |
| productcatalogservice | Yes |
| quoteservice | Yes |
| recommendationservice | Yes |
| shippingservice | Yes |

**Decision: select explicit 1.12.0 tags for all 17 existing application images,
plus the separately verified `ghcr.io/open-telemetry/demo:1.12.0-flagdui` sidecar.**
The earlier stop condition is addressed by scoped patches adapted from
[upstream PR #1766](https://github.com/open-telemetry/opentelemetry-demo/pull/1766) and its
[corrected manifest](https://github.com/open-telemetry/opentelemetry-demo/blob/1002cf062f12c497af57ee4ffde71430d14ced20/kubernetes/opentelemetry-demo.yaml).
The checked-out 1.12.0 Compose configuration, flagd UI Dockerfile/start command,
and `src/flagd/demo.flagd.json` were inspected as supporting references. No
application source was modified.

The overlay implements the following required configuration:

- `frontendproxy-flagdui.yaml` sets `FLAGD_UI_HOST=opentelemetry-demo-flagd`
  and `FLAGD_UI_PORT=4000`, preserving the daemon's existing port 8013.
- `flagd-ui.yaml` adds the upstream `flagd-ui` sidecar on port 4000, its
  150Mi memory limit, and upstream telemetry environment, including
  `http://$(OTEL_COLLECTOR_NAME):4317`. The existing Collector Service exposes
  that port. Runtime behavior, including UI telemetry, has not been tested.
- `flagd-ui-service.yaml` exposes Service port 4000 using the named container
  target `flagdui`. A distinct port name avoids duplicating the daemon's
  `service` container-port name. The Service selector remains unchanged.
- The existing ConfigMap is the read-only seed; its 11 flag definitions match
  both the checkout and PR #1766 exactly. No duplicate seed resource is needed.
  The initializer copies `demo.flagd.json` into a shared `emptyDir` and sets
  mode 0644. Flagd mounts it at `/etc/flagd`; the UI mounts it at `/app/data`.
  Both writable mounts reference the same `config-rw` volume. The old direct
  ConfigMap mount is removed.
- The UI image's configuration and checkout Dockerfile use the default root
  user. The initializer and UI explicitly run as UID/GID 0, so the UI can
  update the root-owned seed file and directory without world-write permissions.
  This follows the upstream ownership model; non-root hardening is separate work.
  Pod replacement recreates the volume and resets UI edits to the ConfigMap seed.
- The new initializer uses verified `busybox:1.36.1`, rather than the upstream
  correction's untagged `busybox`. Existing BusyBox references elsewhere and all
  existing third-party image versions remain unchanged. In particular, flagd
  stays at the checkout's `v0.11.2`; the correction's unrelated downgrade to
  `v0.11.1` and observability image upgrades are not adopted.

The additional UI tag and BusyBox initializer were checked using only public
manifest and image-configuration JSON; no layers were pulled. Both expose
Linux/AMD64 manifests. The UI index digest was
`sha256:f6bdafaa9075715dc5a1b9d0f81ab275a5b002606ddeb08c85ee7dcdb116a17c`;
its command is `npm start`, and the checked-out script binds `0.0.0.0:4000`.
The 17 previous service-image checks were reused rather than repeated.

`kubernetes/upstream/kustomization.yaml` is the base. It references the identical
official manifest at the immutable commit above, rather than duplicating its
large generated contents. A local base beneath `kubernetes/` cannot load the parent
manifest file with standard Kustomize file restrictions, and an overlay cannot
use its own ancestor as a base. The sibling remote-resource base avoids both
problems without disabling restrictions. Rendering needs HTTPS access to
`raw.githubusercontent.com`, including from Argo CD's repo-server. The verified
manifest SHA-256 is
`ea09379db215c83822179e257092b5ad7984577c8f9b9c028954ce306b57a695`.

`kubernetes/eks/` selects the dedicated **otel-demo** application namespace,
preserving upstream namespace references. It retains the existing ClusterIP
services and adds no ingress, load balancer, or DNS. Its `frontend-image.yaml`
patch targets only the frontend Deployment/container, avoiding a repository-wide
image replacement: all upstream application services share the same GHCR image
name with different tag suffixes. The default remains the real upstream image
`ghcr.io/open-telemetry/demo:1.12.0-frontend` until publishing succeeds.
The 17 exact old-tag image overrides cannot match an ECR frontend reference,
so changing the separate frontend patch preserves the publishing handoff.

The Terraform EKS module is pinned to 21.26.0. Its managed-node-group configuration
creates the node role with `AmazonEC2ContainerRegistryReadOnly`, which includes
ECR authentication and image pulls. This was verified in the initialized module's
IAM resources; no IAM correction was needed. Same-account ECR pulling remains
AWS-untested and also requires node network access to ECR and image-layer storage.

## Argo CD prerequisites and examples

An authorized operator must first provision EKS and separately install a reviewed,
Kubernetes-compatible Argo CD release, its CRDs, and controller RBAC in `argocd`.
Argo CD is not installed by this repository. The examples assume Argo CD runs in
the target EKS cluster, so `https://kubernetes.default.svc` means that same cluster.
For an external Argo CD instance, register EKS separately and change the exact
destination server in both examples.

The EKS API is private by default. Operators need network routing, DNS resolution,
and authorized Kubernetes credentials from the VPC or a connected network for
installation, inspection, and port forwarding. An external Argo CD controller
also needs private API reachability; GitHub publishing does not need Kubernetes
access. Configure read-only Git credentials in Argo CD if the eventual repository
is private, and ensure the repo-server can reach GitHub and the pinned upstream
manifest. Do not commit credentials here.

Before registering `argocd/project.yaml` and `argocd/application.yaml`:

- Replace `REPLACE_OWNER/REPLACE_REPOSITORY` in both files with the exact published
  repository path, preserving identical URLs. No repository has been published here.
- Replace `REPLACE_GITOPS_BRANCH` with the branch holding the overlay, for example
  your reviewed main branch. This is configured via `spec.source.targetRevision`;
  it is separate from the IAM publishing-branch setting.
- Review the AppProject first, then register the Application. It targets
  `kubernetes/eks` and `otel-demo`; it does not manage its own Argo configuration.

The project permits only that repository/destination and the kinds actually
present in the 74 rendered resources. The inherited monitoring stack needs
Namespace, ClusterRole, and ClusterRoleBinding permissions as well as namespaced
workloads. Those three kinds are cluster-scoped: the destination namespace is not
a security boundary for their names or RBAC effects. Review these inherited
read permissions and avoid installing multiple copies with colliding cluster
resource names. No wildcard kind allowlists are used. See
[Argo CD projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/).

The Application omits `syncPolicy.automated`, so automatic sync, automatic pruning,
and self-healing stay disabled. It has no cascading-deletion finalizer. For manual
syncs, leave **Prune** unchecked and do not request prune on the command line.
See [Argo CD sync policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).

## Manual image-to-deployment handoff

The following is a future operator sequence; none of these publishing or cluster
operations was executed during implementation:

1. Run the publishing workflow on the trusted branch and confirm the frontend
   image exists under its full commit-SHA tag.
2. Review the runtime-validation limitations above. In
   `kubernetes/eks/frontend-image.yaml`, replace only `image:` with
   `<frontend_repository_url>:<published-40-character-commit-sha>`. Use the actual
   published image SHA, not the later GitOps configuration commit's SHA.
3. Render and review `kubectl kustomize kubernetes/eks`. Confirm only the intended
   frontend image changed, then commit and push that configuration change to the
   Application's configured GitOps branch.
4. Refresh Argo CD, inspect the revision and diff, and **manually sync**, with
   pruning disabled. Verify workloads and functionality before treating delivery
   as successful. The workflow does not perform this Git update or sync.

After a separately authorized deployment, access the existing entry-point proxy
from a machine with cluster access:

```sh
kubectl -n otel-demo port-forward service/opentelemetry-demo-frontendproxy 8080:8080
```

Open `http://localhost:8080`. The default local bind avoids publicly exposing the
shop or its demo observability UIs. Do not bypass the frontend proxy by assuming
the frontend Service is the complete application entry point.

## Overlay checks and unresolved validation

`kubectl kustomize kubernetes/eks` rendered 74 resources using standard loading
restrictions with kubectl 1.30.5 and its bundled Kustomize. YAML structure,
namespace/RBAC-subject consistency, all 18 application images at 1.12.0, the
ClusterIP entry point, and exact project kind allowlists passed local checks.
Container ports, Service selectors/targets, proxy hostnames, Collector port,
volume references, read-only seed, writable mounts, initialization command, and
UID/GID settings also passed structural checks against the confirmed references.
A temporary offline test using the identical upstream snapshot confirmed that a
frontend SHA image override changes no other image. Existing third-party image
references and the original manifest's hash remained unchanged. No new resource
kinds were needed, so the Argo CD configuration and its exact kind allowlists
remain unchanged. **Configuration rendering passed; runtime compatibility remains
untested.**

These are local structural checks, not server-side admission or runtime tests.
Use a kubectl version supported by the target EKS version before cluster work.
Argo CRD admission, repository credentials, private API access, scheduling and
capacity, ECR pulls, the inherited Grafana test Pod, observability, and the 1.12.0
application behavior remain unverified. No cluster was contacted,
and no AWS operation, deployment, build, commit, or push was performed.
