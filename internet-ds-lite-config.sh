#!/bin/sh

SCRIPT_VERSION="2025.04.21-08-20" # Updated version reflecting message key reduction

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

# --- Source common functions if available ---
# Assume aios structure
BASE_DIR="${BASE_DIR:-/tmp/aios}" # Ensure BASE_DIR is set
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}" # Ensure CACHE_DIR is set
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}" # Ensure LOG_DIR is set
AIOS_COMMON_INFO="${BASE_DIR}/common-information.sh"
AIOS_COMMON_PKG="${BASE_DIR}/common-package.sh" # For install_package
AIOS_COMMON_MENU="${BASE_DIR}/common-menu.sh" # For selector (if needed directly)
AIOS_COMMON_COUNTRY="${BASE_DIR}/common-country.sh" # For confirm() and is_east_japan()
AIOS_COMMON_COLOR="${BASE_DIR}/common-color.sh" # For color()

# --- Debug Logging Function (should be loaded by aios) ---
# Fallback logger
if ! command -v debug_log >/dev/null 2>&1; then
    debug_log() {
        local level="$1"
        local message="$2"
        # Per user request, default to DEBUG level for non-essential logs
        [ "$level" = "INFO" ] && level="DEBUG"
        echo "${level}: ${message}" >&2
    }
    debug_log "WARN" "debug_log function not found initially, using basic fallback."
fi

# --- Load necessary common scripts ---
load_common_script() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    if [ -f "$script_path" ]; then
        # shellcheck source=/dev/null
        . "$script_path"
        debug_log "DEBUG" "Loaded common script: $script_name"
        return 0
    else
        # Error message in English as common scripts are essential
        printf "\033[31mError: Common script not found: %s\033[0m\n" "$script_name" >&2
        return 1
    fi
}

# Load required scripts, exit if essential ones are missing
load_common_script "$AIOS_COMMON_INFO" || exit 1
load_common_script "$AIOS_COMMON_PKG" || exit 1
# load_common_script "$AIOS_COMMON_MENU" || exit 1 # Not directly needed by functions here
load_common_script "$AIOS_COMMON_COLOR" || exit 1 # Load color for messages

# Check for confirm and is_east_japan functions (load common-country if needed)
if ! command -v confirm >/dev/null 2>&1 || ! command -v is_east_japan >/dev/null 2>&1; then
     debug_log "WARN" "'confirm' or 'is_east_japan' function not found. Attempting to load from common-country.sh"
     if ! load_common_script "$AIOS_COMMON_COUNTRY"; then
          printf "\033[31mError: common-country.sh not found or failed to load. Cannot proceed.\033[0m\n" >&2
          exit 1
     elif ! command -v confirm >/dev/null 2>&1 || ! command -v is_east_japan >/dev/null 2>&1; then
          printf "\033[31mError: Required functions ('confirm', 'is_east_japan') could not be loaded. Cannot proceed.\033[0m\n" >&2
          exit 1
     fi
fi
# Check get_message
if ! command -v get_message >/dev/null 2>&1; then
     debug_log "ERROR" "Core 'get_message' function from aios not found. User messages will be limited."
     # Basic fallback for get_message
     get_message() { echo "$1"; }
