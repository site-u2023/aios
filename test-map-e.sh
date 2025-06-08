#!/bin/ash

SCRIPT_VERSION="2025.06.08-00-00"

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
STATIC_API_RULE_LINE=""
MAPE_IPV6_ACQUISITION_METHOD=""
WAN6_PREFIX=""

map_rules_data() {
    cat << EOF
2001:380:A120::9,22,153.240.0.0,16,2400:4050:0000::,34,6
2001:380:A120::9,21,153.241.0.0,17,2400:4050:4000::,35,6
2001:380:A120::9,21,153.241.128.0,17,2400:4050:6000::,35,6
2001:380:A120::9,23,153.242.0.0,15,2400:4050:8000::,33,6
2001:380:A120::9,21,122.26.0.0,17,2400:4051:0000::,35,6
2001:380:A120::9,20,114.146.64.0,18,2400:4051:2000::,36,6
2001:380:A120::9,20,114.148.192.0,18,2400:4051:3000::,36,6
2001:380:A120::9,20,114.150.192.0,18,2400:4051:4000::,36,6
2001:380:A120::9,20,114.163.64.0,18,2400:4051:5000::,36,6
2001:380:A120::9,20,114.163.128.0,18,2400:4051:6000::,36,6
2001:380:A120::9,20,114.167.64.0,18,2400:4051:7000::,36,6
2001:380:A120::9,20,114.172.192.0,18,2400:4051:8000::,36,6
2001:380:A120::9,20,114.177.64.0,18,2400:4051:9000::,36,6
2001:380:A120::9,20,118.0.64.0,18,2400:4051:A000::,36,6
2001:380:A120::9,20,118.7.64.0,18,2400:4051:B000::,36,6
2001:380:A120::9,20,118.8.192.0,18,2400:4051:C000::,36,6
2001:380:A120::9,20,118.9.0.0,18,2400:4051:D000::,36,6
2001:380:A120::9,20,123.218.64.0,18,2400:4051:E000::,36,6
2001:380:A120::9,20,123.220.128.0,18,2400:4051:F000::,36,6
2001:380:A120::9,20,123.225.192.0,18,2400:4052:0000::,36,6
2001:380:A120::9,20,153.134.0.0,18,2400:4052:1000::,36,6
2001:380:A120::9,20,153.139.128.0,18,2400:4052:2000::,36,6
2001:380:A120::9,20,153.151.64.0,18,2400:4052:3000::,36,6
2001:380:A120::9,20,153.170.64.0,18,2400:4052:4000::,36,6
2001:380:A120::9,20,153.170.192.0,18,2400:4052:5000::,36,6
2001:380:A120::9,19,61.127.128.0,19,2400:4052:6000::,37,6
2001:380:A120::9,19,114.146.0.0,19,2400:4052:6800::,37,6
2001:380:A120::9,19,114.146.128.0,19,2400:4052:7000::,37,6
2001:380:A120::9,19,114.148.64.0,19,2400:4052:7800::,37,6
2001:380:A120::9,19,114.148.160.0,19,2400:4052:8000::,37,6
2001:380:A120::9,19,114.149.0.0,19,2400:4052:8800::,37,6
2001:380:A120::9,19,114.150.160.0,19,2400:4052:9000::,37,6
2001:380:A120::9,19,114.158.0.0,19,2400:4052:9800::,37,6
2001:380:A120::9,21,153.193.0.0,17,2400:4052:A000::,35,6
2001:380:A120::9,20,153.165.192.0,18,2400:4052:C000::,36,6
2001:380:A120::9,18,180.49.0.0,20,2400:4052:D000::,38,6
2001:380:A120::9,18,180.49.16.0,20,2400:4052:D400::,38,6
2001:380:A120::9,18,180.49.32.0,20,2400:4052:D800::,38,6
2001:380:A120::9,18,180.49.48.0,20,2400:4052:DC00::,38,6
2001:380:A120::9,18,180.49.64.0,20,2400:4052:E000::,38,6
2001:380:A120::9,18,180.49.80.0,20,2400:4052:E400::,38,6
2001:380:A120::9,18,180.49.96.0,20,2400:4052:E800::,38,6
2001:380:A120::9,18,180.49.112.0,20,2400:4052:EC00::,38,6
2001:380:A120::9,19,114.162.128.0,19,2400:4053:0000::,37,6
2001:380:A120::9,19,114.163.0.0,19,2400:4053:0800::,37,6
2001:380:A120::9,19,114.165.224.0,19,2400:4053:1000::,37,6
2001:380:A120::9,19,114.167.192.0,19,2400:4053:1800::,37,6
2001:380:A120::9,19,114.177.128.0,19,2400:4053:2000::,37,6
2001:380:A120::9,19,114.178.224.0,19,2400:4053:2800::,37,6
2001:380:A120::9,19,118.1.0.0,19,2400:4053:3000::,37,6
2001:380:A120::9,19,118.3.192.0,19,2400:4053:3800::,37,6
2001:380:A120::9,19,118.6.64.0,19,2400:4053:4000::,37,6
2001:380:A120::9,19,118.7.160.0,19,2400:4053:4800::,37,6
2001:380:A120::9,19,118.7.192.0,19,2400:4053:5000::,37,6
2001:380:A120::9,19,118.9.64.0,19,2400:4053:5800::,37,6
2001:380:A120::9,19,118.9.128.0,19,2400:4053:6000::,37,6
2001:380:A120::9,19,118.22.128.0,19,2400:4053:6800::,37,6
2001:380:A120::9,19,122.16.0.0,19,2400:4053:7000::,37,6
2001:380:A120::9,19,123.220.0.0,19,2400:4053:7800::,37,6
2001:380:A120::9,22,153.173.0.0,16,2400:4053:8000::,34,6
2001:380:A120::9,22,153.238.0.0,16,2400:4053:C000::,34,6
2001:380:A120::9,22,153.239.0.0,16,2400:4150:0000::,34,6
2001:380:A120::9,22,153.252.0.0,16,2400:4150:4000::,34,6
2001:380:A120::9,19,123.222.96.0,19,2400:4150:8000::,37,6
2001:380:A120::9,19,123.225.96.0,19,2400:4150:8800::,37,6
2001:380:A120::9,19,123.225.160.0,19,2400:4150:9000::,37,6
2001:380:A120::9,19,124.84.96.0,19,2400:4150:9800::,37,6
2001:380:A120::9,19,123.225.0.0,19,2400:4150:A000::,37,6
2001:380:A120::9,19,118.3.0.0,19,2400:4150:A800::,37,6
2001:380:A120::9,22,180.60.0.0,16,2400:4151:0000::,34,6
2001:380:A120::9,21,153.139.0.0,17,2400:4151:4000::,35,6
2001:380:A120::9,21,219.161.128.0,17,2400:4151:6000::,35,6
2001:380:A120::9,20,153.187.0.0,18,2400:4151:8000::,36,6
2001:380:A120::9,20,153.191.0.0,18,2400:4151:9000::,36,6
2001:380:A120::9,20,180.12.64.0,18,2400:4151:A000::,36,6
2001:380:A120::9,20,180.13.0.0,18,2400:4151:B000::,36,6
2001:380:A120::9,19,124.84.128.0,19,2400:4151:C000::,37,6
2001:380:A120::9,19,124.98.192.0,19,2400:4151:C800::,37,6
2001:380:A120::9,19,124.100.0.0,19,2400:4151:D000::,37,6
2001:380:A120::9,19,124.100.224.0,19,2400:4151:D800::,37,6
2001:380:A120::9,17,122.26.232.0,21,2400:4151:E000::,39,6
2001:380:A120::9,17,122.26.224.0,21,2400:4151:E200::,39,6
2001:380:A120::9,18,118.3.64.0,20,2400:4151:E400::,38,6
2001:380:A120::9,20,180.16.0.0,18,2400:4152:0000::,36,6
2001:380:A120::9,20,180.29.128.0,18,2400:4152:1000::,36,6
2001:380:A120::9,20,180.59.64.0,18,2400:4152:2000::,36,6
2001:380:A120::9,20,219.161.0.0,18,2400:4152:3000::,36,6
2001:380:A120::9,19,153.129.160.0,19,2400:4152:4000::,37,6
2001:380:A120::9,19,153.130.0.0,19,2400:4152:4800::,37,6
2001:380:A120::9,19,153.131.96.0,19,2400:4152:5000::,37,6
2001:380:A120::9,18,180.26.192.0,20,2400:4152:5800::,38,6
2001:380:A120::9,17,114.172.144.0,21,2400:4152:5C00::,39,6
2001:380:A120::9,19,153.131.128.0,19,2400:4152:6000::,37,6
2001:380:A120::9,19,153.132.128.0,19,2400:4152:6800::,37,6
2001:380:A120::9,19,153.134.64.0,19,2400:4152:7000::,37,6
2001:380:A120::9,19,153.137.0.0,19,2400:4152:7800::,37,6
2001:380:A120::9,19,153.139.192.0,19,2400:4152:8000::,37,6
2001:380:A120::9,19,153.151.32.0,19,2400:4152:8800::,37,6
2001:380:A120::9,19,153.156.96.0,19,2400:4152:9000::,37,6
2001:380:A120::9,19,153.156.128.0,19,2400:4152:9800::,37,6
2001:380:A120::9,17,114.172.152.0,21,2400:4152:A000::,39,6
2001:380:A120::9,18,180.26.208.0,20,2400:4152:A400::,38,6
2001:380:A120::9,17,124.98.32.0,21,2400:4152:A800::,39,6
2001:380:A120::9,17,124.98.40.0,21,2400:4152:AA00::,39,6
2001:380:A120::9,17,122.26.240.0,21,2400:4152:B000::,39,6
2001:380:A120::9,18,114.172.128.0,20,2400:4152:B400::,38,6
2001:380:A120::9,18,122.26.128.0,20,2400:4152:B800::,38,6
2001:380:A120::9,17,122.26.248.0,21,2400:4152:BC00::,39,6
2001:380:A120::9,17,123.225.152.0,21,2400:4152:BE00::,39,6
2001:380:A120::9,18,118.3.80.0,20,2400:4152:C000::,38,6
2001:380:A120::9,17,124.98.16.0,21,2400:4152:C600::,39,6
2001:380:A120::9,17,124.98.24.0,21,2400:4152:CA00::,39,6
2001:380:A120::9,17,124.98.8.0,21,2400:4152:CC00::,39,6
2001:380:A120::9,17,124.98.0.0,21,2400:4152:CE00::,39,6
2001:380:A120::9,17,118.3.112.0,21,2400:4152:D000::,39,6
2001:380:A120::9,17,118.3.120.0,21,2400:4152:D200::,39,6
2001:380:A120::9,18,118.3.48.0,20,2400:4152:E000::,38,6
2001:380:A120::9,17,118.3.96.0,21,2400:4152:E800::,39,6
2001:380:A120::9,17,118.3.104.0,21,2400:4152:F000::,39,6
2001:380:A120::9,18,118.3.32.0,20,2400:4152:F400::,38,6
2001:380:A120::9,19,153.165.96.0,19,2400:4153:0000::,37,6
2001:380:A120::9,19,153.165.160.0,19,2400:4153:0800::,37,6
2001:380:A120::9,19,153.171.224.0,19,2400:4153:1000::,37,6
2001:380:A120::9,19,153.175.0.0,19,2400:4153:1800::,37,6
2001:380:A120::9,19,153.181.0.0,19,2400:4153:2000::,37,6
2001:380:A120::9,19,153.183.224.0,19,2400:4153:2800::,37,6
2001:380:A120::9,19,153.184.128.0,19,2400:4153:3000::,37,6
2001:380:A120::9,19,153.187.224.0,19,2400:4153:3800::,37,6
2001:380:A120::9,18,220.106.32.0,20,2400:4153:4000::,38,6
2001:380:A120::9,18,220.106.48.0,20,2400:4153:4400::,38,6
2001:380:A120::9,19,153.188.0.0,19,2400:4153:4800::,37,6
2001:380:A120::9,19,153.190.128.0,19,2400:4153:5000::,37,6
2001:380:A120::9,19,153.191.64.0,19,2400:4153:5800::,37,6
2001:380:A120::9,19,153.191.192.0,19,2400:4153:6000::,37,6
2001:380:A120::9,19,153.194.96.0,19,2400:4153:6800::,37,6
2001:380:A120::9,18,220.106.64.0,20,2400:4153:7000::,38,6
2001:380:A120::9,18,220.106.80.0,20,2400:4153:7400::,38,6
2001:380:A120::9,18,180.26.128.0,20,2400:4153:7800::,38,6
2001:380:A120::9,18,180.26.144.0,20,2400:4153:7C00::,38,6
2001:380:A120::9,19,180.12.128.0,19,2400:4153:8000::,37,6
2001:380:A120::9,19,180.26.96.0,19,2400:4153:8800::,37,6
2001:380:A120::9,19,180.26.160.0,19,2400:4153:9000::,37,6
2001:380:A120::9,19,180.26.224.0,19,2400:4153:9800::,37,6
2001:380:A120::9,19,180.30.0.0,19,2400:4153:A000::,37,6
2001:380:A120::9,19,180.31.96.0,19,2400:4153:A800::,37,6
2001:380:A120::9,19,180.32.64.0,19,2400:4153:B000::,37,6
2001:380:A120::9,19,180.34.160.0,19,2400:4153:B800::,37,6
2001:380:A120::9,19,180.46.0.0,19,2400:4153:C000::,37,6
2001:380:A120::9,19,180.48.0.0,19,2400:4153:C800::,37,6
2001:380:A120::9,19,180.50.192.0,19,2400:4153:D000::,37,6
2001:380:A120::9,19,180.53.0.0,19,2400:4153:D800::,37,6
2001:380:A120::9,19,218.230.128.0,19,2400:4153:E000::,37,6
2001:380:A120::9,19,219.161.64.0,19,2400:4153:E800::,37,6
2001:380:A120::9,19,220.96.64.0,19,2400:4153:F000::,37,6
2001:380:A120::9,19,220.99.0.0,19,2400:4153:F800::,37,6
EOF
}

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
        WAN6_PREFIX=$(echo "$ipv6_addr" | awk -F: '{if (NF>=4) printf "%s:%s:%s:%s::/64", $1, $2, $3, $4; else print ""}')
        return 0
    fi
    
    local ipv6_prefix=""
    if command -v network_get_prefix6 >/dev/null 2>&1; then
        network_get_prefix6 ipv6_prefix "wan6"
    fi
    
    if [ -n "$ipv6_prefix" ]; then
        USER_IPV6_ADDR="$ipv6_prefix"
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
    local _wan6_if_name_arg="$1" 
    local _ocn_api_code_arg="$2" 

    local current_user_ipv6_addr="$USER_IPV6_ADDR"
    local normalized_prefix_for_check=""
    local found_rule_line="" 

    if [ -z "$current_user_ipv6_addr" ]; then
        return 1
    fi

    normalized_prefix_for_check=$(echo "$current_user_ipv6_addr" | awk -F: '{printf "%s:%s:%s:%s::", $1, $2, $3, $4}')

    if [ -z "$normalized_prefix_for_check" ]; then
        return 1
    fi

    found_rule_line=$(map_rules_data | {
        _found_in_subshell=0
        while IFS= read -r _csv_rule_line; do
            if [ -z "$_csv_rule_line" ]; then
                continue
            fi
            _rule_ipv6_prefix_from_csv=$(echo "$_csv_rule_line" | cut -d',' -f5)
            _rule_ipv6_prefix_len_from_csv=$(echo "$_csv_rule_line" | cut -d',' -f6)

            if [ -z "$_rule_ipv6_prefix_from_csv" ] || [ -z "$_rule_ipv6_prefix_len_from_csv" ]; then
                continue
            fi
            
            case "$_rule_ipv6_prefix_len_from_csv" in
                ''|*[!0-9]*) 
                    continue ;;
            esac

            if check_ipv6_in_range "$normalized_prefix_for_check" "$_rule_ipv6_prefix_from_csv" "$_rule_ipv6_prefix_len_from_csv"; then
                echo "$_csv_rule_line" 
                _found_in_subshell=1
                break 
            fi
        done
        if [ "$_found_in_subshell" -eq 1 ]; then exit 0; else exit 1; fi
    })

    if [ -n "$found_rule_line" ]; then
        STATIC_API_RULE_LINE="$found_rule_line"
        return 0 
    else
        STATIC_API_RULE_LINE=""
        return 1 
    fi
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
    
    return 0
}

