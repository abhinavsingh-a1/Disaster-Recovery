
# aws-drs-terraform-v2 (aws-drs-terraform-cross-az)

```
Terraform + AWS CLI lab for AWS Elastic Disaster Recovery:
continuous replication of an Apache EC2 server across AZs, point-in-time recovery, drills, Elastic IP failover and failback,
with architecture diagram and runbook.
```

<img src="https://raw.githubusercontent.com/abhinavsingh-a1/Disaster-Recovery/c7dcef0b07b1a1f838a4aa6307ac81233a6b772a/aws-drs-terraform-v2/docs/architecture-v2.svg">

# terraform-aws-dr (aws-multi-region-dr-terraform)

```
Terraform project for multi-region disaster recovery on AWS.
One variable switches between the four DR strategies (backup & restore, pilot light, warm standby, multi-site) using Route 53 failover, Aurora Global Database, Auto Scaling, and AWS Backup with cross-region copies and Vault Lock.
Includes a failover runbook script and an architecture diagram.
```


# serverless-dr-terraform (serverless-dr-active-active-terraform)

```
Multi-region active/active disaster recovery for a serverless REST API on AWS, built with Terraform.
API Gateway + Lambda in two regions, DynamoDB global table replication, Route 53 latency routing with health-check failover,
replication-lag alarms, PITR backups, and a scripted failover drill.
```

<img src="https://raw.githubusercontent.com/abhinavsingh-a1/Disaster-Recovery/01a295c776d08beecc197121a7078faa8016b78b/serverless-dr-terraform/docs/architecture.svg">

# aws-drs-terraform (aws-drs-terraform-lab)

```
Terraform lab for AWS Elastic Disaster Recovery (DRS):
cross-AZ recovery of an EC2 server with continuous replication, point-in-time snapshots, drill/recovery and failover.
Includes helper scripts, cleanup automation and an architecture diagram.
```

<img src="https://raw.githubusercontent.com/abhinavsingh-a1/Disaster-Recovery/ac06c5ee79a9664701fb4d969cbf37c0bc0bb480/aws-drs-terraform/docs/architecture.svg">

