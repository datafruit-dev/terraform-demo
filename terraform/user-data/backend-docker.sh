#!/bin/bash

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install AWS CLI (needed for ECR authentication)
yum install -y aws-cli

# Get ECR login token and login to Docker
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}

# Pull the latest backend image from ECR
docker pull ${ecr_backend_repository}:latest

# Create systemd service for the backend container
cat > /etc/systemd/system/backend.service << EOF
[Unit]
Description=Image Editor Backend Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/docker stop backend
ExecStartPre=-/usr/bin/docker rm backend
ExecStartPre=/usr/bin/docker pull ${ecr_backend_repository}:latest
ExecStart=/usr/bin/docker run --name backend \
  --rm \
  -p 8080:8080 \
  ${ecr_backend_repository}:latest
ExecStop=/usr/bin/docker stop backend

[Install]
WantedBy=multi-user.target
EOF

# Start and enable the service
systemctl daemon-reload
systemctl start backend
systemctl enable backend