# =============================================================================
# IAM ROLES AND INSTANCE PROFILES
# =============================================================================

# IAM Role for EC2 Instances
# Allows EC2 instances to use AWS Systems Manager for remote access
resource "aws_iam_role" "ec2_role" {
  name = "image-editor-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach Systems Manager policy for Session Manager access
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy for ECR Access
# Allows EC2 instances to pull Docker images from ECR
resource "aws_iam_policy" "ecr_pull_policy" {
  name        = "image-editor-ecr-pull-policy"
  description = "Policy to allow EC2 instances to pull images from ECR"

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
}

# Attach ECR policy to EC2 role
resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ecr_pull_policy.arn
}

# Instance Profile to attach IAM role to EC2
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "image-editor-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# =============================================================================
# EC2 INSTANCES
# =============================================================================

# Backend EC2 Instance  
# Runs FastAPI application in private subnet
resource "aws_instance" "backend" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Enable detailed monitoring for better SSM integration
  monitoring = true

  # Metadata options for IMDSv2 (recommended for security and SSM)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  user_data = base64encode(templatefile("${path.module}/user-data/backend-docker.sh", {
    aws_region             = var.aws_region
    ecr_registry           = aws_ecr_repository.backend.repository_url
    ecr_backend_repository = aws_ecr_repository.backend.repository_url
  }))

  # Ensure VPC endpoints are created before the instance
  depends_on = [
    aws_ecr_repository.backend,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssm_messages,
    aws_vpc_endpoint.ec2_messages
  ]

  tags = {
    Name = "image-editor-backend"
  }
}
# Runs Next.js application in private subnet
resource "aws_instance" "frontend" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids = [aws_security_group.frontend.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Enable detailed monitoring for better SSM integration
  monitoring = true

  # Metadata options for IMDSv2 (recommended for security and SSM)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  user_data = base64encode(templatefile("${path.module}/user-data/frontend-docker.sh", {
    aws_region              = var.aws_region
    ecr_registry            = aws_ecr_repository.frontend.repository_url
    ecr_frontend_repository = aws_ecr_repository.frontend.repository_url
    backend_hostname        = local.backend_hostname
  }))

  # Ensure VPC endpoints are created before the instance
  depends_on = [
    aws_ecr_repository.frontend,
    aws_instance.backend,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssm_messages,
    aws_vpc_endpoint.ec2_messages
  ]

  tags = {
    Name = "image-editor-frontend"
  }
}
# =============================================================================
# APPLICATION LOAD BALANCER
# =============================================================================

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "image-editor-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "image-editor-alb"
  }
}

# Target Group for Frontend
resource "aws_lb_target_group" "frontend" {
  name     = "image-editor-frontend-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "image-editor-frontend-tg"
  }
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "frontend" {
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = aws_instance.frontend.id
}

# =============================================================================
# SSM READINESS CHECK
# =============================================================================

# Wait for backend instance to register with SSM before deployment
resource "null_resource" "wait_for_backend_ssm" {
  triggers = {
    instance_id = aws_instance.backend.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for backend instance ${aws_instance.backend.id} to register with SSM..."
      i=1
      while [ $i -le 30 ]; do
        if aws ssm describe-instance-information --region ${var.aws_region} --filters "Key=InstanceIds,Values=${aws_instance.backend.id}" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
          echo "Backend instance is registered with SSM and online"
          exit 0
        fi
        echo "Attempt $i/30: Instance not yet registered with SSM, waiting 30 seconds..."
        sleep 30
        i=$((i + 1))
      done
      echo "ERROR: Backend instance failed to register with SSM after 15 minutes"
      exit 1
    EOT
  }

  depends_on = [aws_instance.backend]
}

# Wait for frontend instance to register with SSM before deployment
resource "null_resource" "wait_for_frontend_ssm" {
  triggers = {
    instance_id = aws_instance.frontend.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for frontend instance ${aws_instance.frontend.id} to register with SSM..."
      i=1
      while [ $i -le 30 ]; do
        if aws ssm describe-instance-information --region ${var.aws_region} --filters "Key=InstanceIds,Values=${aws_instance.frontend.id}" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
          echo "Frontend instance is registered with SSM and online"
          exit 0
        fi
        echo "Attempt $i/30: Instance not yet registered with SSM, waiting 30 seconds..."
        sleep 30
        i=$((i + 1))
      done
      echo "ERROR: Frontend instance failed to register with SSM after 15 minutes"
      exit 1
    EOT
  }

  depends_on = [aws_instance.frontend]
}
