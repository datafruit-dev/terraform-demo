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

# Set variables from Terraform
REGION="${region}"
ACCOUNT_ID="${account_id}"

# Login to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Pull and run the backend container
docker pull $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/image-editor-backend:latest
docker run -d --name backend --restart unless-stopped -p 8080:8080 $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/image-editor-backend:latest

# Create systemd service to manage the container
cat > /etc/systemd/system/backend.service << EOF
[Unit]
Description=Image Editor Backend Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start backend
ExecStop=/usr/bin/docker stop backend
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl daemon-reload
systemctl enable backend