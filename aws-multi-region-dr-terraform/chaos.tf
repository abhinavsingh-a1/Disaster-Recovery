# ---------------------------------------------------------------------------
# Chaos engineering with AWS Fault Injection Service (FIS).
# Templates are free until started. Start one with:
#   aws fis start-experiment --region <primary> --experiment-template-id <id>
# or run scripts/dr-drill.sh, which starts the outage experiment and measures RTO/RPO.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "fis_assume" {
  provider = aws.primary

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fis" {
  count              = var.enable_chaos_experiments ? 1 : 0
  provider           = aws.primary
  name               = "${local.name}-fis"
  assume_role_policy = data.aws_iam_policy_document.fis_assume.json
}

resource "aws_iam_role_policy_attachment" "fis" {
  for_each = var.enable_chaos_experiments ? toset([
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess",
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access",
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorSSMAccess",
  ]) : toset([])

  provider   = aws.primary
  role       = aws_iam_role.fis[0].name
  policy_arn = each.value
}

# 1) Regional outage drill: cut all network traffic in the primary web-tier
#    subnets for 10 minutes. ALB targets go unhealthy -> Route 53 health check
#    fails -> alarm -> failover Lambda -> traffic moves to the DR region.
resource "aws_fis_experiment_template" "primary_outage" {
  count       = var.enable_chaos_experiments ? 1 : 0
  provider    = aws.primary
  description = "Primary site outage: block all traffic in primary web-tier subnets for 10 minutes"
  role_arn    = aws_iam_role.fis[0].arn

  stop_condition {
    source = "none"
  }

  action {
    name      = "disrupt-web-subnets"
    action_id = "aws:network:disrupt-connectivity"

    parameter {
      key   = "duration"
      value = "PT10M"
    }

    parameter {
      key   = "scope"
      value = "all"
    }

    target {
      key   = "Subnets"
      value = "primary-web-subnets"
    }
  }

  target {
    name           = "primary-web-subnets"
    resource_type  = "aws:ec2:subnet"
    selection_mode = "ALL"
    resource_arns  = module.network_primary.app_subnet_arns
  }

  tags = {
    Name = "${local.name}-primary-outage"
  }
}

# 2) Self-healing drill: terminate one primary web instance; the ASG must
#    replace it with no user-visible errors.
resource "aws_fis_experiment_template" "terminate_instance" {
  count       = var.enable_chaos_experiments ? 1 : 0
  provider    = aws.primary
  description = "Terminate one primary web instance and let Auto Scaling replace it"
  role_arn    = aws_iam_role.fis[0].arn

  stop_condition {
    source = "none"
  }

  action {
    name      = "terminate-one"
    action_id = "aws:ec2:terminate-instances"

    target {
      key   = "Instances"
      value = "one-primary-web-instance"
    }
  }

  target {
    name           = "one-primary-web-instance"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)"

    resource_tag {
      key   = "Name"
      value = "${local.name}-primary-web"
    }

    filter {
      path   = "State.Name"
      values = ["running"]
    }
  }

  tags = {
    Name = "${local.name}-terminate-instance"
  }
}

# 3) Load drill: 5 minutes of CPU stress on every primary instance; target
#    tracking should scale the group out and back in.
resource "aws_fis_experiment_template" "cpu_stress" {
  count       = var.enable_chaos_experiments ? 1 : 0
  provider    = aws.primary
  description = "CPU stress on all primary web instances to exercise auto scaling"
  role_arn    = aws_iam_role.fis[0].arn

  stop_condition {
    source = "none"
  }

  action {
    name      = "cpu-stress"
    action_id = "aws:ssm:send-command"

    parameter {
      key   = "documentArn"
      value = "arn:aws:ssm:${var.primary_region}::document/AWSFIS-Run-CPU-Stress"
    }

    parameter {
      key   = "documentParameters"
      value = jsonencode({ DurationSeconds = "300", InstallDependencies = "True" })
    }

    parameter {
      key   = "duration"
      value = "PT6M"
    }

    target {
      key   = "Instances"
      value = "all-primary-web-instances"
    }
  }

  target {
    name           = "all-primary-web-instances"
    resource_type  = "aws:ec2:instance"
    selection_mode = "ALL"

    resource_tag {
      key   = "Name"
      value = "${local.name}-primary-web"
    }

    filter {
      path   = "State.Name"
      values = ["running"]
    }
  }

  tags = {
    Name = "${local.name}-cpu-stress"
  }
}
