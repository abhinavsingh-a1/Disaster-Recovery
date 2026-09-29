#!/usr/bin/env bash
# Monthly failover exercise (the talk: "test the failover before disaster strikes").
# Inverts the primary health check -> Route 53 sends ALL traffic to the DR region,
# verifies it, then restores normal routing.
set -euo pipefail

API_URL=$(terraform output -raw api_url)

echo "==> Simulating primary region failure"
terraform apply -auto-approve -var simulate_primary_failure=true

echo "==> Waiting for Route 53 to mark primary unhealthy (~2-3 min)"
sleep 180

echo "==> Every request should now be served by the DR region"
for i in $(seq 1 5); do
  curl -fsS -D - "$API_URL/health" -o /dev/null | grep -i x-served-by-region
done

read -rp "Press Enter to restore normal routing..."
terraform apply -auto-approve -var simulate_primary_failure=false
echo "Drill complete - update the runbook with anything you learned."
