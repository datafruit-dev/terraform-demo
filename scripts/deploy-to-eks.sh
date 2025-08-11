#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Deploying Image Editor application to EKS...${NC}"

# Configuration
CLUSTER_NAME=${1:-image-editor-cluster}
REGION=${2:-us-east-1}
ECR_REGISTRY="642375200181.dkr.ecr.us-east-1.amazonaws.com"

echo -e "${YELLOW}Cluster: $CLUSTER_NAME${NC}"
echo -e "${YELLOW}Region: $REGION${NC}"

# Update kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Create namespace
echo -e "${GREEN}Creating namespace...${NC}"
kubectl apply -f k8s-manifests/namespace.yaml

# Create ECR pull secret (if using private ECR)
echo -e "${GREEN}Creating ECR pull secret...${NC}"
kubectl delete secret ecr-registry-secret -n image-editor --ignore-not-found
kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=$ECR_REGISTRY \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region $REGION) \
  -n image-editor

# Deploy backend
echo -e "${GREEN}Deploying backend service...${NC}"
kubectl apply -f k8s-manifests/backend-deployment.yaml

# Wait for backend to be ready
echo -e "${YELLOW}Waiting for backend deployment to be ready...${NC}"
kubectl rollout status deployment/image-editor-backend -n image-editor --timeout=300s

# Deploy frontend
echo -e "${GREEN}Deploying frontend service...${NC}"
kubectl apply -f k8s-manifests/frontend-deployment.yaml

# Wait for frontend to be ready
echo -e "${YELLOW}Waiting for frontend deployment to be ready...${NC}"
kubectl rollout status deployment/image-editor-frontend -n image-editor --timeout=300s

# Deploy ingress
echo -e "${GREEN}Deploying ingress...${NC}"
kubectl apply -f k8s-manifests/ingress.yaml

# Get deployment status
echo -e "${GREEN}Deployment Status:${NC}"
kubectl get deployments -n image-editor
kubectl get pods -n image-editor
kubectl get services -n image-editor
kubectl get ingress -n image-editor

# Wait for ALB to be provisioned
echo -e "${YELLOW}Waiting for ALB to be provisioned (this may take a few minutes)...${NC}"
sleep 30

# Get ALB URL
ALB_URL=$(kubectl get ingress -n image-editor image-editor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$ALB_URL" ]; then
    echo -e "${YELLOW}ALB is still being provisioned. Check back in a few minutes with:${NC}"
    echo "kubectl get ingress -n image-editor image-editor-ingress"
else
    echo -e "${GREEN}✅ Application deployed successfully!${NC}"
    echo -e "${GREEN}Application URL: http://$ALB_URL${NC}"
fi

echo -e "${GREEN}Deployment complete!${NC}"