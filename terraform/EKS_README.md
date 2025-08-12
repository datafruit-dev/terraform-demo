# Image Editor - EKS Deployment

## Overview

This Terraform configuration deploys an Amazon EKS cluster for running the Image Editor application with Kubernetes. The setup includes a production-ready EKS cluster with managed node groups, AWS Load Balancer Controller, and all necessary IAM roles and policies.

## Architecture

```
Internet → ALB (Managed by AWS LB Controller) → Ingress → Services → Pods
                                                            ↓
                                                    ┌──────────────┐
                                                    │   Frontend   │
                                                    │  (2 replicas)│
                                                    └──────────────┘
                                                            ↓
                                                    ┌──────────────┐
                                                    │   Backend    │
                                                    │  (2 replicas)│
                                                    └──────────────┘
```

### Components

- **EKS Cluster**: Managed Kubernetes control plane (v1.30)
- **Node Group**: Managed EC2 instances (t3.medium) for running pods
- **AWS Load Balancer Controller**: Manages ALB for ingress
- **EBS CSI Driver**: Enables persistent volume support
- **OIDC Provider**: Enables IAM roles for service accounts (IRSA)
- **VPC Configuration**: Uses existing VPC with proper subnet tagging

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0
3. **kubectl** >= 1.30
4. **helm** >= 3.0
5. **Existing VPC** with properly tagged subnets (created by network.tf)

## Deployment Steps

### 1. Deploy the Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy the infrastructure (includes EKS)
terraform apply

# Get cluster details
terraform output eks_cluster_name
terraform output eks_cluster_endpoint
```

### 2. Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name image-editor-cluster

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### 3. Install AWS Load Balancer Controller

```bash
# Add the EKS Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get values from Terraform outputs
export VPC_ID=$(terraform output -raw vpc_id)
export LB_ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn)

# Install the controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=image-editor-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${LB_ROLE_ARN} \
  --set region=us-east-1 \
  --set vpcId=${VPC_ID}

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 4. Deploy the Application

The application deployment is handled by GitHub Actions, but can also be done manually:

```bash
# From the image-editor repository
cd ../../../image-editor

# Deploy using the script
./scripts/deploy-to-eks.sh

# Or manually
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/ingress.yaml
```

## Configuration Details

### EKS Cluster Configuration

- **Version**: 1.30
- **Logging**: All control plane logs enabled
- **Endpoint Access**: Both private and public enabled
- **Subnets**: Deployed across public and private subnets

### Node Group Configuration

- **Instance Type**: t3.medium
- **Capacity Type**: ON_DEMAND
- **Scaling**:
  - Desired: 2 nodes
  - Min: 1 node
  - Max: 4 nodes
- **Disk Size**: 20 GB
- **AMI Type**: Amazon Linux 2

### IAM Roles

1. **EKS Cluster Role**: Allows EKS to manage resources
2. **Node Group Role**: Allows EC2 instances to join the cluster
3. **AWS Load Balancer Controller Role**: Manages ALB resources
4. **EBS CSI Driver Role**: Manages EBS volumes for persistent storage

### Security Groups

The EKS cluster automatically manages security groups for:
- Control plane to node communication
- Node to node communication
- Pod to pod communication

### Subnet Tagging

Subnets are tagged for EKS and ALB discovery:
- Public subnets: `kubernetes.io/role/elb=1`
- Private subnets: `kubernetes.io/role/internal-elb=1`
- All subnets: `kubernetes.io/cluster/image-editor-cluster=shared`

## Monitoring and Management

### View Cluster Resources

```bash
# Nodes
kubectl get nodes

# Namespaces
kubectl get namespaces

# All resources in image-editor namespace
kubectl get all -n image-editor

# Pods with more details
kubectl get pods -n image-editor -o wide
```

### View Logs

```bash
# Backend logs
kubectl logs -l app=backend -n image-editor --tail=100

# Frontend logs
kubectl logs -l app=frontend -n image-editor --tail=100

# AWS Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Scaling

```bash
# Scale deployments manually
kubectl scale deployment backend --replicas=3 -n image-editor
kubectl scale deployment frontend --replicas=3 -n image-editor

# Scale node group (via AWS Console or CLI)
aws eks update-nodegroup-config \
  --cluster-name image-editor-cluster \
  --nodegroup-name image-editor-node-group \
  --scaling-config desiredSize=3,minSize=2,maxSize=5
```

## Cost Optimization

### Current Setup (Estimated Monthly Costs)
- **EKS Control Plane**: $73/month
- **Node Group (2x t3.medium)**: ~$60/month
- **ALB**: ~$25/month + data transfer
- **NAT Gateway**: ~$45/month
- **Total**: ~$200-250/month

### Cost Saving Options

1. **Use Spot Instances**: Change `capacity_type` to "SPOT" in eks.tf
2. **Reduce Node Size**: Use t3.small for development
3. **Scale Down**: Reduce min nodes to 1 for non-production
4. **Use Fargate**: For serverless container execution (requires configuration changes)

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n image-editor

# Check events
kubectl get events -n image-editor --sort-by='.lastTimestamp'
```

### ALB Not Created

```bash
# Check ingress status
kubectl describe ingress image-editor-ingress -n image-editor

# Check AWS LB Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### Node Issues

```bash
# Check node status
kubectl describe node <node-name>

# Check system pods
kubectl get pods -n kube-system
```

### IAM Permission Issues

```bash
# Verify OIDC provider
aws eks describe-cluster --name image-editor-cluster --query "cluster.identity.oidc.issuer"

# Check service account annotations
kubectl describe sa aws-load-balancer-controller -n kube-system
```

## Cleanup

### Remove Application
```bash
kubectl delete namespace image-editor
```

### Destroy Infrastructure
```bash
# This will destroy the EKS cluster and all resources
terraform destroy
```

**Note**: Ensure all Kubernetes resources (especially those creating AWS resources like ALBs) are deleted before running `terraform destroy` to avoid orphaned resources.

## Migration from EC2 to EKS

The infrastructure now supports both EC2 and EKS deployments. To fully migrate:

1. Deploy EKS infrastructure (already in place)
2. Deploy applications to EKS (via GitHub Actions)
3. Verify EKS deployment is working
4. Update DNS/Route53 to point to new ALB
5. Remove EC2-specific resources from Terraform (optional)

## Additional Resources

- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)