calculate_mape_params() {
    if [ -z "$STATIC_API_RULE_LINE" ]; then
        return 1
    fi
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        return 1
    fi

    local csv_br_ipv6_address csv_ea_bit_length csv_ipv4_prefix csv_ipv4_prefix_length
    local csv_ipv6_prefix_rule csv_ipv6_prefix_length_rule csv_psid_offset

    csv_br_ipv6_address=$(echo "$STATIC_API_RULE_LINE" | cut -d',' -f1)
    csv_ea_bit_length=$(echo "$STATIC_API_RULE_LINE"   | cut -d',' -f2)
    csv_ipv4_prefix=$(echo "$STATIC_API_RULE_LINE"     | cut -d',' -f3)
    csv_ipv4_prefix_length=$(echo "$STATIC_API_RULE_LINE" | cut -d',' -f4)
    csv_ipv6_prefix_rule=$(echo "$STATIC_API_RULE_LINE" | cut -d',' -f5)
    csv_ipv6_prefix_length_rule=$(echo "$STATIC_API_RULE_LINE" | cut -d',' -f6)
    csv_psid_offset=$(echo "$STATIC_API_RULE_LINE"    | cut -d',' -f7)
    
    BR="$csv_br_ipv6_address"
    IPV4_NET_PREFIX="$csv_ipv4_prefix"
    IP4PREFIXLEN="$csv_ipv4_prefix_length"
    IPV6_RULE_PREFIX="$csv_ipv6_prefix_rule"
    IPV6_RULE_PREFIXLEN="$csv_ipv6_prefix_length_rule"
    EALEN="$csv_ea_bit_length"
    OFFSET="$csv_psid_offset"

    local var_to_check
    local value_to_check
    for var_to_check in EALEN IP4PREFIXLEN IPV6_RULE_PREFIXLEN OFFSET; do
        eval "value_to_check=\$$var_to_check" 
        if ! printf "%s" "$value_to_check" | grep -qE '^[0-9]+$'; then
            return 1
        fi
    done

    read -r h0 h1 h2 h3 h4 h5 h6 h7 <<EOF
$USER_IPV6_HEXTETS
EOF

    local ipv4_suffix_len=$((32 - IP4PREFIXLEN))
    PSIDLEN=$((EALEN - ipv4_suffix_len))
    if [ "$PSIDLEN" -lt 0 ]; then
        return 1
    fi

    local shift_calc=$((16 - OFFSET - PSIDLEN)) 
    local mask=$(( ((1 << PSIDLEN) - 1) << shift_calc ))
    
    local h3_val_for_calc=0
    if printf "%s" "$h3" | grep -qE '^[0-9a-fA-F]{1,4}$'; then
        h3_val_for_calc=$((0x$h3))
    fi
    PSID=$(( (h3_val_for_calc & mask) >> shift_calc ))

    local o1 o2 o3_base o4_base o3_val o4_val
    o1=$(echo "$IPV4_NET_PREFIX" | cut -d. -f1)
    o2=$(echo "$IPV4_NET_PREFIX" | cut -d. -f2)
    o3_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f3)
    o4_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f4)

    local h2_val_for_calc=0
    if printf "%s" "$h2" | grep -qE '^[0-9a-fA-F]{1,4}$'; then
        h2_val_for_calc=$((0x$h2))
    fi

    o3_val=$(( o3_base | ( (h2_val_for_calc & 0x03C0) >> 6 ) ))
    o4_val=$(( ( (h2_val_for_calc & 0x003F) << 2 ) | (((h3_val_for_calc) & 0xC000) >> 14) ))

    IPADDR="${o1}.${o2}.${o3_val}.${o4_val}"

    local ce_h3_masked ce_h4 ce_h5 ce_h6 ce_h7
    ce_h3_masked=$(printf "%04x" $((h3_val_for_calc & 0xFF00)))
    ce_h4=$(printf "%04x" "$o1")
    ce_h5=$(printf "%04x" $((o2 * 256 + o3_val)))
    ce_h6=$(printf "%04x" $((o4_val * 256)))
    ce_h7=$(printf "%04x" $((PSID * 256)))

    CE="${h0}:${h1}:${h2}:${ce_h3_masked}:${ce_h4}:${ce_h5}:${ce_h6}:${ce_h7}"
       
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
        printf "Error: Failed to commit UCI changes for: %s\n" "$commit_errors" >&2
        return 1
    fi
    
    printf "MAP-E UCI settings applied successfully.\n"
    
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
    case "$WAN6_PREFIX" in
        "") ipv6_label="IPv6プレフィックス:" ;;
        *)  ipv6_label="IPv6アドレス:" ;;
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

    if ! get_ocn_rule_from_api "$WAN6_IF_NAME" "$OCN_API_CODE"; then
        printf "MAP-EルールをAPI DATAから取得できませんでした。終了します。\n" >&2
        return 1
    fi

    if ! install_map_package; then
        printf "MAPパッケージのインストールに失敗しました。終了します。\n" >&2
        return 1
    fi

    if [ -z "$USER_IPV6_ADDR" ]; then
        printf "ユーザーのIPv6アドレスが設定されていません。終了します\n" >&2
        return 1
    fi
    if ! parse_user_ipv6 "$USER_IPV6_ADDR"; then
        printf "ユーザーIPv6アドレス(%s)のパースに失敗しました。終了します。\n" "$USER_IPV6_ADDR" >&2
        return 1
    fi

    if ! calculate_mape_params; then
        printf "MAP-Eパラメータの計算に失敗しました終了します。\n" >&2
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

ocn_main

exit $?
