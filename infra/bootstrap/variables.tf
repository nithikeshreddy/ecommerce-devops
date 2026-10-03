variable "region" {
  description = "AWS region in which to create the state bucket."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name; use lowercase letters, digits, and hyphens."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Use 3–63 lowercase letters, digits, or hyphens, beginning and ending with a letter or digit."
  }
}
