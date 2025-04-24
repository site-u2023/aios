#!/bin/sh

SCRIPT_VERSION="2025.04.21-10:35" # Reflecting final error handling, message key usage, and POSIX compliance

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-04-21
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 24.10.0)
#
# ⚠️ IMPORTANT NOTICE:
# OpenWrt OS exclusively uses **Almquist Shell (ash)** and
# is **NOT** compatible with Bourne-Again Shell (bash).
#
# 📢 POSIX Compliance Guidelines:
# ✅ Use `[` instead of `[[` for conditions
# ✅ Use $(command) instead of backticks `command`
# ✅ Use $(( )) for arithmetic instead of let
# ✅ Define functions as func_name() {} (no function keyword)
# ✅ No associative arrays (declare -A is NOT supported)
# ✅ No here-strings (<<< is NOT supported)
# ✅ No -v flag in test or [[
# ✅ Avoid bash-specific string operations like ${var:0:3}
# ✅ Avoid arrays entirely when possible (even indexed arrays can be problematic)
# ✅ Use printf followed by read instead of read -p
# ✅ Use printf instead of echo -e for portable formatting
# ✅ Avoid process substitution <() and >()
# ✅ Prefer case statements over complex if/elif chains
# ✅ Use command -v instead of which or type for command existence checks
# ✅ Keep scripts modular with small, focused functions
# ✅ Use simple error handling instead of complex traps
# ✅ Test scripts with ash/dash explicitly, not just bash
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
### =========================================================

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

# --- Function Definitions ---

