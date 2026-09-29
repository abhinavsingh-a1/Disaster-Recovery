locals {
  script  = file("${path.module}/scripts/drs_runbook.py")
  runtime = "python3.11"

  common_parameters = {
    AutomationAssumeRole = {
      type        = "String"
      description = "Role the runbook runs as."
      default     = aws_iam_role.automation.arn
    }
    SourceInstanceIds = {
      type        = "StringList"
      description = "EC2 instance IDs of the protected (source) servers."
      default     = var.source_instance_ids
    }
    SubnetIds = {
      type        = "StringList"
      description = "Recovery subnets (round-robin)."
      default     = var.recovery_subnet_ids
    }
    SecurityGroupId = {
      type    = "String"
      default = var.recovery_security_group_id
    }
    InstanceType = {
      type    = "String"
      default = var.recovery_instance_type
    }
    InstanceProfileArn = {
      type    = "String"
      default = aws_iam_instance_profile.recovery.arn
    }
  }

  prepare_step = {
    name      = "Prepare"
    action    = "aws:executeScript"
    onFailure = "Abort"

    inputs = {
      Runtime = local.runtime
      Handler = "prepare"
      Script  = local.script

      InputPayload = {
        SourceInstanceIds  = "{{ SourceInstanceIds }}"
        SubnetIds          = "{{ SubnetIds }}"
        SecurityGroupId    = "{{ SecurityGroupId }}"
        InstanceType       = "{{ InstanceType }}"
        InstanceProfileArn = "{{ InstanceProfileArn }}"
      }
    }
    outputs = [{
      Name     = "SourceServerIds"
      Selector = "$.Payload.SourceServerIds"
      Type     = "StringList"
    }]
  }
}

# 1) Apply launch settings (idempotent). Run once replication is healthy so drills
#    already use the right shape.
resource "aws_ssm_document" "prepare" {
  name            = "${var.name}-PrepareLaunchSettings"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Apply DRS launch settings: no private-IP copy, copy tags, right-sizing NONE, instance type, private subnets, recovery SG, instance profile, IMDSv2."
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters    = local.common_parameters
    mainSteps     = [local.prepare_step]
    outputs       = ["Prepare.SourceServerIds"]
  })
}

# 2) Drill or recovery from a point in time, then register targets on the DR ALB.
resource "aws_ssm_document" "recover" {
  name            = "${var.name}-Recover"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Launch DRS drill or recovery instances from the latest or a chosen point in time and (for recovery) register them with the DR load balancer."
    assumeRole    = "{{ AutomationAssumeRole }}"

    parameters = merge(local.common_parameters, {
      Mode = {
        type          = "String"
        description   = "drill = test launch, production untouched; recovery = real failover."
        default       = "drill"
        allowedValues = ["drill", "recovery"]
      }
      PointInTime = {
        type        = "String"
        description = "latest, or an ISO-8601 UTC timestamp (e.g. 2026-09-29T19:10:00Z): newest snapshot at or before it is used."
        default     = "latest"
      }
      RegisterWithDrLoadBalancer = {
        type        = "Boolean"
        description = "Register recovery (not drill) instances with the DR target group."
        default     = true
      }
      TargetGroupArn = {
        type    = "String"
        default = var.target_group_arn
      }
    })
    mainSteps = [
      local.prepare_step,
      {
        name      = "StartRecovery"
        action    = "aws:executeScript"
        onFailure = "Abort"

        inputs = {
          Runtime = local.runtime
          Handler = "start_recovery"
          Script  = local.script

          InputPayload = {
            SourceServerIds = "{{ Prepare.SourceServerIds }}"
            Mode            = "{{ Mode }}"
            PointInTime     = "{{ PointInTime }}"
          }
        }
        outputs = [{
          Name     = "JobId"
          Selector = "$.Payload.JobId"
          Type     = "String"
        }]
      },
      {
        name           = "WaitForJob"
        action         = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 3600
        onFailure      = "Abort"

        inputs = {
          Service          = "drs"
          Api              = "DescribeJobs"
          filters          = { jobIDs = ["{{ StartRecovery.JobId }}"] }
          PropertySelector = "$.items[0].status"
          DesiredValues    = ["COMPLETED"]
        }
      },
      {
        name      = "Finalize"
        action    = "aws:executeScript"
        onFailure = "Abort"

        inputs = {
          Runtime = local.runtime
          Handler = "finalize_recovery"
          Script  = local.script

          InputPayload = {
            JobId          = "{{ StartRecovery.JobId }}"
            Mode           = "{{ Mode }}"
            Register       = "{{ RegisterWithDrLoadBalancer }}"
            TargetGroupArn = "{{ TargetGroupArn }}"
          }
        }
        outputs = [
          { Name = "Ec2InstanceIds", Selector = "$.Payload.Ec2InstanceIds", Type = "StringList" },
          { Name = "RecoveryInstanceIds", Selector = "$.Payload.RecoveryInstanceIds", Type = "StringList" },
        ]
      },
    ]
    outputs = ["StartRecovery.JobId", "Finalize.Ec2InstanceIds", "Finalize.RecoveryInstanceIds"]
  })
}

