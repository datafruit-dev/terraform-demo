# =============================================================================
# OUTPUTS
# =============================================================================

# Note: Application URL will be available after deploying the Ingress
# Run: kubectl get ingress -n image-editor
# to get the ALB DNS name

# VPC and Subnet IDs (still needed for EKS)
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# ECR Repository URLs
output "ecr_backend_repository_url" {
  description = "URL of the backend ECR repository"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  description = "URL of the frontend ECR repository"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_registry_id" {
  description = "The registry ID where the repositories are created"
  value       = aws_ecr_repository.backend.registry_id
}