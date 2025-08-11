#!/bin/bash

# Script to deploy Kubernetes resources to EKS cluster

set -e

CLUSTER_NAME="image-editor-cluster"
REGION="us-east-1"

echo "Deploying Kubernetes resources to cluster: $CLUSTER_NAME"

# Update kubeconfig
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Create namespace
echo "Creating namespace..."
kubectl apply -f ../k8s-manifests/namespace.yaml

# Deploy backend
echo "Deploying backend service..."
kubectl apply -f ../k8s-manifests/backend-deployment.yaml

# Deploy frontend
echo "Deploying frontend service..."
kubectl apply -f ../k8s-manifests/frontend-deployment.yaml

# Apply HPA
echo "Setting up Horizontal Pod Autoscalers..."
kubectl apply -f ../k8s-manifests/hpa.yaml

# Apply Ingress (requires AWS Load Balancer Controller)
echo "Creating Ingress resource..."
kubectl apply -f ../k8s-manifests/ingress.yaml

# Wait for deployments to be ready
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/backend -n image-editor --timeout=5m
kubectl rollout status deployment/frontend -n image-editor --timeout=5m

# Display status
echo ""
echo "=== Deployment Status ==="
kubectl get all -n image-editor

echo ""
echo "=== Ingress Status ==="
kubectl get ingress -n image-editor

# Try to get ALB URL
ALB_URL=$(kubectl get ingress -n image-editor image-editor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$ALB_URL" ]; then
  echo ""
  echo "✅ Application deployed successfully!"
  echo "🌐 Application URL: http://$ALB_URL"
else
  echo ""
  echo "⏳ ALB is being provisioned. Check status with:"
  echo "   kubectl get ingress -n image-editor -w"
fi