#!/bin/ash

# OpenWrt 19.07+ configuration
# Powered by config-softwir

SCRIPT_VERSION="2025.06.07-00-00"

OCN_API_CODE=""

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
WAN_IF_NAME="wan"
WAN6_IF_NAME="wan6"
MAP_IF_NAME="wanmap"
LAN_IF_NAME="lan"

USER_IPV6_ADDR=""
USER_IPV6_HEXTETS=""

API_RULE_JSON=""

determine_ipv6_acquisition_method() {

    if ! ping -6 -c 1 -W 3 2001:4860:4860::8888 >/dev/null 2>&1 && \
       ! ping -6 -c 1 -W 3 2606:4700:4700::1111 >/dev/null 2>&1; then
        return 1
    fi
    
    local ipv6_addr=""
    if command -v network_get_ipaddr6 >/dev/null 2>&1; then
        network_get_ipaddr6 ipv6_addr "wan6"
    fi
    
    if [ -n "$ipv6_addr" ]; then
        USER_IPV6_ADDR="$ipv6_addr"
        MAPE_IPV6_ACQUISITION_METHOD="gua"
        return 0
    fi
    
    local ipv6_prefix=""
    if command -v network_get_prefix6 >/dev/null 2>&1; then
        network_get_prefix6 ipv6_prefix "wan6"
    fi
    
    if [ -n "$ipv6_prefix" ]; then
        USER_IPV6_ADDR="$ipv6_prefix"
        MAPE_IPV6_ACQUISITION_METHOD="pd"
        return 0
    fi
    
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
    local key_for_decryption="$2"
    local current_user_ipv6_addr="$USER_IPV6_ADDR"
    local normalized_prefix=""
    local prefix_len_for_api="64"

    local decrypted_api_code="" 

    if [ -z "$current_user_ipv6_addr" ]; then
        return 1
    fi

    normalized_prefix=$(echo "$current_user_ipv6_addr" | awk -F: '{printf "%s:%s:%s:%s::", $1, $2, $3, $4}')

    local api_url
    local hex_xor_key=""
    local wget_rule_result

    if [ -z "$key_for_decryption" ]; then
        return 1
    fi

    api_url="https://rule.map.ocn.ad.jp/?ipv6Prefix=${normalized_prefix}&ipv6PrefixLength=${prefix_len_for_api}&code="
    
    local temp_stderr_file="/tmp/wget_initial_stderr_$$"
    local initial_wget_stdout_discarded 
    initial_wget_stdout_discarded=$(wget -6 -O - "$api_url" 2>"$temp_stderr_file")
    local initial_wget_exit_status=$?

    local initial_wget_stderr_content=""
    if [ -s "$temp_stderr_file" ]; then
        initial_wget_stderr_content=$(cat "$temp_stderr_file")
    fi
    rm -f "$temp_stderr_file"
    initial_wget_stdout_discarded=""

    if [ "$initial_wget_exit_status" -eq 0 ]; then
        initial_wget_stderr_content=""
        return 1
    fi
    
    local seed_for_xor_key=""
    seed_for_xor_key=$(printf '%s\n' "$initial_wget_stderr_content" | awk 'NR==3 {print $3}')
    initial_wget_stderr_content=""

    if [ -z "$seed_for_xor_key" ]; then
        key_for_decryption="" 
        return 1
    fi

    hex_xor_key=$(echo "$seed_for_xor_key" | \
        { \
            local extracted_str_from_sed_pipe
            local temp_hex_output_pipe=""
            local char_idx_pipe=1
            local current_char_pipe
            local char_ascii_val_pipe
            
            IFS= read -r extracted_str_from_sed_pipe || true 

            if [ -n "$extracted_str_from_sed_pipe" ]; then
                while [ "$char_idx_pipe" -le "${#extracted_str_from_sed_pipe}" ]; do
                    current_char_pipe=$(echo "$extracted_str_from_sed_pipe" | cut -c"$char_idx_pipe")
                    char_ascii_val_pipe=$(printf "%d" "'$current_char_pipe") 
                    temp_hex_output_pipe="${temp_hex_output_pipe}$(printf "%02x" "$char_ascii_val_pipe")"
                    char_idx_pipe=$((char_idx_pipe + 1))
                done
                echo "$temp_hex_output_pipe" 
            else
                echo "" 
            fi
        } \
    )
    seed_for_xor_key=""

    if [ -z "$hex_xor_key" ]; then
        key_for_decryption=""
        return 1
    fi
    
    decrypted_api_code=$(generate "$key_for_decryption" "$hex_xor_key" | tr -d '\n')
    local generate_exit_status=$?
    
    key_for_decryption="" 
    hex_xor_key=""

    if [ "$generate_exit_status" -ne 0 ] || [ -z "$decrypted_api_code" ]; then 
         decrypted_api_code="" 
         return 1
    fi
    
    if [ -z "$decrypted_api_code" ]; then
        return 1
    fi

    api_url="https://rule.map.ocn.ad.jp/?ipv6Prefix=${normalized_prefix}&ipv6PrefixLength=${prefix_len_for_api}&code=${decrypted_api_code}"
    
    local wget_stderr_file_rule="/tmp/wget_stderr_rule_$$"
    wget_rule_result=$(wget -6 -q -O- "$api_url" 2>"$wget_stderr_file_rule") 
    local rule_wget_status=$?
    
    decrypted_api_code=""

    local rule_wget_stderr_content=""
    if [ -s "$wget_stderr_file_rule" ]; then
        rule_wget_stderr_content=$(cat "$wget_stderr_file_rule")
    fi
    rm -f "$wget_stderr_file_rule"
    rule_wget_stderr_content=""
            
    if [ "$rule_wget_status" -ne 0 ] || [ -z "$wget_rule_result" ]; then
        wget_rule_result="" 
        return 1
    fi

    local json_response
    json_response=$(echo "$wget_rule_result" | sed -e 's/^v6plus(//' -e 's/);$//')
    wget_rule_result="" 

    if [ -z "$json_response" ]; then
        return 1
    fi

    API_RULE_JSON="" 
    local temp_file="/tmp/mape_json_$$"
    echo "$json_response" > "$temp_file"
    json_response=""

    local in_block=0; local current_block=""; local block_ipv6_prefix=""; local block_prefix_len_str=""; local block_prefix_len_num=0
    while IFS= read -r line; do
        case "$line" in *'{'*) in_block=1; current_block="$line"; block_ipv6_prefix=""; block_prefix_len_str=""; block_prefix_len_num=0; continue ;; esac
        if [ "$in_block" -eq 1 ]; then
            current_block="${current_block}\n$line"
            if echo "$line" | grep -q '"ipv6Prefix":'; then block_ipv6_prefix=$(echo "$line" | sed -n 's/.*"ipv6Prefix":\s*"\([^"]*\)".*/\1/p'); fi
            if echo "$line" | grep -q '"ipv6PrefixLength":'; then
                block_prefix_len_str=$(echo "$line" | sed -n 's/.*"ipv6PrefixLength":\s*"\([^"]*\)".*/\1/p')
                if [ -n "$block_prefix_len_str" ] && expr "$block_prefix_len_str" + 0 > /dev/null 2>&1; then
                    block_prefix_len_num=$((block_prefix_len_str))
                else block_prefix_len_num=0; fi
            fi
            case "$line" in
                *'}'*)
                    in_block=0
                    if [ -n "$block_ipv6_prefix" ] && [ "$block_prefix_len_num" -gt 0 ]; then
                        if check_ipv6_in_range "$normalized_prefix" "$block_ipv6_prefix" "$block_prefix_len_num"; then
                            API_RULE_JSON="$current_block"; 
                            rm -f "$temp_file"; 
                            current_block=""; block_ipv6_prefix=""; block_prefix_len_str="";
                            return 0 
                        fi
                    fi
                    current_block="" ;;
            esac
        fi
    done < "$temp_file"
    rm -f "$temp_file"
    current_block=""; block_ipv6_prefix=""; block_prefix_len_str="";

    return 1
}

