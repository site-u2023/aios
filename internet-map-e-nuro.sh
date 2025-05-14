#!/bin/sh
# Information provided by https://github.com/tinysun
# Vr.4.01
# License: CC0

SCRIPT_VERSION="2025.05.14-00-00"

# OpenWrt関数をロード
. /lib/functions/network.sh

# Function to get IPv4 base address for NURO (ruleprefix36)
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
mold_mape_nuro() {
    local NET_IF6
    network_flush_cache
    network_find_wan6 NET_IF6
    network_get_prefix6 NET_PFX6 "${NET_IF6}"

    if [ -z "$NET_PFX6" ]; then
        debug_log "DEBUG" "mold_mape_nuro: NET_PFX6 is not set. Cannot proceed."
        printf "%s\\n" "$(color "red" "$(get_message "MSG_MAPE_IPV6_PREFIX_FAILED" "DETAIL=NET_PFX6_empty")")"
        return 1
    fi

    NEW_IP6_PREFIX=$(echo "$NET_PFX6" | cut -d'/' -f1)
    if [ -z "$NEW_IP6_PREFIX" ]; then
        debug_log "DEBUG" "mold_mape_nuro: Failed to extract address part from NET_PFX6 ('$NET_PFX6')."
        printf "%s\\n" "$(color "red" "$(get_message "MSG_MAPE_IPV6_PREFIX_FAILED" "DETAIL=NET_PFX6_parse_fail")")"
        return 1
    fi
    debug_log "DEBUG" "mold_mape_nuro: Using source IPv6 for MAP-E: $NEW_IP6_PREFIX (derived from NET_PFX6: $NET_PFX6)"

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
            if ($1 == "") $1 = "0"; if ($NF == "" && NF == 8) $NF = "0"; if (NF == 1 && $1 == "") $1 = "0"
        }
        h0 = $1; if (h0 == "") h0 = "0"; h1 = $2; if (h1 == "") h1 = "0"
        h2 = $3; if (h2 == "") h2 = "0"; h3 = $4; if (h3 == "") h3 = "0"
        print h0 " " h1 " " h2 " " h3
    }')

    read -r h0_str h1_str h2_str h3_str <<EOF
