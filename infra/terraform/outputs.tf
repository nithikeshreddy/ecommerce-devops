output "vpc_id" {
  description = "VPC containing the EKS cluster."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Subnets tagged for internet-facing load balancers."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnets used by EKS and its managed node group."
  value       = module.vpc.private_subnets
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint; network reachability and IAM access are both required."
  value       = module.eks.cluster_endpoint
}

output "frontend_repository_url" {
  description = "Private ECR repository for the upstream frontend service."
  value       = aws_ecr_repository.frontend.repository_url
}
