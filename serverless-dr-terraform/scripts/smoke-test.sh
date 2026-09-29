#!/usr/bin/env bash
# End-to-end check run after every release (the talk: "continuous testing").
# 1) write a note in the primary region
# 2) read it back from the DR region (proves replication + DR stack works)
# 3) read it through the shared custom domain (proves Route 53 routing)
set -euo pipefail

PRIMARY_URL=$(terraform output -raw primary_invoke_url)
DR_URL=$(terraform output -raw dr_invoke_url)
API_URL=$(terraform output -raw api_url)

echo "==> Health checks"
curl -fsS "$PRIMARY_URL/health"; echo
curl -fsS "$DR_URL/health"; echo

echo "==> Create note in primary"
ID=$(curl -fsS -X POST "$PRIMARY_URL/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"smoke test","content":"written in primary"}' | jq -r .id)
echo "created $ID"

echo "==> Read from DR region (retrying while replication catches up)"
for i in $(seq 1 10); do
  if OUT=$(curl -fsS "$DR_URL/notes/$ID" 2>/dev/null); then
    echo "$OUT" | jq .
    break
  fi
  sleep 1
  [ "$i" = 10 ] && { echo "note never replicated to DR"; exit 1; }
done

echo "==> Read via custom domain"
curl -fsS -D - "$API_URL/notes/$ID" -o /dev/null | grep -i x-served-by-region

echo "==> Cleanup"
curl -fsS -X DELETE "$DR_URL/notes/$ID" -o /dev/null
echo "Smoke test passed"
