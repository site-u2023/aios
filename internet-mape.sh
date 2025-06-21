#!/bin/ash

# OpenWrt 19.07+ configuration
# Powered by https://ipv4.web.fc2.com/map-e.html

SCRIPT_VERSION="2025.06.14-00-00"

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

fetch_rule_api_ocn() {
    local ocn_api_code="$1"
    local user_ipv6_prefix_len="${user_ipv6_prefix_len:-64}"
    
    if [ -z "$ocn_api_code" ]; then
        printf "\nOCN APIコードを入力してください: "
        read -s ocn_api_code
        echo
    fi
    
    [ -z "$ocn_api_code" ] || [ -z "$USER_IPV6_PREFIX" ] && return 1

    if [ -n "$NET_PFX6" ]; then
        user_ipv6_prefix_len=$(echo "$NET_PFX6" | cut -d'/' -f2)
    fi
    
    API_RESPONSE=$(wget -6 -q -O - --timeout=10 "https://rule.map.ocn.ad.jp/?ipv6Prefix=${USER_IPV6_PREFIX}&ipv6PrefixLength=${user_ipv6_prefix_len}&code=${ocn_api_code}")
    [ -z "$API_RESPONSE" ] && return 1

    API_RESPONSE=$(echo "$API_RESPONSE" | awk '
    BEGIN { in_block=0; block=""; }
    /\{/ { in_block=1; block=$0; next; }
    in_block {
        block = block "\n" $0
        if (/\}/) {
            if (block ~ /"brIpv6Address":/) {
                print block
                exit
            }
            in_block=0; block="";
        }
    }')

    [ -z "$API_RESPONSE" ] && return 1 || return 0
}

get_rule_api() {
    local api_response="$API_RESPONSE"
    
    BR=""; EALEN=""; IPV4_NET_PREFIX=""; IP4PREFIXLEN=""; IPV6_RULE_PREFIX=""; IPV6_RULE_PREFIXLEN=""; OFFSET=""

    [ -z "$api_response" ] && return 1
    
    eval $(echo "$api_response" | awk -F'"' '
    BEGIN { ipv6_raw="" }
    {
        if($2=="brIpv6Address") print "BR=\""$4"\""
        else if($2=="eaBitLength") print "EALEN=\""$4"\""
        else if($2=="ipv4Prefix") print "IPV4_NET_PREFIX=\""$4"\""
        else if($2=="ipv4PrefixLength") print "IP4PREFIXLEN=\""$4"\""
        else if($2=="ipv6Prefix") ipv6_raw=$4
        else if($2=="ipv6PrefixLength") print "IPV6_RULE_PREFIXLEN=\""$4"\""
        else if($2=="psIdOffset") print "OFFSET=\""$4"\""
    }
    END {
        if(ipv6_raw != "") {
            # Split by colons and process each segment
            n = split(ipv6_raw, segments, ":")
            result = ""
            
            for (i = 1; i <= n; i++) {
                if (segments[i] == "") {
                    if (i == 1 || i == n) result = result ":"
                    else if (substr(result, length(result)) != ":") result = result ":"
                    result = result ":"
                } else {
                    seg = segments[i]
                    gsub(/^0+/, "", seg)
                    if (seg == "") seg = "0"
                    
                    if (result != "" && substr(result, length(result)) != ":") {
                        result = result ":"
                    }
                    result = result seg
                }
            }
            
            gsub(/:::+/, "::", result)
            gsub(/:0+::/, "::", result)
            gsub(/::0$/, "::", result)
            
            print "IPV6_RULE_PREFIX=\"" result "\""
        }
    }')

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

install_map_package() {
    local pkg_manager=""

    if command -v opkg >/dev/null 2>&1; then
        pkg_manager="opkg"
    elif command -v apk >/dev/null 2>&1; then
        pkg_manager="apk"
    else
        return 1
    fi
    
    case "$pkg_manager" in
        "opkg")
            opkg list-installed | grep -q '^map ' && return 0
            opkg update >/dev/null 2>&1
            if ! opkg install map >/dev/null 2>&1; then
                return 1
            fi
            ;;
        "apk")
            apk list -I 2>/dev/null | grep -q '^map-' && return 0
            apk update >/dev/null 2>&1
            if ! apk add map >/dev/null 2>&1; then
                return 1
            fi
            ;;
    esac
    
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

display_mape() {
    local ipv6_label
    case "$NET_ADDR6" in
        "") ipv6_label="IPv6プレフィックス:" ;;
        *)  ipv6_label="IPv6アドレス:" ;;
    esac

    printf "\n"
    printf "\033[1mconfig-softwire\033[0m\n"
    printf "\n"   
    printf "\033[1m%s\033[0m %s\n" "$ipv6_label" "$USER_IPV6_ADDR"
    printf "\n"
    printf "\033[1m• CE:\033[0m %s\n" "$CE"
    printf "\033[1m• IPv4アドレス:\033[0m %s\n" "$IPADDR"
    
    printf "\033[1m• ポート番号:\033[0m "
    local AMAX=$(( (1 << OFFSET) - 1 ))
    local port_idx
    for port_idx in $(seq 0 "$AMAX"); do
        local shift_bits=$(( 16 - OFFSET ))
        local port_base=$(( port_idx << shift_bits ))
        local psid_shift=$(( 16 - OFFSET - PSIDLEN ))
        [ "$psid_shift" -lt 0 ] && psid_shift=0
        local psid_part=$(( PSID << psid_shift ))
        local port=$(( port_base | psid_part ))
        local port_range_size=$(( 1 << psid_shift ))
        [ "$port_range_size" -le 0 ] && port_range_size=1
        local port_end=$(( port + port_range_size - 1 ))

        # [ "$port_end" -lt 1024 ] && continue
        # [ "$port" -lt 1024 ] && port=1024
        printf "%d-%d" "$port" "$port_end"
        [ "$port_idx" -lt "$AMAX" ] && printf " "
    done

    printf "\n"    
    printf "\033[1m• PSID:\033[0m %s (10進)\n" "$PSID"
    printf "------------------------------------------------------\n"
    printf "\033[1m注: 本当の値とは違う場合があります。\033[0m\n"
    printf "\033[1m注: 0〜1023は特権ポートです。詳細はISPに確認してください。\033[0m\n"
    printf "\n"
    
    printf "option peeraddr %s\n" "$BR"
    printf "option ipaddr %s\n" "$IPV4_NET_PREFIX"
    printf "option ip4prefixlen %s\n" "$IP4PREFIXLEN"
    printf "option ip6prefix %s\n" "$IPV6_RULE_PREFIX"
    printf "option ip6prefixlen %s\n" "$IPV6_RULE_PREFIXLEN"
    printf "option ealen %s\n" "$EALEN"
    printf "option psidlen %s\n" "$PSIDLEN"
    printf "option offset %s\n" "$OFFSET"
    printf "\n"
    printf "export LEGACY=1\n"
    printf "------------------------------------------------------\n"
    printf "\033[34m(config-softwire)#\033[0m \033[1mmap-version draft\033[0m\n"
    printf "\033[34m(config-softwire)#\033[0m \033[1mrule\033[0m \033[1;34m<0-65535>\033[0m \033[1mipv4-prefix\033[0m \033[1;34m%s/%s\033[0m \033[1mipv6-prefix\033[0m \033[1;34m%s/%s\033[0m [ea-length \033[34m%s\033[0m|psid-length \033[34m%s\033[0m [psid \033[36m%s\033[0m]] [offset \033[34m%s\033[0m] [forwarding]\n" \
       "$IPV4_NET_PREFIX" "$IP4PREFIXLEN" "$IPV6_RULE_PREFIX" "$IPV6_RULE_PREFIXLEN" "$EALEN" "$PSIDLEN" "$PSID" "$OFFSET"
    printf "\n"
    printf "Powered by \033[1mhttps://ipv4.web.fc2.com/map-e.html\033[0m\n"
    printf "\n"
    
    return 0
}

