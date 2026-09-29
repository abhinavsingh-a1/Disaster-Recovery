"""Starts the DR runbooks when the production health-check alarm enters ALARM.

Triggered by SNS (CloudWatch alarm notification). Skips a runbook that is
already running so repeated notifications never launch a second recovery.
"""
import json
import os

import boto3

ssm = boto3.client("ssm", region_name=os.environ["DR_REGION"])
RUNBOOKS = json.loads(os.environ["RUNBOOKS_JSON"])
ACTIVE = ["Pending", "InProgress", "Waiting"]


def _already_running(document):
    resp = ssm.describe_automation_executions(Filters=[
        {"Key": "DocumentNamePrefix", "Values": [document]},
        {"Key": "ExecutionStatus", "Values": ACTIVE},
    ])
    return bool(resp.get("AutomationExecutionMetadataList"))


def handler(event, context):
    started = []
    for record in event.get("Records", []):
        alarm = json.loads(record["Sns"]["Message"])
        if alarm.get("NewStateValue") != "ALARM":
            print("Ignoring state %s" % alarm.get("NewStateValue"))
            continue
        for document, parameters in RUNBOOKS.items():
            if _already_running(document):
                print("%s already running - skipped" % document)
                continue
            execution = ssm.start_automation_execution(DocumentName=document, Parameters=parameters)
            started.append({document: execution["AutomationExecutionId"]})
    print({"started": started})
    return {"started": started}