# --- Function to retrieve DS-Lite provider data based on AS Number ---
# Arguments: $1: AS Number (numeric, without "AS" prefix)
# Output: Space-separated string: AS_NUM INTERNAL_KEY "DISPLAY_NAME" AFTR_ADDRESS
# Returns: 0 if found, 1 if not found. Logs failure to debug log.
get_dslite_provider_data_by_as() {
    local search_asn="$1"
    local result=""

    # --- DS-Lite Provider Database (Here Document) ---
    # POSIX compliant way to define multi-line string
    provider_db=$(cat <<-'EOF'
2519 transix "transix" "USE_REGION"
2527 cross "Cross Pass" "2001:f60:0:200::1:1"
4737 v6connect "v6 Connect" "2001:c28:5:301::11"
EOF
)
    # --- End of Database ---

    # POSIX compliant grep and head
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
#   Success: "Provider Display Name|AFTR Address|Region Text" to stdout, returns 0.
#   Failure: Reason string (e.g., "AS cache missing", "ISP AS 12345") to stdout, returns 1.
#            Logs detailed error to debug log. No stderr output.
detect_provider_internal() {
    local isp_as="" region="" reason_str=""
    local provider_data=""
    local internal_key=""
    local display_name=""
    local aftr_address=""
    local region_text="" # Keep region_text for output consistency

    local cache_as_file="${CACHE_DIR}/isp_as.ch"
    local cache_region_code_file="${CACHE_DIR}/ip_region_code.tmp"
    local cache_region_name_file="${CACHE_DIR}/ip_region_name.tmp"

    # Read AS number from cache (POSIX compliant checks)
    if [ ! -f "$cache_as_file" ]; then
        reason_str="AS cache missing"
        debug_log "DEBUG" "detect_provider_internal: Error - AS Number cache file not found: $cache_as_file"
        echo "$reason_str"
        return 1
    fi
    # POSIX compliant read and sed
    isp_as=$(cat "$cache_as_file" | sed 's/^AS//i')
    # Handle empty isp_as after sed or read failure (POSIX compliant check)
    if [ -z "$isp_as" ]; then
        reason_str="AS cache read error"
        debug_log "DEBUG" "detect_provider_internal: Error - Failed to read AS Number from cache file: $cache_as_file"
        echo "$reason_str"
        return 1
    fi
    debug_log "DEBUG" "detect_provider_internal: Using AS Number $isp_as"

    # Get provider data
    provider_data=$(get_dslite_provider_data_by_as "$isp_as")
    # POSIX compliant check for function success and non-empty result
    if [ $? -ne 0 ] || [ -z "$provider_data" ]; then
        reason_str="ISP AS $isp_as" # Reason is the unsupported AS number
        debug_log "DEBUG" "detect_provider_internal: Error - Could not find DS-Lite provider data for AS $isp_as."
        echo "$reason_str"
        return 1
    fi

    # Parse provider data (handle quoted display name) - POSIX awk
    internal_key=$(echo "$provider_data" | awk '{print $2}')
    display_name=$(echo "$provider_data" | awk -F '"' '{print $2}')
    aftr_address=$(echo "$provider_data" | awk '{print $4}') # Could be "USE_REGION"

    debug_log "DEBUG" "detect_provider_internal: Parsed data - Key=$internal_key, Name=$display_name, AFTR=$aftr_address"

    # Handle Transix region check if needed (POSIX compliant checks)
    if [ "$internal_key" = "transix" ] && [ "$aftr_address" = "USE_REGION" ]; then
        debug_log "DEBUG" "detect_provider_internal: Transix detected, checking region."
        # Read region from cache (try both code and name) - POSIX compliant
        if [ -f "$cache_region_code_file" ]; then region=$(cat "$cache_region_code_file"); fi
        if [ -z "$region" ] && [ -f "$cache_region_name_file" ]; then region=$(cat "$cache_region_name_file"); fi

        if [ -z "$region" ]; then
            reason_str="No region info for Transix"
            debug_log "DEBUG" "detect_provider_internal: Error - Required region information not found in cache for Transix detection."
            echo "$reason_str"
            return 1
        fi
        debug_log "DEBUG" "detect_provider_internal: Using region info '$region' for Transix."

        # is_east_japan function is assumed to be loaded
        is_east_japan "$region"
        local region_result=$?
        # POSIX compliant check for return status
        if [ $region_result -eq 0 ]; then
            display_name="Transix (East Japan)"
            aftr_address="$AFTR_TRANS_EAST"
            region_text="East Japan"
        elif [ $region_result -eq 1 ]; then
            display_name="Transix (West Japan)"
            aftr_address="$AFTR_TRANS_WEST"
            region_text="West Japan"
        else
            reason_str="Region determination failed for Transix"
            debug_log "DEBUG" "detect_provider_internal: Error - Failed to determine required region (East/West) for Transix using '$region'."
            echo "$reason_str"
            return 1
        fi
        debug_log "DEBUG" "detect_provider_internal: Transix region resolved - Name=$display_name, AFTR=$aftr_address, Region=$region_text"
    fi

    # Output in the unified format on success - POSIX echo/printf
    echo "${display_name}|${aftr_address}|${region_text}"
    return 0
}

# --- Auto Detect and Apply DS-Lite Settings ---
# Called by menu.db or internet-auto-config.sh
# Uses get_message for success/unsupported messages. Logs errors to debug log.
# No stderr output.
auto_detect_and_apply() {
    debug_log "DEBUG" "Starting DS-Lite auto-detection and application process."

    # Perform internal detection
    local detection_result
    local detection_status # Store return status

    # Capture stdout and check status separately - POSIX compliant
    detection_result=$(detect_provider_internal)
    detection_status=$?

    if [ $detection_status -ne 0 ]; then
        # Failure reason already logged by detect_provider_internal
        # Display unsupported message using the reason from stdout
        # POSIX printf
        printf "\n%s\n" "$(color red "$(get_message "MSG_DSLITE_AUTO_DETECT_UNSUPPORTED" rsn="$detection_result")")"
        return 1 # Return failure to menu handler
    fi

    # Parse detection result - POSIX cut
    local detected_provider=$(echo "$detection_result" | cut -d'|' -f1)
    local detected_aftr=$(echo "$detection_result" | cut -d'|' -f2)
    # local detected_region_text=$(echo "$detection_result" | cut -d'|' -f3) # Region text not used

    # Display detected provider result using MSG_AUTO_CONFIG_RESULT (assuming this key exists and is desired)
    # If only success/failure is needed, this can be removed. POSIX printf
    printf "\n%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$detected_provider" tp="DS-Lite")")"

    # Confirm with the user (hardcoded English question - consider message key if localization needed)
    local confirm_auto=1
    confirm "Apply these settings? {ynr}" # Assumes confirm function is POSIX compliant
    confirm_auto=$?

    # POSIX compliant check for return status
    if [ $confirm_auto -eq 0 ]; then # Yes
        debug_log "DEBUG" "User confirmed applying DS-Lite settings for $detected_provider."
        printf "\n" # Newline before potential success message
        # Pass AFTR and Provider Name to apply_dslite_settings
        apply_dslite_settings "$detected_aftr" "$detected_provider"
        local apply_status=$?
        # apply_dslite_settings handles its own success message.
        # Return its status directly.
        return $apply_status
    else # No or Return
         debug_log "DEBUG" "User declined to apply DS-Lite settings."
         # No cancellation message to user, return failure to menu handler
        return 1
    fi
}