generate() {
    local input_hex_encrypted="$1"
    local key_hex="$2"
    local decrypted_raw_output=""
    local i=0
    local j=0
    local input_len=${#input_hex_encrypted}
    local key_len=${#key_hex}

    if [ -z "$key_hex" ]; then
        return 1
    fi
    
    if [ "$input_len" -eq 0 ]; then
        return 1
    fi

    if [ $((input_len % 2)) -ne 0 ]; then
        return 1
    fi
    if [ $((key_len % 2)) -ne 0 ]; then
        return 1
    fi

    while [ "$i" -lt "$input_len" ]; do
        local current_input_byte_hex
        local current_key_byte_hex
        local dec_input
        local dec_key
        local xor_result_dec
        local result_char
        local printf_status_input
        local printf_status_key

        current_input_byte_hex=$(echo "$input_hex_encrypted" | cut -c $((i + 1))-$((i + 2)))
        current_key_byte_hex=$(echo "$key_hex" | cut -c $((j + 1))-$((j + 2)))

        dec_input=$(printf "%d" "0x$current_input_byte_hex" 2>/dev/null)
        printf_status_input=$?
        if [ "$printf_status_input" -ne 0 ]; then
            return 1
        fi

        dec_key=$(printf "%d" "0x$current_key_byte_hex" 2>/dev/null)
        printf_status_key=$?
        if [ "$printf_status_key" -ne 0 ]; then
            return 1
        fi
        
        xor_result_dec=$((dec_input ^ dec_key))
        result_char=$(printf "\\$(printf "%03o" "$xor_result_dec")")
        decrypted_raw_output="${decrypted_raw_output}${result_char}"
        
        i=$((i + 2))
        j=$((j + 2))
        if [ "$j" -ge "$key_len" ]; then
            j=0
        fi
    done
    
    echo -n "$decrypted_raw_output"
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

    local hextet_count=$(echo "$USER_IPV6_HEXTETS" | awk '{print NF}')
    if [ "$hextet_count" -ne 8 ]; then
        USER_IPV6_HEXTETS=""
        return 1
    fi

    local expanded_ipv6
    expanded_ipv6=$(echo "$USER_IPV6_HEXTETS" \
      | awk '{print $1":"$2":"$3":"$4":"$5":"$6":"$7":"$8}')
    
    return 0
}

calculate_mape_params() {
    if [ -z "$API_RULE_JSON" ]; then
        return 1
    fi
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        return 1
    fi

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
    API_RULE_JSON=""

    for v in "$api_ea_bit_length" "$api_ipv4_prefix_length" \
              "$api_ipv6_prefix_length_rule" "$api_psid_offset"; do
        if ! printf "%s" "$v" | grep -qE '^[0-9]+$'; then
            USER_IPV6_HEXTETS=""
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

    api_br_ipv6_address=""; api_ea_bit_length=""; api_ipv4_prefix=""; api_ipv4_prefix_length=""
    api_ipv6_prefix_rule=""; api_ipv6_prefix_length_rule=""; api_psid_offset=""

    read -r h0 h1 h2 h3 h4 h5 h6 h7 <<EOF
$USER_IPV6_HEXTETS
EOF
    USER_IPV6_HEXTETS=""

    local ipv4_suffix_len=$((32 - IP4PREFIXLEN))
    PSIDLEN=$((EALEN - ipv4_suffix_len))
    if [ "$PSIDLEN" -lt 0 ]; then
        return 1
    fi

    local shift=$((16 - OFFSET - PSIDLEN))
    local mask=$(( ((1 << PSIDLEN) - 1) << shift ))
    PSID=$(( ((0x$h3) & mask) >> shift ))

    local o1 o2 o3_base o4_base o3_val o4_val
    o1=$(echo "$IPV4_NET_PREFIX" | cut -d. -f1)
    o2=$(echo "$IPV4_NET_PREFIX" | cut -d. -f2)
    o3_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f3)
    o4_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f4)

    o3_val=$(( o3_base | ( ((0x$h2) & 0x03C0) >> 6 ) ))
    o4_val=$(( ( ((0x$h2) & 0x003F) << 2 ) | (((0x$h3) & 0xC000) >> 14) ))

    IPADDR="${o1}.${o2}.${o3_val}.${o4_val}"

    local ce_h3_masked ce_h4 ce_h5 ce_h6 ce_h7
    ce_h3_masked=$(printf "%04x" $((0x$h3 & 0xFF00)))
    ce_h4=$(printf "%04x" "$o1")
    ce_h5=$(printf "%04x" $((o2 * 256 + o3_val)))
    ce_h6=$(printf "%04x" $((o4_val * 256)))
    ce_h7=$(printf "%04x" $((PSID * 256)))

    CE="${h0}:${h1}:${h2}:${ce_h3_masked}:${ce_h4}:${ce_h5}:${ce_h6}:${ce_h7}"
    
    h0=""; h1=""; h2=""; h3=""; h4=""; h5=""; h6=""; h7=""
    o1=""; o2=""; o3_base=""; o4_base=""; o3_val=""; o4_val=""
    ce_h3_masked=""; ce_h4=""; ce_h5=""; ce_h6=""; ce_h7=""
    ipv4_suffix_len=""; shift=""; mask=""

    return 0
}

