"""Automated regional failover.

Triggered by the `primary-site-down` CloudWatch alarm (via SNS in us-east-1).

Steps
  1. Ignore anything that is not an ALARM transition.
  2. Re-check the Route 53 health check: if most checkers see the primary as
     healthy again, it was a blip - notify and stop.
  3. If AUTO_FAILOVER_ENABLED is false, report what would happen and stop
     (human in the loop).
  4. Promote the Aurora secondary with failover-global-cluster
     (AllowDataLoss=True: the primary region is assumed unreachable).
     Idempotent: skipped if the DR cluster is already the writer or a
     failover/switchover is already running.
  5. Raise the DR Auto Scaling group to production capacity.
  6. Publish a summary to the DR alerts topic.
"""
import json
import logging
import os

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)


def load_config(env=None):
    env = os.environ if env is None else env
    return {
        "enabled": env.get("AUTO_FAILOVER_ENABLED", "false").lower() == "true",
        "health_check_id": env["HEALTH_CHECK_ID"],
        "global_cluster_id": env["GLOBAL_CLUSTER_ID"],
        "dr_cluster_arn": env["DR_CLUSTER_ARN"],
        "dr_region": env["DR_REGION"],
        "dr_asg_name": env["DR_ASG_NAME"],
        "capacity": int(env["PRODUCTION_CAPACITY"]),
        "topic_arn": env["NOTIFY_TOPIC_ARN"],
    }


def alarm_states(event):
    """Extract NewStateValue from every SNS record carrying a CloudWatch alarm."""
    states = []
    for record in event.get("Records", []):
        try:
            message = json.loads(record["Sns"]["Message"])
        except (KeyError, TypeError, ValueError):
            continue
        state = message.get("NewStateValue")
        if state:
            states.append(state)
    return states


def primary_still_down(route53, health_check_id):
    """True unless a majority of Route 53 checkers report success."""
    observations = route53.get_health_check_status(HealthCheckId=health_check_id)["HealthCheckObservations"]
    if not observations:
        return True
    healthy = sum(1 for o in observations if o["StatusReport"]["Status"].startswith("Success"))
    return healthy * 2 <= len(observations)


def promote_database(rds, cfg):
    cluster = rds.describe_global_clusters(GlobalClusterIdentifier=cfg["global_cluster_id"])["GlobalClusters"][0]
    for member in cluster.get("GlobalClusterMembers", []):
        if member["DBClusterArn"] == cfg["dr_cluster_arn"] and member.get("IsWriter"):
            return "already-writer"
    if cluster.get("Status") in ("failing-over", "switching-over") or cluster.get("FailoverState"):
        return "already-in-progress"
    rds.failover_global_cluster(
        GlobalClusterIdentifier=cfg["global_cluster_id"],
        TargetDbClusterIdentifier=cfg["dr_cluster_arn"],
        AllowDataLoss=True,
    )
    return "failover-started"


def scale_web_tier(autoscaling, cfg):
    group = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[cfg["dr_asg_name"]])["AutoScalingGroups"][0]
    target = cfg["capacity"]
    if group["MinSize"] >= target and group["DesiredCapacity"] >= target:
        return f"already-at-{group['DesiredCapacity']}"
    autoscaling.update_auto_scaling_group(
        AutoScalingGroupName=cfg["dr_asg_name"],
        MinSize=target,
        DesiredCapacity=max(target, group["DesiredCapacity"]),
        MaxSize=max(target, group["MaxSize"]),
    )
    return f"scaled-to-{target}"


def notify(sns, cfg, subject, result):
    sns.publish(TopicArn=cfg["topic_arn"], Subject=subject[:100], Message=json.dumps(result, indent=2))


def handle(event, cfg, route53, rds, autoscaling, sns):
    """Pure orchestration logic; AWS clients are injected (unit-testable)."""
    states = alarm_states(event)
    if "ALARM" not in states:
        return {"action": "ignored", "states": states}

    if not primary_still_down(route53, cfg["health_check_id"]):
        result = {"action": "none", "reason": "primary health check recovered before failover"}
        notify(sns, cfg, "DR: primary alarm fired but site recovered", result)
        return result

    if not cfg["enabled"]:
        result = {
            "action": "dry-run",
            "would": [
                f"promote {cfg['dr_cluster_arn']} in {cfg['global_cluster_id']}",
                f"scale {cfg['dr_asg_name']} to {cfg['capacity']}",
            ],
            "next_step": "run scripts/failover.sh unplanned, or set auto_failover_enabled = true",
        }
        notify(sns, cfg, "DR: primary site down - manual failover needed", result)
        return result

    result = {"action": "failover"}
    try:
        result["database"] = promote_database(rds, cfg)
    except Exception as exc:  # keep going: serving reads from DR still helps
        LOG.exception("database promotion failed")
        result["database"] = f"error: {exc}"
    try:
        result["web_tier"] = scale_web_tier(autoscaling, cfg)
    except Exception as exc:
        LOG.exception("scaling failed")
        result["web_tier"] = f"error: {exc}"

    notify(sns, cfg, "DR: automated failover to DR region", result)
    return result


def lambda_handler(event, context):  # pragma: no cover - thin AWS wiring
    import boto3

    cfg = load_config()
    LOG.info("event: %s", json.dumps(event))
    result = handle(
        event,
        cfg,
        route53=boto3.client("route53"),
        rds=boto3.client("rds", region_name=cfg["dr_region"]),
        autoscaling=boto3.client("autoscaling", region_name=cfg["dr_region"]),
        sns=boto3.client("sns", region_name=cfg["dr_region"]),
    )
    LOG.info("result: %s", json.dumps(result))
    return result
