# =============================================================================
# LOCAL VARIABLES
# =============================================================================

locals {
  internal_domain  = "internal.local"
  backend_hostname = "backend.${local.internal_domain}"
}

# =============================================================================
# NETWORKING - VPC
# =============================================================================

# Virtual Private Cloud (VPC)
# This creates an isolated network environment for our application
# Using 10.0.0.0/16 gives us 65,536 IP addresses to work with
# DNS support is enabled for internal service discovery
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "image-editor-vpc"
  }
}

# Internet Gateway
# This provides internet connectivity for resources in public subnets
# Required for the ALB to receive traffic from the internet
# Also enables outbound internet access for resources in public subnets
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "image-editor-igw"
  }
}

# =============================================================================
# NETWORKING - SUBNETS
# =============================================================================

# Public Subnets (2 required for ALB high availability)
# These subnets will host the Application Load Balancer
# They have direct routes to the Internet Gateway for public access
# Using /24 subnet mask gives 256 IPs per subnet (AWS reserves 5 per subnet)
# Spread across 2 AZs for high availability as required by ALB
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, count.index) # 10.0.0.0/24, 10.0.1.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true # Auto-assign public IPs to instances launched here

  tags = {
    Name = "image-editor-public-subnet-${count.index + 1}"
    Type = "Public"
  }
}

# Private Subnet for Frontend and Backend EC2 instances
# This subnet has no direct internet route - only through NAT Gateway
# This provides security by preventing direct inbound connections from internet
# Both frontend and backend servers will be placed here for protection
# Using offset of 10 to clearly separate from public subnet ranges
# Single subnet simplifies architecture and reduces cross-AZ data transfer costs
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, 10) # 10.0.10.0/24
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "image-editor-private-subnet"
    Type = "Private"
  }
}

# =============================================================================
# NETWORKING - NAT GATEWAY
# =============================================================================

# Elastic IP for NAT Gateway
# This provides a static public IP address for the NAT Gateway
# Ensures consistent outbound IP for services that might whitelist our traffic
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "image-editor-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway
# Enables outbound internet connectivity for resources in private subnets
# Required for EC2 instances to download packages, Docker images, etc.
# Placed in public subnet so it can reach the Internet Gateway
#
# NOTE: Cost-saving but a single-AZ SPOF and can incur cross-AZ data charges
# if we eventually add another private subnet in another AZ. Best practice
# for prod: one NAT per AZ and route each private subnet to its local NAT.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "image-editor-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# NETWORKING - ROUTE TABLES
# =============================================================================

# Route Table for Public Subnets
# Directs all non-local traffic (0.0.0.0/0) to the Internet Gateway
# This enables both inbound and outbound internet connectivity
# Local traffic within VPC (10.0.0.0/16) is automatically routed
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "image-editor-public-rt"
  }
}

# Route Table for Private Subnets
# Directs all non-local traffic (0.0.0.0/0) to the NAT Gateway
# This enables outbound-only internet connectivity (no inbound initiation)
# Essential for instances to download updates while remaining protected
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "image-editor-private-rt"
  }
}

# Route Table Associations for Public Subnets
# Links each public subnet to the public route table
# Without this, subnets would only have access to the default VPC route table
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Table Association for Private Subnet
# Links the private subnet to the private route table
# Ensures private subnet traffic goes through NAT for internet access
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
# =============================================================================
# SECURITY GROUPS
# =============================================================================

# Security Group for Application Load Balancer
# This is the only security group that allows inbound traffic from the internet
# Acts as the first line of defense for the application
# Only allows HTTP (80) and HTTPS (443) traffic from anywhere
# Egress is limited to the frontend security group on port 3000
resource "aws_security_group" "alb" {
  name        = "image-editor-alb-sg"
  description = "Security group for Application Load Balancer - allows HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "image-editor-alb-sg"
    Type = "ALB"
  }
}

