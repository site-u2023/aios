#!/bin/sh

# OpenWrt 19.07+ configuration
# Reference: https://ipv4.web.fc2.com/map-e.html
# This script file can be used standalone.

# set -ex

SCRIPT_VERSION="2025.06.21-00-00"

LAN_IPADDR="192.168.1.1"
LAN_DEF="br-lan" 
WAN_DEF="wan"
LAN_NAME="lan"
WAN_NAME="wan"
WAN6_NAME="wan6"
WANMAP_NAME="wanmap"
WANMAP6_NAME="wanmap6"

BR=""
IPV4_NET_PREFIX=""
IP4PREFIXLEN=""
IPADDR=""
IPV6_RULE_PREFIX=""
IPV6_RULE_PREFIXLEN=""
EALEN=""
PSIDLEN=""
OFFSET=""
PSID=""
CE=""
MTU="1460"
LEGACYMAP="1"
USER_IPV6_ADDR=""
USER_IPV6_HEXTETS=""
USER_IPV6_PREFIX=""
WAN6_PREFIX=""
OS_VERSION="" 
API_RESPONSE=""

initialize_info() {
    if [ -n "$USER_IPV6_ADDR" ]; then
        USER_IPV6_PREFIX=$(echo "$USER_IPV6_ADDR" | awk -F'[/:]' '{printf "%s:%s:%s:%s::", $1, $2, $3, $4}')
        return 0
    fi
    
    if [ -f "/etc/openwrt_release" ]; then
        OS_VERSION=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d"'" -f2)
    fi

    if . /lib/functions.sh && . /lib/functions/network.sh; then
        network_flush_cache
        network_find_wan6 NET_IF6
    else
        return 1
    fi

    local ipv6_addr=""
    if network_get_ipaddr6 NET_ADDR6 "$NET_IF6" && [ -n "$NET_ADDR6" ]; then
        ipv6_addr="$NET_ADDR6"
        WAN6_PREFIX="$(echo "$NET_ADDR6" | awk -F'[/:]' '{printf "%s:%s:%s:%s::/64", $1, $2, $3, $4}')"
    elif network_get_prefix6 NET_PFX6 "$NET_IF6" && [ -n "$NET_PFX6" ]; then
        ipv6_addr="$NET_PFX6"
    else
        return 1
    fi
    USER_IPV6_ADDR="$ipv6_addr"
    USER_IPV6_PREFIX=$(echo "$ipv6_addr" | awk -F'[/:]' '{printf "%s:%s:%s:%s::", $1, $2, $3, $4}')

    if command -v /etc/init.d/sysntpd >/dev/null 2>&1; then
        /etc/init.d/sysntpd restart >/dev/null 2>&1
        sleep 5
    fi
    
    return 0
}

fetch_rule_api() {
    [ -z "$USER_IPV6_ADDR" ] || [ -z "$USER_IPV6_PREFIX" ] && return 1
    
    API_RESPONSE=$(wget -q -O - --timeout=10 "https://map-api-worker.site-u.workers.dev/map-rule?user_prefix=${USER_IPV6_PREFIX}")
    
    [ -z "$API_RESPONSE" ] && return 1 || return 0
}

get_rule_api() {
    local api_response="$API_RESPONSE"

    BR=""; EALEN=""; IPV4_NET_PREFIX=""; IP4PREFIXLEN=""; IPV6_RULE_PREFIX=""; IPV6_RULE_PREFIXLEN=""; OFFSET=""

    [ -z "$api_response" ] && return 1

    BR=$(echo "$api_response" | jsonfilter -e '@.brIpv6Address')
    EALEN=$(echo "$api_response" | jsonfilter -e '@.eaBitLength')
    IPV4_NET_PREFIX=$(echo "$api_response" | jsonfilter -e '@.ipv4Prefix')
    IP4PREFIXLEN=$(echo "$api_response" | jsonfilter -e '@.ipv4PrefixLength')
    IPV6_RULE_PREFIX=$(echo "$api_response" | jsonfilter -e '@.ipv6Prefix')
    IPV6_RULE_PREFIXLEN=$(echo "$api_response" | jsonfilter -e '@.ipv6PrefixLength')
    OFFSET=$(echo "$api_response" | jsonfilter -e '@.psIdOffset')

    [ -z "$BR" ] || [ -z "$EALEN" ] || [ -z "$IPV4_NET_PREFIX" ] || [ -z "$IP4PREFIXLEN" ] || [ -z "$IPV6_RULE_PREFIX" ] || [ -z "$IPV6_RULE_PREFIXLEN" ] || [ -z "$OFFSET" ] && return 1

    return 0
}

