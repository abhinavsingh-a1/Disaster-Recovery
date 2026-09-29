# CI/CD

## Pipelines

| Workflow | Trigger | Jobs |
|---|---|---|
| `ci.yml` | PR, push to main | fmt, validate, `terraform test`, bootstrap validate, tflint, checkov (report-only at first), shellcheck, Python compile |
| `deploy.yml` | PR (plan only), push to main (plan + apply), manual | OIDC login; `terraform plan` with summary; `apply` of the saved plan in the protected `production` environment |
| `dr-drill.yml` | 06:00 UTC on day 1 of each month, manual | Runs `scripts/drill-test.sh`; uploads the report (kept 400 days) |

`deploy.yml` and `dr-drill.yml` share a concurrency group, so they never touch the state at the same time.

## Setup

1. Apply `bootstrap/` with `github_repository = "owner/repo"`. It outputs `github_deploy_role_arn`.
2. In GitHub, go to **Settings -> Secrets and variables -> Actions -> Variables** and add:
   - `AWS_ROLE_ARN`: the role ARN
   - `AWS_REGION`: the state bucket Region
   - `TF_STATE_BUCKET`: the bucket name
3. Create the environment **production** with required reviewers. That is the manual approval gate for `apply`.
4. Commit `.terraform.lock.hcl` after the first local `terraform init` so CI uses the same provider builds.
5. Optional: `pre-commit install` for local fmt, validate, tflint and shellcheck hooks.

Without `AWS_ROLE_ARN`, the deploy and drill jobs are skipped, so forks still get green CI.

## Remote state

- S3 bucket: versioned, SSE-KMS, TLS-only policy, public access blocked, old versions expire after 90 days.
- Locking uses the S3 native lockfile (`use_lockfile = true`, Terraform >= 1.10). No DynamoDB table.
- Change `-var-file` in `deploy.yml` (`TF_VAR_FILE`) per environment, or use one state key per environment.

## Hardening the deploy role

Bootstrap attaches `AdministratorAccess` so the first run works. For production:
- Replace it with a policy scoped to the services used: EC2/VPC, ELB, IAM (roles with a project prefix only), KMS, RDS, Secrets Manager, Route 53, DRS, SSM, Lambda, CloudWatch/Logs/Events, SNS, Backup, S3 (state).
- Add a permissions boundary to the roles Terraform creates.
- Restrict the OIDC trust `sub` to `repo:owner/repo:environment:production` for apply, and use a read-only role for PR plans.
