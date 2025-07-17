#!/bin/sh

# OpenWrt 19.07+ configuration
# Reference: https://openwrt.org/docs/guide-user/services/dns/adguard-home
#            https://github.com/AdguardTeam/AdGuardHome
# This script file can be used standalone.

SCRIPT_VERSION="2025.07.17-00-00"

# set -ex

REQUIRED_MEM="50" # unit: MB
REQUIRED_FLASH="100" # unit: MB
LAN="${LAN:-br-lan}"
NET_ADDR=""
NET_ADDR6=""
SERVICE_NAME=""
INSTALL_MODE=""
ARCH=""
AGH=""
PACKAGE_MANAGER=""

check_system() {
  printf "\033[1;34mChecking existing AdGuard Home installation\033[0m\n"
  if [ -x /etc/init.d/adguardhome ] || [ -x /etc/init.d/AdGuardHome ] || [ -x /usr/bin/adguardhome ]; then
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
    PACKAGE_MANAGER="unknown"
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

  printf "Memory: \033[1mFree %s MB\033[0m / Total %s MB\n" "$MEM_FREE_MB" "$MEM_TOTAL_MB"
  printf "Flash:  \033[1mFree %s MB\033[0m / Total %s MB\n" "$FLASH_FREE_MB" "$FLASH_TOTAL_MB"

  if [ "$MEM_FREE_MB" -lt "$REQUIRED_MEM" ]; then
    printf "Error: Insufficient memory. At least %sMB RAM is required.\n" "$REQUIRED_MEM"
    exit 1
  fi
  if [ "$FLASH_FREE_MB" -lt "$REQUIRED_FLASH" ]; then
    printf "Error: Insufficient flash storage. At least %sMB free space is required.\n" "$REQUIRED_FLASH"
    exit 1
  fi

  printf "Detected LAN interface: %s\n" "$LAN"
  printf "Package manager: %s\n" "$PACKAGE_MANAGER"
}

install_prompt() {
  printf "\033[1;32mSystem resources are sufficient for AdGuard Home installation. Proceeding with setup.\033[0m\n"

  if [ -n "$1" ]; then
    case "$1" in
      official) INSTALL_MODE="official"; return ;;
      openwrt) INSTALL_MODE="openwrt"; return ;;
      remove) remove_adguardhome; exit 0 ;;
      *) printf "\033[1;31mWarning: Unrecognized argument '$1'. Proceeding with interactive prompt.\033[0m\n" ;;
    esac
  fi

  while true; do
    printf "\033[1;34m  1) Install Official binary\033[0m\n"
    printf "\033[1;34m  2) Install OpenWrt package\033[0m\n"
    printf "Enter choice (1, 2): "
    read -r choice
    case "$choice" in
      1|official) INSTALL_MODE="official"; break ;;
      2|openwrt) INSTALL_MODE="openwrt"; break ;;
      *) printf "\033[1;31mInvalid choice '$choice'. Please enter 1 or 2.\033[0m\n" ;;
    esac
  done
}

install_cacertificates() {
  case "$PACKAGE_MANAGER" in
    apk)
      printf "\033[1;34mUpdating apk index…\033[0m\n"
      apk update
      printf "\033[1;34mInstalling ca-certificates…\033[0m\n"
      apk add ca-certificates
      ;;
    opkg)
      printf "\033[1;34mUpdating opkg index\033[0m\n"
      opkg update --verbosity=0
      printf "\033[1;34mInstalling ca-bundle\033[0m\n"
      opkg install --verbosity=0 ca-bundle
      ;;
    *)
      printf "\033[1;31mNo supported package manager (apk or opkg) found.\033[0m\n"
      exit 1
      ;;
  esac
}