fi


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
# Internal database for DS-Lite providers.
# Arguments: $1: AS Number (numeric, without "AS" prefix)
# Output: Space-separated string: AS_NUM INTERNAL_KEY "DISPLAY_NAME" AFTR_ADDRESS
#         (e.g., 2519 transix "transix" "USE_REGION") - USE_REGION indicates region check needed
# Returns: 0 if found, 1 if not found.
get_dslite_provider_data_by_as() {
    local search_asn="$1"
    local result=""

    # --- DS-Lite Provider Database (Here Document) ---
    # Format: AS_NUM INTERNAL_KEY "DISPLAY_NAME" AFTR_ADDRESS
    # For Transix, AFTR_ADDRESS is "USE_REGION" to trigger regional check. DISPLAY_NAME must be quoted.
    local provider_db=$(cat <<-'EOF'
2519 transix "transix" "USE_REGION"
2527 cross "Cross Pass" "2001:f60:0:200::1:1"
4737 v6connect "v6 Connect" "2001:c28:5:301::11"
EOF
)
    # --- End of Database ---

    # Search for the AS number in the database
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
# Outputs: "Provider Display Name|AFTR Address|Region Text" on success, empty on failure
# Errors are printed to stderr directly (hardcoded English).
detect_provider_internal() {
    local isp_as="" region=""
    local provider_data=""
    local internal_key=""
    local display_name=""
    local aftr_address=""
    local region_text=""

    local cache_as_file="${CACHE_DIR}/ip_as.tmp"
    local cache_region_code_file="${CACHE_DIR}/ip_region_code.tmp"
    local cache_region_name_file="${CACHE_DIR}/ip_region_name.tmp"

    # Read AS number from cache
    if [ -f "$cache_as_file" ]; then
        isp_as=$(cat "$cache_as_file" | sed 's/^AS//i') # Remove AS prefix
    fi
    if [ -z "$isp_as" ]; then
        # Hardcoded error message
        printf "\033[31mError: AS Number cache file not found or empty: %s\033[0m\n" "$cache_as_file" >&2
        return 1
    fi
    debug_log "DEBUG" "detect_provider_internal: Using AS Number $isp_as"

    # Get provider data
    provider_data=$(get_dslite_provider_data_by_as "$isp_as")
    if [ $? -ne 0 ] || [ -z "$provider_data" ]; then
        # Hardcoded error message
        printf "\033[31mError: Could not find DS-Lite provider data for AS %s.\033[0m\n" "$isp_as" >&2
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
        # Read region from cache
        if [ -f "$cache_region_code_file" ]; then region=$(cat "$cache_region_code_file"); fi
        if [ -z "$region" ] && [ -f "$cache_region_name_file" ]; then region=$(cat "$cache_region_name_file"); fi

        if [ -z "$region" ]; then
            # Hardcoded error message
            printf "\033[31mError: Region information not found in cache for Transix detection.\033[0m\n" >&2
            return 1
        fi
        debug_log "DEBUG" "detect_provider_internal: Using region $region for Transix."

        # is_east_japan function is assumed to be loaded from common-country.sh
        is_east_japan "$region"
        local region_result=$?
        if [ $region_result -eq 0 ]; then
            display_name="Transix (East Japan)" # Update display name
            aftr_address="$AFTR_TRANS_EAST"
            region_text="East Japan"
        elif [ $region_result -eq 1 ]; then
            display_name="Transix (West Japan)" # Update display name
            aftr_address="$AFTR_TRANS_WEST"
            region_text="West Japan"
        else
            # Hardcoded error message
            printf "\033[31mError: Could not determine region (East/West) for Transix: %s\033[0m\n" "$region" >&2
            return 1
        fi
        debug_log "DEBUG" "detect_provider_internal: Transix region resolved - Name=$display_name, AFTR=$aftr_address, Region=$region_text"
    fi

    # Output in the unified format
    echo "${display_name}|${aftr_address}|${region_text}"
    return 0
}

# --- Auto Detect and Apply DS-Lite Settings ---
# Called by menu.db or internet-auto-config.sh
# Uses get_message for result and failure summary, hardcoded English for confirmation.
auto_detect_and_apply() {
    debug_log "DEBUG" "Starting DS-Lite auto-detection and application process." # Changed INFO to DEBUG

    # Perform internal detection
    local detection_result
    detection_result=$(detect_provider_internal)
    local detection_status=$?

    if [ $detection_status -ne 0 ]; then
        # Specific error already printed by detect_provider_internal (hardcoded English)
        debug_log "ERROR" "DS-Lite auto-detection failed (detailed error above)."
        # Use get_message for generic failure summary
        printf "\n%s\n" "$(color red "$(get_message "MSG_DSLITE_AUTO_DETECT_FAILED")")" >&2
        return 1
    fi

    # Parse detection result
    local detected_provider=$(echo "$detection_result" | cut -d'|' -f1)
    local detected_aftr=$(echo "$detection_result" | cut -d'|' -f2)
    # local detected_region_text=$(echo "$detection_result" | cut -d'|' -f3) # Region text not used

    # Display result using get_message
    # Placeholders: sp (Service Provider), tp (Type)
    printf "\n%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$detected_provider" tp="DS-Lite")")"

    # Confirm with the user (hardcoded English question)
    local confirm_auto=1
    # confirm function expects message key, but we use hardcoded string here
    # Assuming confirm can handle a direct string if the key lookup fails or is modified.
    # If confirm strictly requires a key, this needs adjustment in common-menu.sh or here.
    confirm "Apply these settings? {ynr}" # Hardcoded English
    confirm_auto=$?

    if [ $confirm_auto -eq 0 ]; then # Yes
        debug_log "DEBUG" "User confirmed applying DS-Lite settings for $detected_provider."
        printf "\n" # Newline before applying settings
        # Pass AFTR and Provider Name (or key) to apply_dslite_settings
        apply_dslite_settings "$detected_aftr" "$detected_provider"
        return $? # Return the status of apply_dslite_settings
    else # No or Return
         debug_log "DEBUG" "User declined to apply DS-Lite settings." # Changed INFO to DEBUG
         # No cancellation message to user, return error to menu
        return 1
    fi
}

