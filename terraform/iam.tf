# =============================================================================
# IAM RESOURCES FOR ECR ACCESS
# =============================================================================

# IAM Policy for ECR Access
# Allows EKS nodes to pull Docker images from ECR
resource "aws_iam_policy" "ecr_pull_policy" {
  name        = "image-editor-ecr-pull-policy"
  description = "Policy to allow EKS nodes to pull images from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "image-editor-ecr-pull-policy"
  }
}