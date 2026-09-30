#!/usr/bin/env bash
# Manual failover: promote the DR region and scale its web tier to production.
#
#   ./scripts/failover.sh planned     # both regions healthy: zero-data-loss switchover (drills, maintenance)
#   ./scripts/failover.sh unplanned   # primary region down: failover, may lose the last seconds of writes
#
# Uses the AWS CLI rather than `terraform apply`, because during a regional
# outage Terraform cannot refresh resources in the failed region.
set -euo pipefail

MODE="${1:-}"
cd "$(dirname "$0")/.."

out() { terraform output -raw "$1" 2>/dev/null || true; }

PRIMARY_REGION="$(out primary_region)"
DR_REGION="$(out dr_region)"
GLOBAL_ID="$(out global_cluster_id)"
DR_CLUSTER_ARN="$(out dr_db_cluster_arn)"
DR_ASG="$(out dr_asg_name)"
PROD_CAPACITY="$(out production_capacity)"

if [[ -z "$DR_CLUSTER_ARN" || "$DR_CLUSTER_ARN" == "null" ]]; then
  echo "No DR cluster: dr_strategy is backup_restore. Follow the restore steps in docs/runbook.md." >&2
  exit 1
fi

case "$MODE" in
  planned)
    echo ">> Switchover of $GLOBAL_ID to $DR_CLUSTER_ARN (no data loss)"
    aws rds switchover-global-cluster \
      --region "$PRIMARY_REGION" \
      --global-cluster-identifier "$GLOBAL_ID" \
      --target-db-cluster-identifier "$DR_CLUSTER_ARN" >/dev/null
    ;;
  unplanned)
    echo ">> Failover of $GLOBAL_ID to $DR_CLUSTER_ARN (may lose the last seconds of writes)"
    aws rds failover-global-cluster \
      --region "$DR_REGION" \
      --global-cluster-identifier "$GLOBAL_ID" \
      --target-db-cluster-identifier "$DR_CLUSTER_ARN" \
      --allow-data-loss >/dev/null
    ;;
  *)
    echo "Usage: $0 planned|unplanned" >&2
    exit 1
    ;;
esac

echo ">> Scaling $DR_ASG in $DR_REGION to $PROD_CAPACITY instances"
aws autoscaling update-auto-scaling-group \
  --region "$DR_REGION" \
  --auto-scaling-group-name "$DR_ASG" \
  --min-size "$PROD_CAPACITY" \
  --desired-capacity "$PROD_CAPACITY"

echo ">> Waiting for the DR cluster to become the writer..."
for _ in $(seq 1 60); do
  WRITER="$(aws rds describe-global-clusters --region "$DR_REGION" \
    --global-cluster-identifier "$GLOBAL_ID" \
    --query "GlobalClusters[0].GlobalClusterMembers[?IsWriter].DBClusterArn | [0]" --output text)"
  if [[ "$WRITER" == "$DR_CLUSTER_ARN" ]]; then
    echo ">> DR cluster is now the writer."
    break
  fi
  sleep 10
done

echo ">> Done. Set dr_activate = true in terraform.tfvars so the next apply keeps the DR site at production size."
