#!/usr/bin/env bash

# Copyright (c) 2026 community-scripts ORG
# Author: Hermandev07
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/workadventure/workadventure

if [[ -z "${FUNCTIONS_FILE_PATH:-}" ]]; then
  FUNCTIONS_FILE_PATH="$(curl -fsSL https://raw.githubusercontent.com/Hermandev07/ProxmoxVED/main/misc/install.func)"
fi

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing build dependencies"
$STD apt install -y \
  git \
  build-essential \
  maven \
  curl \
  wget \
  unzip
msg_ok "Installed Dependencies"

# Use project runtime helpers (they handle distro-specific installation)
JAVA_VERSION="17" setup_java
NODE_VERSION="18" setup_nodejs

msg_ok "Runtime setup complete"

msg_info "Deploying WorkAdventure source"
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "workadventure" "workadventure/workadventure" "tarball"
msg_ok "Deployed source to /opt/workadventure"

motd_ssh
customize
cleanup_lxc
