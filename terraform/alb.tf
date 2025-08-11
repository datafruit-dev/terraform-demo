# =============================================================================
# APPLICATION LOAD BALANCER FOR EKS
# =============================================================================
# Note: This ALB will be used by the AWS Load Balancer Controller
# to route traffic to the EKS cluster nodes

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "image-editor-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "image-editor-alb"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

# Target Group for EKS NodePort Services
# The AWS Load Balancer Controller will manage target registration
resource "aws_lb_target_group" "eks_nodes" {
  name     = "image-editor-eks-nodes"
  port     = 30080  # NodePort for frontend service
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  
  target_type = "instance"
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200-399"
  }

  deregistration_delay = 30

  tags = {
    Name = "image-editor-eks-nodes"
  }
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_nodes.arn
  }
}

# Attach EKS nodes to target group
# This will be done automatically by the AWS Load Balancer Controller
# when using Ingress resources, but we can also do it manually
resource "aws_lb_target_group_attachment" "eks_nodes" {
  count            = aws_eks_node_group.main.scaling_config[0].desired_size
  target_group_arn = aws_lb_target_group.eks_nodes.arn
  target_id        = data.aws_instances.eks_nodes.ids[count.index]
  port             = 30080

  depends_on = [aws_eks_node_group.main]
}

# Data source to get EKS node instances
data "aws_instances" "eks_nodes" {
  filter {
    name   = "tag:kubernetes.io/cluster/image-editor-cluster"
    values = ["owned"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [aws_eks_node_group.main]
}