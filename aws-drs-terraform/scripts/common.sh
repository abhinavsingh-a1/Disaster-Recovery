#!/usr/bin/env bash
# Shared helpers: read Terraform outputs and look up the DRS source server.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

tfout() { terraform output -raw "$1"; }

REGION="$(tfout region)"
PROJECT="$(tfout project_name)"
SOURCE_INSTANCE_ID="$(tfout source_instance_id)"

# DRS source server ID that belongs to our EC2 source instance ("s-xxxxxxxx")
source_server_id() {
  aws drs describe-source-servers --region "$REGION" \
    --query "items[?sourceProperties.identificationHints.awsInstanceID=='${SOURCE_INSTANCE_ID}'].sourceServerID | [0]" \
    --output text
}

require_source_server() {
  SRC_ID="$(source_server_id)"
  if [[ -z "$SRC_ID" || "$SRC_ID" == "None" ]]; then
    echo "No DRS source server found for $SOURCE_INSTANCE_ID. Run ./scripts/install-agent.sh first." >&2
    exit 1
  fi
}