# Apply DS-Lite settings using UCI and sed
# $1: AFTR Address
# $2: Service Name/Key (used for logging)
# Uses get_message for success and reboot messages. Logs errors to debug log.
# No stderr output. No starting message. Returns 0 on success, 1 on failure.
apply_dslite_settings() {
    local aftr_address="$1"
    local service_key="$2" # Used for logging
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix="" # For reboot messages

    debug_log "DEBUG" "Applying DS-Lite settings for AFTR: $aftr_address (Key: $service_key)"
    # No starting message to stdout

    # 1. Install ds-lite package silently (Assumes install_package is POSIX compliant)
    if ! install_package ds-lite silent; then
        debug_log "DEBUG" "Error: Failed to install ds-lite package."
        return 1
    fi
    debug_log "DEBUG" "ds-lite package installed or already present."

    # 2. Backup original files (Log errors only) - POSIX cp
    debug_log "DEBUG" "Backing up /etc/config/network to $NETWORK_BACKUP"
    cp /etc/config/network "$NETWORK_BACKUP" 2>/dev/null # Ignore cp error for backup
    if [ -f "$proto_script" ]; then
        if [ ! -f "$PROTO_BACKUP" ]; then
            debug_log "DEBUG" "Backing up $proto_script to $PROTO_BACKUP"
            cp "$proto_script" "$PROTO_BACKUP" 2>/dev/null # Ignore cp error for backup
        else
            debug_log "DEBUG" "Protocol script backup $PROTO_BACKUP already exists."
        fi
    else
         debug_log "DEBUG" "Protocol script $proto_script not found, cannot back up."
         # Continue without backup
    fi

    # 3. Configure UCI settings (Log errors, return 1 on failure) - Assumes uci is POSIX compliant
    debug_log "DEBUG" "Applying UCI settings for DS-Lite."
    # POSIX compliant here-document for uci batch
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
set network.ds_lite.peeraddr='$aftr_address'
set network.ds_lite.mtu='1460'
# Add ds_lite to wan firewall zone if not already present - POSIX compliant loop
local current_networks=\$(uci -q get firewall.@zone[$FW_ZONE_INDEX].network 2>/dev/null)
local found=0
local net="" # POSIX variable declaration
for net in \$current_networks; do if [ "\$net" = "ds_lite" ]; then found=1; break; fi; done
if [ "\$found" -eq 0 ]; then add_list firewall.@zone[$FW_ZONE_INDEX].network='ds_lite'; fi
commit dhcp
commit network
commit firewall
EOF
    # POSIX compliant check for return status
    if [ $? -ne 0 ]; then
         debug_log "DEBUG" "Error: Failed to apply UCI settings."
         return 1
    fi
    debug_log "DEBUG" "UCI settings applied successfully."

    # 4. Modify proto script MTU (Log errors only, non-fatal) - POSIX grep, sed, mv, rm
    if [ -f "$proto_script" ]; then
        debug_log "DEBUG" "Checking MTU in $proto_script"
        if grep -q "mtu:-1280" "$proto_script"; then
            debug_log "DEBUG" "Modifying MTU from 1280 to 1460 in $proto_script"
            # Use temporary file for sed to handle potential errors better
            sed "s/mtu:-1280/mtu:-1460/g" "$proto_script" > "${proto_script}.tmp"
            # POSIX compliant check for sed success and non-empty temp file
            if [ $? -eq 0 ] && [ -s "${proto_script}.tmp" ]; then
                mv "${proto_script}.tmp" "$proto_script"
                debug_log "DEBUG" "Successfully modified MTU in $proto_script."
            else
                debug_log "DEBUG" "Error: Failed to modify protocol script MTU (sed failed or produced empty file). Continuing."
                rm -f "${proto_script}.tmp"
                # Non-fatal error, continue
            fi
        else
            debug_log "DEBUG" "MTU in $proto_script does not need modification or was already changed."
        fi
    else
        debug_log "DEBUG" "Protocol script $proto_script not found after package install. Cannot modify MTU."
    fi

    # 5. Success Message (using get_message) to stdout - POSIX printf
    printf "\n%s\n" "$(color green "$(get_message "MSG_DSLITE_APPLY_SUCCESS")")"

    # 6. Reboot Confirmation (using common get_message keys) - POSIX printf
    printf "%s\n" "$(get_message MSG_REBOOT_REQUIRED)" # Use existing common key

    # Setup msg_prefix for confirm messages if color is available - POSIX command -v
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi

    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # Use existing common key
    confirm_reboot=$?
    # POSIX compliant check for return status
    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%s%s\n" "$msg_prefix" "$(get_message MSG_REBOOTING)" # Use existing common key
        reboot; exit 0 # Exit script after initiating reboot (Assumes reboot is available)
    # No messages needed for "No" or "Return" cases here.
    # The calling function (menu.db) should handle the return status.
    fi

    return 0 # Return success if reboot not chosen or confirm failed
}

