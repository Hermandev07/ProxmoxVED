#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BLACKBOXAI
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/workadventure/workadventure

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  curl \
  ca-certificates
msg_ok "Installed Dependencies"

# Runtime Setup
NODE_VERSION="22" setup_nodejs

msg_info "Installing WorkAdventure (sources)"
fetch_and_deploy_gh_release "workadventure" "workadventure/workadventure" "tarball"

msg_info "Configuring Node workspaces"
cd /opt/workadventure
$STD npm ci || $STD npm install

# Build subprojects if present (mirrors the provided Dockerfile fragments concept)
if [[ -d play ]]; then
  msg_info "Building Play"
  cd play
  $STD npm run -s typesafe-i18n || true
  $STD npm run -s build-iframe-api || true
  $STD npm run -s build || true
  cd ..
  msg_ok "Built Play"
fi

if [[ -d back ]]; then
  msg_info "Building Back"
  cd back
  $STD npm install -s || true
  $STD npm run -s runprod || $STD npm run -s build || true
  cd ..
  msg_ok "Built Back"
fi

if [[ -d map-storage ]]; then
  msg_info "Building Map Storage UI"
  cd map-storage
  $STD npm install -s || true
  $STD npm run -s front:build || true
  $STD npm run -s build || true
  cd ..
  msg_ok "Built Map Storage"
fi

cat <<'EOF' >/etc/systemd/system/workadventure.service
[Unit]
Description=WorkAdventure (play/back/map-storage)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/workadventure
Environment=NODE_ENV=production
# Upstream typically provides a start script for the whole stack; we rely on package scripts.
# If upstream changes, update this unit accordingly.
ExecStart=/bin/bash -lc 'cd /opt/workadventure && npm run -s start'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now workadventure
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

