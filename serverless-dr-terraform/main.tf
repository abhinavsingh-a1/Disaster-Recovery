###############################################################################
# 1. Lambda source package (shared by both regions - same code everywhere)
###############################################################################
data "archive_file" "notes" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/notes.zip"
}

###############################################################################
# 2. Global data layer: ONE DynamoDB global table, replica in the DR region.
#    Deployed once (the talk puts this in its own "infra" stack for the same
#    reason: it is a global construct, not a per-region one).
###############################################################################
module "global_table" {
  source = "./modules/dynamodb-global-table"

  providers = {
    aws = aws.primary
  }

  table_name      = var.table_name
  replica_regions = [var.dr_region]
}

###############################################################################
# 3. Regional application stacks: identical API Gateway + Lambda in each region
###############################################################################
data "aws_route53_zone" "this" {
  provider     = aws.primary
  name         = var.hosted_zone_name
  private_zone = false
}

module "api_primary" {
  source = "./modules/regional-api"

  providers = {
    aws = aws.primary
  }

  name_prefix        = var.project_name
  stage_name         = var.stage_name
  table_name         = module.global_table.table_name
  domain_name        = local.api_domain_name
  hosted_zone_id     = data.aws_route53_zone.this.zone_id
  lambda_zip_path    = data.archive_file.notes.output_path
  lambda_zip_hash    = data.archive_file.notes.output_base64sha256
  log_retention_days = var.log_retention_days

  depends_on = [module.global_table]
}

module "api_dr" {
  source = "./modules/regional-api"

  providers = {
    aws = aws.dr
  }

  name_prefix        = var.project_name
  stage_name         = var.stage_name
  table_name         = module.global_table.table_name
  domain_name        = local.api_domain_name
  hosted_zone_id     = data.aws_route53_zone.this.zone_id
  lambda_zip_path    = data.archive_file.notes.output_path
  lambda_zip_hash    = data.archive_file.notes.output_base64sha256
  log_retention_days = var.log_retention_days

  # The replica table must exist before the DR Lambdas are granted access to it.
  depends_on = [module.global_table]
}
