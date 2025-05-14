#!/bin/sh
# Information provided by https://github.com/tinysun
# Vr.4.01
# License: CC0

SCRIPT_VERSION="2025.05.14-00-00"

# OpenWrt関数をロード
. /lib/functions/network.sh

# Function to get IPv4 base address for NURO (ruleprefix36)
# Function to get IPv4 base address for NURO (ruleprefix36)
# ARGS: $1 (string) = Hexadecimal prefix key (e.g., "0x240d000f00")
# ECHO: (string) Comma-separated IPv4 octets (e.g., "219,104,128") or empty string
get_ruleprefix36_value() {
    local prefix_hex_key="$1"

    case "$prefix_hex_key" in
        "0x240d000f00") echo "219,104,128" ;;
        "0x240d000f10") echo "219,104,144" ;;
        "0x240d000f20") echo "219,104,160" ;;
        "0x240d000f30") echo "219,104,176" ;;
        "0x240d000fa0") echo "219,104,138" ;;
        "0x240d000fd0") echo "219,104,141" ;;
        *) echo "" ;;
    esac
}

# Function to calculate MAP-E parameters for NURO Hikari
# This function assumes NET_PFX6 (from network_get_prefix6) is globally available and set.
# It sets the following global variables:
#   NEW_IP6_PREFIX: Source IPv6 address (address part from NET_PFX6)
#   BR: Border Relay IPv6 address
#   IPV4: IPv4 address for UCI config (e.g., "219.104.128.0")
#   IPADDR: Full calculated IPv4 address (for display)
#   IP4PREFIXLEN: IPv4 prefix length (e.g., "20")
#   IP6PFX: IPv6 prefix for MAP-E rule (e.g., "240d:f:0")
#   IP6PREFIXLEN: IPv6 prefix length for MAP-E rule (e.g., "36")
#   EALEN: EA-bits length (e.g., "20")
#   PSIDLEN: PSID length (e.g., "8")
#   OFFSET: Offset value (e.g., "4")
#   PSID: Calculated PSID value (decimal)
#   PORTS: String of calculated port ranges
#   CE: Calculated CE IPv6 address
#   IPV6PREFIX: LAN-side /64 IPv6 prefix derived from NEW_IP6_PREFIX (for display/wan6 config)
# Returns:
#   0 on success
#   1 on failure
mold_mape_nuro() {
    local NET_IF6 NET_ADDR6
    network_flush_cache
    network_find_wan6 NET_IF6
    network_get_prefix6 NET_PFX6 "${NET_IF6}"

    if [ -z "$NET_PFX6" ]; then
        debug_log "ERROR" "mold_mape_nuro: NET_PFX6 is not set. Cannot proceed."
        printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_IPV6_PREFIX_FAILED" "DETAIL=NET_PFX6_empty")")"
        return 1
    fi

    NEW_IP6_PREFIX=$(echo "$NET_PFX6" | cut -d'/' -f1)
    if [ -z "$NEW_IP6_PREFIX" ]; then
        debug_log "ERROR" "mold_mape_nuro: Failed to extract address part from NET_PFX6 ('$NET_PFX6')."
        printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_IPV6_PREFIX_FAILED" "DETAIL=NET_PFX6_parse_fail")")"
        return 1
    fi
    debug_log "INFO" "mold_mape_nuro: Using source IPv6 for MAP-E: $NEW_IP6_PREFIX (derived from NET_PFX6: $NET_PFX6)"

    local ipv6_addr="$NEW_IP6_PREFIX"
    local h0_str h1_str h2_str h3_str

    local awk_output
    awk_output=$(echo "$ipv6_addr" | awk '
    BEGIN { FS=":"; OFS=":" }
    {
        num_fields = NF
        if ($0 ~ /::/) {
            zero_fields = 8 - num_fields + 1
            zeros = ""
            for (i = 1; i <= zero_fields; i++) {
                zeros = zeros "0" (i < zero_fields ? ":" : "")
            }
            sub(/::/, zeros)
            if ($1 == "") $1 = "0"
            if ($NF == "" && NF == 8) $NF = "0"
            if (NF == 1 && $1 == "") $1 = "0"
        }
        h0 = $1; if (h0 == "") h0 = "0"
        h1 = $2; if (h1 == "") h1 = "0"
        h2 = $3; if (h2 == "") h2 = "0"
        h3 = $4; if (h3 == "") h3 = "0"
        print h0 " " h1 " " h2 " " h3
    }')

    read -r h0_str h1_str h2_str h3_str <<EOF
$awk_output
EOF

    if [ -z "$h0_str" ]; then
        printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_IPV6_AWK_PARSE_FAILED" "INPUT=$ipv6_addr")")"
        debug_log "ERROR" "mold_mape_nuro: Failed to parse IPv6 address part using awk. Input: '${ipv6_addr}'"
        return 1
    fi

    local HEXTET0 HEXTET1 HEXTET2 HEXTET3
    HEXTET0=$(printf %d "0x${h0_str:-0}")
    HEXTET1=$(printf %d "0x${h1_str:-0}")
    HEXTET2=$(printf %d "0x${h2_str:-0}")
    HEXTET3=$(printf %d "0x${h3_str:-0}")

    debug_log "DEBUG" "mold_mape_nuro: Parsed HEXTETs: H0=${HEXTET0}(${h0_str}), H1=${HEXTET1}(${h1_str}), H2=${HEXTET2}(${h2_str}), H3=${HEXTET3}(${h3_str})"

    local val_for_prefix36_calc_h2=$(( (HEXTET2 & 0xff00) >> 4 ))
    local PREFIX36_NUMERIC=$(( (HEXTET0 * 16777216) + (HEXTET1 * 256) + val_for_prefix36_calc_h2 ))
    local prefix36_hex_key_lookup
    prefix36_hex_key_lookup=$(printf "0x%x" "$PREFIX36_NUMERIC")

    debug_log "DEBUG" "mold_mape_nuro: Calculated PREFIX36_NUMERIC=$PREFIX36_NUMERIC, hex_key_lookup_for_nuro=$prefix36_hex_key_lookup"

    BR=""
    IPV4=""
    IPADDR=""
    IP4PREFIXLEN=""
    IP6PFX=""
    IP6PREFIXLEN=""
    EALEN=""
    PSIDLEN=""
    OFFSET=""
    PSID=0
    PORTS=""
    CE=""
    IPV6PREFIX=""

    local octet_str octet1 octet2 octet3
    octet_str=$(get_ruleprefix36_value "$prefix36_hex_key_lookup")

    if [ -n "$octet_str" ]; then
        debug_log "INFO" "mold_mape_nuro: Matched NURO ruleprefix36 for key '$prefix36_hex_key_lookup'. IPv4 base octets: $octet_str"
        IFS=',' read -r octet1 octet2 octet3 <<EOF
