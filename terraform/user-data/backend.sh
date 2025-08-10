#!/bin/bash

# Update system
yum update -y

# Install Python 3.11 and development tools
yum install -y python3.11 python3.11-pip git

# Install system dependencies for Pillow
yum install -y gcc python3-devel libjpeg-devel zlib-devel

# Clone the application
cd /home/ec2-user
git clone https://github.com/datafruit-dev/image-editor.git app
cd app/backend

# Create virtual environment
python3.11 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install fastapi uvicorn pillow numpy psutil python-multipart aiofiles

# Create systemd service for the backend
cat > /etc/systemd/system/backend.service << EOF
[Unit]
Description=Image Editor Backend
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/app/backend
Environment="PATH=/home/ec2-user/app/backend/venv/bin"
ExecStart=/home/ec2-user/app/backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start and enable the service
systemctl daemon-reload
systemctl start backend
systemctl enable backend