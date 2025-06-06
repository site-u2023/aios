#!/bin/ash

SCRIPT_VERSION="0.1.0-ocn" # 新しいスクリプト用のバージョン
SCRIPT_DEBUG="${SCRIPT_DEBUG:-false}" # デバッグモード (trueで有効)
OCN_API_CODE="" # OCN API Code (プロンプトで入力)

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
MTU="1460" # デフォルトMTU
LEGACYMAP="1" # OpenWrt 21+ を想定
WAN_IF_NAME="wan"       # デフォルトの物理WANインターフェース名
WAN6_IF_NAME="wan6"     # デフォルトのIPv6 WANインターフェース名
MAP_IF_NAME="wanmap"    # MAPインターフェース名
LAN_IF_NAME="lan"       # デフォルトのLANインターフェース名

USER_IPV6_ADDR=""
USER_IPV6_HEXTETS=""

API_RULE_JSON=""

debug_log() {
    if [ "$SCRIPT_DEBUG" = "true" ]; then
        printf "DEBUG: %s\n" "$1" >&2
    fi
}

determine_ipv6_acquisition_method() {
    debug_log "Starting IPv6 acquisition method determination"
    
    if ! uci get network.wan6 >/dev/null 2>&1; then
        debug_log "wan6 interface not found, creating it"
        uci set network.wan6=interface
        uci set network.wan6.proto=dhcpv6
        uci set network.wan6.ifname=eth1
        uci commit network
        /etc/init.d/network restart
        sleep 30
    fi
    
    debug_log "Checking IPv6 connectivity"
    if ! ping -6 -c 1 -W 3 2001:4860:4860::8888 >/dev/null 2>&1 && \
       ! ping -6 -c 1 -W 3 2606:4700:4700::1111 >/dev/null 2>&1; then
        debug_log "IPv6 connectivity check failed"
        return 1
    fi
    
    local ipv6_addr=""
    if command -v network_get_ipaddr6 >/dev/null 2>&1; then
        network_get_ipaddr6 ipv6_addr "wan6"
    fi
    
    if [ -n "$ipv6_addr" ]; then
        debug_log "GUA address found: $ipv6_addr"
        USER_IPV6_ADDR="$ipv6_addr"
        MAPE_IPV6_ACQUISITION_METHOD="gua"
        return 0
    fi
    
    local ipv6_prefix=""
    if command -v network_get_prefix6 >/dev/null 2>&1; then
        network_get_prefix6 ipv6_prefix "wan6"
    fi
    
    if [ -n "$ipv6_prefix" ]; then
        debug_log "PD prefix found: $ipv6_prefix"
        USER_IPV6_ADDR="$ipv6_prefix"
        MAPE_IPV6_ACQUISITION_METHOD="pd"
        return 0
    fi
    
    debug_log "No IPv6 address or prefix found - line incompatible"
    printf "回線がMAP-Eに対応していません\n"
    return 1
}

check_ipv6_in_range() {
    local target_ipv6="$1"
    local prefix_ipv6="$2"
    local prefix_len="$3" 

    local target_hex=$(echo "$target_ipv6" | awk -F: '{
        result = ""
        zero_fill = 8 - NF
        for(i=1; i<=NF; i++) {
            if($i == "") {
                for(j=0; j<zero_fill; j++) result = result "0000"
                zero_fill = 0 
            } else {
                seg = $i
                while(length(seg) < 4) seg = "0" seg
                result = result seg
            }
        }
        while(length(result) < 32) result = result "0000"
        print toupper(substr(result, 1, 32))
    }')
    
    local prefix_hex=$(echo "$prefix_ipv6" | awk -F: '{
        result = ""
        zero_fill = 8 - NF
        for(i=1; i<=NF; i++) {
            if($i == "") {
                for(j=0; j<zero_fill; j++) result = result "0000"
                zero_fill = 0
            } else {
                seg = $i
                while(length(seg) < 4) seg = "0" seg
                result = result seg
            }
        }
        while(length(result) < 32) result = result "0000"
        print toupper(substr(result, 1, 32))
    }')
    
    local hex_chars=$(( (prefix_len + 3) / 4 ))
    
    local target_masked=$(echo "$target_hex" | cut -c1-"$hex_chars")
    local prefix_masked=$(echo "$prefix_hex" | cut -c1-"$hex_chars")
    
    [ "$target_masked" = "$prefix_masked" ]
}

