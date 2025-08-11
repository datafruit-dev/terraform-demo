#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== EC2 to EKS Migration Script ===${NC}"
echo -e "${YELLOW}This script will help migrate from EC2 instances to EKS cluster${NC}\n"

# Check if user wants to proceed
read -p "Do you want to proceed with the migration? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${RED}Migration cancelled.${NC}"
    exit 1
fi

# Step 1: Apply Terraform changes to create EKS cluster
echo -e "\n${YELLOW}Step 1: Creating EKS infrastructure...${NC}"
cd ../terraform
terraform init
terraform plan -out=eks-migration.tfplan
echo -e "${YELLOW}Review the plan above. Do you want to apply these changes?${NC}"
read -p "Apply Terraform changes? (yes/no): " -r
if [[ $REPLY =~ ^[Yy]es$ ]]; then
    terraform apply eks-migration.tfplan
else
    echo -e "${RED}Terraform apply cancelled. Exiting.${NC}"
    exit 1
fi

# Step 2: Setup EKS cluster with applications
echo -e "\n${YELLOW}Step 2: Setting up EKS cluster...${NC}"
cd ../scripts
./setup-eks-cluster.sh

# Step 3: Test the new deployment
echo -e "\n${YELLOW}Step 3: Testing EKS deployment...${NC}"
NAMESPACE="image-editor"
kubectl get pods -n $NAMESPACE
kubectl get ingress -n $NAMESPACE

# Step 4: Get Load Balancer URL
LB_URL=$(kubectl get ingress -n $NAMESPACE image-editor-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ ! -z "$LB_URL" ]; then
    echo -e "${GREEN}New EKS deployment is available at: http://$LB_URL${NC}"
    echo -e "${YELLOW}Please test the application at this URL before proceeding.${NC}"
else
    echo -e "${YELLOW}Load Balancer is still being provisioned. Please wait and check manually.${NC}"
fi

# Step 5: Optional - Remove old EC2 resources
echo -e "\n${YELLOW}Step 5: Cleanup old EC2 resources${NC}"
echo -e "${RED}WARNING: This will destroy the EC2 instances and related resources!${NC}"
read -p "Do you want to remove the old EC2 infrastructure? (yes/no): " -r
if [[ $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${YELLOW}To remove EC2 resources, comment out or remove the following from Terraform:${NC}"
    echo "  - compute.tf (EC2 instances and ALB configuration)"
    echo "  - Remove EC2-specific security groups from network.tf"
    echo "  - Update outputs.tf to remove EC2-specific outputs"
    echo ""
    echo "Then run: terraform plan && terraform apply"
else
    echo -e "${GREEN}EC2 resources retained. You can remove them later when ready.${NC}"
fi

echo -e "\n${GREEN}=== Migration Process Complete ===${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Update DNS records to point to the new Load Balancer"
echo "2. Monitor the EKS cluster for stability"
echo "3. Update CI/CD pipelines to use deploy-to-eks.yml workflow"
echo "4. Remove old EC2 resources once EKS is stable"