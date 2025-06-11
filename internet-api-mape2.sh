#!/bin/ash

# OpenWrt 19.07+ configuration
# Powered by https://ipv4.web.fc2.com/map-e.html

SCRIPT_VERSION="2025.06.11-00-00"

WAN_IF_NAME=""
LAN_IF_NAME=""
MAP_IF_NAME="wanmap"
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

initialize_network_info() {
    if [ -f /lib/functions.sh ]; then
        . /lib/functions.sh
        if [ -f /lib/functions/network.sh ]; then # OpenWrt 21.02+
            . /lib/functions/network.sh
        elif [ -f /lib/network/network.sh ]; then # Older OpenWrt
            . /lib/network/network.sh
        else
            return 1
        fi
    else
        return 1
    fi

    local detected_wan6_if=""
    if command -v network_find_wan6 >/dev/null 2>&1; then
        network_find_wan6 detected_wan6_if
    fi

    if [ -n "$detected_wan6_if" ]; then
        WAN6_IF_NAME="$detected_wan6_if"
    else
        return 1
    fi
    
    if [ -z "$WAN6_IF_NAME" ]; then
        return 1
    fi

    local detected_wan_if=""
    if command -v network_find_wan >/dev/null 2>&1; then
        network_find_wan detected_wan_if
    fi
    if [ -n "$detected_wan_if" ]; then
        WAN_IF_NAME="$detected_wan_if"
    fi

    local detected_lan_if=""
    if command -v network_get_device >/dev/null 2>&1; then
        network_get_device detected_lan_if lan
    fi
    if [ -n "$detected_lan_if" ]; then
        LAN_IF_NAME="$detected_lan_if"
    fi

    if ! ping -6 -c 1 -W 3 2001:4860:4860::8888 >/dev/null 2>&1 && \
       ! ping -6 -c 1 -W 3 2606:4700:4700::1111 >/dev/null 2>&1; then
        return 1
    fi
    
    local ipv6_addr=""
    network_get_ipaddr6 ipv6_addr "$WAN6_IF_NAME"
    
    if [ -n "$ipv6_addr" ]; then
        USER_IPV6_ADDR="$ipv6_addr"
        WAN6_PREFIX=$(echo "$ipv6_addr" | awk -F: '{if (NF>=4) printf "%s:%s:%s:%s::/64", $1, $2, $3, $4; else print ""}')
        return 0
    fi
    
    local ipv6_prefix=""
    network_get_prefix6 ipv6_prefix "$WAN6_IF_NAME"
    
    if [ -n "$ipv6_prefix" ]; then
        USER_IPV6_ADDR="$ipv6_prefix"
        return 0
    fi
    
    return 1
}

