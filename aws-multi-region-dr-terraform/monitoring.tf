# ---------------------------------------------------------------------------
# Alerting: one SNS topic per region (CloudWatch alarms can only notify a
# topic in their own region) plus one in us-east-1 for the Route 53 alarm.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts_primary" {
  provider = aws.primary
  name     = "${local.name}-alerts"
}

resource "aws_sns_topic" "alerts_dr" {
  provider = aws.dr
  name     = "${local.name}-alerts"
}

resource "aws_sns_topic" "alerts_global" {
  provider = aws.us_east_1
  name     = "${local.name}-alerts-global"
}

# Allow EventBridge (backup failures) to publish to the primary topic
data "aws_iam_policy_document" "alerts_primary" {
  provider = aws.primary

  statement {
    sid       = "AllowEventBridge"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts_primary.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }

  statement {
    sid       = "AllowCloudWatch"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts_primary.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts_primary" {
  provider = aws.primary
  arn      = aws_sns_topic.alerts_primary.arn
  policy   = data.aws_iam_policy_document.alerts_primary.json
}

resource "aws_sns_topic_subscription" "email_primary" {
  count     = var.alert_email != null ? 1 : 0
  provider  = aws.primary
  topic_arn = aws_sns_topic.alerts_primary.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "email_dr" {
  count     = var.alert_email != null ? 1 : 0
  provider  = aws.dr
  topic_arn = aws_sns_topic.alerts_dr.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "email_global" {
  count     = var.alert_email != null ? 1 : 0
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alerts_global.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# The outage detector: primary health check failing for 3 consecutive minutes.
# Notifies people AND triggers the failover Lambda (automation.tf).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "primary_site_down" {
  provider            = aws.us_east_1
  alarm_name          = "${local.name}-primary-site-down"
  alarm_description   = "Route 53 health check for the primary site has failed for 3 minutes."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  alarm_actions = [aws_sns_topic.alerts_global.arn]
  ok_actions    = [aws_sns_topic.alerts_global.arn]
}

# Live RPO: how far the DR copy of the database is behind the writer
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  count               = local.deploy_dr ? 1 : 0
  provider            = aws.dr
  alarm_name          = "${local.name}-aurora-replication-lag"
  alarm_description   = "Aurora Global Database replication lag above ${var.replication_lag_alarm_ms} ms: the DR copy is falling behind (RPO at risk)."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.replication_lag_alarm_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.dr[0].cluster_identifier
  }

  alarm_actions = [aws_sns_topic.alerts_dr.arn]
  ok_actions    = [aws_sns_topic.alerts_dr.arn]
}

# ---------------------------------------------------------------------------
# One dashboard with both regions side by side
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "dr" {
  provider       = aws.primary
  dashboard_name = "${local.name}-disaster-recovery"

  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "Site health (1 = healthy)"
            region = "us-east-1"
            view   = "timeSeries"
            stat   = "Minimum"
            period = 60
            metrics = concat(
              [["AWS/Route53", "HealthCheckStatus", "HealthCheckId", aws_route53_health_check.primary.id, { label = "primary" }]],
              local.deploy_dr ? [["AWS/Route53", "HealthCheckStatus", "HealthCheckId", aws_route53_health_check.dr[0].id, { label = "dr" }]] : []
            )
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "Requests per minute"
            view   = "timeSeries"
            stat   = "Sum"
            period = 60
            metrics = concat(
              [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.app_primary.alb_arn_suffix, { region = var.primary_region, label = "primary" }]],
              local.deploy_dr ? [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.app_dr[0].alb_arn_suffix, { region = var.dr_region, label = "dr" }]] : []
            )
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "HTTP 5xx"
            view   = "timeSeries"
            stat   = "Sum"
            period = 60
            metrics = concat(
              [
                ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", module.app_primary.alb_arn_suffix, { region = var.primary_region, label = "primary ALB" }],
                ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.app_primary.alb_arn_suffix, { region = var.primary_region, label = "primary app" }]
              ],
              local.deploy_dr ? [
                ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", module.app_dr[0].alb_arn_suffix, { region = var.dr_region, label = "dr ALB" }],
                ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.app_dr[0].alb_arn_suffix, { region = var.dr_region, label = "dr app" }]
              ] : []
            )
          }
        }
      ],
      local.deploy_dr ? [
        {
          type   = "metric"
          x      = 12
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "Aurora replication lag, ms (live RPO)"
            region = var.dr_region
            view   = "timeSeries"
            stat   = "Maximum"
            period = 60
            metrics = [
              ["AWS/RDS", "AuroraGlobalDBReplicationLag", "DBClusterIdentifier", aws_rds_cluster.dr[0].cluster_identifier]
            ]
          }
        }
      ] : []
    )
  })
}
