#!/bin/bash
set -e

# Variables
CLUSTER_NAME="image-editor-cluster"
AWS_REGION="us-east-1"

echo "Deploying Kubernetes manifests to cluster: $CLUSTER_NAME"

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Apply Kubernetes manifests
echo "Creating namespace..."
kubectl apply -f ../k8s-manifests/namespace.yaml

echo "Deploying backend..."
kubectl apply -f ../k8s-manifests/backend-deployment.yaml

echo "Deploying frontend..."
kubectl apply -f ../k8s-manifests/frontend-deployment.yaml

echo "Creating ingress..."
kubectl apply -f ../k8s-manifests/ingress.yaml

# Wait for deployments to be ready
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/backend -n image-editor
kubectl wait --for=condition=Available --timeout=300s deployment/frontend -n image-editor

# Get deployment status
echo "Deployment status:"
kubectl get deployments -n image-editor
kubectl get pods -n image-editor
kubectl get services -n image-editor
kubectl get ingress -n image-editor

# Get the application URL
echo "Waiting for ALB to be provisioned (this may take a few minutes)..."
sleep 30

APP_URL=$(kubectl get ingress image-editor-ingress -n image-editor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ ! -z "$APP_URL" ]; then
  echo "✅ Application is available at: http://$APP_URL"
else
  echo "⏳ ALB is still being provisioned. Run the following command to check status:"
  echo "kubectl get ingress -n image-editor"
fi