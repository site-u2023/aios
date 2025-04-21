#!/bin/sh

SCRIPT_VERSION="2025.04.21-10:15" # Reflecting updated error handling and message keys

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
# Returns: 0 if found, 1 if not found.
get_dslite_provider_data_by_as() {
    local search_asn="$1"
    local result=""

    # --- DS-Lite Provider Database (Here Document) ---
    local provider_db=$(cat <<-'EOF'
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
#   On Success: "Provider Display Name|AFTR Address|Region Text" to stdout, returns 0.
#   On Failure: Short reason string to stdout, logs debug message, returns 1.
detect_provider_internal() {
    local isp_as="" region=""
    local provider_data=""
    local internal_key=""
    local display_name=""
    local aftr_address=""
    local region_text="" # Keep region_text for output consistency
    local reason_str="" # For outputting failure reason

    local cache_as_file="${CACHE_DIR}/ip_as.tmp"
    local cache_region_code_file="${CACHE_DIR}/ip_region_code.tmp"
    local cache_region_name_file="${CACHE_DIR}/ip_region_name.tmp"

    # Read AS number from cache
    if [ ! -f "$cache_as_file" ] || ! isp_as=$(cat "$cache_as_file" | sed 's/^AS//i'); then
        debug_log "DEBUG" "detect_provider_internal: AS Number cache file not found or empty: $cache_as_file"
        reason_str="Required AS cache not found"
        echo "$reason_str" # Output reason to stdout
        return 1
    fi
    # Handle empty isp_as after sed
    if [ -z "$isp_as" ]; then
        debug_log "DEBUG" "detect_provider_internal: Failed to read AS Number from cache file: $cache_as_file"
        reason_str="Failed to read AS Number from cache"
        echo "$reason_str" # Output reason to stdout
        return 1
    fi
    debug_log "DEBUG" "detect_provider_internal: Using AS Number $isp_as"

    # Get provider data
    provider_data=$(get_dslite_provider_data_by_as "$isp_as")
    if [ $? -ne 0 ] || [ -z "$provider_data" ]; then
        debug_log "DEBUG" "detect_provider_internal: Could not find DS-Lite provider data for AS $isp_as."
        reason_str="Unsupported ISP AS ${isp_as}"
        echo "$reason_str" # Output reason to stdout
        return 1
    fi

    # Parse provider data (handle quoted display name)
    internal_key=$(echo "$provider_data" | awk '{print $2}')
    display_name=$(echo "$provider_data" | awk -F '"' '{print $2}')
    aftr_address=$(echo "$provider_data" | awk '{print $4}') # Could be "USE_REGION"

    debug_log "DEBUG" "detect_provider_internal: Parsed data - Key=$internal_key, Name=$display_name, AFTR=$aftr_address"

    # Handle Transix region check if needed
    if [ "$internal_key" = "transix" ] && [ "$aftr_address" = "USE_REGION" ]; then
        debug_log "DEBUG" "detect_provider_internal: Transix detected, checking region."
        # Read region from cache (try both code and name)
        if [ -f "$cache_region_code_file" ]; then region=$(cat "$cache_region_code_file"); fi
        if [ -z "$region" ] && [ -f "$cache_region_name_file" ]; then region=$(cat "$cache_region_name_file"); fi

        if [ -z "$region" ]; then
            debug_log "DEBUG" "detect_provider_internal: Required region information not found in cache for Transix detection."
            reason_str="Required region cache not found for Transix"
            echo "$reason_str" # Output reason to stdout
            return 1
        fi
        debug_log "DEBUG" "detect_provider_internal: Using region info '$region' for Transix."

        # is_east_japan function is assumed to be loaded
        is_east_japan "$region"
        local region_result=$?
        if [ $region_result -eq 0 ]; then
            display_name="Transix (East Japan)"
            aftr_address="$AFTR_TRANS_EAST"
            region_text="East Japan"
        elif [ $region_result -eq 1 ]; then
            display_name="Transix (West Japan)"
            aftr_address="$AFTR_TRANS_WEST"
            region_text="West Japan"
        else
            debug_log "DEBUG" "detect_provider_internal: Failed to determine required region (East/West) for Transix using '$region'."
            reason_str="Region determination failed for Transix ('${region}')"
            echo "$reason_str" # Output reason to stdout
            return 1
        fi
        debug_log "DEBUG" "detect_provider_internal: Transix region resolved - Name=$display_name, AFTR=$aftr_address, Region=$region_text"
    fi

    # Output in the unified format on success
    echo "${display_name}|${aftr_address}|${region_text}"
    return 0
}

# --- Auto Detect and Apply DS-Lite Settings ---
# Called by menu.db or internet-auto-config.sh
# Uses get_message for success result and unsupported reason, hardcoded English for confirmation.
auto_detect_and_apply() {
    debug_log "DEBUG" "Starting DS-Lite auto-detection and application process."

    # Perform internal detection and capture stdout (reason string on failure, result on success)
    local detection_result=""
    local reason_str=""
    # Use command substitution and check status code
    detection_result=$(detect_provider_internal)
    local detection_status=$?

    # --- Error Handling Block ---
    if [ $detection_status -ne 0 ]; then
        # Specific error message should have been logged by detect_provider_internal
        debug_log "DEBUG" "DS-Lite auto-detection failed (detect_provider_internal returned status $detection_status)."
        # The reason string is in $detection_result on failure
        reason_str="$detection_result"
        # Log the reason string for debugging
        debug_log "DEBUG" "Reason for failure: $reason_str"

        # Display the error message using the existing key and {rsn} placeholder.
        # As per user instruction, {:} in the message definition requires no special handling here.
        printf "\n%s\n" "$(color red "$(get_message "MSG_DSLITE_AUTO_DETECT_UNSUPPORTED" rsn="$reason_str")")"

        # Return failure status to the menu handler
        return 1
    fi
    # --- End of Error Handling Block ---

    # --- Success Path ---
    # Parse success detection result (Provider|AFTR|Region)
    local detected_provider=$(echo "$detection_result" | cut -d'|' -f1)
    local detected_aftr=$(echo "$detection_result" | cut -d'|' -f2)
    # local detected_region_text=$(echo "$detection_result" | cut -d'|' -f3) # Region text not used

    # Display success result using get_message to stdout
    printf "\n%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$detected_provider" tp="DS-Lite")")"

    # Confirm with the user (hardcoded English question)
    local confirm_auto=1
    confirm "Apply these settings? {ynr}" # Hardcoded English
    confirm_auto=$?

    if [ $confirm_auto -eq 0 ]; then # Yes
        debug_log "DEBUG" "User confirmed applying DS-Lite settings for $detected_provider."
        printf "\n"
        # Pass AFTR and Provider Name (for {sp}) to apply_dslite_settings
        apply_dslite_settings "$detected_aftr" "$detected_provider"
        return $?
    else # No or Return
          debug_log "DEBUG" "User declined to apply DS-Lite settings."
          # Return failure status to the menu handler (no user message for cancellation)
         return 1
     fi
 }
 
# Apply DS-Lite settings using UCI and sed
# $1: AFTR Address
# $2: Service Provider Name (for {sp} placeholder)
# Uses get_message for success and reboot messages, hardcoded English for errors/start.
apply_dslite_settings() {
    local aftr_address="$1"
    local service_provider_name="$2" # Renamed for clarity with {sp}
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix="" # For reboot messages

    debug_log "DEBUG" "Applying DS-Lite settings for AFTR: $aftr_address (Provider: $service_provider_name)"
    printf "%s\n" "$(color blue "Applying DS-Lite settings...")" # Hardcoded English start message

    # 1. Install ds-lite package silently
    if ! install_package ds-lite silent; then
        # Hardcoded specific error to stderr
        printf "\033[31mError: Failed to install ds-lite package.\033[0m\n" >&2
        return 1
    fi
    debug_log "DEBUG" "ds-lite package installed or already present."

    # 2. Backup original files (No user message)
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
         # Continue without backup
    fi

    # 3. Configure UCI settings (No user message)
    debug_log "DEBUG" "Applying UCI settings for DS-Lite."
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
# Add ds_lite to wan firewall zone if not already present
local current_networks=\$(uci -q get firewall.@zone[$FW_ZONE_INDEX].network 2>/dev/null)
local found=0
for net in \$current_networks; do if [ "\$net" = "ds_lite" ]; then found=1; break; fi; done
if [ "\$found" -eq 0 ]; then add_list firewall.@zone[$FW_ZONE_INDEX].network='ds_lite'; fi
commit dhcp
commit network
commit firewall
EOF
    if [ $? -ne 0 ]; then
         # Hardcoded specific error to stderr
         printf "\033[31mError: Failed to apply UCI settings.\033[0m\n" >&2
         return 1
    fi
    debug_log "DEBUG" "UCI settings applied successfully."

    # 4. Modify proto script MTU (No user message)
    if [ -f "$proto_script" ]; then
        debug_log "DEBUG" "Checking MTU in $proto_script"
        if grep -q "mtu:-1280" "$proto_script"; then
            debug_log "DEBUG" "Modifying MTU from 1280 to 1460 in $proto_script"
            sed -i -e "s/mtu:-1280/mtu:-1460/g" "$proto_script"
            if [ $? -ne 0 ]; then
                # Log debug but don't fail the whole process
                debug_log "DEBUG" "Failed to modify protocol script MTU, but continuing."
            fi
        else
            debug_log "DEBUG" "MTU in $proto_script does not need modification or was already changed."
        fi
    else
        debug_log "DEBUG" "Protocol script $proto_script not found after package install. Cannot modify MTU."
    fi

    # 5. Success Message (using get_message with {sp}) to stdout
    printf "\n%s\n" "$(color green "$(get_message "MSG_DSLITE_APPLY_SUCCESS" sp="$service_provider_name")")"

    # 6. Reboot Confirmation (using common get_message keys)
    printf "%s\n" "$(get_message MSG_REBOOT_REQUIRED)" # Use existing common key

    # Setup msg_prefix for confirm messages if color is available
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi

    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # Use existing common key
    confirm_reboot=$?
    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%s%s\n" "$msg_prefix" "$(get_message MSG_REBOOTING)" # Use existing common key
        reboot; exit 0 # Exit script after initiating reboot
    elif [ $confirm_reboot -eq 2 ]; then # Return
         # Hardcoded English message to stdout
         printf "%sReturning to menu.\n" "$msg_prefix"
         return 0 # Return success to menu handler
    else # No
        # Hardcoded English message to stdout
        printf "%sSettings applied. Please reboot the device later.\n" "$msg_prefix"
        return 0 # Return success to menu handler
    fi
}

# Restore original settings
# Uses get_message for success and reboot messages, hardcoded English for errors/warnings/start.
restore_dslite_settings() {
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix="" # For reboot messages

    debug_log "DEBUG" "Restoring settings before DS-Lite configuration."
    printf "%s\n" "$(color blue "Restoring previous DS-Lite settings...")" # Hardcoded English start message

    # 1. Restore network config (No user message on success)
    debug_log "DEBUG" "Checking for network backup: $NETWORK_BACKUP"
    if [ -f "$NETWORK_BACKUP" ]; then
        debug_log "DEBUG" "Restoring /etc/config/network from $NETWORK_BACKUP"
        # Ensure copy succeeds before removing backup
        if cp "$NETWORK_BACKUP" /etc/config/network; then
            rm "$NETWORK_BACKUP"
        else
             # Hardcoded specific warning to stderr (non-fatal)
             printf "\033[33mWarning: Failed to restore /etc/config/network from backup. Backup not removed.\033[0m\n" >&2
             debug_log "DEBUG" "Failed to copy network config from backup. Backup not removed."
             # Continue restoration attempt
        fi
    else
        debug_log "DEBUG" "Network configuration backup $NETWORK_BACKUP not found."
    fi

    # 2. Restore proto script (No user message on success)
    debug_log "DEBUG" "Checking for protocol script backup: $PROTO_BACKUP"
    if [ -f "$PROTO_BACKUP" ]; then
        debug_log "DEBUG" "Restoring $proto_script from $PROTO_BACKUP"
        # Ensure copy succeeds before removing backup
        if cp "$PROTO_BACKUP" "$proto_script"; then
            rm "$PROTO_BACKUP"
        else
             # Hardcoded specific warning to stderr (non-fatal)
             printf "\033[33mWarning: Failed to restore %s from backup. Backup not removed.\033[0m\n" "$proto_script" >&2
             debug_log "DEBUG" "Failed to copy protocol script from backup. Backup not removed."
             # Continue restoration attempt
        fi
    elif [ -f "$proto_script" ]; then
         # Attempt to revert MTU change if backup doesn't exist
         debug_log "DEBUG" "Protocol backup not found. Attempting to revert MTU change in $proto_script."
         if grep -q "mtu:-1460" "$proto_script"; then
              sed -i -e "s/mtu:-1460/mtu:-1280/g" "$proto_script"
              debug_log "DEBUG" "Reverted MTU change in $proto_script."
         else
              debug_log "DEBUG" "MTU in $proto_script does not appear to need reverting."
         fi
    else
         debug_log "DEBUG" "Protocol script $proto_script not found, cannot restore or revert."
    fi

    # 3. Remove ds_lite interface and firewall entry (No user message)
    debug_log "DEBUG" "Removing ds_lite interface and firewall entries via UCI."
    uci -q batch <<EOF
delete network.ds_lite
# Iterate through firewall zones to remove ds_lite from network list
local zone_count=\$(uci show firewall | grep -c "@zone\[")
local i=0
while [ \$i -lt \$zone_count ]; do
    local current_networks=\$(uci -q get firewall.@zone[\$i].network 2>/dev/null)
    local updated_networks=""
    local changed=0
    for net in \$current_networks; do
        if [ "\$net" = "ds_lite" ]; then
             changed=1
        else
             updated_networks="\$updated_networks \$net"
        fi
    done
    if [ "\$changed" -eq 1 ]; then
         # Remove trailing/leading spaces and set the updated list
         updated_networks=\$(echo \$updated_networks | sed 's/^ *//; s/ *$//')
         if [ -z "\$updated_networks" ]; then
              # If list becomes empty, delete the option
              delete firewall.@zone[\$i].network
         else
              # Otherwise, set the cleaned list
              set firewall.@zone[\$i].network="\$updated_networks"
         fi
    fi
    i=\$((i + 1))
done
commit network
commit firewall
EOF
    if [ $? -ne 0 ]; then
        # Log debug but don't fail the whole process
        debug_log "DEBUG" "UCI commands to remove ds_lite interface/firewall entries might have failed."
    fi
    debug_log "DEBUG" "UCI commands for removal executed."

    # 4. Success Message (using get_message) to stdout
    printf "\n%s\n" "$(color green "$(get_message "MSG_DSLITE_RESTORE_SUCCESS")")"

    # 5. Reboot Confirmation (using common get_message keys)
    printf "%s\n" "$(get_message MSG_REBOOT_REQUIRED)" # Use existing common key

    # Setup msg_prefix for confirm messages if color is available
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi

    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # Use existing common key
    confirm_reboot=$?
    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%s%s\n" "$msg_prefix" "$(get_message MSG_REBOOTING)" # Use existing common key
        reboot; exit 0 # Exit script after initiating reboot
    elif [ $confirm_reboot -eq 2 ]; then # Return
         # Hardcoded English message to stdout
         printf "%sReturning to menu.\n" "$msg_prefix"
         return 0 # Return success to menu handler
    else # No
        # Hardcoded English message to stdout
        printf "%sSettings restored. Please reboot the device later.\n" "$msg_prefix"
        return 0 # Return success to menu handler
    fi
}

# --- is_east_japan function (assumed loaded from common-country.sh) ---
# Function definition is not needed here as it's assumed to be loaded.

# --- Script Execution ---
# This script defines functions to be called from menu.db or other scripts.
# It does not run main logic automatically when sourced.

: # No-op to ensure the script sourcing doesn't cause unexpected output or errors
