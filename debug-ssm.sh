#!/bin/bash

echo "=== SSM Debugging Script ==="
echo ""

# Check for running instances
echo "1. Checking for EC2 instances with the expected tags..."
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=image-editor-backend-*,image-editor-frontend-*" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name'].Value|[0],State.Name,IamInstanceProfile.Arn]" \
  --output table

echo ""
echo "2. Checking SSM managed instances..."
aws ssm describe-instance-information \
  --query "InstanceInformationList[].[InstanceId,PingStatus,LastPingDateTime,PlatformName,IsLatestVersion]" \
  --output table

echo ""
echo "3. Checking specific instances for SSM readiness..."
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=image-editor-backend-*,image-editor-frontend-*" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

for INSTANCE_ID in $INSTANCES; do
  echo ""
  echo "Instance: $INSTANCE_ID"
  
  # Get instance details
  aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],State.Name,IamInstanceProfile.Arn]" \
    --output text
  
  # Check if registered with SSM
  SSM_STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query "InstanceInformationList[0].PingStatus" \
    --output text 2>/dev/null)
  
  if [ "$SSM_STATUS" == "None" ] || [ -z "$SSM_STATUS" ]; then
    echo "  ❌ Not registered with SSM"
  else
    echo "  ✅ SSM Status: $SSM_STATUS"
  fi
  
  # Try to get SSM agent version
  echo "  Attempting to get SSM agent version..."
  aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl status amazon-ssm-agent | head -5"]' \
    --query "Command.CommandId" \
    --output text 2>&1 | head -1
done

echo ""
echo "4. Checking VPC endpoints..."
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters 'Name=tag:Name,Values=image-editor-vpc' --query 'Vpcs[0].VpcId' --output text)" \
  --query "VpcEndpoints[].[ServiceName,State]" \
  --output table

echo ""
echo "5. Checking security groups for SSM traffic..."
VPC_ID=$(aws ec2 describe-vpcs --filters 'Name=tag:Name,Values=image-editor-vpc' --query 'Vpcs[0].VpcId' --output text)
echo "VPC ID: $VPC_ID"

# Check if instances can reach SSM endpoints
echo ""
echo "6. Checking IAM role permissions..."
ROLE_NAME="image-editor-ec2-role"
aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "AttachedPolicies[].PolicyArn" --output text

echo ""
echo "=== Troubleshooting Tips ==="
echo "If instances are not registered with SSM:"
echo "1. Check that the instance has been running for at least 5 minutes"
echo "2. Verify the SSM agent is installed and running on the instance"
echo "3. Check CloudWatch logs for SSM agent errors"
echo "4. Ensure the instance can reach SSM endpoints (via NAT or VPC endpoints)"
echo "5. Verify IAM role has AmazonSSMManagedInstanceCore policy"