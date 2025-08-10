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