install_openwrt() {
  printf "\033[1;34mInstalling AdGuard Home (OpenWrt package)\033[0m\n"
  case "$PACKAGE_MANAGER" in
    apk)
      apk add adguardhome || {
        printf "\033[1;31mapk add failed, falling back to official…\033[0m\n"
        return
      }
      ;;
    opkg)
      opkg install --verbosity=0 adguardhome || {
        printf "\033[1;31mopkg install failed, falling back to official…\033[0m\n"
        return
      }
      ;;
    *)
      install_official
      ;;
  esac
  SERVICE_NAME="adguardhome"
}

install_official() {

  VER=$(wget -q --no-check-certificate -O - https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest | jsonfilter -e '@.tag_name') 
  [ -n "$VER" ] || { printf "\033[1;31mError: Failed to get AdGuard Home version from GitHub API.\033[0m\n"; exit 1; }
  printf "\033[1;33mInstall Version: $VER\033[0m\n"

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
  URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${VER}/${TAR}"
  printf "\033[1;34mDownloading ${TAR}\033[0m\n"
  if ! wget -q --no-check-certificate -O "/etc/AdGuardHome/${TAR}" "$URL"; then
    printf "\033[1;31mDownload failed. Please check network connection.\033[0m\n"
    exit 1
  fi
  tar -C /etc/ -xzf "/etc/AdGuardHome/${TAR}"
  rm "/etc/AdGuardHome/${TAR}"
  chmod +x /etc/AdGuardHome/AdGuardHome
  SERVICE_NAME="AdGuardHome"
}

get_iface_addrs() {
# To support IPv6 tunnel environments such as MAP-E and DS-Lite, Global Unicast Addresses (2000::/3) are also included as DNS advertisement targets.
# For enhanced security, exclude link-local and temporary addresses by matching only ULA (fd|fc) and GUA (2000::/3) scopes.
  NET_ADDR=$(ip -o -4 addr list "$LAN" | awk 'NR==1{split($4,a,"/");print a[1];exit}')
  NET_ADDR6=$(ip -o -6 addr list "$LAN" scope global | awk 'match($4,/^(fd|fc|2)/){split($4,a,"/");print a[1];exit}')
# NET_ADDR=$(/sbin/ip -o -4 addr list "$LAN" | awk 'NR==1{ split($4, ip_addr, "/"); print ip_addr[1]; exit }')
# NET_ADDR6=$(/sbin/ip -o -6 addr list "$LAN" scope global | awk '$4 ~ /^fd|^fc/ { split($4, ip_addr, "/"); print ip_addr[1]; exit }')
}

common_config_firewall() {
  printf "\033[1;34mConfiguring firewall rules for AdGuard Home\033[0m\n"
  
  uci -q delete firewall.adguardhome_dns_53 || true

  if command -v nft >/dev/null 2>&1; then
    nft list table ip nat > /dev/null 2>&1 || nft add table ip nat
    nft list chain ip nat prerouting > /dev/null 2>&1 || nft add chain ip nat prerouting '{ type nat hook prerouting priority -100; policy accept; }'
    nft list table ip6 nat > /dev/null 2>&1 || nft add table ip6 nat
    nft list chain ip6 nat prerouting > /dev/null 2>&1 || nft add chain ip6 nat prerouting '{ type nat hook prerouting priority -100; policy accept; }'

    for proto in udp tcp; do
      if ! nft list chain ip nat prerouting 2>/dev/null | grep -qF "iifname \"${LAN}\" ${proto} dport 53 dnat to ${NET_ADDR}:53"; then
        nft add rule ip nat prerouting iifname "${LAN}" ${proto} dport 53 dnat to ${NET_ADDR}:53
      fi
      if ! nft list chain ip6 nat prerouting 2>/dev/null | grep -qF "iifname \"${LAN}\" ${proto} dport 53 dnat to ${NET_ADDR6}:53"; then
        nft add rule ip6 nat prerouting iifname "${LAN}" ${proto} dport 53 dnat to ${NET_ADDR6}:53
      fi
    done

    nft list ruleset > /etc/nftables.conf
  else
    uci set firewall.adguardhome_dns_53=redirect
    uci set firewall.adguardhome_dns_53.name='AdGuardHome DNS 53'
    uci set firewall.adguardhome_dns_53.src='lan'
    uci add_list firewall.adguardhome_dns_53.proto='tcp'
    uci add_list firewall.adguardhome_dns_53.proto='udp'
    uci set firewall.adguardhome_dns_53.src_dport='53'
    uci set firewall.adguardhome_dns_53.dest='lan'
    uci set firewall.adguardhome_dns_53.dest_ip="${NET_ADDR}"
    uci set firewall.adguardhome_dns_53.dest_port='53'
    uci set firewall.adguardhome_dns_53.target='DNAT'
    uci commit firewall
  fi

  /etc/init.d/firewall restart || {
    printf "\033[1;31mFailed to restart firewall\033[0m\n"
    exit 1
  }
}

