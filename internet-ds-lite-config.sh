#!/bin/sh

SCRIPT_VERSION="2025.05.19-00-00"

. /lib/functions/network.sh

DSLITE_AFTR_IP=""
DSLITE_DISPLAY_NAME=""

DSLITE_PROTO_SCRIPT_PATH="/lib/netifd/proto/dslite.sh"
DSLITE_PROTO_SCRIPT_BACKUP_PATH="${DSLITE_PROTO_SCRIPT_PATH}.bak"

DETECTED_AFTR_INFO=""
DETECTED_PROVIDER_DISPLAY_NAME=""
DETECTED_PROVIDER_KEY=""

check_ipv6_reachability_dslite() {
    local addr="$1"
    if [ -z "$addr" ]; then
        debug_log "DEBUG" "check_ipv6_reachability_dslite: No address provided."
        return 1
    fi
    if ping -6 -c 1 -w 2 "$addr" >/dev/null 2>&1; then
        debug_log "DEBUG" "check_ipv6_reachability_dslite: IPv6 address $addr is reachable."
        return 0
    else
        debug_log "DEBUG" "check_ipv6_reachability_dslite: IPv6 address $addr is NOT reachable."
        return 1
    fi
}

decode_hex_aftr_name_dslite() {
    local hexstr="$1"
    if [ -z "$hexstr" ]; then
        echo ""
        return
    fi
    echo "$hexstr" | sed 's/../& /g' | awk '{for(i=1;i<=NF;i++) printf "%c", "0x"$i; print ""}'
}