get_ocn_rule_from_api() {
    local wan_iface="${1:-$WAN6_IF_NAME}"
    local current_user_ipv6_addr="$USER_IPV6_ADDR"
    local normalized_prefix=""
    local prefix_len_for_api="64"

    if [ -z "$OCN_API_CODE" ]; then
        printf "ERROR: OCN API Code is not set. Please provide it when prompted.\n" >&2
        return 1
    fi

    if [ -z "$current_user_ipv6_addr" ]; then
        printf "ERROR: USER_IPV6_ADDR is not set.\n" >&2
        return 1
    fi

    normalized_prefix=$(echo "$current_user_ipv6_addr" \
        | awk -F: '{printf "%s:%s:%s:%s::", $1, $2, $3, $4}')
    debug_log "Using IPv6 for API query: $normalized_prefix (derived from $current_user_ipv6_addr)"

    local api_url="https://rule.map.ocn.ad.jp/?ipv6Prefix=${normalized_prefix}"\
"&ipv6PrefixLength=${prefix_len_for_api}&code=${OCN_API_CODE}"
    debug_log "API URL: $api_url"

    local raw_json_response
    raw_json_response=$(wget -qO- "$api_url" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$raw_json_response" ]; then
        printf "ERROR: Failed to get API response or response is empty. URL: %s\n" \
               "$api_url" >&2
        if echo "$raw_json_response" | grep -q "Forbidden"; then
            printf "HINT: The API request was forbidden. Check if the OCN API Code is correct.\n" \
                   >&2
        fi
        return 1
    fi

    local json_response
    json_response=$(echo "$raw_json_response" \
        | sed -e 's/^v6plus(//' -e 's/);$//')
    if [ -z "$json_response" ]; then
        printf "ERROR: API response was empty after stripping v6plus() wrapper.\n" >&2
        return 1
    fi

    local temp_file="/tmp/mape_json_$$"
    echo "$json_response" > "$temp_file"

    local in_block=0
    local current_block=""
    local block_ipv6_prefix=""
    local block_prefix_len_str=""
    local block_prefix_len_num=0

    while IFS= read -r line; do
        case "$line" in
            *'{'*)
                in_block=1
                current_block="$line"
                block_ipv6_prefix=""
                block_prefix_len_str=""
                block_prefix_len_num=0
                continue
                ;;
        esac

        if [ "$in_block" -eq 1 ]; then
            current_block="${current_block}
$line"
            if echo "$line" | grep -q '"ipv6Prefix":'; then
                block_ipv6_prefix=$(echo "$line" \
                    | sed -n 's/.*"ipv6Prefix":\s*"\([^"]*\)".*/\1/p')
            fi
            if echo "$line" | grep -q '"ipv6PrefixLength":'; then
                block_prefix_len_str=$(echo "$line" \
                    | sed -n 's/.*"ipv6PrefixLength":\s*"\([^"]*\)".*/\1/p')
                if [ -n "$block_prefix_len_str" ] \
                   && [ "$block_prefix_len_str" -eq "$block_prefix_len_str" ] \
                   2>/dev/null; then
                    block_prefix_len_num=$((block_prefix_len_str))
                else
                    block_prefix_len_num=0
                fi
            fi

            case "$line" in
                *'}'*)
                    in_block=0
                    if [ -n "$block_ipv6_prefix" ] \
                       && [ "$block_prefix_len_num" -gt 0 ]; then
                        if check_ipv6_in_range \
                             "$normalized_prefix" \
                             "$block_ipv6_prefix" \
                             "$block_prefix_len_num"; then
                            debug_log "Found matching rule block: $current_block"
                            API_RULE_JSON="$current_block"
                            rm -f "$temp_file"
                            return 0
                        fi
                    fi
                    current_block=""
                    ;;
            esac
        fi
    done < "$temp_file"

    rm -f "$temp_file"
    printf "ERROR: No matching rule block found for your IPv6 prefix in API response.\n" >&2
    API_RULE_JSON=""
    return 1
}

