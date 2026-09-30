locals {
  name = var.project_name

  # backup_restore keeps nothing running in the DR region except the backup vault
  deploy_dr = var.dr_strategy != "backup_restore"

  # multi_site = both regions take traffic (active-active)
  active_active = var.dr_strategy == "multi_site"

  # DNS records and HTTPS certificates need a hosted zone
  create_dns = var.hosted_zone_id != null

  # Size of the DR web tier for each strategy in normal operation
  dr_capacity_by_strategy = {
    backup_restore = { min = 0, desired = 0, max = 0 }
    pilot_light    = { min = 0, desired = 0, max = var.primary_capacity.max }
    warm_standby   = { min = 1, desired = 1, max = var.primary_capacity.max }
    multi_site     = var.primary_capacity
  }

  # dr_activate = "scale to production" during a disaster
  dr_capacity = var.dr_activate ? var.primary_capacity : lookup(local.dr_capacity_by_strategy, var.dr_strategy, local.dr_capacity_by_strategy.warm_standby)

  app_source = file("${path.module}/app/app.py")

  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}