$awk_output
EOF

    if [ -z "$h0_str" ]; then
        printf "%s\\n" "$(color "red" "$(get_message "MSG_MAPE_IPV6_AWK_PARSE_FAILED")")"
        debug_log "DEBUG" "mold_mape_nuro: Failed to parse IPv6 address part using awk. Input: '${ipv6_addr}'"
        return 1
    fi

    local HEXTET0 HEXTET1 HEXTET2 HEXTET3
    HEXTET0=$(printf %d "0x${h0_str:-0}")
    HEXTET1=$(printf %d "0x${h1_str:-0}")
    HEXTET2=$(printf %d "0x${h2_str:-0}")
    HEXTET3=$(printf %d "0x${h3_str:-0}")

    debug_log "DEBUG" "mold_mape_nuro: Parsed HEXTETs (str): $h0_str:$h1_str:$h2_str:$h3_str (dec): $HEXTET0:$HEXTET1:$HEXTET2:$HEXTET3"

    local ruleprefix_h0_part_numeric=$((HEXTET0 * 65536))
    local ruleprefix_h1_part_numeric=$HEXTET1
    local ruleprefix_h2_byte_for_key=$(( (HEXTET2 & 0xff00) >> 8 ))
    local calculated_numeric_key=$(( (ruleprefix_h0_part_numeric + ruleprefix_h1_part_numeric) * 256 + ruleprefix_h2_byte_for_key ))
    local prefix36_hex_key_lookup
    prefix36_hex_key_lookup=$(printf "0x%x" "$calculated_numeric_key")

    debug_log "DEBUG" "mold_mape_nuro: Calculated prefix36_hex_key_lookup=$prefix36_hex_key_lookup"

    BR=""; IPV4=""; IPADDR=""; IP4PREFIXLEN=""; IP6PFX=""; IP6PREFIXLEN=""
    EALEN=""; PSIDLEN=""; OFFSET=""; PSID=0; PORTS=""; CE=""; IPV6PREFIX=""

    local octet_str octet1 octet2 octet3
    octet_str=$(get_ruleprefix36_value "$prefix36_hex_key_lookup")

    if [ -n "$octet_str" ]; then
        debug_log "DEBUG" "mold_mape_nuro: Matched NURO rule key '$prefix36_hex_key_lookup'. Octets: $octet_str"
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

        local h2_upper_byte_only_val=$(( HEXTET2 & 0xff00 ))
        IP6PFX="${h0_str}:${h1_str}:$(printf %04x "$h2_upper_byte_only_val")"

        debug_log "DEBUG" "mold_mape_nuro: NURO Params: IPV4=$IPV4/$IP4PREFIXLEN, IP6PFX=$IP6PFX/$IP6PREFIXLEN, PSID=$PSID"
    else
        debug_log "DEBUG" "mold_mape_nuro: No matching NURO rule for key '$prefix36_hex_key_lookup'."
        printf "%s\\n" "$(color "red" "$(get_message "MSG_MAPE_UNSUPPORTED_PREFIX_RULE")")"
        return 1
    fi

    PORTS=""
    local AMAX=$(( (1 << OFFSET) - 1 ))
    local A
    for A in $(seq 1 "$AMAX"); do
        local shift_bits=$(( 16 - OFFSET ))
        local port_base=$(( A << shift_bits ))
        local psid_shift_val=$(( 16 - OFFSET - PSIDLEN ))
         if [ "$psid_shift_val" -lt 0 ]; then psid_shift_val=0; fi
        local psid_part=$(( PSID << psid_shift_val ))
        local port_start=$(( port_base | psid_part ))
        local port_range_size=$(( 1 << psid_shift_val ))
        if [ "$port_range_size" -le 0 ]; then port_range_size=1; fi
        local port_end=$(( port_start + port_range_size - 1 ))

        if [ "$port_start" -lt 1 ]; then port_start=1; fi
        if [ "$port_end" -gt 65535 ]; then port_end=65535; fi
        if [ "$port_start" -gt "$port_end" ]; then continue; fi

        PORTS="${PORTS}${port_start}-${port_end}"
        if [ "$A" -lt "$AMAX" ]; then
            if [ $(( A % 3 )) -eq 0 ]; then PORTS="${PORTS}\n"; else PORTS="${PORTS} "; fi
        fi
    done

    local ce_octet1_disp ce_octet2_disp ce_octet3_disp ce_octet4_disp
    ce_octet1_disp=$(echo "$IPADDR" | cut -d. -f1)
    ce_octet2_disp=$(echo "$IPADDR" | cut -d. -f2)
    ce_octet3_disp=$(echo "$IPADDR" | cut -d. -f3)
    ce_octet4_disp=$(echo "$IPADDR" | cut -d. -f4)

    local CE_HEXTET0=$HEXTET0; local CE_HEXTET1=$HEXTET1
    local CE_HEXTET2=$HEXTET2; local CE_HEXTET3=$(( HEXTET3 & 0xff00 ))
    local CE_HEXTET4=$ce_octet1_disp
    local CE_HEXTET5=$(( (ce_octet2_disp << 8) | ce_octet3_disp ))
    local CE_HEXTET6=$(( ce_octet4_disp << 8 ))
    local CE_HEXTET7=$(( PSID << 8 ))

    CE="$(printf %04x "$CE_HEXTET0"):$(printf %04x "$CE_HEXTET1"):$(printf %04x "$CE_HEXTET2"):$(printf %04x "$CE_HEXTET3"):$(printf %04x "$CE_HEXTET4"):$(printf %04x "$CE_HEXTET5"):$(printf %04x "$CE_HEXTET6"):$(printf %04x "$CE_HEXTET7")"
    debug_log "DEBUG" "mold_mape_nuro: CE IPv6: $CE"

    IPV6PREFIX="${h0_str}:${h1_str}:${h2_str}:${h3_str}::"

    debug_log "DEBUG" "mold_mape_nuro: MAP-E parameter calculation for NURO completed."
    return 0
}