parse_user_ipv6() {
    local ipv6_to_parse="$1"
    if [ -z "$ipv6_to_parse" ]; then
        debug_log "parse_user_ipv6: No IPv6 address provided to parse."
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

    local hextet_count=$(echo "$USER_IPV6_HEXTETS" | awk '{print NF}')
    if [ "$hextet_count" -ne 8 ]; then
        debug_log "parse_user_ipv6: Failed to parse IPv6 into 8 hextets. Got $hextet_count: '$USER_IPV6_HEXTETS' from '$ipv6_to_parse'"
        USER_IPV6_HEXTETS=""
        return 1
    fi

    local expanded_ipv6
    expanded_ipv6=$(echo "$USER_IPV6_HEXTETS" \
      | awk '{print $1":"$2":"$3":"$4":"$5":"$6":"$7":"$8}')
    debug_log "Parsed user IPv6 hextets: $USER_IPV6_HEXTETS"
    debug_log "Expanded IPv6 address: $expanded_ipv6"
    
    return 0
}

OK_calculate_mape_params() {
    if [ -z "$API_RULE_JSON" ]; then
        printf "ERROR: API_RULE_JSON is empty in calculate_mape_params.\n" >&2
        return 1
    fi
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        printf "ERROR: USER_IPV6_HEXTETS is empty in calculate_mape_params.\n" >&2
        return 1
    fi

    echo "DEBUG: API_RULE_JSON content:"
    echo "$API_RULE_JSON"
    echo "DEBUG: End of API_RULE_JSON"

    local api_br_ipv6_address api_ea_bit_length api_ipv4_prefix api_ipv4_prefix_length \
          api_ipv6_prefix_rule api_ipv6_prefix_length_rule api_psid_offset

    api_br_ipv6_address=$(echo "$API_RULE_JSON" | sed -n 's/.*"brIpv6Address":\s*"\([^"]*\)".*/\1/p')
    api_ea_bit_length=$(echo "$API_RULE_JSON"   | sed -n 's/.*"eaBitLength":\s*"\([^"]*\)".*/\1/p')
    api_ipv4_prefix=$(echo "$API_RULE_JSON"     | sed -n 's/.*"ipv4Prefix":\s*"\([^"]*\)".*/\1/p')
    api_ipv4_prefix_length=$(echo "$API_RULE_JSON" | sed -n 's/.*"ipv4PrefixLength":\s*"\([^"]*\)".*/\1/p')
    api_ipv6_prefix_rule=$(echo "$API_RULE_JSON"   | sed -n 's/.*"ipv6Prefix":\s*"\([^"]*\)".*/\1/p')
    api_ipv6_prefix_length_rule=$(echo "$API_RULE_JSON" | sed -n 's/.*"ipv6PrefixLength":\s*"\([^"]*\)".*/\1/p')
    api_psid_offset=$(echo "$API_RULE_JSON"    | sed -n 's/.*"psIdOffset":\s*"\([^"]*\)".*/\1/p')

    echo "DEBUG: Extracted values:"
    echo "  brIpv6Address: $api_br_ipv6_address"
    echo "  eaBitLength: $api_ea_bit_length"
    echo "  ipv4Prefix: $api_ipv4_prefix"
    echo "  ipv4PrefixLength: $api_ipv4_prefix_length"
    echo "  ipv6Prefix: $api_ipv6_prefix_rule"
    echo "  ipv6PrefixLength: $api_ipv6_prefix_length_rule"
    echo "  psIdOffset: $api_psid_offset"

    for var_val in "$api_ea_bit_length" \
                   "$api_ipv4_prefix_length" \
                   "$api_ipv6_prefix_length_rule" \
                   "$api_psid_offset"; do
        if [ -z "$var_val" ] || ! echo "$var_val" | grep -qE '^[0-9]+$'; then
            printf "ERROR: API parameter '%s' is not a valid number.\n" "$var_val" >&2
            return 1
        fi
    done
    for var_val in "$api_br_ipv6_address" "$api_ipv4_prefix" "$api_ipv6_prefix_rule"; do
        if [ -z "$var_val" ]; then
            printf "ERROR: Required API string parameter is empty.\n" >&2
            return 1
        fi
    done

    BR="$api_br_ipv6_address"
    IPV4_NET_PREFIX="$api_ipv4_prefix"
    IP4PREFIXLEN="$api_ipv4_prefix_length"
    IPV6_RULE_PREFIX="$api_ipv6_prefix_rule"
    IPV6_RULE_PREFIXLEN="$api_ipv6_prefix_length_rule"
    EALEN="$api_ea_bit_length"
    OFFSET="$api_psid_offset"

    local h0 h1 h2 h3 h4 h5 h6 h7
    read -r h0 h1 h2 h3 h4 h5 h6 h7 <<EOF
$USER_IPV6_HEXTETS
EOF

    local ipv4_suffix_len=$((32 - IP4PREFIXLEN))
    PSIDLEN=$((EALEN - ipv4_suffix_len))
    if [ "$PSIDLEN" -lt 0 ]; then
        printf "ERROR: Calculated PSIDLEN is negative (%s).\n" "$PSIDLEN" >&2
        return 1
    fi

    PSID=$(( ( (0x$h3) & 0x3F00) >> 8 ))

    local o1 o2 o3_base o4_base o3_val o4_val
    o1=$(echo "$IPV4_NET_PREFIX" | cut -d. -f1); o1=$((o1)) 2>/dev/null||o1=0
    o2=$(echo "$IPV4_NET_PREFIX" | cut -d. -f2); o2=$((o2)) 2>/dev/null||o2=0
    o3_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f3); o3_base=$((o3_base))2>/dev/null||o3_base=0
    o4_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f4); o4_base=$((o4_base))2>/dev/null||o4_base=0

    o3_val=$((o3_base | ( ( (0x$h2) & 0x03C0) >> 6 ) ))
    o4_val=$(( ( ( (0x$h2) & 0x003F) << 2 ) | ( ( (0x$h3) & 0xC000) >> 14 ) ))

    IPADDR="${o1}.${o2}.${o3_val}.${o4_val}"

    local ce_h3_masked
    ce_h3_masked=$(printf "%04x" "$(( 0x$h3 & 0xFF00 ))")
    local ce_h4
    ce_h4=$(printf "%04x" "$o1")
    local ce_h5
    ce_h5=$(printf "%04x" "$((o2 * 256 + o3_val))")
    local ce_h6
    ce_h6=$(printf "%04x" "$((o4_val * 256))")
    local ce_h7
    ce_h7=$(printf "%04x" "$((PSID * 256))")

    CE="${h0}:${h1}:${h2}:${ce_h3_masked}:${ce_h4}:${ce_h5}:${ce_h6}:${ce_h7}"

    return 0
}