parse_user_ipv6() {
    local ipv6_to_parse="$1"
    [ -z "$ipv6_to_parse" ] && { USER_IPV6_HEXTETS=""; return 1; }
    
    ipv6_to_parse=${ipv6_to_parse%/*}
    
    if [ "${ipv6_to_parse}" != "${ipv6_to_parse#*::}" ]; then
        local before="${ipv6_to_parse%::*}"
        local after="${ipv6_to_parse#*::}"
        [ "$before" = "$ipv6_to_parse" ] && before=""
        [ "$after" = "$ipv6_to_parse" ] && after=""
        
        local before_count=0 after_count=0
        if [ -n "$before" ]; then
            before_count=1
            local temp="$before"
            while [ "${temp#*:}" != "$temp" ]; do
                before_count=$((before_count + 1))
                temp="${temp#*:}"
            done
        fi
        if [ -n "$after" ]; then
            after_count=1
            local temp="$after"
            while [ "${temp#*:}" != "$temp" ]; do
                after_count=$((after_count + 1))
                temp="${temp#*:}"
            done
        fi
        
        local zero_count=$((8 - before_count - after_count))
        local zeros=""
        while [ $((zero_count -= 1)) -ge 0 ]; do
            zeros="$zeros:0"
        done
        
        ipv6_to_parse="$before$zeros"
        [ -n "$after" ] && ipv6_to_parse="$ipv6_to_parse:$after"
        ipv6_to_parse=${ipv6_to_parse#:}
    fi
    
    USER_IPV6_HEXTETS=""
    local IFS=':'
    set -- $ipv6_to_parse
    
    [ $# -ne 8 ] && { USER_IPV6_HEXTETS=""; return 1; }
    
    for segment in "$@"; do
        segment="0000$segment"
        segment=${segment#${segment%????}}
        USER_IPV6_HEXTETS="$USER_IPV6_HEXTETS$segment "
    done
    
    USER_IPV6_HEXTETS=${USER_IPV6_HEXTETS% }
    return 0
}

calculate_mape_params() {
    [ -z "$USER_IPV6_HEXTETS" ] && return 1
    [ -z "$EALEN" ] || [ -z "$IPV4_NET_PREFIX" ] || [ -z "$IP4PREFIXLEN" ] || [ -z "$OFFSET" ] || [ -z "$IPV6_RULE_PREFIXLEN" ] && return 1

    set -- $USER_IPV6_HEXTETS
    local h0_val=$((0x${1:-0})) h1_val=$((0x${2:-0})) h2_val=$((0x${3:-0})) h3_val=$((0x${4:-0}))

    local ealen_num=$((EALEN)) rule_prefixlen_num=$((IPV6_RULE_PREFIXLEN)) ip4prefixlen_num=$((IP4PREFIXLEN))
    local ea_bits_end_offset=$((64 - rule_prefixlen_num - ealen_num))
    [ "$ea_bits_end_offset" -lt 0 ] && return 1

    local user_ipv6_first64bits=$(( (h0_val << 48) | (h1_val << 32) | (h2_val << 16) | h3_val ))
    local ea_bits=$(( (user_ipv6_first64bits >> ea_bits_end_offset) & ((1 << ealen_num) - 1) ))

    local ipv4_suffix_len_num=$((32 - ip4prefixlen_num))
    [ "$ipv4_suffix_len_num" -lt 0 ] && return 1

    PSIDLEN=$((ealen_num - ipv4_suffix_len_num))
    [ "$PSIDLEN" -lt 0 ] && PSIDLEN=0
    [ "$PSIDLEN" -gt 16 ] && return 1

    local ipv4_suffix=$(( ea_bits >> PSIDLEN ))
    PSID=$(( ea_bits & ((1 << PSIDLEN) - 1) ))

    local ipv4_work="$IPV4_NET_PREFIX"
    local o1_val="${ipv4_work%%.*}"; ipv4_work="${ipv4_work#*.}"
    local o2_val="${ipv4_work%%.*}"; ipv4_work="${ipv4_work#*.}"
    local o3_val="${ipv4_work%%.*}"; local o4_val="${ipv4_work#*.}"
    
    if [ "$ipv4_suffix_len_num" -gt 0 ]; then
        o4_val=$(( o4_val | (ipv4_suffix & 0xFF) ))
        [ "$ipv4_suffix_len_num" -gt 8 ] && o3_val=$(( o3_val | ((ipv4_suffix >> 8) & 0xFF) ))
        [ "$ipv4_suffix_len_num" -gt 16 ] && o2_val=$(( o2_val | ((ipv4_suffix >> 16) & 0xFF) ))
        [ "$ipv4_suffix_len_num" -gt 24 ] && o1_val=$(( o1_val | ((ipv4_suffix >> 24) & 0xFF) ))
    fi

    IPADDR="${o1_val}.${o2_val}.${o3_val}.${o4_val}"
    CE=$(printf "%x:%x:%x:%x:%x:%x:%x:%x" "$h0_val" "$h1_val" "$h2_val" "$h3_val" "$o1_val" $(( (o2_val << 8) | o3_val )) $(( o4_val << 8 )) $(( PSID << 8 )))

    return 0
}

configure_openwrt_mape() {    
    cp /etc/config/network /etc/config/network.map-e.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.map-e.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.map-e.bak 2>/dev/null

    uci -q set network.${WAN_NAME}.disabled='1'
    uci -q set network.${WAN_NAME}.auto='0'
    uci -q set network.${WAN6_NAME}.disabled='1'
    uci -q set network.${WAN6_NAME}.auto='0'
    
    if ! uci -q get network.${LAN_NAME} >/dev/null; then
        uci -q set network.${LAN_NAME}=interface
        uci -q set network.${LAN_NAME}.proto='static'
        uci -q set network.${LAN_NAME}.device="${LAN_DEF}"
        uci -q set network.${LAN_NAME}.ipaddr="${LAN_IPADDR}"
        uci -q set network.${LAN_NAME}.netmask='255.255.255.0'
    fi

    if ! uci -q get dhcp.${LAN_NAME} >/dev/null; then
        uci -q set dhcp.${LAN_NAME}=dhcp
        uci -q set dhcp.${LAN_NAME}.interface="${LAN_NAME}"
        uci -q set dhcp.${LAN_NAME}.start='100'
        uci -q set dhcp.${LAN_NAME}.limit='150'
        uci -q set dhcp.${LAN_NAME}.leasetime='12h'
    fi

    uci -q set dhcp.${LAN_NAME}.ra='relay'
    uci -q set dhcp.${LAN_NAME}.dhcpv6='relay'
    uci -q set dhcp.${LAN_NAME}.ndp='relay'
    uci -q set dhcp.${LAN_NAME}.force='1'

    uci -q delete network.${WANMAP6_NAME}
    uci -q delete dhcp.${WANMAP6_NAME}
    uci -q delete network.${WANMAP_NAME}

    uci -q set network.${WANMAP6_NAME}=interface
    uci -q set network.${WANMAP6_NAME}.proto='dhcpv6'
    uci -q set network.${WANMAP6_NAME}.device="${WAN_DEF}"
    uci -q set network.${WANMAP6_NAME}.reqaddress='try'
    uci -q set network.${WANMAP6_NAME}.reqprefix='auto'
    uci -q set dhcp.${WANMAP6_NAME}=dhcp
    uci -q set dhcp.${WANMAP6_NAME}.interface="${WANMAP6_NAME}"
    uci -q set dhcp.${WANMAP6_NAME}.master='1' 
    uci -q set dhcp.${WANMAP6_NAME}.ra='relay'
    uci -q set dhcp.${WANMAP6_NAME}.dhcpv6='relay'
    uci -q set dhcp.${WANMAP6_NAME}.ndp='relay'

    uci -q set network.${WANMAP_NAME}=interface
    uci -q set network.${WANMAP_NAME}.proto='map'
    uci -q set network.${WANMAP_NAME}.maptype='map-e'
    uci -q set network.${WANMAP_NAME}.peeraddr="${BR}" 
    uci -q set network.${WANMAP_NAME}.ipaddr="${IPV4_NET_PREFIX}" 
    uci -q set network.${WANMAP_NAME}.ip4prefixlen="${IP4PREFIXLEN}" 
    uci -q set network.${WANMAP_NAME}.ip6prefix="${IPV6_RULE_PREFIX}" 
    uci -q set network.${WANMAP_NAME}.ip6prefixlen="${IPV6_RULE_PREFIXLEN}" 
    uci -q set network.${WANMAP_NAME}.ealen="${EALEN}" 
    uci -q set network.${WANMAP_NAME}.psidlen="${PSIDLEN}" 
    uci -q set network.${WANMAP_NAME}.offset="${OFFSET}" 
    uci -q set network.${WANMAP_NAME}.mtu="${MTU}" 
    uci -q set network.${WANMAP_NAME}.encaplimit='ignore'

    if [ -n "$NET_ADDR6" ]; then 
        uci -q set network.${WANMAP6_NAME}.ip6prefix="$WAN6_PREFIX"
    fi

    if echo "$OS_VERSION" | grep -q "^19"; then
        uci -q delete network.${WANMAP_NAME}.legacymap
        uci -q delete network.${WANMAP_NAME}.tunlink 
        uci -q add_list network.${WANMAP_NAME}.tunlink="${WANMAP6_NAME}"
    else
        uci -q set network.${WANMAP_NAME}.legacymap="${LEGACYMAP}" 
        uci -q set network.${WANMAP_NAME}.tunlink="${WANMAP6_NAME}"
        uci -q set dhcp.${WANMAP6_NAME}.ignore='1'
    fi

    local current_firewall_wan_networks
    current_firewall_wan_networks=$(uci -q get firewall.@zone[1].network 2>/dev/null)
    if ! echo "$current_firewall_wan_networks" | grep -qw "${WANMAP_NAME}"; then
        uci -q add_list firewall.@zone[1].network="${WANMAP_NAME}"
    fi
    if ! echo "$current_firewall_wan_networks" | grep -qw "${WANMAP6_NAME}"; then
        uci -q add_list firewall.@zone[1].network="${WANMAP6_NAME}"
    fi
    local current_firewall_lan_networks
    current_firewall_lan_networks=$(uci -q get firewall.@zone[0].network 2>/dev/null)
    if ! echo "$current_firewall_lan_networks" | grep -qw "${LAN_NAME}"; then
        uci -q add_list firewall.@zone[0].network="${LAN_NAME}"
    fi
    uci -q set firewall.@zone[1].masq='1'
    uci -q set firewall.@zone[1].mtu_fix='1'
    
    local commit_failed=0
    uci -q commit network
    if [ $? -ne 0 ]; then commit_failed=1; fi
    uci -q commit dhcp
    if [ $? -ne 0 ]; then commit_failed=1; fi
    uci -q commit firewall
    if [ $? -ne 0 ]; then commit_failed=1; fi
    if [ "$commit_failed" -eq 1 ]; then
        return 1
    fi

    return 0
}

replace_map() {
    local proto_script_path="/lib/netifd/proto/map.sh"
    local backup_script_path="${proto_script_path}.bak"
    local source_url=""
    local wget_rc

    if echo "$OS_VERSION" | grep -q "^19"; then
        source_url="https://raw.githubusercontent.com/site-u2023/map-e/main/map.sh.19"
    else
        source_url="https://raw.githubusercontent.com/site-u2023/map-e/main/map.sh.new"
    fi
    
    if [ -f "$proto_script_path" ]; then
        if command cp "$proto_script_path" "$backup_script_path"; then
            :
        else
            :
        fi
    fi

    command wget -6 -q -O "$proto_script_path" --timeout=10 --no-check-certificate "$source_url"
    wget_rc=$?
    if [ "$wget_rc" -eq 0 ]; then
        if [ -s "$proto_script_path" ]; then
            if command chmod +x "$proto_script_path"; then
                return 0
            fi
        fi
    fi
    
    return 1
}

internet_map_common() {
  initialize_info
  fetch_rule_api
  get_rule_api
  parse_user_ipv6
  calculate_mape_params
  configure_openwrt_mape
  replace_map
  echo "All done!"
}

internet_map_main "$@"
