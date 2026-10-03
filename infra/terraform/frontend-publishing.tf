variable "frontend_publishing" {
  description = "Optional GitHub publisher. Reuse an existing OIDC provider, or explicitly request creation, never both."
  type = object({
    github_repository          = string
    publishing_branch          = string
    existing_oidc_provider_arn = optional(string)
    create_oidc_provider       = optional(bool, false)
    github_owner_id            = optional(string)
    github_repository_id       = optional(string)
  })
  default = null

  validation {
    condition = var.frontend_publishing == null ? true : (
      can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$", var.frontend_publishing.github_repository)) &&
      can(regex("^[A-Za-z0-9_][A-Za-z0-9_./-]*$", var.frontend_publishing.publishing_branch))
    )
    error_message = "Specify one exact owner/repository and a branch name without refs/heads/, wildcards, colons, or whitespace."
  }

  validation {
    condition = var.frontend_publishing == null ? true : (
      var.frontend_publishing.create_oidc_provider != (var.frontend_publishing.existing_oidc_provider_arn != null)
    )
    error_message = "Choose exactly one: existing_oidc_provider_arn or create_oidc_provider = true."
  }

  validation {
    condition = try(var.frontend_publishing.existing_oidc_provider_arn, null) == null ? true : can(regex(
      "^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$",
      var.frontend_publishing.existing_oidc_provider_arn
    ))
    error_message = "The existing ARN must identify the GitHub Actions OIDC provider in the publishing account."
  }

  validation {
    condition = var.frontend_publishing == null ? true : (
      (var.frontend_publishing.github_owner_id == null && var.frontend_publishing.github_repository_id == null) ||
      (can(regex("^[0-9]+$", var.frontend_publishing.github_owner_id)) &&
      can(regex("^[0-9]+$", var.frontend_publishing.github_repository_id)))
    )
    error_message = "For immutable GitHub subject claims, supply both numeric IDs as strings; otherwise omit both."
  }
}

locals {
  frontend_publisher_enabled = var.frontend_publishing != null
  github_subject_repository = !local.frontend_publisher_enabled ? null : (
    var.frontend_publishing.github_owner_id == null ? var.frontend_publishing.github_repository :
    "${split("/", var.frontend_publishing.github_repository)[0]}@${var.frontend_publishing.github_owner_id}/${split("/", var.frontend_publishing.github_repository)[1]}@${var.frontend_publishing.github_repository_id}"
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = try(var.frontend_publishing.create_oidc_provider, false) ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # IAM uses its trusted CA library for GitHub; no hardcoded certificate thumbprint.
}

resource "aws_iam_role" "frontend_publisher" {
  count = local.frontend_publisher_enabled ? 1 : 0

  name                 = "${var.project_name}-frontend-publisher"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = var.frontend_publishing.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.frontend_publishing.existing_oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${local.github_subject_repository}:ref:refs/heads/${var.frontend_publishing.publishing_branch}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "frontend_publisher" {
  count = local.frontend_publisher_enabled ? 1 : 0

  name = "frontend-ecr-push"
  role = aws_iam_role.frontend_publisher[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthentication"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "FrontendRepositoryOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = aws_ecr_repository.frontend.arn
      },
    ]
  })
}

output "frontend_publishing_role_arn" {
  description = "GitHub AWS_ROLE_ARN repository variable; null until frontend_publishing is configured."
  value       = try(aws_iam_role.frontend_publisher[0].arn, null)
}

output "frontend_publishing_oidc_subject" {
  description = "Exact GitHub OIDC subject trusted by the publishing role."
  value       = local.frontend_publisher_enabled ? "repo:${local.github_subject_repository}:ref:refs/heads/${var.frontend_publishing.publishing_branch}" : null
}

output "frontend_ecr_repository_name" {
  description = "GitHub ECR_REPOSITORY repository variable (name, not URL)."
  value       = aws_ecr_repository.frontend.name
}

output "frontend_publishing_region" {
  description = "GitHub AWS_REGION repository variable."
  value       = var.region
}