ipv6_address_dslite() {
    local addr="$1"
    local gua_addr=""

    if [ -z "$addr" ]; then
        return 1
    fi

    if network_get_ipaddr6 gua_addr "$addr" 2>/dev/null && [ -n "$gua_addr" ]; then
        addr="$gua_addr"
    fi

    case "$addr" in
        2[0-9a-fA-F]*|3[0-9a-fA-F]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

get_aaaa_record_dslite() {
    local hostname="$1"
    local resolved_ip=""
    local nslookup_output=""

    if [ -z "$hostname" ]; then
        debug_log "DEBUG" "get_aaaa_record_dslite: Hostname is empty."
        echo ""
        return
    fi

    nslookup_output=$(nslookup -type=AAAA "$hostname" 2>/dev/null)

    if [ -n "$nslookup_output" ]; then
        resolved_ip=$(echo "$nslookup_output" | grep -i '^Address:' | awk '{print $2}' | head -n1)
    fi

    if [ -n "$resolved_ip" ]; then
        if ipv6_address_dslite "$resolved_ip"; then
            debug_log "DEBUG" "get_aaaa_record_dslite: Resolved $hostname to AAAA: $resolved_ip (using nslookup). Validation by ipv6_address_dslite successful."
            echo "$resolved_ip"
        else
            debug_log "DEBUG" "get_aaaa_record_dslite: Resolved IP '$resolved_ip' for hostname '$hostname' (using nslookup) is not a valid IPv6 format according to ipv6_address_dslite."
            echo ""
        fi
    else
        debug_log "DEBUG" "get_aaaa_record_dslite: Could not resolve AAAA record for hostname '$hostname' using nslookup, or nslookup output was empty/unparseable."
        echo ""
    fi
}

manual_dslite() {
    local aftr_value="$1"

    debug_log "DEBUG" "manual_dslite: Configuring DS-Lite manually with AFTR: $aftr_value (confirmation is handled by the menu system)."

    DETECTED_AFTR_INFO="$aftr_value"
    DETECTED_PROVIDER_DISPLAY_NAME="$(get_message "${SELECTED_MENU_KEY}")"
    DETECTED_PROVIDER_KEY="manual"

    DSLITE_AFTR_IP="$aftr_value"
    DSLITE_DISPLAY_NAME="$(get_message "${SELECTED_MENU_KEY}")"

    return 0
}

get_dslite() {
    local manual_input_specifier="$1"

    DHCP_AFTR_NAME=""

    if [ -n "$manual_input_specifier" ]; then
        debug_log "DEBUG" "get_dslite: Manual mode (input specifier present: '$manual_input_specifier'), calling manual_dslite()."
        manual_dslite "$manual_input_specifier"
        return $?
    fi
    
    debug_log "DEBUG" "get_dslite: Automatic mode. Starting AFTR name detection from DHCP."
    
    local logical_wan6_ifname=""
    local physical_wan_ifname=""
    local lease_file="/tmp/hosts/odhcp6c"
    local aftr_name_option_code="24"
    local raw_aftr_name=""
    local exit_status=0

    network_find_wan6 logical_wan6_ifname

    if [ -z "$logical_wan6_ifname" ]; then
        debug_log "DEBUG" "get_dslite: Could not find logical IPv6 WAN interface (wan6) or network_find_wan6 failed to set it."
        exit_status=1
    fi

    if [ "$exit_status" -eq 0 ]; then
        network_get_physdev physical_wan_ifname "$logical_wan6_ifname"

        if [ -z "$physical_wan_ifname" ]; then
            debug_log "DEBUG" "get_dslite: Could not find physical device for $logical_wan6_ifname or network_get_physdev failed to set it."
            exit_status=1
        fi
    fi
    
    if [ "$exit_status" -eq 0 ]; then
        debug_log "DEBUG" "get_dslite: Found logical IPv6 WAN interface: $logical_wan6_ifname, Physical device: $physical_wan_ifname" 
        if [ ! -f "$lease_file" ]; then
            debug_log "DEBUG" "get_dslite: Lease file '$lease_file' not found."
            exit_status=1
        fi
    fi

    if [ "$exit_status" -eq 0 ]; then
        raw_aftr_name=$(grep "^${physical_wan_ifname} .*aftr-name" "$lease_file" | awk '{print $NF}' 2>/dev/null)

        if [ -z "$raw_aftr_name" ]; then
            local hex_encoded_aftr_name
            hex_encoded_aftr_name=$(grep "^${physical_wan_ifname} ${aftr_name_option_code} " "$lease_file" | awk '{print $3}' 2>/dev/null)

            if [ -n "$hex_encoded_aftr_name" ]; then
                debug_log "DEBUG" "get_dslite: Found HEX encoded AFTR name '$hex_encoded_aftr_name' for $physical_wan_ifname. Decoding."
                raw_aftr_name=$(echo "$hex_encoded_aftr_name" | sed 's/../\\x&/g' | xargs printf "%b" 2>/dev/null)
                if [ $? -ne 0 ] || [ -z "$raw_aftr_name" ]; then
                    debug_log "DEBUG" "get_dslite: Failed to decode HEX AFTR name or result was empty: '$hex_encoded_aftr_name'."
                    raw_aftr_name=""
                else
                    debug_log "DEBUG" "get_dslite: Decoded HEX AFTR name: '$raw_aftr_name'."
                fi
            fi
        fi

        if [ -z "$raw_aftr_name" ]; then
            debug_log "DEBUG" "get_dslite: Could not retrieve AFTR name from lease file for interface '$physical_wan_ifname'." 
            exit_status=1
        fi
    fi
    
    if [ "$exit_status" -ne 0 ]; then
        debug_log "DEBUG" "get_dslite: Failed to retrieve AFTR name from DHCP."
        printf "%s\n" "$(color red "$(get_message MSG_DSLITE_AUTO_DETECT_FAILED)")"
        return 1
    fi

    DHCP_AFTR_NAME="$raw_aftr_name"
    debug_log "DEBUG" "get_dslite: Automatic AFTR detection successful. DHCP_AFTR_NAME set to '$DHCP_AFTR_NAME'."
    return 0
}

map_dslite() {
    local manual_input_specifier="$1"
    local source_specifier=""
    local func_exit_status=0

    local AFTR_TRANS_EAST="2403:7f00:4000:2000::126"
    local AFTR_TRANS_WEST="2403:7f00:c000:1000::126"
    local determined_aftr_ip_transix=""
    local determined_region_name_transix="Unknown"

    DETECTED_AFTR_INFO=""
    DETECTED_PROVIDER_DISPLAY_NAME=""
    DETECTED_PROVIDER_KEY=""

    if [ "$DETECTED_PROVIDER_KEY" = "manual" ]; then
        return 0
    fi
    
    if [ -n "$manual_input_specifier" ]; then
        source_specifier="$manual_input_specifier"
        debug_log "DEBUG" "map_dslite: Manual mode. Using input specifier: '$source_specifier'"
    else
        if [ -n "$DHCP_AFTR_NAME" ]; then
            source_specifier="$DHCP_AFTR_NAME"
            debug_log "DEBUG" "map_dslite: Automatic mode. Using DHCP_AFTR_NAME: '$source_specifier'"
        else
            debug_log "DEBUG" "map_dslite: Automatic mode but DHCP_AFTR_NAME is not set."
            printf "%s\n" "$(color red "$(get_message MSG_DSLITE_UNSUPPORTED)")"
            return 1
        fi
    fi

    if [ -z "$source_specifier" ]; then
        debug_log "DEBUG" "map_dslite: source_specifier is empty before mapping."
        printf "%s\n" "$(color red "$(get_message MSG_DSLITE_UNSUPPORTED)")"
        return 1 
    fi

    debug_log "DEBUG" "map_dslite: Retrieved raw AFTR name (source_specifier): '$source_specifier'."

    if ipv6_address_dslite "$source_specifier"; then
        DETECTED_AFTR_INFO="$source_specifier"
        if [ "$source_specifier" = "$AFTR_TRANS_EAST" ]; then
            DETECTED_PROVIDER_KEY="transix"
            DETECTED_PROVIDER_DISPLAY_NAME="Transix (East Japan)"
        elif [ "$source_specifier" = "$AFTR_TRANS_WEST" ]; then
            DETECTED_PROVIDER_KEY="transix"
            DETECTED_PROVIDER_DISPLAY_NAME="Transix (West Japan)"
        else
            DETECTED_PROVIDER_KEY="manual_ip" 
            DETECTED_PROVIDER_DISPLAY_NAME="Manual IP ($source_specifier)"
            debug_log "DEBUG" "map_dslite: Manual IP detected. Key set to 'manual_ip'."
        fi
    else
        if [ "$source_specifier" = "gw.transix.jp" ]; then
            debug_log "DEBUG" "map_dslite: [Transix] Starting AFTR determination using hardcoded IPs." 
            if [ -n "$AFTR_TRANS_EAST" ] && check_ipv6_reachability_dslite "$AFTR_TRANS_EAST"; then
                determined_aftr_ip_transix="$AFTR_TRANS_EAST"
                determined_region_name_transix="Transix (East)"
                debug_log "DEBUG" "map_dslite: [Transix] Using hardcoded East AFTR: $determined_aftr_ip_transix" 
            elif [ -n "$AFTR_TRANS_WEST" ] && check_ipv6_reachability_dslite "$AFTR_TRANS_WEST"; then
                determined_aftr_ip_transix="$AFTR_TRANS_WEST"
                determined_region_name_transix="Transix (West)"
                debug_log "DEBUG" "map_dslite: [Transix] Using hardcoded West AFTR: $determined_aftr_ip_transix" 
            else
                debug_log "DEBUG" "map_dslite: [Transix] Failed to determine AFTR using hardcoded IPs. Both are unreachable or undefined." 
            fi

            if [ -n "$determined_aftr_ip_transix" ] && [ "$determined_region_name_transix" != "Unknown" ]; then
                DETECTED_AFTR_INFO="$determined_aftr_ip_transix"
                DETECTED_PROVIDER_DISPLAY_NAME="$determined_region_name_transix"
                DETECTED_PROVIDER_KEY="transix"
                debug_log "DEBUG" "map_dslite: Detected provider as Transix. AFTR: $DETECTED_AFTR_INFO, Display: $DETECTED_PROVIDER_DISPLAY_NAME" 
            else
                debug_log "DEBUG" "map_dslite: [Transix] Failed to determine Transix region or AFTR. No valid AFTR IP." 
                DETECTED_PROVIDER_DISPLAY_NAME="Transix (Resolution Failed)"
                DETECTED_PROVIDER_KEY="transix"
            fi
        elif [ "$source_specifier" = "dgw.xpass.jp" ]; then
            DETECTED_AFTR_INFO="$source_specifier"
            DETECTED_PROVIDER_DISPLAY_NAME="Cross Path"
            DETECTED_PROVIDER_KEY="cross_path"
            debug_log "DEBUG" "map_dslite: Detected provider as Cross Path based on AFTR name '$source_specifier'." 
        elif [ "$source_specifier" = "gw.example.v6option.ne.jp" ]; then
            DETECTED_AFTR_INFO="$source_specifier"
            DETECTED_PROVIDER_DISPLAY_NAME="v6 Option"
            DETECTED_PROVIDER_KEY="v6option"
            debug_log "DEBUG" "map_dslite: Detected provider as v6 Option based on AFTR name '$source_specifier'." 
        else
            DETECTED_AFTR_INFO="$source_specifier"
            DETECTED_PROVIDER_DISPLAY_NAME="Unknown (AFTR: $source_specifier)"
            DETECTED_PROVIDER_KEY="unknown"
            debug_log "DEBUG" "map_dslite: Unknown provider for AFTR name '$source_specifier'. Using raw AFTR info." 
        fi
    fi

    if [ -z "$DETECTED_PROVIDER_KEY" ] || [ "$DETECTED_PROVIDER_KEY" = "unknown" ]; then
        debug_log "DEBUG" "map_dslite: Failed to determine a known provider or AFTR for '$source_specifier'." 参考
        func_exit_status=1
    fi
    
    if [ "$func_exit_status" -eq 0 ]; then
        if [ -z "$DETECTED_AFTR_INFO" ]; then
            debug_log "DEBUG" "map_dslite: Final AFTR_INFO is empty for Key '$DETECTED_PROVIDER_KEY'." 
            func_exit_status=1
        fi
    fi

    if [ "$func_exit_status" -ne 0 ]; then
        printf "%s\n" "$(color red "$(get_message MSG_DSLITE_UNSUPPORTED)")"
        return 1
    fi

    debug_log "DEBUG" "map_dslite: Mapping complete. Key: '$DETECTED_PROVIDER_KEY', Display: '$DETECTED_PROVIDER_DISPLAY_NAME', AFTR Info: '$DETECTED_AFTR_INFO'." 参考
    return 0
}

determine_dslite() {
    local aftr_info_from_db="$DETECTED_AFTR_INFO"
    local provider_display_name_from_db="$DETECTED_PROVIDER_DISPLAY_NAME"
    local provider_key="$DETECTED_PROVIDER_KEY"

    DSLITE_AFTR_IP=""
    DSLITE_DISPLAY_NAME="$provider_display_name_from_db"

    debug_log "DEBUG" "determine_dslite: Processing for Provider Key '$provider_key', AFTR Info: '$aftr_info_from_db', Display Name: '$provider_display_name_from_db'."

    if [ "$DETECTED_PROVIDER_KEY" = "manual" ]; then
        DSLITE_AFTR_IP="$aftr_info_from_db"
        return 0
    fi
    
    if [ -z "$provider_key" ]; then
        debug_log "DEBUG" "determine_dslite: Provider key (from global) is empty."
        return 1
    fi

    if [ -z "$aftr_info_from_db" ]; then
        debug_log "DEBUG" "determine_dslite: AFTR information (from global) is empty for Provider Key '$provider_key'."
        return 1
    fi

    if [ "$provider_key" = "transix" ]; then
        DSLITE_AFTR_IP="$aftr_info_from_db"
        debug_log "DEBUG" "determine_dslite: [Transix] Using AFTR IP determined by get_dslite: $DSLITE_AFTR_IP, Display: $DSLITE_DISPLAY_NAME"
    else
        if ipv6_address_dslite "$aftr_info_from_db"; then
            DSLITE_AFTR_IP="$aftr_info_from_db"
        else
            DSLITE_AFTR_IP=$(get_aaaa_record_dslite "$aftr_info_from_db")
            if [ -z "$DSLITE_AFTR_IP" ]; then
                debug_log "DEBUG" "determine_dslite: Failed to resolve hostname '$aftr_info_from_db' for Provider Key '$provider_key'."
                return 1
            fi
        fi
        
        if ! check_ipv6_reachability_dslite "$DSLITE_AFTR_IP"; then
            debug_log "DEBUG" "determine_dslite: AFTR IP '$DSLITE_AFTR_IP' for '$provider_key' is not reachable."
            DSLITE_AFTR_IP=""
            return 1
        fi
    fi

    if [ -z "$DSLITE_AFTR_IP" ]; then
        debug_log "DEBUG" "determine_dslite: Final DSLITE_AFTR_IP could not be determined for Provider Key '$provider_key'."
        return 1
    fi

    debug_log "DEBUG" "determine_dslite: AFTR determined: $DSLITE_AFTR_IP for $DSLITE_DISPLAY_NAME."
    return 0
}

replace_dslite_sh() {
    debug_log "DEBUG" "replace_dslite_sh: Processing protocol script '$DSLITE_PROTO_SCRIPT_PATH'."

    if [ ! -f "$DSLITE_PROTO_SCRIPT_PATH" ]; then
        debug_log "DEBUG" "replace_dslite_sh: Protocol script '$DSLITE_PROTO_SCRIPT_PATH' not found. 'ds-lite' package might not be installed correctly."
        return 1
    fi
    if [ ! -f "$DSLITE_PROTO_SCRIPT_BACKUP_PATH" ]; then
        cp "$DSLITE_PROTO_SCRIPT_PATH" "$DSLITE_PROTO_SCRIPT_BACKUP_PATH" 2>/dev/null
        if [ $? -ne 0 ]; then
            debug_log "DEBUG" "replace_dslite_sh: Failed to create backup '$DSLITE_PROTO_SCRIPT_BACKUP_PATH'."
        fi
    fi

    if grep -q "mtu:-1280" "$DSLITE_PROTO_SCRIPT_PATH"; then
        debug_log "DEBUG" "replace_dslite_sh: Modifying MTU from 1280 to 1460 in '$DSLITE_PROTO_SCRIPT_PATH'."
        sed "s/mtu:-1280/mtu:-1460/g" "$DSLITE_PROTO_SCRIPT_PATH" > "${DSLITE_PROTO_SCRIPT_PATH}.tmp"
        if [ $? -eq 0 ] && [ -s "${DSLITE_PROTO_SCRIPT_PATH}.tmp" ]; then
            mv "${DSLITE_PROTO_SCRIPT_PATH}.tmp" "$DSLITE_PROTO_SCRIPT_PATH"
            debug_log "DEBUG" "replace_dslite_sh: MTU in '$DSLITE_PROTO_SCRIPT_PATH' modified."
        else
            rm -f "${DSLITE_PROTO_SCRIPT_PATH}.tmp"
            debug_log "DEBUG" "replace_dslite_sh: Failed to modify MTU. Restoring from backup if available."
            if [ -f "$DSLITE_PROTO_SCRIPT_BACKUP_PATH" ]; then
                cp "$DSLITE_PROTO_SCRIPT_BACKUP_PATH" "$DSLITE_PROTO_SCRIPT_PATH" 2>/dev/null
            fi
            return 1
        fi
    else
        debug_log "DEBUG" "replace_dslite_sh: MTU in '$DSLITE_PROTO_SCRIPT_PATH' does not appear to be default 1280 or was already changed."
    fi

    return 0
}

config_dslite() {
    local DSLITE="dslite" # Ensure this matches the actual interface name created by the 'dslite' proto

    local ZONE_NO
    local wan_zone_name_to_find="wan"
    local WAN_IF="${WAN_IF:-wan}" # Used in fallback logic
    local WAN6_IF="${WAN6_IF:-wan6}"
    local LAN_IF="${LAN_IF:-lan}"

    debug_log "DEBUG" "config_dslite: Starting function. WAN_IF is '$WAN_IF', WAN6_IF is '$WAN6_IF', LAN_IF is '$LAN_IF'."

    # Attempt to find the firewall zone index for 'wan' by its name
    ZONE_NO=$(uci show firewall | grep -E "firewall\.@zone\[([0-9]+)\].name='$wan_zone_name_to_find'" | sed -n 's/firewall\.@zone\[\([0-9]*\)\].name=.*/\1/p' | head -n1)
    debug_log "DEBUG" "config_dslite: Attempt 1: ZONE_NO from 'name=$wan_zone_name_to_find' is: '$ZONE_NO'"

    if [ -z "$ZONE_NO" ]; then
        debug_log "DEBUG" "config_dslite: Firewall zone named '$wan_zone_name_to_find' not found. Attempting fallback by network list containing '$WAN_IF'."
        # Fallback 1: Try to find a zone that has '$WAN_IF' in its network list
        ZONE_NO=$(uci show firewall | grep "network.*'$WAN_IF'" | sed -n "s/^firewall\.@zone\[\([0-9]*\)\].*/\1/p" | head -n1)
        debug_log "DEBUG" "config_dslite: Attempt 2 (Fallback 1): ZONE_NO from network list '$WAN_IF' is: '$ZONE_NO'"
        
        if [ -z "$ZONE_NO" ]; then
            debug_log "DEBUG" "config_dslite: No zone found associated with network '$WAN_IF' either. Defaulting to zone index '1'. This might not be correct for the WAN."
            ZONE_NO="1" # Default to zone 1 as a last resort
        else
            debug_log "DEBUG" "config_dslite: Using firewall zone index '$ZONE_NO' (found via network list containing '$WAN_IF')."
        fi
    else
        debug_log "DEBUG" "config_dslite: Using firewall zone index '$ZONE_NO' (found via name='$wan_zone_name_to_find')."
    fi
    debug_log "DEBUG" "config_dslite: Final FIREWALL ZONE_NO to be used for dslite interface: '$ZONE_NO'"


    if [ -z "$DSLITE_AFTR_IP" ]; then
        debug_log "DEBUG" "config_dslite: DSLITE_AFTR_IP is not set. Cannot apply UCI settings."
        return 1
    fi

    debug_log "DEBUG" "config_dslite: Backing up /etc/config/network, /etc/config/dhcp, /etc/config/firewall."
    cp /etc/config/network /etc/config/network.dslite.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.dslite.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.dslite.bak 2>/dev/null

    debug_log "DEBUG" "config_dslite: Applying UCI settings for network interface '${DSLITE}' and dhcp. AFTR: '$DSLITE_AFTR_IP'."

    uci -q set network.${WAN_IF}.disabled='1'
    uci -q set network.${WAN_IF}.auto='0'

    uci -q set dhcp.${LAN_IF}.ra='relay'
    uci -q set dhcp.${LAN_IF}.dhcpv6='server'
    uci -q set dhcp.${LAN_IF}.ndp='relay'
    uci -q set dhcp.${LAN_IF}.force='1'
    
    uci -q set dhcp.${WAN6_IF}=dhcp
    uci -q set dhcp.${WAN6_IF}.interface="$WAN6_IF"
    uci -q set dhcp.${WAN6_IF}.ignore='1'
    uci -q set dhcp.${WAN6_IF}.master='1'
    uci -q set dhcp.${WAN6_IF}.ra='relay'
    uci -q set dhcp.${WAN6_IF}.dhcpv6='relay'
    uci -q set dhcp.${WAN6_IF}.ndp='relay'

    debug_log "DEBUG" "config_dslite: Deleting and recreating network interface '${DSLITE}'."
    uci -q delete network.${DSLITE}
    uci -q set network.${DSLITE}=interface
    uci -q set network.${DSLITE}.proto='dslite'
    uci -q set network.${DSLITE}.peeraddr="$DSLITE_AFTR_IP"
    uci -q set network.${DSLITE}.mtu='1460'

    debug_log "DEBUG" "config_dslite: Applying firewall UCI settings for interface '${DSLITE}' in WAN zone index '${ZONE_NO}'."

    local current_networks
    current_networks=$(uci -q get firewall.@zone[${ZONE_NO}].network 2>/dev/null)
    local uci_add_list_failed=0 # Flag specifically for add_list failure

    # Check if old WAN_IF is in the zone and remove it.
    # Failure to remove (e.g., if not present) is not necessarily a fatal error for this script's logic.
    if echo "$current_networks" | grep -q "\b${WAN_IF}\b"; then
        debug_log "DEBUG" "config_dslite: Attempting to remove '${WAN_IF}' from firewall zone ${ZONE_NO} network list."
        uci -q del_list firewall.@zone[${ZONE_NO}].network="${WAN_IF}"
        if [ $? -ne 0 ]; then
            # Log as a warning, but do not set a fatal error flag here.
            debug_log "DEBUG" "config_dslite: Failed to remove '${WAN_IF}' from firewall zone ${ZONE_NO} (it might not have been there, or another issue)."
        else
            debug_log "DEBUG" "config_dslite: Successfully removed '${WAN_IF}' from firewall zone ${ZONE_NO} network list."
        fi
    else
        debug_log "DEBUG" "config_dslite: '${WAN_IF}' not found in current network list for zone ${ZONE_NO}. No removal needed."
    fi

    # Add DSLITE to the zone if not already present.
    # Re-fetch current_networks in case it changed due to del_list
    current_networks=$(uci -q get firewall.@zone[${ZONE_NO}].network 2>/dev/null)
    if ! echo "$current_networks" | grep -q "\b${DSLITE}\b"; then
        debug_log "DEBUG" "config_dslite: Attempting to add '${DSLITE}' to firewall zone ${ZONE_NO} network list."
        uci -q add_list firewall.@zone[${ZONE_NO}].network="${DSLITE}"
        if [ $? -ne 0 ]; then
            debug_log "DEBUG" "config_dslite: Failed to add '${DSLITE}' to firewall zone ${ZONE_NO}."
            uci_add_list_failed=1 # Set flag if add_list fails
        else
            debug_log "DEBUG" "config_dslite: Successfully added '${DSLITE}' to firewall zone ${ZONE_NO} network list."
        fi
    else
        debug_log "DEBUG" "config_dslite: '${DSLITE}' already in firewall zone ${ZONE_NO} network list."
    fi
    
    # If adding DSLITE to the firewall zone failed, this is a more critical issue.
    if [ "$uci_add_list_failed" -eq 1 ]; then
        debug_log "DEBUG" "config_dslite: Halting before commit due to failure to add '${DSLITE}' to firewall zone ${ZONE_NO}."
        return 1
    fi

    # Proceed to set masq and mtu_fix only if adding DSLITE was successful or it was already there.
    debug_log "DEBUG" "config_dslite: Setting masq='1' and mtu_fix='1' for firewall zone '${ZONE_NO}'."
    uci -q set firewall.@zone[${ZONE_NO}].masq='1'
    if [ $? -ne 0 ]; then
        debug_log "DEBUG" "config_dslite: Failed to set masq for firewall zone ${ZONE_NO}."
        # Not necessarily fatal, but log it.
    fi
    uci -q set firewall.@zone[${ZONE_NO}].mtu_fix='1'
    if [ $? -ne 0 ]; then
        debug_log "DEBUG" "config_dslite: Failed to set mtu_fix for firewall zone ${ZONE_NO}."
        # Not necessarily fatal, but log it.
    fi
    
    local commit_failed=0
    local commit_errors=""
    debug_log "DEBUG" "config_dslite: Committing UCI changes for dhcp, network, and firewall."
    
    uci -q commit dhcp
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}dhcp "
        debug_log "DEBUG" "config_dslite: Failed to commit dhcp."
    fi

    uci -q commit network
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}network "
        debug_log "DEBUG" "config_dslite: Failed to commit network."
    fi
    
    uci -q commit firewall
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}firewall "
        debug_log "DEBUG" "config_dslite: Failed to commit firewall."
    fi

    if [ "$commit_failed" -eq 1 ]; then
        debug_log "DEBUG" "config_dslite: Failed to commit one or more UCI sections: ${commit_errors}."
        return 1
    fi

    debug_log "DEBUG" "config_dslite: UCI settings applied and committed successfully."
    return 0
}