configure_openwrt_mape() {

    local WANMAP="${MAP_IF_NAME:-wanmap}"

    local ZONE_NO
    local wan_zone_name_to_find="wan"
    ZONE_NO=$(uci show firewall | grep -E "firewall\.@zone\[([0-9]+)\].name='$wan_zone_name_to_find'" | sed -n 's/firewall\.@zone\[\([0-9]*\)\].name=.*/\1/p' | head -n1)

    if [ -z "$ZONE_NO" ]; then
        ZONE_NO="1"
    fi

    local WAN_IF="${WAN_IF:-wan}"
    local WAN6_IF="${WAN6_IF:-wan6}"
    local LAN_IF="${LAN_IF:-lan}"

    local osversion=""
    if [ -f "/etc/openwrt_release" ]; then
        osversion=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d"'" -f2)
    else
        osversion="unknown"
    fi
    
    cp /etc/config/network /etc/config/network.map-e.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.map-e.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.map-e.bak 2>/dev/null
    
    uci -q set network.${WAN_IF}.disabled='1'
    uci -q set network.${WAN_IF}.auto='0'

    uci -q set dhcp.${LAN_IF}.ra='relay'
    uci -q set dhcp.${LAN_IF}.dhcpv6='relay'
    uci -q set dhcp.${LAN_IF}.ndp='relay'
    uci -q set dhcp.${LAN_IF}.force='1'

    uci -q set dhcp.${WAN6_IF}=dhcp
    uci -q set dhcp.${WAN6_IF}.interface="$WAN6_IF"
    uci -q set dhcp.${WAN6_IF}.master='1'
    uci -q set dhcp.${WAN6_IF}.ra='relay'
    uci -q set dhcp.${WAN6_IF}.dhcpv6='relay'
    uci -q set dhcp.${WAN6_IF}.ndp='relay'

    uci -q set network.${WAN6_IF}.proto='dhcpv6'
    uci -q set network.${WAN6_IF}.reqaddress='try'
    uci -q set network.${WAN6_IF}.reqprefix='auto' 
    
    if [ "$MAPE_IPV6_ACQUISITION_METHOD" = "gua" ]; then
        if [ -n "$IPV6PREFIX" ]; then
            uci -q set network.${WAN6_IF}.ip6prefix="${IPV6PREFIX}/64"
        else
            uci -q delete network.${WAN6_IF}.ip6prefix
        fi
    elif [ "$MAPE_IPV6_ACQUISITION_METHOD" = "pd" ]; then
        uci -q delete network.${WAN6_IF}.ip6prefix
    else
        uci -q delete network.${WAN6_IF}.ip6prefix
    fi

    uci -q set network.${WANMAP}=interface
    uci -q set network.${WANMAP}.proto='map'
    uci -q set network.${WANMAP}.maptype='map-e'
    uci -q set network.${WANMAP}.peeraddr="${BR}"
    uci -q set network.${WANMAP}.ipaddr="${IPV4_NET_PREFIX}"
    uci -q set network.${WANMAP}.ip4prefixlen="${IP4PREFIXLEN}"
    uci -q set network.${WANMAP}.ip6prefix="${IPV6_RULE_PREFIX}"
    uci -q set network.${WANMAP}.ip6prefixlen="${IP6PREFIXLEN}"
    uci -q set network.${WANMAP}.ealen="${EALEN}"
    uci -q set network.${WANMAP}.psidlen="${PSIDLEN}"
    uci -q set network.${WANMAP}.offset="${OFFSET}"
    uci -q set network.${WANMAP}.mtu="${MTU}"
    uci -q set network.${WANMAP}.encaplimit='ignore'

    if echo "$osversion" | grep -q "^19"; then
        uci -q delete network.${WANMAP}.tunlink
        uci -q add_list network.${WANMAP}.tunlink="${WAN6_IF}"
        uci -q delete network.${WANMAP}.legacymap
    else
        uci -q set dhcp.${WAN6_IF}.ignore='1'
        uci -q set network.${WANMAP}.legacymap='1'
        uci -q set network.${WANMAP}.tunlink="${WAN6_IF}"
    fi
    
    local current_wan_networks
    current_wan_networks=$(uci -q get firewall.@zone[${ZONE_NO}].network 2>/dev/null)

    if echo "$current_wan_networks" | grep -q "\b${WAN_IF}\b"; then
        uci -q del_list firewall.@zone[${ZONE_NO}].network="${WAN_IF}"
    fi

    if ! echo "$current_wan_networks" | grep -q "\b${WANMAP}\b"; then
        uci -q add_list firewall.@zone[${ZONE_NO}].network="${WANMAP}"
    fi
    uci -q set firewall.@zone[${ZONE_NO}].masq='1'
    uci -q set firewall.@zone[${ZONE_NO}].mtu_fix='1'
    
    local commit_failed=0
    local commit_errors=""

    uci -q commit network
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}network "
    fi

    uci -q commit dhcp
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}dhcp "
    fi
    
    uci -q commit firewall
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}firewall "
    fi

    if [ "$commit_failed" -eq 1 ]; then
        return 1
    fi
    
    printf "MAP-E UCI設定が正常に適用されました。\n"
    
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
            opkg update && opkg install map
            ;;
        "apk")
            apk list -I 2>/dev/null | grep -q '^map-' && return 0
            apk update && apk add map
            ;;
    esac
}

