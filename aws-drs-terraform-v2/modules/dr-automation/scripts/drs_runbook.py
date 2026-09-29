"""Handlers for the DR SSM Automation runbooks (aws:executeScript steps).

Each handler receives the step's InputPayload as `events` and returns a dict
that the runbook exposes via $.Payload.<key>. Every handler is idempotent or
fails loudly, and each finishes well inside the 600 s executeScript limit;
long waits are done by aws:waitForAwsResourceProperty steps instead.
"""
import boto3

drs = boto3.client("drs")
ec2 = boto3.client("ec2")
elbv2 = boto3.client("elbv2")


def _paginate(call, **kwargs):
    items, token = [], None
    while True:
        if token:
            kwargs["nextToken"] = token
        resp = call(**kwargs)
        items.extend(resp.get("items", []))
        token = resp.get("nextToken")
        if not token:
            return items


def _source_servers_for(instance_ids):
    wanted = {i for i in instance_ids if i}
    found = {}
    for server in _paginate(drs.describe_source_servers, filters={}, maxResults=200):
        if server.get("isArchived"):
            continue
        hints = server.get("sourceProperties", {}).get("identificationHints", {})
        if hints.get("awsInstanceID") in wanted:
            found[hints["awsInstanceID"]] = server["sourceServerID"]
    missing = wanted - set(found)
    if missing:
        raise RuntimeError(
            "Not registered in DRS yet (agent still installing or failed): %s" % sorted(missing)
        )
    return [found[i] for i in sorted(found)]


def prepare(events, context):
    server_ids = _source_servers_for(events["SourceInstanceIds"])
    subnets = events["SubnetIds"]
    for idx, server_id in enumerate(server_ids):
        drs.update_launch_configuration(
            sourceServerID=server_id,
            copyPrivateIp=False,
            copyTags=True,
            launchDisposition="STARTED",
            targetInstanceTypeRightSizingMethod="NONE",
            licensing={"osByol": False},
        )
        template_id = drs.get_launch_configuration(sourceServerID=server_id)["ec2LaunchTemplateID"]
        data = {
            "InstanceType": events["InstanceType"],
            "IamInstanceProfile": {"Arn": events["InstanceProfileArn"]},
            "MetadataOptions": {"HttpTokens": "required", "HttpEndpoint": "enabled"},
            "NetworkInterfaces": [{
                "DeviceIndex": 0,
                "SubnetId": subnets[idx % len(subnets)],
                "Groups": [events["SecurityGroupId"]],
                "AssociatePublicIpAddress": False,
                "DeleteOnTermination": True,
            }],
        }
        version = ec2.create_launch_template_version(
            LaunchTemplateId=template_id,
            SourceVersion="$Default",
            VersionDescription="dr-automation",
            LaunchTemplateData=data,
        )["LaunchTemplateVersion"]["VersionNumber"]
        ec2.modify_launch_template(LaunchTemplateId=template_id, DefaultVersion=str(version))
    return {"SourceServerIds": server_ids}


def start_recovery(events, context):
    mode = events["Mode"]
    point_in_time = (events.get("PointInTime") or "latest").strip()
    specs = []
    for server_id in events["SourceServerIds"]:
        spec = {"sourceServerID": server_id}
        if point_in_time.lower() != "latest":
            snaps = drs.describe_recovery_snapshots(
                sourceServerID=server_id,
                order="DESC",
                filters={"toDateTime": point_in_time},
                maxResults=1,
            ).get("items", [])
            if not snaps:
                raise RuntimeError("No snapshot at or before %s for %s" % (point_in_time, server_id))
            spec["recoverySnapshotID"] = snaps[0]["snapshotID"]
        specs.append(spec)
    job = drs.start_recovery(sourceServers=specs, isDrill=(mode == "drill"))["job"]
    return {"JobId": job["jobID"]}


def finalize_recovery(events, context):
    job = drs.describe_jobs(filters={"jobIDs": [events["JobId"]]})["items"][0]
    servers = job.get("participatingServers", [])
    failed = [s["sourceServerID"] for s in servers if s.get("launchStatus") != "LAUNCHED"]
    if failed:
        raise RuntimeError("Launch failed for %s - check the DRS job log of %s" % (failed, events["JobId"]))

    recovery_ids = [s["recoveryInstanceID"] for s in servers if s.get("recoveryInstanceID")]
    ec2_ids = []
    if recovery_ids:
        instances = _paginate(drs.describe_recovery_instances, filters={"recoveryInstanceIDs": recovery_ids})
        ec2_ids = [r["ec2InstanceID"] for r in instances if r.get("ec2InstanceID")]

    register = str(events.get("Register")).lower() == "true" and events.get("Mode") == "recovery"
    if register and ec2_ids:
        ec2.get_waiter("instance_running").wait(
            InstanceIds=ec2_ids, WaiterConfig={"Delay": 10, "MaxAttempts": 45}
        )
        elbv2.register_targets(
            TargetGroupArn=events["TargetGroupArn"],
            Targets=[{"Id": i, "Port": 80} for i in ec2_ids],
        )
    return {"RecoveryInstanceIds": recovery_ids, "Ec2InstanceIds": ec2_ids, "Registered": register}


def reverse_replication(events, context):
    ids = [i for i in events.get("RecoveryInstanceIds", []) if i and i != "all"]
    if not ids:
        ids = [
            r["recoveryInstanceID"]
            for r in _paginate(drs.describe_recovery_instances, filters={})
            if not r.get("isDrill")
        ]
    if not ids:
        raise RuntimeError("No non-drill recovery instances found to fail back")
    for recovery_id in ids:
        drs.reverse_replication(recoveryInstanceID=recovery_id)
    return {"RecoveryInstanceIds": ids}


def terminate_drills(events, context):
    ids = [
        r["recoveryInstanceID"]
        for r in _paginate(drs.describe_recovery_instances, filters={})
        if r.get("isDrill")
    ]
    for start in range(0, len(ids), 200):
        drs.terminate_recovery_instances(recoveryInstanceIDs=ids[start:start + 200])
    return {"RecoveryInstanceIds": ids}
