variable "name" {
  description = "Alias name (without alias/)."
  type        = string
}

variable "description" {
  description = "Key description."
  type        = string
}

variable "via_services" {
  description = "AWS services (short names) allowed to use the key on behalf of account principals."
  type        = list(string)
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "key" {
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Same pattern AWS uses for the aws/ebs key: any principal in THIS account,
  # but only through the listed services (EC2/EBS for DRS staging disks and
  # snapshots, RDS, AWS Backup, Secrets Manager).
  statement {
    sid = "AllowUseThroughAwsServices"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:ListGrants",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [for s in var.via_services : "${s}.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}

output "key_arn" {
  value = aws_kms_key.this.arn
}
