# Testing and verification

The project uses layered testing. The cheap layers run on every commit without an AWS account. The expensive layers run in your account and produce evidence that the DR design works.

## Static checks (CI, no AWS account)

**Formatting and validation.** `terraform fmt -check -recursive` and `terraform validate` catch syntax errors, wrong references and type mismatches in the root stack and the `bootstrap/` stack.

**Plan-level strategy tests.** `tests/strategies.tftest.hcl` uses `terraform test` with mocked AWS providers, so it needs no credentials and costs nothing. Each run plans the stack with different inputs and asserts on the result:

| Run | Asserts |
|---|---|
| `warm_standby_is_the_default` | One DR instance, Aurora secondary present, failover Lambda present, no DNS without a zone |
| `pilot_light_runs_database_only` | DR web tier at zero, secondary present, failover records, certificates in both regions |
| `backup_restore_runs_nothing_in_dr` | No DR web tier or database, simple record, no Lambda, backups still copied cross-region |
| `multi_site_is_active_active` | Production-size DR tier, latency records to both regions, write forwarding on |
| `dr_activate_scales_to_production` | Activation raises the DR tier to production size |
| `rejects_unknown_strategy` | Input validation rejects unknown strategies |
| `requires_domain_with_hosted_zone` | Input validation requires a domain name with a hosted zone |

Run locally:

```bash
terraform init -backend=false
terraform test
```

**TFLint** with the AWS ruleset flags invalid instance types, deprecated syntax, unused declarations and missing version constraints.

**Checkov** scans for security misconfigurations and uploads results to GitHub code scanning. Intentional exceptions are listed with reasons in `.checkov.yaml`. The job starts in soft-fail mode; after triaging the first report, set `soft-fail: false` so new findings fail the build.

**Python unit tests** cover the application routes (liveness versus deep health, read-only regions returning 503, write-then-read, HTML escaping) and the failover Lambda (ignores OK transitions, skips failover when the site has recovered, dry-run mode, promotes and scales, idempotency when already promoted or in progress, scaling from zero for pilot light). They use fakes, so they need neither AWS nor a database:

```bash
python3 -m unittest discover -s tests/python -v
```

**ShellCheck** lints the runbook scripts.

## Chaos experiments (your AWS account)

Start any template from the console or with:

```bash
aws fis start-experiment --region "$(terraform output -raw primary_region)" \
  --experiment-template-id "$(terraform output -raw fis_terminate_instance_template_id)"
```

Start with the instance termination experiment: it is low-risk and shows Auto Scaling replacing an instance while the error-rate widgets on the dashboard stay flat. The CPU stress experiment should show the primary group scaling out and back in over roughly 15 minutes. The primary outage experiment is the full regional drill; use it through the drill script below.

## The DR drill (your AWS account)

`scripts/dr-drill.sh` runs the whole scenario end to end and measures it:

1. It confirms the primary region is serving traffic.
2. It writes a marker note through the public URL.
3. It starts the primary outage experiment.
4. In `--manual` mode, it runs the unplanned failover after three minutes; otherwise it waits for the Lambda.
5. It polls the public URL until responses come from the DR region (traffic RTO) and until writes succeed there (write RTO).
6. It checks the marker note still exists (RPO).
7. It writes a Markdown report to `drill-results/`.

```bash
./scripts/dr-drill.sh --manual     # first drill: you control the failover
./scripts/dr-drill.sh              # later: with auto_failover_enabled = true
```

Requirements: a hosted zone and domain (traffic must move by DNS), `enable_chaos_experiments = true`, and a replicated strategy.

After the drill, commit the report and copy the numbers into the README table. Then practise failback with `docs/runbook.md` section 5, because a drill is only complete when the system is back in its normal state.

A few notes on reading the results. Your workstation's DNS cache can add up to about a minute to the traffic RTO, since the alias records resolve with a 60-second TTL. The write RTO includes alarm evaluation (about 3 minutes) when running with automation. Any RPO other than zero in a drill is worth investigating, because a healthy global database lags by well under a second.
