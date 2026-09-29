# IAM user used once to install the AWS Replication Agent on the source server
# (video: user "edr-demo", programmatic access,
#  policy AWSElasticDisasterRecoveryAgentInstallationPolicy).
resource "aws_iam_user" "drs_agent" {
  name = "${local.name}-drs-agent-installer"
}

resource "aws_iam_user_policy_attachment" "drs_agent" {
  user       = aws_iam_user.drs_agent.name
  policy_arn = "${local.policy_arn_prefix}/AWSElasticDisasterRecoveryAgentInstallationPolicy"
}

resource "aws_iam_access_key" "drs_agent" {
  count = var.create_agent_access_key ? 1 : 0
  user  = aws_iam_user.drs_agent.name
}

# Optional IAM user for the DRS Failback Client
# (policy AWSElasticDisasterRecoveryFailbackInstallationPolicy).
resource "aws_iam_user" "drs_failback" {
  count = var.create_failback_user ? 1 : 0
  name  = "${local.name}-drs-failback"
}

resource "aws_iam_user_policy_attachment" "drs_failback" {
  count      = var.create_failback_user ? 1 : 0
  user       = aws_iam_user.drs_failback[0].name
  policy_arn = "${local.policy_arn_prefix}/AWSElasticDisasterRecoveryFailbackInstallationPolicy"
}

resource "aws_iam_access_key" "drs_failback" {
  count = var.create_failback_user ? 1 : 0
  user  = aws_iam_user.drs_failback[0].name
}

# Instance role for the source server: SSM Session Manager replaces the
# "Connect" button from the video and lets scripts/install-agent.sh run remotely.
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "source" {
  name               = "${local.name}-source-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "source_ssm" {
  role       = aws_iam_role.source.name
  policy_arn = "${local.policy_arn_prefix}/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "source" {
  name = "${local.name}-source-server-profile"
  role = aws_iam_role.source.name
}
