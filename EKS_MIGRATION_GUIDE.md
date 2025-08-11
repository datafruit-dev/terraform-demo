# EC2 to EKS Migration Guide

## Overview
This guide documents the migration process from EC2-based deployment to Amazon EKS (Elastic Kubernetes Service) for the image-editor application.

## Architecture Changes

### Previous Architecture (EC2)
- **Frontend**: Single EC2 instance running Next.js in Docker
- **Backend**: Single EC2 instance running FastAPI in Docker
- **Load Balancer**: Application Load Balancer (ALB) routing to EC2 instances
- **Networking**: VPC with public/private subnets
- **Deployment**: GitHub Actions using SSM to deploy to EC2

### New Architecture (EKS)
- **Frontend**: Kubernetes Deployment with 2+ replicas
- **Backend**: Kubernetes Deployment with 2+ replicas
- **Load Balancer**: AWS Load Balancer Controller managing ALB via Ingress
- **Networking**: Same VPC, utilizing EKS cluster
- **Auto-scaling**: Horizontal Pod Autoscaler (HPA) for dynamic scaling
- **Deployment**: GitHub Actions using kubectl to deploy to EKS

## Benefits of Migration

1. **High Availability**: Multiple replicas across availability zones
2. **Auto-scaling**: Automatic scaling based on CPU/memory metrics
3. **Rolling Updates**: Zero-downtime deployments with rollback capability
4. **Resource Efficiency**: Better resource utilization with container orchestration
5. **Simplified Management**: Kubernetes handles container lifecycle
6. **Cost Optimization**: Scale down during low traffic periods

## Prerequisites

### Local Tools Required
```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install AWS CLI (if not already installed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### AWS Resources Required
- AWS Account with appropriate permissions
- ECR repositories (already exist from EC2 setup)
- VPC and subnets (already exist from EC2 setup)

## Migration Steps

### Step 1: Deploy EKS Infrastructure

```bash
cd terraform-demo/terraform
terraform init
terraform plan
terraform apply
```

This will create:
- EKS Cluster
- EKS Node Group (2-4 t3.medium instances)
- IAM roles and policies for EKS
- OIDC provider for IRSA
- AWS Load Balancer Controller IAM role

### Step 2: Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name image-editor-cluster
kubectl get nodes  # Verify connection
```

### Step 3: Deploy Applications to EKS

Run the setup script:
```bash
cd terraform-demo/scripts
./setup-eks-cluster.sh
```

Or manually deploy:
```bash
# Create namespace
kubectl apply -f terraform-demo/k8s-manifests/namespace.yaml

# Install metrics server for HPA
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=image-editor-cluster \
  --set serviceAccount.create=true \
  --set region=us-east-1

# Deploy applications
kubectl apply -f terraform-demo/k8s-manifests/backend-deployment.yaml
kubectl apply -f terraform-demo/k8s-manifests/frontend-deployment.yaml
kubectl apply -f terraform-demo/k8s-manifests/ingress.yaml
kubectl apply -f terraform-demo/k8s-manifests/hpa.yaml
```

### Step 4: Verify Deployment

```bash
# Check pods
kubectl get pods -n image-editor

# Check services
kubectl get svc -n image-editor

# Get Load Balancer URL
kubectl get ingress -n image-editor
```

### Step 5: Update CI/CD Pipeline

Update your GitHub repository to use the new workflow:
- Use `.github/workflows/deploy-to-eks.yml` instead of `deploy-to-ec2.yml`
- The new workflow will build images and deploy to EKS

### Step 6: DNS Update

Once the new Load Balancer is ready:
1. Get the new ALB DNS name from the Ingress
2. Update your DNS records to point to the new ALB
3. Test the application thoroughly

### Step 7: Decommission EC2 Resources (Optional)

After confirming EKS deployment is stable:

```bash
# Remove EC2-specific resources from Terraform
# Comment out or delete:
# - compute.tf
# - EC2-related security groups in network.tf

# Apply changes
terraform plan
terraform apply
```

## Monitoring and Maintenance

### View Logs
```bash
# Backend logs
kubectl logs -f deployment/image-editor-backend -n image-editor

# Frontend logs
kubectl logs -f deployment/image-editor-frontend -n image-editor
```

### Scale Manually
```bash
# Scale backend
kubectl scale deployment/image-editor-backend --replicas=5 -n image-editor

# Scale frontend
kubectl scale deployment/image-editor-frontend --replicas=5 -n image-editor
```

### Update Deployments
```bash
# Update backend image
kubectl set image deployment/image-editor-backend \
  backend=642375200181.dkr.ecr.us-east-1.amazonaws.com/image-editor-backend:new-tag \
  -n image-editor

# Check rollout status
kubectl rollout status deployment/image-editor-backend -n image-editor
```

### Rollback if Needed
```bash
# Rollback to previous version
kubectl rollout undo deployment/image-editor-backend -n image-editor
```

## Cost Comparison

### EC2 Setup (Monthly Estimate)
- 2x t3.small instances: ~$30
- ALB: ~$20
- NAT Gateway: ~$45
- **Total: ~$95/month**

### EKS Setup (Monthly Estimate)
- EKS Cluster: $73
- 2x t3.medium instances (Node Group): ~$60
- ALB: ~$20
- NAT Gateway: ~$45
- **Total: ~$198/month**

*Note: EKS provides better scalability and reliability. Costs can be optimized with Spot instances and auto-scaling.*

## Troubleshooting

### Pods Not Starting
```bash
kubectl describe pod <pod-name> -n image-editor
kubectl logs <pod-name> -n image-editor
```

### Ingress Not Getting Address
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### Node Issues
```bash
kubectl describe node <node-name>
kubectl get events -n image-editor
```

## Rollback Plan

If you need to rollback to EC2:
1. Keep EC2 infrastructure running during migration
2. Update DNS to point back to old ALB
3. Stop EKS deployments: `kubectl scale deployment --all --replicas=0 -n image-editor`
4. Destroy EKS cluster if needed: `terraform destroy -target=aws_eks_cluster.main`

## Security Considerations

1. **Network Isolation**: Pods run in private subnets
2. **IAM Roles**: Using IRSA for fine-grained permissions
3. **Secrets Management**: Use Kubernetes Secrets or AWS Secrets Manager
4. **Image Scanning**: ECR scanning enabled for vulnerability detection
5. **RBAC**: Implement Kubernetes RBAC for access control

## Next Steps

1. **Add SSL/TLS**: Configure ACM certificate for HTTPS
2. **Implement GitOps**: Use ArgoCD or Flux for declarative deployments
3. **Add Monitoring**: Deploy Prometheus and Grafana for metrics
4. **Add Logging**: Implement centralized logging with CloudWatch or ELK
5. **Backup Strategy**: Implement Velero for cluster backup