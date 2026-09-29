# ---------------- KMS (customer-managed keys) ----------------
module "kms_primary" {
  source       = "./modules/kms-key"
  name         = "${local.name}-primary"
  description  = "Primary-region CMK: RDS, AWS Backup, EBS"
  via_services = ["ec2", "rds", "backup", "secretsmanager"]
}

module "kms_dr" {
  source       = "./modules/kms-key"
  providers    = { aws = aws.dr }
  name         = "${local.name}-dr"
  description  = "DR-region CMK: DRS staging disks and snapshots, RDS replica, AWS Backup copies"
  via_services = ["ec2", "rds", "backup", "secretsmanager"]
}

# ---------------- Security groups for application instances ----------------
resource "aws_security_group" "app_primary" {
  name        = "${local.name}-app-prod"
  description = "Protected application servers (production)"
  vpc_id      = module.network_primary.vpc_id

  ingress {
    description     = "HTTP from production ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [module.web_alb_primary.security_group_id]
  }

  egress {
    description = "HTTPS to AWS APIs / package repos, TCP 1500 to DRS replication servers, DB"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "recovery" {
  provider    = aws.dr
  name        = "${local.name}-recovery"
  description = "DRS drill/recovery instances"
  vpc_id      = module.network_dr.vpc_id

  ingress {
    description     = "HTTP from DR ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [module.web_alb_dr.security_group_id]
  }

  egress {
    description = "AWS APIs, reverse replication (TCP 1500) during failback, DB"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- IAM for protected (source) servers ----------------
# The replication agent authenticates with this role - no IAM user access keys.
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
  name               = "${local.name}-source-server"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "source_drs" {
  role       = aws_iam_role.source.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryEc2InstancePolicy"
}

resource "aws_iam_role_policy_attachment" "source_ssm" {
  role       = aws_iam_role.source.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "source_secret" {
  count = var.enable_database ? 1 : 0
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [module.database[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "source_secret" {
  count  = var.enable_database ? 1 : 0
  name   = "read-db-secret"
  role   = aws_iam_role.source.id
  policy = data.aws_iam_policy_document.source_secret[0].json
}

resource "aws_iam_instance_profile" "source" {
  name = "${local.name}-source-server"
  role = aws_iam_role.source.name
}