calculate_mape_params() {
    if [ -z "$API_RULE_JSON" ]; then
        printf "ERROR: API_RULE_JSON is empty in calculate_mape_params.\n" >&2
        return 1
    fi
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        printf "ERROR: USER_IPV6_HEXTETS is empty in calculate_mape_params.\n" >&2
        return 1
    fi

    echo "DEBUG: API_RULE_JSON content:"
    echo "$API_RULE_JSON"
    echo "DEBUG: End of API_RULE_JSON"

    local api_br_ipv6_address api_ea_bit_length api_ipv4_prefix api_ipv4_prefix_length
    local api_ipv6_prefix_rule api_ipv6_prefix_length_rule api_psid_offset

    api_br_ipv6_address=$(echo "$API_RULE_JSON" | sed -n 's/.*"brIpv6Address":\s*"\([^"]*\)".*/\1/p')
    api_ea_bit_length=$(echo "$API_RULE_JSON"   | sed -n 's/.*"eaBitLength":\s*"\([^"]*\)".*/\1/p')
    api_ipv4_prefix=$(echo "$API_RULE_JSON"     | sed -n 's/.*"ipv4Prefix":\s*"\([^"]*\)".*/\1/p')
    api_ipv4_prefix_length=$(echo "$API_RULE_JSON" \
        | sed -n 's/.*"ipv4PrefixLength":\s*"\([^"]*\)".*/\1/p')
    api_ipv6_prefix_rule=$(echo "$API_RULE_JSON" \
        | sed -n 's/.*"ipv6Prefix":\s*"\([^"]*\)".*/\1/p')
    api_ipv6_prefix_length_rule=$(echo "$API_RULE_JSON" \
        | sed -n 's/.*"ipv6PrefixLength":\s*"\([^"]*\)".*/\1/p')
    api_psid_offset=$(echo "$API_RULE_JSON"    | sed -n 's/.*"psIdOffset":\s*"\([^"]*\)".*/\1/p')

    # validate numeric values
    for v in "$api_ea_bit_length" "$api_ipv4_prefix_length" \
              "$api_ipv6_prefix_length_rule" "$api_psid_offset"; do
        if ! printf "%s" "$v" | grep -qE '^[0-9]+$'; then
            printf "ERROR: API parameter '%s' is not a valid number.\n" "$v" >&2
            return 1
        fi
    done

    BR="$api_br_ipv6_address"
    IPV4_NET_PREFIX="$api_ipv4_prefix"
    IP4PREFIXLEN="$api_ipv4_prefix_length"
    IPV6_RULE_PREFIX="$api_ipv6_prefix_rule"
    IPV6_RULE_PREFIXLEN="$api_ipv6_prefix_length_rule"
    EALEN="$api_ea_bit_length"
    OFFSET="$api_psid_offset"

    # split user IPv6 into 8 hextets
    read -r h0 h1 h2 h3 h4 h5 h6 h7 <<EOF
$USER_IPV6_HEXTETS
EOF

    # calculate PSID length
    local ipv4_suffix_len=$((32 - IP4PREFIXLEN))
    PSIDLEN=$((EALEN - ipv4_suffix_len))
    if [ "$PSIDLEN" -lt 0 ]; then
        printf "ERROR: Calculated PSIDLEN is negative (%s).\n" "$PSIDLEN" >&2
        return 1
    fi

    # dynamic mask/shift for PSID extraction
    local shift=$((16 - OFFSET - PSIDLEN))
    local mask=$(( ((1 << PSIDLEN) - 1) << shift ))
    PSID=$(( ((0x$h3) & mask) >> shift ))

    # build IPv4 address
    local o1 o2 o3_base o4_base o3_val o4_val
    o1=$(echo "$IPV4_NET_PREFIX" | cut -d. -f1)
    o2=$(echo "$IPV4_NET_PREFIX" | cut -d. -f2)
    o3_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f3)
    o4_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f4)

    o3_val=$(( o3_base | ( ((0x$h2) & 0x03C0) >> 6 ) ))
    o4_val=$(( ( ((0x$h2) & 0x003F) << 2 ) | (((0x$h3) & 0xC000) >> 14) ))

    IPADDR="${o1}.${o2}.${o3_val}.${o4_val}"

    # build CE IPv6 address
    local ce_h3_masked ce_h4 ce_h5 ce_h6 ce_h7
    ce_h3_masked=$(printf "%04x" $((0x$h3 & 0xFF00)))
    ce_h4=$(printf "%04x" "$o1")
    ce_h5=$(printf "%04x" $((o2 * 256 + o3_val)))
    ce_h6=$(printf "%04x" $((o4_val * 256)))
    ce_h7=$(printf "%04x" $((PSID * 256)))

    CE="${h0}:${h1}:${h2}:${ce_h3_masked}:${ce_h4}:${ce_h5}:${ce_h6}:${ce_h7}"

    return 0
}

