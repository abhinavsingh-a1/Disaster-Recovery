# Costs

Rough monthly on-demand estimate for the **default cross-region lab** (us-east-1/us-east-2, one protected server). Prices change: confirm with the AWS Pricing Calculator.

| Item | Approx. USD/month |
|---|---|
| NAT gateways (prod + DR) | ~66 + data processing |
| Application Load Balancers (2) | ~33 + LCU |
| Public IPv4 addresses (NAT EIPs, ALB nodes) | ~15-25 |
| RDS db.t4g.micro primary (Multi-AZ) + cross-region replica + storage | ~40-50 |
| DRS per source server (~0.028/h) | ~20 |
| Replication server t3.small (24/7) | ~15 |
| Protected server t3.micro + detailed monitoring | ~10 |
| Staging disks, PIT snapshots, Backup storage, cross-region transfer | ~5-15 (grows with data) |
| KMS keys (2), Secrets Manager, Route 53 health check, Lambda, CloudWatch | ~5 |
| **Total** | **~200-260** |

During a drill or recovery, add the recovery instances, the conversion server (minutes) and EBS volumes.

## Cutting costs

- `dr_mode = "cross-az"`: no second Region, no cross-region transfer, no failback template. You still keep two VPCs.
- `db_multi_az = false` (already set in `envs/lab.tfvars`), or `enable_database = false`.
- `enable_flow_logs = false` for short labs.
- Destroy after each session (`make destroy`). DRS itself has no fixed fee.
- In production, the DR side is cheap compared with a warm standby: only replication servers and low-cost staging disks run until you recover.
