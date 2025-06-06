#!/bin/ash

# --- Global Settings ---
SCRIPT_VERSION="0.1.0-ocn" # 新しいスクリプト用のバージョン
SCRIPT_DEBUG="${SCRIPT_DEBUG:-false}" # デバッグモード (trueで有効)
OCN_API_CODE="" # OCN API Code (プロンプトで入力)

# MAP-E設定パラメータ用グローバル変数 (calculate_mape_paramsで設定)
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

# ユーザーのIPv6情報用グローバル変数
USER_IPV6_ADDR=""
USER_IPV6_HEXTETS="" # h0 h1 h2 h3 h4 h5 h6 h7 (スペース区切り)

# APIから取得したルールJSON用グローバル変数
API_RULE_JSON=""

# --- Helper Functions ---

# デバッグメッセージ出力関数
debug_log() {
    if [ "$SCRIPT_DEBUG" = "true" ]; then
        printf "DEBUG: %s\n" "$1" >&2
    fi
}

# --- Core Functions ---

# IPv6取得方法を判定してUSER_IPV6_ADDRとMAPE_IPV6_ACQUISITION_METHODを設定する関数
determine_ipv6_acquisition_method() {
    debug_log "Starting IPv6 acquisition method determination"
    
    # wan6インターフェース存在確認
    if ! uci get network.wan6 >/dev/null 2>&1; then
        debug_log "wan6 interface not found, creating it"
        uci set network.wan6=interface
        uci set network.wan6.proto=dhcpv6
        uci set network.wan6.ifname=eth1
        uci commit network
        /etc/init.d/network restart
        sleep 30
    fi
    
    # 疎通確認
    debug_log "Checking IPv6 connectivity"
    if ! ping -6 -c 1 -W 3 2001:4860:4860::8888 >/dev/null 2>&1 && \
       ! ping -6 -c 1 -W 3 2606:4700:4700::1111 >/dev/null 2>&1; then
        debug_log "IPv6 connectivity check failed"
        return 1
    fi
    
    # GUA判定（優先）
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
    
    # PDフォールバック
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
    
    # 回線不適合
    debug_log "No IPv6 address or prefix found - line incompatible"
    printf "回線がMAP-Eに対応していません\n"
    return 1
}

# IPv6アドレスが指定されたプレフィックス範囲内かチェック（ビット単位）
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
    
    local hex_digits_to_compare=$(( (prefix_len + 3) / 4 ))
    local target_masked=$(echo "$target_hex" | cut -c1-"$hex_digits_to_compare")
    local prefix_masked=$(echo "$prefix_hex" | cut -c1-"$hex_digits_to_compare")
    
    if [ $((prefix_len % 4)) -eq 0 ]; then
        [ "$target_masked" = "$prefix_masked" ]
        return $?
    fi

    if [ "$hex_digits_to_compare" -eq 0 ]; then
         [ "$target_hex" = "$prefix_hex" ] 
         return $?
    fi

    local last_target_char=$(echo "$target_masked" | awk '{print substr($0, length($0))}')
    local last_prefix_char=$(echo "$prefix_masked" | awk '{print substr($0, length($0))}')
    
    local last_target_dec=$(printf "%d" "0x${last_target_char}")
    local last_prefix_dec=$(printf "%d" "0x${last_prefix_char}")
    
    local remaining_bits=$(( prefix_len % 4 ))
    local bit_mask=0
    if [ "$remaining_bits" -eq 1 ]; then bit_mask=8;
    elif [ "$remaining_bits" -eq 2 ]; then bit_mask=12;
    elif [ "$remaining_bits" -eq 3 ]; then bit_mask=14;
    fi
    
    if [ $((last_target_dec & bit_mask)) -ne $((last_prefix_dec & bit_mask)) ]; then
        return 1
    fi
    
    return 0
}