configure_openwrt_mape() {
    debug_log "Applying MAP-E configuration to OpenWrt..."

    uci -q batch <<-EOF
        set network.$MAP_IF_NAME=interface
        set network.$MAP_IF_NAME.proto='map'
        set network.$MAP_IF_NAME.maptype='map-e'
        set network.$MAP_IF_NAME.peeraddr='$BR'
        set network.$MAP_IF_NAME.ipaddr='$IPV4_NET_PREFIX'
        set network.$MAP_IF_NAME.ip4prefixlen='$IP4PREFIXLEN'
        set network.$MAP_IF_NAME.ip6prefix='$IPV6_RULE_PREFIX'
        set network.$MAP_IF_NAME.ip6prefixlen='$IPV6_RULE_PREFIXLEN'
        set network.$MAP_IF_NAME.ealen='$EALEN'
        set network.$MAP_IF_NAME.psidlen='$PSIDLEN'
        set network.$MAP_IF_NAME.offset='$OFFSET'
        set network.$MAP_IF_NAME.mtu='${MTU:-1460}'
        set network.$MAP_IF_NAME.encaplimit='ignore'
        set network.$MAP_IF_NAME.legacymap='${LEGACYMAP:-1}'
        set network.$MAP_IF_NAME.tunlink='$WAN6_IF_NAME'
EOF
    if [ $? -ne 0 ]; then
        printf "ERROR: Failed to apply uci batch for network.$MAP_IF_NAME.\n" >&2
        return 1
    fi

    uci -q batch <<-EOF
        set network.$WAN6_IF_NAME.proto='dhcpv6'
        set network.$WAN6_IF_NAME.reqaddress='try'
        set network.$WAN6_IF_NAME.reqprefix='auto' 
EOF
    if [ $? -ne 0 ]; then
        printf "ERROR: Failed to apply uci batch for network.$WAN6_IF_NAME.\n" >&2
        return 1
    fi
    
    uci -q batch <<-EOF
        set dhcp.$LAN_IF_NAME.ra='relay'
        set dhcp.$LAN_IF_NAME.dhcpv6='relay'
        set dhcp.$LAN_IF_NAME.ndp='relay'
EOF
    if [ $? -ne 0 ]; then
        printf "ERROR: Failed to apply uci batch for dhcp.$LAN_IF_NAME.\n" >&2
        return 1
    fi

    local wan_zone_idx
    wan_zone_idx=$(uci show firewall | grep -E "firewall\.@zone\[([0-9]+)\].name='wan'" | cut -d'[' -f2 | cut -d']' -f1 | head -n1)
    if [ -n "$wan_zone_idx" ]; then
        local current_networks
        current_networks=$(uci -q get firewall.@zone["$wan_zone_idx"].network)
        if ! echo "$current_networks" | grep -q "\b$MAP_IF_NAME\b"; then
            uci -q add_list firewall.@zone["$wan_zone_idx"].network="$MAP_IF_NAME"
        fi
        uci -q set firewall.@zone["$wan_zone_idx"].masq='1'
        uci -q set firewall.@zone["$wan_zone_idx"].mtu_fix='1'
    else
        printf "WARN: Firewall zone named 'wan' not found. Manual firewall configuration for '$MAP_IF_NAME' might be needed.\n" >&2
    fi

    if ! uci -q commit network; then
        printf "ERROR: Failed to commit network configuration.\n" >&2
        return 1
    fi
    if ! uci -q commit dhcp; then
        printf "ERROR: Failed to commit DHCP configuration.\n" >&2
        return 1
    fi
    if ! uci -q commit firewall; then
        printf "ERROR: Failed to commit firewall configuration.\n" >&2
        return 1
    fi

    printf "INFO: MAP-E UCI configuration applied successfully.\n"
    printf "INFO: You may need to restart network services (/etc/init.d/network restart) or reboot the device.\n"
    return 0
}

