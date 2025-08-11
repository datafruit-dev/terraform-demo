# SSM SendCommand Fix for GitHub Actions Deployment

## Problem
The GitHub Actions workflow was failing with the error:
```
An error occurred (InvalidInstanceId) when calling the SendCommand operation: Instances not in a valid state for account
```

## Root Causes Identified

1. **Instance Naming Mismatch**: The GitHub Actions workflow was looking for instances with names matching the pattern `image-editor-backend-*` and `image-editor-frontend-*`, but the Terraform configuration was creating instances with exact names without suffixes.

2. **SSM Agent Initialization**: The SSM agent needs time to fully initialize and register with the AWS Systems Manager service after instance launch.

3. **Instance Dependencies**: EC2 instances were being created potentially before VPC endpoints were fully available.

## Changes Made

### 1. Updated Instance Names (compute.tf)
- Changed backend instance name from `image-editor-backend` to `image-editor-backend-1`
- Changed frontend instance name from `image-editor-frontend` to `image-editor-frontend-1`
- This matches the wildcard pattern expected by the GitHub Actions workflow

### 2. Added Explicit Dependencies (compute.tf)
- Added dependencies on VPC endpoints (ssm, ssm_messages, ec2_messages) to ensure they're created before EC2 instances
- This ensures SSM connectivity is available when instances start

### 3. Enhanced SSM Agent Initialization (user-data scripts)
- Added a retry loop (up to 30 attempts) to wait for SSM agent to be active
- Added additional 15-second wait after activation to ensure full registration with SSM service
- This prevents the "not in valid state" error by ensuring SSM is fully ready

### 4. Added Instance Metadata Options (compute.tf)
- Configured IMDSv2 (Instance Metadata Service Version 2) for better security
- Enabled detailed monitoring for better observability
- These settings improve SSM compatibility and security

## Files Modified

1. `terraform/compute.tf`
   - Updated instance names to include suffix
   - Added metadata options for IMDSv2
   - Added explicit dependencies on VPC endpoints
   - Enabled detailed monitoring

2. `terraform/user-data/backend-docker.sh`
   - Enhanced SSM agent initialization with retry logic
   - Added proper wait conditions

3. `terraform/user-data/frontend-docker.sh`
   - Enhanced SSM agent initialization with retry logic
   - Added proper wait conditions

## Verification Steps

After applying these Terraform changes:

1. Run `terraform plan` to review the changes
2. Run `terraform apply` to create/update the infrastructure
3. Wait for instances to fully initialize (check AWS Console → EC2 → Instances)
4. Verify SSM connectivity:
   ```bash
   aws ssm describe-instance-information --filters "Key=tag:Name,Values=image-editor-backend-1,image-editor-frontend-1"
   ```
5. Run the GitHub Actions workflow to verify deployment works

## Additional Notes

- The VPC endpoints for SSM were already properly configured in `vpc-endpoints.tf`
- Security groups already had the necessary rules for HTTPS traffic (0.0.0.0/0 egress)
- IAM roles and policies for SSM were already correctly configured
- The fix primarily addresses timing and naming issues rather than connectivity problems