# Apply DS-Lite settings using UCI and sed
# $1: AFTR Address
# $2: Service Name/Key (Internal use, not displayed to user)
# Uses get_message for success and reboot messages, hardcoded English for errors.
apply_dslite_settings() {
    local aftr_address="$1"
    local service_key="$2" # Use key for potential internal logic if needed
    local proto_script="/lib/netifd/proto/dslite.sh"
    # Error/Warning prefixes for hardcoded messages
    local error_prefix="\033[31mError: "
    local warning_prefix="\033[33mWarning: "
    local reset_color="\033[0m"
    local msg_prefix="" # For reboot messages

    debug_log "DEBUG" "Applying DS-Lite settings for AFTR: $aftr_address (Key: $service_key)" # Changed INFO to DEBUG
    printf "%s\n" "$(color blue "Applying DS-Lite settings...")" # Hardcoded English

    # 1. Install ds-lite package silently
    # Assuming install_package handles its own errors/messages if not silent
    if ! install_package ds-lite silent; then
        # Hardcoded error message
        printf "%sFailed to install ds-lite package.%s\n" "$error_prefix" "$reset_color" >&2
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
         debug_log "WARN" "Protocol script $proto_script not found, cannot back up."
         # Continue without backup, might be ok if ds-lite package installed it
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
         # Hardcoded error message
         printf "%sFailed to apply UCI settings.%s\n" "$error_prefix" "$reset_color" >&2
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
                # Log warning but don't fail the whole process
                debug_log "WARN" "Failed to modify protocol script MTU, but continuing."
            fi
        else
            debug_log "DEBUG" "MTU in $proto_script does not need modification or was already changed."
        fi
    else
        debug_log "WARN" "Protocol script $proto_script not found after package install. Cannot modify MTU."
    fi

    # 5. Success Message (using get_message)
    printf "\n%s\n" "$(color green "$(get_message "MSG_DSLITE_APPLY_SUCCESS")")"

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
         # Hardcoded English message
         printf "%sReturning to menu.\n" "$msg_prefix"
         return 0 # Return success to menu
    else # No
        # Hardcoded English message
        printf "%sSettings applied. Please reboot the device later.\n" "$msg_prefix"
        return 0 # Return success to menu
    fi
}

# Restore original settings
# Uses get_message for success and reboot messages, hardcoded English for errors/warnings.
restore_dslite_settings() {
    local proto_script="/lib/netifd/proto/dslite.sh"
    # Error/Warning prefixes for hardcoded messages
    local error_prefix="\033[31mError: "
    local warning_prefix="\033[33mWarning: "
    local reset_color="\033[0m"
    local msg_prefix="" # For reboot messages

    debug_log "DEBUG" "Restoring settings before DS-Lite configuration." # Changed INFO to DEBUG
    printf "%s\n" "$(color blue "Restoring previous DS-Lite settings...")" # Hardcoded English

    # 1. Restore network config (No user message on success)
    debug_log "DEBUG" "Checking for network backup: $NETWORK_BACKUP"
    if [ -f "$NETWORK_BACKUP" ]; then
        debug_log "DEBUG" "Restoring /etc/config/network from $NETWORK_BACKUP"
        # Ensure copy succeeds before removing backup
        if cp "$NETWORK_BACKUP" /etc/config/network; then
            rm "$NETWORK_BACKUP"
        else
             # Hardcoded warning message
             printf "%sFailed to copy network config from backup. Backup not removed.%s\n" "$warning_prefix" "$reset_color" >&2
             debug_log "ERROR" "Failed to copy network config from backup. Backup not removed."
             # Continue restoration attempt
        fi
    else
        debug_log "WARN" "Network configuration backup $NETWORK_BACKUP not found."
    fi

    # 2. Restore proto script (No user message on success)
    debug_log "DEBUG" "Checking for protocol script backup: $PROTO_BACKUP"
    if [ -f "$PROTO_BACKUP" ]; then
        debug_log "DEBUG" "Restoring $proto_script from $PROTO_BACKUP"
        # Ensure copy succeeds before removing backup
        if cp "$PROTO_BACKUP" "$proto_script"; then
            rm "$PROTO_BACKUP"
        else
             # Hardcoded warning message
             printf "%sFailed to copy protocol script from backup. Backup not removed.%s\n" "$warning_prefix" "$reset_color" >&2
             debug_log "ERROR" "Failed to copy protocol script from backup. Backup not removed."
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
         debug_log "WARN" "Protocol script $proto_script not found, cannot restore or revert."
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
        # Log warning but don't fail the whole process
        debug_log "WARN" "UCI commands to remove ds_lite interface/firewall entries might have failed."
    fi
    debug_log "DEBUG" "UCI commands for removal executed."

    # 4. Success Message (using get_message)
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
         # Hardcoded English message
         printf "%sReturning to menu.\n" "$msg_prefix"
         return 0 # Return success to menu
    else # No
        # Hardcoded English message
        printf "%sSettings restored. Please reboot the device later.\n" "$msg_prefix"
        return 0 # Return success to menu
    fi
}

# --- is_east_japan function (assumed loaded from common-country.sh) ---
# Placeholder if common-country.sh loading fails (should not happen)
if ! command -v is_east_japan >/dev/null 2>&1; then
    is_east_japan() { return 2; } # Always return Unknown
    debug_log "ERROR" "is_east_japan function was not loaded. Regional detection will fail."
fi

# --- Script Execution ---
# This script defines functions to be called from menu.db or other scripts.
# It does not run main logic automatically when sourced.

: # No-op to ensure the script sourcing doesn't cause unexpected output or errors
