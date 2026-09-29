variable "name" {
  description = "Server name (Name tag)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size (GiB)."
  type        = number
}

variable "subnet_id" {
  description = "Private app subnet."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups."
  type        = list(string)
}

variable "instance_profile_name" {
  description = "Instance profile with AWSElasticDisasterRecoveryEc2InstancePolicy."
  type        = string
}

variable "drs_region" {
  description = "Region where DRS replicates this server (the DR region)."
  type        = string
}

variable "install_agent" {
  description = "Install the AWS Replication Agent at boot."
  type        = bool
}

variable "dr_group" {
  description = "Value of the DRGroup tag."
  type        = string
}

variable "ami_id" {
  description = "Optional AMI; defaults to latest Amazon Linux 2023."
  type        = string
  default     = null
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "this" {
  ami                    = coalesce(var.ami_id, data.aws_ssm_parameter.al2023.value)
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name
  monitoring             = true
  ebs_optimized          = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    server_name   = var.name
    drs_region    = var.drs_region
    install_agent = var.install_agent
  })

  tags = {
    Name    = var.name
    DRGroup = var.dr_group
    Backup  = "true"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

output "instance_id" {
  value = aws_instance.this.id
}

output "private_ip" {
  value = aws_instance.this.private_ip
}