restore_mape() {
    local file_pairs
    local pkg_manager
    
    file_pairs="
        /etc/config/network:/etc/config/network.map-e.bak
        /etc/config/dhcp:/etc/config/dhcp.map-e.bak
        /etc/config/firewall:/etc/config/firewall.map-e.bak
        /lib/netifd/proto/map.sh:/lib/netifd/proto/map.sh.bak
    "

    if command -v opkg >/dev/null 2>&1; then
        pkg_manager="opkg"
    elif command -v apk >/dev/null 2>&1; then
        pkg_manager="apk"
    fi

    local error_msg="\033[31mERROR: 復元処理に失敗しました。\033[0m"
    local item original_file backup_file
    for item in $file_pairs; do
        original_file="${item%%:*}"
        backup_file="${item#*:}"
        if [ -f "$backup_file" ]; then
            if ! (cp "$backup_file" "$original_file" && rm "$backup_file"); then
                printf "$error_msg\n" >&2
                return 1
            fi
        fi
    done
    printf "\033[32mUCI設定復元成功。\033[0m\n"
    printf "\033[32mMAPスクリプト復元成功。\033[0m\n"

    local pkg_error_msg="\033[31mERROR: パッケージ削除に失敗しました。\033[0m"
    case "$pkg_manager" in
        opkg)
            if opkg list-installed | grep -q '^map '; then
                if ! opkg remove map >/dev/null 2>&1; then
                    printf "$pkg_error_msg\n" >&2
                    return 1
                fi
            fi
            ;;
        apk)
            if apk info -e map >/dev/null 2>&1; then
                if ! apk del map >/dev/null 2>&1; then
                    printf "$pkg_error_msg\n" >&2
                    return 1
                fi
            fi
            ;;
    esac
    printf "\033[32mMAPパッケージ削除成功。\033[0m\n"

    printf "\033[33m何かキーを押すとデバイスを再起動します。\033[0m\n"
    read -r -n 1 -s
    reboot
    return 0
}