# マッチするJSONブロックを抽出
get_matching_json_blocks() {
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
    
    normalized_prefix=$(echo "$current_user_ipv6_addr" | awk -F: '{printf "%s:%s:%s:%s::", $1, $2, $3, $4}')
    debug_log "Using IPv6 for API query: $normalized_prefix (derived from $current_user_ipv6_addr)"
    
    local api_url="https://rule.map.ocn.ad.jp/?ipv6Prefix=${normalized_prefix}&ipv6PrefixLength=${prefix_len_for_api}&code=${OCN_API_CODE}"
    debug_log "API URL: $api_url"
    local raw_json_response
    raw_json_response=$(wget -qO- "$api_url" 2>/dev/null) 
    
    if [ $? -ne 0 ] || [ -z "$raw_json_response" ]; then
        printf "ERROR: Failed to get API response or response is empty. URL: %s\n" "$api_url" >&2
        if echo "$raw_json_response" | grep -q "Forbidden"; then
             printf "HINT: The API request was forbidden. Check if the OCN API Code is correct.\n" >&2
        fi
        return 1
    fi
    
    local json_response
    json_response=$(echo "$raw_json_response" | sed -e 's/^v6plus(//' -e 's/);$//')
    
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
                current_block="{" 
                block_ipv6_prefix=""
                block_prefix_len_str=""
                block_prefix_len_num=0
                continue
                ;;
        esac
        
        if [ "$in_block" -eq 1 ]; then
            current_block="${current_block}${line}" 
            
            if echo "$line" | grep -q '"ipv6Prefix":'; then
                 block_ipv6_prefix=$(echo "$line" | sed -n 's/.*"ipv6Prefix":\s*"\([^"]*\)".*/\1/p')
            fi
            if echo "$line" | grep -q '"ipv6PrefixLength":'; then
                block_prefix_len_str=$(echo "$line" | sed -n 's/.*"ipv6PrefixLength":\s*"\([^"]*\)".*/\1/p')
                if [ -n "$block_prefix_len_str" ] && [ "$block_prefix_len_str" -eq "$block_prefix_len_str" ] 2>/dev/null; then
                    block_prefix_len_num=$((block_prefix_len_str))
                else
                    block_prefix_len_num=0
                fi
            fi
            
            case "$line" in
                *'}'*)
                    in_block=0
                    if [ -n "$block_ipv6_prefix" ] && [ "$block_prefix_len_num" -gt 0 ]; then
                        if check_ipv6_in_range "$normalized_prefix" "$block_ipv6_prefix" "$block_prefix_len_num"; then
                            debug_log "Found matching rule block: $current_block"
                            API_RULE_JSON="$current_block"
                            rm -f "$temp_file"
                            return 0
                        else
                            debug_log "Rule block $block_ipv6_prefix/$block_prefix_len_num did not match user prefix $normalized_prefix"
                        fi
                    else
                        debug_log "Skipping block due to missing prefix or length: $current_block"
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

# ユーザーのIPv6アドレスを解析してヘキステットに分解する関数
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

    debug_log "Parsed user IPv6 hextets: $USER_IPV6_HEXTETS (from $ipv6_to_parse)"
    return 0
}