get_rule_from_api() {
    local _wan6_if_name_arg="$1" 
    local current_user_ipv6_addr_for_api="$USER_IPV6_ADDR"
    local api_url="https://map-api-worker.site-u.workers.dev/map-rule"
    local api_response=""
    local user_prefix_for_api=""
    local ret_code=1

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

    _br=$(echo "$api_response" | grep '"brIpv6Address":' | awk -F'"' '{print $4}')
    _ealen=$(echo "$api_response" | grep '"eaBitLength":' | awk -F'"' '{print $4}')
    _ipv4_net_prefix=$(echo "$api_response" | grep '"ipv4Prefix":' | awk -F'"' '{print $4}')
    _ip4prefixlen=$(echo "$api_response" | grep '"ipv4PrefixLength":' | awk -F'"' '{print $4}')
    _ipv6_rule_prefix=$(echo "$api_response" | grep '"ipv6Prefix":' | awk -F'"' '{print $4}')
    _ipv6_rule_prefixlen=$(echo "$api_response" | grep '"ipv6PrefixLength":' | awk -F'"' '{print $4}')
    _offset=$(echo "$api_response" | grep '"psIdOffset":' | awk -F'"' '{print $4}')

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
    BEGIN { FS=":"; OFS=" "; }
    {
        num_colons = 0; for (k=1; k<=length($0); k++) { if (substr($0, k, 1) == ":") num_colons++; }
        
        expanded_addr = $0;
        if (index(expanded_addr, "::")) {
            sub("::", ":DOUBLE_COLON:", expanded_addr);
            
            n_fields = split(expanded_addr, arr, ":");
            
            output_str = "";
            zeros_inserted = 0;
            field_count_out = 0;

            for (j=1; j<=n_fields; j++) {
                if (arr[j] == "DOUBLE_COLON") {
                    valid_fields = 0;
                    for (m=1; m<=n_fields; m++) {
                        if (arr[m] != "DOUBLE_COLON" && arr[m] != "") {
                             valid_fields++;
                        }
                    }
                    if ($0 == "::") {
                        zeros_to_add = 8;
                    } else if (substr($0,1,2) == "::" && substr($0,length($0)-1,2) == "::" && length($0) == 2) {
                        zeros_to_add = 8;
                    } else if (substr($0,1,2) == "::") {
                        zeros_to_add = 8 - valid_fields;
                    } else if (substr($0,length($0)-1,2) == "::") {
                        zeros_to_add = 8 - valid_fields;
                    } else {
                        zeros_to_add = 8 - valid_fields;
                    }
                    
                    for (l=1; l<=zeros_to_add; l++) {
                        output_str = output_str (field_count_out > 0 ? OFS : "") "0000";
                        field_count_out++;
                    }
                    zeros_inserted = 1;
                } else if (arr[j] != "") {
                    seg = arr[j];
                    while(length(seg) < 4) seg = "0" seg;
                    output_str = output_str (field_count_out > 0 ? OFS : "") seg;
                    field_count_out++;
                } else if (arr[j] == "" && j > 1 && j < n_fields && zeros_inserted == 0 && field_count_out < 8) {
                     output_str = output_str (field_count_out > 0 ? OFS : "") "0000";
                     field_count_out++;
                }
            }
            if (zeros_inserted == 0) {
                while (field_count_out < 8) {
                    output_str = output_str (field_count_out > 0 ? OFS : "") "0000";
                    field_count_out++;
                }
            }
            print output_str;
            
        } else {
            n_fields = split($0, arr, ":");
            output_str = "";
            for (j=1; j<=n_fields; j++) {
                 seg = arr[j];
                 while(length(seg) < 4) seg = "0" seg;
                 output_str = output_str (j > 1 ? OFS : "") seg;
            }
            for (j=n_fields+1; j<=8; j++) {
                 output_str = output_str OFS "0000";
            }
            print output_str;
        }
    }'
    
    USER_IPV6_HEXTETS=$(echo "$ipv6_to_parse" | awk "$awk_script")
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        return 1
    fi
    return 0
}

calculate_mape_params() {
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        return 1
    fi

    if [ -z "$BR" ] || [ -z "$EALEN" ] || [ -z "$IPV4_NET_PREFIX" ] || \
       [ -z "$IP4PREFIXLEN" ] || [ -z "$IPV6_RULE_PREFIX" ] || \
       [ -z "$IPV6_RULE_PREFIXLEN" ] || [ -z "$OFFSET" ]; then
        return 1
    fi

    for value_to_check in "$EALEN" "$IP4PREFIXLEN" "$IPV6_RULE_PREFIXLEN" "$OFFSET"; do
        case "$value_to_check" in
            ''|*[!0-9]*)
                return 1 ;;
        esac
    done

    read -r h0 h1 h2 h3 _h4 _h5 _h6 _h7 <<EOF
