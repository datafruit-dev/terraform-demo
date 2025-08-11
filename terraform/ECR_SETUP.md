# ECR Setup for Image Editor Application

## Overview
This Terraform configuration now includes Amazon Elastic Container Registry (ECR) repositories for storing Docker images of the image-editor application. The EC2 instances are configured to pull and run Docker containers from these ECR repositories.

## ECR Repositories Created

1. **Backend Repository**: `image-editor-backend`
   - Stores Docker images for the FastAPI backend application
   - Repository URL available in output: `ecr_backend_repository_url`

2. **Frontend Repository**: `image-editor-frontend`
   - Stores Docker images for the Next.js frontend application
   - Repository URL available in output: `ecr_frontend_repository_url`

## Features

### Security & Access Control
- EC2 instances have IAM permissions to pull images from ECR
- Repository policies restrict access to authorized EC2 instances
- Image vulnerability scanning enabled by default

### Cost Optimization
- Lifecycle policies automatically remove old images (keeps last 10 by default)
- Configurable via `ecr_image_count` variable

### EC2 Instance Configuration
- EC2 instances now use Docker to run applications
- Automatic Docker installation and configuration via user-data scripts
- Systemd services manage Docker containers for high availability
- Automatic container restart on failure

## Deployment Process

### 1. Deploy Infrastructure
```bash
cd terraform-demo/terraform
terraform init
terraform plan
terraform apply
```

### 2. Push Images to ECR
The GitHub Actions workflow in the image-editor repository will automatically:
- Build Docker images for frontend and backend
- Push images to the ECR repositories
- Tag images with commit SHA and 'latest'

### 3. EC2 Instance Behavior
When EC2 instances launch, they will:
1. Install Docker and AWS CLI
2. Authenticate with ECR using IAM role credentials
3. Pull the latest images from ECR
4. Run containers as systemd services
5. Automatically restart containers if they fail

## Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for resources | us-east-1 |
| `ecr_image_count` | Number of images to keep in ECR | 10 |
| `enable_ecr_scanning` | Enable vulnerability scanning | true |

## Accessing ECR Repositories

### Via AWS CLI
```bash
# Get login token
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <registry-url>

# Pull an image
docker pull <repository-url>:latest

# Push an image
docker tag my-image:latest <repository-url>:latest
docker push <repository-url>:latest
```

### Via GitHub Actions
The workflow uses AWS credentials stored as GitHub secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Monitoring & Troubleshooting

### Check Container Status on EC2
```bash
# Connect to EC2 instance via Session Manager
aws ssm start-session --target <instance-id>

# Check service status
sudo systemctl status backend
sudo systemctl status frontend

# View logs
sudo journalctl -u backend -f
sudo journalctl -u frontend -f

# Check Docker containers
sudo docker ps
sudo docker logs backend
sudo docker logs frontend
```

### ECR Repository Metrics
- Monitor image push/pull metrics in CloudWatch
- Review vulnerability scan results in ECR console
- Check repository size and image count

## Updates & Maintenance

### Updating Container Images
1. Push new images to ECR (via GitHub Actions or manually)
2. Restart services on EC2 instances:
   ```bash
   sudo systemctl restart backend
   sudo systemctl restart frontend
   ```

### Changing ECR Settings
Update variables in `terraform.tfvars` or via command line:
```bash
terraform apply -var="ecr_image_count=20"
```

## Security Best Practices
1. Regularly review and patch vulnerabilities found by ECR scanning
2. Use specific image tags in production (not 'latest')
3. Implement least-privilege IAM policies
4. Enable CloudTrail logging for ECR API calls
5. Consider using ECR image immutability for production repositories