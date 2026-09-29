#!/usr/bin/env bash
# Applies the video's launch settings to the DRS source server:
#   - instance type right-sizing OFF (so our own instance type is used)
#   - instance type = recovery_instance_type (c5.large)
#   - launch into the recovery subnet, same SG as source, public IP = yes
# Storage settings of the launch template are deliberately NOT touched
# (the video warns that changing them breaks drills/recoveries).
source "$(dirname "$0")/common.sh"
require_source_server

SUBNET="$(tfout recovery_subnet_id)"
SG="$(tfout app_security_group_id)"
ITYPE="$(tfout recovery_instance_type)"

aws drs update-launch-configuration --region "$REGION" \
  --source-server-id "$SRC_ID" \
  --target-instance-type-right-sizing-method NONE \
  --launch-disposition STARTED \
  --no-copy-private-ip \
  --copy-tags >/dev/null

LT_ID=$(aws drs get-launch-configuration --region "$REGION" \
  --source-server-id "$SRC_ID" --query ec2LaunchTemplateID --output text)

DATA=$(cat <<JSON
{
  "InstanceType": "${ITYPE}",
  "NetworkInterfaces": [{
    "DeviceIndex": 0,
    "SubnetId": "${SUBNET}",
    "Groups": ["${SG}"],
    "AssociatePublicIpAddress": true,
    "DeleteOnTermination": true
  }],
  "TagSpecifications": [{
    "ResourceType": "instance",
    "Tags": [{"Key": "Name", "Value": "${PROJECT}-recovery-server"}]
  }]
}
JSON
)

VER=$(aws ec2 create-launch-template-version --region "$REGION" \
  --launch-template-id "$LT_ID" --source-version '$Default' \
  --version-description "${PROJECT}: recovery subnet, ${ITYPE}, public IP" \
  --launch-template-data "$DATA" \
  --query 'LaunchTemplateVersion.VersionNumber' --output text)

aws ec2 modify-launch-template --region "$REGION" \
  --launch-template-id "$LT_ID" --default-version "$VER" >/dev/null

echo "Launch template $LT_ID -> default version $VER ($ITYPE in $SUBNET, public IP)."
