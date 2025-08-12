# Migration from EC2 to EKS

This document describes the changes made to migrate the image-editor application from EC2 instances to Amazon EKS (Elastic Kubernetes Service).

## Architecture Changes

### Previous Architecture (EC2-based)
- 2 EC2 instances (frontend and backend) in private subnets
- Application Load Balancer in public subnets
- Direct EC2 instance management via SSM
- Docker containers running directly on EC2 with systemd

### New Architecture (EKS-based)
- EKS cluster with managed node groups
- Applications deployed as Kubernetes Deployments with 2 replicas each
- AWS Load Balancer Controller managing ALB through Kubernetes Ingress
- Service mesh for internal communication
- Horizontal Pod Autoscaling capability

## Files Changed

### New Files
- `terraform/eks.tf` - EKS cluster, node groups, and IAM configuration
- `k8s/namespace.yaml` - Kubernetes namespace for the application
- `k8s/service-account.yaml` - Service account with IRSA for ECR access
- `k8s/backend-deployment.yaml` - Backend deployment and service
- `k8s/frontend-deployment.yaml` - Frontend deployment and service
- `k8s/ingress.yaml` - Ingress configuration for ALB
- `scripts/setup-eks-addons.sh` - Script to install AWS Load Balancer Controller

### Modified Files
- `terraform/outputs.tf` - Added EKS cluster outputs, removed EC2 instance outputs
- `terraform/network.tf` - Removed EC2-specific DNS records

### Deprecated Files
- `terraform/compute.tf` -> `terraform/compute.tf.deprecated` - EC2 instance configuration (kept for reference)

## Deployment Steps

### 1. Deploy Infrastructure with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name image-editor-cluster
```

### 3. Install AWS Load Balancer Controller and Deploy Applications

```bash
cd ..
./scripts/setup-eks-addons.sh
```

### 4. Verify Deployment

```bash
# Check pod status
kubectl get pods -n image-editor

# Check services
kubectl get svc -n image-editor

# Get application URL
kubectl get ingress image-editor-ingress -n image-editor
```

## Benefits of EKS Migration

1. **Scalability**: Easy horizontal scaling with HPA (Horizontal Pod Autoscaler)
2. **High Availability**: Multiple replicas across availability zones
3. **Rolling Updates**: Zero-downtime deployments with rolling update strategy
4. **Resource Efficiency**: Better resource utilization with container orchestration
5. **Observability**: Built-in Kubernetes metrics and logging
6. **Self-healing**: Automatic pod restart on failure
7. **Service Discovery**: Native Kubernetes service discovery
8. **Cost Optimization**: Spot instance support for node groups

## CI/CD Changes Required

The GitHub Actions workflow needs to be updated to deploy to EKS instead of EC2. See the updated workflow in `.github/workflows/deploy-to-eks.yml`.

## Rollback Plan

If needed, the EC2 infrastructure can be restored by:
1. Renaming `compute.tf.deprecated` back to `compute.tf`
2. Removing `eks.tf`
3. Running `terraform apply`
4. Using the original GitHub Actions workflows

## Security Improvements

1. **IRSA (IAM Roles for Service Accounts)**: Fine-grained IAM permissions for pods
2. **Network Policies**: Can implement Kubernetes network policies for micro-segmentation
3. **Pod Security Standards**: Enforce security best practices at the pod level
4. **Secrets Management**: Use Kubernetes secrets or AWS Secrets Manager integration

## Monitoring and Logging

- **CloudWatch Container Insights**: Enabled for cluster monitoring
- **Application Logs**: Available through CloudWatch Logs
- **Metrics**: Prometheus-compatible metrics endpoint available

## Cost Considerations

- EKS control plane: ~$0.10/hour
- Node groups: t3.medium instances (can be optimized based on load)
- Consider using Spot instances for non-critical workloads
- Implement cluster autoscaler for dynamic scaling