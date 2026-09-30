#!/bin/bash
# Installs and starts the DR demo app (app/app.py) as a systemd service.
set -euo pipefail

retry() { # retry <attempts> <command...> - NAT and IAM can take a moment after boot
  local n=$1; shift
  for ((i = 1; i <= n; i++)); do "$@" && return 0; sleep 10; done
  return 1
}

retry 30 dnf install -y python3-pip
retry 30 pip3 install --quiet "PyMySQL==1.1.1"

install -d -m 755 /opt/dr-app
install -d -m 700 /etc/dr-app
echo '${app_b64gz}' | base64 -d | gunzip > /opt/dr-app/app.py
echo '${config_b64}' | base64 -d > /etc/dr-app/config.json

# Database credentials from the Secrets Manager copy in THIS region
retry 30 aws secretsmanager get-secret-value \
  --region '${region}' \
  --secret-id '${secret_name}' \
  --query SecretString --output text > /etc/dr-app/db-secret.json
chmod 600 /etc/dr-app/db-secret.json /etc/dr-app/config.json

cat > /etc/systemd/system/dr-app.service <<'UNIT'
[Unit]
Description=DR demo web app
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/dr-app/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now dr-app
