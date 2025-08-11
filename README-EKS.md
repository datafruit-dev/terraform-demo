# Image Editor Infrastructure - EKS Version

This repository contains the Terraform configuration for deploying the Image Editor application on Amazon EKS (Elastic Kubernetes Service).

## Architecture Overview

The infrastructure has been migrated from EC2 instances to EKS for improved scalability and reliability:

### Previous Architecture (EC2)
- 2 EC2 instances (frontend and backend) in private subnet
- Application Load Balancer in public subnets
- Manual deployment via SSM

### New Architecture (EKS)
- **EKS Cluster**: Managed Kubernetes control plane
- **Node Group**: Auto-scaling group of worker nodes (2-4 nodes)
- **Kubernetes Deployments**: 
  - Frontend (Next.js) - 2+ replicas with HPA
  - Backend (FastAPI) - 2+ replicas with HPA
- **AWS Load Balancer Controller**: Manages ALB via Ingress resources
- **Horizontal Pod Autoscaler**: Automatically scales pods based on CPU/memory usage

### Benefits of EKS Architecture
1. **High Availability**: Multiple replicas across nodes
2. **Auto-scaling**: Both pod-level (HPA) and node-level scaling
3. **Self-healing**: Automatic pod restarts and rescheduling
4. **Rolling Updates**: Zero-downtime deployments
5. **Better Resource Utilization**: Multiple pods per node
6. **Simplified Operations**: Kubernetes manages container orchestration

## Network Architecture (Maintained)

The same network security policies are maintained:
- VPC with public and private subnets
- NAT Gateway for outbound internet access
- Security groups enforcing traffic isolation
- ALB as the only internet-facing component

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0
3. **kubectl** - Kubernetes CLI
4. **helm** - Kubernetes package manager

## Deployment Steps

### 1. Deploy Infrastructure with Terraform

```bash
cd terraform-demo/terraform

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### 2. Configure kubectl

After Terraform completes, configure kubectl to connect to your cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name image-editor-cluster
```

### 3. Install AWS Load Balancer Controller

The AWS Load Balancer Controller manages ALBs for your Ingress resources:

```bash
cd ../..
./terraform-demo/scripts/setup-alb-controller.sh image-editor-cluster us-east-1
```

### 4. Deploy the Application

Deploy the frontend and backend services to EKS:

```bash
cd terraform-demo
./scripts/deploy-to-eks.sh image-editor-cluster us-east-1
```

### 5. Access the Application

Get the ALB URL (wait 2-3 minutes for provisioning):

```bash
kubectl get ingress -n image-editor image-editor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Kubernetes Resources

### Deployments
- **image-editor-backend**: FastAPI application (2+ replicas)
- **image-editor-frontend**: Next.js application (2+ replicas)

### Services
- **backend-service**: ClusterIP service for internal backend access
- **frontend-service**: NodePort service for frontend

### Ingress
- **image-editor-ingress**: ALB ingress routing:
  - `/api/*` → backend-service
  - `/*` → frontend-service

### Auto-scaling
- **HPA**: Scales pods based on CPU (70%) and memory (80%) utilization
- **Cluster Autoscaler**: Can be added to scale nodes automatically

## Monitoring and Management

### View Resources
```bash
# View all resources in the namespace
kubectl get all -n image-editor

# View pod logs
kubectl logs -n image-editor deployment/image-editor-frontend
kubectl logs -n image-editor deployment/image-editor-backend

# Describe pods for troubleshooting
kubectl describe pod -n image-editor <pod-name>
```

### Scaling
```bash
# Manual scaling
kubectl scale deployment image-editor-frontend -n image-editor --replicas=3

# View HPA status
kubectl get hpa -n image-editor
```

### Updates and Rollbacks
```bash
# Update image
kubectl set image deployment/image-editor-frontend -n image-editor \
  frontend=642375200181.dkr.ecr.us-east-1.amazonaws.com/image-editor-frontend:new-tag

# Check rollout status
kubectl rollout status deployment/image-editor-frontend -n image-editor

# Rollback if needed
kubectl rollout undo deployment/image-editor-frontend -n image-editor
```

## CI/CD Integration

The GitHub Actions workflow needs to be updated to deploy to EKS instead of EC2. The new workflow should:
1. Build and push images to ECR
2. Update Kubernetes deployments with new image tags
3. Monitor rollout status

## Cost Optimization

- **Node Group**: Uses t3.medium instances (vs t3.small for EC2)
- **Scaling**: Minimum 2 nodes, can scale to 4 based on load
- **Spot Instances**: Can be configured for non-production workloads

## Security

- **RBAC**: Kubernetes role-based access control
- **Network Policies**: Can be added for pod-to-pod communication rules
- **Secrets Management**: Use Kubernetes secrets or AWS Secrets Manager
- **Pod Security Standards**: Enforce security best practices

## Cleanup

To destroy all resources:

```bash
# Delete Kubernetes resources first
kubectl delete namespace image-editor

# Then destroy infrastructure
cd terraform-demo/terraform
terraform destroy
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -n image-editor <pod-name>
kubectl logs -n image-editor <pod-name>
```

### ALB not provisioning
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### Node issues
```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>
```

## Migration Notes

The migration from EC2 to EKS maintains:
- Same VPC and network configuration
- Same security group policies (adapted for EKS)
- Same ECR repositories
- Same application containers

Changes:
- Replaced EC2 instances with EKS node group
- Replaced static ALB with dynamic ALB via Ingress
- Added Kubernetes service discovery instead of Route53 internal DNS
- Added horizontal pod autoscaling for better scalability