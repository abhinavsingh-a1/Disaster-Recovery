data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.region
}

# ---------------- recovery instance role ----------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Name starts with AWSElasticDisasterRecovery so DRS's service role is allowed
# to pass it when launching recovery instances.
resource "aws_iam_role" "recovery" {
  name               = "AWSElasticDisasterRecovery-${var.name}-recovery"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "recovery_drs" {
  role       = aws_iam_role.recovery.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryRecoveryInstancePolicy"
}

resource "aws_iam_role_policy_attachment" "recovery_ssm" {
  role       = aws_iam_role.recovery.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "recovery_secret" {
  count = var.enable_database_failover ? 1 : 0
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["arn:aws:secretsmanager:${local.region}:${local.account}:secret:${var.secret_name}-*"]
  }
}

resource "aws_iam_role_policy" "recovery_secret" {
  count  = var.enable_database_failover ? 1 : 0
  name   = "read-db-secret"
  role   = aws_iam_role.recovery.id
  policy = data.aws_iam_policy_document.recovery_secret[0].json
}

resource "aws_iam_instance_profile" "recovery" {
  name = "AWSElasticDisasterRecovery-${var.name}-recovery"
  role = aws_iam_role.recovery.name
}

# ---------------- SSM Automation role ----------------
data "aws_iam_policy_document" "ssm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

resource "aws_iam_role" "automation" {
  name               = "${var.name}-dr-automation"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume.json
}

resource "aws_iam_role_policy_attachment" "automation_drs" {
  role       = aws_iam_role.automation.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticDisasterRecoveryConsoleFullAccess"
}

data "aws_iam_policy_document" "automation" {
  statement {
    sid = "LaunchTemplates"

    actions = [
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassRecoveryRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.recovery.arn]
  }

  statement {
    sid       = "RegisterTargets"
    actions   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
    resources = [var.target_group_arn]
  }

  statement {
    sid       = "DescribeTargets"
    actions   = ["elasticloadbalancing:DescribeTargetHealth"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.enable_database_failover ? [1] : []
    content {
      sid       = "PromoteReplica"
      actions   = ["rds:PromoteReadReplica", "rds:DescribeDBInstances"]
      resources = ["arn:aws:rds:${local.region}:${local.account}:db:${var.db_replica_identifier}"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_database_failover ? [1] : []
    content {
      sid       = "RepointDbRecord"
      actions   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
      resources = ["arn:aws:route53:::hostedzone/${var.private_zone_id}"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_database_failover ? [1] : []
    content {
      sid       = "Route53Change"
      actions   = ["route53:GetChange"]
      resources = ["arn:aws:route53:::change/*"]
    }
  }
}

resource "aws_iam_role_policy" "automation" {
  name   = "dr-automation"
  role   = aws_iam_role.automation.id
  policy = data.aws_iam_policy_document.automation.json
}
