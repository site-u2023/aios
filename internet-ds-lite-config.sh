#!/bin/sh

SCRIPT_VERSION="2025.05.17-00-00"

DSLITE_AFTR_IP=""
DSLITE_DISPLAY_NAME=""

DSLITE_PROTO_SCRIPT_PATH="/lib/netifd/proto/dslite.sh"
DSLITE_PROTO_SCRIPT_BACKUP_PATH="${DSLITE_PROTO_SCRIPT_PATH}.bak"

mold_dslite() {
    local aftr_info_from_db="$1"
    local provider_display_name_from_db="$2"
    local provider_key="$3"

    DSLITE_AFTR_IP=""
    DSLITE_DISPLAY_NAME="$provider_display_name_from_db"

    debug_log "DEBUG" "mold_dslite: Determining AFTR for Provider Key '$provider_key'."

    if [ -z "$provider_key" ]; then
        debug_log "DEBUG" "mold_dslite: Provider key is empty."
        return 1
    fi

    if [ "$provider_key" = "transix" ]; then
        local AFTR_TRANS_EAST="2403:7f00:4000:2000::126"
        local AFTR_TRANS_WEST="2403:7f00:c000:1000::126"
        local determined_aftr_ip_transix=""
        local determined_region_name_transix="Unknown"

        debug_log "DEBUG" "mold_dslite: [Transix] Starting AFTR determination using hardcoded IPs."

        if [ -n "$AFTR_TRANS_EAST" ] && check_ipv6_reachability_dslite "$AFTR_TRANS_EAST"; then
            determined_aftr_ip_transix="$AFTR_TRANS_EAST"
            determined_region_name_transix="Transix (East)"
            debug_log "INFO" "mold_dslite: [Transix] Using hardcoded East AFTR: $determined_aftr_ip_transix"
        elif [ -n "$AFTR_TRANS_WEST" ] && check_ipv6_reachability_dslite "$AFTR_TRANS_WEST"; then
            determined_aftr_ip_transix="$AFTR_TRANS_WEST"
            determined_region_name_transix="Transix (West)"
            debug_log "INFO" "mold_dslite: [Transix] Using hardcoded West AFTR: $determined_aftr_ip_transix"
        else
            debug_log "ERROR" "mold_dslite: [Transix] Failed to determine AFTR using hardcoded IPs. Both are unreachable or undefined."
        fi

        if [ -n "$determined_aftr_ip_transix" ] && [ "$determined_region_name_transix" != "Unknown" ]; then
            DSLITE_AFTR_IP="$determined_aftr_ip_transix"
            DSLITE_DISPLAY_NAME="$determined_region_name_transix"
        else
            debug_log "DEBUG" "mold_dslite: [Transix] Failed to determine Transix region or AFTR."
            return 1
        fi
    else
        if [ -z "$aftr_info_from_db" ]; then
            debug_log "DEBUG" "mold_dslite: AFTR information from DB is empty for Provider Key '$provider_key'."
            return 1
        fi

        if is_ipv6_address_dslite "$aftr_info_from_db"; then
            DSLITE_AFTR_IP="$aftr_info_from_db"
        else
            DSLITE_AFTR_IP=$(get_aaaa_record_dslite "$aftr_info_from_db")
            if [ -z "$DSLITE_AFTR_IP" ]; then
                debug_log "DEBUG" "mold_dslite: Failed to resolve hostname '$aftr_info_from_db' for Provider Key '$provider_key'."
                return 1
            fi
        fi
        if ! check_ipv6_reachability_dslite "$DSLITE_AFTR_IP"; then
            debug_log "DEBUG" "mold_dslite: AFTR IP '$DSLITE_AFTR_IP' for '$provider_key' is not reachable."
            DSLITE_AFTR_IP=""
            return 1
        fi
    fi

    if [ -z "$DSLITE_AFTR_IP" ]; then
        debug_log "DEBUG" "mold_dslite: Final AFTR IP address could not be determined for Provider Key '$provider_key'."
        return 1
    fi

    debug_log "DEBUG" "mold_dslite: AFTR determined: $DSLITE_AFTR_IP for $DSLITE_DISPLAY_NAME."
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
    local fw_zone_index="$1"

    if [ -z "$DSLITE_AFTR_IP" ]; then
        debug_log "ERROR" "config_dslite: DSLITE_AFTR_IP is not set. Cannot apply UCI settings."
        return 1
    fi

    debug_log "DEBUG" "config_dslite: Backing up /etc/config/network, /etc/config/dhcp, /etc/config/firewall."
    cp /etc/config/network /etc/config/network.dslite.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.dslite.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.dslite.bak 2>/dev/null

    debug_log "DEBUG" "config_dslite: Applying UCI settings. AFTR: '$DSLITE_AFTR_IP', FW Zone Index: '$fw_zone_index'"

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

    uci -q delete network.ds_lite
    uci -q set network.ds_lite=interface
    uci -q set network.ds_lite.proto='dslite'
    uci -q set network.ds_lite.peeraddr="$DSLITE_AFTR_IP"
    uci -q set network.ds_lite.mtu='1460'

    local current_networks
    current_networks=$(uci -q get firewall.@zone["$fw_zone_index"].network 2>/dev/null)
    local found_in_fw=0
    local net_fw=""
    for net_fw in $current_networks; do
        if [ "$net_fw" = "ds_lite" ]; then
            found_in_fw=1
            break
        fi
    done
    if [ "$found_in_fw" -eq 0 ]; then
        uci -q add_list firewall.@zone["$fw_zone_index"].network='ds_lite'
    fi
    uci -q set firewall.@zone["$fw_zone_index"].masq='1'
    uci -q set firewall.@zone["$fw_zone_index"].mtu_fix='1'


    local commit_failed=0
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
    local msg_prefix=""

    debug_log "DEBUG" "Restoring DS-Lite settings from backups."

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
                debug_log "DEBUG" "Restored $original_file from $backup_file."
            else
                debug_log "ERROR" "Failed to restore $original_file from $backup_file."
                all_restored_successfully=0
            fi
        else
            debug_log "DEBUG" "Backup $backup_file not found for $original_file. No action taken for this file."
        fi
    done

    if [ -f "$DSLITE_PROTO_SCRIPT_BACKUP_PATH" ]; then
        if cp "$DSLITE_PROTO_SCRIPT_BACKUP_PATH" "$DSLITE_PROTO_SCRIPT_PATH"; then
            rm "$DSLITE_PROTO_SCRIPT_BACKUP_PATH"
            debug_log "DEBUG" "Restored $DSLITE_PROTO_SCRIPT_PATH from $DSLITE_PROTO_SCRIPT_BACKUP_PATH."
        else
            debug_log "ERROR" "Failed to restore $DSLITE_PROTO_SCRIPT_PATH from $DSLITE_PROTO_SCRIPT_BACKUP_PATH."
            all_restored_successfully=0
        fi
    else
        debug_log "DEBUG" "Backup $DSLITE_PROTO_SCRIPT_BACKUP_PATH not found for $DSLITE_PROTO_SCRIPT_PATH. No action taken for this file."
    fi

    if [ "$all_restored_successfully" -eq 1 ]; then
        printf "%s\n" "$(color green "$(get_message MSG_DSLITE_RESTORE_SUCCESS)")"
    else
        debug_log "ERROR" "One or more files may not have been restored successfully. Please check logs."
    fi

    debug_log "DEBUG" "DS-Lite settings restoration process completed."
    return 0
}

internet_dslite_main() {

    print_section_title "MENU_INTERNET_DSLITE"

    # DS-LITE パラメータ計算
    if ! mold_dslite; then
        debug_log "DEBUG" "internet_map_main: mold_mape function failed. Exiting script."
        return 1
    fi
    
    if ! replace_dslite_sh; then
        return 1
    fi
    
    # `dslite` パッケージのインストール 
    if ! install_package dslite hidden; then
        debug_log "DEBUG" "internet_map_main: Failed to install 'dslite' package or it was already installed. Continuing."
        return 1
    fi

    # UCI設定の適用
    if ! config_dslite; then
        debug_log "DEBUG" "internet_map_main: config_dslite function failed. UCI settings might be inconsistent."
        return 1
    fi

    display_dslite
    
    # 再起動
    #debug_log "DEBUG" "internet_map_main: Configuration complete. Rebooting system."
    reboot

    return 0 # Explicitly exit with success status

}

# internet_dslite_main

