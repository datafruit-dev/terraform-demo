# EC2 to EKS Migration Guide

## Overview
This document describes the migration from EC2-based deployment to Amazon EKS (Elastic Kubernetes Service) for the image-editor application.

## Architecture Changes

### Previous Architecture (EC2-based)
- 2 EC2 instances (t3.small) running in private subnet
- Backend service on one EC2 instance
- Frontend service on another EC2 instance
- Application Load Balancer in public subnets
- Manual scaling and deployment via SSM

### New Architecture (EKS-based)
- EKS cluster with managed node group
- 2-4 worker nodes (t3.small) with auto-scaling
- Backend and Frontend services running as Kubernetes Deployments
- Horizontal Pod Autoscaler for automatic scaling
- Same VPC, subnets, and security group policies maintained
- AWS Load Balancer Controller for Ingress management

## Benefits of Migration

### Scalability
- **Horizontal Pod Autoscaler**: Automatically scales pods based on CPU/memory usage
- **Cluster Autoscaler**: Can automatically add/remove nodes based on demand
- **Rolling Updates**: Zero-downtime deployments with automatic rollback capability

### Reliability
- **Self-healing**: Kubernetes automatically restarts failed containers
- **Health Checks**: Built-in liveness and readiness probes
- **Pod Distribution**: Pods spread across multiple nodes for high availability
- **Service Discovery**: Internal DNS for service-to-service communication

### Operational Excellence
- **Declarative Configuration**: Infrastructure as code with Kubernetes manifests
- **Version Control**: Easy rollback to previous versions
- **Resource Management**: Better CPU/memory allocation and limits
- **Monitoring**: Better integration with CloudWatch Container Insights

## Migration Steps

### 1. Deploy EKS Infrastructure

```bash
cd terraform-demo/terraform

# Initialize Terraform
terraform init

# Review changes
terraform plan

# Apply EKS infrastructure
terraform apply
```

### 2. Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name image-editor-cluster

# Verify connection
kubectl get nodes
```

### 3. Install AWS Load Balancer Controller

```bash
cd terraform-demo/scripts
./setup-alb-controller.sh
```

### 4. Deploy Application

```bash
# Deploy all Kubernetes resources
./deploy-k8s-resources.sh

# Or deploy manually
kubectl apply -f ../k8s-manifests/namespace.yaml
kubectl apply -f ../k8s-manifests/backend-deployment.yaml
kubectl apply -f ../k8s-manifests/frontend-deployment.yaml
kubectl apply -f ../k8s-manifests/hpa.yaml
kubectl apply -f ../k8s-manifests/ingress.yaml
```

### 5. Verify Deployment

```bash
# Check pods
kubectl get pods -n image-editor

# Check services
kubectl get svc -n image-editor

# Check ingress/ALB
kubectl get ingress -n image-editor

# Get application URL
kubectl get ingress -n image-editor -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

## Network and Security

### Maintained from EC2 Setup
- Same VPC configuration (10.0.0.0/16)
- Same subnet structure (2 public, 1 private)
- Same NAT Gateway for outbound internet access
- Same security group policies for ALB

### New Security Groups
- **EKS Cluster Security Group**: Controls access to EKS control plane
- **EKS Nodes Security Group**: Controls access to worker nodes
  - Allows ALB to reach pods on NodePort range (30000-32767)
  - Allows inter-node communication
  - Maintains same outbound rules as EC2 instances

## CI/CD Updates

### GitHub Actions Workflow
The new workflow (`deploy-to-eks.yml`) provides:
- Automated Docker image builds and push to ECR
- Kubernetes deployment with rolling updates
- Automatic rollback on failure
- Support for component-specific deployments (backend/frontend/both)

### Deployment Command
```yaml
# Manual deployment
workflow_dispatch:
  inputs:
    component: backend|frontend|both
    environment: production|staging

# Automatic deployment on push to main
on:
  push:
    branches: [main]
```

## Monitoring and Logging

### CloudWatch Container Insights
```bash
# Enable Container Insights (optional)
aws eks update-cluster-config \
  --name image-editor-cluster \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

### Application Logs
```bash
# View backend logs
kubectl logs -n image-editor -l app=backend --tail=100 -f

# View frontend logs
kubectl logs -n image-editor -l app=frontend --tail=100 -f
```

## Scaling Configuration

### Horizontal Pod Autoscaler
- **Backend**: 2-10 replicas, scales at 70% CPU or 80% memory
- **Frontend**: 2-10 replicas, scales at 70% CPU or 80% memory

### Manual Scaling
```bash
# Scale backend
kubectl scale deployment backend -n image-editor --replicas=4

# Scale frontend
kubectl scale deployment frontend -n image-editor --replicas=4
```

## Rollback Procedures

### Application Rollback
```bash
# View rollout history
kubectl rollout history deployment/backend -n image-editor

# Rollback to previous version
kubectl rollout undo deployment/backend -n image-editor

# Rollback to specific revision
kubectl rollout undo deployment/backend -n image-editor --to-revision=2
```

### Infrastructure Rollback
```bash
# If EKS deployment fails, revert to EC2
cd terraform-demo/terraform
mv compute.tf.old compute.tf
rm eks.tf
terraform apply
```

## Cost Comparison

### EC2-based (Previous)
- 2x t3.small instances: ~$30/month
- ALB: ~$20/month
- NAT Gateway: ~$45/month
- **Total**: ~$95/month

### EKS-based (New)
- EKS Control Plane: $73/month
- 2x t3.small nodes (min): ~$30/month
- ALB: ~$20/month
- NAT Gateway: ~$45/month
- **Total**: ~$168/month

**Note**: EKS provides better scalability and reliability. Costs can be optimized with:
- Spot instances for worker nodes (up to 70% savings)
- Fargate for serverless containers
- Reserved Instances for predictable workloads

## Troubleshooting

### Common Issues

1. **Pods not starting**
```bash
kubectl describe pod <pod-name> -n image-editor
kubectl logs <pod-name> -n image-editor
```

2. **ALB not created**
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

3. **Cannot pull images from ECR**
```bash
# Verify node IAM role has ECR permissions
aws iam get-role --role-name image-editor-eks-node-group-role
```

4. **Service unavailable**
```bash
# Check service endpoints
kubectl get endpoints -n image-editor
```

## Cleanup

To remove all resources:

```bash
# Delete Kubernetes resources
kubectl delete namespace image-editor

# Destroy EKS infrastructure
cd terraform-demo/terraform
terraform destroy -target=aws_eks_cluster.main -target=aws_eks_node_group.main
terraform destroy
```

## Support

For issues or questions:
1. Check EKS cluster logs in CloudWatch
2. Review pod logs with kubectl
3. Verify security group rules
4. Ensure IAM roles have correct permissions