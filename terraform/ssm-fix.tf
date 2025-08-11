# =============================================================================
# ADDITIONAL SSM CONFIGURATION
# =============================================================================
# This file contains additional configurations to ensure SSM works properly

# Additional IAM policy for SSM operations
resource "aws_iam_policy" "ssm_additional" {
  name        = "image-editor-ssm-additional-policy"
  description = "Additional permissions for SSM operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::aws-ssm-${var.aws_region}/*",
          "arn:aws:s3:::aws-windows-downloads-${var.aws_region}/*",
          "arn:aws:s3:::amazon-ssm-${var.aws_region}/*",
          "arn:aws:s3:::amazon-ssm-packages-${var.aws_region}/*",
          "arn:aws:s3:::${var.aws_region}-birdwatcher-prod/*",
          "arn:aws:s3:::patch-baseline-snapshot-${var.aws_region}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::aws-ssm-document-attachments-${var.aws_region}/*"
      }
    ]
  })
}

# Attach the additional SSM policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ssm_additional_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ssm_additional.arn
}

# CloudWatch Logs policy for SSM (helps with debugging)
resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Create a CloudWatch Log Group for SSM logs
resource "aws_cloudwatch_log_group" "ssm_logs" {
  name              = "/aws/ssm/image-editor"
  retention_in_days = 7

  tags = {
    Name = "image-editor-ssm-logs"
  }
}