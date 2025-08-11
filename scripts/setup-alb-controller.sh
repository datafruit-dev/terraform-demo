#!/bin/bash

# Script to install AWS Load Balancer Controller on EKS cluster
# This enables the Ingress resources to create ALBs automatically

set -e

CLUSTER_NAME="image-editor-cluster"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Setting up AWS Load Balancer Controller for cluster: $CLUSTER_NAME"

# Update kubeconfig
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Create IAM service account
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name=AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve \
  --region $REGION \
  --override-existing-serviceaccounts

# Install cert-manager (required by AWS Load Balancer Controller)
kubectl apply \
  --validate=false \
  -f https://github.com/jetstack/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager \
  deployment/cert-manager-cainjector \
  deployment/cert-manager-webhook \
  -n cert-manager

# Download and install AWS Load Balancer Controller
curl -Lo v2_7_0_full.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.7.0/v2_7_0_full.yaml

# Replace cluster name in the manifest
sed -i.bak -e "s|your-cluster-name|${CLUSTER_NAME}|" v2_7_0_full.yaml

# Remove the ServiceAccount section (we created it with eksctl)
sed -i.bak -e '/apiVersion: v1/,/---/d' v2_7_0_full.yaml

# Apply the controller
kubectl apply -f v2_7_0_full.yaml

# Clean up downloaded files
rm -f v2_7_0_full.yaml v2_7_0_full.yaml.bak

# Wait for the controller to be ready
echo "Waiting for AWS Load Balancer Controller to be ready..."
kubectl wait --for=condition=Available --timeout=300s \
  deployment/aws-load-balancer-controller \
  -n kube-system

echo "✅ AWS Load Balancer Controller installed successfully"

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system | grep aws-load-balancer-controller