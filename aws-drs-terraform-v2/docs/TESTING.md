# Testing strategy

| Layer | Tool | Runs | Catches |
|---|---|---|---|
| Format | `terraform fmt -check` | every PR | style drift |
| Static validation | `terraform validate` | every PR | syntax, types, references |
| Unit | `terraform test` (`tests/unit.tftest.hcl`, mocked providers) | every PR, offline | topology logic, variable validation, optional components wiring |
| Lint | tflint + AWS ruleset | every PR | invalid instance types, unused declarations, deprecated syntax |
| Security | checkov | every PR | misconfigurations (see skips in `.checkov.yaml`) |
| Scripts | shellcheck, `py_compile` | every PR | shell and Python errors |
| Integration | `scripts/drill-test.sh` | after deploy, monthly (GitHub Actions) | the real thing: replication, launch, app response, RTO |

## Unit tests

```bash
terraform init -backend=false
terraform test
```
The tests cover:
- Cross-region is the default: DR Region, failback template, private data plane, PIT retention of 7 or more days.
- cross-az mode: same Region and no duplicate DRS template.
- Multiple protected servers.
- The optional database.
- DNS failover off by default, and on when a zone is given.
- Rejection of invalid input: retention 0, same Region in cross-region mode, DR VPC without NAT or endpoints, unknown vault-lock mode.

They cost nothing and need no credentials. They do **not** prove that AWS accepts the configuration. That is what the integration layer is for.

## First-deployment acceptance checklist

Run this once per new account or Region pair, and file the results:

- [ ] `terraform apply` completes; a second `plan` shows **no changes**.
- [ ] SNS email subscriptions confirmed.
- [ ] `make status`: every server `CONTINUOUS`; `DRS/<project>` metrics appear in CloudWatch; alarms are `OK`.
- [ ] Replication traffic is private: the replication server has no public IP; flow logs show TCP 1500 between the VPC CIDRs.
- [ ] Staging disks and snapshots are encrypted with the `alias/<project>-dr` CMK.
- [ ] `make drill` passes; RTO recorded; drill instances terminated.
- [ ] Drill from an older `PointInTime` launches the expected snapshot.
- [ ] Stop Apache on a production server: the ALB unhealthy-host alarm fires, and with DNS enabled the Route 53 alarm fires after `failover_evaluation_minutes`.
- [ ] In a maintenance window, a full failover (`scripts/failover.sh`) serves traffic from the DR ALB. The app reaches the promoted DB via `db.<project>.internal`.
- [ ] Failback phase 1 reaches `CONTINUOUS` in the primary Region.
- [ ] AWS Backup: a job succeeded, the copy is in the DR vault, and deleting a recovery point is **denied**.
- [ ] `cleanup-drs.sh` + `terraform destroy` leave no orphaned DRS resources (lab accounts).

## Chaos ideas (optional)
Use AWS Fault Injection Service to stop instances or disrupt network in an AZ. Or detach the NAT route to test lag alarms. Confirm that alerts arrive and the runbooks still work.