# Security Group for Frontend EC2 Instance
# Only accepts traffic from the ALB, not directly from internet
# This implements the security requirement that frontend is not directly accessible
# Can communicate with backend for API calls
resource "aws_security_group" "frontend" {
  name        = "image-editor-frontend-sg"
  description = "Security group for Frontend EC2 - only allows traffic from ALB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "image-editor-frontend-sg"
    Type = "Frontend"
  }
}

# Security Group for Backend (FastAPI) EC2 Instance
# Most restricted security group - only accepts traffic from frontend
# This implements the security requirement that backend is isolated
resource "aws_security_group" "backend" {
  name        = "image-editor-backend-sg"
  description = "Security group for Backend EC2 - only allows traffic from Frontend"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "image-editor-backend-sg"
    Type = "Backend"
  }
}

# =============================================================================
# SECURITY GROUP RULES
# =============================================================================

# -----------------------------------------------------------------------------
# ALB Security Group Rules
# -----------------------------------------------------------------------------

# ALB Ingress: HTTP from Internet
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from Internet"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# ALB Ingress: HTTPS from Internet
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from Internet"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# ALB Egress: To Frontend on port 3000
resource "aws_vpc_security_group_egress_rule" "alb_to_frontend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow ALB to communicate with Frontend"
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.frontend.id
}

# -----------------------------------------------------------------------------
# Frontend Security Group Rules
# -----------------------------------------------------------------------------

# Frontend Ingress: From ALB on port 3000
resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "Next.js port from ALB"
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

# Frontend Egress: HTTPS to Internet
resource "aws_vpc_security_group_egress_rule" "frontend_https_out" {
  security_group_id = aws_security_group.frontend.id
  description       = "HTTPS to Internet for updates"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Frontend Egress: HTTP to Internet
resource "aws_vpc_security_group_egress_rule" "frontend_http_out" {
  security_group_id = aws_security_group.frontend.id
  description       = "HTTP to Internet for updates"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Frontend Egress: To Backend on port 8080
resource "aws_vpc_security_group_egress_rule" "frontend_to_backend" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "Allow Frontend to communicate with Backend API"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend.id
}

# -----------------------------------------------------------------------------
# Backend Security Group Rules
# -----------------------------------------------------------------------------

# Backend Ingress: From Frontend on port 8080
resource "aws_vpc_security_group_ingress_rule" "backend_from_frontend" {
  security_group_id            = aws_security_group.backend.id
  description                  = "FastAPI port from Frontend"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.frontend.id
}

# Backend Egress: HTTPS to Internet
resource "aws_vpc_security_group_egress_rule" "backend_https_out" {
  security_group_id = aws_security_group.backend.id
  description       = "HTTPS to Internet for pip packages"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Backend Egress: HTTP to Internet
resource "aws_vpc_security_group_egress_rule" "backend_http_out" {
  security_group_id = aws_security_group.backend.id
  description       = "HTTP to Internet for packages"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# INTERNAL DNS WITH ROUTE53 PRIVATE HOSTED ZONE
# =============================================================================

# Private hosted zone for internal service discovery
resource "aws_route53_zone" "internal" {
  name = local.internal_domain

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name = "image-editor-internal-dns"
  }
}

# DNS record for backend service
resource "aws_route53_record" "backend" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = local.backend_hostname
  type    = "A"
  ttl     = 300
  records = [aws_instance.backend.private_ip]
}


# =============================================================================
# OPTIONAL: SSH ACCESS (for debugging - remove in production)
# =============================================================================

# Security Group for SSH Bastion/Jump Host (Optional)
# Uncomment if you need SSH access for debugging
# In production, use AWS Systems Manager Session Manager instead
/*
resource "aws_security_group" "ssh_bastion" {
  name        = "image-editor-ssh-bastion-sg"
  description = "Security group for SSH Bastion - debugging only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from specific IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP_HERE/32"]  # Replace with your IP
  }

  egress {
    description = "SSH to private instances"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "image-editor-ssh-bastion-sg"
    Type = "Bastion"
  }
}
*/
