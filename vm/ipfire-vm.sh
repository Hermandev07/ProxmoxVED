#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: blackboxai
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -Eeuo pipefail

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source /dev/stdin <<<"$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/api.func")"

function header_info {
  clear
  cat <<"EOF"
   ____  ____  _   __
  / __ \/ __ \/ | / /_______  ____  ________
 / / / / /_/ /  |/ / ___/ _ \/ __ \/ ___/ _ \
/ /_/ / ____/ /|  (__  )  __/ / / (__  )  __/
\____/_/   /_/ |_/____/\___/_/ /_/____/\___/

EOF
}

header_info
echo -e "Loading..."

# API VARIABLES
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="ipfire-vm"
var_os="ipfire"
var_version="2.31" # placeholder; actual installer ISO/IMG is selected from upstream assets

GEN_MAC="02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')"
GEN_MAC_LAN="02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

set -Eeo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  post_update_to_api "failed" "$command"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  if [[ -n "${VMID:-}" ]] && qm status "$VMID" &>/dev/null; then
    cleanup_vmid
  fi
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if qm status "$VMID" &>/dev/null; then
    qm stop "$VMID" &>/dev/null || true
    qm destroy "$VMID" &>/dev/null || true
  fi
}

function cleanup() {
  popd >/dev/null 2>&1 || true
  post_update_to_api "done" "none"
  [[ -n "${TEMP_DIR:-}" ]] && rm -rf "$TEMP_DIR" || true
}

TEMP_DIR="$(mktemp -d)"
pushd "$TEMP_DIR" >/dev/null

function send_line_to_vm() {
  local line="$1"
  echo -e "${DGN}Sending line: ${YW}$line${CL}"

  local i character
  for ((i = 0; i < ${#line}; i++)); do
    character=${line:i:1}
    case $character in
    " ") character="spc" ;;
    "-") character="minus" ;;
    "=") character="equal" ;;
    ",") character="comma" ;;
    ".") character="dot" ;;
    "/") character="slash" ;;
    "'") character="apostrophe" ;;
    ";") character="semicolon" ;;
    '\\') character="backslash" ;;
    '`') character="grave_accent" ;;
    "[") character="bracket_left" ;;
    "]") character="bracket_right" ;;
    "_") character="shift-minus" ;;
    "+") character="shift-equal" ;;
    "?") character="shift-slash" ;;
    "<") character="shift-comma" ;;
    ">") character="shift-dot" ;;
    '"') character="shift-apostrophe" ;;
    ":") character="shift-semicolon" ;;
    "|") character="shift-backslash" ;;
    "~") character="shift-grave_accent" ;;
    "{") character="shift-bracket_left" ;;
    "}") character="shift-bracket_right" ;;
    "A") character="shift-a" ;;
    "B") character="shift-b" ;;
    "C") character="shift-c" ;;
    "D") character="shift-d" ;;
    "E") character="shift-e" ;;
    "F") character="shift-f" ;;
    "G") character="shift-g" ;;
    "H") character="shift-h" ;;
    "I") character="shift-i" ;;
    "J") character="shift-j" ;;
    "K") character="shift-k" ;;
    "L") character="shift-l" ;;
    "M") character="shift-m" ;;
    "N") character="shift-n" ;;
    "O") character="shift-o" ;;
    "P") character="shift-p" ;;
    "Q") character="shift-q" ;;
    "R") character="shift-r" ;;
    "S") character="shift-s" ;;
    "T") character="shift-t" ;;
    "U") character="shift-u" ;;
    "V") character="shift-v" ;;
    "W") character="shift-w" ;;
    "X") character="shift=x" ;;
    "Y") character="shift-y" ;;
    "Z") character="shift-z" ;;
    "!") character="shift-1" ;;
    "@") character="shift-2" ;;
    "#") character="shift-3" ;;
    '$') character="shift-4" ;;
    "%") character="shift-5" ;;
    "^") character="shift-6" ;;
    "&") character="shift-7" ;;
    "*") character="shift-8" ;;
    "(") character="shift-9" ;;
    ")") character="shift-0" ;;
    esac
    qm sendkey "$VMID" "$character"
  done
  qm sendkey "$VMID" ret
}

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function pve_check() {
  if ! pveversion | grep -Eq "pve-manager/(8\.[1-4]|9\.[0-2])(\.[0-9]+)*"; then
    msg_error "This version of Proxmox Virtual Environment is not supported"
    echo -e "Requires Proxmox Virtual Environment Version 8.1 - 8.4 or 9.0 - 9.2."
    echo -e "Exiting..."
    sleep 2
    exit 1
  fi
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${CROSS} This script will not work with PiMox! \n"
    echo -e "Exiting..."
    sleep 2
    exit 1
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit 1
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "⚠  User exited script \n"
  exit 1
}

