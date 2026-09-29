# Operations runbook

All commands run from the repository root with credentials for the target account. Scripts read IDs from `terraform output`, so run them where the state is initialized.

## 0. Roles

| Role | Responsibility |
|---|---|
| Incident commander | Declares disaster, approves failover and failback |
| Operator | Runs the steps below |
| App owner | Verifies application behavior after each step |

## 1. Deploy

1. Bootstrap the state bucket once (see README).
2. Run `make test lint`, then `make init`, `make plan VAR_FILE=envs/<env>.tfvars` and `make apply`.
3. Confirm the SNS email subscriptions.
4. Wait for initial sync (`make status` shows `CONTINUOUS`).
5. Run the `<name>-PrepareLaunchSettings` runbook once. The Recover runbook also runs it, but running it early makes the DRS console show the final shape.
6. Run `make drill` and file the report.

When you add a protected server, re-apply Terraform. The runbook defaults (instance IDs) are updated automatically.

## 2. Monthly drill (non-disruptive)

```bash
make drill                       # or: scripts/drill-test.sh --keep  (inspect instances, then TerminateDrills)
```
The drill checks replication, launches drill instances from the latest snapshot into the DR VPC, curls `/health.html` inside each instance through SSM, measures RTO, writes `reports/drill-*.md` and terminates the drills. Production is untouched, and drill instances are **not** registered on the DR ALB.

Drill from a specific moment:
```bash
aws ssm start-automation-execution --region <dr-region> \
  --document-name <name>-Recover \
  --parameters Mode=drill,PointInTime=2026-09-29T19:10:00Z
```

## 3. Real failover

Declare the disaster first. Then:

```bash
scripts/failover.sh latest --with-database
# or recover to a point BEFORE a ransomware event:
scripts/failover.sh 2026-09-29T19:10:00Z --with-database
```

What happens:
1. `Recover` with Mode=recovery launches recovery instances in the DR private subnets and registers them on the DR ALB.
2. `FailoverDatabase` promotes the replica and repoints `db.<project>.internal`.
3. **With Route 53:** the primary health check is already failing, so DNS answers with the DR ALB. **Without Route 53:** give users the `dr_url` output or change DNS manually.

Verify:
- `terraform output dr_url` returns the page, and the page shows the original content.
- The DR target group shows its targets as healthy.
- The application can reach the DB. `db.<project>.internal` now resolves to the promoted replica.

> **Ransomware:** choose a `PointInTime` before the infection. For the DB, a replica has already replicated the damage. Restore RDS from an earlier automated backup or from the locked AWS Backup copy instead of promoting the replica.

## 4. Failback (two phases)

**Phase 1: resync (no downtime).**
```bash
scripts/failback.sh
```
This starts reversed replication from the recovery instances to the failback staging area in the primary Region. Wait until the new source servers in the primary Region show `CONTINUOUS`.

**Phase 2: cut-over (short maintenance window).**
1. Stop writes on the DR side.
2. In the **primary Region** DRS console, launch recovery for the reversed source servers. Launch settings there default to DRS values, so review subnet, instance type and SG first.
3. Register the new instances with the production target group (console or `aws elbv2 register-targets`).
4. Database: the old primary is now stale. Recreate replication in the other direction: create a cross-region replica of the promoted DB in the primary Region, then promote it. Or restore from a snapshot. Repoint `db.<project>.internal`.
5. When the Route 53 health check turns healthy, traffic returns automatically.
6. Terminate the DR recovery instances and deregister them from the DR ALB.
7. Restart forward replication: stop reversed replication, and make sure the original source servers replicate to the DR Region again (reinstall the agent if needed).
8. Reconcile Terraform. If a new DB is now primary, import it or rebuild the database module deliberately. **Do not blindly `terraform apply`** after a DB failover: review the plan.

## 5. Teardown

```bash
scripts/cleanup-drs.sh     # recovery instances + source servers in both Regions
# wait ~10 min for DRS-managed replication/conversion servers to disappear
terraform destroy -var-file=envs/lab.tfvars
```
Special cases:
- **Vault Lock:** governance mode requires `backup:DeleteBackupVaultLockConfiguration` (admin) or waiting until recovery points expire. Compliance mode past its grace period: the vault cannot be deleted before retention ends. Plan for that.
- **Promoted replica:** Terraform still manages it by identifier and will delete it. Take a final snapshot first if needed.
- **Stuck staging disks/snapshots:** delete leftover resources tagged `AWSElasticDisasterRecoveryManaged` in the DR Region.

## 6. Troubleshooting

| Symptom | Check |
|---|---|
| Server never appears in DRS | `/var/log/user-data.log` (SSM Session Manager). NAT route present? Instance role has the DRS policy? Region support? |
| Stuck in `INITIATING` / `STALLED` | Staging subnet reaches DRS/EC2/S3 (NAT or endpoints)? TCP 1500 allowed from the source CIDR? Peering routes in **both** private route tables? |
| Lag alarm | Bandwidth throttling, NAT limits, burst credits on the replication server (try a larger type) |
| `Prepare` fails "not registered" | Agent not finished yet. Run `make status` |
| Recover job COMPLETED but runbook fails | A server's launch failed. Open the job log in the DRS console (quota, AMI/licensing, subnet capacity) |
| Recovery instance unhealthy on ALB | Recovery SG allows 80 from the DR ALB SG? Apache enabled at boot? |
| Instance profile rejected at launch | The recovery role name must start with `AWSElasticDisasterRecovery` (DRS PassRole). Kept by default |
| Auto-recovery did nothing | Lambda logs in us-east-1. PassRole on the automation role. Alarm transitioned to ALARM? |
| `terraform destroy` fails on subnets/SGs | DRS resources still exist. Run `cleanup-drs.sh` and wait |
