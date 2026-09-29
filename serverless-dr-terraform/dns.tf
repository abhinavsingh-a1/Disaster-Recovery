###############################################################################
# Route 53: one name (api.<zone>), two latency-based alias records.
# If a region's health check fails (or its alias target is unhealthy),
# Route 53 stops answering with that region and all traffic goes to the other.
###############################################################################

resource "aws_route53_health_check" "api" {
  for_each = var.enable_health_checks ? local.regions : {}

  type              = "HTTPS"
  fqdn              = each.value.api.execute_api_host
  port              = 443
  resource_path     = "/${var.stage_name}/health"
  request_interval  = 30
  failure_threshold = 3
  measure_latency   = true

  # Failover drill: an inverted check reports "unhealthy" while the region is fine.
  invert_healthcheck = each.value.invert_hc

  tags = {
    Name = "${var.project_name}-${each.value.region}-health"
  }
}

resource "aws_route53_record" "api_latency" {
  for_each = local.regions

  zone_id        = data.aws_route53_zone.this.zone_id
  name           = local.api_domain_name
  type           = "A"
  set_identifier = "${var.project_name}-${each.value.region}"

  latency_routing_policy {
    region = each.value.region
  }

  alias {
    name                   = each.value.api.regional_domain_name
    zone_id                = each.value.api.regional_zone_id
    evaluate_target_health = true
  }

  health_check_id = var.enable_health_checks ? aws_route53_health_check.api[each.key].id : null
}