install_map_package() {
    local pkg_manager=""
    local is_installed=0
    
    if command -v opkg >/dev/null 2>&1; then
        pkg_manager="opkg"
    elif command -v apk >/dev/null 2>&1; then
        pkg_manager="apk"
    else
        printf "ERROR: No supported package manager found (opkg/apk).\n" >&2
        return 1
    fi
    
    case "$pkg_manager" in
        "opkg")
            if opkg list-installed | grep -q '^map '; then
                is_installed=1
            fi
            ;;
        "apk")
            if apk list -I 2>/dev/null | grep -q '^map-'; then
                is_installed=1
            fi
            ;;
    esac
    
    if [ "$is_installed" -eq 1 ]; then
        return 0
    fi
    
    printf "INFO: MAP package not found. Installing...\n"
    
    case "$pkg_manager" in
        "opkg")
            if ! opkg update; then
                printf "ERROR: Failed to update package list with opkg.\n" >&2
                return 1
            fi
            if ! opkg install map; then
                printf "ERROR: Failed to install MAP package with opkg.\n" >&2
                return 1
            fi
            ;;
        "apk")
            if ! apk update; then
                printf "ERROR: Failed to update package list with apk.\n" >&2
                return 1
            fi
            if ! apk add map; then
                printf "ERROR: Failed to install MAP package with apk.\n" >&2
                return 1
            fi
            ;;
    esac
    
    printf "INFO: MAP package installed successfully.\n"
    return 0
}

