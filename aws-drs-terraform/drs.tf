# ---------------------------------------------------------------------------
# 1. Initialize Elastic Disaster Recovery in the region (one-time, per region).
#    There is no Terraform resource for this, so the AWS CLI is used.
# ---------------------------------------------------------------------------
resource "terraform_data" "drs_init" {
  count = var.initialize_drs ? 1 : 0
  input = var.region

  provisioner "local-exec" {
    command = "aws drs initialize-service --region ${var.region} || echo 'DRS already initialized in ${var.region}'"
  }
}

# ---------------------------------------------------------------------------
# 2. Default replication settings (video: "Replication settings" wizard).
#    Applies to every source server that registers in this region.
#    If a template already exists (e.g. created in the console), import it:
#      terraform import aws_drs_replication_configuration_template.this <template-id>
# ---------------------------------------------------------------------------
resource "aws_drs_replication_configuration_template" "this" {
  # Step 1 - staging area
  staging_area_subnet_id           = aws_subnet.this["staging"].id
  replication_server_instance_type = var.replication_server_instance_type
  use_dedicated_replication_server = false

  # Step 2 - volumes & security groups
  default_large_staging_disk_type         = var.staging_disk_type
  ebs_encryption                          = "DEFAULT"
  associate_default_security_group        = true # DRS creates SG allowing TCP 1500
  replication_servers_security_groups_ids = []

  # Step 3 - data routing & throttling
  data_plane_routing   = var.use_private_ip_for_replication ? "PRIVATE_IP" : "PUBLIC_IP"
  create_public_ip     = !var.use_private_ip_for_replication
  bandwidth_throttling = var.bandwidth_throttling_mbps

  # Step 4 - point-in-time (PIT) snapshot policy (DRS defaults, 7-day daily retention)
  pit_policy {
    rule_id            = 1
    enabled            = true
    interval           = 10
    retention_duration = 60
    units              = "MINUTE"
  }

  pit_policy {
    rule_id            = 2
    enabled            = true
    interval           = 1
    retention_duration = 24
    units              = "HOUR"
  }

  pit_policy {
    rule_id            = 3
    enabled            = true
    interval           = 1
    retention_duration = var.pit_retention_days
    units              = "DAY"
  }

  staging_area_tags = local.staging_area_tags

  depends_on = [
    terraform_data.drs_init,
    aws_route_table_association.this,
  ]
}

# ---------------------------------------------------------------------------
# 3. Launch settings (instance type, recovery subnet, public IP) are per
#    source server and only exist after the agent registers the server, so
#    they are applied by scripts/configure-launch.sh using the outputs below.
# ---------------------------------------------------------------------------