mape_nuro_config() {
    local wanmap_if='wanmap'
    local firewall_zone_idx='1'
    local openwrt_release_major

    debug_log "DEBUG" "mape_nuro_config: Backing up configuration files..."
    cp /etc/config/network /etc/config/network.map-e-nuro.bak && debug_log "DEBUG" "mape_nuro_config: network backup created (.map-e-nuro.bak)." || debug_log "DEBUG" "mape_nuro_config: Failed to backup network config."
    cp /etc/config/dhcp /etc/config/dhcp.map-e-nuro.bak && debug_log "DEBUG" "mape_nuro_config: dhcp backup created (.map-e-nuro.bak)." || debug_log "DEBUG" "mape_nuro_config: Failed to backup dhcp config."
    cp /etc/config/firewall /etc/config/firewall.map-e-nuro.bak && debug_log "DEBUG" "mape_nuro_config: firewall backup created (.map-e-nuro.bak)." || debug_log "DEBUG" "mape_nuro_config: Failed to backup firewall config."

    debug_log "DEBUG" "mape_nuro_config: Applying NURO MAP-E UCI settings."

    debug_log "DEBUG" "mape_nuro_config: Setting DHCP LAN..."
    uci set dhcp.lan.ra='relay'
    uci set dhcp.lan.dhcpv6='server'
    uci set dhcp.lan.ndp='relay'
    uci set dhcp.lan.force='1'

    debug_log "DEBUG" "mape_nuro_config: Setting WAN interface (network.wan.auto='1')..."
    uci set network.wan.auto='1'

    debug_log "DEBUG" "mape_nuro_config: Setting DHCP WAN6..."
    uci set dhcp.wan6=dhcp
    uci set dhcp.wan6.interface='wan'
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
        debug_log "DEBUG" "mape_nuro_config: Applying settings for OpenWrt $openwrt_release_major (21-24, SN)..."
        uci set dhcp.wan6.ignore='1'
        uci set network."$wanmap_if".legacymap='1'
        uci set network."$wanmap_if".tunlink='wan6'
    elif [ "$openwrt_release_major" = "19" ]; then
        debug_log "DEBUG" "mape_nuro_config: Applying settings for OpenWrt 19..."
        uci -q delete network."$wanmap_if".tunlink
        uci add_list network."$wanmap_if".tunlink='wan6'
    else
        debug_log "DEBUG" "mape_nuro_config: OpenWrt release '$openwrt_release_major' not explicitly handled by version-specific settings. Applying defaults which might be similar to 21+."
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

    debug_log "DEBUG" "mape_nuro_config: Committing all UCI changes..."
    local commit_success=1
    if ! uci commit dhcp; then
        debug_log "DEBUG" "mape_nuro_config: 'uci commit dhcp' failed."
        commit_success=0
    fi
    if ! uci commit network; then
        debug_log "DEBUG" "mape_nuro_config: 'uci commit network' failed."
        commit_success=0
    fi
    if ! uci commit firewall; then
        debug_log "DEBUG" "mape_nuro_config: 'uci commit firewall' failed."
        commit_success=0
    fi

    if [ "$commit_success" -eq 1 ]; then
        debug_log "DEBUG" "mape_nuro_config: All UCI changes committed successfully."
        return 0
    else
        debug_log "DEBUG" "mape_nuro_config: One or more UCI commit operations failed."
        # MSG_MAPE_UCI_COMMIT_FAILED is not in internet-map-e.sh, using direct English.
        printf "%s\\n" "$(color "red" "Error: UCI commit failed.")"
        return 1
    fi
}

