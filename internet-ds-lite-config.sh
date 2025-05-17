#!/bin/sh

SCRIPT_VERSION="2025.05.17-00-00"

. /lib/functions/network.sh

DSLITE_AFTR_IP=""
DSLITE_DISPLAY_NAME=""

DSLITE_PROTO_SCRIPT_PATH="/lib/netifd/proto/dslite.sh"
DSLITE_PROTO_SCRIPT_BACKUP_PATH="${DSLITE_PROTO_SCRIPT_PATH}.bak"

DETECTED_AFTR_INFO=""
DETECTED_PROVIDER_DISPLAY_NAME=""
DETECTED_PROVIDER_KEY=""

get_dslite() {
    local logical_wan6_ifname=""
    local physical_wan_ifname=""
    local lease_file="/tmp/hosts/odhcp6c"
    local aftr_name_option_code="24"
    local raw_aftr_name=""
    local AFTR_TRANS_EAST="2403:7f00:4000:2000::126"
    local AFTR_TRANS_WEST="2403:7f00:c000:1000::126"
    local determined_aftr_ip_transix=""
    local determined_region_name_transix="Unknown"

    debug_log "DEBUG" "get_dslite: Starting AFTR detection."

    DETECTED_AFTR_INFO=""
    DETECTED_PROVIDER_DISPLAY_NAME=""
    DETECTED_PROVIDER_KEY=""

    network_find_wan6 logical_wan6_ifname
    if [ -z "$logical_wan6_ifname" ]; then
        debug_log "DEBUG" "get_dslite: Could not find logical IPv6 WAN interface (wan6)."
        return 1
    fi
    debug_log "DEBUG" "get_dslite: Found logical IPv6 WAN interface: $logical_wan6_ifname"

    network_get_physdev physical_wan_ifname "$logical_wan6_ifname"
    if [ -z "$physical_wan_ifname" ]; then
        debug_log "DEBUG" "get_dslite: Could not find physical device for $logical_wan6_ifname. Cannot proceed with lease file parsing."
        return 1
    fi
    debug_log "DEBUG" "get_dslite: Found physical device for $logical_wan6_ifname: $physical_wan_ifname"


    if [ ! -f "$lease_file" ]; then
        debug_log "DEBUG" "get_dslite: Lease file '$lease_file' not found."
        return 1
    fi

    raw_aftr_name=$(grep "^${physical_wan_ifname} .*aftr-name" "$lease_file" | awk '{print $NF}' 2>/dev/null)

    if [ -z "$raw_aftr_name" ]; then
        local hex_encoded_aftr_name
        hex_encoded_aftr_name=$(grep "^${physical_wan_ifname} ${aftr_name_option_code} " "$lease_file" | awk '{print $3}' 2>/dev/null)

        if [ -n "$hex_encoded_aftr_name" ]; then
            debug_log "DEBUG" "get_dslite: Found HEX encoded AFTR name '$hex_encoded_aftr_name' for $physical_wan_ifname. Decoding is required."
            debug_log "DEBUG" "get_dslite: HEX encoded AFTR name found, but decoding function is not implemented."
            raw_aftr_name=""
        fi
    fi

    if [ -z "$raw_aftr_name" ]; then
        debug_log "DEBUG" "get_dslite: Could not retrieve AFTR name from lease file for interface '$physical_wan_ifname'."
        return 1
    fi

    debug_log "DEBUG" "get_dslite: Retrieved raw AFTR name: '$raw_aftr_name' for interface '$physical_wan_ifname'."

    if [ "$raw_aftr_name" = "gw.transix.jp" ]; then
        debug_log "DEBUG" "get_dslite: [Transix] Starting AFTR determination using hardcoded IPs."
        if [ -n "$AFTR_TRANS_EAST" ] && check_ipv6_reachability_dslite "$AFTR_TRANS_EAST"; then
            determined_aftr_ip_transix="$AFTR_TRANS_EAST"
            determined_region_name_transix="Transix (East)"
            debug_log "DEBUG" "get_dslite: [Transix] Using hardcoded East AFTR: $determined_aftr_ip_transix"
        elif [ -n "$AFTR_TRANS_WEST" ] && check_ipv6_reachability_dslite "$AFTR_TRANS_WEST"; then
            determined_aftr_ip_transix="$AFTR_TRANS_WEST"
            determined_region_name_transix="Transix (West)"
            debug_log "DEBUG" "get_dslite: [Transix] Using hardcoded West AFTR: $determined_aftr_ip_transix"
        else
            debug_log "DEBUG" "get_dslite: [Transix] Failed to determine AFTR using hardcoded IPs. Both are unreachable or undefined."
        fi

        if [ -n "$determined_aftr_ip_transix" ] && [ "$determined_region_name_transix" != "Unknown" ]; then
            DETECTED_AFTR_INFO="$determined_aftr_ip_transix"
            DETECTED_PROVIDER_DISPLAY_NAME="$determined_region_name_transix"
            DETECTED_PROVIDER_KEY="transix"
            debug_log "DEBUG" "get_dslite: Detected provider as Transix. AFTR: $DETECTED_AFTR_INFO, Display: $DETECTED_PROVIDER_DISPLAY_NAME"
        else
            debug_log "DEBUG" "get_dslite: [Transix] Failed to determine Transix region or AFTR. No valid AFTR IP."
            DETECTED_AFTR_INFO=""
            DETECTED_PROVIDER_DISPLAY_NAME="Transix (Resolution Failed)"
            DETECTED_PROVIDER_KEY="transix"
            return 1
        fi
    elif [ "$raw_aftr_name" = "dgw.xpass.jp" ]; then
        DETECTED_AFTR_INFO="$raw_aftr_name"
        DETECTED_PROVIDER_DISPLAY_NAME="Cross Path"
        DETECTED_PROVIDER_KEY="cross_path"
        debug_log "DEBUG" "get_dslite: Detected provider as Cross Path based on AFTR name '$raw_aftr_name'."
    elif [ "$raw_aftr_name" = "gw.example.v6option.ne.jp" ]; then
        DETECTED_AFTR_INFO="$raw_aftr_name"
        DETECTED_PROVIDER_DISPLAY_NAME="v6 Option"
        DETECTED_PROVIDER_KEY="v6option"
        debug_log "DEBUG" "get_dslite: Detected provider as v6 Option based on AFTR name '$raw_aftr_name'."
    else
        DETECTED_AFTR_INFO="$raw_aftr_name"
        DETECTED_PROVIDER_DISPLAY_NAME="Unknown (AFTR: $raw_aftr_name)"
        DETECTED_PROVIDER_KEY="unknown"
        debug_log "DEBUG" "get_dslite: Unknown provider for AFTR name '$raw_aftr_name'. Using raw AFTR info."
    fi

    if [ -z "$DETECTED_PROVIDER_KEY" ] || [ "$DETECTED_PROVIDER_KEY" = "unknown" ]; then
        debug_log "DEBUG" "get_dslite: Failed to determine a known provider or AFTR for '$raw_aftr_name'."
        return 1
    fi
    
    if [ -z "$DETECTED_AFTR_INFO" ]; then
        debug_log "DEBUG" "get_dslite: Final AFTR_INFO is empty for Key '$DETECTED_PROVIDER_KEY'."
        return 1
    fi

    debug_log "DEBUG" "get_dslite: Detection complete. Key: '$DETECTED_PROVIDER_KEY', Display: '$DETECTED_PROVIDER_DISPLAY_NAME', AFTR Info: '$DETECTED_AFTR_INFO'."
    return 0
}