# 3) Failback: reverse replication from recovery instances to the original side.
resource "aws_ssm_document" "failback" {
  name            = "${var.name}-Failback"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Start reversed replication for recovery instances (all non-drill instances by default)."
    assumeRole    = "{{ AutomationAssumeRole }}"

    parameters = {
      AutomationAssumeRole = local.common_parameters.AutomationAssumeRole

      RecoveryInstanceIds = {
        type        = "StringList"
        description = "DRS recovery instance IDs, or 'all'."
        default     = ["all"]
      }
    }
    mainSteps = [{
      name      = "ReverseReplication"
      action    = "aws:executeScript"
      onFailure = "Abort"

      inputs = {
        Runtime      = local.runtime
        Handler      = "reverse_replication"
        Script       = local.script
        InputPayload = { RecoveryInstanceIds = "{{ RecoveryInstanceIds }}" }
      }
      outputs = [{ Name = "RecoveryInstanceIds", Selector = "$.Payload.RecoveryInstanceIds", Type = "StringList" }]
    }]
    outputs = ["ReverseReplication.RecoveryInstanceIds"]
  })
}

# 4) Clean up drill instances after a test.
resource "aws_ssm_document" "terminate_drills" {
  name            = "${var.name}-TerminateDrills"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Terminate all DRS drill instances."
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters    = { AutomationAssumeRole = local.common_parameters.AutomationAssumeRole }

    mainSteps = [{
      name      = "Terminate"
      action    = "aws:executeScript"
      onFailure = "Abort"

      inputs = {
        Runtime      = local.runtime
        Handler      = "terminate_drills"
        Script       = local.script
        InputPayload = {}
      }
      outputs = [{ Name = "RecoveryInstanceIds", Selector = "$.Payload.RecoveryInstanceIds", Type = "StringList" }]
    }]
    outputs = ["Terminate.RecoveryInstanceIds"]
  })
}

# 5) Database failover: promote the replica and repoint db.<project>.internal.
resource "aws_ssm_document" "failover_database" {
  count           = var.enable_database_failover ? 1 : 0
  name            = "${var.name}-FailoverDatabase"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Promote the DR read replica to a standalone primary and point the private DB DNS record at it. One-way: rebuild replication afterwards (see docs/RUNBOOK.md)."
    assumeRole    = "{{ AutomationAssumeRole }}"

    parameters = {
      AutomationAssumeRole = local.common_parameters.AutomationAssumeRole
      ReplicaIdentifier    = { type = "String", default = var.db_replica_identifier }
      ReplicaAddress       = { type = "String", default = var.db_replica_address }
      HostedZoneId         = { type = "String", default = var.private_zone_id }
      RecordName           = { type = "String", default = var.db_record_fqdn }
    }
    mainSteps = [
      {
        name      = "PromoteReplica"
        action    = "aws:executeAwsApi"
        onFailure = "Abort"

        inputs = {
          Service               = "rds"
          Api                   = "PromoteReadReplica"
          DBInstanceIdentifier  = "{{ ReplicaIdentifier }}"
          BackupRetentionPeriod = 7
        }
      },
      {
        name   = "LetPromotionStart"
        action = "aws:sleep"
        inputs = { Duration = "PT2M" }
      },
      {
        name           = "WaitUntilAvailable"
        action         = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 3600
        onFailure      = "Abort"

        inputs = {
          Service              = "rds"
          Api                  = "DescribeDBInstances"
          DBInstanceIdentifier = "{{ ReplicaIdentifier }}"
          PropertySelector     = "$.DBInstances[0].DBInstanceStatus"
          DesiredValues        = ["available"]
        }
      },
      {
        name      = "RepointDnsRecord"
        action    = "aws:executeAwsApi"
        onFailure = "Abort"

        inputs = {
          Service      = "route53"
          Api          = "ChangeResourceRecordSets"
          HostedZoneId = "{{ HostedZoneId }}"

          ChangeBatch = {
            Comment = "DR database failover"

            Changes = [{
              Action = "UPSERT"

              ResourceRecordSet = {
                Name            = "{{ RecordName }}"
                Type            = "CNAME"
                TTL             = 30
                ResourceRecords = [{ Value = "{{ ReplicaAddress }}" }]
              }
            }]
          }
        }
      },
    ]
  })
}
