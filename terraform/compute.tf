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

# ECR Policy for EC2 instances to pull images
resource "aws_iam_role_policy" "ecr_policy" {
  name = "image-editor-ecr-policy"
  role = aws_iam_role.ec2_role.id

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
      },
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      }
    ]
  })
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

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  user_data = base64encode(templatefile("${path.module}/user-data/backend.sh", {
    account_id = data.aws_caller_identity.current.account_id
    region     = data.aws_region.current.name
  }))

  tags = {
    Name = "image-editor-backend"
  }
}

# Frontend EC2 Instance
# Runs Next.js application in private subnet
resource "aws_instance" "frontend" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids = [aws_security_group.frontend.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  user_data = base64encode(templatefile("${path.module}/user-data/frontend.sh", {
    backend_hostname = local.backend_hostname
    account_id       = data.aws_caller_identity.current.account_id
    region           = data.aws_region.current.name
  }))

  depends_on = [aws_instance.backend]

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
