"""Publishes DRS replication health as CloudWatch metrics every 5 minutes.

Metrics (namespace from METRIC_NAMESPACE):
  ProtectedServers, UnhealthyServers, MaxReplicationLagSeconds,
  ReplicationLagSeconds (dimension SourceServerId)
"""
import os
import re

import boto3

drs = boto3.client("drs")
cloudwatch = boto3.client("cloudwatch")
NAMESPACE = os.environ["METRIC_NAMESPACE"]

HEALTHY_STATES = {
    "CONTINUOUS", "INITIAL_SYNC", "INITIATING", "BACKLOG", "CREATING_SNAPSHOT", "RESCAN",
}
DURATION = re.compile(r"P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$")


def _seconds(iso_duration):
    match = DURATION.match(iso_duration or "")
    if not match:
        return 0.0
    days, hours, minutes, seconds = match.groups()
    return int(days or 0) * 86400 + int(hours or 0) * 3600 + int(minutes or 0) * 60 + float(seconds or 0)


def _servers():
    items, token = [], None
    while True:
        kwargs = {"filters": {}, "maxResults": 200}
        if token:
            kwargs["nextToken"] = token
        resp = drs.describe_source_servers(**kwargs)
        items.extend(resp.get("items", []))
        token = resp.get("nextToken")
        if not token:
            return [s for s in items if not s.get("isArchived")]


def handler(event, context):
    servers = _servers()
    metrics, unhealthy, max_lag = [], [], 0.0
    for server in servers:
        info = server.get("dataReplicationInfo", {})
        state = info.get("dataReplicationState", "UNKNOWN")
        lag = _seconds(info.get("lagDuration"))
        max_lag = max(max_lag, lag)
        if state not in HEALTHY_STATES:
            unhealthy.append({"id": server["sourceServerID"], "state": state})
        metrics.append({
            "MetricName": "ReplicationLagSeconds",
            "Dimensions": [{"Name": "SourceServerId", "Value": server["sourceServerID"]}],
            "Value": lag,
            "Unit": "Seconds",
        })
    metrics += [
        {"MetricName": "ProtectedServers", "Value": len(servers), "Unit": "Count"},
        {"MetricName": "UnhealthyServers", "Value": len(unhealthy), "Unit": "Count"},
        {"MetricName": "MaxReplicationLagSeconds", "Value": max_lag, "Unit": "Seconds"},
    ]
    for start in range(0, len(metrics), 20):
        cloudwatch.put_metric_data(Namespace=NAMESPACE, MetricData=metrics[start:start + 20])
    summary = {"servers": len(servers), "unhealthy": unhealthy, "max_lag_seconds": max_lag}
    print(summary)
    return summary