# APIから取得したJSONルールとユーザーIPv6からMAP-Eパラメータを計算する
calculate_mape_params() {
    if [ -z "$API_RULE_JSON" ]; then
        printf "ERROR: API_RULE_JSON is empty in calculate_mape_params.\n" >&2
        return 1
    fi
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        printf "ERROR: USER_IPV6_HEXTETS is empty in calculate_mape_params.\n" >&2
        return 1
    fi

    debug_log "Calculating MAP-E parameters..."

    local api_br_ipv6_address api_ea_bit_length api_ipv4_prefix api_ipv4_prefix_length \
          api_ipv6_prefix_rule api_ipv6_prefix_length_rule api_psid_offset

    api_br_ipv6_address=$(echo "$API_RULE_JSON" | sed -n 's/.*"brIpv6Address":\s*"\([^"]*\)".*/\1/p')
    api_ea_bit_length=$(echo "$API_RULE_JSON" | sed -n 's/.*"eaBitLength":\s*"\([^"]*\)".*/\1/p')
    api_ipv4_prefix=$(echo "$API_RULE_JSON" | sed -n 's/.*"ipv4Prefix":\s*"\([^"]*\)".*/\1/p')
    api_ipv4_prefix_length=$(echo "$API_RULE_JSON" | sed -n 's/.*"ipv4PrefixLength":\s*"\([^"]*\)".*/\1/p')
    api_ipv6_prefix_rule=$(echo "$API_RULE_JSON" | sed -n 's/.*"ipv6Prefix":\s*"\([^"]*\)".*/\1/p')
    api_ipv6_prefix_length_rule=$(echo "$API_RULE_JSON" | sed -n 's/.*"ipv6PrefixLength":\s*"\([^"]*\)".*/\1/p')
    api_psid_offset=$(echo "$API_RULE_JSON" | sed -n 's/.*"psIdOffset":\s*"\([^"]*\)".*/\1/p')

    for var_val in "$api_ea_bit_length" "$api_ipv4_prefix_length" "$api_ipv6_prefix_length_rule" "$api_psid_offset"; do
        if [ -z "$var_val" ] || ! echo "$var_val" | grep -qE '^[0-9][0-9]*$'; then
            printf "ERROR: API parameter '%s' is not a valid non-negative number.\n" "$var_val" >&2
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
    local temp_hextets="$USER_IPV6_HEXTETS"
    read -r h0 h1 h2 h3 h4 h5 h6 h7 <<EOF
$temp_hextets
EOF

    local ipv4_suffix_len=$((32 - IP4PREFIXLEN))
    if [ "$ipv4_suffix_len" -lt 0 ]; then
        printf "ERROR: Calculated ipv4_suffix_len is negative (%s).\n" "$ipv4_suffix_len" >&2
        return 1
    fi
    PSIDLEN=$((EALEN - ipv4_suffix_len))
    if [ "$PSIDLEN" -lt 0 ]; then
        printf "ERROR: Calculated PSIDLEN is negative (%s). EALEN=%s, IPv4SuffixLen=%s\n" "$PSIDLEN" "$EALEN" "$ipv4_suffix_len" >&2
        return 1
    fi

    if [ "$OFFSET" -eq 6 ] && [ "$EALEN" -eq 20 ] && \
       [ "$IP4PREFIXLEN" -eq 18 ] && [ "$PSIDLEN" -eq 6 ]; then
        
        PSID=$(( ( (0x$h3) & 0x3F00) >> 8 ))

        local o1=$(echo "$IPV4_NET_PREFIX" | cut -d. -f1)
        local o2=$(echo "$IPV4_NET_PREFIX" | cut -d. -f2)
        local o3_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f3)
        local o4_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f4)
        o1=$((o1)) 2>/dev/null || o1=0
        o2=$((o2)) 2>/dev/null || o2=0
        o3_base=$((o3_base)) 2>/dev/null || o3_base=0
        o4_base=$((o4_base)) 2>/dev/null || o4_base=0

        local suffix_o3_part=$(( ( (0x$h2) & 0x03C0) >> 6 ))
        local o3_val=$((o3_base | suffix_o3_part))

        local suffix_o4_part1=$(( ( (0x$h2) & 0x003F) << 2 ))
        local suffix_o4_part2=$(( ( (0x$h3) & 0xC000) >> 14 ))
        local o4_val=$((o4_base | suffix_o4_part1 | suffix_o4_part2))
        
        IPADDR="${o1}.${o2}.${o3_val}.${o4_val}"
    else
        printf "WARN: Calculation logic for the provided API parameters (OFFSET=%s, EALEN=%s, IP4PREFIXLEN=%s, PSIDLEN=%s) is not explicitly defined. IPADDR and PSID might be incorrect.\n" "$OFFSET" "$EALEN" "$IP4PREFIXLEN" "$PSIDLEN" >&2
        PSID=0
        IPADDR="$IPV4_NET_PREFIX"
    fi

    local ce_h0="$h0"
    local ce_h1="$h1"
    local ce_h2="$h2"
    local ce_h3="$h3"
    
    local ip_o1=$(echo "$IPADDR" | cut -d. -f1); ip_o1=$((ip_o1)) 2>/dev/null || ip_o1=0
    local ip_o2=$(echo "$IPADDR" | cut -d. -f2); ip_o2=$((ip_o2)) 2>/dev/null || ip_o2=0
    local ip_o3=$(echo "$IPADDR" | cut -d. -f3); ip_o3=$((ip_o3)) 2>/dev/null || ip_o3=0
    local ip_o4=$(echo "$IPADDR" | cut -d. -f4); ip_o4=$((ip_o4)) 2>/dev/null || ip_o4=0

    local ce_h4=$(printf %04x "$ip_o1")
    local ce_h5=$(printf %04x "$(( (ip_o2 << 8) | ip_o3 ))")
    local ce_h6=$(printf %04x "$(( ip_o4 << 8 ))")
    local ce_h7=$(printf %04x "$(( PSID << 8 ))")

    CE="${ce_h0}:${ce_h1}:${ce_h2}:${ce_h3}:${ce_h4}:${ce_h5}:${ce_h6}:${ce_h7}"
    
    return 0
}

# MAP-E設定をOpenWrtに適用する関数
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
    
    # パッケージマネージャーの判定
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