common_config() {
  printf "\033[1;34mBacking up configuration files\033[0m\n"
  cp /etc/config/network /etc/config/network.adguard.bak
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
  
  printf "Router IPv4 : %s\n" "${NET_ADDR}"
  printf "Router IPv6 : %s\n" "${NET_ADDR6}"
  
  uci set dhcp.@dnsmasq[0].noresolv="1"
  uci set dhcp.@dnsmasq[0].cachesize="0"
  uci set dhcp.@dnsmasq[0].rebind_protection='0'
  uci set dhcp.@dnsmasq[0].port="54"
  uci set dhcp.@dnsmasq[0].domain="lan"
  uci set dhcp.@dnsmasq[0].local="/lan/"
  uci set dhcp.@dnsmasq[0].expandhosts="1"
  uci -q del dhcp.@dnsmasq[0].server || true
  uci add_list dhcp.@dnsmasq[0].server="${NET_ADDR}"
  uci -q del dhcp.lan.dhcp_option || true
  uci -q del dhcp.lan.dns || true
  uci add_list dhcp.lan.dhcp_option='3,'"${NET_ADDR}"
  uci add_list dhcp.lan.dhcp_option='6,'"${NET_ADDR}"
  uci add_list dhcp.lan.dhcp_option='15',"lan"

# To support IPv6 tunnel environments such as MAP-E and DS-Lite, Global Unicast Addresses (2000::/3) are also included as DNS advertisement targets.
# For enhanced security, exclude link-local and temporary addresses by matching only ULA (fd|fc) and GUA (2000::/3) scopes.
for OUTPUT in $(ip -o -6 addr list br-lan scope global | awk 'match($4,/^(fd|fc|2)/){split($4,a,"/");print a[1]}'); do
    printf "Adding %s to IPV6 DNS\n" "$OUTPUT"
    uci add_list dhcp.lan.dns="$OUTPUT"
done
# for OUTPUT in $(ip -o -6 addr list br-lan scope global | awk '$4 ~ /^fd|^fc|^2/ { split($4, ip_addr, "/"); print ip_addr[1] }'); do
#     printf "Adding %s to IPV6 DNS\n" "$OUTPUT"
#     uci add_list dhcp.lan.dns="$OUTPUT"
# done
  
  uci commit dhcp
  /etc/init.d/dnsmasq restart || {
    printf "\033[1;31mFailed to restart dnsmasq\033[0m\n"
    exit 1
  }
  /etc/init.d/odhcpd restart || {
    printf "\033[1;31mFailed to restart odhcpd\033[0m\n"
    exit 1
  }
}

