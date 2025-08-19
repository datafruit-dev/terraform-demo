#!/bin/bash

# Health Check Script for Image Editor Application
# This script checks the health of the deployed application on EKS

set -e

echo "🔍 Checking Image Editor Application Health..."
echo "=============================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
echo "📡 Checking cluster connectivity..."
if kubectl cluster-info &> /dev/null; then
    echo "✅ Connected to Kubernetes cluster"
else
    echo "❌ Cannot connect to Kubernetes cluster"
    echo "💡 Make sure you have run: aws eks update-kubeconfig --region us-east-1 --name image-editor-cluster"
    exit 1
fi

# Check namespace
echo "📦 Checking namespace..."
if kubectl get namespace image-editor &> /dev/null; then
    echo "✅ image-editor namespace exists"
else
    echo "❌ image-editor namespace not found"
    exit 1
fi

# Check deployments
echo "🚀 Checking deployments..."
BACKEND_READY=$(kubectl get deployment backend -n image-editor -o jsonpath="{.status.readyReplicas}" 2>/dev/null || echo "0")
FRONTEND_READY=$(kubectl get deployment frontend -n image-editor -o jsonpath="{.status.readyReplicas}" 2>/dev/null || echo "0")

if [ "$BACKEND_READY" -gt 0 ]; then
    echo "✅ Backend deployment is ready ($BACKEND_READY replicas)"
else
    echo "❌ Backend deployment is not ready"
fi

if [ "$FRONTEND_READY" -gt 0 ]; then
    echo "✅ Frontend deployment is ready ($FRONTEND_READY replicas)"
else
    echo "❌ Frontend deployment is not ready"
fi

# Check services
echo "🌐 Checking services..."
kubectl get services -n image-editor

# Check ingress
echo "🔗 Checking ingress..."
INGRESS_ADDRESS=$(kubectl get ingress -n image-editor -o jsonpath="{.items[0].status.loadBalancer.ingress[0].hostname}" 2>/dev/null || echo "")

if [ -n "$INGRESS_ADDRESS" ]; then
    echo "✅ Ingress is ready: http://$INGRESS_ADDRESS"
    echo "🌍 Application should be accessible at: http://$INGRESS_ADDRESS"
else
    echo "⏳ Ingress is still being provisioned or not found"
fi

# Check pods
echo "🏃 Checking pod status..."
kubectl get pods -n image-editor

echo ""
echo "🎉 Health check completed!"
echo "💡 Use kubectl logs -f deployment/backend -n image-editor to view backend logs"
echo "💡 Use kubectl logs -f deployment/frontend -n image-editor to view frontend logs"
