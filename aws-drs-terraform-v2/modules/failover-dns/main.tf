# Provider for this module must be us-east-1 (Route 53 health-check metrics live there).
data "aws_caller_identity" "current" {}

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns_name
  type              = var.primary_uses_https ? "HTTPS" : "HTTP"
  port              = var.primary_uses_https ? 443 : 80
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30
  tags              = { Name = "${var.name}-primary-app" }
}

resource "aws_route53_record" "primary" {
  zone_id         = var.hosted_zone_id
  name            = var.record_name
  type            = "A"
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id        = var.hosted_zone_id
  name           = var.record_name
  type           = "A"
  set_identifier = "dr"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.dr_alb_dns_name
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = false
  }
}

# ---------------- alarm + notifications ----------------
resource "aws_sns_topic" "failover" {
  name = "${var.name}-failover"
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.failover.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "primary_down" {
  alarm_name          = "${var.name}-primary-app-down"
  alarm_description   = "Route 53 health check for production is failing; DNS has failed over to DR."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = var.evaluation_minutes
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }
  alarm_actions = [aws_sns_topic.failover.arn]
  ok_actions    = [aws_sns_topic.failover.arn]
}

# ---------------- optional automatic recovery ----------------
locals {
  runbooks = merge(
    { (var.recover_document_name) = { Mode = ["recovery"] } },
    var.database_document_name == "" ? {} : { (var.database_document_name) = {} },
  )
}

data "archive_file" "auto_failover" {
  count       = var.auto_recovery_enabled ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/functions/auto_failover.py"
  output_path = "${path.module}/.build/auto_failover.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "auto_failover" {
  count              = var.auto_recovery_enabled ? 1 : 0
  name               = "${var.name}-auto-failover"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_cloudwatch_log_group" "auto_failover" {
  count             = var.auto_recovery_enabled ? 1 : 0
  name              = "/aws/lambda/${var.name}-auto-failover"
  retention_in_days = 90
}

data "aws_iam_policy_document" "auto_failover" {
  count = var.auto_recovery_enabled ? 1 : 0
  statement {
    actions   = ["ssm:StartAutomationExecution"]
    resources = [for d in keys(local.runbooks) : "arn:aws:ssm:${var.dr_region}:${data.aws_caller_identity.current.account_id}:automation-definition/${d}:*"]
  }
  statement {
    actions   = ["ssm:DescribeAutomationExecutions"]
    resources = ["*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [var.automation_role_arn]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.auto_failover[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "auto_failover" {
  count  = var.auto_recovery_enabled ? 1 : 0
  name   = "auto-failover"
  role   = aws_iam_role.auto_failover[0].id
  policy = data.aws_iam_policy_document.auto_failover[0].json
}

resource "aws_lambda_function" "auto_failover" {
  count            = var.auto_recovery_enabled ? 1 : 0
  function_name    = "${var.name}-auto-failover"
  role             = aws_iam_role.auto_failover[0].arn
  runtime          = "python3.12"
  handler          = "auto_failover.handler"
  filename         = data.archive_file.auto_failover[0].output_path
  source_code_hash = data.archive_file.auto_failover[0].output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      DR_REGION     = var.dr_region
      RUNBOOKS_JSON = jsonencode(local.runbooks)
    }
  }

  depends_on = [aws_cloudwatch_log_group.auto_failover, aws_iam_role_policy.auto_failover]
}

resource "aws_lambda_permission" "sns" {
  count         = var.auto_recovery_enabled ? 1 : 0
  statement_id  = "AllowSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_failover[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.failover.arn
}

resource "aws_sns_topic_subscription" "auto_failover" {
  count     = var.auto_recovery_enabled ? 1 : 0
  topic_arn = aws_sns_topic.failover.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.auto_failover[0].arn
}

output "health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "failover_topic_arn" {
  value = aws_sns_topic.failover.arn
}