display_mape_nuro() {
    # Parameter check: internet-map-e.sh display_mape does not have this initial check. Removing.
    # if [ -z "$NEW_IP6_PREFIX" ] || [ -z "$BR" ] || [ -z "$IPV4" ]; then
    #     debug_log "DEBUG" "display_mape_nuro: One or more essential MAP-E parameters are not set. Display may be incomplete."
    #     # MSG_MAPE_DISPLAY_INCOMPLETE is not in internet-map-e.sh. Removing printf.
    # fi

    # Header for the display section
    # internet-map-e.sh uses print_section_title "MENU_INTERNET_MAPE" in main, not in display_mape.
    # display_mape in internet-map-e.sh directly prints titles.
    printf "\\n%s\\n" "$(color "$CLR_BLUE" "--- NURO MAP-E Configuration Details ---")" # Retaining NURO specific title

    # Calculated Parameters Title (mimicking internet-map-e.sh's display_mape direct print style)
    printf "%s\\n" "$(color "$CLR_CYAN" "Calculated MAP-E Parameters:")" # Direct English
    printf "  %-25s: %s\\n" "Source IPv6 Prefix" "$NEW_IP6_PREFIX"
    printf "  %-25s: %s\\n" "CE IPv6 Address" "$CE"
    printf "  %-25s: %s\\n" "Resulting IPv4 Address" "$IPADDR"
    printf "  %-25s: %s\\n" "PSID (Decimal)" "$PSID"
    printf "  %-25s: %s\\n" "Border Relay (Peer)" "$BR"

    # UCI Values Title (mimicking internet-map-e.sh's display_mape direct print style)
    printf "\\n%s\\n" "$(color "$CLR_CYAN" "OpenWrt UCI Configuration Values (for network.wanmap):")" # Direct English
    printf "  option%-20s '%s'\\n" " peeraddr" "$BR"
    printf "  option%-20s '%s'\\n" " ipaddr" "$IPV4"
    printf "  option%-20s '%s'\\n" " ip4prefixlen" "$IP4PREFIXLEN"
    printf "  option%-20s '%s::'\\n" " ip6prefix" "$IP6PFX"
    printf "  option%-20s '%s'\\n" " ip6prefixlen" "$IP6PREFIXLEN"
    printf "  option%-20s '%s'\\n" " ealen" "$EALEN"
    printf "  option%-20s '%s'\\n" " psidlen" "$PSIDLEN"
    printf "  option%-20s '%s'\\n" " offset" "$OFFSET"
    printf "  option%-20s '%s'\\n" " mtu" "1452"
    printf "  option%-20s '%s'\\n" " encaplimit" "ignore"

    if [ -n "$PORTS" ]; then
        # Port Ranges Title (mimicking internet-map-e.sh's display_mape direct print style)
        printf "\\n%s\\n" "$(color "$CLR_CYAN" "Available Port Ranges:")" # Direct English
        printf "  %b\\n" "$PORTS"
    else
        debug_log "DEBUG" "display_mape_nuro: PORTS variable is empty. Cannot display port ranges."
    fi

    printf "\\n%s\\n" "$(color "$CLR_MAGENTA" "(config-softwire)# site-u2023/aios/internet-map-e-nuro.sh")"
    printf "\\n"

    # display_mape in internet-map-e.sh has these success messages and read.
    printf "%s\n" "$(color green "$(get_message "MSG_MAPE_PARAMS_CALC_SUCCESS")")"
    printf "%s\n" "$(color yellow "$(get_message "MSG_MAPE_APPLY_SUCCESS")")"
    read -r -n 1 -s
}

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

    debug_log "DEBUG" "restore_mape_nuro: Starting restoration of NURO MAP-E configurations."

    echo "$files_to_restore_nuro" | while IFS= read -r item; do
        if [ -z "$item" ]; then continue; fi
        total_to_check=$((total_to_check + 1))
        original_file=$(echo "$item" | cut -d':' -f1)
        backup_file=$(echo "$item" | cut -d':' -f2)

        debug_log "DEBUG" "restore_mape_nuro: Checking backup '$backup_file' for '$original_file'."
        if [ -f "$backup_file" ]; then
            debug_log "DEBUG" "restore_mape_nuro: Backup file '$backup_file' found. Attempting to restore to '$original_file'."
            if cp "$backup_file" "$original_file"; then
                debug_log "DEBUG" "restore_mape_nuro: Successfully restored '$original_file' from '$backup_file'."
                restored_count=$((restored_count + 1))
            else
                local cp_rc=$?
                debug_log "DEBUG" "restore_mape_nuro: Failed to restore '$original_file' from '$backup_file'. cp exit code: $cp_rc."
                failed_count=$((failed_count + 1))
            fi
        else
            debug_log "DEBUG" "restore_mape_nuro: Backup file '$backup_file' not found. Skipping restore for '$original_file'."
            not_found_count=$((not_found_count + 1))
        fi
    done

    debug_log "DEBUG" "restore_mape_nuro: Restore summary: Total checked=$total_to_check, Restored=$restored_count, Not found=$not_found_count, Failed=$failed_count."

    if [ "$failed_count" -gt 0 ]; then
        debug_log "DEBUG" "restore_mape_nuro: Restore process completed with $failed_count failure(s)."
        # MSG_MAPE_RESTORE_WITH_ERRORS is not in internet-map-e.sh. Using direct English.
        printf "%s\\n" "$(color "red" "Error: Restore completed with $failed_count failure(s).")"
        overall_status=2
    elif [ "$restored_count" -gt 0 ]; then
        debug_log "DEBUG" "restore_mape_nuro: Restore process completed. $restored_count file(s) restored successfully."
        printf "%s\\n" "$(color "$CLR_GREEN" "$(get_message "MSG_MAPE_RESTORE_COMPLETE" "COUNT=$restored_count")")" # Using MSG_MAPE_RESTORE_COMPLETE from internet-map-e.sh
        overall_status=0
    else
        debug_log "DEBUG" "restore_mape_nuro: No backup files (.map-e-nuro.bak) were found to restore."
        printf "%s\\n" "$(color "$CLR_YELLOW" "$(get_message "MSG_NO_BACKUP_FOUND")")" # Using MSG_NO_BACKUP_FOUND from internet-map-e.sh
        overall_status=1
    fi
    
    if [ "$overall_status" -eq 0 ] || [ "$overall_status" -eq 2 ]; then
        debug_log "DEBUG" "restore_mape_nuro: Attempting to remove 'map' package as part of NURO configuration restore."
        if opkg remove map >/dev/null 2>&1; then
            debug_log "DEBUG" "restore_mape_nuro: 'map' package removed successfully."
        else
            debug_log "DEBUG" "restore_mape_nuro: Failed to remove 'map' package or it was not installed. Continuing."
        fi
        # Messages from internet-map-e.sh restore_mape function
        # printf "\n%s\n" "$(color green "$(get_message "MSG_MAPE_RESTORE_COMPLETE")")" # Already printed above if successful
        printf "%s\n" "$(color yellow "$(get_message "MSG_MAPE_APPLY_SUCCESS")")" # This seems to be a generic "apply changes" message.
        read -r -n 1 -s
        # Reboot is handled by internet-map-e.sh restore_mape after these messages.
    fi

    return "$overall_status"
}

