# Migration Guide: EC2 to EKS

This guide documents the migration of the image-editor application from EC2 instances to Amazon EKS (Elastic Kubernetes Service).

## Overview

The application has been migrated from:
- **Before**: 2 EC2 instances (frontend and backend) with an Application Load Balancer
- **After**: EKS cluster with Kubernetes deployments, services, and ingress

## Architecture Changes

### Previous Architecture (EC2)
- Frontend EC2 instance running Next.js in Docker
- Backend EC2 instance running FastAPI in Docker
- Application Load Balancer routing traffic to EC2 instances
- Manual deployment via SSM commands

### New Architecture (EKS)
- EKS cluster with managed node group
- Frontend and Backend deployed as Kubernetes Deployments (2 replicas each)
- Services for internal communication
- AWS Load Balancer Controller managing ALB through Ingress
- Automated deployment via kubectl and GitHub Actions

## Benefits of Migration

1. **Scalability**: Easy horizontal scaling with Kubernetes HPA
2. **High Availability**: Multiple replicas across availability zones
3. **Self-healing**: Automatic pod restarts and health checks
4. **Resource Efficiency**: Better resource utilization with container orchestration
5. **Simplified Deployments**: Rolling updates with zero downtime
6. **Better Observability**: Native Kubernetes monitoring and logging

## Deployment Steps

### 1. Deploy Infrastructure with Terraform

```bash
cd terraform-demo/terraform

# Initialize Terraform
terraform init

# Review the changes
terraform plan

# Apply the infrastructure
terraform apply
```

This will create:
- EKS cluster with node group
- VPC, subnets, and networking components
- ECR repositories for container images
- IAM roles and policies
- OIDC provider for IRSA

### 2. Install AWS Load Balancer Controller

```bash
cd terraform-demo/scripts
./install-aws-load-balancer-controller.sh
```

This installs the AWS Load Balancer Controller which manages ALB/NLB resources for Kubernetes Ingress.

### 3. Deploy Applications to EKS

```bash
cd terraform-demo/scripts
./deploy-k8s-manifests.sh
```

This deploys:
- Namespace: `image-editor`
- Backend deployment and service
- Frontend deployment and service
- Ingress for external access

### 4. Verify Deployment

```bash
# Check deployments
kubectl get deployments -n image-editor

# Check pods
kubectl get pods -n image-editor

# Check services
kubectl get services -n image-editor

# Get application URL
kubectl get ingress -n image-editor
```

## GitHub Actions Workflow

The new workflow `deploy-to-eks.yml` handles:
1. Building Docker images for frontend and backend
2. Pushing images to ECR
3. Deploying to EKS using kubectl
4. Verifying deployment status

### Triggering Deployments

**Automatic deployment on push to main:**
```yaml
on:
  push:
    branches:
      - main
```

**Manual deployment:**
- Go to Actions tab in GitHub
- Select "Deploy to EKS" workflow
- Click "Run workflow"
- Choose component (backend/frontend/both)

## Kubernetes Manifests

### Backend (`backend-deployment.yaml`)
- 2 replicas for high availability
- Resource limits and requests
- Health checks (liveness and readiness probes)
- ClusterIP service for internal communication

### Frontend (`frontend-deployment.yaml`)
- 2 replicas for high availability
- Environment variables for API URL
- Resource limits and requests
- Health checks
- ClusterIP service

### Ingress (`ingress.yaml`)
- AWS ALB ingress controller
- Path-based routing:
  - `/api/*` → Backend service
  - `/*` → Frontend service
- Internet-facing ALB

## Monitoring and Troubleshooting

### View logs
```bash
# Backend logs
kubectl logs -f deployment/backend -n image-editor

# Frontend logs
kubectl logs -f deployment/frontend -n image-editor
```

### Scale deployments
```bash
# Scale backend
kubectl scale deployment/backend --replicas=3 -n image-editor

# Scale frontend
kubectl scale deployment/frontend --replicas=3 -n image-editor
```

### Update deployments
```bash
# Update backend image
kubectl set image deployment/backend backend=<new-image> -n image-editor

# Update frontend image
kubectl set image deployment/frontend frontend=<new-image> -n image-editor
```

### Rollback deployments
```bash
# Rollback backend
kubectl rollout undo deployment/backend -n image-editor

# Rollback frontend
kubectl rollout undo deployment/frontend -n image-editor
```

## Cost Optimization

1. **Node Group**: Using t3.medium instances (cost-effective for workloads)
2. **Spot Instances**: Consider using Spot instances for non-critical workloads
3. **Auto-scaling**: Configure HPA and Cluster Autoscaler for optimal resource usage
4. **Resource Requests**: Set appropriate resource requests and limits

## Security Considerations

1. **IRSA**: IAM Roles for Service Accounts for fine-grained permissions
2. **Network Policies**: Implement Kubernetes network policies
3. **Pod Security Standards**: Apply pod security policies
4. **Secrets Management**: Use AWS Secrets Manager or Kubernetes secrets
5. **Image Scanning**: ECR scanning enabled for vulnerability detection

## Cleanup

To destroy the infrastructure:
```bash
# Delete Kubernetes resources first
kubectl delete namespace image-editor

# Uninstall AWS Load Balancer Controller
helm uninstall aws-load-balancer-controller -n kube-system

# Destroy Terraform resources
cd terraform-demo/terraform
terraform destroy
```

## Next Steps

1. **Configure HPA**: Set up Horizontal Pod Autoscaler for automatic scaling
2. **Add Monitoring**: Deploy Prometheus and Grafana for monitoring
3. **Implement CI/CD**: Enhance GitHub Actions with testing and staging environments
4. **Add Logging**: Set up centralized logging with CloudWatch or ELK stack
5. **Configure Backups**: Implement backup strategies for stateful components