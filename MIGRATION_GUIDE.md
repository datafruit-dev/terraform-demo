# Migration Guide: EC2 to EKS

This guide provides step-by-step instructions for migrating the Image Editor application from EC2 instances to Amazon EKS.

## Overview

The migration involves:
1. Deploying the EKS infrastructure alongside existing EC2 infrastructure
2. Deploying the application to EKS
3. Testing the EKS deployment
4. Switching traffic to EKS
5. Decommissioning EC2 resources (optional)

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed (>= 1.0)
- kubectl installed (>= 1.30)
- helm installed (>= 3.0)
- Access to both repositories:
  - `terraform-demo` (infrastructure)
  - `image-editor` (application)

## Phase 1: Deploy EKS Infrastructure

### Step 1: Update Terraform Configuration

The EKS configuration has already been added to the Terraform files. The new files include:
- `eks.tf` - EKS cluster, node groups, and IAM roles
- `policies/aws-load-balancer-controller-policy.json` - IAM policy for ALB controller
- Updated `network.tf` - Subnet tags for EKS
- Updated `variables.tf` - EKS configuration variables

### Step 2: Apply Terraform Changes

```bash
cd terraform-demo/terraform

# Initialize Terraform (to download new providers)
terraform init -upgrade

# Review the changes
terraform plan

# Apply the changes (this will create EKS resources)
terraform apply
```

This will create:
- EKS cluster
- Managed node group with 2 nodes
- IAM roles and policies
- OIDC provider for IRSA
- EBS CSI driver addon

**Note**: EKS cluster creation takes 10-15 minutes.

### Step 3: Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name image-editor-cluster

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### Step 4: Install AWS Load Balancer Controller

```bash
# Add Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get required values from Terraform
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
  --set vpcId=${VPC_ID} \
  --wait

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
```

## Phase 2: Deploy Application to EKS

### Option A: Using GitHub Actions (Recommended)

1. Push changes to the main branch:
```bash
cd image-editor
git add .
git commit -m "Add EKS deployment configuration"
git push origin main
```

2. The GitHub Actions workflow will automatically:
   - Build and push Docker images to ECR
   - Deploy to EKS cluster
   - Create ALB via Ingress

3. Monitor the deployment in GitHub Actions UI

### Option B: Manual Deployment

```bash
cd image-editor

# Deploy all resources
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/ingress.yaml

# Wait for deployments
kubectl rollout status deployment/backend -n image-editor
kubectl rollout status deployment/frontend -n image-editor

# Get ALB URL
kubectl get ingress image-editor-ingress -n image-editor
```

## Phase 3: Verify EKS Deployment

### Step 1: Check Resource Status

```bash
# Check deployments
kubectl get deployments -n image-editor

# Check pods
kubectl get pods -n image-editor

# Check services
kubectl get services -n image-editor

# Check ingress (ALB)
kubectl get ingress -n image-editor
```

### Step 2: Test Application

```bash
# Get the ALB URL
ALB_URL=$(kubectl get ingress image-editor-ingress -n image-editor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Application URL: http://$ALB_URL"

# Test the application
curl -I http://$ALB_URL
```

### Step 3: Verify Functionality

1. Open the ALB URL in a browser
2. Test image upload and processing
3. Verify both frontend and backend are working

## Phase 4: Traffic Migration

### Option 1: DNS Switch (Recommended for Production)

If using Route53 or custom domain:

1. Create a new CNAME record pointing to the EKS ALB
2. Test with the new domain
3. Update the main domain to point to EKS ALB
4. Monitor for issues

### Option 2: Direct Cutover

1. Note down both ALB URLs:
   - EC2 ALB: `terraform output app_url`
   - EKS ALB: From kubectl get ingress

2. Update any references to use the EKS ALB URL

## Phase 5: Monitor and Validate

### Monitoring Commands

```bash
# Watch pods
kubectl get pods -n image-editor -w

# Check logs
kubectl logs -l app=backend -n image-editor --tail=100
kubectl logs -l app=frontend -n image-editor --tail=100

# Check metrics
kubectl top nodes
kubectl top pods -n image-editor
```

### Performance Comparison

Compare metrics between EC2 and EKS:
- Response times
- Error rates
- Resource utilization
- Cost

## Phase 6: Cleanup (Optional)

Once confident with EKS deployment, you can remove EC2 resources.

### Option 1: Keep Both (Recommended Initially)

Keep both deployments running for rollback capability.

### Option 2: Remove EC2 Resources Only

```bash
cd terraform-demo/terraform

# Comment out or remove from Terraform files:
# - compute.tf (EC2 instances)
# - ALB resources for EC2

# Apply changes
terraform plan
terraform apply
```

### Option 3: Full Cleanup

To remove everything:

```bash
# Delete Kubernetes resources first
kubectl delete namespace image-editor

# Uninstall AWS Load Balancer Controller
helm uninstall aws-load-balancer-controller -n kube-system

# Destroy all Terraform resources
terraform destroy
```

## Rollback Plan

If issues occur during migration:

### Quick Rollback to EC2

1. The EC2 infrastructure remains intact if not removed
2. Simply point traffic back to the EC2 ALB
3. Investigate and fix EKS issues

### EKS Rollback

```bash
# Rollback deployment to previous version
kubectl rollout undo deployment/backend -n image-editor
kubectl rollout undo deployment/frontend -n image-editor

# Check rollout status
kubectl rollout status deployment/backend -n image-editor
kubectl rollout status deployment/frontend -n image-editor
```

## Troubleshooting

### Common Issues and Solutions

#### Pods not starting
```bash
kubectl describe pod <pod-name> -n image-editor
kubectl logs <pod-name> -n image-editor
```

#### ALB not created
```bash
kubectl describe ingress image-editor-ingress -n image-editor
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

#### Image pull errors
```bash
# Verify ECR access
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 642375200181.dkr.ecr.us-east-1.amazonaws.com

# Check node IAM role has ECR permissions
kubectl describe pod <pod-name> -n image-editor | grep -A 10 Events
```

#### Connection issues between services
```bash
# Test service discovery
kubectl run test-pod --image=busybox -it --rm --restart=Never -n image-editor -- wget -qO- http://backend:8080/health
```

## Benefits of EKS Migration

### Advantages
- **Auto-scaling**: HPA and Cluster Autoscaler support
- **Self-healing**: Automatic pod restarts and rescheduling
- **Rolling updates**: Zero-downtime deployments
- **Better resource utilization**: Multiple apps on same nodes
- **Standardization**: Kubernetes ecosystem and tools
- **Portability**: Easier to move between cloud providers

### Considerations
- **Higher complexity**: Requires Kubernetes knowledge
- **Higher base cost**: EKS control plane fee ($73/month)
- **Learning curve**: Team needs Kubernetes skills

## Post-Migration Tasks

1. **Set up monitoring**: CloudWatch Container Insights or Prometheus
2. **Configure auto-scaling**: HPA and Cluster Autoscaler
3. **Implement CI/CD**: Enhance GitHub Actions workflows
4. **Add health checks**: Improve liveness and readiness probes
5. **Security scanning**: Enable ECR scanning and pod security policies
6. **Backup strategy**: Implement Velero or similar for cluster backup

## Support and Resources

- [EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)