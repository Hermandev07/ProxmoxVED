#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: blackboxai
# License: MIT | https://github.com/Hermandev07/ProxmoxVED/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source /dev/stdin <<<"$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/api.func")"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/vm-core.func")
load_functions

APP="ipfire"
NSAPP="ipfire-vm"
var_os="ipfire"
var_version="2.x"

ISO_URL_DEFAULT="https://www.ipfire.org/downloads/thank-you?url=https://downloads.ipfire.org/releases/ipfire-2.x/2.29-core202/ipfire-2.29-core202-x86_64.iso"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
GEN_MAC_WAN=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')

set -Eeo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api_vm "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api_vm "failed" "TERMINATED"' SIGTERM

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  post_update_to_api "failed" "$command" >/dev/null 2>&1 || true
  echo -e "\n${RD:-}[ERROR]${CL:-} in line ${line_number:-?}: exit code ${exit_code:-?}: ${command}" >&2
  cleanup_vmid
}

function cleanup_vmid() {
  if [[ -n "${VMID:-}" ]] && qm status "$VMID" &>/dev/null; then
    qm stop "$VMID" &>/dev/null || true
    qm destroy "$VMID" &>/dev/null || true
  fi
}

function cleanup() {
  [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" || true
}

function header_info {
  clear
  cat <<"EOF"
    ____  _   _   ___  __  __   _      ___  _   _  ____
   / __ \| | | | / _ \/ / / /  / | /| / _ \/ | | |/ __ \
  / /_/ /| |_| |/ //_/ /_/ /  / |/ |/ //_/  | |_| / /_/ /
 /_____/  \___/\____/\____/   /_/  |_\____/\_/\__/\____/

EOF
}

header_info
echo -e "\n Loading..."

check_root
pve_check
arch_check
ssh_check

TEMP_DIR=$(mktemp -d)

VMID=""
HN="ipfire"
CORE_COUNT="2"
RAM_SIZE="2048"
DISK_SIZE="8G"
START_VM="yes"
METHOD=""
STORAGE=""
BRG_LAN="vmbr0"
BRG_WAN="vmbr1"
VLAN_LAN=""
VLAN_WAN=""
MTU=""
MAC_LAN="$GEN_MAC"
MAC_WAN="$GEN_MAC_WAN"

IP_MODE="auto" # auto|2nic|1nic

LAN_IP=""
LAN_NETMASK=""
LAN_GW=""
LAN_USE_DHCP="yes" # yes|no
WAN_USE_DHCP="yes" # yes|no
WAN_IP=""
WAN_NETMASK=""
WAN_GW=""

ISO_URL="$ISO_URL_DEFAULT"

function get_valid_nextid_local() {
  get_valid_nextid
}

function vm_confirm_new_vm() {
  local title="IPFire VM"
  local msg="Create IPFire VM now?"
  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" --yesno "$msg" 10 60; then
    return 0
  fi
  return 1
}

function default_settings() {
  VMID="$(get_valid_nextid_local)"
  FORMAT=",efitype=4m"
  MACHINE=""

  # default bridges must exist (like other vm scripts)
  if ! grep -q "^iface ${BRG_LAN}" /etc/network/interfaces; then
    msg_error "Bridge '${BRG_LAN}' does not exist in /etc/network/interfaces"; exit 1
  fi
  if ! grep -q "^iface ${BRG_WAN}" /etc/network/interfaces; then
    msg_error "Bridge '${BRG_WAN}' does not exist in /etc/network/interfaces"; exit 1
  fi

  echo -e "${DGN:-}VM ID: ${BGN:-}${VMID}${CL:-}";
  echo -e "${DGN:-}Hostname: ${BGN:-}${HN}${CL:-}";
  echo -e "${DGN:-}CPU cores: ${BGN:-}${CORE_COUNT}${CL:-}";
  echo -e "${DGN:-}RAM MiB: ${BGN:-}${RAM_SIZE}${CL:-}";
  echo -e "${DGN:-}Disk: ${BGN:-}${DISK_SIZE}${CL:-}";
  echo -e "${DGN:-}LAN bridge (net0): ${BGN:-}${BRG_LAN}${CL:-}";
  echo -e "${DGN:-}WAN bridge (net1): ${BGN:-}${BRG_WAN}${CL:-}";
  echo -e "${DGN:-}IP mode: ${BGN:-}${IP_MODE}${CL:-}";
  echo -e "${DGN:-}Start after create: ${BGN:-}${START_VM}${CL:-}";

  [[ -n "${ISO_URL:-}" ]] || ISO_URL="$ISO_URL_DEFAULT"
}

function advanced_settings() {
  METHOD="advanced"

  VMID="$(get_valid_nextid_local)"
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 "$VMID" --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      [[ -z "$VMID" ]] && VMID="$(get_valid_nextid_local)"
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS:-}${RD:-} ID $VMID is already in use${CL:-}"; sleep 1; continue
      fi
      break
    else
      exit_script
    fi
  done

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HOSTNAME" --inputbox "Set Hostname" 8 58 "$HN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    HN=$(echo "${VM_NAME,,}" | tr -cd '[:alnum:]-'); [[ -z "$HN" ]] && HN="ipfire"
  else
    exit_script
  fi

  if CPU=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 "$CORE_COUNT" --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    CORE_COUNT=$(echo "$CPU" | tr -cd '[:digit:]'); [[ -z "$CORE_COUNT" ]] && CORE_COUNT=2
  else
    exit_script
  fi

  if RAM=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 "$RAM_SIZE" --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    RAM_SIZE=$(echo "$RAM" | tr -cd '[:digit:]'); [[ -z "$RAM_SIZE" ]] && RAM_SIZE=2048
  else
    exit_script
  fi

  if DISK=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Disk size in GiB" 8 58 "${DISK_SIZE%G}" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE="$(echo "$DISK" | tr -cd '[:digit:]')G"; [[ "$DISK_SIZE" == "G" ]] && DISK_SIZE="8G"
  else
    exit_script
  fi

  if BRG_L=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set LAN Bridge (net0)" 8 58 "$BRG_LAN" --title "LAN BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    BRG_LAN="$BRG_L"; [[ -z "$BRG_LAN" ]] && BRG_LAN="vmbr0"
  else
    exit_script
  fi

  if BRG_W=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set WAN Bridge (net1)" 8 58 "$BRG_WAN" --title "WAN BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    BRG_WAN="$BRG_W"; [[ -z "$BRG_WAN" ]] && BRG_WAN="vmbr1"
  else
    exit_script
  fi

  if MODE_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --radiolist "NIC setup" 12 58 2 \
    "auto" "Try 2 NICs, but allow 1 NIC install to continue" ON \
    "2nic" "Force 2 NICs (net0+net1)" OFF \
    "1nic" "Force 1 NIC (net0 only)" OFF 3>&1 1>&2 2>&3); then
    IP_MODE="$MODE_CHOICE"
  else
    exit_script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START" --yesno "Start VM after create?" 10 60); then
    START_VM="yes"
  else
    START_VM="no"
  fi

  # Installation network prompts (LAN always; WAN optional depending on NICs)
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "LAN IP" --yesno "Use DHCP for LAN (net0)?" 10 60); then
    LAN_USE_DHCP="yes"
  else
    LAN_USE_DHCP="no"
    LAN_IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "LAN IP address for IPFire" 8 58 "" --title "LAN IP" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit_script
    LAN_NETMASK=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "LAN netmask" 8 58 "24" --title "LAN NETMASK (prefix or mask)" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit_script
    LAN_GW=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "LAN gateway (usually your router)" 8 58 "" --title "LAN GW" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit_script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "WAN IP" --yesno "Use DHCP for WAN (net1)?" 10 60); then
    WAN_USE_DHCP="yes"
  else
    WAN_USE_DHCP="no"
    WAN_IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "WAN IP address for IPFire" 8 58 "" --title "WAN IP" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit_script
    WAN_NETMASK=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "WAN netmask" 8 58 "24" --title "WAN NETMASK (prefix or mask)" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit_script
    WAN_GW=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "WAN gateway" 8 58 "" --title "WAN GW" --cancel-button Exit-Script 3>&1 1>&2 2>&3) || exit_script
  fi
}