$octet_str
EOF

        BR="2001:3b8:200:ff9::1"
        IP6PREFIXLEN=36
        PSIDLEN=8
        OFFSET=4
        EALEN=$((56 - IP6PREFIXLEN))
        IP4PREFIXLEN=$((32 - (EALEN - PSIDLEN)))
        IPV4="${octet1}.${octet2}.${octet3}.0"
        PSID=$(( HEXTET3 & 0x00ff ))
        IPADDR="${octet1}.${octet2}.${octet3}.${PSID}"

        local h2_masked_for_ip6pfx=$(( HEXTET2 & 0xff00 ))
        IP6PFX0_str=$(printf %x "$HEXTET0")
        IP6PFX1_str=$(printf %x "$HEXTET1")
        IP6PFX2_str=$(printf %x "$h2_masked_for_ip6pfx")
        IP6PFX="${IP6PFX0_str}:${IP6PFX1_str}:${IP6PFX2_str}"

        debug_log "DEBUG" "mold_mape_nuro: NURO Params: BR=$BR, IPV4=$IPV4, IP4PREFIXLEN=$IP4PREFIXLEN, IP6PFX=$IP6PFX, IP6PREFIXLEN=$IP6PREFIXLEN"
        debug_log "DEBUG" "mold_mape_nuro: NURO Params: EALEN=$EALEN, PSIDLEN=$PSIDLEN, OFFSET=$OFFSET, PSID=$PSID, IPADDR=$IPADDR"

    else
        debug_log "ERROR" "mold_mape_nuro: No matching NURO ruleprefix36 found for key '$prefix36_hex_key_lookup'."
        printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_UNSUPPORTED_PREFIX_RULE" "SERVICE=NURO" "KEY=$prefix36_hex_key_lookup")")"
        return 1
    fi

    PORTS=""
    local AMAX=$(( (1 << OFFSET) - 1 ))
    debug_log "DEBUG" "mold_mape_nuro: Calculating port ranges: AMAX=$AMAX, OFFSET=$OFFSET, PSIDLEN=$PSIDLEN, PSID=$PSID"

    local A
    for A in $(seq 1 "$AMAX"); do
        local shift_bits=$(( 16 - OFFSET ))
        local port_base=$(( A << shift_bits ))
        local psid_shift=$(( 16 - OFFSET - PSIDLEN ))
        if [ "$psid_shift" -lt 0 ]; then
            debug_log "WARN" "mold_mape_nuro: psid_shift is negative ($psid_shift). Setting to 0."
            psid_shift=0
        fi
        local psid_part=$(( PSID << psid_shift ))
        local port_start=$(( port_base | psid_part ))
        local port_range_size=$(( 1 << psid_shift ))
        if [ "$port_range_size" -le 0 ]; then
             debug_log "WARN" "mold_mape_nuro: port_range_size is not positive ($port_range_size). Setting to 1."
             port_range_size=1
        fi
        local port_end=$(( port_start + port_range_size - 1 ))

        PORTS="${PORTS}${port_start}-${port_end}"

        if [ "$A" -lt "$AMAX" ]; then
            if [ $(( A % 3 )) -eq 0 ]; then
                PORTS="${PORTS}\n"
            else
                PORTS="${PORTS} "
            fi
        fi
    done
    debug_log "DEBUG" "mold_mape_nuro: Calculated PORTS string (raw): $PORTS"

    local RFC=false
    local CE_HEXTET0 CE_HEXTET1 CE_HEXTET2 CE_HEXTET3 CE_HEXTET4 CE_HEXTET5 CE_HEXTET6 CE_HEXTET7
    CE_HEXTET0=$HEXTET0
    CE_HEXTET1=$HEXTET1
    CE_HEXTET2=$HEXTET2
    CE_HEXTET3=$(( HEXTET3 & 0xff00 ))

    local ce_octet1_disp ce_octet2_disp ce_octet3_disp ce_octet4_disp
    ce_octet1_disp=$(echo "$IPADDR" | cut -d. -f1)
    ce_octet2_disp=$(echo "$IPADDR" | cut -d. -f2)
    ce_octet3_disp=$(echo "$IPADDR" | cut -d. -f3)
    ce_octet4_disp=$(echo "$IPADDR" | cut -d. -f4)

    if [ "$RFC" = "true" ]; then
        debug_log "DEBUG" "mold_mape_nuro: Calculating CE Address (RFC mode - unexpected for NURO)"
        CE_HEXTET4=0
        CE_HEXTET5=$(( (ce_octet1_disp << 8) | ce_octet2_disp ))
        CE_HEXTET6=$(( (ce_octet3_disp << 8) | ce_octet4_disp ))
        CE_HEXTET7=$PSID
    else
        debug_log "DEBUG" "mold_mape_nuro: Calculating CE Address (Non-RFC mode)"
        CE_HEXTET4=$ce_octet1_disp
        CE_HEXTET5=$(( (ce_octet2_disp << 8) | ce_octet3_disp ))
        CE_HEXTET6=$(( ce_octet4_disp << 8 ))
        CE_HEXTET7=$(( PSID << 8 ))
    fi

    local CE0_str CE1_str CE2_str CE3_str CE4_str CE5_str CE6_str CE7_str
    CE0_str=$(printf %04x "$CE_HEXTET0")
    CE1_str=$(printf %04x "$CE_HEXTET1")
    CE2_str=$(printf %04x "$CE_HEXTET2")
    CE3_str=$(printf %04x "$CE_HEXTET3")
    CE4_str=$(printf %04x "$CE_HEXTET4")
    CE5_str=$(printf %04x "$CE_HEXTET5")
    CE6_str=$(printf %04x "$CE_HEXTET6")
    CE7_str=$(printf %04x "$CE_HEXTET7")
    CE="${CE0_str}:${CE1_str}:${CE2_str}:${CE3_str}:${CE4_str}:${CE5_str}:${CE6_str}:${CE7_str}"
    debug_log "DEBUG" "mold_mape_nuro: Generated CE IPv6 Address: $CE"

    IPV6PREFIX="${h0_str}:${h1_str}:${h2_str}:${h3_str}::"
    debug_log "DEBUG" "mold_mape_nuro: LAN-side IPv6 Prefix (IPV6PREFIX for display/wan6): $IPV6PREFIX"

    debug_log "INFO" "mold_mape_nuro: MAP-E parameter calculation for NURO completed successfully."
    return 0
}

