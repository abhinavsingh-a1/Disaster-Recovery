# Offline unit tests: `terraform init -backend=false && terraform test`
# Providers are mocked, so no AWS credentials or cost. They verify topology
# logic, input validation and module wiring at plan time.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
}

mock_provider "aws" {
  alias = "dr"
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-2a", "us-east-2b", "us-east-2c", "us-east-2d"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

mock_provider "aws" {
  alias = "global"
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

run "cross_region_is_default" {
  command = plan

  assert {
    condition     = output.effective_dr_region == "us-east-2"
    error_message = "Default DR region should be us-east-2."
  }
  assert {
    condition     = output.failback_staging_enabled
    error_message = "Cross-region mode needs a failback staging area in the primary region."
  }
  assert {
    condition     = output.data_plane_routing == "PRIVATE_IP"
    error_message = "Replication must use private IPs."
  }
  assert {
    condition     = output.pit_retention_days >= 7
    error_message = "Default PIT retention must be at least 7 days (ransomware)."
  }
  assert {
    condition     = length(module.drs_primary) == 1
    error_message = "Failback DRS template expected in cross-region mode."
  }
}

run "cross_az_mode" {
  command = plan
  variables {
    dr_mode = "cross-az"
  }

  assert {
    condition     = output.effective_dr_region == var.primary_region
    error_message = "cross-az mode must recover in the primary region."
  }
  assert {
    condition     = !output.failback_staging_enabled && length(module.drs_primary) == 0
    error_message = "cross-az mode must not create a second DRS template in the same region."
  }
}

run "multiple_protected_servers" {
  command = plan
  variables {
    protected_servers = {
      web-1 = { az_index = 0 }
      web-2 = { az_index = 1, instance_type = "t3.small" }
    }
  }

  assert {
    condition     = output.protected_server_names == ["web-1", "web-2"]
    error_message = "Both servers should be protected."
  }
}

run "database_optional" {
  command = plan
  variables {
    enable_database = false
  }

  assert {
    condition     = length(module.database) == 0 && output.database == null
    error_message = "Database tier should be skipped."
  }
}

run "dns_failover_off_by_default" {
  command = plan

  assert {
    condition     = !output.failover_dns_enabled && length(module.failover_dns) == 0
    error_message = "DNS failover must be opt-in."
  }
}

run "dns_failover_on" {
  command = plan
  variables {
    hosted_zone_id        = "Z0000000000000000000"
    dns_record_name       = "app.example.com"
    auto_recovery_enabled = true
  }

  assert {
    condition     = output.failover_dns_enabled && output.app_url == "http://app.example.com"
    error_message = "DNS failover should be wired when a hosted zone is given."
  }
}

run "rejects_short_retention" {
  command = plan
  variables {
    snapshot_retention_days = 0
  }
  expect_failures = [var.snapshot_retention_days]
}

run "rejects_same_region_cross_region" {
  command = plan
  variables {
    dr_region = "us-east-1"
  }
  expect_failures = [var.dr_region]
}

run "rejects_dr_without_connectivity" {
  command = plan
  variables {
    dr_enable_nat_gateway   = false
    dr_enable_vpc_endpoints = false
  }
  expect_failures = [var.dr_enable_vpc_endpoints]
}

run "rejects_bad_vault_lock_mode" {
  command = plan
  variables {
    backup_vault_lock_mode = "strict"
  }
  expect_failures = [var.backup_vault_lock_mode]
}
