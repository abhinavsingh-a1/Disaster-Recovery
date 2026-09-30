# ---------------------------------------------------------------------------
# Route 53
#   Health check on the primary site: always created, because it drives the
#   outage alarm and the failover Lambda even without a hosted zone.
#   Records (only with hosted_zone_id):
#     backup_restore            : simple record -> primary ALB
#     pilot_light / warm_standby: failover routing (PRIMARY health-checked, SECONDARY = DR)
#     multi_site                : latency routing, both regions health-checked
#   The health check hits /health on port 80. The HTTP listener forwards
#   /health* to the app (everything else redirects to HTTPS), and /health
#   checks database connectivity, so a dead database also triggers failover.
# ---------------------------------------------------------------------------
resource "aws_route53_health_check" "primary" {
  provider          = aws.primary
  fqdn              = module.app_primary.alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  request_interval  = var.health_check_interval
  failure_threshold = 3

  tags = {
    Name = "${local.name}-primary"
  }
}

resource "aws_route53_health_check" "dr" {
  count             = local.deploy_dr ? 1 : 0
  provider          = aws.primary
  fqdn              = module.app_dr[0].alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  request_interval  = var.health_check_interval
  failure_threshold = 3

  tags = {
    Name = "${local.name}-dr"
  }
}

# ---------------------------- backup_restore -------------------------------
resource "aws_route53_record" "simple" {
  count    = local.create_dns && !local.deploy_dr ? 1 : 0
  provider = aws.primary
  zone_id  = var.hosted_zone_id
  name     = var.domain_name
  type     = "A"

  alias {
    name                   = module.app_primary.alb_dns_name
    zone_id                = module.app_primary.alb_zone_id
    evaluate_target_health = true
  }
}

# ---------------------- pilot_light / warm_standby -------------------------
resource "aws_route53_record" "failover_primary" {
  count           = local.create_dns && local.deploy_dr && !local.active_active ? 1 : 0
  provider        = aws.primary
  zone_id         = var.hosted_zone_id
  name            = var.domain_name
  type            = "A"
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = module.app_primary.alb_dns_name
    zone_id                = module.app_primary.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "failover_secondary" {
  count          = local.create_dns && local.deploy_dr && !local.active_active ? 1 : 0
  provider       = aws.primary
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "dr"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name    = module.app_dr[0].alb_dns_name
    zone_id = module.app_dr[0].alb_zone_id
    # false: in pilot light the DR ALB has no instances until it is scaled up,
    # but Route 53 must still send traffic there once the primary is down.
    evaluate_target_health = false
  }
}

# ------------------------------ multi_site ---------------------------------
resource "aws_route53_record" "latency_primary" {
  count           = local.create_dns && local.active_active ? 1 : 0
  provider        = aws.primary
  zone_id         = var.hosted_zone_id
  name            = var.domain_name
  type            = "A"
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  latency_routing_policy {
    region = var.primary_region
  }

  alias {
    name                   = module.app_primary.alb_dns_name
    zone_id                = module.app_primary.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "latency_dr" {
  count           = local.create_dns && local.active_active ? 1 : 0
  provider        = aws.primary
  zone_id         = var.hosted_zone_id
  name            = var.domain_name
  type            = "A"
  set_identifier  = "dr"
  health_check_id = aws_route53_health_check.dr[0].id

  latency_routing_policy {
    region = var.dr_region
  }

  alias {
    name                   = module.app_dr[0].alb_dns_name
    zone_id                = module.app_dr[0].alb_zone_id
    evaluate_target_health = true
  }
}
