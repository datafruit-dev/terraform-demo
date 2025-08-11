#!/bin/bash

# Update system
yum update -y

# Install CloudWatch agent for better logging
yum install -y amazon-cloudwatch-agent

# Ensure SSM Agent is installed and updated
yum install -y amazon-ssm-agent

# Stop SSM agent to configure it properly
systemctl stop amazon-ssm-agent

# Create SSM agent configuration directory if it doesn't exist
mkdir -p /etc/amazon/ssm

# Configure SSM agent to use the correct region
echo "${aws_region}" > /etc/amazon/ssm/region

# Start and enable SSM agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Wait for SSM agent to be fully ready and registered
echo "Waiting for SSM agent to be ready..."
for i in {1..60}; do
  if systemctl is-active --quiet amazon-ssm-agent; then
    echo "SSM agent is active"
    # Check if the agent has registered with SSM
    if sudo amazon-ssm-agent -fingerprint 2>&1 | grep -q "Instance"; then
      echo "SSM agent is registered"
      # Additional wait to ensure full registration
      sleep 20
    fi
    break
  fi
  echo "Waiting for SSM agent... attempt $i/30"
  sleep 5
done

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