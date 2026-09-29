#!/usr/bin/env bash
# Installs the AWS Replication Agent on the source server via SSM Run Command
# (the video does the same interactively: sudo -i, download, run installer,
#  enter region + access key + secret, press Enter to replicate all disks).
#
# NOTE: the access key is passed as a command parameter and is visible in the
# SSM command history. Delete it afterwards: set create_agent_access_key=false
# and run `terraform apply` (the agent keeps working with its own credentials).
source "$(dirname "$0")/common.sh"

AK="$(tfout agent_access_key_id)"
SK="$(tfout agent_secret_access_key)"
[[ -n "$AK" ]] || { echo "No agent access key. Set create_agent_access_key=true and apply." >&2; exit 1; }

URL="https://aws-elastic-disaster-recovery-${REGION}.s3.${REGION}.amazonaws.com/latest/linux/aws-replication-installer-init"
INSTALL="/root/aws-replication-installer-init --region ${REGION} --aws-access-key-id ${AK} --aws-secret-access-key ${SK} --no-prompt"

echo "Waiting for $SOURCE_INSTANCE_ID to be online in SSM..."
for _ in $(seq 1 40); do
  STATUS=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=${SOURCE_INSTANCE_ID}" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)
  [[ "$STATUS" == "Online" ]] && break
  sleep 15
done
[[ "$STATUS" == "Online" ]] || { echo "Instance not online in SSM." >&2; exit 1; }

PARAMS=$(cat <<JSON
{"commands":[
  "cloud-init status --wait || true",
  "test -x /root/aws-replication-installer-init || (curl -fsSL -o /root/aws-replication-installer-init ${URL} && chmod +x /root/aws-replication-installer-init)",
  "${INSTALL}"
],"executionTimeout":["3600"]}
JSON
)

CMD_ID=$(aws ssm send-command --region "$REGION" \
  --instance-ids "$SOURCE_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "Install AWS DRS replication agent" \
  --parameters "$PARAMS" \
  --query 'Command.CommandId' --output text)
echo "SSM command: $CMD_ID"

while true; do
  S=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" \
      --instance-id "$SOURCE_INSTANCE_ID" --query Status --output text 2>/dev/null || echo Pending)
  case "$S" in
    Success) break ;;
    Failed|Cancelled|TimedOut)
      aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" \
        --instance-id "$SOURCE_INSTANCE_ID" --query '[StandardOutputContent,StandardErrorContent]' --output text
      exit 1 ;;
    *) echo "  agent install: $S"; sleep 20 ;;
  esac
done

aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" \
  --instance-id "$SOURCE_INSTANCE_ID" --query StandardOutputContent --output text | tail -n 5
echo "Source server registered in DRS as: $(source_server_id)"
