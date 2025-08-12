#!/bin/bash
set -e

# Variables
CLUSTER_NAME="image-editor-cluster"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Installing AWS Load Balancer Controller for cluster: $CLUSTER_NAME"

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Install cert-manager (required by AWS Load Balancer Controller)
echo "Installing cert-manager..."
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-cainjector -n cert-manager

# Get the IAM role ARN from Terraform output
IAM_ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn)

# Create service account with IAM role annotation
echo "Creating service account..."
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

# Install AWS Load Balancer Controller using Helm
echo "Adding EKS Helm repository..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo "Installing AWS Load Balancer Controller..."
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=image-editor-vpc" --query "Vpcs[0].VpcId" --output text)

# Wait for the controller to be ready
echo "Waiting for AWS Load Balancer Controller to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/aws-load-balancer-controller -n kube-system

echo "AWS Load Balancer Controller installation complete!"
kubectl get deployment -n kube-system aws-load-balancer-controller