display_nuro_ports() {
    local rules_file="/tmp/map-wanmap.rules"

    debug_log "DEBUG" "display_nuro_ports: Displaying PORTSETS from '$rules_file'."

    if [ -f "$rules_file" ]; then
        # No specific message key for this title in internet-map-e.sh. Using direct English.
        printf "\\n%s\\n" "$(color "$CLR_CYAN" "NURO MAP-E Active Port Sets (from $rules_file):")"
        awk '/PORTSETS/' "$rules_file"
        printf "\\n"
    else
        debug_log "DEBUG" "display_nuro_ports: Rules file '$rules_file' not found. Cannot display port sets."
        # No specific message key for this error in internet-map-e.sh. Using direct English.
        printf "%s\\n" "$(color "$CLR_YELLOW" "Warning: Rules file '$rules_file' not found. Cannot display port sets.")"
        return 1
    fi
    return 0
}

internet_map_nuro_main() {
    if type print_section_title > /dev/null 2>&1; then
        print_section_title "MENU_INTERNET_MAPE" # This key exists in internet-map-e.sh
    else
        debug_log "DEBUG" "internet_map_nuro_main: Starting NURO MAP-E Setup."
    fi

    if ! mold_mape_nuro; then
        debug_log "DEBUG" "internet_map_nuro_main: mold_mape_nuro function failed. Exiting script."
        return 1
    fi
    
    if ! install_package map hidden; then
        debug_log "DEBUG" "internet_map_nuro_main: Failed to install 'map' package. Exiting." # Critical, so exit
        return 1
    fi

    if ! mape_nuro_config; then
        debug_log "DEBUG" "internet_map_nuro_main: mape_nuro_config function failed. UCI settings might be inconsistent."
        return 1
    fi
    
    display_mape_nuro # This function now handles its own final messages and read
    
    debug_log "DEBUG" "internet_map_nuro_main: Configuration complete. Rebooting system."
    reboot

    return 0
}
