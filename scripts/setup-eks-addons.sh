#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up EKS Add-ons${NC}"

# Get cluster name from Terraform output
CLUSTER_NAME=$(terraform -chdir=terraform output -raw eks_cluster_name 2>/dev/null || echo "image-editor-cluster")
REGION="us-east-1"

echo -e "${YELLOW}Configuring kubectl for cluster: $CLUSTER_NAME${NC}"

# Update kubeconfig
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Install AWS Load Balancer Controller using Helm
echo -e "${YELLOW}Installing AWS Load Balancer Controller${NC}"

# Add the EKS Helm chart repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the AWS Load Balancer Controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::642375200181:role/image-editor-aws-load-balancer-controller" \
  --wait

echo -e "${GREEN}AWS Load Balancer Controller installed successfully${NC}"

# Apply Kubernetes manifests
echo -e "${YELLOW}Applying Kubernetes manifests${NC}"

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/service-account.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/ingress.yaml

echo -e "${GREEN}Kubernetes resources deployed successfully${NC}"

# Wait for deployments to be ready
echo -e "${YELLOW}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/backend -n image-editor
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n image-editor

# Get the Load Balancer URL
echo -e "${YELLOW}Waiting for Ingress to get an address...${NC}"
sleep 30
INGRESS_URL=$(kubectl get ingress image-editor-ingress -n image-editor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

if [ "$INGRESS_URL" != "pending" ] && [ ! -z "$INGRESS_URL" ]; then
    echo -e "${GREEN}Application is available at: http://$INGRESS_URL${NC}"
else
    echo -e "${YELLOW}Ingress is still provisioning. Check status with:${NC}"
    echo "kubectl get ingress image-editor-ingress -n image-editor"
fi

echo -e "${GREEN}Setup complete!${NC}"