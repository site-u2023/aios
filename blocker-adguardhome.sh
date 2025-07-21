#!/bin/sh

# OpenWrt 19.07+ configuration
# Reference: https://openwrt.org/docs/guide-user/services/dns/adguard-home
#            https://github.com/AdguardTeam/AdGuardHome
# This script file can be used standalone.

SCRIPT_VERSION="2025.07.21-00-00"

# set -ex

REQUIRED_MEM="50" # unit: MB
REQUIRED_FLASH="100" # unit: MB
LAN="${LAN:-br-lan}"
DNS_PORT="${DNS_PORT:-53}"

NET_ADDR=""
NET_ADDR6_LIST=""
SERVICE_NAME=""
INSTALL_MODE=""
ARCH=""
AGH=""
PACKAGE_MANAGER=""
FAMILY_TYPE=""

check_system() {
  printf "\033[1;34mChecking existing AdGuard Home installation\033[0m\n"
  if /etc/AdGuardHome/AdGuardHome -v >/dev/null 2>&1 || opkg list-installed adguardhome >/dev/null 2>&1; then
    printf "\033[1;33mAdGuard Home is already installed. Exiting.\033[0m\n"
    remove_adguardhome
    exit 0
  fi
  
  printf "\033[1;34mChecking LAN interface\033[0m\n"
  LAN="$(ubus call network.interface.lan status 2>/dev/null | jsonfilter -e '@.l3_device')"
  if [ -z "$LAN" ]; then
    printf "\033[1;31mLAN interface not found. Aborting.\033[0m\n"
    exit 1
  fi

  printf "\033[1;34mChecking package manager\033[0m\n"
  if command -v opkg >/dev/null 2>&1; then
    PACKAGE_MANAGER="opkg"
  elif command -v apk >/dev/null 2>&1; then
    PACKAGE_MANAGER="apk"
  else
    printf "\033[1;31mNo supported package manager (apk or opkg) found.\033[0m\n"
    printf "\033[1;31mThis script is designed for OpenWrt systems only.\033[0m\n"
    exit 1
  fi

  printf "\033[1;34mChecking system memory and flash storage\033[0m\n"
  MEM_TOTAL_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  MEM_FREE_KB=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  BUFFERS_KB=$(awk '/^Buffers:/ {print $2}' /proc/meminfo)
  CACHED_KB=$(awk '/^Cached:/ {print $2}' /proc/meminfo)

  if [ -n "$MEM_FREE_KB" ]; then
    MEM_FREE_MB=$((MEM_FREE_KB / 1024))
  else
    MEM_FREE_MB=$(((BUFFERS_KB + CACHED_KB) / 1024))
  fi
  MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))

  DF_OUT=$(df -k / | awk 'NR==2 {print $2, $4}')
  FLASH_TOTAL_KB=$(printf '%s\n' "$DF_OUT" | awk '{print $1}')
  FLASH_FREE_KB=$(printf '%s\n' "$DF_OUT" | awk '{print $2}')
  FLASH_FREE_MB=$((FLASH_FREE_KB / 1024))
  FLASH_TOTAL_MB=$((FLASH_TOTAL_KB / 1024))

  if [ "$MEM_FREE_MB" -lt "$REQUIRED_MEM" ]; then
    mem_col=31
  else
    mem_col=32
  fi
  if [ "$FLASH_FREE_MB" -lt "$REQUIRED_FLASH" ]; then
    flash_col=31
  else
    flash_col=32
  fi

  printf "Memory: Free \033[%sm%s MB\033[0m / Total %s MB\n" \
    "$mem_col" "$MEM_FREE_MB" "$MEM_TOTAL_MB"
  printf "Flash:  Free \033[%sm%s MB\033[0m / Total %s MB\n" \
    "$flash_col" "$FLASH_FREE_MB" "$FLASH_TOTAL_MB"

  if [ "$MEM_FREE_MB" -lt "$REQUIRED_MEM" ]; then
    printf "\033[1;31mError: Insufficient memory. At least %sMB RAM is required.\033[0m\n" \
      "$REQUIRED_MEM"
    exit 1
  fi
  if [ "$FLASH_FREE_MB" -lt "$REQUIRED_FLASH" ]; then
    printf "\033[1;31mError: Insufficient flash storage. At least %sMB free space is required.\033[0m\n" \
      "$REQUIRED_FLASH"
    exit 1
  fi

  printf "\033[1;34mDetected LAN interface:\033[0m %s\n" "$LAN"
  printf "\033[1;34mPackage manager:\033[0m %s\n" "$PACKAGE_MANAGER"
}

