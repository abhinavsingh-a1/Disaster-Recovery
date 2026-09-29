locals {
  api_domain_name = "${var.api_subdomain}.${var.hosted_zone_name}"

  common_tags = {
    Project     = var.project_name
    ManagedBy   = "terraform"
    DRStrategy  = "multi-site-active-active"
  }

  # Region map used for the Route 53 latency records / health checks.
  regions = {
    primary = {
      region    = var.primary_region
      api       = module.api_primary
      invert_hc = var.simulate_primary_failure
    }
    dr = {
      region    = var.dr_region
      api       = module.api_dr
      invert_hc = false
    }
  }
}