# Function to apply NURO MAP-E UCI settings
# This function assumes that global variables for MAP-E parameters
# (BR, IPV4, IP4PREFIXLEN, IP6PFX, IP6PREFIXLEN, EALEN, PSIDLEN, OFFSET)
# have been set by mold_mape_nuro().
# It strictly adheres to the UCI settings from site-u2023/config-software/map-e-nuro.sh.
# Returns:
#   0 on success (UCI commands executed and committed)
#   1 on UCI commit failure
mape_nuro_config() {
    local wanmap_if='wanmap'
    local firewall_zone_idx='1'
    local openwrt_release_major

    # 設定のバックアップ作成 (NURO版)
    debug_log "DEBUG" "mape_nuro_config: Backing up configuration files..."
    cp /etc/config/network /etc/config/network.map-e-nuro.bak && debug_log "DEBUG" "mape_nuro_config: network backup created (.map-e-nuro.bak)." || debug_log "DEBUG" "mape_nuro_config: Failed to backup network config."
    cp /etc/config/dhcp /etc/config/dhcp.map-e-nuro.bak && debug_log "DEBUG" "mape_nuro_config: dhcp backup created (.map-e-nuro.bak)." || debug_log "DEBUG" "mape_nuro_config: Failed to backup dhcp config."
    cp /etc/config/firewall /etc/config/firewall.map-e-nuro.bak && debug_log "DEBUG" "mape_nuro_config: firewall backup created (.map-e-nuro.bak)." || debug_log "DEBUG" "mape_nuro_config: Failed to backup firewall config."

    debug_log "INFO" "mape_nuro_config: Applying NURO MAP-E UCI settings."

    debug_log "DEBUG" "mape_nuro_config: Setting DHCP LAN..."
    uci set dhcp.lan.ra='relay'
    uci set dhcp.lan.dhcpv6='server'
    uci set dhcp.lan.ndp='relay'
    uci set dhcp.lan.force='1'

    debug_log "DEBUG" "mape_nuro_config: Setting WAN interface (network.wan.auto='1')..."
    uci set network.wan.auto='1'

    debug_log "DEBUG" "mape_nuro_config: Setting DHCP WAN6..."
    uci set dhcp.wan6=dhcp
    uci set dhcp.wan6.master='1'
    uci set dhcp.wan6.ra='relay'
    uci set dhcp.wan6.dhcpv6='relay'
    uci set dhcp.wan6.ndp='relay'

    debug_log "DEBUG" "mape_nuro_config: Setting MAP-E interface (network.$wanmap_if)..."
    uci set network."$wanmap_if"=interface
    uci set network."$wanmap_if".proto='map'
    uci set network."$wanmap_if".maptype='map-e'
    uci set network."$wanmap_if".peeraddr="$BR"
    uci set network."$wanmap_if".ipaddr="$IPV4"
    uci set network."$wanmap_if".ip4prefixlen="$IP4PREFIXLEN"
    uci set network."$wanmap_if".ip6prefix="${IP6PFX}::"
    uci set network."$wanmap_if".ip6prefixlen="$IP6PREFIXLEN"
    uci set network."$wanmap_if".ealen="$EALEN"
    uci set network."$wanmap_if".psidlen="$PSIDLEN"
    uci set network."$wanmap_if".offset="$OFFSET"
    uci set network."$wanmap_if".mtu='1452'
    uci set network."$wanmap_if".encaplimit='ignore'

    openwrt_release_major=$(grep 'DISTRIB_RELEASE' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2 | cut -c 1-2)
    debug_log "DEBUG" "mape_nuro_config: Detected OpenWrt major release: '$openwrt_release_major'"

    if [ -n "$openwrt_release_major" ] && \
       ( [ "$openwrt_release_major" = "SN" ] || \
         [ "$openwrt_release_major" -ge 21 ] && [ "$openwrt_release_major" -le 24 ] ); then
        debug_log "INFO" "mape_nuro_config: Applying settings for OpenWrt $openwrt_release_major (21-24, SN)..."
        uci set dhcp.wan6.ignore='1'
        uci set network."$wanmap_if".legacymap='1'
        uci set network."$wanmap_if".tunlink='wan6'
    elif [ "$openwrt_release_major" = "19" ]; then
        debug_log "INFO" "mape_nuro_config: Applying settings for OpenWrt 19..."
        uci -q delete network."$wanmap_if".tunlink
        uci add_list network."$wanmap_if".tunlink='wan6'
    else
        debug_log "WARN" "mape_nuro_config: OpenWrt release '$openwrt_release_major' not explicitly handled by version-specific settings. Applying defaults which might be similar to 21+."
        uci set dhcp.wan6.ignore='1'
        uci set network."$wanmap_if".legacymap='1'
        uci set network."$wanmap_if".tunlink='wan6'
    fi

    debug_log "DEBUG" "mape_nuro_config: Setting Firewall rules for zone index $firewall_zone_idx..."
    local current_fw_networks
    current_fw_networks=$(uci -q get firewall.@zone["$firewall_zone_idx"].network)
    
    if echo "$current_fw_networks" | grep -q '\bwan\b'; then
        uci del_list firewall.@zone["$firewall_zone_idx"].network='wan'
        debug_log "DEBUG" "mape_nuro_config: Removed 'wan' from firewall zone $firewall_zone_idx network list."
    fi
    if ! echo "$current_fw_networks" | grep -q "\b$wanmap_if\b"; then
        uci add_list firewall.@zone["$firewall_zone_idx"].network="$wanmap_if"
        debug_log "DEBUG" "mape_nuro_config: Added '$wanmap_if' to firewall zone $firewall_zone_idx network list."
    else
        debug_log "DEBUG" "mape_nuro_config: '$wanmap_if' already in firewall zone $firewall_zone_idx network list."
    fi

    debug_log "DEBUG" "mape_nuro_config: Setting DNS configurations..."
    uci -q delete dhcp.lan.dns
    uci -q delete dhcp.lan.dhcp_option
    uci -q delete network.lan.dns

    uci add_list network.lan.dns='118.238.201.33'
    uci add_list network.lan.dns='152.165.245.17'

    uci add_list dhcp.lan.dhcp_option='6,1.1.1.1,8.8.8.8'
    uci add_list dhcp.lan.dhcp_option='6,1.0.0.1,8.8.4.4'

    uci add_list network.lan.dns='240d:0010:0004:0005::33'
    uci add_list network.lan.dns='240d:12:4:1b01:152:165:245:17'

    uci add_list dhcp.lan.dns='2606:4700:4700::1111'
    uci add_list dhcp.lan.dns='2001:4860:4860::8888'
    uci add_list dhcp.lan.dns='2606:4700:4700::1001'
    uci add_list dhcp.lan.dns='2001:4860:4860::8844'

    debug_log "INFO" "mape_nuro_config: Committing all UCI changes..."
    local commit_success=1
    if ! uci commit dhcp; then
        debug_log "ERROR" "mape_nuro_config: 'uci commit dhcp' failed."
        commit_success=0
    fi
    if ! uci commit network; then
        debug_log "ERROR" "mape_nuro_config: 'uci commit network' failed."
        commit_success=0
    fi
    if ! uci commit firewall; then
        debug_log "ERROR" "mape_nuro_config: 'uci commit firewall' failed."
        commit_success=0
    fi

    if [ "$commit_success" -eq 1 ]; then
        debug_log "INFO" "mape_nuro_config: All UCI changes committed successfully."
        return 0
    else
        debug_log "ERROR" "mape_nuro_config: One or more UCI commit operations failed."
        printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_UCI_COMMIT_FAILED")")"
        return 1
    fi
}