install_prompt() {
  printf "\033[1;32mSystem resources are sufficient for AdGuard Home installation. Proceeding with setup.\033[0m\n"

  if [ -n "$1" ]; then
    case "$1" in
      official) INSTALL_MODE="official"; return ;;
      openwrt) INSTALL_MODE="openwrt"; return ;;
      remove) remove_adguardhome ;;
      exit) exit 0 ;;
      *) printf "\033[1;31mWarning: Unrecognized argument '$1'. Proceeding with interactive prompt.\033[0m\n" ;;
    esac
  fi

  while true; do
    printf "[1] Install Official binary\n"
    printf "[2] Install OpenWrt package\n"
    printf "[0] Exit\n"
    printf "Please select (1, 2 or 0): "
    read -r choice
    
    case "$choice" in
      1|official) INSTALL_MODE="official"; break ;;
      2|openwrt) INSTALL_MODE="openwrt"; break ;;
      0|exit) 
        printf "\033[1;33mInstallation cancelled.\033[0m\n"
        exit 0 
        ;;
      *) printf "\033[1;31mInvalid choice '$choice'. Please enter 1, 2, or 0.\033[0m\n" ;;
    esac
  done
}

install_cacertificates() {
  case "$PACKAGE_MANAGER" in
    apk)
      printf "\033[1;34mUpdating apk index窶ｦ\033[0m\n"
      apk update
      printf "\033[1;34mInstalling ca-certificates窶ｦ\033[0m\n"
      apk add ca-certificates
      ;;
    opkg)
      printf "\033[1;34mUpdating opkg index\033[0m\n"
      opkg update --verbosity=0
      printf "\033[1;34mInstalling ca-bundle\033[0m\n"
      opkg install --verbosity=0 ca-bundle
      ;;
  esac
}

install_openwrt() {
  printf "\033[1;34mInstalling AdGuard Home (OpenWrt package)\033[0m\n"
  
  case "$PACKAGE_MANAGER" in
    apk)
      if apk search adguardhome | grep -q "^adguardhome-"; then
        apk add adguardhome || {
          printf "\033[1;31mNetwork error during apk add. Aborting.\033[0m\n"
          exit 1
        }
      else
        printf "\033[1;31mPackage 'adguardhome' not found in apk repository, falling back to official窶ｦ\033[0m\n"
        install_official
      fi
      ;;
    opkg)
      if opkg list | grep -q "^adguardhome "; then
        opkg install --verbosity=0 adguardhome || {
          printf "\033[1;31mNetwork error during opkg install. Aborting.\033[0m\n"
          exit 1
        }
      else
        printf "\033[1;31mPackage 'adguardhome' not found in opkg repository, falling back to official窶ｦ\033[0m\n"
        install_official
      fi
      ;;
  esac
  
  SERVICE_NAME="adguardhome"
}

install_official() {
  CA="--no-check-certificate"
  URL="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest"
  VER=$( { wget -q -O - "$URL" || wget -q "$CA" -O - "$URL"; } | jsonfilter -e '@.tag_name' )
  [ -n "$VER" ] || { printf "\033[1;31mError: Failed to get AdGuard Home version from GitHub API.\033[0m\n"; exit 1; }
  printf "\033[1;33mInstall Version: %s\033[0m\n" "$VER"
  
  mkdir -p /etc/AdGuardHome

  case "$(uname -m)" in
    aarch64|arm64) ARCH=arm64 ;;
    armv7l)        ARCH=armv7 ;;
    armv6l)        ARCH=armv6 ;;
    armv5l)        ARCH=armv5 ;;
    x86_64|amd64)  ARCH=amd64 ;;
    i386|i686)     ARCH=386 ;;
    mips)          ARCH=mipsle ;;
    mips64)        ARCH=mips64le ;;
    *) printf "Unsupported arch: %s\n" "$(uname -m)"; exit 1 ;;
  esac

  TAR="AdGuardHome_linux_${ARCH}.tar.gz"
  URL2="https://github.com/AdguardTeam/AdGuardHome/releases/download/${VER}/${TAR}"
  DEST="/etc/AdGuardHome/${TAR}"
  printf '\033[1;34mDownloading %s\033[0m\n' "$TAR"
  if ! { wget -q -O "$DEST" "$URL2" || wget -q "$CA" -O "$DEST" "$URL2"; }; then
    printf '\033[1;31mDownload failed. Please check network connection.\033[0m\n'
    exit 1
  fi
  tar -C /etc/ -xzf "/etc/AdGuardHome/${TAR}"
  rm "/etc/AdGuardHome/${TAR}"
  chmod +x /etc/AdGuardHome/AdGuardHome
  
  SERVICE_NAME="AdGuardHome"
}