display_dslite() {
    debug_log "DEBUG" "display_dslite: Displaying DS-Lite configuration summary and status."

    if [ -z "$DSLITE_AFTR_IP" ] || [ -z "$DSLITE_DISPLAY_NAME" ]; then
        printf "\n%s\n" "$(color red "$(get_message MSG_DSLITE_AUTO_DETECT_FAILED)")"
        return 1
    fi

    printf "\n%s\n" "$(color blue "DS-Lite Configuration Summary:")"
    printf "  %s %s\n" "Provider:" "$DSLITE_DISPLAY_NAME"
    printf "  %s %s\n" "AFTR (Border Relay):" "$DSLITE_AFTR_IP"
    printf "  %s %s\n" "Interface MTU (expected):" "1460"
    printf "\n"
    printf "%s\n" "$(color green "$(get_message "MSG_DSLITE_SUCCESS")")"
    printf "%s\n" "$(color yellow "$(get_message "MSG_DSLITE_APPLY_SUCCESS")")"
    read -r -n 1 -s
    printf "\n"
     
    debug_log "DEBUG" "Rebooting system after restore."
    reboot    
    return 0
}

restore_dslite() {
    debug_log "DEBUG" "restore_dslite_settings: Restoring DS-Lite settings from backups."

    local files_to_restore="network dhcp firewall"
    local config_dir="/etc/config"
    local backup_suffix=".dslite.bak"
    local file_base
    local original_file
    local backup_file
    local all_restored_successfully=1

    for file_base in $files_to_restore; do
        original_file="${config_dir}/${file_base}"
        backup_file="${original_file}${backup_suffix}"
        if [ -f "$backup_file" ]; then
            if cp "$backup_file" "$original_file"; then
                rm "$backup_file"
                debug_log "DEBUG" "restore_dslite_settings: Restored $original_file from $backup_file."
            else
                debug_log "DEBUG" "restore_dslite_settings: Failed to restore $original_file from $backup_file."
                all_restored_successfully=0
            fi
        else
            debug_log "DEBUG" "restore_dslite_settings: Backup $backup_file not found for $original_file. No action taken for this file."
        fi
    done

    if [ -f "$DSLITE_PROTO_SCRIPT_BACKUP_PATH" ]; then
        if cp "$DSLITE_PROTO_SCRIPT_BACKUP_PATH" "$DSLITE_PROTO_SCRIPT_PATH"; then
            rm "$DSLITE_PROTO_SCRIPT_BACKUP_PATH"
            debug_log "DEBUG" "restore_dslite_settings: Restored $DSLITE_PROTO_SCRIPT_PATH from $DSLITE_PROTO_SCRIPT_BACKUP_PATH."
        else
            debug_log "DEBUG" "restore_dslite_settings: Failed to restore $DSLITE_PROTO_SCRIPT_PATH from $DSLITE_PROTO_SCRIPT_BACKUP_PATH."
            all_restored_successfully=0
        fi
    else
        debug_log "DEBUG" "restore_dslite_settings: Backup $DSLITE_PROTO_SCRIPT_BACKUP_PATH not found for $DSLITE_PROTO_SCRIPT_PATH. No action taken for this file."
    fi

    if [ "$all_restored_successfully" -eq 1 ]; then
        printf "\n"
        printf "%s\n" "$(color green "$(get_message MSG_DSLITE_RESTORE_SUCCESS)")"
    else
        debug_log "DEBUG" "restore_dslite_settings: One or more files may not have been restored successfully. Please check logs."
    fi

    debug_log "DEBUG" "restore_dslite_settings: DS-Lite settings restoration process completed."
    return 0
}

internet_dslite_main() {

    if ! get_dslite "$@"; then
        return 1
    fi

    if ! map_dslite "$@"; then
        return 1
    fi
    
    if ! determine_dslite; then
        debug_log "DEBUG" "internet_dslite_main: determine_dslite function failed. Exiting script."
        return 1
    fi
    
    if ! install_package ds-lite hidden; then
        debug_log "DEBUG" "internet_dslite_main: Failed to install 'dslite' package or it was already installed. Continuing."
        return 1
    fi

    if ! replace_dslite_sh; then
        return 1
    fi
    
    if ! config_dslite; then
        debug_log "DEBUG" "internet_dslite_main: config_dslite function failed. UCI settings might be inconsistent."
        return 1
    fi

    if ! display_dslite; then
        debug_log "DEBUG" "internet_dslite_main: display_dslite function failed. Aborting reboot."
        return 1
    fi
    
    debug_log "DEBUG" "internet_dslite_main: Configuration complete. Rebooting system."
    reboot

    return 0
}
