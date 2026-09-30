# Disaster recovery runbook

This runbook assumes you run commands from the repository root with credentials for the account, and that the Terraform state bucket lives in the DR region (the `bootstrap/` default), so `terraform output` works even when the primary region is down.

## Roles of each tool during an incident

| Situation | Use | Why |
|---|---|---|
| Primary region down, automation enabled | Nothing, then watch | The failover Lambda promotes and scales by itself |
| Primary region down, automation disabled | `scripts/failover.sh unplanned` | You decide; the Lambda already told you what to do |
| Planned move (drill, maintenance, failback) | `scripts/failover.sh planned` | Switchover waits for replication, so no data is lost |
| Data corrupted or deleted (both regions affected) | AWS Backup restore | Replication copied the damage; only backups predate it |
| `backup_restore` strategy | AWS Backup restore plus Terraform | Nothing is running in the DR region to fail over to |

## 1. Detect and decide

You are alerted by the `primary-site-down` alarm (SNS e-mail from `us-east-1`), by the load balancer 5xx or unhealthy-host alarms, or by users. Before acting, check three things.

First, the CloudWatch dashboard (`terraform output -raw dashboard_url`): is the primary health check red, and is the DR site green?

Second, the AWS Health Dashboard: is this a regional AWS event or something in your own stack?

Third, replication lag on the dashboard. A recent lag of a few hundred milliseconds means an unplanned failover loses at most that much data. A lag of minutes means a larger potential loss; decide deliberately.

If the primary is only degraded (a bad deployment, for example), rolling back is usually faster and safer than a regional failover.

## 2. Unplanned failover (primary region unavailable)

```bash
./scripts/failover.sh unplanned
```

The script calls `aws rds failover-global-cluster --allow-data-loss` against the DR region, raises the DR Auto Scaling group to production size, and waits until the DR cluster reports as the writer. Route 53 has usually already moved traffic by the time you run it. Afterwards:

```bash
# keep Terraform from shrinking the DR site on the next apply
sed -i 's/^dr_activate *=.*/dr_activate = true/' terraform.tfvars
```

Do not run `terraform apply` for the whole stack while the primary region is unavailable: refreshing resources there will stall or fail.

Verify the result:

```bash
curl -s "$(terraform output -raw app_url)/api/whoami"   # region should be the DR region, db_writable true
```

## 3. Planned switchover (drills and maintenance)

```bash
./scripts/failover.sh planned
```

`switchover-global-cluster` waits for the secondary to catch up before swapping roles, so no committed write is lost. Traffic follows only when the primary health check fails, so for a pure database drill you can also point users at the DR site manually by temporarily lowering the primary's capacity to zero, or by running the FIS outage experiment.

## 4. Restore from backup (`backup_restore`, or logical corruption)

1. Find the recovery point. Use the most recent one for a regional outage, or the last one before the corruption:

   ```bash
   aws backup list-recovery-points-by-backup-vault --region "$(terraform output -raw dr_region)" \
     --backup-vault-name "$(terraform output -raw backup_vault_dr)"
   ```

2. Build the DR stack from code. Set `dr_strategy = "pilot_light"` and apply. With the primary region down, apply only the DR-side resources with `-target` (the DR network, DR app module and DR database resources), because the global cluster APIs in the primary region are unavailable. For corruption with both regions healthy, a normal apply works.

3. Restore the Aurora recovery point into the DR VPC's database subnets, from the AWS Backup console or with `aws backup start-restore-job` and restore metadata that names the DB subnet group and security group created in step 2.

4. Point the application at the restored cluster. Put its endpoint in the app configuration (`db_host`) or rename the restored cluster, then run an instance refresh on the DR Auto Scaling group.

5. Re-point DNS. With `backup_restore` the record is a simple record to the primary; change `dr_strategy` to a replicated strategy (step 2) so failover records exist, or update the record manually.

Expect hours for this path. That is the RTO this strategy accepts in exchange for its low cost.

## 5. Failback (return to the primary region)

After the primary region recovers, the old primary cluster is detached or out of date. The procedure is:

1. Confirm the primary region is healthy in the AWS Health Dashboard.
2. Re-create the old primary as a secondary of the current writer. Remove the stale cluster if Aurora left it detached, then add a cluster in the primary region to the global cluster, from the console or with `aws rds create-db-cluster --global-cluster-identifier ...`. Wait until replication lag is low.
3. In a quiet window, run a planned switchover back. `failover.sh planned` targets the DR cluster, so for failback run the same command with the primary cluster ARN (`terraform output -raw primary_db_cluster_arn`):

   ```bash
   aws rds switchover-global-cluster --region <dr-region> \
     --global-cluster-identifier "$(terraform output -raw global_cluster_id)" \
     --target-db-cluster-identifier "$(terraform output -raw primary_db_cluster_arn)"
   ```

4. Set `dr_activate = false`, then run `terraform plan`. If the re-created cluster's identifier or settings differ from the configuration, align them with `terraform import` or `terraform state rm` plus import until the plan is clean.
5. Apply. The DR web tier returns to its standby size.

Rehearse failback during drills; it is the part of DR teams most often skip.

## 6. After every incident or drill

Record timings in `drill-results/` (the drill script does this for you) and update the measured RTO/RPO table in the README. Review whether alarms fired early enough and whether anyone had to improvise a step. Then update this runbook. A DR plan is only as good as its last successful drill.
