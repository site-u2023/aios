#!/bin/sh

SCRIPT_VERSION="2025.05.17-06:48" # AFTR dynamic resolution, Transix region detection, error handling corrected based on user feedback

# --- Assume aios environment variables and functions are loaded ---
# BASE_DIR, CACHE_DIR, LOG_DIR are assumed to be set by aios main script.
# Functions like debug_log, get_message, color, confirm, is_east_japan, install_package
# are assumed to be available in the environment. No checks performed here.

# --- Constants ---
# AFTR Addresses (still needed for Transix regional logic)
AFTR_TRANS_EAST="2404:8e00::feed:100"
AFTR_TRANS_WEST="2404:8e01::feed:100"
# AFTR_XPASS and AFTR_V6CONNECT are now managed in get_dslite_provider_data_by_as

# Backup file names
NETWORK_BACKUP="/etc/config/network.dslite.old"
PROTO_BACKUP="/lib/netifd/proto/dslite.sh.dslite.old"

# Firewall zone index (Assuming WAN is zone 1, adjust if necessary)
FW_ZONE_INDEX=1

# --- Helper function to perform a basic check for IPv6 address format ---
is_ipv6_address_dslite() {
    if echo "$1" | grep -q ":" && echo "$1" | grep -Eq '^[0-9a-fA-F:.]+$'; then
        if ! echo "$1" | grep -Eq '\.[a-zA-Z]'; then # Ensure it's not a domain-like string with dots
             return 0
        fi
    fi
    return 1
}

