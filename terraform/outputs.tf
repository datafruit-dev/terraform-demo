# =============================================================================
# OUTPUTS
# =============================================================================

# Note: The application URL will be available after deploying the Ingress resource
# Run: kubectl get ingress -n image-editor image-editor-ingress
output "app_url_instructions" {
  description = "Instructions to get the application URL"
  value       = "After deploying to EKS, run: kubectl get ingress -n image-editor image-editor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
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

# EKS Cluster Information
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

# Update kubeconfig command
output "update_kubeconfig_command" {
  description = "Command to update kubeconfig for kubectl access"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

# Setup instructions
output "setup_instructions" {
  description = "Instructions to complete the EKS setup"
  value = <<-EOT
    
    ========================================
    EKS Cluster Setup Instructions:
    ========================================
    
    1. Update your kubeconfig:
       ${indent(3, "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}")}
    
    2. Install AWS Load Balancer Controller:
       ${indent(3, "cd ../.. && ./terraform-demo/scripts/setup-alb-controller.sh ${aws_eks_cluster.main.name} ${var.aws_region}")}
    
    3. Deploy the application:
       ${indent(3, "cd terraform-demo && ./scripts/deploy-to-eks.sh ${aws_eks_cluster.main.name} ${var.aws_region}")}
    
    4. Get the application URL (wait 2-3 minutes after deployment):
       ${indent(3, "kubectl get ingress -n image-editor image-editor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'")}
    
    ========================================
  EOT
}