# Function to display NURO MAP-E parameters and UCI configuration values
# Assumes global variables from mold_mape_nuro() are set.
display_mape_nuro() {
    # Check if essential parameters are set (basic check)
    if [ -z "$NEW_IP6_PREFIX" ] || [ -z "$BR" ] || [ -z "$IPV4" ]; then
        debug_log "WARN" "display_mape_nuro: One or more essential MAP-E parameters are not set. Display may be incomplete."
        printf "%s\\n" "$(color yellow "$(get_message "MSG_MAPE_DISPLAY_INCOMPLETE")")"
    fi

    # Header for the display section
    # Assuming print_section_title or similar helper is available for consistent styling,
    # otherwise, use simple echo with color.
    if type print_section_title > /dev/null 2>&1; then
        print_section_title "DISPLAY_MAPE_NURO_TITLE" # Message key for "NURO MAP-E Configuration Details"
    else
        printf "\\n%s\\n" "$(color blue "--- NURO MAP-E Configuration Details ---")"
    fi

    printf "%s\\n" "$(color cyan "$(get_message "DISPLAY_SECTION_CALCULATED_PARAMS")")" # "Calculated MAP-E Parameters:"
    printf "  %-25s: %s\\n" "$(get_message "DISPLAY_LABEL_SOURCE_IPV6")" "$NEW_IP6_PREFIX" # "Source IPv6 Prefix"
    printf "  %-25s: %s\\n" "$(get_message "DISPLAY_LABEL_CE_IPV6")" "$CE" # "CE IPv6 Address"
    printf "  %-25s: %s\\n" "$(get_message "DISPLAY_LABEL_FULL_IPV4")" "$IPADDR" # "Resulting IPv4 Address"
    printf "  %-25s: %s\\n" "$(get_message "DISPLAY_LABEL_PSID_DEC")" "$PSID" # "PSID (Decimal)"
    printf "  %-25s: %s\\n" "$(get_message "DISPLAY_LABEL_BR_ADDRESS")" "$BR" # "Border Relay (Peer)"

    printf "\\n%s\\n" "$(color cyan "$(get_message "DISPLAY_SECTION_UCI_VALUES")")" # "OpenWrt UCI Configuration Values (for network.wanmap):"
    printf "  option%-20s '%s'\\n" " peeraddr" "$BR"
    printf "  option%-20s '%s'\\n" " ipaddr" "$IPV4" # e.g., 219.104.128.0
    printf "  option%-20s '%s'\\n" " ip4prefixlen" "$IP4PREFIXLEN" # e.g., 20
    printf "  option%-20s '%s::'\\n" " ip6prefix" "$IP6PFX" # e.g., 240d:f:0 (:: is appended)
    printf "  option%-20s '%s'\\n" " ip6prefixlen" "$IP6PREFIXLEN" # e.g., 36
    printf "  option%-20s '%s'\\n" " ealen" "$EALEN" # e.g., 20
    printf "  option%-20s '%s'\\n" " psidlen" "$PSIDLEN" # e.g., 8
    printf "  option%-20s '%s'\\n" " offset" "$OFFSET" # e.g., 4
    printf "  option%-20s '%s'\\n" " mtu" "1452" # Fixed value for NURO from map-e-nuro.sh
    printf "  option%-20s '%s'\\n" " encaplimit" "ignore" # Fixed value for NURO
    # legacymap and tunlink depend on OpenWrt version and are set in config_mape_nuro

    # Port Information
    # Calculate total available ports based on parameters
    # Total ports = (2^OFFSET - 1) * 2^(16 - OFFSET - PSIDLEN)
    # However, map-e-nuro.sh does not display total ports, it directly shows ranges.
    # We will use the PORTS variable generated by mold_mape_nuro().

    if [ -n "$PORTS" ]; then
        printf "\\n%s\\n" "$(color cyan "$(get_message "DISPLAY_SECTION_PORT_RANGES")")" # "Available Port Ranges:"
        # Display the PORTS string, interpreting newlines
        # The PORTS variable is already formatted with spaces and newlines by mold_mape_nuro
        printf "  %b\\n" "$PORTS" # Use %b to interpret backslash escapes like \n
    else
        debug_log "WARN" "display_mape_nuro: PORTS variable is empty. Cannot display port ranges."
    fi

    printf "\\n%s\\n" "$(color magenta "(config-softwire)# site-u2023/aios/internet-map-e-nuro.sh")"
    printf "\\n"
}