determine_dslite() {
    local aftr_info_from_db="$DETECTED_AFTR_INFO"
    local provider_display_name_from_db="$DETECTED_PROVIDER_DISPLAY_NAME"
    local provider_key="$DETECTED_PROVIDER_KEY"

    DSLITE_AFTR_IP=""
    DSLITE_DISPLAY_NAME="$provider_display_name_from_db"

    debug_log "DEBUG" "determine_dslite: Processing for Provider Key '$provider_key', AFTR Info: '$aftr_info_from_db', Display Name: '$provider_display_name_from_db'."

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
        if is_ipv6_address_dslite "$aftr_info_from_db"; then
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
    local DSLITE="ds_lite"
    local ZONE_NO='1'

    if [ -z "$DSLITE_AFTR_IP" ]; then
        debug_log "DEBUG" "config_dslite: DSLITE_AFTR_IP is not set. Cannot apply UCI settings."
        return 1
    fi

    debug_log "DEBUG" "config_dslite: Backing up /etc/config/network, /etc/config/dhcp, /etc/config/firewall."
    cp /etc/config/network /etc/config/network.dslite.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.dslite.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.dslite.bak 2>/dev/null

    debug_log "DEBUG" "config_dslite: Applying UCI settings for network interface '${DSLITE}' and dhcp. AFTR: '$DSLITE_AFTR_IP'."

    uci -q set network.wan.auto='0'
    uci -q set dhcp.lan.ra='relay'
    uci -q set dhcp.lan.dhcpv6='server'
    uci -q set dhcp.lan.ndp='relay'
    uci -q set dhcp.lan.force='1'

    uci -q set dhcp.wan6=dhcp
    uci -q set dhcp.wan6.interface='wan6'
    uci -q set dhcp.wan6.ignore='1'
    uci -q set dhcp.wan6.master='1'
    uci -q set dhcp.wan6.ra='relay'
    uci -q set dhcp.wan6.dhcpv6='relay'
    uci -q set dhcp.wan6.ndp='relay'

    debug_log "DEBUG" "config_dslite: Deleting and recreating network interface '${DSLITE}'."
    uci -q delete network.${DSLITE}
    uci -q set network.${DSLITE}=interface
    uci -q set network.${DSLITE}.proto='dslite'
    uci -q set network.${DSLITE}.peeraddr="$DSLITE_AFTR_IP"
    uci -q set network.${DSLITE}.mtu='1460'

    debug_log "DEBUG" "config_dslite: Applying firewall UCI settings for interface '${DSLITE}' in zone index '${ZONE_NO}'."

    debug_log "DEBUG" "config_dslite: Attempting to remove '${DSLITE}' from firewall zone '${ZONE_NO}' network list."
    uci -q del_list firewall.@zone["${ZONE_NO}"].network="${DSLITE}"

    debug_log "DEBUG" "config_dslite: Adding '${DSLITE}' to firewall zone '${ZONE_NO}' network list."
    uci -q add_list firewall.@zone["${ZONE_NO}"].network="${DSLITE}"
    
    debug_log "DEBUG" "config_dslite: Setting masq='1' and mtu_fix='1' for firewall zone '${ZONE_NO}'."
    uci -q set firewall.@zone["${ZONE_NO}"].masq='1'
    uci -q set firewall.@zone["${ZONE_NO}"].mtu_fix='1'

    local commit_failed=0
    debug_log "DEBUG" "config_dslite: Committing UCI changes for dhcp, network, and firewall."
    uci -q commit dhcp || commit_failed=1
    uci -q commit network || commit_failed=1
    uci -q commit firewall || commit_failed=1

    if [ "$commit_failed" -eq 1 ]; then
        debug_log "ERROR" "config_dslite: Failed to commit one or more UCI sections."
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
    printf "  %-25s %s\n" "Provider:" "$DSLITE_DISPLAY_NAME"
    printf "  %-25s %s\n" "AFTR (Border Relay):" "$DSLITE_AFTR_IP"
    printf "  %-25s %s\n" "Interface MTU (expected):" "1460"
    
    printf "%s\n" "$(color green "$(get_message MSG_DSLITE_APPLY_SUCCES)")"
    read -r -n 1 -s
    
    return 0
}

restore_dslite_settings() {
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
        printf "%s\n" "$(color green "$(get_message MSG_DSLITE_RESTORE_SUCCESS)")"
    else
        debug_log "DEBUG" "restore_dslite_settings: One or more files may not have been restored successfully. Please check logs."
    fi

    debug_log "DEBUG" "restore_dslite_settings: DS-Lite settings restoration process completed."
    return 0
}

internet_dslite_main() {

    print_section_title "MENU_INTERNET_DSLITE"

    if ! get_dslite; then
        return 1
    fi
    
    if ! determine_dslite; then
        debug_log "DEBUG" "internet_dslite_main: determine_dslite function failed. Exiting script."
        return 1
    fi
    
    if ! install_package dslite hidden; then
        debug_log "DEBUG" "internet_map_main: Failed to install 'dslite' package or it was already installed. Continuing."
        return 1
    fi

    if ! replace_dslite_sh; then
        return 1
    fi
    
    if ! config_dslite; then
        debug_log "DEBUG" "internet_dslite_main: config_dslite function failed. UCI settings might be inconsistent."
        return 1
    fi

    display_dslite
    
    debug_log "DEBUG" "internet_dslite_main: Configuration complete. Rebooting system."
    reboot

    return 0
}