$USER_IPV6_HEXTETS
EOF

    local h0_val_for_calc h1_val_for_calc h2_val_for_calc h3_val_for_calc
    h0_val_for_calc=$((0x${h0:-0}))
    h1_val_for_calc=$((0x${h1:-0}))
    h2_val_for_calc=$((0x${h2:-0}))
    h3_val_for_calc=$((0x${h3:-0}))

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

    local shift_for_psid=$((16 - OFFSET - PSIDLEN))
    if [ "$shift_for_psid" -lt 0 ]; then
        return 1
    fi

    local psid_field_only_mask=0
    if [ "$PSIDLEN" -gt 0 ]; then
        psid_field_only_mask=$(( (1 << PSIDLEN) - 1 ))
    fi
    local psid_mask_in_hextet3=$(( psid_field_only_mask << shift_for_psid ))

    if [ "$PSIDLEN" -eq 0 ]; then
        PSID=0
    else
        PSID=$(( (h3_val_for_calc & psid_mask_in_hextet3) >> shift_for_psid ))
    fi

    local o1 o2 o3_base o4_base o3_val o4_val
    o1=$(echo "$IPV4_NET_PREFIX" | cut -d. -f1)
    o2=$(echo "$IPV4_NET_PREFIX" | cut -d. -f2)
    o3_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f3)
    o4_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f4)

    o3_val=$(( o3_base | ( (h2_val_for_calc & 0x03C0) >> 6 ) ))
    o4_val=$(( ( (h2_val_for_calc & 0x003F) << 2 ) | (( (h3_val_for_calc & 0xC000) >> 14) & 0x0003 ) ))

    IPADDR="${o1}.${o2}.${o3_val}.${o4_val}"

    local ce_h0_str=$(printf "%04x" "$h0_val_for_calc")
    local ce_h1_str=$(printf "%04x" "$h1_val_for_calc")
    local ce_h2_str=$(printf "%04x" "$h2_val_for_calc")
    local ce_h3_masked_val=$(( h3_val_for_calc & (~psid_mask_in_hextet3 & 0xFFFF) ))
    local ce_h3_str=$(printf "%04x" "$ce_h3_masked_val")
    local ce_h4_str=$(printf "%04x" "$o1")
    local ce_h5_str=$(printf "%04x" $(( (o2 << 8) | o3_val )) )
    local ce_h6_str=$(printf "%04x" $(( o4_val << 8 )) )
    local ce_h7_val=0
    if [ "$PSIDLEN" -gt 0 ]; then
         ce_h7_val=$(( PSID << shift_for_psid ))
    fi
    local ce_h7_str=$(printf "%04x" "$ce_h7_val")

    CE="${ce_h0_str}:${ce_h1_str}:${ce_h2_str}:${ce_h3_str}:${ce_h4_str}:${ce_h5_str}:${ce_h6_str}:${ce_h7_str}"
    return 0
}

