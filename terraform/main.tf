terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket  = "terraform-state-bucket-datafruit-demo"
    key     = "terraform-demo/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Fetch all available AWS availability zones in the current region
# This ensures we're using active AZs and makes the infrastructure portable
data "aws_availability_zones" "available" {
  state = "available"
}

# Fetch the most recent Amazon Linux 2023 AMI
# AL2023 is the latest generation Amazon Linux with improved performance and security
# It comes with systemd, DNF package manager, and better container support
data "aws_ami" "amazon_linux_2023" {
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
}