# Function to restore NURO MAP-E configuration from backups
# Restores network, dhcp, and firewall configs from ".map-e-nuro.bak" files.
# Based on site-u2023/aios/internet-map-e.sh restore_mape()
# and site-u2023/config-software/map-e-nuro.sh _func_RECOVERY()
# Returns:
#   0: If at least one backup file was successfully restored.
#   1: If no backup files were found to restore.
#   2: If one or more files failed to restore (but at least one backup was found).
restore_mape_nuro() {
    local files_to_restore_nuro
    local original_file backup_file
    local restored_count=0
    local not_found_count=0
    local failed_count=0
    local total_to_check=0
    local overall_status=1

    files_to_restore_nuro="
        /etc/config/network:/etc/config/network.map-e-nuro.bak
        /etc/config/dhcp:/etc/config/dhcp.map-e-nuro.bak
        /etc/config/firewall:/etc/config/firewall.map-e-nuro.bak
    "

    debug_log "INFO" "restore_mape_nuro: Starting restoration of NURO MAP-E configurations."

    echo "$files_to_restore_nuro" | while IFS= read -r item; do
        if [ -z "$item" ]; then continue; fi

        total_to_check=$((total_to_check + 1))
        original_file=$(echo "$item" | cut -d':' -f1)
        backup_file=$(echo "$item" | cut -d':' -f2)

        debug_log "DEBUG" "restore_mape_nuro: Checking backup '$backup_file' for '$original_file'."
        if [ -f "$backup_file" ]; then
            debug_log "INFO" "restore_mape_nuro: Backup file '$backup_file' found. Attempting to restore to '$original_file'."
            if cp "$backup_file" "$original_file"; then
                debug_log "INFO" "restore_mape_nuro: Successfully restored '$original_file' from '$backup_file'."
                restored_count=$((restored_count + 1))
            else
                local cp_rc=$?
                debug_log "ERROR" "restore_mape_nuro: Failed to restore '$original_file' from '$backup_file'. cp exit code: $cp_rc."
                failed_count=$((failed_count + 1))
            fi
        else
            debug_log "WARN" "restore_mape_nuro: Backup file '$backup_file' not found. Skipping restore for '$original_file'."
            not_found_count=$((not_found_count + 1))
        fi
    done

    debug_log "INFO" "restore_mape_nuro: Restore summary: Total checked=$total_to_check, Restored=$restored_count, Not found=$not_found_count, Failed=$failed_count."

    if [ "$failed_count" -gt 0 ]; then
        debug_log "ERROR" "restore_mape_nuro: Restore process completed with $failed_count failure(s)."
        overall_status=2
        printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_RESTORE_WITH_ERRORS" "COUNT=$failed_count")")"
    elif [ "$restored_count" -gt 0 ]; then
        debug_log "INFO" "restore_mape_nuro: Restore process completed. $restored_count file(s) restored successfully."
        overall_status=0
        printf "%s\\n" "$(color green "$(get_message "MSG_MAPE_RESTORE_COMPLETE_SUCCESS" "COUNT=$restored_count")")"
    else
        debug_log "WARN" "restore_mape_nuro: No backup files (.map-e-nuro.bak) were found to restore."
        overall_status=1
        printf "%s\\n" "$(color yellow "$(get_message "MSG_MAPE_NO_BACKUPS_FOUND_NURO")")"
    fi
    
    if [ "$overall_status" -eq 0 ] || [ "$overall_status" -eq 2 ]; then
        debug_log "INFO" "restore_mape_nuro: Attempting to remove 'map' package as part of NURO configuration restore."
        if opkg remove map >/dev/null 2>&1; then
            debug_log "INFO" "restore_mape_nuro: 'map' package removed successfully."
        else
            debug_log "INFO" "restore_mape_nuro: Failed to remove 'map' package or it was not installed. Continuing."
        fi
    fi

    return "$overall_status"
}

