#!/bin/bash

# Deployment script that waits for SSM connectivity before deploying
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting deployment process...${NC}"

# Get instance IDs from Terraform outputs (this will wait for SSM readiness)
echo -e "${YELLOW}Getting instance IDs from Terraform...${NC}"
BACKEND_INSTANCE_ID=$(cd terraform && terraform output -raw backend_instance_id)
FRONTEND_INSTANCE_ID=$(cd terraform && terraform output -raw frontend_instance_id)

echo -e "${GREEN}Backend Instance ID: ${BACKEND_INSTANCE_ID}${NC}"
echo -e "${GREEN}Frontend Instance ID: ${FRONTEND_INSTANCE_ID}${NC}"

# Function to check if instance is connected to SSM
check_ssm_connectivity() {
    local instance_id=$1
    local instance_name=$2
    
    echo -e "${YELLOW}Verifying SSM connectivity for ${instance_name}...${NC}"
    
    if aws ssm describe-instance-information --region us-east-1 \
        --filters "Key=InstanceIds,Values=${instance_id}" \
        --query 'InstanceInformationList[0].PingStatus' --output text | grep -q "Online"; then
        echo -e "${GREEN}✓ ${instance_name} is connected to SSM${NC}"
        return 0
    else
        echo -e "${RED}✗ ${instance_name} is not connected to SSM${NC}"
        return 1
    fi
}

# Verify both instances are connected to SSM
check_ssm_connectivity "$BACKEND_INSTANCE_ID" "Backend"
check_ssm_connectivity "$FRONTEND_INSTANCE_ID" "Frontend"

# Deploy to backend instance
echo -e "${YELLOW}Deploying to backend instance...${NC}"
aws ssm send-command \
    --region us-east-1 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["cd /home/ec2-user","sudo systemctl restart backend","sudo systemctl status backend"]' \
    --targets "Key=InstanceIds,Values=${BACKEND_INSTANCE_ID}" \
    --comment "Deploy backend application"

# Deploy to frontend instance  
echo -e "${YELLOW}Deploying to frontend instance...${NC}"
aws ssm send-command \
    --region us-east-1 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["cd /home/ec2-user","sudo systemctl restart frontend","sudo systemctl status frontend"]' \
    --targets "Key=InstanceIds,Values=${FRONTEND_INSTANCE_ID}" \
    --comment "Deploy frontend application"

echo -e "${GREEN}Deployment commands sent successfully!${NC}"
echo -e "${YELLOW}You can check the deployment status in the AWS Systems Manager console.${NC}"