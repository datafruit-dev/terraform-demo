# =============================================================================
# VARIABLES
# =============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "ecr_image_count" {
  description = "Number of Docker images to keep in ECR repositories"
  type        = number
  default     = 10
}

variable "enable_ecr_scanning" {
  description = "Enable vulnerability scanning for images pushed to ECR"
  type        = bool
  default     = true
}

# =============================================================================
# EKS VARIABLES
# =============================================================================

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for EKS node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_group_desired_size" {
  description = "Desired number of nodes in the EKS node group"
  type        = number
  default     = 2
}

variable "eks_node_group_min_size" {
  description = "Minimum number of nodes in the EKS node group"
  type        = number
  default     = 1
}

variable "eks_node_group_max_size" {
  description = "Maximum number of nodes in the EKS node group"
  type        = number
  default     = 4
}
