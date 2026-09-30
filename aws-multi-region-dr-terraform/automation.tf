# ---------------------------------------------------------------------------
# Automated failover
#   primary_site_down alarm (us-east-1) -> SNS (us-east-1) -> Lambda (DR region)
# The Lambda re-checks the health check, then (if auto_failover_enabled)
# promotes the Aurora secondary and scales the DR web tier to production.
# With auto_failover_enabled = false it only reports what it would do.
# Not created for backup_restore: there is nothing running to fail over to.
# ---------------------------------------------------------------------------
data "archive_file" "failover" {
  type        = "zip"
  source_file = "${path.module}/lambda/failover/handler.py"
  output_path = "${path.module}/.build/failover.zip"
}

data "aws_iam_policy_document" "failover_assume" {
  provider = aws.dr

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "failover" {
  count    = local.deploy_dr ? 1 : 0
  provider = aws.dr

  statement {
    sid       = "ReadHealth"
    actions   = ["route53:GetHealthCheckStatus"]
    resources = ["arn:aws:route53:::healthcheck/${aws_route53_health_check.primary.id}"]
  }

  statement {
    sid = "PromoteDatabase"
    actions = [
      "rds:FailoverGlobalCluster",
      "rds:DescribeGlobalClusters",
      "rds:DescribeDBClusters",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DescribeScaling"
    actions   = ["autoscaling:DescribeAutoScalingGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "ScaleDrWebTier"
    actions   = ["autoscaling:UpdateAutoScalingGroup"]
    resources = [module.app_dr[0].asg_arn]
  }

  statement {
    sid       = "Notify"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts_dr.arn]
  }
}

resource "aws_iam_role" "failover" {
  count              = local.deploy_dr ? 1 : 0
  provider           = aws.dr
  name               = "${local.name}-failover-lambda"
  assume_role_policy = data.aws_iam_policy_document.failover_assume.json
}

resource "aws_iam_role_policy" "failover" {
  count    = local.deploy_dr ? 1 : 0
  provider = aws.dr
  name     = "failover"
  role     = aws_iam_role.failover[0].id
  policy   = data.aws_iam_policy_document.failover[0].json
}

resource "aws_iam_role_policy_attachment" "failover_logs" {
  count      = local.deploy_dr ? 1 : 0
  provider   = aws.dr
  role       = aws_iam_role.failover[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "failover_xray" {
  count      = local.deploy_dr ? 1 : 0
  provider   = aws.dr
  role       = aws_iam_role.failover[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_cloudwatch_log_group" "failover" {
  count             = local.deploy_dr ? 1 : 0
  provider          = aws.dr
  name              = "/aws/lambda/${local.name}-failover"
  retention_in_days = 90
}

resource "aws_lambda_function" "failover" {
  count            = local.deploy_dr ? 1 : 0
  provider         = aws.dr
  function_name    = "${local.name}-failover"
  description      = "Promotes the DR region when the primary site is down"
  role             = aws_iam_role.failover[0].arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.failover.output_path
  source_code_hash = data.archive_file.failover.output_base64sha256
  timeout          = 120
  memory_size      = 256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      AUTO_FAILOVER_ENABLED = tostring(var.auto_failover_enabled)
      HEALTH_CHECK_ID       = aws_route53_health_check.primary.id
      GLOBAL_CLUSTER_ID     = aws_rds_global_cluster.this.id
      DR_CLUSTER_ARN        = aws_rds_cluster.dr[0].arn
      DR_REGION             = var.dr_region
      DR_ASG_NAME           = module.app_dr[0].asg_name
      PRODUCTION_CAPACITY   = tostring(var.primary_capacity.desired)
      NOTIFY_TOPIC_ARN      = aws_sns_topic.alerts_dr.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.failover]
}

# Cross-region SNS -> Lambda subscription (topic in us-east-1, function in DR)
resource "aws_lambda_permission" "failover_sns" {
  count         = local.deploy_dr ? 1 : 0
  provider      = aws.dr
  statement_id  = "AllowAlarmTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failover[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts_global.arn
}

resource "aws_sns_topic_subscription" "failover_trigger" {
  count     = local.deploy_dr ? 1 : 0
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alerts_global.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.failover[0].arn

  depends_on = [aws_lambda_permission.failover_sns]
}
