#!/bin/bash

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Node.js 20
curl -sL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs git

# Clone the application
cd /home/ec2-user
git clone https://github.com/datafruit-dev/image-editor.git app
cd app/frontend

# Set backend URL to use internal DNS (for server-side API routes)
echo "BACKEND_URL=http://${backend_hostname}:8080" > .env.local

# Install dependencies
npm install

# Build the application (will use the env variable)
npm run build

# Install PM2 to run the app
npm install -g pm2

# Start the application with PM2
pm2 start npm --name "frontend" -- start
pm2 startup systemd -u ec2-user --hp /home/ec2-user
pm2 save