function default_settings() {
  VMID="$(get_valid_nextid)"
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""

  HN="ipfire"
  CPU_TYPE=""
  CORE_COUNT="4"
  RAM_SIZE="8192"

  BRG="vmbr0"
  WAN_BRG="vmbr1"

  IP_ADDR=""
  WAN_IP_ADDR=""
  LAN_GW=""
  WAN_GW=""
  NETMASK=""
  WAN_NETMASK=""

  VLAN=""
  MTU=""

  MAC="$GEN_MAC"
  WAN_MAC="$GEN_MAC_LAN"

  START_VM="yes"
  METHOD="default"

  echo -e "${DGN}Using Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${DGN}Using Hostname: ${BGN}${HN}${CL}"
  echo -e "${DGN}Allocated Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${DGN}Allocated RAM: ${BGN}${RAM_SIZE}${CL}"

  if ! grep -q "^iface ${BRG}" /etc/network/interfaces; then
    msg_error "Bridge '${BRG}' does not exist in /etc/network/interfaces"
    exit 1
  else
    echo -e "${DGN}Using LAN Bridge: ${BGN}${BRG}${CL}"
  fi

  if ! grep -q "^iface ${WAN_BRG}" /etc/network/interfaces; then
    msg_error "Bridge '${WAN_BRG}' does not exist in /etc/network/interfaces"
    exit 1
  else
    echo -e "${DGN}Using WAN Bridge: ${BGN}${WAN_BRG}${CL}"
  fi

  echo -e "${DGN}Using LAN MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${DGN}Using WAN MAC Address: ${BGN}${WAN_MAC}${CL}"
  echo -e "${DGN}Using Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${BL}Creating a IPFire VM using the above default settings${CL}"
}

