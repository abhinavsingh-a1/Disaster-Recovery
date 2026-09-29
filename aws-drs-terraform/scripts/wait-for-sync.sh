#!/usr/bin/env bash
# Waits for initial sync to finish (console status "Ready", data replication "Healthy").
source "$(dirname "$0")/common.sh"
require_source_server

while true; do
  read -r STATE LAG <<<"$(aws drs describe-source-servers --region "$REGION" \
    --filters "sourceServerIDs=${SRC_ID}" \
    --query 'items[0].dataReplicationInfo.[dataReplicationState,lagDuration]' --output text)"
  echo "$(date +%T)  $SRC_ID  replication=$STATE  lag=$LAG"
  [[ "$STATE" == "CONTINUOUS" ]] && break
  sleep 30
done
echo "Source server is ready for drill / recovery."