display_mape() {

    local ipv6_label
    case "$MAPE_IPV6_ACQUISITION_METHOD" in
        gua) ipv6_label="IPv6アドレス:" ;;
        pd)  ipv6_label="IPv6プレフィックス:"  ;;
        *)   ipv6_label="IPv6プレフィックス/アドレス:" ;;
    esac

    printf "\n"
    printf "\033[1mconfig-softwire\033[0m %s\n"
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
    
    for A in $(seq 1 "$last"); do
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
    printf "\033[1m注: PCN（プロビジョニング・コントロール・ネーム）APIの値です。\033[0m\n"
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

    return 0
}

ocn_main() {
    if [ -f /lib/functions.sh ]; then
        . /lib/functions.sh
        . /lib/functions/network.sh
    else
        printf "このスクリプトはOpenWrt環境でのみ動作します。\n" >&2
        return 1
    fi

    if ! determine_ipv6_acquisition_method; then
        printf "この回線はMAP-Eに対応していません。\n" >&2
        return 1
    fi

    if [ -n "$1" ]; then
        OCN_API_CODE="$1"
    elif [ -z "$OCN_API_CODE" ]; then
        printf "\nOCN APIコードを入力してください: "
        if ! read OCN_API_CODE_INPUT; then
            printf "\nエラー: OCN APIコードの入力に失敗しました。\n" >&2
            return 1
        fi
        OCN_API_CODE="$OCN_API_CODE_INPUT"
    fi

    if [ -z "$OCN_API_CODE" ]; then
        printf "OCN APIコードが指定されていません。終了します。\n" >&2
        return 1
    fi

    if ! get_ocn_rule_from_api "$WAN6_IF_NAME" "$OCN_API_CODE"; then
        printf "MAP-EルールをAPIから取得できませんでした。終了します。\n" >&2
        return 1
    fi

    if ! install_map_package; then
        printf "MAPパッケージのインストールに失敗しました。終了します。\n" >&2
        return 1
    fi

    if [ -z "$USER_IPV6_ADDR" ]; then
        printf "ユーザーのIPv6アドレスが設定されていません。終了します。\n" >&2
        return 1
    fi
    if ! parse_user_ipv6 "$USER_IPV6_ADDR"; then
        printf "ユーザーIPv6アドレス(%s)のパースに失敗しました。終了します。\n" "$USER_IPV6_ADDR" >&2
        return 1
    fi

    if ! calculate_mape_params; then
        printf "MAP-Eパラメータの計算に失敗しました。終了します。\n" >&2
        return 1
    fi

    if ! display_mape; then
        printf "MAP-Eパラメータ表示に失敗しました。終了します。\n" >&2
        return 1
    fi

    # if ! configure_openwrt_mape; then
    #     printf "MAP-E設定の適用に失敗しました。終了します。\n" >&2
    #     return 1
    # fi

    # printf "何かキーを押すと再起動します。\n"
    # read -r -n1 -s
    # reboot

    return 0
}

ocn_main "$@"