configure_openwrt_mape() {
    local ZONE_NO
    ZONE_NO=$(uci show firewall | grep -E "firewall\.@zone\[([0-9]+)\].name='wan'" | sed -n 's/firewall\.@zone\[\([0-9]*\)\].name=.*/\1/p' | head -n1)
    if [ -z "$ZONE_NO" ]; then
        ZONE_NO="1"
    fi

    local osversion=""
    if [ -f "/etc/openwrt_release" ]; then
        osversion=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d"'" -f2)
    else
        osversion="unknown"
    fi
    
    cp /etc/config/network /etc/config/network.map-e.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.map-e.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.map-e.bak 2>/dev/null
    
    uci -q set network.${WAN_IF_NAME}.disabled='1'
    uci -q set network.${WAN_IF_NAME}.auto='0'

    uci -q set dhcp.${LAN_IF_NAME}.ra='relay'
    uci -q set dhcp.${LAN_IF_NAME}.dhcpv6='relay'
    uci -q set dhcp.${LAN_IF_NAME}.ndp='relay'
    uci -q set dhcp.${LAN_IF_NAME}.force='1'

    uci -q set dhcp.${WAN6_IF_NAME}=dhcp
    uci -q set dhcp.${WAN6_IF_NAME}.interface="$WAN6_IF_NAME"
    uci -q set dhcp.${WAN6_IF_NAME}.master='1'
    uci -q set dhcp.${WAN6_IF_NAME}.ra='relay'
    uci -q set dhcp.${WAN6_IF_NAME}.dhcpv6='relay'
    uci -q set dhcp.${WAN6_IF_NAME}.ndp='relay'
    
    uci -q set network.${WAN6_IF_NAME}.proto='dhcpv6'
    uci -q set network.${WAN6_IF_NAME}.reqaddress='try'
    uci -q set network.${WAN6_IF_NAME}.reqprefix='auto' 
    
    if [ -n "$WAN6_PREFIX" ]; then
        uci -q set network.${WAN6_IF_NAME}.ip6prefix="$WAN6_PREFIX"
    else
        uci -q delete network.${WAN6_IF_NAME}.ip6prefix
    fi

    uci -q set network.${MAP_IF_NAME}=interface
    uci -q set network.${MAP_IF_NAME}.proto='map'
    uci -q set network.${MAP_IF_NAME}.maptype='map-e'
    uci -q set network.${MAP_IF_NAME}.peeraddr="${BR}"
    uci -q set network.${MAP_IF_NAME}.ipaddr="${IPV4_NET_PREFIX}"
    uci -q set network.${MAP_IF_NAME}.ip4prefixlen="${IP4PREFIXLEN}"
    uci -q set network.${MAP_IF_NAME}.ip6prefix="${IPV6_RULE_PREFIX}"
    uci -q set network.${MAP_IF_NAME}.ip6prefixlen="${IPV6_RULE_PREFIXLEN}"
    uci -q set network.${MAP_IF_NAME}.ealen="${EALEN}"
    uci -q set network.${MAP_IF_NAME}.psidlen="${PSIDLEN}"
    uci -q set network.${MAP_IF_NAME}.offset="${OFFSET}"
    uci -q set network.${MAP_IF_NAME}.mtu="${MTU}"
    uci -q set network.${MAP_IF_NAME}.encaplimit='ignore'

    if echo "$osversion" | grep -q "^19"; then
        uci -q delete network.${MAP_IF_NAME}.tunlink
        uci -q add_list network.${MAP_IF_NAME}.tunlink="${WAN6_IF_NAME}"
        uci -q delete network.${MAP_IF_NAME}.legacymap
    else
        uci -q set dhcp.${WAN6_IF_NAME}.ignore='1'
        uci -q set network.${MAP_IF_NAME}.legacymap="${LEGACYMAP}"
        uci -q set network.${MAP_IF_NAME}.tunlink="${WAN6_IF_NAME}"
    fi
    
    local current_wan_networks
    current_wan_networks=$(uci -q get firewall.@zone[${ZONE_NO}].network 2>/dev/null)

    if echo "$current_wan_networks" | grep -q "\b${WAN_IF_NAME}\b"; then
        uci -q del_list firewall.@zone[${ZONE_NO}].network="${WAN_IF_NAME}"
    fi

    if ! echo "$current_wan_networks" | grep -q "\b${MAP_IF_NAME}\b"; then
        uci -q add_list firewall.@zone[${ZONE_NO}].network="${MAP_IF_NAME}"
    fi
    uci -q set firewall.@zone[${ZONE_NO}].masq='1'
    uci -q set firewall.@zone[${ZONE_NO}].mtu_fix='1'
    
    local commit_failed=0

    uci -q commit network
    if [ $? -ne 0 ]; then
        commit_failed=1
    fi

    uci -q commit dhcp
    if [ $? -ne 0 ]; then
        commit_failed=1
    fi
    
    uci -q commit firewall
    if [ $? -ne 0 ]; then
        commit_failed=1
    fi

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
    local osversion_file="${CACHE_DIR}/osversion.ch"
    local osversion=""
    local source_url=""
    local wget_rc
    local chmod_rc

    if [ -f "$osversion_file" ]; then
        osversion=$(cat "$osversion_file")
    else
        osversion="unknown"
    fi

    if echo "$osversion" | grep -q "^19"; then
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
                if type get_message > /dev/null 2>&1; then
                    printf "%s\n" "$(color green "$(get_message "MSG_MAP_SH_UPDATE_SUCCESS")")"
                fi
                return 0
            else
                return 2
            fi
        else
            return 1
        fi
    else
        return 1
    fi
}

