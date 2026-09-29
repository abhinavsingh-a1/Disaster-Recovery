#!/usr/bin/env bash
# REAL failover (disruptive to the DR side, production is left as is):
#   Recover(Mode=recovery) -> register DR ALB targets, then optional DB failover.
# Usage: scripts/failover.sh [point-in-time|latest] [--with-database]
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

PIT="${1:-latest}"
WITH_DB="${2:-}"

read -r -p "Start REAL recovery in $DR_REGION from '$PIT'? Type 'failover': " ok
[[ "$ok" == "failover" ]] || { echo aborted; exit 1; }

EXEC=$(start_runbook "$DOC_RECOVER" Mode=recovery "PointInTime=$PIT")
wait_runbook "$EXEC" 3600
runbook_output "$EXEC" "Finalize.Ec2InstanceIds"

if [[ "$WITH_DB" == "--with-database" && -n "$DOC_DB" ]]; then
  log "promoting DR database replica"
  wait_runbook "$(start_runbook "$DOC_DB")" 3600
fi

log "done. DR endpoint: $(tf '.dr_url.value')  (Route 53 fails over automatically if configured)"
