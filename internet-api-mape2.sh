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

get_rule_from_api() {
    local _wan6_if_name_arg="$1" 
    local current_user_ipv6_addr_for_api="$USER_IPV6_ADDR"
    local api_url="https://map-api-worker.site-u.workers.dev/map-rule"
    local api_response=""
    local user_prefix_for_api=""
    local ret_code=1

    if [ -z "$current_user_ipv6_addr_for_api" ]; then
        # printf "DEBUG: User IPv6 address is not set for API query.\n" >&2 # デバッグメッセージは英語
        return 1
    fi

    # APIに渡す user_prefix を整形 (例: xxxx:xxxx:xxxx:xxxx::)
    # USER_IPV6_ADDR が完全なアドレスでも、API側でプレフィックス部分を見てくれる想定
    # 元のスクリプトでは /64 が付与される場合もあるため、:: より前を取得
    user_prefix_for_api=$(echo "$current_user_ipv6_addr_for_api" | awk -F/ '{print $1}' | awk -F: '{if(NF>=4) printf "%s:%s:%s:%s::", $1, $2, $3, $4; else print $0}')

    if [ -z "$user_prefix_for_api" ]; then
        # printf "DEBUG: Failed to format user_prefix for API from %s.\n" "$current_user_ipv6_addr_for_api" >&2
        return 1
    fi
    
    # printf "DEBUG: Querying API with user_prefix: %s\n" "$user_prefix_for_api" >&2

    # wgetでAPIを呼び出し、レスポンスを取得
    # -q: 静かに実行, -O -: 標準出力へ出力, --timeout=10: 10秒でタイムアウト
    api_response=$(wget -q -O - --timeout=10 "${api_url}?user_prefix=${user_prefix_for_api}")
    ret_code=$?

    if [ $ret_code -ne 0 ] || [ -z "$api_response" ]; then
        # printf "DEBUG: API request failed or got empty response. wget status: %d\n" "$ret_code" >&2
        BR=""; EALEN=""; IPV4_NET_PREFIX=""; IP4PREFIXLEN=""; IPV6_RULE_PREFIX=""; IPV6_RULE_PREFIXLEN=""; OFFSET=""
        return 1
    fi

    # JSONレスポンスのパース (grep と awk/sed を使用)
    # APIレスポンスは整形済み (キーごとに改行) を前提とする
    # 例: "brIpv6Address": "2001:380:a120::9",
    # awk -F'"' を使うと、4番目のフィールド ($4) が値になる
    _br=$(echo "$api_response" | grep '"brIpv6Address":' | awk -F'"' '{print $4}')
    _ealen=$(echo "$api_response" | grep '"eaBitLength":' | awk -F'"' '{print $4}')
    _ipv4_net_prefix=$(echo "$api_response" | grep '"ipv4Prefix":' | awk -F'"' '{print $4}')
    _ip4prefixlen=$(echo "$api_response" | grep '"ipv4PrefixLength":' | awk -F'"' '{print $4}')
    _ipv6_rule_prefix=$(echo "$api_response" | grep '"ipv6Prefix":' | awk -F'"' '{print $4}')
    _ipv6_rule_prefixlen=$(echo "$api_response" | grep '"ipv6PrefixLength":' | awk -F'"' '{print $4}')
    _offset=$(echo "$api_response" | grep '"psIdOffset":' | awk -F'"' '{print $4}')

    # 必須のパラメータが一つでも取得できなかった場合はエラー
    if [ -z "$_br" ] || [ -z "$_ealen" ] || [ -z "$_ipv4_net_prefix" ] || \
       [ -z "$_ip4prefixlen" ] || [ -z "$_ipv6_rule_prefix" ] || \
       [ -z "$_ipv6_rule_prefixlen" ] || [ -z "$_offset" ]; then
        # printf "DEBUG: Failed to parse all required fields from API response.\n" >&2
        # printf "DEBUG: Response was: %s\n" "$api_response" >&2
        BR=""; EALEN=""; IPV4_NET_PREFIX=""; IP4PREFIXLEN=""; IPV6_RULE_PREFIX=""; IPV6_RULE_PREFIXLEN=""; OFFSET=""
        return 1
    fi

    # グローバル変数に設定
    BR="$_br"
    EALEN="$_ealen"
    IPV4_NET_PREFIX="$_ipv4_net_prefix"
    IP4PREFIXLEN="$_ip4prefixlen"
    IPV6_RULE_PREFIX="$_ipv6_rule_prefix"
    IPV6_RULE_PREFIXLEN="$_ipv6_rule_prefixlen"
    OFFSET="$_offset"
    
    # 以前の STATIC_API_RULE_LINE は直接使われないので、設定は不要
    # printf "DEBUG: API rule data populated successfully.\n" >&2
    return 0 # 成功
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
    if [ -z "$USER_IPV6_HEXTETS" ]; then
        # printf "DEBUG: USER_IPV6_HEXTETS is not set in calculate_mape_params.\n" >&2
        return 1
    fi

    # APIから取得済みのグローバル変数:
    # BR, EALEN, IPV4_NET_PREFIX, IP4PREFIXLEN, 
    # IPV6_RULE_PREFIX, IPV6_RULE_PREFIXLEN, OFFSET

    # 必須APIパラメータが設定されているか確認
    if [ -z "$BR" ] || [ -z "$EALEN" ] || [ -z "$IPV4_NET_PREFIX" ] || \
       [ -z "$IP4PREFIXLEN" ] || [ -z "$IPV6_RULE_PREFIX" ] || \
       [ -z "$IPV6_RULE_PREFIXLEN" ] || [ -z "$OFFSET" ]; then
        # printf "DEBUG: One or more required MAP-E parameters (BR, EALEN, etc.) from API are not set.\n" >&2
        return 1
    fi

    # 必須数値パラメータが実際に数値であるかチェック
    local var_to_check value_to_check
    for var_to_check in EALEN IP4PREFIXLEN IPV6_RULE_PREFIXLEN OFFSET; do
        eval "value_to_check=\$$var_to_check" 
        if ! printf "%s" "$value_to_check" | grep -qE '^[0-9]+$'; then
            # printf "DEBUG: API Parameter %s ('%s') is not a valid number.\n" "$var_to_check" "$value_to_check" >&2
            return 1
        fi
    done

    # ユーザーIPv6アドレスのヘキステットを読み込み (parse_user_ipv6 で設定済み)
    read -r h0 h1 h2 h3 _h4 _h5 _h6 _h7 <<EOF
$USER_IPV6_HEXTETS
EOF
    # h0-h3 のみ使用。_h4-_h7 はプレースホルダー。

    local h0_val_for_calc h1_val_for_calc h2_val_for_calc h3_val_for_calc # 10進数値
    h0_val_for_calc=$((0x${h0:-0}))
    h1_val_for_calc=$((0x${h1:-0}))
    h2_val_for_calc=$((0x${h2:-0}))
    h3_val_for_calc=$((0x${h3:-0}))


    # PSIDLEN の計算: EA-bits長 - IPv4サフィックス長
    # IPv4サフィックス長 = 32 - ルールIPv4プレフィックス長
    local ipv4_suffix_len=$((32 - IP4PREFIXLEN))
    if [ "$ipv4_suffix_len" -lt 0 ]; then # IP4PREFIXLEN が32より大きい場合
        # printf "DEBUG: Invalid IP4PREFIXLEN (%s) > 32.\n" "$IP4PREFIXLEN" >&2
        return 1
    fi
    PSIDLEN=$((EALEN - ipv4_suffix_len))

    if [ "$PSIDLEN" -lt 0 ]; then
        # printf "DEBUG: Calculated PSIDLEN (%s) is negative. (EALEN=%s, IP4PREFIXLEN=%s).\n" "$PSIDLEN" "$EALEN" "$IP4PREFIXLEN" >&2
        PSIDLEN=0 # ルールが不正である可能性が高いが、元ソースの挙動に倣い0とする
    fi
    if [ "$PSIDLEN" -gt 16 ]; then # PSIDは最大16ビット
        # printf "DEBUG: Calculated PSIDLEN (%s) is too large (max 16).\n" "$PSIDLEN" >&2
        return 1 
    fi
    # printf "DEBUG: PSIDLEN calculated: %s\n" "$PSIDLEN"


    # PSID の計算に必要なシフト量とマスク
    # shift_for_psid は、HEXTET3内でPSIDフィールドの最下位ビットが、HEXTET3全体の最下位ビットから見て何ビット左にあるかを示す。
    # (PSIDフィールドを右端に寄せるための右シフト量でもある)
    local shift_for_psid=$((16 - OFFSET - PSIDLEN)) 
    if [ "$shift_for_psid" -lt 0 ]; then # OFFSET + PSIDLEN が16を超える場合 (PSIDフィールドがHEXTET3に収まらない)
        # printf "DEBUG: Invalid rule parameters for PSID calculation: OFFSET (%s) + PSIDLEN (%s) > 16.\n" "$OFFSET" "$PSIDLEN" >&2
        return 1
    fi
    
    local psid_field_only_mask=0 # PSIDLEN ビットが全て1のマスク (例: PSIDLEN=6 なら 0b111111)
    if [ "$PSIDLEN" -gt 0 ]; then
        psid_field_only_mask=$(( (1 << PSIDLEN) - 1 ))
    fi
    # HEXTET3 内でPSIDフィールドに相当する部分だけのマスク (例: OFFSET=4, PSIDLEN=6 なら 0b0000111111000000)
    local psid_mask_in_hextet3=$(( psid_field_only_mask << shift_for_psid ))
    
    if [ "$PSIDLEN" -eq 0 ]; then
        PSID=0
    else
        PSID=$(( (h3_val_for_calc & psid_mask_in_hextet3) >> shift_for_psid ))
    fi
    # printf "DEBUG: PSID calculated: %s (from HEXTET3=0x%s, OFFSET=%s, PSIDLEN=%s)\n" "$PSID" "$h3" "$OFFSET" "$PSIDLEN"


    # IPADDR (ユーザーの具体的なIPv4アドレス) の計算
    # APIからの IPV4_NET_PREFIX と、ユーザーIPv6のHEXTET2, HEXTET3 から導出
    # 注意: 以下のEA-bitsからIPv4サフィックスへのマッピング方法は固定ロジックであり、APIからは直接指示されません。
    #       このマッピングは、EA-bitsの一部をユーザーIPv6アドレスのH2およびH3の特定位置から取得する仮定に基づいています。
    local o1 o2 o3_base o4_base o3_val o4_val
    o1=$(echo "$IPV4_NET_PREFIX" | cut -d. -f1)
    o2=$(echo "$IPV4_NET_PREFIX" | cut -d. -f2)
    o3_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f3) 
    o4_base=$(echo "$IPV4_NET_PREFIX" | cut -d. -f4)
    
    # HEXTET2の上位6ビットの内の下位4ビット (H2のビット10,9,8,7) を o3 のサフィックスに、
    # HEXTET2の下位6ビット (H2のビット5,4,3,2,1,0) を o4 の上位6ビットに、
    # HEXTET3の最上位2ビット (H3のビット15,14) を o4 の下位2ビットにマッピングする。
    o3_val=$(( o3_base | ( (h2_val_for_calc & 0x03C0) >> 6 ) )) 
    o4_val=$(( ( (h2_val_for_calc & 0x003F) << 2 ) | (( (h3_val_for_calc & 0xC000) >> 14) & 0x0003 ) ))

    IPADDR="${o1}.${o2}.${o3_val}.${o4_val}"
    # printf "DEBUG: IPADDR calculated: %s (EA-bits from HEXTET2=0x%s, HEXTET3=0x%s)\n" "$IPADDR" "$h2" "$h3"


    # CE (Customer Edge IPv6 アドレス) の計算
    # H0, H1, H2 はユーザーIPv6アドレスからそのまま使用
    # H3 はPSIDフィールドをマスクして0にする
    # H4, H5, H6 は計算されたIPADDRの各オクテットから生成
    # H7 はPSIDを (16 - OFFSET - PSIDLEN) 左シフトして配置 (汎用化)
    
    local ce_h0_str=$(printf "%04x" "$h0_val_for_calc")
    local ce_h1_str=$(printf "%04x" "$h1_val_for_calc")
    local ce_h2_str=$(printf "%04x" "$h2_val_for_calc")
    
    local ce_h3_masked_val=$(( h3_val_for_calc & (~psid_mask_in_hextet3 & 0xFFFF) )) # HEXTET3からPSID部分を0にする
    local ce_h3_str=$(printf "%04x" "$ce_h3_masked_val")

    local ce_h4_str=$(printf "%04x" "$o1")                     # IPADDRの第1オクテット
    local ce_h5_str=$(printf "%04x" $(( (o2 << 8) | o3_val )) ) # IPADDRの第2オクテットと第3オクテット
    local ce_h6_str=$(printf "%04x" $(( o4_val << 8 )) )       # IPADDRの第4オクテットを上位8ビットに配置

    # CE H7 の計算 (汎用化): PSID を (16 - OFFSET - PSIDLEN) 左シフト
    # shift_for_psid は既に (16 - OFFSET - PSIDLEN) として計算済み (PSID計算で使用)
    local ce_h7_val=0
    if [ "$PSIDLEN" -gt 0 ]; then
         ce_h7_val=$(( PSID << shift_for_psid ))
    fi
    local ce_h7_str=$(printf "%04x" "$ce_h7_val")

    CE="${ce_h0_str}:${ce_h1_str}:${ce_h2_str}:${ce_h3_str}:${ce_h4_str}:${ce_h5_str}:${ce_h6_str}:${ce_h7_str}"
    # printf "DEBUG: CE calculated: %s\n" "$CE"
       
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