internet_map_common() {
    local api_mode="$1"
    local apply_mode="$2"
    local ocn_code="$3"

    if ! initialize_info; then
        printf "\033[31mERROR: IPv6初期化失敗、または非対応環境。\033[0m\n" >&2
        return 1
    fi
    if [ "$api_mode" = "ocn" ]; then
        if ! fetch_rule_api_ocn "$ocn_code"; then
            printf "\033[31mERROR: MAP-Eルール取得失敗。\033[0m\n" >&2
            return 1
        fi
    else
        if ! fetch_rule_api; then
            printf "\033[31mERROR: MAP-Eルール取得失敗。\033[0m\n" >&2
            return 1
        fi
    fi
    if ! get_rule_api; then
        printf "\033[31mERROR: MAP-Eルール解析失敗。\033[0m\n" >&2
        return 1
    fi
    if [ -z "$USER_IPV6_ADDR" ]; then
        printf "\033[31mERROR: ユーザーIPv6アドレス未設定。\033[0m\n" >&2
        return 1
    fi
    if ! parse_user_ipv6 "$USER_IPV6_ADDR"; then
        printf "\033[31mERROR: IPv6アドレス解析失敗。\033[0m\n" >&2
        return 1
    fi
    if ! calculate_mape_params; then
        printf "\033[31mERROR: MAP-Eパラメータ計算失敗。\033[0m\n" >&2
        return 1
    fi
    if ! display_mape; then
        printf "\033[31mERROR: MAP-Eパラメータ表示失敗。\033[0m\n" >&2
        return 1
    fi

    if [ "$apply_mode" = "apply" ]; then
        if ! install_map_package; then
            printf "\033[31mERROR: MAPパッケージ導入失敗。\033[0m\n" >&2
            return 1
        else
            printf "\033[32mMAPパッケージ導入成功。\033[0m\n"
        fi
        if ! replace_map; then
            printf "\033[31mERROR: MAPスクリプト更新失敗。\033[0m\n" >&2
            return 1
        else
            printf "\033[32mMAPスクリプト更新成功。\033[0m\n"
        fi
        if ! configure_openwrt_mape; then
            printf "\033[31mERROR: UCI設定適用失敗。\033[0m\n" >&2
            return 1
        else
            printf "\033[32mUCI設定適用成功。\033[0m\n"
        fi
        printf "\033[33m何かキーを押すとデバイスを再起動します。\033[0m\n"
        read -r -n1 -s
        reboot
    else
        printf "\033[33m注: 実際の設定及び再起動は行いません。\033[0m\n"
    fi
    
    return 0
}

test_internet_map_main() {
    local input_ipv6=""
    if [ -z "$1" ]; then
        printf "\nGUAまたはPDを入力してください（空欄の場合はデバイス値を利用します）: "
        read input_ipv6
        if [ -n "$input_ipv6" ]; then
            USER_IPV6_ADDR="$input_ipv6"
        fi
    else
        USER_IPV6_ADDR="$1"
    fi
    internet_map_common "default" "dry"
}
internet_map_ocn_main()       { internet_map_common "ocn" "apply" "$1"; }
internet_map_main()           { internet_map_common "default" "apply"; }

# test_internet_map_main "$@"
# internet_map_ocn_main "$@"
# internet_map_main
