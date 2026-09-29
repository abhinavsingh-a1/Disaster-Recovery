data "aws_caller_identity" "current" {}

locals {
  namespace = "DRS/${var.name}"
}

# ---------------- SNS topics (DR + primary region) ----------------
resource "aws_sns_topic" "dr" {
  name = "${var.name}-dr-alerts"
}

resource "aws_sns_topic" "primary" {
  provider = aws.primary
  name     = "${var.name}-prod-alerts"
}

resource "aws_sns_topic_subscription" "dr" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.dr.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic_subscription" "primary" {
  provider  = aws.primary
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.primary.arn
  protocol  = "email"
  endpoint  = each.value
}

data "aws_iam_policy_document" "dr_topic" {
  statement {
    sid       = "AllowEventBridge"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.dr.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "AllowCloudWatchAlarms"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.dr.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "dr" {
  arn    = aws_sns_topic.dr.arn
  policy = data.aws_iam_policy_document.dr_topic.json
}

# ---------------- DRS events -> SNS ----------------
resource "aws_cloudwatch_event_rule" "drs_events" {
  name        = "${var.name}-drs-events"
  description = "Replication stalled / launch result events from AWS DRS"

  event_pattern = jsonencode({
    source        = ["aws.drs"]
    "detail-type" = var.drs_event_detail_types
  })
}

resource "aws_cloudwatch_event_target" "drs_events" {
  rule = aws_cloudwatch_event_rule.drs_events.name
  arn  = aws_sns_topic.dr.arn
}

# ---------------- replication monitor Lambda (custom metrics) ----------------
data "archive_file" "monitor" {
  type        = "zip"
  source_file = "${path.module}/functions/replication_monitor.py"
  output_path = "${path.module}/.build/replication_monitor.zip"
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

resource "aws_iam_role" "monitor" {
  name               = "${var.name}-drs-monitor"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_cloudwatch_log_group" "monitor" {
  name              = "/aws/lambda/${var.name}-drs-monitor"
  retention_in_days = 30
}

data "aws_iam_policy_document" "monitor" {
  statement {
    actions   = ["drs:DescribeSourceServers"]
    resources = ["*"]
  }
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [local.namespace]
    }
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.monitor.arn}:*"]
  }
}

resource "aws_iam_role_policy" "monitor" {
  name   = "drs-monitor"
  role   = aws_iam_role.monitor.id
  policy = data.aws_iam_policy_document.monitor.json
}

resource "aws_lambda_function" "monitor" {
  function_name    = "${var.name}-drs-monitor"
  role             = aws_iam_role.monitor.arn
  runtime          = "python3.12"
  handler          = "replication_monitor.handler"
  filename         = data.archive_file.monitor.output_path
  source_code_hash = data.archive_file.monitor.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = { METRIC_NAMESPACE = local.namespace }
  }

  depends_on = [aws_cloudwatch_log_group.monitor, aws_iam_role_policy.monitor]
}

resource "aws_cloudwatch_event_rule" "monitor_schedule" {
  name                = "${var.name}-drs-monitor"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "monitor_schedule" {
  rule = aws_cloudwatch_event_rule.monitor_schedule.name
  arn  = aws_lambda_function.monitor.arn
}

resource "aws_lambda_permission" "monitor_schedule" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monitor_schedule.arn
}

# ---------------- alarms (DR region) ----------------
resource "aws_cloudwatch_metric_alarm" "unhealthy_servers" {
  alarm_name          = "${var.name}-drs-unhealthy-servers"
  alarm_description   = "One or more DRS source servers are stalled, disconnected, paused or stopped."
  namespace           = local.namespace
  metric_name         = "UnhealthyServers"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching" # no data = the monitor itself is broken
  alarm_actions       = [aws_sns_topic.dr.arn]
  ok_actions          = [aws_sns_topic.dr.arn]
}

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  alarm_name          = "${var.name}-drs-replication-lag"
  alarm_description   = "DRS replication lag above ${var.max_lag_seconds}s - RPO at risk."
  namespace           = local.namespace
  metric_name         = "MaxReplicationLagSeconds"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.max_lag_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.dr.arn]
  ok_actions          = [aws_sns_topic.dr.arn]
}

# ---------------- alarms (primary region) ----------------
resource "aws_cloudwatch_metric_alarm" "prod_unhealthy_hosts" {
  provider            = aws.primary
  alarm_name          = "${var.name}-prod-unhealthy-hosts"
  alarm_description   = "Production targets failing health checks."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.primary_alb_arn_suffix
    TargetGroup  = var.primary_tg_arn_suffix
  }
  alarm_actions = [aws_sns_topic.primary.arn]
  ok_actions    = [aws_sns_topic.primary.arn]
}

resource "aws_cloudwatch_metric_alarm" "prod_5xx" {
  provider            = aws.primary
  alarm_name          = "${var.name}-prod-target-5xx"
  alarm_description   = "Production targets returning 5xx."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.primary_alb_arn_suffix
  }
  alarm_actions = [aws_sns_topic.primary.arn]
}

output "topic_arns" {
  value = {
    dr      = aws_sns_topic.dr.arn
    primary = aws_sns_topic.primary.arn
  }
}