# MAP-E設定情報を表示する関数
display_mape() {
    printf "\n"
    printf "プレフィックス情報:\n"
    local ipv6_label
    case "$MAPE_IPV6_ACQUISITION_METHOD" in
        gua)
            ipv6_label="IPv6アドレス:"
            ;;
        pd)
            ipv6_label="IPv6プレフィックス:"
            ;;
        *)
            ipv6_label="IPv6プレフィックスまたはアドレス:"
            ;;
    esac
    printf "  %s %s\n" "$ipv6_label" "$USER_IPV6_ADDR"
    printf "  CE: %s\n" "$CE"
    printf "  IPv4アドレス: %s\n" "$IPADDR"
    printf "  PSID (10進数): %s\n" "$PSID"

    printf "\n"
    printf "注意: 実際の値は異なる可能性があります\n"
    
    printf "\n"
    printf "OpenWrt設定値:\n"
    printf "  option peeraddr '%s'\n" "$BR"
    printf "  option ipaddr %s\n" "$IPV4_NET_PREFIX"
    printf "  option ip4prefixlen '%s'\n" "$IP4PREFIXLEN"
    printf "  option ip6prefix '%s::'\n" "$IPV6_RULE_PREFIX"
    printf "  option ip6prefixlen '%s'\n" "$IPV6_RULE_PREFIXLEN"
    printf "  option ealen '%s'\n" "$EALEN"
    printf "  option psidlen '%s'\n" "$PSIDLEN"
    printf "  option offset '%s'\n" "$OFFSET"
    printf "\n"
    printf "  export LEGACY=1\n"

    local max_port_blocks=$(( (1 << OFFSET) ))
    local ports_per_block=$(( 1 << (16 - OFFSET - PSIDLEN) ))
    local total_ports=$(( ports_per_block * ((1 << OFFSET) - 1) )) 

    printf "\n"
    printf "ポート情報:\n"
    printf "  利用可能なポート数: %s\n" "$total_ports"

    printf "\n"
    printf "ポート範囲:\n"
    
    local shift_bits=$(( 16 - OFFSET ))
    local psid_shift=$(( 16 - OFFSET - PSIDLEN ))
    if [ "$psid_shift" -lt 0 ]; then
        psid_shift=0
    fi
    local port_range_size=$(( 1 << psid_shift ))
    local port_max_index=$(( (1 << OFFSET) - 1 ))
    local line_buffer=""
    local items_in_line=0
    local max_items_per_line=3
    
    for A in $(seq 1 "$port_max_index"); do
        local port_base=$(( A << shift_bits ))
        local psid_part=$(( PSID << psid_shift ))
        local port_start_val=$(( port_base | psid_part ))
        local port_end_val=$(( port_start_val + port_range_size - 1 ))
        
        if [ "$items_in_line" -eq 0 ]; then
            line_buffer="${port_start_val}-${port_end_val}"
        else
            line_buffer="${line_buffer} ${port_start_val}-${port_end_val}"
        fi
        
        items_in_line=$((items_in_line + 1))
        
        if [ "$items_in_line" -ge "$max_items_per_line" ] || [ "$A" -eq "$port_max_index" ]; then
            printf "  %s\n" "$line_buffer"
            line_buffer=""
            items_in_line=0
        fi
    done

    printf "\n"
    printf "Powered by config-softwire\n"
    printf "\n"
    printf "MAP-Eパラメータの計算が成功しました。\n"
    printf "何かキーを押すと設定を適用して再起動します...\n"
    read -r -n 1 -s
    
    return 0
}

# メイン処理
main() {
    SCRIPT_DEBUG="true"
    if [ "$SCRIPT_DEBUG" = "true" ]; then
        printf "INFO: Script running in DEBUG mode.\n"
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

    if ! determine_ipv6_acquisition_method; then
        printf "FATAL: IPv6 acquisition method determination failed. Exiting.\n" >&2
        return 1
    fi
    printf "INFO: IPv6 acquisition method determined: %s\n" "$MAPE_IPV6_ACQUISITION_METHOD"

    if [ -n "$1" ]; then
        OCN_API_CODE="$1"
        debug_log "OCN API Code received from argument."
    elif [ -z "$OCN_API_CODE" ]; then
        printf "Please enter your OCN API Code: "
        if ! read OCN_API_CODE_INPUT; then
            printf "\nERROR: Failed to read OCN API Code.\n" >&2
            return 1
        fi
        OCN_API_CODE="$OCN_API_CODE_INPUT"
        printf "\n"
        debug_log "OCN API Code received from prompt input."
    fi

    if [ -z "$OCN_API_CODE" ]; then
        printf "ERROR: OCN API Code was not provided. Exiting.\n" >&2
        return 1
    fi

    if ! get_matching_json_blocks "$WAN6_IF_NAME"; then
        printf "FATAL: Could not retrieve MAP-E rule from API. Exiting.\n" >&2
        return 1
    fi
    printf "INFO: Successfully retrieved MAP-E rule from API.\n"

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
    printf "INFO: Successfully parsed user IPv6 address.\n"

    if ! calculate_mape_params; then
        printf "FATAL: Failed to calculate MAP-E parameters. Exiting.\n" >&2
        return 1
    fi
    printf "INFO: Successfully calculated MAP-E parameters.\n"

    # if ! configure_openwrt_mape; then
    #     printf "FATAL: Failed to apply MAP-E configuration to OpenWrt. Exiting.\n" >&2
    #     return 1
    # fi
    printf "INFO: OpenWrt configuration skipped for testing.\n"

    printf "INFO: OCN MAP-E setup script finished successfully.\n"
    
    return 0
}

# --- スクリプト実行 ---
main "$@"
