#!/usr/bin/env bash
# Usage: ./scripts/start-recovery.sh [drill|recovery] [snapshot-id]
#   drill    - test launch, source keeps replicating (recommended for testing)
#   recovery - real failover launch (the video uses this one)
# Without a snapshot ID the latest point in time is used.
source "$(dirname "$0")/common.sh"
require_source_server

MODE="${1:-drill}"
SNAP="${2:-}"
case "$MODE" in
  drill)    DRILL_FLAG="--is-drill" ;;
  recovery) DRILL_FLAG="--no-is-drill" ;;
  *) echo "mode must be drill or recovery" >&2; exit 1 ;;
esac

SRC_SPEC="sourceServerID=${SRC_ID}"
[[ -n "$SNAP" ]] && SRC_SPEC="${SRC_SPEC},recoverySnapshotID=${SNAP}"

JOB=$(aws drs start-recovery --region "$REGION" \
  --source-servers "$SRC_SPEC" $DRILL_FLAG \
  --tags "Project=${PROJECT}" \
  --query 'job.jobID' --output text)
echo "Started $MODE job $JOB (snapshot -> conversion server -> recovery instance)"

while true; do
  STATUS=$(aws drs describe-jobs --region "$REGION" --filters "jobIDs=${JOB}" \
    --query 'items[0].status' --output text)
  LAUNCH=$(aws drs describe-jobs --region "$REGION" --filters "jobIDs=${JOB}" \
    --query 'items[0].participatingServers[0].launchStatus' --output text)
  echo "$(date +%T)  job=$STATUS  launch=$LAUNCH"
  [[ "$STATUS" == "COMPLETED" ]] && break
  sleep 30
done

[[ "$LAUNCH" == "LAUNCHED" ]] || { echo "Launch status: $LAUNCH - check job log in the DRS console." >&2; exit 1; }

EC2_ID=$(aws drs describe-recovery-instances --region "$REGION" \
  --filters "sourceServerIDs=${SRC_ID}" \
  --query 'items[0].ec2InstanceID' --output text)
IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$EC2_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Recovery instance: $EC2_ID"
echo "Open http://${IP}/ - the page should still name the ORIGINAL source instance ${SOURCE_INSTANCE_ID}."
echo "Failover = point users/DNS/Elastic IP at this instance."
