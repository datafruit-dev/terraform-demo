# =============================================================================
# SSM REGISTRATION WAIT RESOURCES
# =============================================================================
# These resources ensure instances are registered with SSM before marking them as ready

# Wait for backend instance to register with SSM
resource "null_resource" "wait_for_backend_ssm" {
  depends_on = [aws_instance.backend]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for backend instance ${aws_instance.backend.id} to register with SSM..."
      for i in {1..60}; do
        if aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=${aws_instance.backend.id}" \
          --query "InstanceInformationList[0].PingStatus" \
          --output text 2>/dev/null | grep -q "Online"; then
          echo "Backend instance is registered with SSM"
          exit 0
        fi
        echo "Waiting for SSM registration... attempt $i/60"
        sleep 10
      done
      echo "Warning: Backend instance may not be fully registered with SSM"
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    instance_id = aws_instance.backend.id
  }
}

# Wait for frontend instance to register with SSM
resource "null_resource" "wait_for_frontend_ssm" {
  depends_on = [aws_instance.frontend]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for frontend instance ${aws_instance.frontend.id} to register with SSM..."
      for i in {1..60}; do
        if aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=${aws_instance.frontend.id}" \
          --query "InstanceInformationList[0].PingStatus" \
          --output text 2>/dev/null | grep -q "Online"; then
          echo "Frontend instance is registered with SSM"
          exit 0
        fi
        echo "Waiting for SSM registration... attempt $i/60"
        sleep 10
      done
      echo "Warning: Frontend instance may not be fully registered with SSM"
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    instance_id = aws_instance.frontend.id
  }
}

# Output to show SSM registration status
output "ssm_registration_status" {
  value = {
    backend_instance_id  = aws_instance.backend.id
    frontend_instance_id = aws_instance.frontend.id
    note                 = "Run 'aws ssm describe-instance-information' to verify SSM registration"
  }
  depends_on = [
    null_resource.wait_for_backend_ssm,
    null_resource.wait_for_frontend_ssm
  ]
}