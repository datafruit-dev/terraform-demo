# =============================================================================
# VARIABLES
# =============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
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
