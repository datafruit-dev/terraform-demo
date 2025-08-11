# Comprehensive SSM Fix for GitHub Actions Deployment

## Problem
Even after the initial fixes, the GitHub Actions workflow continues to fail with:
```
An error occurred (InvalidInstanceId) when calling the SendCommand operation: Instances not in a valid state for account
```

## Root Cause Analysis

The issue occurs when EC2 instances are not properly registered as SSM managed instances, even though:
- SSM Agent is installed and running
- IAM permissions are configured
- VPC endpoints exist
- Security groups allow traffic

## Comprehensive Solution

### 1. Enhanced IAM Permissions (`ssm-fix.tf`)
Added comprehensive SSM permissions beyond the basic `AmazonSSMManagedInstanceCore`:
- SSM message channel operations
- EC2 message operations
- S3 access for SSM packages
- CloudWatch logging for debugging

### 2. Adjusted Instance Metadata Settings (`compute.tf`)
- Changed `http_tokens` from `"required"` to `"optional"` to ensure SSM agent compatibility
- Increased `http_put_response_hop_limit` from 1 to 2 for container access
- These changes allow SSM agent to properly communicate with AWS services

### 3. Enhanced SSM Agent Initialization (`user-data/*.sh`)
- Added explicit SSM agent configuration with correct region
- Increased wait time from 30 to 60 attempts
- Added fingerprint check to verify registration
- Installed CloudWatch agent for better logging
- Added 20-second post-registration wait

### 4. Added SSM Registration Verification (`ssm-wait.tf`)
- Terraform null_resource that waits for SSM registration
- Verifies instances are "Online" in SSM before completing
- Provides clear output about registration status

### 5. Debugging Tools (`debug-ssm.sh`)
Created a comprehensive debugging script that checks:
- EC2 instance status and tags
- SSM managed instance registration
- VPC endpoint configuration
- Security group rules
- IAM role permissions

## Files Modified/Created

1. **New Files:**
   - `terraform/ssm-fix.tf` - Additional IAM policies and CloudWatch configuration
   - `terraform/ssm-wait.tf` - SSM registration verification resources
   - `debug-ssm.sh` - Debugging script

2. **Modified Files:**
   - `terraform/main.tf` - Added null provider
   - `terraform/compute.tf` - Adjusted metadata options
   - `terraform/user-data/backend-docker.sh` - Enhanced SSM initialization
   - `terraform/user-data/frontend-docker.sh` - Enhanced SSM initialization

## Deployment Steps

1. **Apply Terraform Changes:**
   ```bash
   cd terraform
   terraform init -upgrade
   terraform plan
   terraform apply
   ```

2. **Wait for SSM Registration:**
   The Terraform apply will now wait for instances to register with SSM.
   This can take 5-10 minutes after instance launch.

3. **Verify SSM Registration:**
   ```bash
   # Run the debug script
   bash ../debug-ssm.sh
   
   # Or manually check
   aws ssm describe-instance-information \
     --query "InstanceInformationList[].[InstanceId,PingStatus]" \
     --output table
   ```

4. **Test GitHub Actions Workflow:**
   Once instances show as "Online" in SSM, the GitHub Actions workflow should work.

## Why This Fix Works

1. **Metadata Options**: The strict IMDSv2 requirement (`http_tokens = "required"`) can prevent SSM agent from accessing instance metadata. Setting it to `"optional"` allows fallback to IMDSv1 when needed.

2. **Complete IAM Permissions**: The basic SSM policy may not include all necessary permissions for command execution. The additional policy ensures all SSM operations work.

3. **Registration Time**: SSM agent needs time to:
   - Start and initialize
   - Retrieve credentials from instance metadata
   - Register with the SSM service
   - Become "Online" and ready for commands

4. **Region Configuration**: Explicitly setting the region ensures SSM agent connects to the correct regional endpoint.

## Troubleshooting

If issues persist:

1. **Check Instance Logs:**
   ```bash
   aws ssm get-command-invocation \
     --command-id <command-id> \
     --instance-id <instance-id>
   ```

2. **Check SSM Agent Logs on Instance:**
   - Connect via Session Manager (if possible)
   - Check `/var/log/amazon/ssm/amazon-ssm-agent.log`

3. **Verify Network Connectivity:**
   - Ensure NAT Gateway is working
   - Check VPC endpoint status
   - Verify security group rules

4. **Force Re-registration:**
   If an instance was previously registered, you may need to:
   - Stop the instance
   - Start it again
   - Wait for fresh registration

## Expected Outcome

After applying these fixes:
- Instances will take 5-10 minutes to fully initialize
- SSM will show instances as "Online"
- GitHub Actions workflow will successfully execute commands
- Deployments will complete without errors