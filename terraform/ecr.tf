# =============================================================================
# ECR REPOSITORIES
# =============================================================================

# ECR Repository for Backend Docker Images
resource "aws_ecr_repository" "backend" {
  name                 = "image-editor-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = var.enable_ecr_scanning
  }

  # Lifecycle policy to keep only the last 10 images
  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "image-editor-backend"
    Application = "image-editor"
    Component   = "backend"
  }
}

# ECR Repository for Frontend Docker Images
resource "aws_ecr_repository" "frontend" {
  name                 = "image-editor-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = var.enable_ecr_scanning
  }

  # Lifecycle policy to keep only the last 10 images
  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "image-editor-frontend"
    Application = "image-editor"
    Component   = "frontend"
  }
}

# =============================================================================
# ECR LIFECYCLE POLICIES
# =============================================================================

# Lifecycle policy for backend repository
# Keeps only the specified number of images to manage storage costs
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_image_count} images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Lifecycle policy for frontend repository
# Keeps only the specified number of images to manage storage costs
resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_image_count} images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# =============================================================================
# ECR REPOSITORY POLICIES
# =============================================================================

# Repository policy for backend ECR
# Allows pulling images from EC2 instances and GitHub Actions
resource "aws_ecr_repository_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPullFromEC2"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ec2_role.arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# Repository policy for frontend ECR
# Allows pulling images from EC2 instances and GitHub Actions
resource "aws_ecr_repository_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPullFromEC2"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ec2_role.arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}