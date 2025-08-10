# Image Editor Terraform Deployment

## Architecture Overview

This Terraform configuration deploys a secure, scalable image processing application on AWS EC2 with the following architecture:

```
Internet → ALB (Public Subnet) → Frontend (Private Subnet) → Backend (Private Subnet)
                                          ↓                           ↓
                                    NAT Gateway ← ← ← ← ← ← ← ← ← ← ← 
```

### Security Features
- **Backend isolation**: Only accessible from frontend, no direct internet access
- **Frontend protection**: Only accessible through ALB, not directly from internet  
- **Private subnet deployment**: Both application tiers in private subnets
- **Outbound internet access**: Through NAT Gateway for package updates

### Components
- **VPC**: Custom network with public and private subnets
- **ALB**: Application Load Balancer in public subnets for HA
- **EC2 Instances**: t3.small instances for frontend and backend
- **Security Groups**: Strict ingress/egress rules for each tier
- **NAT Gateway**: Single NAT for cost optimization (see note below)

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.0 installed
3. Update the git repository URL in `user-data/*.sh` files

## Deployment Steps

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy the infrastructure
terraform apply

# Get the application URL
terraform output app_url
```

## Important Notes

### NAT Gateway Configuration
Currently using a single NAT Gateway for cost savings. This creates:
- Single point of failure (SPOF) in one AZ
- Potential cross-AZ data transfer charges

**For production**, modify to use one NAT per AZ by updating the NAT Gateway resources in `main.tf`.

### Backend URL Configuration
The frontend needs to know the backend URL. Current approaches:
1. **Simple** (current): Hardcoded in user-data script
2. **Better**: Use AWS Systems Manager Parameter Store
3. **Best**: Use service discovery (AWS Cloud Map) or internal ALB

### SSH Access
By default, instances are only accessible via AWS Systems Manager Session Manager. To enable traditional SSH:
1. Uncomment the SSH bastion security group in `security.tf`
2. Add your IP address
3. Launch a bastion host in a public subnet

## Customization

### Instance Sizes
Edit `instance_type` in `compute.tf`:
- Development: `t3.micro` (1 vCPU, 1GB RAM)
- Current: `t3.small` (2 vCPU, 2GB RAM)  
- Production: `t3.medium` or larger

### SSL/HTTPS
To enable HTTPS:
1. Obtain an SSL certificate (AWS ACM recommended)
2. Uncomment the HTTPS listener in `alb.tf`
3. Update the certificate ARN

## Cleanup

```bash
terraform destroy
```

## Cost Considerations
- NAT Gateway: ~$45/month
- ALB: ~$25/month + data transfer
- EC2 (2x t3.small): ~$30/month
- EBS Storage: ~$2/month
- **Estimated Total**: ~$100-120/month

## Troubleshooting

### Application Not Loading
1. Check ALB target health: AWS Console → EC2 → Target Groups
2. Verify security group rules allow traffic flow
3. Check instance logs via Session Manager

### High Latency
Consider placing a NAT Gateway in each AZ if backend is in different AZ than NAT

### Package Installation Failures
Verify NAT Gateway is working and route tables are correctly configured