terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

############################
# Inputs
############################

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "demo-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.28"
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS worker nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "bucket_names" {
  description = "Bucket base names. Final names are bucket_prefix + each name."
  type        = list(string)
  default     = ["test1", "test2", "test3"]
}

variable "bucket_prefix" {
  description = "Optional prefix to ensure global uniqueness (e.g., yourname-123-)."
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "demo"
}

locals {
  # Final bucket names (use a prefix if you need uniqueness)
  bucket_full_names = [for n in var.bucket_names : "${var.bucket_prefix}${n}"]
  
  # Common tags for all resources
  common_tags = {
    Environment = "demo"
    ManagedBy   = "terraform"
    Cluster     = var.cluster_name
  }
}

############################
# Data Sources
############################

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

############################
# Networking (VPC and Subnets)
############################

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    local.common_tags,
    {
      Name                                           = "${var.name_prefix}-eks-vpc"
      "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
    }
  )
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name                                           = "${var.name_prefix}-public-subnet-${count.index + 1}"
      "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
      "kubernetes.io/role/elb"                      = "1"
    }
  )
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    local.common_tags,
    {
      Name                                           = "${var.name_prefix}-private-subnet-${count.index + 1}"
      "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
      "kubernetes.io/role/internal-elb"             = "1"
    }
  )
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-eks-igw"
    }
  )
}

resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.eks_igw]
}

resource "aws_nat_gateway" "eks_nat" {
  count = 2

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-nat-gateway-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.eks_igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-public-rt"
    }
  )
}

resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat[count.index].id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-private-rt-${count.index + 1}"
    }
  )
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

############################
# Security Groups
############################

resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.name_prefix}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.eks_vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-eks-cluster-sg"
    }
  )
}

resource "aws_security_group" "eks_nodes_sg" {
  name        = "${var.name_prefix}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description = "Allow nodes to communicate with each other"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "Allow pods to communicate with the cluster API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-eks-nodes-sg"
    }
  )
}

############################
# IAM Roles for EKS
############################

# EKS Cluster IAM Role
data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name               = "${var.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Node Group IAM Role
data "aws_iam_policy_document" "eks_nodes_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_nodes_role" {
  name               = "${var.name_prefix}-eks-nodes-role"
  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes_role.name
}

############################
# EKS Cluster
############################

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs    = ["0.0.0.0/0"]
    security_group_ids     = [aws_security_group.eks_cluster_sg.id]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

############################
# EKS Node Groups
############################

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.name_prefix}-eks-node-group"
  node_role_arn   = aws_iam_role.eks_nodes_role.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = var.node_instance_types

  # Use the latest EKS-optimized AMI
  ami_type = "AL2_x86_64"

  # Enable disk encryption
  disk_size = 20
  
  remote_access {
    ec2_ssh_key = aws_key_pair.eks_nodes_key.key_name
    source_security_group_ids = [aws_security_group.eks_nodes_sg.id]
  }

  labels = {
    Environment = "demo"
    NodeGroup   = "primary"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-eks-node"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

############################
# KMS Key for EKS Encryption
############################

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS cluster encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-eks-kms"
    }
  )
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name_prefix}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

############################
# SSH Key Pair for Node Access
############################

resource "tls_private_key" "eks_nodes_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "eks_nodes_key" {
  key_name   = "${var.name_prefix}-eks-nodes-key"
  public_key = tls_private_key.eks_nodes_key.public_key_openssh

  tags = local.common_tags
}

############################
# S3 Buckets (maintained from original)
############################

resource "aws_s3_bucket" "buckets" {
  for_each = toset(local.bucket_full_names)
  bucket   = each.value

  tags = merge(
    local.common_tags,
    {
      Name = each.value
    }
  )
}

resource "aws_s3_bucket_ownership_controls" "ownership" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id
  rule { 
    object_ownership = "BucketOwnerEnforced" 
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  for_each                = aws_s3_bucket.buckets
  bucket                  = each.value.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# IAM Policy for Node Group to Access S3 Buckets
data "aws_iam_policy_document" "nodes_s3_access" {
  statement {
    sid       = "BucketLevel"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [for b in values(aws_s3_bucket.buckets) : b.arn]
  }

  statement {
    sid     = "ObjectLevel"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:GetObjectVersion"
    ]
    resources = [for b in values(aws_s3_bucket.buckets) : "${b.arn}/*"]
  }
}

resource "aws_iam_policy" "nodes_s3_access" {
  name   = "${var.name_prefix}-eks-nodes-s3-access"
  policy = data.aws_iam_policy_document.nodes_s3_access.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "nodes_s3_access" {
  role       = aws_iam_role.eks_nodes_role.name
  policy_arn = aws_iam_policy.nodes_s3_access.arn
}

# S3 Bucket Policies for secure access
data "aws_iam_policy_document" "bucket_policy" {
  for_each = aws_s3_bucket.buckets

  # Deny non-TLS (HTTPS) requests
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [each.value.arn, "${each.value.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Allow access only to EKS nodes role
  statement {
    sid     = "AllowEKSNodesAccess"
    effect  = "Allow"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.eks_nodes_role.arn]
    }
    resources = [each.value.arn, "${each.value.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "apply" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id
  policy   = data.aws_iam_policy_document.bucket_policy[each.key].json

  depends_on = [
    aws_s3_bucket_ownership_controls.ownership,
    aws_s3_bucket_server_side_encryption_configuration.sse,
    aws_s3_bucket_public_access_block.block_public
  ]
}

############################
# OIDC Provider for IRSA
############################

data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-eks-irsa"
    }
  )
}

############################
# Outputs
############################

output "cluster_id" {
  description = "The name/id of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster_sg.id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster's OIDC Issuer"
  value       = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.eks_nodes.id
}

output "node_group_role_arn" {
  description = "IAM role ARN of the EKS Node Group"
  value       = aws_iam_role.eks_nodes_role.arn
}

output "vpc_id" {
  description = "VPC ID where EKS cluster is deployed"
  value       = aws_vpc.eks_vpc.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs where EKS nodes are deployed"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for load balancers"
  value       = aws_subnet.public[*].id
}

output "bucket_names_created" {
  description = "List of S3 bucket names created"
  value       = [for b in values(aws_s3_bucket.buckets) : b.bucket]
}

output "kubeconfig_command" {
  description = "AWS CLI command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.eks_cluster.name}"
}

output "node_ssh_key_private" {
  description = "Private SSH key for accessing EKS nodes (store securely!)"
  value       = tls_private_key.eks_nodes_key.private_key_pem
  sensitive   = true
}