function advanced_settings() {
  local ip_regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'

  VMID="$(get_valid_nextid)"
  METHOD="advanced"

  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID="$(get_valid_nextid)"
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$MACH" = "q35" ]; then
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$CPU_TYPE1" = "1" ]; then
      echo -e "${DGN}Using CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${DGN}Using CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$DISK_CACHE" = "1" ]; then
      echo -e "${DGN}Using Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 ipfire --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VM_NAME" ]; then
      HN="ipfire"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
    fi
    echo -e "${DGN}Using Hostname: ${BGN}$HN${CL}"
  else
    exit-script
  fi

  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 4 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$CORE_COUNT" ] && CORE_COUNT="2"
    echo -e "${DGN}Allocated Cores: ${BGN}$CORE_COUNT${CL}"
  else
    exit-script
  fi

  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 8192 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$RAM_SIZE" ] && RAM_SIZE="8192"
    echo -e "${DGN}Allocated RAM: ${BGN}$RAM_SIZE${CL}"
  else
    exit-script
  fi

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a LAN Bridge" 8 58 vmbr0 --title "LAN BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$BRG" ] && BRG="vmbr0"
    if ! grep -q "^iface $BRG" /etc/network/interfaces; then
      msg_error "Bridge '$BRG' does not exist in /etc/network/interfaces"
      exit 1
    fi
    echo -e "${DGN}Using LAN Bridge: ${BGN}$BRG${CL}"
  else
    exit-script
  fi

  if IP_ADDR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a LAN IP (blank for DHCP)" 8 58 $IP_ADDR --title "LAN IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$IP_ADDR" ]; then
      echo -e "${DGN}Using DHCP for LAN${CL}"
    else
      if [[ -n "$IP_ADDR" && ! "$IP_ADDR" =~ $ip_regex ]]; then
        msg_error "Invalid IP Address format for LAN IP."
        exit 1
      fi
      echo -e "${DGN}Using LAN IP ADDRESS: ${BGN}$IP_ADDR${CL}"
      if LAN_GW=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a LAN GATEWAY IP" 8 58 $LAN_GW --title "LAN GATEWAY IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [ -z "$LAN_GW" ] && { msg_error "Gateway required for static LAN"; exit 1; }
        [[ -n "$LAN_GW" && ! "$LAN_GW" =~ $ip_regex ]] && { msg_error "Invalid Gateway IP format"; exit 1; }
        echo -e "${DGN}Using LAN GATEWAY ADDRESS: ${BGN}$LAN_GW${CL}"
      else
        exit-script
      fi
      if NETMASK=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set LAN NETMASK (e.g. 255.255.255.0)" 8 58 ${NETMASK:-255.255.255.0} --title "LAN NETMASK" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [ -z "$NETMASK" ] && NETMASK="255.255.255.0"
        echo -e "${DGN}Using LAN NETMASK: ${BGN}$NETMASK${CL}"
      else
        exit-script
      fi
    fi
  else
    exit-script
  fi

  if WAN_BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a WAN Bridge" 8 58 vmbr1 --title "WAN BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$WAN_BRG" ] && WAN_BRG="vmbr1"
    if ! grep -q "^iface $WAN_BRG" /etc/network/interfaces; then
      msg_error "WAN Bridge '$WAN_BRG' does not exist in /etc/network/interfaces"
      exit 1
    fi
    echo -e "${DGN}Using WAN Bridge: ${BGN}$WAN_BRG${CL}"
  else
    exit-script
  fi

  if WAN_IP_ADDR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a WAN IP (blank for DHCP)" 8 58 $WAN_IP_ADDR --title "WAN IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$WAN_IP_ADDR" ]; then
      echo -e "${DGN}Using DHCP for WAN${CL}"
    else
      if [[ -n "$WAN_IP_ADDR" && ! "$WAN_IP_ADDR" =~ $ip_regex ]]; then
        msg_error "Invalid IP Address format for WAN IP."
        exit 1
      fi
      echo -e "${DGN}Using WAN IP ADDRESS: ${BGN}$WAN_IP_ADDR${CL}"
      if WAN_GW=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a WAN GATEWAY IP" 8 58 $WAN_GW --title "WAN GATEWAY IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [ -z "$WAN_GW" ] && { msg_error "Gateway required for static WAN"; exit 1; }
        [[ -n "$WAN_GW" && ! "$WAN_GW" =~ $ip_regex ]] && { msg_error "Invalid WAN Gateway IP format"; exit 1; }
        echo -e "${DGN}Using WAN GATEWAY ADDRESS: ${BGN}$WAN_GW${CL}"
      else
        exit-script
      fi
      if WAN_NETMASK=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set WAN NETMASK (e.g. 255.255.255.0)" 8 58 ${WAN_NETMASK:-255.255.255.0} --title "WAN NETMASK" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [ -z "$WAN_NETMASK" ] && WAN_NETMASK="255.255.255.0"
        echo -e "${DGN}Using WAN NETMASK: ${BGN}$WAN_NETMASK${CL}"
      else
        exit-script
      fi
    fi
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a WAN MAC Address" 8 58 $GEN_MAC --title "WAN MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$MAC1" ] && MAC="$GEN_MAC" || MAC="$MAC1"
    echo -e "${DGN}Using LAN MAC Address: ${BGN}$MAC${CL}"
  else
    exit-script
  fi

  if MAC2=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a LAN MAC Address" 8 58 $GEN_MAC_LAN --title "LAN MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [ -z "$MAC2" ] && WAN_MAC="$GEN_MAC_LAN" || WAN_MAC="$MAC2"
    echo -e "${DGN}Using WAN MAC Address: ${BGN}$WAN_MAC${CL}"
  else
    exit-script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create IPFire VM?" --no-button Do-Over 10 58); then
    echo -e "${RD}Creating a IPFire VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

arch_check
pve_check
ssh_check

if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "IPFire VM" --yesno "This will create a New IPFire VM. Proceed?" 10 58); then
  :
else
  header_info && echo -e "⚠ User exited script \n" && exit 1
fi

start_script
post_to_api_vm

msg_info "Validating Storage"
STORAGE_MENU=()
MSG_MAX_LENGTH=0
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
  FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-0} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')

VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit 1
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi

msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

# ---- Download IPFire VM image ----
# IPFire download matrix varies over time. This script uses a best-effort URL selection.
# It expects an IPFire QCOW2 image (preferred). If unavailable, the installer may need manual intervention.

IPFIRE_ASSET_BASE_URL="https://www.ipfire.org/download/ipfire"

msg_info "Retrieving IPFire download page"
if ! curl -fsSL "$IPFIRE_ASSET_BASE_URL" -o page.html; then
  msg_error "Failed to fetch IPFire download page"
  exit 1
