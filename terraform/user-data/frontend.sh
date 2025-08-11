#!/bin/bash

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Get AWS region from instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Pull and run the frontend container
docker pull $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/image-editor-frontend:latest

# Create systemd service for the frontend container
cat > /etc/systemd/system/frontend.service << EOF
[Unit]
Description=Image Editor Frontend Container
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStartPre=-/usr/bin/docker stop frontend
ExecStartPre=-/usr/bin/docker rm frontend
ExecStart=/usr/bin/docker run --name frontend -p 3000:3000 -e BACKEND_URL=http://${backend_hostname}:8080 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/image-editor-frontend:latest
ExecStop=/usr/bin/docker stop frontend

[Install]
WantedBy=multi-user.target
EOF

# Start and enable the service
systemctl daemon-reload
systemctl start frontend
systemctl enable frontend