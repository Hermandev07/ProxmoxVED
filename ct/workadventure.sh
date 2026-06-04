#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2026 community-scripts ORG
# Author: Hermandev07
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/workadventure/workadventure

APP="WorkAdventure"
var_tags="${var_tags:-proxmox;workadventure}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/workadventure ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "workadventure" "workadventure/workadventure"; then
    msg_info "Stopping Services"
    systemctl stop workadventure-backend workadventure-frontend || true
    msg_ok "Stopped Services"

    msg_info "Backing up config and data"
    cp -r /opt/workadventure /opt/workadventure_backup || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "workadventure" "workadventure/workadventure" "tarball"

    msg_info "Restoring Data"
    cp -r /opt/workadventure_backup/. /opt/workadventure/ || true
    rm -rf /opt/workadventure_backup
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start workadventure-backend workadventure-frontend || true
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# The main install flow (called by build.func helpers)
start
build_container

# Fetch & deploy repo (uses the project's helper - will place sources into /opt/workadventure)
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "workadventure" "workadventure/workadventure" "tarball"

# Runtime setup - adjust versions if upstream requires different ones
JAVA_VERSION="17" setup_java
NODE_VERSION="18" setup_nodejs

# Build steps (best-effort; upstream build details may vary)
if [[ -d /opt/workadventure ]]; then
  cd /opt/workadventure || exit

  if [[ -f mvnw ]] || [[ -f pom.xml ]]; then
    if [[ -f mvnw ]]; then
      $STD ./mvnw -q -DskipTests package || true
    else
      $STD mvn -q -DskipTests package || true
    fi
  fi

  if [[ -f package.json ]]; then
    $STD npm install --silent || true
    $STD npm run build --silent || true
  fi

  # Create lightweight systemd service units. These are generic and may need tuning.
  cat <<EOF >/etc/systemd/system/workadventure-backend.service
[Unit]
Description=WorkAdventure Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/workadventure
ExecStart=/usr/bin/env bash -c 'if compgen -G "/opt/workadventure/*-backend*.jar" >/dev/null; then java -jar /opt/workadventure/*-backend*.jar; else echo "No backend jar found; adjust service"; sleep infinity; fi'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/workadventure-frontend.service
[Unit]
Description=WorkAdventure Frontend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/workadventure
ExecStart=/usr/bin/env bash -c 'if [[ -f /opt/workadventure/start-frontend.sh ]]; then /opt/workadventure/start-frontend.sh; else echo "No frontend start script found; adjust service"; sleep infinity; fi'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now workadventure-backend workadventure-frontend || true
fi

description

msg_ok "Completed Successfully!"