# Function to display available ports (for NURO Nichiban countermeasure)
# Based on _func_NICHIBAN_PORT from site-u2023/config-software/map-e-nuro.sh
display_nuro_ports() {
    local rules_file="/tmp/map-wanmap.rules" # File path from map-e-nuro.sh

    debug_log "INFO" "display_nuro_ports: Displaying PORTSETS from '$rules_file'."

    if [ -f "$rules_file" ]; then
        # Assuming get_message and color functions are available
        printf "\\n%s\\n" "$(color cyan "$(get_message "DISPLAY_NURO_PORTSETS_TITLE")")" # "NURO MAP-E Active Port Sets (from $rules_file):"
        
        # map-e-nuro.sh uses awk '/PORTSETS/'
        # We will replicate this. Output will be whatever map.sh puts in that file.
        awk '/PORTSETS/' "$rules_file"
        
        printf "\\n"
        # map-e-nuro.sh has a read -p here. We'll make it optional or handled by calling context.
        # For now, just display.
    else
        debug_log "WARN" "display_nuro_ports: Rules file '$rules_file' not found. Cannot display port sets."
        printf "%s\\n" "$(color yellow "$(get_message "MSG_MAPE_NURO_RULES_FILE_NOT_FOUND" "FILE=$rules_file")")"
        return 1
    fi
    return 0
}

