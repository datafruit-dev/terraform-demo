# =============================================================================
# OUTPUTS
# =============================================================================

# Application URL
output "app_url" {
  description = "URL to access the application"
  value       = "http://${aws_lb.main.dns_name}"
}

# Load Balancer DNS
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

# Private IPs for debugging
output "frontend_private_ip" {
  description = "Private IP of the Frontend instance"
  value       = aws_instance.frontend.private_ip
}

output "backend_private_ip" {
  description = "Private IP of the Backend instance"
  value       = aws_instance.backend.private_ip
}

# VPC and Subnet IDs
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

# ECR Registry ID
output "ecr_registry_id" {
  description = "The registry ID where the repositories are created"
  value       = aws_ecr_repository.backend.registry_id
}