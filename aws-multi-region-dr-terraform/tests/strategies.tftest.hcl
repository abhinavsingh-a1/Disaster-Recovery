# Plan-only tests with mocked AWS providers: no credentials, no cost.
# Run with: terraform init -backend=false && terraform test
# They check that each dr_strategy wires up the right resources.

mock_provider "aws" {
  alias = "primary"

  mock_data "aws_availability_zones" {
    override_during = plan
    defaults = { names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"] }
  }
  mock_data "aws_iam_policy_document" {
    override_during = plan
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_region" {
    override_during = plan
    defaults = { name = "eu-central-1" }
  }
  mock_data "aws_caller_identity" {
    override_during = plan
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_ssm_parameter" {
    override_during = plan
    defaults = { value = "ami-0123456789abcdef0" }
  }

  # ACM exposes validation options at plan time in the real provider; mimic that.
  mock_resource "aws_acm_certificate" {
    override_during = plan
    defaults = {
      arn = "arn:aws:acm:eu-central-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [{
        domain_name           = "app.example.com"
        resource_record_name  = "_abc.app.example.com."
        resource_record_type  = "CNAME"
        resource_record_value = "_def.acm-validations.aws."
      }]
    }
  }
}

mock_provider "aws" {
  alias = "dr"

  mock_data "aws_availability_zones" {
    override_during = plan
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
  mock_data "aws_iam_policy_document" {
    override_during = plan
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_region" {
    override_during = plan
    defaults = { name = "eu-west-1" }
  }
  mock_data "aws_caller_identity" {
    override_during = plan
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_ssm_parameter" {
    override_during = plan
    defaults = { value = "ami-0123456789abcdef0" }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

run "warm_standby_is_the_default" {
  command = plan

  assert {
    condition     = output.dr_capacity.min == 1 && output.dr_capacity.desired == 1
    error_message = "warm_standby must keep exactly one DR web instance running."
  }

  assert {
    condition     = length(aws_rds_cluster.dr) == 1 && length(module.app_dr) == 1
    error_message = "warm_standby must deploy the Aurora secondary and the DR web tier."
  }

  assert {
    condition     = length(aws_lambda_function.failover) == 1
    error_message = "The failover Lambda must exist for replicated strategies."
  }

  assert {
    condition     = length(aws_route53_record.failover_primary) == 0
    error_message = "No DNS records without a hosted zone."
  }
}

run "pilot_light_runs_database_only" {
  command = plan

  variables {
    dr_strategy    = "pilot_light"
    hosted_zone_id = "Z0000000000000000000"
    domain_name    = "app.example.com"
  }

  assert {
    condition     = output.dr_capacity.min == 0 && output.dr_capacity.desired == 0
    error_message = "pilot_light must keep the DR web tier at zero instances."
  }

  assert {
    condition     = length(aws_rds_cluster.dr) == 1
    error_message = "pilot_light must keep the Aurora secondary running."
  }

  assert {
    condition     = length(aws_route53_record.failover_primary) == 1 && length(aws_route53_record.failover_secondary) == 1
    error_message = "pilot_light must use Route 53 failover routing."
  }

  assert {
    condition     = length(aws_acm_certificate.primary) == 1 && length(aws_acm_certificate.dr) == 1
    error_message = "With a hosted zone, both regions must get an HTTPS certificate."
  }
}

run "backup_restore_runs_nothing_in_dr" {
  command = plan

  variables {
    dr_strategy    = "backup_restore"
    hosted_zone_id = "Z0000000000000000000"
    domain_name    = "app.example.com"
  }

  assert {
    condition     = length(module.app_dr) == 0 && length(aws_rds_cluster.dr) == 0
    error_message = "backup_restore must not run a DR web tier or database."
  }

  assert {
    condition     = length(aws_route53_record.simple) == 1 && length(aws_route53_record.failover_primary) == 0
    error_message = "backup_restore must use a simple record."
  }

  assert {
    condition     = length(aws_lambda_function.failover) == 0
    error_message = "Nothing to fail over to under backup_restore."
  }

  assert {
    condition     = length([for r in aws_backup_plan.this.rule : r if length(r.copy_action) == 1]) == 1
    error_message = "Backups must still be copied to the DR region."
  }
}

run "multi_site_is_active_active" {
  command = plan

  variables {
    dr_strategy    = "multi_site"
    hosted_zone_id = "Z0000000000000000000"
    domain_name    = "app.example.com"
  }

  assert {
    condition     = output.dr_capacity.desired == 2
    error_message = "multi_site must run the DR web tier at production capacity."
  }

  assert {
    condition     = length(aws_route53_record.latency_primary) == 1 && length(aws_route53_record.latency_dr) == 1
    error_message = "multi_site must use latency routing to both regions."
  }

  assert {
    condition     = aws_rds_cluster.dr[0].enable_global_write_forwarding == true
    error_message = "multi_site must enable Aurora global write forwarding."
  }
}

run "dr_activate_scales_to_production" {
  command = plan

  variables {
    dr_strategy = "pilot_light"
    dr_activate = true
  }

  assert {
    condition     = output.dr_capacity.min == 2
    error_message = "dr_activate must raise the DR web tier to production size."
  }
}

run "rejects_unknown_strategy" {
  command = plan

  variables {
    dr_strategy = "cold_standby"
  }

  expect_failures = [var.dr_strategy]
}

run "requires_domain_with_hosted_zone" {
  command = plan

  variables {
    hosted_zone_id = "Z0000000000000000000"
  }

  expect_failures = [var.domain_name]
}