remove_adguardhome() {
  printf "\033[1;34mRemoving AdGuard Home\033[0m\n"

  if [ -x /etc/AdGuardHome/AdGuardHome ]; then
    INSTALL_TYPE="official"
    AGH="AdGuardHome"
  elif [ -x /usr/bin/adguardhome ]; then
    INSTALL_TYPE="openwrt"
    AGH="adguardhome"
  else
    printf "\033[1;31mAdGuard Home not found\033[0m\n"
    return 1
  fi

  printf "Found AdGuard Home (%s version)\n" "$INSTALL_TYPE"
  printf "Do you want to remove it? (y/N): "
  read -r confirm
  case "$confirm" in
    [yY]|[yY][eE][sS]) ;;
    *)  
      printf "\033[1;33mCancelled\033[0m\n"
      return 0
      ;;
  esac

  /etc/init.d/"${AGH}" stop 2>/dev/null || true
  /etc/init.d/"${AGH}" disable 2>/dev/null || true

  if [ "$INSTALL_TYPE" = "official" ]; then
    "/etc/${AGH}/${AGH}" -s uninstall 2>/dev/null || true
  else
    if command -v apk >/dev/null 2>&1; then
      apk del "$AGH" 2>/dev/null || true
    elif command -v opkg >/dev/null 2>&1; then
      opkg remove --verbosity=0 "$AGH" 2>/dev/null || true
    fi
  fi

  if [ -d "/etc/${AGH}" ]; then
    printf "Do you want to remove configuration directory /etc/${AGH}? (y/N): "
    read -r config_confirm
    case "$config_confirm" in
      [yY]|[yY][eE][sS])
        rm -rf "/etc/${AGH}"
        ;;
      *)
        printf "\033[1;33mConfiguration directory preserved.\033[0m\n"
        ;;
    esac
  fi

  for config_file in network dhcp firewall; do
    backup_file="/etc/config/${config_file}.adguard.bak"
    if [ -f "$backup_file" ]; then
      printf "\033[1;34mRestoring ${config_file} configuration\033[0m\n"
      cp "$backup_file" "/etc/config/${config_file}"
      rm "$backup_file"
    fi
  done

  if uci -q get dhcp.@dnsmasq[0].port >/dev/null 2>&1; then
    if [ "$(uci -q get dhcp.@dnsmasq[0].port)" != "53" ]; then
      printf "\033[1;34mRestoring dnsmasq port to 53\033[0m\n"
      uci set dhcp.@dnsmasq[0].port='53'
      uci commit dhcp
    fi
  fi

  uci -q delete firewall.adguardhome_dns_53 2>/dev/null || true

  if command -v nft >/dev/null 2>&1; then

    get_iface_addrs
  
    for proto in udp tcp; do
      nft delete rule ip  nat prerouting iifname "${LAN}" ${proto} dport 53 dnat to ${NET_ADDR}:53 2>/dev/null || true
      nft delete rule ip6 nat prerouting iifname "${LAN}" ${proto} dport 53 dnat to ${NET_ADDR6}:53 2>/dev/null || true
    done

    if ! nft list chain ip  nat prerouting 2>/dev/null | grep -q 'dport 53'; then
      nft delete chain ip  nat prerouting 2>/dev/null || true
      nft delete table ip  nat 2>/dev/null || true
    fi
    if ! nft list chain ip6 nat prerouting 2>/dev/null | grep -q 'dport 53'; then
      nft delete chain ip6 nat prerouting 2>/dev/null || true
      nft delete table ip6 nat 2>/dev/null || true
    fi
    nft list ruleset > /etc/nftables.conf || true
  fi

  uci commit firewall

  /etc/init.d/dnsmasq restart || {
    printf "\033[1;31mFailed to restart dnsmasq\033[0m\n"
    exit 1
  }
  /etc/init.d/odhcpd restart || {
    printf "\033[1;31mFailed to restart odhcpd\033[0m\n"
    exit 1
  }
  /etc/init.d/firewall restart || {
    printf "\033[1;31mFailed to restart firewall\033[0m\n"
    exit 1
  }

  printf "\033[1;32mAdGuard Home has been removed successfully.\033[0m\n"
  printf "\033[33mPress any key to reboot your device.\033[0m\n"
  read -r -n1 -s
  reboot
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
  printf "\033[1;34mAccess UI 👉    http://${NET_ADDR}:3000/\033[0m\n"
}

# adguardhome_main "$@"
