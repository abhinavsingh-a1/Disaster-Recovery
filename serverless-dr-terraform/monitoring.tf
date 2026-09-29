###############################################################################
# Replication-lag alarm (one of the "challenges" in the talk).
# DynamoDB publishes ReplicationLatency in the SOURCE region, per receiving region.
###############################################################################

resource "aws_cloudwatch_metric_alarm" "replication_latency_primary_to_dr" {
  provider = aws.primary

  alarm_name          = "${var.project_name}-replication-latency-${var.primary_region}-to-${var.dr_region}"
  alarm_description   = "Global table replication lag ${var.primary_region} -> ${var.dr_region} is above ${var.replication_latency_threshold_ms} ms"
  namespace           = "AWS/DynamoDB"
  metric_name         = "ReplicationLatency"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.replication_latency_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName       = module.global_table.table_name
    ReceivingRegion = var.dr_region
  }

  alarm_actions = var.alarm_sns_topic_arn == "" ? [] : [var.alarm_sns_topic_arn]
  ok_actions    = var.alarm_sns_topic_arn == "" ? [] : [var.alarm_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "replication_latency_dr_to_primary" {
  provider = aws.dr

  alarm_name          = "${var.project_name}-replication-latency-${var.dr_region}-to-${var.primary_region}"
  alarm_description   = "Global table replication lag ${var.dr_region} -> ${var.primary_region} is above ${var.replication_latency_threshold_ms} ms"
  namespace           = "AWS/DynamoDB"
  metric_name         = "ReplicationLatency"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.replication_latency_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName       = module.global_table.table_name
    ReceivingRegion = var.primary_region
  }
}
