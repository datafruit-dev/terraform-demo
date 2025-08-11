#!/bin/bash

# Update system
yum update -y

# Install and start SSM Agent (should be pre-installed on AL2023, but ensure it's running)
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Wait for SSM agent to be ready
sleep 10
systemctl status amazon-ssm-agent

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

# Pull the latest frontend image from ECR
docker pull ${ecr_frontend_repository}:latest

# Create systemd service for the frontend container
cat > /etc/systemd/system/frontend.service << EOF
[Unit]
Description=Image Editor Frontend Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=10
Environment="BACKEND_URL=http://${backend_hostname}:8080"
ExecStartPre=-/usr/bin/docker stop frontend
ExecStartPre=-/usr/bin/docker rm frontend
ExecStartPre=/usr/bin/docker pull ${ecr_frontend_repository}:latest
ExecStart=/usr/bin/docker run --name frontend \
  --rm \
  -p 3000:3000 \
  -e BACKEND_URL=http://${backend_hostname}:8080 \
  ${ecr_frontend_repository}:latest
ExecStop=/usr/bin/docker stop frontend

[Install]
WantedBy=multi-user.target
EOF

# Start and enable the service
systemctl daemon-reload
systemctl start frontend
systemctl enable frontend