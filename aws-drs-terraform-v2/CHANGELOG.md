# Changelog

## v2.0.0 - DR platform

Upgrade of the v1 cross-AZ console demo. It addresses the ten gaps found in the v1 review:

| # | v1 gap | v2 solution |
|---|---|---|
| 1 | Untested | `terraform test` unit suite (mocked, offline), tflint, checkov, shellcheck in CI; `scripts/drill-test.sh` end-to-end drill with RTO report; monthly drill workflow; acceptance checklist (docs/TESTING.md) |
| 2 | Manual Elastic IP failover | Production and DR ALBs; Route 53 failover records with health check; runbook registers recovery instances; optional auto-recovery Lambda |
| 3 | AZ-only | `dr_mode = cross-region` (default) with DR Region, failback staging in the primary Region; `cross-az` still available |
| 4 | Public subnets / public replication | Private app/db/staging subnets, ALBs only public, `PRIVATE_IP` replication over VPC peering, optional VPC endpoints, flow logs, SSM instead of SSH |
| 5 | Shell scripts | SSM Automation runbooks (Prepare, Recover, FailoverDatabase, Failback, TerminateDrills); scripts are thin wrappers |
| 6 | No monitoring | Replication metrics Lambda, lag/unhealthy alarms, DRS EventBridge events, ALB alarms, Route 53 alarm, SNS email |
| 7 | 1-day retention, default key | 7-day PIT default, CMKs, AWS Backup daily with cross-region copy and Vault Lock |
| 8 | No CI/CD, local state | S3 remote state with native locking, bootstrap stack, GitHub OIDC, plan/approve/apply pipeline, pre-commit |
| 9 | Not reusable | Ten modules; `protected_servers` map; tfvars per environment |
| 10 | No DB/DNS/secrets | RDS Multi-AZ + cross-region replica, replicated Secrets Manager secret, private DNS name that follows DB failover |

### Breaking changes vs v1
- IAM user access keys for the agent are gone (instance role).
- Recovery happens in a separate VPC/Region; the EIP workflow is removed.
- State must be migrated to the S3 backend.

## v1.0.0
- Single-Region cross-AZ lab reproducing the console walkthrough: source EC2 with Apache, DRS replication template, manual launch settings, recovery and EIP failover scripts.
