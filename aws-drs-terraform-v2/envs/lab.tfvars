# Cheapest sensible cross-region lab. Destroy after testing.
project_name            = "drs-lab"
primary_region          = "us-east-1"
dr_mode                 = "cross-region"
dr_region               = "us-east-2"
snapshot_retention_days = 7
enable_database         = true
db_multi_az             = false
backup_vault_lock_mode  = "governance"
alert_emails            = []