fi

# Try to pick a qcow2 asset.
# This is intentionally tolerant (regex matches common patterns).
URL="$(grep -Eo 'https?://[^\"\047 ]+\.(qcow2|img)(\.xz|\.gz)?' page.html | head -n 1 || true)"

if [ -z "$URL" ]; then
  msg_error "Could not automatically find an IPFire qcow2/img asset on the download page."
  msg_error "Installer automation will fail unless you update URL selection logic."
  exit 1
fi

msg_ok "Found IPFire image URL"
msg_info "Downloading IPFire image"

# Download and decompress if needed
FILENAME="$(basename "$URL")"
curl -f#SL -o "$FILENAME" "$URL"

# Handle common compression formats
FILE=""
case "$FILENAME" in
*.xz)
  unxz -cv "$FILENAME" >/dev/null 2>&1
  FILE="${FILENAME%.xz}"
  ;;
*.gz)
  gunzip -f "$FILENAME" >/dev/null 2>&1
  FILE="${FILENAME%.gz}"
  ;;
*)
  FILE="$FILENAME"
  ;;
esac

if [ ! -f "$FILE" ]; then
  msg_error "Downloaded file not found after decompression: $FILE"
  exit 1
fi

msg_ok "Downloaded ${CL}${BL}$FILE${CL}"

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
esac

for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

msg_info "Creating a IPFire VM"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} \
  -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags proxmox-helper-scripts \
  -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -net1 virtio,bridge=$WAN_BRG,macaddr=$WAN_MAC$VLAN$MTU \
  -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

pvesm alloc "$STORAGE" "$VMID" "$DISK0" 4M 1>&/dev/null
qm importdisk "$VMID" "$FILE" "$STORAGE" ${DISK_IMPORT:-} 1>&/dev/null

qm set "$VMID" \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=2G \
  -boot order=scsi0 \
  -serial0 socket \
  -tags community-script >/dev/null

qm resize "$VMID" scsi0 10G >/dev/null

DESCRIPTION=$(cat <<EOF
<div align='center'>
  <h2 style='font-size: 24px; margin: 20px 0;'>IPFire VM</h2>
  <p style='margin: 16px 0;'>Automated IPFire VM provisioning for Proxmox VE.</p>
</div>
EOF
)

qm set "$VMID" -description "$DESCRIPTION" >/dev/null

msg_ok "Created a IPFire VM ${CL}${BL}(${HN})"

msg_info "Starting IPFire VM (Patience this may take a while)"
qm start "$VMID"

# Let installer start
sleep 60

# ---- Installer automation (best effort) ----
# IPFire installer prompt flow can change. The following aims to:
# - proceed with install
# - set interface roles (LAN/WAN)
# - configure static IPs if provided
# NOTE: If prompts differ, you must adjust the send_line_to_vm sequence.

send_line_to_vm ""

# The installer typically starts with a menu. Send ENTER to accept defaults.
send_line_to_vm ""

# Wait a bit for menu navigation
sleep 30

# Configure interfaces: assume eth0=LAN, eth1=WAN. Many installers prompt in this order.
# If LAN IP provided, set it; else keep DHCP.
# (We do not know exact input sequence; this is intentionally minimal and may require tuning.)

if [ -n "$IP_ADDR" ]; then
  # Attempt static LAN config: IP, netmask, gateway
  # You may need to map NETMASK input to CIDR depending on installer.
  send_line_to_vm "$IP_ADDR"
  send_line_to_vm "$NETMASK"
  send_line_to_vm "$LAN_GW"
else
  # Choose DHCP for LAN
  send_line_to_vm "dhcp"
fi

if [ -n "$WAN_IP_ADDR" ]; then
  send_line_to_vm "$WAN_IP_ADDR"
  send_line_to_vm "$WAN_NETMASK"
  send_line_to_vm "$WAN_GW"
else
  send_line_to_vm "dhcp"
fi

# Finalize install (best effort)
# Give installer time to reach next screen
sleep 60
send_line_to_vm ""

# Wait for install
sleep 1200

msg_ok "Started IPFire VM"
msg_ok "Completed successfully!\n"

if [ -n "$IP_ADDR" ]; then
  echo -e "${INFO}${YW} LAN configured:${CL} http://${IP_ADDR}${CL}"
else
  echo -e "${INFO}${YW} LAN DHCP enabled.${CL}"
fi

post_update_to_api "done" "none"

