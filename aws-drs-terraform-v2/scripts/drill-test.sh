#!/usr/bin/env bash
# End-to-end DR test (non-disruptive):
#   1. all servers replicating  2. Prepare + Recover(Mode=drill)
#   3. HTTP check inside each drill instance via SSM  4. measure RTO
#   5. write a Markdown report (audit evidence)  6. terminate drill instances
# Usage: scripts/drill-test.sh [--keep] [--report-dir reports]
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

KEEP=false
REPORT_DIR="reports"
while (($#)); do
  case "$1" in
    --keep) KEEP=true ;;
    --report-dir) REPORT_DIR="$2"; shift ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
  shift
done
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/drill-$(date -u +%Y%m%dT%H%M%SZ).md"
START=$(date +%s)
RESULT="FAILED"

finish() {
  local end=$(( $(date +%s) - START ))
  {
    echo "# DR drill report"
    echo
    echo "| Item | Value |"
    echo "|---|---|"
    echo "| Date (UTC) | $(date -u +%FT%TZ) |"
    echo "| DR region | $DR_REGION |"
    echo "| Protected instances | ${SOURCE_INSTANCE_IDS[*]} |"
    echo "| Drill instances | ${DRILL_IDS:-n/a} |"
    echo "| Measured RTO (launch to healthy HTTP) | ${RTO:-n/a} s |"
    echo "| Total test duration | ${end} s |"
    echo "| Result | **$RESULT** |"
  } > "$REPORT"
  log "report written: $REPORT"
}
trap finish EXIT

log "1/5 checking replication state"
BAD=$(aws drs describe-source-servers --region "$DR_REGION" --filters '{}' \
  --query 'items[?isArchived==`false` && dataReplicationInfo.dataReplicationState!=`CONTINUOUS`].sourceServerID' --output text)
[[ -z "$BAD" ]] || { log "not in CONTINUOUS replication: $BAD"; exit 1; }

log "2/5 launching drill"
EXEC=$(start_runbook "$DOC_RECOVER" Mode=drill)
wait_runbook "$EXEC" 3600
mapfile -t DRILL < <(runbook_output "$EXEC" "Finalize.Ec2InstanceIds" | jq -r '.[]')
DRILL_IDS="${DRILL[*]}"
log "drill instances: $DRILL_IDS"

log "3/5 waiting for SSM agent on drill instances"
for _ in $(seq 1 40); do
  ONLINE=$(aws ssm describe-instance-information --region "$DR_REGION" \
    --filters "Key=InstanceIds,Values=$(IFS=,; echo "${DRILL[*]}")" \
    --query 'length(InstanceInformationList[?PingStatus==`Online`])' --output text)
  [[ "$ONLINE" == "${#DRILL[@]}" ]] && break
  sleep 15
done

log "4/5 HTTP check inside each drill instance"
CMD=$(aws ssm send-command --region "$DR_REGION" --document-name AWS-RunShellScript \
  --instance-ids "${DRILL[@]}" \
  --parameters 'commands=["curl -fsS http://localhost/health.html","curl -fsS http://localhost/ | head -5"]' \
  --query Command.CommandId --output text)
sleep 20
for id in "${DRILL[@]}"; do
  aws ssm wait command-executed --region "$DR_REGION" --command-id "$CMD" --instance-id "$id" \
    || { log "HTTP check failed on $id"; exit 1; }
done
RTO=$(( $(date +%s) - START ))
RESULT="PASSED"
log "drill passed, RTO ~${RTO}s"

if [[ "$KEEP" == false ]]; then
  log "5/5 terminating drill instances"
  wait_runbook "$(start_runbook "$DOC_TERMINATE")" 900
fi
