# =============================================================================
# EKS CLUSTER CONFIGURATION
# =============================================================================

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "image-editor-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "image-editor-eks-cluster-role"
  }
}

# Attach required policies to EKS cluster role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "image-editor-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.31"

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, [aws_subnet.private.id])
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs    = ["0.0.0.0/0"]
    
    # Use existing security groups
    security_group_ids = [aws_security_group.eks_cluster.id]
  }

  # Enable control plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]

  tags = {
    Name = "image-editor-eks-cluster"
  }
}

# =============================================================================
# EKS NODE GROUP CONFIGURATION
# =============================================================================

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_node_group" {
  name = "image-editor-eks-node-group-role"

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

  tags = {
    Name = "image-editor-eks-node-group-role"
  }
}

# Attach required policies to node group role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node_group.name
}

# Custom ECR policy for pulling images from our repositories
resource "aws_iam_policy" "eks_ecr_pull_policy" {
  name        = "image-editor-eks-ecr-pull-policy"
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
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = aws_iam_policy.eks_ecr_pull_policy.arn
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "image-editor-node-group"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = [aws_subnet.private.id]

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = ["t3.medium"]
  
  # Use the latest EKS-optimized AMI
  ami_type = "AL2023_x86_64_STANDARD"

  # Enable remote access for debugging (optional)
  # remote_access {
  #   ec2_ssh_key = var.ssh_key_name
  # }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
    aws_iam_role_policy_attachment.eks_ssm_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]

  tags = {
    Name = "image-editor-eks-node-group"
  }
}

# =============================================================================
# SECURITY GROUPS FOR EKS
# =============================================================================

# Security Group for EKS Cluster
resource "aws_security_group" "eks_cluster" {
  name        = "image-editor-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "image-editor-eks-cluster-sg"
  }
}

# Allow nodes to communicate with cluster API
resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow nodes to communicate with cluster API"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

# Allow cluster API to communicate with nodes
resource "aws_vpc_security_group_egress_rule" "eks_cluster_to_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow cluster to communicate with nodes"
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

# Allow cluster to communicate with nodes on kubelet port
resource "aws_vpc_security_group_egress_rule" "eks_cluster_to_nodes_kubelet" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow cluster to communicate with kubelet"
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

# Security Group for EKS Nodes
resource "aws_security_group" "eks_nodes" {
  name        = "image-editor-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name                                              = "image-editor-eks-nodes-sg"
    "kubernetes.io/cluster/image-editor-cluster"     = "owned"
  }
}

# Allow nodes to communicate with each other
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_internal" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow nodes to communicate with each other"
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

# Allow nodes to receive communication from cluster control plane
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_cluster" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow nodes to receive communication from cluster"
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

# Allow nodes to receive kubelet communication from cluster
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_kubelet" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow kubelet communication from cluster"
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

# Allow ALB to reach nodes (for ingress controller)
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_alb" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow ALB to reach nodes"
  from_port                    = 30000
  to_port                      = 32767
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

# Egress rules for nodes
resource "aws_vpc_security_group_egress_rule" "eks_nodes_all" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# IAM ROLE FOR AWS LOAD BALANCER CONTROLLER
# =============================================================================

# Create IAM policy for AWS Load Balancer Controller
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for AWS Load Balancer Controller"
  
  policy = file("${path.module}/iam-policies/aws-load-balancer-controller-policy.json")
}

# Create OIDC provider for EKS
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "image-editor-eks-oidc"
  }
}

# IAM role for AWS Load Balancer Controller service account
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "aws-load-balancer-controller"
  }
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}

# =============================================================================
# OUTPUTS FOR KUBERNETES CONFIGURATION
# =============================================================================

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}