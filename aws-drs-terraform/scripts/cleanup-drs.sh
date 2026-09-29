#!/usr/bin/env bash
# Removes everything DRS created outside of Terraform (video: "Resource cleanup"):
#   recovery instances -> disconnect + delete source server -> leftover staging
#   volumes and snapshots. Run this BEFORE `terraform destroy`.
source "$(dirname "$0")/common.sh"
SRC_ID="$(source_server_id)"

if [[ -n "$SRC_ID" && "$SRC_ID" != "None" ]]; then
  RIDS=$(aws drs describe-recovery-instances --region "$REGION" \
    --filters "sourceServerIDs=${SRC_ID}" --query 'items[].recoveryInstanceID' --output text)
  if [[ -n "$RIDS" ]]; then
    echo "Terminating recovery instances: $RIDS"
    aws drs terminate-recovery-instances --region "$REGION" --recovery-instance-ids $RIDS >/dev/null
    for _ in $(seq 1 40); do
      LEFT=$(aws drs describe-recovery-instances --region "$REGION" \
        --filters "sourceServerIDs=${SRC_ID}" --query 'length(items)' --output text)
      [[ "$LEFT" == "0" ]] && break
      echo "  waiting for recovery instances to terminate ($LEFT left)"; sleep 15
    done
  fi

  echo "Disconnecting source server $SRC_ID (stops replication, removes staging resources)"
  aws drs disconnect-source-server --region "$REGION" --source-server-id "$SRC_ID" >/dev/null || true
  sleep 10
  aws drs delete-source-server --region "$REGION" --source-server-id "$SRC_ID" && echo "Deleted $SRC_ID"
else
  echo "No DRS source server registered for $SOURCE_INSTANCE_ID."
fi

echo "Waiting for DRS replication/conversion servers to terminate..."
for _ in $(seq 1 40); do
  N=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:DrsStagingArea,Values=${PROJECT}" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
    --query 'length(Reservations[].Instances[])' --output text)
  [[ "$N" == "0" ]] && break
  echo "  $N staging instance(s) still running"; sleep 15
done

for V in $(aws ec2 describe-volumes --region "$REGION" \
    --filters "Name=tag:DrsStagingArea,Values=${PROJECT}" "Name=status,Values=available" \
    --query 'Volumes[].VolumeId' --output text); do
  echo "Deleting staging volume $V"; aws ec2 delete-volume --region "$REGION" --volume-id "$V" || true
done

for S in $(aws ec2 describe-snapshots --region "$REGION" --owner-ids self \
    --filters "Name=tag:DrsStagingArea,Values=${PROJECT}" \
    --query 'Snapshots[].SnapshotId' --output text); do
  echo "Deleting snapshot $S"; aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$S" || true
done

echo "DRS cleanup finished. Check the EC2 console for anything tagged DrsStagingArea=${PROJECT}, then run: terraform destroy"