# --- Helper function to check if knot-nslookup (or equivalent supporting -type=AAAA) is available ---
is_knot_nslookup_ok_dslite() {
    if command -v nslookup >/dev/null 2>&1; then
        # Test with a reliable AAAA record to ensure -type=AAAA works as expected
        if nslookup -type=AAAA google.com >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# --- Helper function to get the first AAAA record for a domain ---
# Arguments: $1: Domain name
# Output: IPv6 address on success, empty string on failure.
get_aaaa_record_dslite() {
    local domain_name="$1"
    local nslookup_output=""
    local resolved_ip=""

    if ! is_knot_nslookup_ok_dslite; then
        debug_log "DEBUG" "get_aaaa_record_dslite: nslookup with -type=AAAA support not found. Attempting to install knot-utils..."
        if command -v install_package >/dev/null 2>&1; then # install_package は aios 共通関数と想定
            install_package knot-utils hidden
            if ! is_knot_nslookup_ok_dslite; then
                debug_log "ERROR" "get_aaaa_record_dslite: Failed to install or enable working nslookup for AAAA."
                echo ""
                return 1
            fi
        else
            debug_log "ERROR" "get_aaaa_record_dslite: 'install_package' function not available. Cannot install knot-utils."
            echo ""
            return 1
        fi
    fi

    nslookup_output=$(nslookup -type=AAAA "$domain_name" 2>/dev/null)
    if [ -n "$nslookup_output" ]; then
        resolved_ip=$(echo "$nslookup_output" | awk '/^Address: .*:/ {print $2; exit}')
        if [ -z "$resolved_ip" ]; then
             resolved_ip=$(echo "$nslookup_output" | awk '/AAAA/ {getline; print $3; exit}')
        fi
    fi

    if [ -z "$resolved_ip" ]; then
        debug_log "DEBUG" "get_aaaa_record_dslite: Failed to resolve AAAA record for domain '$domain_name'."
        echo ""
        return 1
    else
        debug_log "DEBUG" "get_aaaa_record_dslite: Successfully resolved '$domain_name' to '$resolved_ip'."
        echo "$resolved_ip"
        return 0
    fi
}

# --- Helper function to check IPv6 reachability ---
# Arguments: $1: IPv6 address
# Returns: 0 if reachable, 1 otherwise.
check_ipv6_reachability_dslite() {
    local ipv6_address="$1"
    local ping_command=""

    if ! is_ipv6_address_dslite "$ipv6_address"; then
        debug_log "DEBUG" "check_ipv6_reachability_dslite: Invalid IPv6 address format '$ipv6_address'."
        return 1
    fi

    if command -v ping6 >/dev/null 2>&1; then
        ping_command="ping6"
    elif command -v ping >/dev/null 2>&1; then
        if ping -6 -c 1 -W 1 "2001:4860:4860::8888" >/dev/null 2>&1; then # Test with a known public IPv6
            ping_command="ping -6"
        fi
    fi

    if [ -z "$ping_command" ]; then
        debug_log "ERROR" "check_ipv6_reachability_dslite: Suitable ping command for IPv6 not found."
        return 1
    fi

    debug_log "DEBUG" "check_ipv6_reachability_dslite: Pinging $ipv6_address using $ping_command"
    if $ping_command -c 1 -W 2 "$ipv6_address" >/dev/null 2>&1; then # 1 packet, 2 second timeout
        debug_log "DEBUG" "check_ipv6_reachability_dslite: $ipv6_address is reachable."
        return 0
    else
        debug_log "DEBUG" "check_ipv6_reachability_dslite: $ipv6_address is NOT reachable."
        return 1
    fi
}

# --- Helper function to determine network area for Transix ---
# Output: "RegionName|DeterminedAftrIp" (e.g., "East Japan|2404:8e00::feed:100")
#         or "Unknown|" if region/AFTR cannot be determined.
get_transix_network_area_dslite() {
    local east_ip="$AFTR_TRANS_EAST"
    local west_ip="$AFTR_TRANS_WEST"
    local east_reachable=1
    local west_reachable=1
    local determined_aftr_ip=""
    local determined_region_name="Unknown"

    debug_log "DEBUG" "get_transix_network_area_dslite: Checking reachability for East ($east_ip) and West ($west_ip)."

    if check_ipv6_reachability_dslite "$east_ip"; then
        east_reachable=0
    fi
    if check_ipv6_reachability_dslite "$west_ip"; then
        west_reachable=0
    fi

    if [ "$east_reachable" -eq 0 ] && [ "$west_reachable" -ne 0 ]; then
        determined_region_name="East Japan"
        determined_aftr_ip="$east_ip"
    elif [ "$east_reachable" -ne 0 ] && [ "$west_reachable" -eq 0 ]; then
        determined_region_name="West Japan"
        determined_aftr_ip="$west_ip"
    elif [ "$east_reachable" -eq 0 ] && [ "$west_reachable" -eq 0 ]; then
        debug_log "WARN" "get_transix_network_area_dslite: Both East and West Transix IPs are reachable."
        local cached_region_name_val=""
        if [ -n "$CACHE_DIR" ] && [ -f "${CACHE_DIR}/region_name.ch" ]; then # CACHE_DIR は aios 共通変数と想定
             cached_region_name_val=$(cat "${CACHE_DIR}/region_name.ch")
             if command -v is_east_japan >/dev/null 2>&1; then # is_east_japan は aios 共通関数と想定
                is_east_japan "$cached_region_name_val"
                local region_code=$?
                if [ $region_code -eq 0 ]; then # East
                    determined_region_name="East Japan"; determined_aftr_ip="$east_ip"
                elif [ $region_code -eq 1 ]; then # West
                    determined_region_name="West Japan"; determined_aftr_ip="$west_ip"
                else # Unknown from cache
                    determined_region_name="East Japan"; determined_aftr_ip="$east_ip" # Fallback to East
                fi
             else # is_east_japan not available
                determined_region_name="East Japan"; determined_aftr_ip="$east_ip" # Fallback to East
             fi
        else # Cache file not found
            determined_region_name="East Japan"; determined_aftr_ip="$east_ip" # Fallback to East
        fi
    else # Neither East nor West IPs are reachable
        determined_region_name="Unknown"; determined_aftr_ip=""
    fi
    
    debug_log "DEBUG" "get_transix_network_area_dslite: Determined Region: $determined_region_name, AFTR: $determined_aftr_ip"
    echo "${determined_region_name}|${determined_aftr_ip}"
    return 0
}

# --- Function Definitions ---

# --- Function to retrieve DS-Lite provider data based on AS Number ---
# Arguments: $1: AS Number (numeric, without "AS" prefix)
# Output: Space-separated string: AS_NUM INTERNAL_KEY "DISPLAY_NAME" AFTR_ADDRESS
# Returns: 0 if found, 1 if not found. Logs failure to debug log.
get_dslite_provider_data_by_as() {
    local search_asn="$1"
    local result=""

    # --- DS-Lite Provider Database (Here Document) ---
    provider_db=$(cat <<-'EOF'
2519 transix "transix" "USE_REGION"
2527 cross "Cross Pass" "2001:f60:0:200::1:1"
4737 v6connect "v6 Connect" "2001:c28:5:301::11"
EOF
)
    # --- End of Database ---

    result=$(echo "$provider_db" | grep "^${search_asn} " | head -n 1)

    if [ -n "$result" ]; then
        debug_log "DEBUG" "get_dslite_provider_data_by_as: Found data for ASN $search_asn: $result"
        echo "$result"
        return 0
    else
        debug_log "DEBUG" "get_dslite_provider_data_by_as: No data found for ASN $search_asn"
        return 1
    fi
}

# --- Auto Detection Provider Function (Internal) ---
# Outputs:
#   Success: "Provider Display Name|AFTR Address|Region Text|Internal Key" to stdout, returns 0.
#   Failure: Reason string (e.g., "AS cache missing", "ISP AS 12345") to stdout, returns 1.
detect_provider_internal() {
    local isp_as="" region="" reason_str=""
    local provider_data=""
    local internal_key=""
    local display_name=""
    local aftr_address=""
    local region_text=""

    local cache_as_file="${CACHE_DIR}/isp_as.ch"
    local cache_region_file="${CACHE_DIR}/region_name.ch"

    if [ ! -f "$cache_as_file" ]; then
        reason_str="AS cache missing"
        debug_log "ERROR" "detect_provider_internal: Error - AS Number cache file not found: $cache_as_file"
        echo "$reason_str"
        return 1
    fi
    isp_as=$(cat "$cache_as_file" | sed 's/^AS//i')
    if [ -z "$isp_as" ]; then
        reason_str="AS cache read error"
        debug_log "ERROR" "detect_provider_internal: Error - Failed to read AS Number from cache file: $cache_as_file"
        echo "$reason_str"
        return 1
    fi
    debug_log "DEBUG" "detect_provider_internal: Using AS Number $isp_as"

    provider_data=$(get_dslite_provider_data_by_as "$isp_as")
    if [ $? -ne 0 ] || [ -z "$provider_data" ]; then
        reason_str="ISP AS $isp_as (Unsupported)" # Added (Unsupported) for clarity in rsn
        debug_log "ERROR" "detect_provider_internal: Error - Could not find DS-Lite provider data for AS $isp_as."
        echo "$reason_str"
        return 1
    fi

    internal_key=$(echo "$provider_data" | awk '{print $2}')
    display_name=$(echo "$provider_data" | awk -F '"' '{print $2}')
    aftr_address=$(echo "$provider_data" | awk '{print $4}') # Could be "USE_REGION"

    debug_log "DEBUG" "detect_provider_internal: Parsed data - Key=$internal_key, Name=$display_name, AFTR=$aftr_address"

    if [ "$internal_key" = "transix" ] && [ "$aftr_address" = "USE_REGION" ]; then
        debug_log "DEBUG" "detect_provider_internal: Transix detected, checking region."
        if [ -f "$cache_region_file" ]; then
            region=$(cat "$cache_region_file")
        fi

        if [ -z "$region" ]; then
            reason_str="No region info for Transix"
            debug_log "ERROR" "detect_provider_internal: Error - Required region information not found in cache for Transix detection."
            echo "$reason_str"
            return 1
        fi
        debug_log "DEBUG" "detect_provider_internal: Using region info '$region' for Transix."

        is_east_japan "$region" # Assumed to be available
        local region_result=$?
        if [ $region_result -eq 0 ]; then
            display_name="Transix (East Japan)"
            # aftr_address will be determined by get_transix_network_area_dslite later,
            # but for detect_provider_internal's immediate output, this is informative.
            aftr_address="$AFTR_TRANS_EAST" 
            region_text="East Japan"
        elif [ $region_result -eq 1 ]; then
            display_name="Transix (West Japan)"
            aftr_address="$AFTR_TRANS_WEST"
            region_text="West Japan"
        else
            reason_str="Region determination failed for Transix"
            debug_log "ERROR" "detect_provider_internal: Error - Failed to determine required region (East/West) for Transix using '$region'."
            echo "$reason_str"
            return 1
        fi
        debug_log "DEBUG" "detect_provider_internal: Transix region resolved - Name=$display_name, AFTR=$aftr_address, Region=$region_text"
    fi

    echo "${display_name}|${aftr_address}|${region_text}|${internal_key}"
    return 0
}

# --- Auto Detect and Apply DS-Lite Settings ---
auto_detect_and_apply() {
    debug_log "DEBUG" "Starting DS-Lite auto-detection and application process."

    local detection_result
    local detection_status
    local reason_for_unsupported="Detection failed" # Default reason

    detection_result=$(detect_provider_internal)
    detection_status=$?

    if [ $detection_status -ne 0 ]; then
        reason_for_unsupported="$detection_result" # Use reason from detect_provider_internal
        printf "\n%s\n" "$(color red "$(get_message "MSG_DSLITE_AUTO_DETECT_UNSUPPORTED" rsn="$reason_for_unsupported")")"
        return 1
    fi

    local detected_provider_name=$(echo "$detection_result" | cut -d'|' -f1)
    local detected_aftr_info_from_db=$(echo "$detection_result" | cut -d'|' -f2)
    local detected_provider_key=$(echo "$detection_result" | cut -d'|' -f4)

    printf "\n%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$detected_provider_name" tp="DS-Lite")")" # MSG_AUTO_CONFIG_RESULT is assumed to exist

    local confirm_auto=1
    confirm "Apply these settings? {ynr}" # Original wording
    confirm_auto=$?

    if [ $confirm_auto -eq 0 ]; then # Yes
        debug_log "DEBUG" "User confirmed applying DS-Lite settings for $detected_provider_name."
        # No printf "\n" here, config_dslite_connection will handle its own message spacing
        
        if config_dslite_connection "$detected_aftr_info_from_db" "$detected_provider_name" "$detected_provider_key"; then
            # Success message (MSG_DSLITE_APPLY_SUCCESS) and reboot prompts are handled within config_dslite_connection
            debug_log "INFO" "DS-Lite configuration process completed successfully by config_dslite_connection."
            return 0
        else
            debug_log "ERROR" "config_dslite_connection failed. See previous logs for details."
            # Use a generic reason if config_dslite_connection doesn't provide one
            # For now, use a fixed reason. More specific reasons would require config_dslite_connection to output them.
            reason_for_unsupported="Configuration failed for $detected_provider_name"
            printf "\n%s\n" "$(color red "$(get_message "MSG_DSLITE_AUTO_DETECT_UNSUPPORTED" r="$reason_for_unsupported")")"
            return 1
        fi
    else # No or Return
         debug_log "DEBUG" "User declined to apply DS-Lite settings."
         # No cancellation message to user, return failure to menu handler
        return 1
    fi
}

