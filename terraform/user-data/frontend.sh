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

# Pull and run the frontend container with backend URL
docker pull $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/image-editor-frontend:latest
docker run -d --name frontend --restart unless-stopped -p 3000:3000 \
  -e BACKEND_URL=http://${backend_hostname}:8080 \
  $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/image-editor-frontend:latest

# Create systemd service to manage the container
cat > /etc/systemd/system/frontend.service << EOF
[Unit]
Description=Image Editor Frontend Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start frontend
ExecStop=/usr/bin/docker stop frontend
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl daemon-reload
systemctl enable frontend