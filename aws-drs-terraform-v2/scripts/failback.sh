#!/usr/bin/env bash
# Failback phase 1: reverse replication from recovery instances to the original side.
# Phase 2 (cut-over) is documented in docs/RUNBOOK.md.
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

EXEC=$(start_runbook "$DOC_FAILBACK")
wait_runbook "$EXEC" 900
runbook_output "$EXEC" "ReverseReplication.RecoveryInstanceIds"
log "reversed replication started; track it in the DRS console of $PRIMARY_REGION"
