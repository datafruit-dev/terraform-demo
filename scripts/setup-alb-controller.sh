#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up AWS Load Balancer Controller for EKS...${NC}"

# Check if required tools are installed
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}aws cli is required but not installed. Aborting.${NC}" >&2; exit 1; }

# Get cluster name from terraform output or use default
CLUSTER_NAME=${1:-image-editor-cluster}
REGION=${2:-us-east-1}

echo -e "${YELLOW}Cluster: $CLUSTER_NAME${NC}"
echo -e "${YELLOW}Region: $REGION${NC}"

# Update kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Add the EKS Helm chart repository
echo -e "${GREEN}Adding EKS Helm chart repository...${NC}"
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get the IAM role ARN from Terraform output
echo -e "${GREEN}Getting IAM role ARN...${NC}"
IAM_ROLE_ARN=$(cd terraform && terraform output -raw aws_load_balancer_controller_role_arn 2>/dev/null || echo "")

if [ -z "$IAM_ROLE_ARN" ]; then
    echo -e "${RED}Could not get IAM role ARN from Terraform output. Please ensure Terraform has been applied.${NC}"
    exit 1
fi

echo -e "${YELLOW}IAM Role ARN: $IAM_ROLE_ARN${NC}"

# Create service account with IAM role annotation
echo -e "${GREEN}Creating service account...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: $IAM_ROLE_ARN
EOF

# Install AWS Load Balancer Controller
echo -e "${GREEN}Installing AWS Load Balancer Controller...${NC}"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=image-editor-vpc" --query "Vpcs[0].VpcId" --output text --region $REGION) \
  --wait

# Verify installation
echo -e "${GREEN}Verifying AWS Load Balancer Controller installation...${NC}"
kubectl get deployment -n kube-system aws-load-balancer-controller

# Check if the controller is running
if kubectl wait --for=condition=available --timeout=300s deployment/aws-load-balancer-controller -n kube-system; then
    echo -e "${GREEN}✅ AWS Load Balancer Controller is successfully installed and running!${NC}"
else
    echo -e "${RED}❌ AWS Load Balancer Controller installation failed or timed out.${NC}"
    exit 1
fi

echo -e "${GREEN}Setup complete! You can now create Ingress resources with the ALB ingress class.${NC}"