# Restore original settings
# Uses get_message for success and reboot messages. Logs errors to debug log.
# No stderr output. No starting message. Returns 0 on success, 1 on failure.
restore_dslite_settings() {
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix="" # For reboot messages

    debug_log "DEBUG" "Restoring settings before DS-Lite configuration."
    # No starting message to stdout

    # 1. Restore network config (Log errors only, non-fatal) - POSIX cp, rm
    debug_log "DEBUG" "Checking for network backup: $NETWORK_BACKUP"
    if [ -f "$NETWORK_BACKUP" ]; then
        debug_log "DEBUG" "Restoring /etc/config/network from $NETWORK_BACKUP"
        # Ensure copy succeeds before removing backup
        if cp "$NETWORK_BACKUP" /etc/config/network; then
            rm "$NETWORK_BACKUP"
        else
             debug_log "DEBUG" "Warning: Failed to restore /etc/config/network from backup. Backup not removed."
             # Continue restoration attempt (non-fatal)
        fi
    else
        debug_log "DEBUG" "Network configuration backup $NETWORK_BACKUP not found."
    fi

    # 2. Restore proto script (Log errors only, non-fatal) - POSIX cp, rm, grep, sed, mv
    debug_log "DEBUG" "Checking for protocol script backup: $PROTO_BACKUP"
    if [ -f "$PROTO_BACKUP" ]; then
        debug_log "DEBUG" "Restoring $proto_script from $PROTO_BACKUP"
        # Ensure copy succeeds before removing backup
        if cp "$PROTO_BACKUP" "$proto_script"; then
            rm "$PROTO_BACKUP"
        else
             debug_log "DEBUG" "Warning: Failed to restore $proto_script from backup. Backup not removed."
             # Continue restoration attempt (non-fatal)
        fi
    elif [ -f "$proto_script" ]; then
         # Attempt to revert MTU change if backup doesn't exist
         debug_log "DEBUG" "Protocol backup not found. Attempting to revert MTU change in $proto_script."
         if grep -q "mtu:-1460" "$proto_script"; then
              # Use temporary file for sed
              sed "s/mtu:-1460/mtu:-1280/g" "$proto_script" > "${proto_script}.tmp"
              # POSIX compliant check for sed success and non-empty temp file
              if [ $? -eq 0 ] && [ -s "${proto_script}.tmp" ]; then
                  mv "${proto_script}.tmp" "$proto_script"
                  debug_log "DEBUG" "Reverted MTU change in $proto_script."
              else
                  debug_log "DEBUG" "Warning: Failed to revert MTU change in $proto_script (sed failed or produced empty file)."
                  rm -f "${proto_script}.tmp"
                  # Non-fatal
              fi
         else
              debug_log "DEBUG" "MTU in $proto_script does not appear to need reverting."
         fi
    else
         debug_log "DEBUG" "Protocol script $proto_script not found, cannot restore or revert."
    fi

    # 3. Remove ds_lite interface and firewall entry (Log errors, return 1 on failure) - Assumes uci is POSIX compliant
    debug_log "DEBUG" "Removing ds_lite interface and firewall entries via UCI."
    # POSIX compliant here-document and loop for uci batch
    uci -q batch <<EOF
delete network.ds_lite
# Iterate through firewall zones to remove ds_lite from network list
local zone_count=\$(uci show firewall | grep -c "@zone\[")
local i=0
while [ \$i -lt \$zone_count ]; do
    local current_networks=\$(uci -q get firewall.@zone[\$i].network 2>/dev/null)
    local updated_networks=""
    local changed=0
    local net="" # POSIX variable declaration
    for net in \$current_networks; do
        if [ "\$net" = "ds_lite" ]; then
             changed=1
        else
             # Append with space only if updated_networks is not empty - POSIX compliant string building
             if [ -n "\$updated_networks" ]; then updated_networks="\$updated_networks \$net"; else updated_networks="\$net"; fi
        fi
    done
    if [ "\$changed" -eq 1 ]; then
         if [ -z "\$updated_networks" ]; then
              # If list becomes empty, delete the option
              delete firewall.@zone[\$i].network
         else
              # Otherwise, set the cleaned list
              set firewall.@zone[\$i].network="\$updated_networks"
         fi
    fi
    # POSIX compliant arithmetic
    i=\$((\$i + 1))
done
commit network
commit firewall
EOF
    # POSIX compliant check for return status
    if [ $? -ne 0 ]; then
        debug_log "DEBUG" "Error: UCI commands to remove ds_lite interface/firewall entries failed."
        return 1
    fi
    debug_log "DEBUG" "UCI commands for removal executed successfully."

    # 4. Success Message (using get_message) to stdout - POSIX printf
    printf "\n%s\n" "$(color green "$(get_message "MSG_DSLITE_RESTORE_SUCCESS")")"

    # 5. Reboot Confirmation (using common get_message keys) - POSIX printf
    printf "%s\n" "$(get_message MSG_REBOOT_REQUIRED)" # Use existing common key

    # Setup msg_prefix for confirm messages if color is available - POSIX command -v
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi

    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # Use existing common key
    confirm_reboot=$?
    # POSIX compliant check for return status
    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%s%s\n" "$msg_prefix" "$(get_message MSG_REBOOTING)" # Use existing common key
        reboot; exit 0 # Exit script after initiating reboot
    # No messages needed for "No" or "Return" cases here.
    fi

    return 0 # Return success if reboot not chosen or confirm failed
}

# --- is_east_japan function (assumed loaded from common-country.sh) ---
# Function definition is not needed here as it's assumed to be loaded.

# --- Script Execution ---
# This script defines functions to be called from menu.db or other scripts.
# It does not run main logic automatically when sourced.

: # No-op to ensure the script sourcing doesn't cause unexpected output or errors