get_iface_addrs() {
  local flag=0
  
  if ip -4 -o addr show dev "$LAN" scope global | grep -q 'inet '; then
    NET_ADDR=$(ip -4 -o addr show dev "$LAN" scope global | awk 'NR==1{sub(/\/.*/,"",$4); print $4}')
    flag=$((flag | 1))
  else
    printf "\033[1;33mWarning: No IPv4 address on %s\033[0m\n" "$LAN"
  fi

  if ip -6 -o addr show dev "$LAN" scope global | grep -q 'inet6 '; then
    NET_ADDR6_LIST=$(ip -6 -o addr show dev "$LAN" scope global | grep -v temporary | awk 'match($4,/^(2|fd|fc)/){sub(/\/.*/,"",$4); print $4;}')
    flag=$((flag | 2))
  else
    printf "\033[1;33mWarning: No IPv6 address on %s\033[0m\n" "$LAN"
  fi

  case $flag in
    3) FAMILY_TYPE=any  ;;
    1) FAMILY_TYPE=ipv4 ;;
    2) FAMILY_TYPE=ipv6 ;;
    *) FAMILY_TYPE=""   ;;
  esac
}

common_config() {
  printf "\033[1;34mBacking up configuration files\033[0m\n"
  cp /etc/config/network  /etc/config/network.adguard.bak
  cp /etc/config/dhcp     /etc/config/dhcp.adguard.bak
  cp /etc/config/firewall /etc/config/firewall.adguard.bak

  [ "$INSTALL_MODE" = "official" ] && {
    /etc/AdGuardHome/AdGuardHome -s install >/dev/null 2>&1 || {
      printf "\033[1;31mInitialization failed. Check AdGuardHome.yaml and port availability.\033[0m\n"
      exit 1
    }
  }

  chmod 700 /etc/"$SERVICE_NAME"
  /etc/init.d/"$SERVICE_NAME" enable
  /etc/init.d/"$SERVICE_NAME" start

  uci set dhcp.@dnsmasq[0].noresolv="1"
  uci set dhcp.@dnsmasq[0].cachesize="0"
  uci set dhcp.@dnsmasq[0].rebind_protection='0'

  # uci set dhcp.@dnsmasq[0].rebind_protection='1'  # keep enabled
  # uci set dhcp.@dnsmasq[0].rebind_localhost='1'   # protect localhost
  # uci add_list dhcp.@dnsmasq[0].rebind_domain='lan'  # allow internal domain

  uci set dhcp.@dnsmasq[0].port="54"
  uci set dhcp.@dnsmasq[0].domain="lan"
  uci set dhcp.@dnsmasq[0].local="/lan/"
  uci set dhcp.@dnsmasq[0].expandhosts="1"

  uci -q del dhcp.@dnsmasq[0].server || true
  uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${DNS_PORT}"
  uci add_list dhcp.@dnsmasq[0].server="::1#${DNS_PORT}"

  uci -q del dhcp.lan.dhcp_option || true
  uci add_list dhcp.lan.dhcp_option="6,${NET_ADDR}"

  uci -q del dhcp.lan.dhcp_option6 || true
  if [ -n "$NET_ADDR6_LIST" ]; then
    for ip in $NET_ADDR6_LIST; do
      uci add_list dhcp.lan.dhcp_option6="option6:dns=[${ip}]"
    done
  fi

  uci commit dhcp
  /etc/init.d/dnsmasq restart || {
    printf "\033[1;31mFailed to restart dnsmasq\033[0m\n"
    printf "\033[1;31mCritical error: Auto-removing AdGuard Home and rebooting in 10 seconds (Ctrl+C to cancel)\033[0m\n"
    sleep 10
    remove_adguardhome "auto"
    reboot
    exit 1
  }
  /etc/init.d/odhcpd restart || {
    printf "\033[1;31mFailed to restart odhcpd\033[0m\n"
    printf "\033[1;31mCritical error: Auto-removing AdGuard Home and rebooting in 10 seconds (Ctrl+C to cancel)\033[0m\n"
    sleep 10
    remove_adguardhome "auto"
    reboot
    exit 1
  }

  printf "\033[1;32mRouter IPv4: %s\033[0m\n" "$NET_ADDR"
  
  if [ -z "$NET_ADDR6_LIST" ]; then
    printf "\033[1;33mRouter IPv6: none found\033[0m\n"
  else
    first_ip=true
    for ip in $NET_ADDR6_LIST; do
      if $first_ip; then
        printf "\033[1;32mRouter IPv6: %s\033[0m\n" "$ip"
        first_ip=false
      else
        printf "\033[1;32mRouter IPv6: %s\033[0m\n" "$ip"
      fi
    done
  fi
}