api_mape_main() {
    if [ -f /lib/functions.sh ]; then
        . /lib/functions.sh
        if [ -f /lib/functions/network.sh ]; then # OpenWrt 21.02+
            . /lib/functions/network.sh
        elif [ -f /lib/network/network.sh ]; then # Older OpenWrt
            . /lib/network/network.sh
        else
            printf "Error: OpenWrt network functions script not found.\n" >&2
            return 1
        fi
    else
        printf "Error: This script is intended to run only in an OpenWrt environment.\n" >&2
        return 1
    fi

    if ! determine_ipv6_acquisition_method; then
        # "この回線はMAP-Eに対応していません。\n"
        printf "This line does not support MAP-E or IPv6 is not available.\n" >&2
        return 1
    fi

    # get_rule_from_api の呼び出しから OCN_API_CODE (第2引数) を削除
    if ! get_rule_from_api "$WAN6_IF_NAME"; then
        # "MAP-EルールをAPI DATAから取得できませんでした。終了します。\n"
        printf "Failed to retrieve MAP-E rule from API. Exiting.\n" >&2
        return 1
    fi

    if ! install_map_package; then
        # "MAPパッケージのインストールに失敗しました。終了します。\n"
        printf "Failed to install MAP package. Exiting.\n" >&2
        return 1
    fi

    if [ -z "$USER_IPV6_ADDR" ]; then
        # "ユーザーのIPv6アドレスが設定されていません。終了します\n"
        printf "User IPv6 address is not set. Exiting.\n" >&2
        return 1
    fi
    if ! parse_user_ipv6 "$USER_IPV6_ADDR"; then
        # "ユーザーIPv6アドレス(%s)のパースに失敗しました。終了します。\n"
        printf "Failed to parse user IPv6 address (%s). Exiting.\n" "$USER_IPV6_ADDR" >&2
        return 1
    fi

    if ! calculate_mape_params; then
        # "MAP-Eパラメータの計算に失敗しました終了します。\n"
        printf "Failed to calculate MAP-E parameters. Exiting.\n" >&2
        return 1
    fi

    if ! display_mape; then
        # "MAP-Eパラメータ表示に失敗しました。終了します。\n"
        printf "Failed to display MAP-E parameters. Exiting.\n" >&2
        return 1
    fi

    # configure_openwrt_mape の呼び出しはコメントアウトされたまま
    # if ! configure_openwrt_mape; then
    #     printf "Failed to apply MAP-E configuration. Exiting.\n" >&2
    #     return 1
    # fi

    # printf "Press any key to reboot.\n"
    # read -r -n1 -s
    # reboot

    return 0
}

api_mape_main

exit $?
