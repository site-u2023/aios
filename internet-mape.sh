#!/bin/ash

# OpenWrt 19.07+ configuration
# Powered by https://ipv4.web.fc2.com/map-e.html

SCRIPT_VERSION="2025.06.12-00-00"

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
STATIC_API_RULE_LINE=""
MAPE_IPV6_ACQUISITION_METHOD=""
WAN6_PREFIX=""
OS_VERSION="" 
GUA=""

initialize_info() {
    if . /lib/functions.sh && . /lib/functions/network.sh; then
        : 
    else
        return 1
    fi

    if [ -f "/etc/openwrt_release" ]; then
        OS_VERSION=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d"'" -f2)
    fi

    local ipv6_info
    if ipv6_info=$(ip -6 addr show scope global | grep "inet6" | grep -v "fd" | sort -k2 -t/ -n | head -1); then
        USER_IPV6_ADDR=$(echo "$ipv6_info" | awk '{print $2}')
        GUA="gua"
    else
        return 1
    fi

    return 0
}

get_rule_from_api() {
    local _wan6_if_name_arg="$1" 
    local current_user_ipv6_addr_for_api="$USER_IPV6_ADDR"
    local api_url="https://map-api-worker.site-u.workers.dev/map-rule"
    local api_response=""
    local user_prefix_for_api=""
    local ret_code=1
    
    local _br _ealen _ipv4_net_prefix _ip4prefixlen _ipv6_rule_prefix _ipv6_rule_prefixlen _offset

    if [ -z "$current_user_ipv6_addr_for_api" ]; then
        return 1
    fi

    user_prefix_for_api=$(echo "$current_user_ipv6_addr_for_api" | awk -F/ '{print $1}' | awk -F: '{if(NF>=4) printf "%s:%s:%s:%s::", $1, $2, $3, $4; else print $0}')

    if [ -z "$user_prefix_for_api" ]; then
        return 1
    fi
    
    api_response=$(wget -q -O - --timeout=10 "${api_url}?user_prefix=${user_prefix_for_api}")
    ret_code=$?

    if [ $ret_code -ne 0 ] || [ -z "$api_response" ]; then
        BR=""; EALEN=""; IPV4_NET_PREFIX=""; IP4PREFIXLEN=""; IPV6_RULE_PREFIX=""; IPV6_RULE_PREFIXLEN=""; OFFSET=""
        return 1
    fi

    _br="" _ealen="" _ipv4_net_prefix="" _ip4prefixlen="" _ipv6_rule_prefix="" _ipv6_rule_prefixlen="" _offset=""
    eval $(echo "$api_response" | awk -F'"' '
        $2 == "brIpv6Address"    { print "_br=\"" $4 "\"" }
        $2 == "eaBitLength"      { print "_ealen=\"" $4 "\"" }
        $2 == "ipv4Prefix"       { print "_ipv4_net_prefix=\"" $4 "\"" }
        $2 == "ipv4PrefixLength" { print "_ip4prefixlen=\"" $4 "\"" }
        $2 == "ipv6Prefix"       { print "_ipv6_rule_prefix=\"" $4 "\"" }
        $2 == "ipv6PrefixLength" { print "_ipv6_rule_prefixlen=\"" $4 "\"" }
        $2 == "psIdOffset"       { print "_offset=\"" $4 "\"" }
    ')

    if [ -z "$_br" ] || [ -z "$_ealen" ] || [ -z "$_ipv4_net_prefix" ] || \
       [ -z "$_ip4prefixlen" ] || [ -z "$_ipv6_rule_prefix" ] || \
       [ -z "$_ipv6_rule_prefixlen" ] || [ -z "$_offset" ]; then
        BR=""; EALEN=""; IPV4_NET_PREFIX=""; IP4PREFIXLEN=""; IPV6_RULE_PREFIX=""; IPV6_RULE_PREFIXLEN=""; OFFSET=""
        return 1
    fi

    BR="$_br"
    EALEN="$_ealen"
    IPV4_NET_PREFIX="$_ipv4_net_prefix"
    IP4PREFIXLEN="$_ip4prefixlen"
    IPV6_RULE_PREFIX="$_ipv6_rule_prefix"
    IPV6_RULE_PREFIXLEN="$_ipv6_rule_prefixlen"
    OFFSET="$_offset"
    
    return 0
}

parse_user_ipv6() {
    local ipv6_to_parse="$1"
    if [ -z "$ipv6_to_parse" ]; then
        USER_IPV6_HEXTETS=""
        return 1
    fi

    local awk_script='
    BEGIN {
        FS=":";
        OFS=" ";
    }
    {
        # Remove /prefixlen if present
        sub(/\/.*/, "", $0);
        addr = $0;

        if (addr == "::") { # Handle the "::" case specifically
            print "0000 0000 0000 0000 0000 0000 0000 0000";
            next; # Exit processing for this line
        }

        # Logic for addresses containing "::"
        if (addr ~ /::/) {
            left_part = "";
            right_part = "";
            
            # Split address by "::"
            # index() returns the position of "::"
            double_colon_pos = index(addr, "::");
            
            if (double_colon_pos > 0) {
                left_part = substr(addr, 1, double_colon_pos - 1);
                right_part = substr(addr, double_colon_pos + 2); # +2 to skip "::"
            } else {
                # This case should ideally not be reached if addr ~ /::/ is true
                # Fallback or error handling can be added here if necessary
            }

            num_left_fields = 0;
            if (left_part != "") {
                # Count fields in the left part
                # split() returns the number of elements
                num_left_fields = split(left_part, left_arr, ":");
            }
            
            num_right_fields = 0;
            if (right_part != "") {
                # Count fields in the right part
                num_right_fields = split(right_part, right_arr, ":");
            }
            
            zeros_to_add = 8 - (num_left_fields + num_right_fields);
            
            result_str = "";
            
            # Process left part
            for (k=1; k<=num_left_fields; k++) {
                current_segment = left_arr[k];
                while (length(current_segment) < 4) {
                    current_segment = "0" current_segment;
                }
                result_str = result_str (length(result_str) > 0 ? OFS : "") current_segment;
            }
            
            # Add zeros for "::" expansion
            for (k=1; k<=zeros_to_add; k++) {
                result_str = result_str (length(result_str) > 0 ? OFS : "") "0000";
            }
            
            # Process right part
            for (k=1; k<=num_right_fields; k++) {
                current_segment = right_arr[k];
                while (length(current_segment) < 4) {
                    current_segment = "0" current_segment;
                }
                result_str = result_str (length(result_str) > 0 ? OFS : "") current_segment;
            }
            print result_str;

        } else {
            # Logic for addresses NOT containing "::" (should be full 8 hextets)
            num_fields = split(addr, hextets_arr, ":");
            output_str = "";
            # If num_fields is not 8, it might be an invalid or already malformed address.
            # This script will format what it gets.
            for (i = 1; i <= num_fields; i++) {
                current_segment = hextets_arr[i];
                while (length(current_segment) < 4) {
                    current_segment = "0" current_segment;
                }
                output_str = output_str (i > 1 ? OFS : "") current_segment;
            }
            print output_str;
        }
    }'
    
    USER_IPV6_HEXTETS=$(echo "$ipv6_to_parse" | awk "$awk_script")
    
    if [ -z "$USER_IPV6_HEXTETS" ] || [ $(echo "$USER_IPV6_HEXTETS" | wc -w) -ne 8 ]; then
        USER_IPV6_HEXTETS="" 
        return 1
    fi
    return 0
}

calculate_mape_params() {
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        return 1
    fi

    if [ -z "$EALEN" ] || [ -z "$IPV4_NET_PREFIX" ] || [ -z "$IP4PREFIXLEN" ] || [ -z "$OFFSET" ]; then
        return 1
    fi

    for value_to_check in "$EALEN" "$IP4PREFIXLEN" "$OFFSET"; do
        case "$value_to_check" in
            ''|*[!0-9]*)
                return 1 ;;
        esac
    done

    read -r h0 h1 h2 h3 _h4 _h5 _h6 _h7 <<EOF
$USER_IPV6_HEXTETS
EOF

    local h0_val=$((0x${h0:-0}))
    local h1_val=$((0x${h1:-0}))
    local h2_val=$((0x${h2:-0}))
    local h3_val=$((0x${h3:-0}))

    local ipv4_suffix_len=$((32 - IP4PREFIXLEN))
    if [ "$ipv4_suffix_len" -lt 0 ]; then
        return 1
    fi
    PSIDLEN=$((EALEN - ipv4_suffix_len))
    if [ "$PSIDLEN" -lt 0 ]; then
        PSIDLEN=0
    fi
    if [ "$PSIDLEN" -gt 16 ]; then
        return 1
    fi

    if [ "$PSIDLEN" -eq 0 ]; then
        PSID=0
    else
        PSID=$(( (h3_val >> 8) & ((1 << PSIDLEN) - 1) ))
    fi

    local o1 o2 o3_base o4_base o3_val o4_val temp_ip
    temp_ip="$IPV4_NET_PREFIX"
    o1="${temp_ip%%.*}"
    temp_ip="${temp_ip#*.}"
    o2="${temp_ip%%.*}"
    temp_ip="${temp_ip#*.}"
    o3_base="${temp_ip%%.*}"
    o4_base="${temp_ip#*.}"

    o3_val=$(( o3_base | ( (h2_val & 0x03C0) >> 6 ) ))
    o4_val=$(( ( (h2_val & 0x003F) << 2 ) | ( (h3_val & 0xC000) >> 14 ) ))

    IPADDR="${o1}.${o2}.${o3_val}.${o4_val}"

    local ce_h0_str=$(printf "%04x" "$h0_val")
    local ce_h1_str=$(printf "%04x" "$h1_val")
    local ce_h2_str=$(printf "%04x" "$h2_val")
    local ce_h3_str=$(printf "%04x" $(( h3_val & ~(((1 << PSIDLEN) - 1) << 8) )) )
    local ce_h4_str=$(printf "%04x" "$o1")
    local ce_h5_str=$(printf "%04x" $(( (o2 << 8) | o3_val )) )
    local ce_h6_str=$(printf "%04x" $(( o4_val << 8 )) )
    local ce_h7_str=$(printf "%04x" $(( PSID << 8 )) )

    CE="${ce_h0_str}:${ce_h1_str}:${ce_h2_str}:${ce_h3_str}:${ce_h4_str}:${ce_h5_str}:${ce_h6_str}:${ce_h7_str}"
    return 0
}

