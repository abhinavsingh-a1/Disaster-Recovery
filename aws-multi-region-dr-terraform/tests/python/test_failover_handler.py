"""Unit tests for lambda/failover/handler.py with fake AWS clients (no boto3 needed)."""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "lambda", "failover"))
import handler  # noqa: E402

DR_ARN = "arn:aws:rds:eu-west-1:123456789012:cluster:dr-demo-dr"
CFG = {
    "enabled": True,
    "health_check_id": "hc-1",
    "global_cluster_id": "dr-demo-global",
    "dr_cluster_arn": DR_ARN,
    "dr_region": "eu-west-1",
    "dr_asg_name": "dr-demo-dr-web",
    "capacity": 2,
    "topic_arn": "arn:aws:sns:eu-west-1:123456789012:dr-demo-alerts",
}


def alarm_event(state="ALARM"):
    return {"Records": [{"Sns": {"Message": json.dumps({"NewStateValue": state})}}]}


class FakeRoute53:
    def __init__(self, statuses):
        self.statuses = statuses

    def get_health_check_status(self, HealthCheckId):
        return {"HealthCheckObservations": [{"StatusReport": {"Status": s}} for s in self.statuses]}


class FakeRds:
    def __init__(self, dr_is_writer=False, status="available"):
        self.dr_is_writer = dr_is_writer
        self.status = status
        self.failovers = []

    def describe_global_clusters(self, GlobalClusterIdentifier):
        return {"GlobalClusters": [{
            "Status": self.status,
            "GlobalClusterMembers": [
                {"DBClusterArn": "arn:primary", "IsWriter": not self.dr_is_writer},
                {"DBClusterArn": DR_ARN, "IsWriter": self.dr_is_writer},
            ],
        }]}

    def failover_global_cluster(self, **kwargs):
        self.failovers.append(kwargs)


class FakeAsg:
    def __init__(self, min_size=1, desired=1, max_size=6):
        self.group = {"MinSize": min_size, "DesiredCapacity": desired, "MaxSize": max_size}
        self.updates = []

    def describe_auto_scaling_groups(self, AutoScalingGroupNames):
        return {"AutoScalingGroups": [dict(self.group)]}

    def update_auto_scaling_group(self, **kwargs):
        self.updates.append(kwargs)


class FakeSns:
    def __init__(self):
        self.messages = []

    def publish(self, **kwargs):
        self.messages.append(kwargs)


DOWN = ["Failure: HTTP Status Code 503"] * 5
UP = ["Success: HTTP Status Code 200, OK"] * 5


class HandlerTests(unittest.TestCase):
    def run_handler(self, event=None, cfg=None, r53=None, rds=None, asg=None):
        self.rds = rds or FakeRds()
        self.asg = asg or FakeAsg()
        self.sns = FakeSns()
        return handler.handle(event or alarm_event(), cfg or CFG, r53 or FakeRoute53(DOWN), self.rds, self.asg, self.sns)

    def test_ok_transition_is_ignored(self):
        result = self.run_handler(event=alarm_event("OK"))
        self.assertEqual(result["action"], "ignored")
        self.assertEqual(self.rds.failovers, [])
        self.assertEqual(self.sns.messages, [])

    def test_recovered_site_does_not_fail_over(self):
        result = self.run_handler(r53=FakeRoute53(UP))
        self.assertEqual(result["action"], "none")
        self.assertEqual(self.rds.failovers, [])
        self.assertEqual(len(self.sns.messages), 1)

    def test_dry_run_only_notifies(self):
        result = self.run_handler(cfg=dict(CFG, enabled=False))
        self.assertEqual(result["action"], "dry-run")
        self.assertEqual(self.rds.failovers, [])
        self.assertEqual(self.asg.updates, [])
        self.assertIn("manual failover", self.sns.messages[0]["Subject"])

    def test_failover_promotes_and_scales(self):
        result = self.run_handler()
        self.assertEqual(result["database"], "failover-started")
        self.assertEqual(self.rds.failovers[0]["TargetDbClusterIdentifier"], DR_ARN)
        self.assertTrue(self.rds.failovers[0]["AllowDataLoss"])
        self.assertEqual(result["web_tier"], "scaled-to-2")
        self.assertEqual(self.asg.updates[0]["MinSize"], 2)

    def test_idempotent_when_dr_already_writer(self):
        result = self.run_handler(rds=FakeRds(dr_is_writer=True), asg=FakeAsg(2, 2, 6))
        self.assertEqual(result["database"], "already-writer")
        self.assertEqual(result["web_tier"], "already-at-2")
        self.assertEqual(self.rds.failovers, [])
        self.assertEqual(self.asg.updates, [])

    def test_failover_in_progress_is_not_repeated(self):
        result = self.run_handler(rds=FakeRds(status="failing-over"))
        self.assertEqual(result["database"], "already-in-progress")
        self.assertEqual(self.rds.failovers, [])

    def test_pilot_light_scales_from_zero(self):
        result = self.run_handler(asg=FakeAsg(0, 0, 6))
        self.assertEqual(result["web_tier"], "scaled-to-2")
        self.assertEqual(self.asg.updates[0]["DesiredCapacity"], 2)

    def test_split_health_observations_count_as_down(self):
        result = self.run_handler(r53=FakeRoute53(UP[:2] + DOWN[:3]))
        self.assertEqual(result["action"], "failover")

    def test_load_config(self):
        env = {
            "AUTO_FAILOVER_ENABLED": "true", "HEALTH_CHECK_ID": "hc", "GLOBAL_CLUSTER_ID": "g",
            "DR_CLUSTER_ARN": "a", "DR_REGION": "eu-west-1", "DR_ASG_NAME": "asg",
            "PRODUCTION_CAPACITY": "3", "NOTIFY_TOPIC_ARN": "t",
        }
        cfg = handler.load_config(env)
        self.assertTrue(cfg["enabled"])
        self.assertEqual(cfg["capacity"], 3)


if __name__ == "__main__":
    unittest.main()
