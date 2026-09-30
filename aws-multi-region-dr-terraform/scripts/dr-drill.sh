#!/usr/bin/env bash
# End-to-end DR drill that produces MEASURED numbers instead of estimates.
#
#   ./scripts/dr-drill.sh               # FIS outage + wait for automated failover (auto_failover_enabled = true)
#   ./scripts/dr-drill.sh --manual      # FIS outage, then this script runs failover.sh unplanned itself
#
# Requirements: hosted_zone_id/domain_name set (traffic must move by DNS),
# enable_chaos_experiments = true, aws CLI, curl, python3.
#
# What it measures
#   Traffic RTO : outage start -> first response served by the DR region
#   Write RTO   : outage start -> first successful write in the DR region
#   RPO         : whether the marker note written just before the outage survives
# Results are appended to drill-results/<timestamp>.md - commit them as evidence.
set -euo pipefail

cd "$(dirname "$0")/.."
MANUAL=false
[[ "${1:-}" == "--manual" ]] && MANUAL=true

out() { terraform output -raw "$1" 2>/dev/null || true; }
now() { date +%s; }
json_field() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1', ''))"; }

APP_URL="$(out app_url)"
PRIMARY_REGION="$(out primary_region)"
DR_REGION="$(out dr_region)"
TEMPLATE_ID="$(out fis_primary_outage_template_id)"
STRATEGY="$(out dr_strategy)"

[[ "$APP_URL" == https://* ]] || { echo "The drill needs DNS failover: set hosted_zone_id and domain_name." >&2; exit 1; }
[[ -n "$TEMPLATE_ID" && "$TEMPLATE_ID" != "null" ]] || { echo "Set enable_chaos_experiments = true." >&2; exit 1; }
[[ "$STRATEGY" != "backup_restore" ]] || { echo "backup_restore has no standby to fail over to; see docs/runbook.md." >&2; exit 1; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="drill-results/${STAMP}.md"
mkdir -p drill-results

echo ">> 1/5 Checking the primary site serves traffic"
REGION_NOW="$(curl -fsS "$APP_URL/api/whoami" | json_field region)"
[[ "$REGION_NOW" == "$PRIMARY_REGION" ]] || { echo "Expected $PRIMARY_REGION, got $REGION_NOW. Is the primary healthy?" >&2; exit 1; }

echo ">> 2/5 Writing marker note"
MARKER_TEXT="drill-${STAMP}"
MARKER_ID="$(curl -fsS -X POST -H 'Content-Type: application/json' \
  -d "{\"text\": \"${MARKER_TEXT}\"}" "$APP_URL/api/notes" | json_field id)"
echo "   marker id ${MARKER_ID}"

echo ">> 3/5 Starting FIS experiment ${TEMPLATE_ID} (primary web tier loses network)"
T0="$(now)"
aws fis start-experiment --region "$PRIMARY_REGION" --experiment-template-id "$TEMPLATE_ID" \
  --query experiment.id --output text

if $MANUAL; then
  echo "   manual mode: waiting 3 minutes for the outage alarm, then running failover.sh unplanned"
  sleep 180
  ./scripts/failover.sh unplanned
fi

echo ">> 4/5 Waiting for traffic to reach ${DR_REGION} (timeout 30 min)"
T_TRAFFIC=""
T_WRITE=""
DEADLINE=$((T0 + 1800))
while (( $(now) < DEADLINE )); do
  if [[ -z "$T_TRAFFIC" ]]; then
    R="$(curl -fsS --max-time 5 "$APP_URL/api/whoami" 2>/dev/null | json_field region || true)"
    if [[ "$R" == "$DR_REGION" ]]; then T_TRAFFIC="$(now)"; echo "   traffic on DR after $((T_TRAFFIC - T0)) s"; fi
  fi
  if [[ -n "$T_TRAFFIC" && -z "$T_WRITE" ]]; then
    if curl -fsS --max-time 5 -X POST -H 'Content-Type: application/json' \
      -d "{\"text\": \"post-failover-${STAMP}\"}" "$APP_URL/api/notes" >/dev/null 2>&1; then
      T_WRITE="$(now)"; echo "   writes accepted in DR after $((T_WRITE - T0)) s"
    fi
  fi
  [[ -n "$T_TRAFFIC" && -n "$T_WRITE" ]] && break
  sleep 5
done

echo ">> 5/5 Checking the marker survived (RPO)"
if curl -fsS "$APP_URL/api/notes/${MARKER_ID}" | grep -q "$MARKER_TEXT"; then
  RPO="0 - marker written before the outage is present in the DR region"
else
  RPO="DATA LOSS - marker ${MARKER_ID} not found in the DR region"
fi

took() { [[ -n "$1" ]] && echo "$(($1 - T0)) s" || echo "not reached within 30 min"; }
{
  echo "# DR drill ${STAMP}"
  echo
  echo "| Item | Result |"
  echo "|---|---|"
  echo "| Strategy | ${STRATEGY} |"
  echo "| Failover mode | $($MANUAL && echo 'manual (failover.sh)' || echo 'automated (Lambda)') |"
  echo "| Primary / DR region | ${PRIMARY_REGION} / ${DR_REGION} |"
  echo "| Traffic RTO (reads) | $(took "$T_TRAFFIC") |"
  echo "| Write RTO | $(took "$T_WRITE") |"
  echo "| RPO | ${RPO} |"
} | tee "$REPORT"

echo
echo "Report saved to ${REPORT}. The FIS experiment ends by itself after 10 minutes."
echo "Fail back later with a planned switchover (docs/runbook.md, section 'Failback')."
