#!/usr/bin/env bash
# Run BEFORE `terraform destroy`: removes resources DRS created outside Terraform
# (recovery/drill instances, source servers -> replication servers, staging disks).
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

for region in "$DR_REGION" "$PRIMARY_REGION"; do
  log "cleaning DRS in $region"
  ids=$(aws drs describe-recovery-instances --region "$region" --filters '{}' \
    --query 'items[].recoveryInstanceID' --output text 2>/dev/null || true)
  if [[ -n "$ids" && "$ids" != "None" ]]; then
    # shellcheck disable=SC2086
    aws drs terminate-recovery-instances --region "$region" --recovery-instance-ids $ids >/dev/null
    log "terminating recovery instances: $ids"
  fi
  for sid in $(aws drs describe-source-servers --region "$region" --filters '{}' \
      --query 'items[].sourceServerID' --output text 2>/dev/null || true); do
    aws drs disconnect-source-server --region "$region" --source-server-id "$sid" >/dev/null || true
    aws drs delete-source-server --region "$region" --source-server-id "$sid" || true
    log "removed source server $sid"
  done
done
log "wait ~10 min until DRS-managed replication/conversion instances are gone, then: terraform destroy"
log "NOTE: a promoted DB replica and locked backup vaults may need manual steps (docs/RUNBOOK.md)"
