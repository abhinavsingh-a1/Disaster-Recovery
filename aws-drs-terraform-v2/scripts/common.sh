#!/usr/bin/env bash
# Shared helpers. Run scripts from the repository root after `terraform apply`.
set -euo pipefail

for bin in terraform aws jq; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done

TF_OUT="$(terraform output -json)"
tf() { jq -r "$1" <<<"$TF_OUT"; }

DR_REGION="$(tf '.effective_dr_region.value')"
PRIMARY_REGION="$(tf '.primary_region.value')"
DOC_PREPARE="$(tf '.automation_documents.value.prepare')"
DOC_RECOVER="$(tf '.automation_documents.value.recover')"
DOC_FAILBACK="$(tf '.automation_documents.value.failback')"
DOC_TERMINATE="$(tf '.automation_documents.value.terminate_drills')"
DOC_DB="$(tf '.automation_documents.value.failover_database')"
mapfile -t SOURCE_INSTANCE_IDS < <(tf '.protected_instance_ids.value[]')
export DR_REGION PRIMARY_REGION DOC_PREPARE DOC_RECOVER DOC_FAILBACK DOC_TERMINATE DOC_DB

log() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# start_runbook <document> [Key=Value ...]  -> prints execution id
start_runbook() {
  local doc="$1"; shift
  local args=()
  for kv in "$@"; do args+=("$kv"); done
  if ((${#args[@]})); then
    aws ssm start-automation-execution --region "$DR_REGION" --document-name "$doc" \
      --parameters "$(printf '%s\n' "${args[@]}" | jq -Rn '[inputs | split("=") | {(.[0]): [.[1]]}] | add')" \
      --query AutomationExecutionId --output text
  else
    aws ssm start-automation-execution --region "$DR_REGION" --document-name "$doc" \
      --query AutomationExecutionId --output text
  fi
}

# wait_runbook <execution-id> [timeout-seconds] -> exits non-zero unless Success
wait_runbook() {
  local id="$1" timeout="${2:-3600}" waited=0 status
  while true; do
    status="$(aws ssm get-automation-execution --region "$DR_REGION" --automation-execution-id "$id" \
      --query AutomationExecution.AutomationExecutionStatus --output text)"
    log "runbook $id: $status"
    case "$status" in
      Success) return 0 ;;
      Failed|Cancelled|TimedOut|CompletedWithFailure) return 1 ;;
    esac
    sleep 30; waited=$((waited + 30))
    ((waited < timeout)) || { log "timeout waiting for $id"; return 1; }
  done
}

runbook_output() {
  aws ssm get-automation-execution --region "$DR_REGION" --automation-execution-id "$1" \
    --query "AutomationExecution.Outputs.\"$2\"" --output json
}
