#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up EKS Cluster and deploying applications...${NC}"

# Variables
AWS_REGION="us-east-1"
CLUSTER_NAME="image-editor-cluster"
NAMESPACE="image-editor"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm is required but not installed.${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed.${NC}" >&2; exit 1; }

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Verify connection
echo -e "${YELLOW}Verifying cluster connection...${NC}"
kubectl get nodes

# Create namespace
echo -e "${YELLOW}Creating namespace...${NC}"
kubectl apply -f ../k8s-manifests/namespace.yaml

# Install metrics server for HPA
echo -e "${YELLOW}Installing metrics server...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install AWS Load Balancer Controller
echo -e "${YELLOW}Installing AWS Load Balancer Controller...${NC}"

# Add the EKS Helm chart repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get the IAM role ARN for the load balancer controller
LB_ROLE_ARN=$(aws iam get-role --role-name image-editor-aws-load-balancer-controller --query 'Role.Arn' --output text)
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)

# Install the AWS Load Balancer Controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$LB_ROLE_ARN \
  --set region=$AWS_REGION \
  --set vpcId=$VPC_ID \
  --wait

# Deploy applications
echo -e "${YELLOW}Deploying applications...${NC}"
kubectl apply -f ../k8s-manifests/backend-deployment.yaml
kubectl apply -f ../k8s-manifests/frontend-deployment.yaml

# Wait for deployments to be ready
echo -e "${YELLOW}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/image-editor-backend -n $NAMESPACE
kubectl wait --for=condition=available --timeout=300s deployment/image-editor-frontend -n $NAMESPACE

# Deploy Ingress
echo -e "${YELLOW}Deploying Ingress...${NC}"
kubectl apply -f ../k8s-manifests/ingress.yaml

# Deploy HPA
echo -e "${YELLOW}Deploying Horizontal Pod Autoscalers...${NC}"
kubectl apply -f ../k8s-manifests/hpa.yaml

# Get Load Balancer URL
echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${YELLOW}Waiting for Load Balancer to be provisioned...${NC}"
sleep 30

LB_URL=$(kubectl get ingress -n $NAMESPACE image-editor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$LB_URL" ]; then
    echo -e "${YELLOW}Load Balancer is still being provisioned. Check status with:${NC}"
    echo "kubectl get ingress -n $NAMESPACE image-editor-ingress"
else
    echo -e "${GREEN}Application is available at: http://$LB_URL${NC}"
fi

# Show deployment status
echo -e "\n${GREEN}Deployment Status:${NC}"
kubectl get all -n $NAMESPACE