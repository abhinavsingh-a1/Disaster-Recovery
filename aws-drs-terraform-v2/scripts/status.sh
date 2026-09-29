#!/usr/bin/env bash
# Replication health of all protected servers + newest PIT snapshots.
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

aws drs describe-source-servers --region "$DR_REGION" --filters '{}' \
  --query 'items[?isArchived==`false`].{server:sourceServerID,host:sourceProperties.identificationHints.hostname,instance:sourceProperties.identificationHints.awsInstanceID,state:dataReplicationInfo.dataReplicationState,lag:dataReplicationInfo.lagDuration}' \
  --output table

for sid in $(aws drs describe-source-servers --region "$DR_REGION" --filters '{}' \
    --query 'items[?isArchived==`false`].sourceServerID' --output text); do
  echo "Newest snapshots for $sid:"
  aws drs describe-recovery-snapshots --region "$DR_REGION" --source-server-id "$sid" \
    --order DESC --max-results 5 --query 'items[].[snapshotID,timestamp]' --output table
done
