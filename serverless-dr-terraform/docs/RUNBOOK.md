# Runbook — notes API (multi-site active/active)

## Normal state

Both regions receive traffic. Route 53 answers `api.example.com` with the region that has the lowest latency for the caller, as long as that region's health check is passing. Nothing needs to be done by a human for a single-region outage.

## When a region fails

Route 53 marks the region unhealthy after three failed checks at 30-second intervals (about 90 seconds) and stops returning it; clients follow within their DNS TTL. Confirm the failover by calling `https://api.example.com/health` a few times and checking that the `X-Served-By-Region` header only shows the surviving region. Watch the `ReplicationLatency` alarms: while one region is down, writes queue for replication and the lag in the direction of the failed region will climb, which is expected. Do not run `terraform apply` against the failed region; if an urgent change is needed in the healthy region, target only its resources.

## When the region recovers

DynamoDB drains the replication backlog automatically. Wait until `ReplicationLatency` is back under the threshold and the region's health check is green; Route 53 then starts sending it traffic again with no action required. Run `./scripts/smoke-test.sh` to confirm both directions work.

## Data corruption (bad deploy or bad write)

Failover does not help, because the bad data is already in every region. Stop the source of bad writes first (roll back through the pipeline), then use point-in-time recovery to restore the table to a new table at a time before the incident, compare, and copy the correct items back. Note that restoring creates a regular table, not a global table; copying items back into the live global table is usually simpler than swapping tables.

## Monthly failover drill

Run `./scripts/failover-drill.sh` from a checkout with access to the state. It sets `simulate_primary_failure = true` (inverting the primary health check), waits for Route 53 to shift traffic, verifies every request is served from the DR region, and then restores normal routing. Record the observed switch-over time and update this runbook with anything that surprised you.

## After every release

The pipeline applies to both regions from the same commit and runs `./scripts/smoke-test.sh`, which writes a note through the primary region, reads it back through the DR region, and reads it through the custom domain. A failing smoke test blocks the release.