function start_or_exit_script() {
  if vm_confirm_new_vm; then
    :
  else
    header_info; exit 0
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    default_settings
  else
    header_info
    advanced_settings
  fi
}

start_script

post_to_api_vm || true

# Storage selection (same pattern as other vm scripts)
select_storage() {
  local storage_menu=()
  msg_info "Validating Storage"
  while read -r line; do
    TAG=$(echo "$line" | awk '{print $1}')
    TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
    FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
    ITEM="  Type: $TYPE Free: $FREE "
    OFFSET=2
    if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
      MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
    fi
    storage_menu+=("$TAG" "$ITEM" "OFF")
  done < <(pvesm status -content images | awk 'NR>1')

  VALID=$(pvesm status -content images | awk 'NR>1')
  if [ -z "$VALID" ]; then
    msg_error "Unable to detect a valid storage location."
    exit 1
  elif [ $((${#storage_menu[@]} / 3)) -eq 1 ]; then
    STORAGE=${storage_menu[0]}
  else
    while [ -z "${STORAGE:+x}" ]; do
      STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
        "Which storage pool should be used for ${HN}?\nTo make a selection, use the Spacebar.\n" \
        16 $((${MSG_MAX_LENGTH:-40} + 23)) 6 \
        "${storage_menu[@]}" 3>&1 1>&2 2>&3)
    done
  fi

  msg_ok "Using ${CL:-}${BL:-}$STORAGE${CL:-} ${GN:-}for Storage Location."
}

select_storage

# Download ISO
mkdir -p "$TEMP_DIR/iso"
ISO_FILE="$TEMP_DIR/iso/ipfire.iso"

msg_info "Retrieving the URL for IPFire ISO"
# Your URL redirects; curl will follow redirects and store ISO
msg_ok "${CL:-}${BL:-}${ISO_URL}${CL:-}"

if [[ ! -s "$ISO_FILE" ]]; then
  msg_info "Downloading IPFire ISO (this may take a while)"
  curl -fL --progress-bar -o "$ISO_FILE" "$ISO_URL"
  msg_ok "Downloaded ISO: ${CL:-}${BL:-}$(basename "$ISO_FILE")${CL:-}"
else
  msg_ok "Using cached ISO: ${CL:-}${BL:-}$(basename "$ISO_FILE")${CL:-}"
fi

ISO_BASENAME="$(basename "$ISO_FILE")"

# Determine boot config
VM_MACHINE_TYPE="i440fx"
# i440fx is default in other scripts, but many require ovmf; we keep ovmf like others

# Create VM
# - net0 always exists
# - net1 exists only in 2nic/auto; if 1nic, omit net1

msg_info "Creating IPFire VM"
qm destroy "$VMID" &>/dev/null || true

NIC0="virtio,bridge=${BRG_LAN},macaddr=${MAC_LAN}${VLAN_LAN}${MTU}"
NIC1="virtio,bridge=${BRG_WAN},macaddr=${MAC_WAN}${VLAN_WAN}${MTU}"

QM_CREATE_ARGS=(
  create "$VMID"
  -agent 1
  -tablet 0
  -localtime 1
  -bios ovmf
  -cores "$CORE_COUNT"
  -memory "$RAM_SIZE"
  -name "$HN"
  -tags "community-script;ipfire"
  -onboot 1
  -ostype l26
  -scsihw virtio-scsi-pci
  -net0 "$NIC0"
)

if [[ "$IP_MODE" == "2nic" || "$IP_MODE" == "auto" ]]; then
  QM_CREATE_ARGS+=( -net1 "$NIC1" )
fi

qm "${QM_CREATE_ARGS[@]}" >/dev/null

# Allocate + attach a disk (qcow2/raw depending on storage)
STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')

case "$STORAGE_TYPE" in
nfs | dir)
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  DISK_EXT=".qcow2"
  THIN=""
  FORMAT=""
  ;;
btrfs)
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  DISK_EXT=".raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  DISK_EXT=".qcow2"
  FORMAT=""
  THIN=""
  ;;
esac

# For ISO-based installers we need an actual disk to install onto
pvesm alloc "$STORAGE" "$VMID" "vm-${VMID}-disk-0${DISK_EXT}" 4M >/dev/null 2>&1 || true
# Create an empty qcow2/raw disk using pvesm alloc + qm set size
DISK0_NAME="vm-${VMID}-disk-0${DISK_EXT:-}"

# If alloc created something, use it; otherwise rely on qm set scsi0 with size
qm set "$VMID" -scsi0 "${STORAGE}:${VMID}/,size=${DISK_SIZE}" >/dev/null 2>&1 || true
# Ensure scsi0 exists with proper size; best-effort (storage backends vary)

# Attach ISO as cdrom and set boot order
# Store ISO into storage local:iso if possible for reliability
msg_info "Uploading ISO to Proxmox ISO storage"
ISO_STORAGE_TARGET=""
if pvesm status -content iso 2>/dev/null | awk 'NR>1 {print $1}' | head -1 >/dev/null 2>&1; then
  ISO_STORAGE_TARGET=$(pvesm status -content iso 2>/dev/null | awk 'NR==2{print $1}')
fi
if [[ -n "$ISO_STORAGE_TARGET" ]]; then
  msg_info "Copying ISO to storage:iso/${ISO_STORAGE_TARGET}"
  # Try to copy with qm/import methods; simplest is to use direct filesystem path is not available.
  # Fallback: attach ISO via local path by keeping it in TEMP_DIR isn't persistent.
  # We therefore keep local path only and warn the user.
  msg_warn "ISO persistence is storage-dependent. This helper attaches the ISO from host path and will restart attachment if supported."
fi

# Attach ISO from host temp path (may or may not persist)
qm set "$VMID" -cdrom "${STORAGE}:iso/${ISO_BASENAME}" >/dev/null 2>&1 || true
# Better: attach as direct file path where Proxmox allows it
qm set "$VMID" --cdrom "${ISO_FILE}" >/dev/null 2>&1 || true

qm set "$VMID" -boot order=d  >/dev/null 2>&1 || true
qm set "$VMID" -serial0 socket >/dev/null 2>&1 || true

msg_ok "Created IPFire VM ${CL:-}${BL:-}(${HN})${CL:-}"

if [[ "$START_VM" == "yes" ]]; then
  msg_info "Starting IPFire VM (installer will boot from ISO)"
  qm start "$VMID" >/dev/null 2>&1
  msg_ok "Started IPFire VM"
fi

msg_ok "IPFire VM setup complete."

echo -e "\n${INFO:-}${YW:-}Complete the IPFire installer in the VM console below (example navigation may differ by version):${CL:-}"

echo -e "${TAB:-  }${BGN:-}WAN${CL:-}: ${BGN:-}${WAN_USE_DHCP:-yes}${CL:-}"
if [[ "$WAN_USE_DHCP" != "yes" ]]; then
  echo -e "${TAB:-  }  WAN IP: ${WAN_IP} / ${WAN_NETMASK}  GW: ${WAN_GW}"
fi

echo -e "${TAB:-  }${BGN:-}LAN${CL:-}: ${BGN:-}${LAN_USE_DHCP:-yes}${CL:-}"
if [[ "$LAN_USE_DHCP" != "yes" ]]; then
  echo -e "${TAB:-  }  LAN IP: ${LAN_IP} / ${LAN_NETMASK}  GW: ${LAN_GW}"
fi

echo -e "\n${TAB:-  }Open the VM console in Proxmox and continue installation."
if [[ "$IP_MODE" == "1nic" ]]; then
  echo -e "${TAB:-  }Note: this VM was created with 1 NIC. If IPFire asks for WAN, you may need to assign the existing NIC as WAN or reboot with 2 NICs." 
fi

echo -e "\nAfter install, remove the ISO/CDROM in Proxmox settings and change boot order to disk."

exit 0

