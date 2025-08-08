terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
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
  description = "Prefix for IAM/EC2 names."
  type        = string
  default     = "demo"
}

locals {
  # Final bucket names (use a prefix if you need uniqueness)
  bucket_full_names = [for n in var.bucket_names : "${var.bucket_prefix}${n}"]
}

############################
# Networking (default VPC)
############################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "Egress-only; no inbound by default"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "${var.name_prefix}-ec2-sg" }
}

############################
# EC2 AMI & Instance
############################

# Latest Amazon Linux 2023 x86_64 HVM EBS
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

############################
# IAM for the instance
############################

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Buckets first, so we can scope the role’s allow-policy exactly
resource "aws_s3_bucket" "buckets" {
  for_each = toset(local.bucket_full_names)
  bucket   = each.value

  tags = { Name = each.value }
}

# (Best practice) Ownership, encryption & public access blocks
resource "aws_s3_bucket_ownership_controls" "ownership" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id
  rule { object_ownership = "BucketOwnerEnforced" }
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

# Allow the instance role to actually use the buckets/objects
data "aws_iam_policy_document" "role_s3_allow" {
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

resource "aws_iam_policy" "role_s3_allow" {
  name   = "${var.name_prefix}-ec2-s3-allow"
  policy = data.aws_iam_policy_document.role_s3_allow.json
}

resource "aws_iam_role_policy_attachment" "attach_role_s3" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.role_s3_allow.arn
}

# Bucket policies that DENY access to anyone except the instance role's *assumed-role sessions*
# (and require TLS). We intentionally do NOT include PutBucketPolicy here to avoid locking out admins.
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

  # Deny bucket-level reads to anyone except the instance role’s STS sessions
  statement {
    sid     = "DenyBucketLevelExceptInstanceRole"
    effect  = "Deny"
    actions = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [each.value.arn]
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.ec2_role.name}/*"
      ]
    }
  }

  # Deny ALL object actions to anyone except the instance role’s STS sessions
  statement {
    sid     = "DenyObjectLevelExceptInstanceRole"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["${each.value.arn}/*"]
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.ec2_role.name}/*"
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "apply" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id
  policy   = data.aws_iam_policy_document.bucket_policy[each.key].json

  # Ensure security settings exist before policy
  depends_on = [
    aws_s3_bucket_ownership_controls.ownership,
    aws_s3_bucket_server_side_encryption_configuration.sse,
    aws_s3_bucket_public_access_block.block_public
  ]
}

# Finally, the EC2 instances with the instance profile attached
resource "aws_instance" "ec2" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  tags = { Name = "${var.name_prefix}-ec2" }
}

# Additional EC2 instance following the same pattern
resource "aws_instance" "ec2_secondary" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[1 % length(data.aws_subnets.default.ids)]
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  tags = { Name = "${var.name_prefix}-ec2-secondary" }
}

############################
# Outputs
############################

output "instance_id" {
  value = aws_instance.ec2.id
}

output "instance_public_ip" {
  value = aws_instance.ec2.public_ip
}

output "secondary_instance_id" {
  value = aws_instance.ec2_secondary.id
}

output "secondary_instance_public_ip" {
  value = aws_instance.ec2_secondary.public_ip
}

output "bucket_names_created" {
  value = [for b in values(aws_s3_bucket.buckets) : b.bucket]
}

