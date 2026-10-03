variable "region" {
  description = "AWS region with at least two available standard availability zones."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "project_name" {
  description = "Short lowercase prefix for infrastructure and the frontend ECR repository."
  type        = string
  default     = "astronomy-shop"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.project_name))
    error_message = "Use 2–24 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "kubernetes_version" {
  description = "Explicit EKS minor version. Check regional availability and support before deployment."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Specify a Kubernetes minor version such as 1.35."
  }
}

variable "node_instance_type" {
  description = "An x86_64 EC2 instance type compatible with the AL2023 node AMI."
  type        = string
  default     = "t3.medium"
  nullable    = false
}

variable "node_counts" {
  description = "Managed node group bounds and initial desired count; no autoscaler is installed."
  type = object({
    min     = number
    desired = number
    max     = number
  })
  default = {
    min     = 1
    desired = 2
    max     = 3
  }
  nullable = false

  validation {
    condition = alltrue([
      for count in [var.node_counts.min, var.node_counts.desired, var.node_counts.max] :
      count >= 1 && count == floor(count)
      ]) && (
      var.node_counts.min <= var.node_counts.desired &&
      var.node_counts.desired <= var.node_counts.max
    )
    error_message = "Node counts must be positive integers with min <= desired <= max."
  }
}

variable "allowed_cluster_access_cidrs" {
  description = "Up to ten trusted public IPv4 CIDRs (/24 through /32). Empty keeps the API private only."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = length(var.allowed_cluster_access_cidrs) <= 10 && alltrue([
      for cidr in var.allowed_cluster_access_cidrs : try(
        can(cidrnetmask(cidr)) &&
        tonumber(split("/", cidr)[1]) >= 24 &&
        tonumber(split("/", cidr)[1]) <= 32,
        false
      )
    ])
    error_message = "Use at most ten valid IPv4 CIDRs with /24–/32 prefixes, or [] for private access only."
  }
}