common_config_firewall() {
  printf "\033[1;34mConfiguring firewall rules for AdGuard Home\033[0m\n"

  rule_name="adguardhome_dns_${DNS_PORT}"
  uci -q delete firewall."$rule_name" || true

  if [ -z "$FAMILY_TYPE" ]; then
    printf "\033[1;31mNo valid IP address family detected. Skipping firewall rule setup.\033[0m\n"
    return
  fi

  uci set firewall."$rule_name"=redirect
  uci set firewall."$rule_name".name="AdGuardHome DNS Redirect (${FAMILY_TYPE})"
  uci set firewall."$rule_name".family="$FAMILY_TYPE"
  uci set firewall."$rule_name".src="lan"
  uci set firewall."$rule_name".dest="lan"
  uci add_list firewall."$rule_name".proto="tcp"
  uci add_list firewall."$rule_name".proto="udp"
  uci set firewall."$rule_name".src_dport="$DNS_PORT"
  uci set firewall."$rule_name".dest_port="$DNS_PORT"
  uci set firewall."$rule_name".target="DNAT"

  uci commit firewall
  /etc/init.d/firewall restart || {
    printf "\033[1;31mFailed to restart firewall\033[0m\n"
    printf "\033[1;31mCritical error: Auto-removing AdGuard Home and rebooting in 10 seconds (Ctrl+C to cancel)\033[0m\n"
    sleep 10
    remove_adguardhome "auto"
    reboot
    exit 1
  }
}

remove_adguardhome() {
  local auto_confirm="$1"

  printf "\033[1;34mRemoving AdGuard Home\033[0m\n"

  if /etc/AdGuardHome/AdGuardHome -v >/dev/null 2>&1; then
    INSTALL_TYPE="official"; AGH="AdGuardHome"
  elif opkg list-installed adguardhome >/dev/null 2>&1; then
    INSTALL_TYPE="openwrt"; AGH="adguardhome"
  else
    printf "\033[1;31mAdGuard Home not found\033[0m\n"
    return 1
  fi

  printf "Found AdGuard Home (%s version)\n" "$INSTALL_TYPE"

  if [ "$auto_confirm" != "auto" ]; then
    printf "Do you want to remove it? (y/N): "
    read -r confirm
    case "$confirm" in
      [yY]|[yY][eE][sS]) ;;
      *) printf "\033[1;33mCancelled\033[0m\n"; return 0 ;;
    esac
  else
    printf "\033[1;33mAuto-removing due to installation error\033[0m\n"
  fi

  /etc/init.d/"${AGH}" stop    2>/dev/null || true
  /etc/init.d/"${AGH}" disable 2>/dev/null || true

  if [ "$INSTALL_TYPE" = "official" ]; then
    "/etc/${AGH}/${AGH}" -s uninstall 2>/dev/null || true
  else
    if command -v apk >/dev/null 2>&1; then
      apk del "$AGH" 2>/dev/null || true
    else
      opkg remove --verbosity=0 "$AGH" 2>/dev/null || true
    fi
  fi

  if [ -d "/etc/${AGH}" ]; then
    if [ "$auto_confirm" != "auto" ]; then
      printf "Remove /etc/%s directory? (y/N): " "$AGH"
      read -r cfg; case "$cfg" in [yY]*) rm -rf "/etc/${AGH}" ;; esac
    else
      rm -rf "/etc/${AGH}"
    fi
  fi

  for cfg in network dhcp firewall; do
    bak="/etc/config/${cfg}.adguard.bak"
    if [ -f "$bak" ]; then
      printf "\033[1;34mRestoring %s configuration\033[0m\n" "$cfg"
      cp "$bak" "/etc/config/${cfg}"
      rm -f "$bak"
    fi
  done

  uci commit network
  uci commit dhcp
  uci commit firewall

  /etc/init.d/dnsmasq restart  || { printf "\033[1;31mFailed to restart dnsmasq\033[0m\n"; exit 1; }
  /etc/init.d/odhcpd restart   || { printf "\033[1;31mFailed to restart odhcpd\033[0m\n"; exit 1; }
  /etc/init.d/firewall restart || { printf "\033[1;31mFailed to restart firewall\033[0m\n"; exit 1; }

  printf "\033[1;32mAdGuard Home has been removed successfully.\033[0m\n"

  if [ "$auto_confirm" != "auto" ]; then
    printf "\033[33mPress any key to reboot.\033[0m\n"
    read -r -n1 -s
    reboot
  else
    printf "\033[1;33mAuto-rebooting\033[0m\n"
    reboot
  fi

  exit 0
}

adguardhome_main() {
  check_system
  install_prompt "$@"
  install_cacertificates
  install_"$INSTALL_MODE"
  get_iface_addrs
  common_config
  common_config_firewall

  printf "\033[1;34mAccess UI v4 address 👉    http://${NET_ADDR}:3000/\033[0m\n"
  if [ -n "$NET_ADDR6_LIST" ]; then
    set -- $NET_ADDR6_LIST
    printf "\033[1;34mAccess UI v6 address 👉    http://%s:3000/\033[0m\n" "$1"  
  fi
}

# adguardhome_main "$@"