display_mape() {
    local ipv6_label
    case "$WAN6_PREFIX" in
        "") ipv6_label="IPv6プレフィックス:" ;;
        *)  ipv6_label="IPv6アドレス:" ;;
    esac

    printf "\n"
    printf "\033[1mconfig-softwire\033[0m\n"
    printf "\n"   
    printf "\033[1m%s\033[0m %s/64\n" "$ipv6_label" "$USER_IPV6_ADDR"
    printf "\n"
    printf "\033[1m• CE:\033[0m %s\n" "$CE"
    printf "\033[1m• IPv4アドレス:\033[0m %s\n" "$IPADDR"
    
    printf "\033[1m• ポート番号:\033[0m "
    local shift_bits=$((16 - OFFSET))
    local psid_shift=$((16 - OFFSET - PSIDLEN))
    [ "$psid_shift" -lt 0 ] && psid_shift=0
    local range_size=$((1 << psid_shift))
    local max_blocks=$((1 << OFFSET))
    local last=$((max_blocks - 1))
    
    for A in $(seq 0 "$last"); do
        local base=$((A << shift_bits))
        local part=$((PSID << psid_shift))
        local start=$((base | part))
        local end=$((start + range_size - 1))
        
        printf "%d-%d" "$start" "$end"
        [ "$A" -lt "$last" ] && printf " "
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
    local backup_files_restored_count=0
    local backup_files_not_found_count=0
    local restore_failed_count=0
    local overall_restore_status=1

    local files_to_restore="
        /etc/config/network:/etc/config/network.map-e.bak
        /etc/config/dhcp:/etc/config/dhcp.map-e.bak
        /etc/config/firewall:/etc/config/firewall.map-e.bak
        /lib/netifd/proto/map.sh:/lib/netifd/proto/map.sh.bak
    "

    local files_to_process
    files_to_process=$(printf -- "%s" "$files_to_restore" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;/^[[:space:]]*$/d')

    printf -- "%s" "$files_to_process" | while IFS=: read -r original_file backup_file_remainder || [ -n "$original_file" ]; do
        local current_backup_file="$backup_file_remainder"

        if [ -f "$current_backup_file" ]; then
            if cp "$current_backup_file" "$original_file"; then
                backup_files_restored_count=$((backup_files_restored_count + 1))
            else
                restore_failed_count=$((restore_failed_count + 1))
            fi
        else
            backup_files_not_found_count=$((backup_files_not_found_count + 1))
        fi
    done

    if [ "$restore_failed_count" -gt 0 ]; then
        overall_restore_status=2
    elif [ "$backup_files_restored_count" -gt 0 ]; then
        overall_restore_status=0
    else
        overall_restore_status=1
    fi

    if [ "$overall_restore_status" -eq 0 ] || [ "$overall_restore_status" -eq 2 ]; then
        opkg remove map >/dev/null 2>&1
        
        printf "\033[32mUCI設定復元成功。\033[0m\n"
        if [ "$overall_restore_status" -eq 2 ]; then
            printf "\033[31mERROR: 一部ファイル復元失敗。\033[0m\n" >&2
        fi
        
        printf "\033[33m何かキーを押すとネットワークサービスを再起動します。\033[0m\n"
        read -r -n 1 -s
        ubus call network reload
        
        return "$overall_restore_status" 
    elif [ "$overall_restore_status" -eq 1 ]; then
        printf "\033[31mERROR: ファイル復元失敗。\033[0m\n" >&2
        return 1
    fi
    
    printf "\033[31mERROR: 復元状態不明。\033[0m\n" >&2
    return 1
}

api_mape_main() {
    if ! initialize_network_info; then
        printf "\033[31mERROR: IPv6初期化失敗、または非対応環境。\033[0m\n" >&2
        return 1
    fi

    if ! get_rule_from_api "$WAN6_IF_NAME"; then
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
    
    if ! configure_openwrt_mape; then
        printf "\033[31mERROR: UCI設定適用失敗。\033[0m\n" >&2
        return 1
    else
        printf "\033[32mUCI設定適用成功。\033[0m\n"
    fi
    
    if ! install_map_package; then
        printf "\033[31mERROR: MAPパッケージ導入失敗。\033[0m\n" >&2
        return 1
    else
        printf "\033[32mMAPパッケージ導入成功。\033[0m\n"
    fi

    if ! replace_map_sh; then
        printf "\033[31mERROR: MAPスクリプト更新失敗。(詳細コード: %s)\033[0m\n" "$ret_code" >&2
    else
        local ret_code=$?
        printf "\033[32mMAPスクリプト更新成功。\033[0m\n"
        return 1
    fi
    
    printf "\033[33m何かキーを押すとネットワークサービスを再起動します。\033[0m\n"
    read -r -n1 -s
    ubus call network reload
    return 0
}

# api_mape_main
