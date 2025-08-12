# Terraform Infrastructure for Image Editor

This repository contains the Terraform configuration for deploying the image-editor application infrastructure on AWS.

## 🚀 Current Architecture: Amazon EKS

The application is now deployed on Amazon EKS (Elastic Kubernetes Service) for better scalability, reliability, and management.

### Infrastructure Components

- **Amazon EKS Cluster**: Managed Kubernetes control plane
- **EKS Node Group**: Auto-scaling group of EC2 instances (t3.medium)
- **VPC and Networking**: Custom VPC with public/private subnets
- **Amazon ECR**: Container registry for Docker images
- **AWS Load Balancer Controller**: Manages ALB for ingress
- **IAM Roles**: IRSA for fine-grained permissions

### Quick Start

1. **Deploy Infrastructure**
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

2. **Install AWS Load Balancer Controller**
   ```bash
   cd scripts
   ./install-aws-load-balancer-controller.sh
   ```

3. **Deploy Applications**
   ```bash
   ./deploy-k8s-manifests.sh
   ```

## 📁 Repository Structure

```
.
├── terraform/                 # Terraform configuration files
│   ├── main.tf               # Provider and backend configuration
│   ├── variables.tf          # Input variables
│   ├── network.tf            # VPC, subnets, security groups
│   ├── eks.tf                # EKS cluster and node group
│   ├── ecr.tf                # ECR repositories
│   ├── outputs.tf            # Output values
│   └── iam-policies/         # IAM policy documents
├── k8s-manifests/            # Kubernetes manifests
│   ├── namespace.yaml        # Application namespace
│   ├── backend-deployment.yaml
│   ├── frontend-deployment.yaml
│   └── ingress.yaml          # ALB ingress configuration
├── scripts/                  # Deployment scripts
│   ├── install-aws-load-balancer-controller.sh
│   └── deploy-k8s-manifests.sh
└── EKS_MIGRATION_GUIDE.md    # Detailed migration documentation
```

## 🔧 Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl
- Helm (for AWS Load Balancer Controller)

## 🚢 Deployment

### Using GitHub Actions

The image-editor repository includes a GitHub Actions workflow that automatically:
1. Builds Docker images
2. Pushes to ECR
3. Deploys to EKS

### Manual Deployment

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name image-editor-cluster

# Deploy or update applications
kubectl apply -f k8s-manifests/
```

## 📊 Monitoring

```bash
# Check cluster status
kubectl get nodes

# Check application status
kubectl get all -n image-editor

# View application logs
kubectl logs -f deployment/backend -n image-editor
kubectl logs -f deployment/frontend -n image-editor

# Get application URL
kubectl get ingress -n image-editor
```

## 🧹 Cleanup

```bash
# Delete Kubernetes resources
kubectl delete namespace image-editor

# Destroy infrastructure
cd terraform
terraform destroy
```

## 📚 Documentation

- [EKS Migration Guide](./EKS_MIGRATION_GUIDE.md) - Detailed migration documentation
- [Terraform Documentation](https://www.terraform.io/docs)
- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## 🔐 Security

- All resources are deployed in a custom VPC
- Private subnets for compute resources
- Security groups with least privilege access
- IAM roles with minimal required permissions
- Container image scanning enabled in ECR

## 💰 Cost Optimization

- Using t3.medium instances for cost-effectiveness
- Node group auto-scaling for optimal resource usage
- Consider Spot instances for non-critical workloads
- Regular review of unused resources

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Test the deployment
4. Submit a pull request

## 📝 License

This project is for demonstration purposes.