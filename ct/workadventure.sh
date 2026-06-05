#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Hermandev07
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/workadventure/workadventure

APP="WorkAdventure"
var_tags="${var_tags:-gaming;education;virtual-world}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

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
    msg_info "Stopping Service"
    systemctl stop workadventure
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    if [[ -f /etc/workadventure.env ]]; then
      cp -a /etc/workadventure.env /opt/workadventure_env.bak
    fi
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "workadventure" "workadventure/workadventure" "tarball"

    msg_info "Rebuilding WorkAdventure (Patience)"
    cd /opt/workadventure || exit

    if [[ -f package.json ]]; then
      $STD rm -rf play node_modules libs
      # install dependencies (workspace-like) in upstream repo
      $STD npm ci || $STD npm install
    fi

    # Build targets similar to provided Dockerfile fragments.
    # Keep this best-effort; upstream repo layout may vary between releases.
    if [[ -d play ]]; then
      cd play || exit

      $STD npm run -s typesafe-i18n || true
      $STD npm run -s build-iframe-api || true
      $STD npm run -s build || true
      cd ..
    fi

    if [[ -d back ]]; then
      cd back
      $STD npm install -s || true
      $STD npm run -s runprod || $STD npm run -s build || true
      cd ..
    fi

    if [[ -d map-storage ]]; then
      cd map-storage
      $STD npm install -s || true
      $STD npm run -s front:build || true
      $STD npm run -s build || true
      cd ..
    fi

    if [[ -f /opt/workadventure_env.bak ]]; then
      cp -a /opt/workadventure_env.bak /etc/workadventure.env
      rm -f /opt/workadventure_env.bak
    fi

    msg_info "Starting Service"
    systemctl start workadventure
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"

