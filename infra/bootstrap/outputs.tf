output "bucket_name" {
  description = "State bucket name to copy into the application root's backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "State bucket region to copy into backend.hcl."
  value       = var.region
}
