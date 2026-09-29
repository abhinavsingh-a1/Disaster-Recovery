data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# The server we are making "disaster ready".
resource "aws_instance" "source" {
  ami                         = data.aws_ssm_parameter.al2023.insecure_value
  instance_type               = var.source_instance_type
  subnet_id                   = aws_subnet.this["source"].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.source.name
  key_name                    = var.key_name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.source_root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/source-user-data.sh.tftpl", {
    region       = var.region
    project_name = var.project_name
  })
  user_data_replace_on_change = true

  tags = { Name = "${local.name}-source-server" }

  lifecycle {
    ignore_changes = [ami]
  }
}