# Configure DS-Lite settings using UCI and sed
# Arguments:
#   $1: aftr_info_from_db (AFTR Address or Domain from provider_db, or "USE_REGION" for Transix)
#   $2: provider_display_name_from_db (Display Name from provider_db)
#   $3: provider_key (Internal provider key, e.g., "transix", "cross")
# Returns 0 on success, 1 on failure.
config_dslite_connection() {
    local aftr_info_from_db="$1"
    local provider_display_name_from_db="$2"
    local provider_key="$3"

    local final_aftr_ip=""
    local final_display_name="$provider_display_name_from_db" # This might be updated for Transix
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix=""

    debug_log "DEBUG" "config_dslite_connection: Received - AFTR Info (DB): '$aftr_info_from_db', Display Name (DB): '$provider_display_name_from_db', Provider Key: '$provider_key'"

    if [ -z "$provider_key" ]; then
        debug_log "ERROR" "config_dslite_connection: Provider key is empty. Cannot proceed."
        return 1
    fi

    if [ "$provider_key" = "transix" ]; then
        debug_log "INFO" "config_dslite_connection: Provider is Transix. Performing dynamic region and AFTR determination..."
        local transix_info
        transix_info=$(get_transix_network_area_dslite)
        local transix_region_name=$(echo "$transix_info" | cut -d'|' -f1)
        final_aftr_ip=$(echo "$transix_info" | cut -d'|' -f2)

        if [ "$transix_region_name" != "Unknown" ] && [ -n "$final_aftr_ip" ]; then
            final_display_name="Transix ($transix_region_name)" # Update display name for success message
            debug_log "INFO" "config_dslite_connection: Transix region: $transix_region_name, AFTR IP: $final_aftr_ip, Display Name: $final_display_name"
        else
            debug_log "ERROR" "config_dslite_connection: Failed to determine Transix region or AFTR. Region: '$transix_region_name', AFTR: '$final_aftr_ip'."
            return 1
        fi
    else # For non-Transix providers (e.g., cross, v6connect)
        if [ -z "$aftr_info_from_db" ]; then
            debug_log "ERROR" "config_dslite_connection: AFTR information from DB is empty for Provider Key '$provider_key'."
            return 1
        fi

        if is_ipv6_address_dslite "$aftr_info_from_db"; then
            final_aftr_ip="$aftr_info_from_db"
            debug_log "DEBUG" "config_dslite_connection: AFTR '$final_aftr_ip' from DB is an IP address."
        else # AFTR from DB is a domain name
            debug_log "DEBUG" "config_dslite_connection: AFTR '$aftr_info_from_db' from DB is a domain. Attempting to resolve..."
            final_aftr_ip=$(get_aaaa_record_dslite "$aftr_info_from_db")
            if [ -z "$final_aftr_ip" ]; then
                debug_log "ERROR" "config_dslite_connection: Failed to resolve AAAA record for AFTR domain '$aftr_info_from_db'."
                return 1
            fi
        fi
        # Check reachability for the resolved/provided IP for non-Transix
        debug_log "DEBUG" "config_dslite_connection: Checking reachability for AFTR IP: $final_aftr_ip"
        if ! check_ipv6_reachability_dslite "$final_aftr_ip"; then
            debug_log "ERROR" "config_dslite_connection: Resolved/Provided AFTR IP '$final_aftr_ip' for $provider_key is not reachable."
            return 1
        fi
    fi

    if [ -z "$final_aftr_ip" ]; then
        debug_log "ERROR" "config_dslite_connection: Final AFTR IP address could not be determined."
        return 1
    fi

    debug_log "INFO" "Proceeding with DS-Lite UCI configuration. Final AFTR: $final_aftr_ip, Final Display Name: '$final_display_name' (Original Key: $provider_key)"

    if ! install_package ds-lite silent; then # install_package は aios 共通関数と想定
        debug_log "ERROR" "config_dslite_connection: Failed to install ds-lite package."
        return 1
    fi
    debug_log "DEBUG" "ds-lite package installed or already present."

    debug_log "DEBUG" "Backing up /etc/config/network to $NETWORK_BACKUP"
    cp /etc/config/network "$NETWORK_BACKUP" 2>/dev/null
    if [ -f "$proto_script" ]; then
        if [ ! -f "$PROTO_BACKUP" ]; then
            debug_log "DEBUG" "Backing up $proto_script to $PROTO_BACKUP"
            cp "$proto_script" "$PROTO_BACKUP" 2>/dev/null
        else
            debug_log "DEBUG" "Protocol script backup $PROTO_BACKUP already exists."
        fi
    else
         debug_log "DEBUG" "Protocol script $proto_script not found, cannot back up."
    fi

    debug_log "DEBUG" "Applying UCI settings for DS-Lite with AFTR: $final_aftr_ip."
    uci -q batch <<EOF
set network.wan.auto='0'
set dhcp.lan.ra='relay'
set dhcp.lan.dhcpv6='server'
set dhcp.lan.ndp='relay'
set dhcp.lan.force='1'
set dhcp.wan6=dhcp
set dhcp.wan6.interface='wan6'
set dhcp.wan6.ignore='1'
set dhcp.wan6.master='1'
set dhcp.wan6.ra='relay'
set dhcp.wan6.dhcpv6='relay'
set dhcp.wan6.ndp='relay'
delete network.ds_lite
set network.ds_lite=interface
set network.ds_lite.proto='dslite'
set network.ds_lite.peeraddr='$final_aftr_ip'
set network.ds_lite.mtu='1460'
local current_networks=\$(uci -q get firewall.@zone[$FW_ZONE_INDEX].network 2>/dev/null)
local found=0
local net=""
for net in \$current_networks; do if [ "\$net" = "ds_lite" ]; then found=1; break; fi; done
if [ "\$found" -eq 0 ]; then add_list firewall.@zone[$FW_ZONE_INDEX].network='ds_lite'; fi
commit dhcp
commit network
commit firewall
EOF
    if [ $? -ne 0 ]; then
         debug_log "ERROR" "config_dslite_connection: Failed to apply UCI settings."
         return 1
    fi
    debug_log "DEBUG" "UCI settings applied successfully."

    if [ -f "$proto_script" ]; then
        debug_log "DEBUG" "Checking MTU in $proto_script"
        if grep -q "mtu:-1280" "$proto_script"; then
            debug_log "DEBUG" "Modifying MTU from 1280 to 1460 in $proto_script"
            sed "s/mtu:-1280/mtu:-1460/g" "$proto_script" > "${proto_script}.tmp"
            if [ $? -eq 0 ] && [ -s "${proto_script}.tmp" ]; then
                mv "${proto_script}.tmp" "$proto_script"
                debug_log "DEBUG" "Successfully modified MTU in $proto_script."
            else
                debug_log "WARN" "config_dslite_connection: Failed to modify protocol script MTU (sed failed or produced empty file). Continuing."
                rm -f "${proto_script}.tmp"
            fi
        else
            debug_log "DEBUG" "MTU in $proto_script does not need modification or was already changed from 1280."
        fi
    else
        debug_log "WARN" "config_dslite_connection: Protocol script $proto_script not found after package install. Cannot modify MTU."
    fi

    # Use existing success message key with the determined provider name
    printf "\n%s\n" "$(color green "$(get_message "MSG_DSLITE_APPLY_SUCCESS" sp="$final_display_name")")"

    printf "%s\n" "$(get_message MSG_REBOOT_REQUIRED)" # MSG_REBOOT_REQUIRED is assumed to exist
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi # color is assumed
    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # MSG_CONFIRM_REBOOT is assumed to exist
    confirm_reboot=$?
    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%s%s\n" "$msg_prefix" "$(get_message MSG_REBOOTING)" # MSG_REBOOTING is assumed
        reboot; exit 0 # reboot is assumed
    fi

    return 0
}