display_mape() {

    local ipv6_label
    case "$MAPE_IPV6_ACQUISITION_METHOD" in
        gua) ipv6_label="IPv6アドレス:" ;;
        pd)  ipv6_label="IPv6プレフィックス:"  ;;
        *)   ipv6_label="IPv6プレフィックス/アドレス:" ;;
    esac

    printf "\n"
    printf "------------------------------------------------------\n"
    printf "\n"   
    printf "%s %s/64\n" "$ipv6_label" "$USER_IPV6_ADDR"
    printf "\n"
    printf "• CE: %s\n" "$CE"
    printf "• IPv4アドレス: %s\n" "$IPADDR"
    
    printf "• ポート番号:\n"
    local shift_bits=$((16 - OFFSET))
    local psid_shift=$((16 - OFFSET - PSIDLEN))
    [ "$psid_shift" -lt 0 ] && psid_shift=0
    local range_size=$((1 << psid_shift))
    local max_blocks=$((1 << OFFSET))
    local last=$((max_blocks - 1))
    
    local line_items=0
    printf "    "
    
    for A in $(seq 1 "$last"); do
        local base=$((A << shift_bits))
        local part=$((PSID << psid_shift))
        local start=$((base | part))
        local end=$((start + range_size - 1))
        
        printf "%d-%d" "$start" "$end"
        line_items=$((line_items + 1))
        
        if [ "$line_items" -eq 3 ] && [ "$A" -lt "$last" ]; then
            printf "\n    "
            line_items=0
        elif [ "$A" -lt "$last" ]; then
            printf " "
        fi
    done
    printf "\n" 
    printf "• PSID: %s (10進)\n" "$PSID"
    printf "\n"
    printf "------------------------------------------------------\n"
    printf "注: 本当の値とは違う場合があります。\n"
    printf "\n"
    
    printf "option peeraddr %s\n" "$BR"
    printf "option ipaddr %s\n" "$IPV4_NET_PREFIX"
    printf "option ip4prefixlen %s\n" "$IP4PREFIXLEN"
    printf "option ip6prefix %s::\n" "$IPV6_RULE_PREFIX"
    printf "option ip6prefixlen %s\n" "$IPV6_RULE_PREFIXLEN"
    printf "option ealen %s\n" "$EALEN"
    printf "option psidlen %s\n" "$PSIDLEN"
    printf "option offset %s\n" "$OFFSET"
    printf "\n"
    printf "export LEGACY=1\n"
    printf "\n"
    printf "------------------------------------------------------\n"
    printf "\n"
    printf "(config-softwire)# map-version draft\n"
    printf "(config-softwire)# rule \033[34m<0-65535>\033[0m ipv4-prefix \033[34m%s/%s\033[0m ipv6-prefix \033[34m%s::/%s\033[0m [ea-length %s][psid-length %s [psid %s]] [offset %s] [forwarding]\n" \
           "$IPV4_NET_PREFIX" "$IP4PREFIXLEN" "$IPV6_RULE_PREFIX" "$IPV6_RULE_PREFIXLEN" "$EALEN" "$PSIDLEN" "$PSID" "$OFFSET"
    printf "\n"  
    printf "------------------------------------------------------\n"
    printf "\n"
    printf "Powered by config-softwire\n"
    printf "Press any key to apply and reboot...\n"
    read -r -n1 -s
    return 0
}