configure_openwrt_mape() {
    
    cp /etc/config/network /etc/config/network.map-e.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.map-e.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.map-e.bak 2>/dev/null
    
    if ! uci -q get network.lan >/dev/null; then
        uci -q set network.lan=interface
        uci -q set network.lan.proto='static'
        uci -q set network.lan.device="${LAN_DEF}"
        uci -q set network.lan.ipaddr="${LAN_IPADDR}"
        uci -q set network.lan.netmask='255.255.255.0'
    fi
    
    if ! uci -q get dhcp.lan >/dev/null; then
        uci -q set dhcp.lan=dhcp
        uci -q set dhcp.lan.interface='lan'
        uci -q set dhcp.lan.start='100'
        uci -q set dhcp.lan.limit='150'
        uci -q set dhcp.lan.leasetime='12h'
    fi
    
    uci -q set dhcp.lan.ra='relay'
    uci -q set dhcp.lan.dhcpv6='relay'
    uci -q set dhcp.lan.ndp='relay'
    uci -q set dhcp.lan.force='1'

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

    if [ -n "$GUA" ]; then 
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
    if ! echo "$current_firewall_wan_networks" | grep -q "\b${WANMAP_NAME}\b"; then
        uci -q add_list firewall.@zone[1].network="${WANMAP_NAME}"
    fi
    if ! echo "$current_firewall_wan_networks" | grep -q "\b${WANMAP6_NAME}\b"; then
        uci -q add_list firewall.@zone[1].network="${WANMAP6_NAME}"
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

    if command -v /etc/init.d/sysntpd >/dev/null 2>&1; then
        /etc/init.d/sysntpd restart >/dev/null 2>&1
        sleep 5
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

replace_map_sh() {
    local proto_script_path="/lib/netifd/proto/map.sh"
    local backup_script_path="${proto_script_path}.bak"
    local osversion=""
    local source_url=""
    local wget_rc
    local chmod_rc

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

    command wget -q ${WGET_IPV_OPT} --no-check-certificate -O "$proto_script_path" "$source_url"
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
    case "$GUA" in
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
        
        printf "%d-%d" "$port" "$port_end"
        [ "$port_idx" -lt "$AMAX" ] && printf " "
    done

    printf "\n"    
    printf "\033[1m• PSID:\033[0m %s (10進)\n" "$PSID"
    printf "------------------------------------------------------\n"
    printf "\033[1m注: 本当の値とは違う場合があります。\033[0m\n"
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
    local error_occurred=0
    local file_pairs
    local item
    local original_file
    local backup_file

    file_pairs="
        /etc/config/network:/etc/config/network.map-e.bak
        /etc/config/dhcp:/etc/config/dhcp.map-e.bak
        /etc/config/firewall:/etc/config/firewall.map-e.bak
        /lib/netifd/proto/map.sh:/lib/netifd/proto/map.sh.bak
    "

    for item in $file_pairs; do
        original_file="${item%%:*}"
        backup_file="${item#*:}"

        [ ! -f "$backup_file" ] || (cp "$backup_file" "$original_file" && rm "$backup_file") || error_occurred=1
    done

    if opkg list-installed | grep -q '^map '; then
        if ! opkg remove map >/dev/null 2>&1; then
            error_occurred=1
        fi
    fi
    
    if [ "$error_occurred" -ne 0 ]; then
        printf "\033[31mUCI設定復元失敗。\033[0m\n" >&2
        return 1
    fi

    printf "\033[32mUCI設定復元成功。\033[0m\n"
    printf "\033[32mMAPスクリプト復元成功。\033[0m\n"
    printf "\033[32mMAPパッケージ削除成功。\033[0m\n"
    printf "\033[33m何かキーを押すとデバイスを再起動します。\033[0m\n"
    read -r -n 1 -s
    reboot
    
    return 0
}

test_internet_map_main() {
    if ! initialize_info; then
        printf "\033[31mERROR: IPv6初期化失敗、または非対応環境。\033[0m\n" >&2
        return 1
    fi

    if ! get_rule_from_api "$WAN6_NAME"; then
        printf "\033[31mERROR: MAP-Eルール取得失敗。\033[0m\n" >&2
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

    printf "\033[33m注: 実際の設定及び再起動は行いません。\033[0m\n"
    
    printf "\033[32mMAPパッケージ導入成功。\033[0m\n"

    printf "\033[32mMAPスクリプト更新成功。\033[0m\n"

    printf "\033[32mUCI設定適用成功。\033[0m\n"
    
    printf "\033[33m何かキーを押すとデバイスを再起動します。\033[0m\n"
    read -r -n1 -s
    return 0
}

internet_map_main() {
    if ! initialize_info; then
        printf "\033[31mERROR: IPv6初期化失敗、または非対応環境。\033[0m\n" >&2
        return 1
    fi

    if ! get_rule_from_api "$WAN6_NAME"; then
        printf "\033[31mERROR: MAP-Eルール取得失敗。\033[0m\n" >&2
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

    if ! install_map_package; then
        printf "\033[31mERROR: MAPパッケージ導入失敗。\033[0m\n" >&2
        return 1
    else
        printf "\033[32mMAPパッケージ導入成功。\033[0m\n"
    fi

    if ! replace_map_sh; then
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
    return 0
}

# test_internet_map_main
# internet_map_main