# Function to replace /lib/netifd/proto/map.sh for NURO (Nichiban countermeasure)
# Based on _func_NICHIBAN from site-u2023/config-software/map-e-nuro.sh
# and structure from site-u2023/aios/internet-map-e.sh replace_map_sh().
# Returns:
#   0 on success (script downloaded and permissions set)
#   1 on download failure or if downloaded file is empty
#   2 on chmod failure (download was successful)
#   3 if OS version is not recognized for this function
replace_map_sh_nuro() {
    local proto_script_path="/lib/netifd/proto/map.sh"
    local backup_script_path="${proto_script_path}.nuro-orig-bak" # Specific backup name for this operation
    local openwrt_release_major
    local source_url=""
    local wget_exit_code
    # WGET_IPV_OPT should be defined globally, e.g., "-4" or "-6" or ""
    # For NURO, IPv6 is primary, so -6 might be preferable if WAN6 is up.
    # map-e-nuro.sh uses wget without explicit -4/-6. We'll assume WGET_IPV_OPT is available or default to no option.
    local current_wget_opts="${WGET_IPV_OPT:-}" # Use global or empty if not set

    debug_log "INFO" "replace_map_sh_nuro: Starting replacement of $proto_script_path for NURO."

    # Determine OpenWrt major release
    openwrt_release_major=$(grep 'DISTRIB_RELEASE' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2 | cut -c 1-2)
    debug_log "DEBUG" "replace_map_sh_nuro: Detected OpenWrt major release: '$openwrt_release_major'"

    # Determine source URL based on OpenWrt version (logic from map-e-nuro.sh)
    if [ "$openwrt_release_major" = "SN" ] || \
       ( [ -n "$openwrt_release_major" ] && [ "$openwrt_release_major" -ge 21 ] && [ "$openwrt_release_major" -le 24 ] ); then # Covers 21, 22, 23, 24, SN
        source_url="https://raw.githubusercontent.com/site-u2023/map-e/main/map.sh.new"
        debug_log "INFO" "replace_map_sh_nuro: Target OpenWrt version ($openwrt_release_major) uses map.sh.new."
    elif [ "$openwrt_release_major" = "19" ]; then
        source_url="https://raw.githubusercontent.com/site-u2023/map-e/main/map19.sh.new" # map-e-nuro.sh uses map19.sh.new for 19.x
        debug_log "INFO" "replace_map_sh_nuro: Target OpenWrt version (19) uses map19.sh.new."
    else
        debug_log "ERROR" "replace_map_sh_nuro: OpenWrt release '$openwrt_release_major' is not supported for map.sh replacement by this NURO script."
        printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_UNSUPPORTED_OS_FOR_MAP_SH" "VERSION=$openwrt_release_major")")"
        return 3 # OS version not recognized
    fi
    debug_log "DEBUG" "replace_map_sh_nuro: Source URL for map.sh: $source_url"

    # Backup the original map.sh script if it exists
    if [ -f "$proto_script_path" ]; then
        debug_log "DEBUG" "replace_map_sh_nuro: Backing up '$proto_script_path' to '$backup_script_path'..."
        if cp "$proto_script_path" "$backup_script_path"; then
            debug_log "INFO" "replace_map_sh_nuro: Original '$proto_script_path' backed up to '$backup_script_path'."
        else
            local cp_rc=$?
            debug_log "WARN" "replace_map_sh_nuro: Failed to back up '$proto_script_path'. cp exit code: $cp_rc."
            # Continue anyway, as replacing is the primary goal.
        fi
    else
        debug_log "INFO" "replace_map_sh_nuro: Original '$proto_script_path' not found. Skipping backup."
    fi

    # Download the new map.sh script
    # map-e-nuro.sh uses `wget --no-check-certificate -O ...`
    debug_log "INFO" "replace_map_sh_nuro: Downloading from '$source_url' to '$proto_script_path'..."
    # Adding -q for quiet, but errors will still go to stderr if wget fails badly.
    command wget -q $current_wget_opts --no-check-certificate -O "$proto_script_path" "$source_url"
    wget_exit_code=$?

    if [ "$wget_exit_code" -eq 0 ]; then
        # Check if the downloaded file is not empty
        if [ -s "$proto_script_path" ]; then
            debug_log "INFO" "replace_map_sh_nuro: Download successful. '$proto_script_path' has been updated."
            # Set execute permissions
            debug_log "DEBUG" "replace_map_sh_nuro: Setting execute permission on '$proto_script_path'."
            if chmod +x "$proto_script_path"; then
                debug_log "INFO" "replace_map_sh_nuro: Execute permission set successfully for '$proto_script_path'."
                printf "%s\\n" "$(color green "$(get_message "MSG_MAPE_MAP_SH_REPLACED_SUCCESS")")"
                # map-e-nuro.sh includes a reboot prompt here.
                # This function will just do the replacement. Reboot decision is up to the main script.
                return 0 # Success
            else
                local chmod_rc=$?
                debug_log "ERROR" "replace_map_sh_nuro: chmod +x FAILED for '$proto_script_path'. Exit code: $chmod_rc."
                printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_MAP_SH_CHMOD_FAILED" "FILE=$proto_script_path")")"
                return 2 # chmod failure
            fi
        else
            debug_log "ERROR" "replace_map_sh_nuro: wget reported success (exit code 0), but the downloaded file '$proto_script_path' is EMPTY."
            printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_MAP_SH_DOWNLOAD_EMPTY" "URL=$source_url")")"
            # Attempt to restore backup if it exists and download failed to produce a valid file
            if [ -f "$backup_script_path" ]; then
                debug_log "INFO" "replace_map_sh_nuro: Attempting to restore original from '$backup_script_path' due to empty download."
                if cp "$backup_script_path" "$proto_script_path"; then
                    debug_log "INFO" "replace_map_sh_nuro: Original '$proto_script_path' restored from backup."
                else
                    debug_log "WARN" "replace_map_sh_nuro: Failed to restore original from backup after empty download."
                fi
            fi
            return 1 # Downloaded file is empty
        fi
    else
        debug_log "ERROR" "replace_map_sh_nuro: wget download FAILED. Exit code: $wget_exit_code. URL: $source_url"
        printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_MAP_SH_DOWNLOAD_FAILED" "URL=$source_url" "CODE=$wget_exit_code")")"
        # No attempt to restore backup here, as the original might still be in place if wget failed to overwrite.
        return 1 # wget failure
    fi
}