test_manual_ipv6_input() {
    printf "IPv6アドレスを入力してください: "
    if ! read USER_IPV6_ADDR_INPUT; then
        printf "ERROR: Failed to read IPv6 address.\n" >&2
        return 1
    fi
    
    if [ -z "$USER_IPV6_ADDR_INPUT" ]; then
        printf "ERROR: IPv6 address cannot be empty.\n" >&2
        return 1
    fi
    
    USER_IPV6_ADDR="$USER_IPV6_ADDR_INPUT"
    MAPE_IPV6_ACQUISITION_METHOD="manual"
    debug_log "Manual IPv6 address input: $USER_IPV6_ADDR"
    return 0
}

main() {
    if [ "$SCRIPT_DEBUG" = "true" ]; then
        printf "Script running in DEBUG mode.\n"
    fi

    if [ -f /lib/functions.sh ]; then
        . /lib/functions.sh
    else
        printf "ERROR: /lib/functions.sh not found. This script requires OpenWrt environment.\n" >&2
        return 1
    fi
    if [ -f /lib/functions/network.sh ]; then
        . /lib/functions/network.sh
    else
        printf "ERROR: /lib/functions/network.sh not found.\n" >&2
        return 1
    fi

    # 通常モード (コメントアウト)
    # if ! determine_ipv6_acquisition_method; then
    #     printf "FATAL: IPv6 acquisition method determination failed. Exiting.\n" >&2
    #     return 1
    # fi

    if [ -n "$1" ]; then
        OCN_API_CODE="$1"
        debug_log "OCN API Code received from argument."
    elif [ -z "$OCN_API_CODE" ]; then
        printf "\n"
        printf "OCN API コードを入力してください: "
        if ! read OCN_API_CODE_INPUT; then
            printf "\nERROR: Failed to read OCN API Code.\n" >&2
            return 1
        fi
        OCN_API_CODE="$OCN_API_CODE_INPUT"
        debug_log "OCN API Code received from prompt input."
    fi

    if [ -z "$OCN_API_CODE" ]; then
        printf "ERROR: OCN API Code was not provided. Exiting.\n" >&2
        return 1
    fi

    # テストモード (手動IPv6アドレス入力を先に実行)
    if ! test_manual_ipv6_input; then
        printf "FATAL: Failed to get manual IPv6 address. Exiting.\n" >&2
        return 1
    fi

    if ! get_ocn_rule_from_api "$WAN6_IF_NAME"; then
        printf "FATAL: Could not retrieve MAP-E rule from API. Exiting.\n" >&2
        return 1
    fi

    if ! install_map_package; then
        printf "FATAL: Failed to install MAP package. Exiting.\n" >&2
        return 1
    fi

    if [ -z "$USER_IPV6_ADDR" ]; then
        printf "FATAL: User IPv6 address was not set. Exiting.\n" >&2
        return 1
    fi
    if ! parse_user_ipv6 "$USER_IPV6_ADDR"; then
        printf "FATAL: Failed to parse user IPv6 address (%s). Exiting.\n" "$USER_IPV6_ADDR" >&2
        return 1
    fi

    if ! calculate_mape_params; then
        printf "FATAL: Failed to calculate MAP-E parameters. Exiting.\n" >&2
        return 1
    fi

    if ! display_mape; then
        printf "FATAL: Failed to display MAP-E parameters. Exiting.\n" >&2
        return 1
    fi
    
    return 0
}

main "$@"
