module "protected_server" {
  source   = "./modules/protected-server"
  for_each = var.protected_servers

  name                  = "${local.name}-${each.key}"
  instance_type         = each.value.instance_type
  root_volume_size      = each.value.root_volume_size
  subnet_id             = module.network_primary.app_subnet_ids[each.value.az_index]
  security_group_ids    = [aws_security_group.app_primary.id]
  instance_profile_name = aws_iam_instance_profile.source.name
  drs_region            = local.dr_region
  install_agent         = var.install_drs_agent
  dr_group              = local.name

  # Agent needs DRS initialized, the replication template and the private path.
  depends_on = [
    module.drs_dr,
    aws_route.primary_to_dr,
    aws_route.dr_to_primary,
    aws_iam_role_policy_attachment.source_drs,
  ]
}

module "web_alb_primary" {
  source = "./modules/web-alb"

  name              = "${local.name}-prod"
  vpc_id            = module.network_primary.vpc_id
  vpc_cidr          = var.primary_vpc_cidr
  public_subnet_ids = module.network_primary.public_subnet_ids
  allowed_cidrs     = var.allowed_http_cidrs
  certificate_arn   = var.certificate_arn_primary
  targets           = { for k, m in module.protected_server : k => m.instance_id }
}

# DR ALB starts empty; the Recover runbook registers recovery instances.
module "web_alb_dr" {
  source    = "./modules/web-alb"
  providers = { aws = aws.dr }

  name              = "${local.name}-dr"
  vpc_id            = module.network_dr.vpc_id
  vpc_cidr          = var.dr_vpc_cidr
  public_subnet_ids = module.network_dr.public_subnet_ids
  allowed_cidrs     = var.allowed_http_cidrs
  certificate_arn   = var.certificate_arn_dr
  targets           = {}
}