# Function to display available ports (for NURO Nichiban countermeasure)
# Based on _func_NICHIBAN_PORT from site-u2023/config-software/map-e-nuro.sh
display_nuro_ports() {
    local rules_file="/tmp/map-wanmap.rules" # File path from map-e-nuro.sh

    debug_log "INFO" "display_nuro_ports: Displaying PORTSETS from '$rules_file'."

    if [ -f "$rules_file" ]; then
        # Assuming get_message and color functions are available
        printf "\\n%s\\n" "$(color cyan "$(get_message "DISPLAY_NURO_PORTSETS_TITLE")")" # "NURO MAP-E Active Port Sets (from $rules_file):"
        
        # map-e-nuro.sh uses awk '/PORTSETS/'
        # We will replicate this. Output will be whatever map.sh puts in that file.
        awk '/PORTSETS/' "$rules_file"
        
        printf "\\n"
        # map-e-nuro.sh has a read -p here. We'll make it optional or handled by calling context.
        # For now, just display.
    else
        debug_log "WARN" "display_nuro_ports: Rules file '$rules_file' not found. Cannot display port sets."
        printf "%s\\n" "$(color yellow "$(get_message "MSG_MAPE_NURO_RULES_FILE_NOT_FOUND" "FILE=$rules_file")")"
        return 1
    fi
    return 0
}

# Function to recover the original map.sh script (for NURO Nichiban countermeasure)
# Based on _func_NICHIBAN_RECOVERY from site-u2023/config-software/map-e-nuro.sh
# Returns:
#   0 if recovery was attempted (successful or not, if backup existed)
#   1 if backup file was not found
recover_original_map_sh_nuro() {
    local proto_script_path="/lib/netifd/proto/map.sh"
    local backup_script_path="${proto_script_path}.nuro-orig-bak" # Must match the backup name used in replace_map_sh_nuro

    debug_log "INFO" "recover_original_map_sh_nuro: Attempting to recover original '$proto_script_path' from '$backup_script_path'."

    if [ -f "$backup_script_path" ]; then
        if cp "$backup_script_path" "$proto_script_path"; then
            debug_log "INFO" "recover_original_map_sh_nuro: Original '$proto_script_path' successfully restored from '$backup_script_path'."
            printf "%s\\n" "$(color green "$(get_message "MSG_MAPE_MAP_SH_RECOVER_SUCCESS")")"
            # map-e-nuro.sh includes a reboot prompt here.
            # This function will just do the recovery. Reboot decision is up to the main script.
            return 0
        else
            local cp_rc=$?
            debug_log "ERROR" "recover_original_map_sh_nuro: Failed to restore '$proto_script_path' from '$backup_script_path'. cp exit code: $cp_rc."
            printf "%s\\n" "$(color red "$(get_message "MSG_MAPE_MAP_SH_RECOVER_FAILED" "FILE=$proto_script_path")")"
            return 0 # Still return 0 as an attempt was made based on backup presence
        fi
    else
        debug_log "WARN" "recover_original_map_sh_nuro: Backup file '$backup_script_path' not found. Cannot recover."
        printf "%s\\n" "$(color yellow "$(get_message "MSG_MAPE_MAP_SH_BACKUP_NOT_FOUND" "FILE=$backup_script_path")")"
        return 1 # Backup not found
    fi
}

internet_map_nuro_main() {

    print_section_title "MENU_INTERNET_MAPE"

    # MAP-Eパラメータ計算
    if ! mape_nuro_mold; then
        debug_log "DEBUG" "mape_mold function failed. Exiting script."
        return 1
    fi
    
    install_package map hidden

    mape_nuro_config
    
    mape_nuro_display
    
    reboot

    return 0 # Explicitly exit with success status
}

# internet_map_nuro_main