# Restore original settings
restore_dslite_settings() {
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix=""

    debug_log "DEBUG" "Restoring settings before DS-Lite configuration."

    debug_log "DEBUG" "Checking for network backup: $NETWORK_BACKUP"
    if [ -f "$NETWORK_BACKUP" ]; then
        debug_log "DEBUG" "Restoring /etc/config/network from $NETWORK_BACKUP"
        if cp "$NETWORK_BACKUP" /etc/config/network; then
            rm "$NETWORK_BACKUP"
        else
             debug_log "WARN" "Warning: Failed to restore /etc/config/network from backup. Backup not removed."
        fi
    else
        debug_log "DEBUG" "Network configuration backup $NETWORK_BACKUP not found."
    fi

    debug_log "DEBUG" "Checking for protocol script backup: $PROTO_BACKUP"
    if [ -f "$PROTO_BACKUP" ]; then
        debug_log "DEBUG" "Restoring $proto_script from $PROTO_BACKUP"
        if cp "$PROTO_BACKUP" "$proto_script"; then
            rm "$PROTO_BACKUP"
        else
             debug_log "WARN" "Warning: Failed to restore $proto_script from backup. Backup not removed."
        fi
    elif [ -f "$proto_script" ]; then
         debug_log "DEBUG" "Protocol backup not found. Attempting to revert MTU change in $proto_script."
         if grep -q "mtu:-1460" "$proto_script"; then
              sed "s/mtu:-1460/mtu:-1280/g" "$proto_script" > "${proto_script}.tmp"
              if [ $? -eq 0 ] && [ -s "${proto_script}.tmp" ]; then
                  mv "${proto_script}.tmp" "$proto_script"
                  debug_log "DEBUG" "Reverted MTU change in $proto_script."
              else
                  debug_log "WARN" "Warning: Failed to revert MTU change in $proto_script (sed failed or produced empty file)."
                  rm -f "${proto_script}.tmp"
              fi
         else
              debug_log "DEBUG" "MTU in $proto_script does not appear to need reverting."
         fi
    else
         debug_log "DEBUG" "Protocol script $proto_script not found, cannot restore or revert."
    fi

    debug_log "DEBUG" "Removing ds_lite interface and firewall entries via UCI."
    uci -q batch <<EOF
delete network.ds_lite
local zone_count=\$(uci show firewall | grep -c "@zone\[")
local i=0
while [ \$i -lt \$zone_count ]; do
    local current_networks=\$(uci -q get firewall.@zone[\$i].network 2>/dev/null)
    local updated_networks=""
    local changed=0
    local net=""
    for net in \$current_networks; do
        if [ "\$net" = "ds_lite" ]; then
             changed=1
        else
             if [ -n "\$updated_networks" ]; then updated_networks="\$updated_networks \$net"; else updated_networks="\$net"; fi
        fi
    done
    if [ "\$changed" -eq 1 ]; then
         if [ -z "\$updated_networks" ]; then
              delete firewall.@zone[\$i].network
         else
              set firewall.@zone[\$i].network="\$updated_networks"
         fi
    fi
    i=\$((\$i + 1))
done
commit network
commit firewall
EOF
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "Error: UCI commands to remove ds_lite interface/firewall entries failed."
        return 1
    fi
    debug_log "DEBUG" "UCI commands for removal executed successfully."

    printf "\n%s\n" "$(color green "$(get_message "MSG_DSLITE_RESTORE_SUCCESS")")"

    printf "%s\n" "$(get_message MSG_REBOOT_REQUIRED)"
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi
    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT"
    confirm_reboot=$?
    if [ $confirm_reboot -eq 0 ]; then
        printf "%s%s\n" "$msg_prefix" "$(get_message MSG_REBOOTING)"
        reboot; exit 0
    fi

    return 0
}

# --- is_east_japan function (assumed loaded from common-country.sh) ---
# Function definition is not needed here as it's assumed to be loaded.

# --- Script Execution ---
# This script defines functions to be called from menu.db or other scripts.
# It does not run main logic automatically when sourced.

: # No-op to ensure the script sourcing doesn't cause unexpected output or errors
