#!/bin/sh
# POSIX-compliant script for configuring DS-Lite on OpenWrt with auto-detection
# Version: 2025.04.14-06-00 (Final minimal version, no restore confirmation)

# --- Source common functions if available ---
# Assume aios structure
AIOS_COMMON_INFO="${BASE_DIR:-/tmp/aios}/common-information.sh"
AIOS_COMMON_PKG="${BASE_DIR:-/tmp/aios}/common-package.sh" # For install_package
AIOS_COMMON_MENU="${BASE_DIR:-/tmp/aios}/common-menu.sh" # For selector
AIOS_COMMON_COUNTRY="${BASE_DIR:-/tmp/aios}/common-country.sh" # Assuming confirm is here
AIOS_COMMON_COLOR="${BASE_DIR:-/tmp/aios}/common-color.sh" # For color function

# Load necessary common scripts
load_common_script() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    if [ -f "$script_path" ]; then
        # shellcheck source=/dev/null
        . "$script_path"
        if command -v debug_log >/dev/null 2>&1; then
            debug_log "DEBUG" "Loaded common script: $script_name"
        else
            # Provide a basic English message if debug_log isn't available yet
            printf "Loaded common script: %s\n" "$script_name"
        fi
        return 0
    else
        # Error message in English as common scripts are essential
        printf "\033[31mError: Common script not found: %s\033[0m\n" "$script_name"
        return 1
    fi
}

# Load required scripts, exit if essential ones are missing
load_common_script "$AIOS_COMMON_INFO" || exit 1
load_common_script "$AIOS_COMMON_PKG" || exit 1
load_common_script "$AIOS_COMMON_MENU" || exit 1
load_common_script "$AIOS_COMMON_COLOR" || exit 1 # Load color for messages

# Check for confirm function (assuming it's in common-country or globally available)
if ! command -v confirm >/dev/null 2>&1; then
     if ! load_common_script "$AIOS_COMMON_COUNTRY"; then
          # Error message in English
          printf "\033[31mError: confirm function not found. Cannot proceed.\033[0m\n"
          exit 1
     elif ! command -v confirm >/dev/null 2>&1; then
          # Error message in English
          printf "\033[31mError: confirm function could not be loaded. Cannot proceed.\033[0m\n"
          exit 1
     fi
fi

# --- Constants ---
# AFTR Addresses
AFTR_TRANS_EAST="2404:8e00::feed:100"
AFTR_TRANS_WEST="2404:8e01::feed:100"
AFTR_XPASS="2001:f60:0:200::1:1"
AFTR_V6CONNECT="2001:c28:5:301::11"

# AS Numbers (for detection)
AS_TRANS="AS2519"
AS_XPASS="AS2527"
AS_V6CONNECT="AS4737" # Example for Asahi Net

# Backup file names
NETWORK_BACKUP="/etc/config/network.dslite.old"
PROTO_BACKUP="/lib/netifd/proto/dslite.sh.dslite.old"

# Firewall zone index (Assuming WAN is zone 1)
FW_ZONE_INDEX=1

# --- Helper Functions (apply_dslite_settings, restore_dslite_settings, is_east_japan) ---

# Apply DS-Lite settings using UCI and sed
# $1: AFTR Address
# $2: Service Name (for messages)
apply_dslite_settings() {
    local aftr_address="$1"
    local service_name="$2"
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix="" error_prefix="\033[31mError: " warning_prefix="\033[33mWarning: " success_prefix="\033[32m" reset_color="\033[0m"
    if command -v color >/dev/null 2>&1; then
        msg_prefix=$(color blue "- ") error_prefix=$(color red "Error: ") warning_prefix=$(color yellow "Warning: ") success_prefix=$(color green "")
    fi

    printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_DSLITE_APPLYING_SETTINGS service="$service_name")" "$reset_color"

    # 1. Install ds-lite package silently
    if ! install_package ds-lite silent; then
        printf "%sFailed to install ds-lite package.%s\n" "$error_prefix" "$reset_color"
        return 1
    fi

    # 2. Backup original files (No explicit message)
    cp /etc/config/network "$NETWORK_BACKUP" 2>/dev/null
    if [ -f "$proto_script" ] && [ ! -f "$PROTO_BACKUP" ]; then
        cp "$proto_script" "$PROTO_BACKUP" 2>/dev/null
    elif [ ! -f "$proto_script" ]; then
         printf "%sProtocol script %s not found.%s\n" "$warning_prefix" "$proto_script" "$reset_color"
    fi

    # 3. Configure UCI settings (No explicit message)
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
local fw_networks=\$(uci -q get firewall.@zone[$FW_ZONE_INDEX].network)
if ! echo "\$fw_networks" | grep -qw "ds_lite"; then
    add_list firewall.@zone[$FW_ZONE_INDEX].network='ds_lite'
fi
commit dhcp
commit network
commit firewall
EOF
    if [ $? -ne 0 ]; then
         printf "%sFailed to apply UCI settings.%s\n" "$error_prefix" "$reset_color"
         return 1
    fi

    # 4. Modify proto script MTU (No explicit message)
    if [ -f "$proto_script" ]; then
        if grep -q "mtu:-1280" "$proto_script"; then
            sed -i -e "s/mtu:-1280/mtu:-1460/g" "$proto_script"
            if [ $? -ne 0 ]; then printf "%sFailed to modify protocol script.%s\n" "$error_prefix" "$reset_color"; fi
        # else: No message if already adjusted or pattern not found
        fi
    fi

    printf "%s%s%s\n" "$success_prefix" "$(get_message MSG_DSLITE_APPLY_SUCCESS service="$service_name")" "$reset_color"
    printf "%s\n" "$(get_message MSG_REBOOT_REQUIRED)" # Use existing key

    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # Use existing key
    confirm_reboot=$?
    if [ $confirm_reboot -eq 0 ]; then
        printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_REBOOTING)" "$reset_color" # Use existing key
        reboot; exit 0
    elif [ $confirm_reboot -eq 2 ]; then
         printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_DSLITE_DONE_MENU)" "$reset_color"
         return 0
    else
        printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_DSLITE_DONE_REBOOT_LATER)" "$reset_color"
        return 0
    fi
}

# Restore original settings (No confirmation before execution)
restore_dslite_settings() {
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix="" error_prefix="\033[31mError: " warning_prefix="\033[33mWarning: " success_prefix="\033[32m" reset_color="\033[0m"
    if command -v color >/dev/null 2>&1; then
        msg_prefix=$(color blue "- ") error_prefix=$(color red "Error: ") warning_prefix=$(color yellow "Warning: ") success_prefix=$(color green "")
    fi

    printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_DSLITE_RESTORING_SETTINGS)" "$reset_color"

    # 1. Restore network config (No message on success)
    if [ -f "$NETWORK_BACKUP" ]; then
        cp "$NETWORK_BACKUP" /etc/config/network; rm "$NETWORK_BACKUP"
    else
        printf "%sNetwork configuration backup not found.%s\n" "$warning_prefix" "$reset_color"
    fi

    # 2. Restore proto script (No message on success)
    if [ -f "$PROTO_BACKUP" ]; then
        cp "$PROTO_BACKUP" "$proto_script"; rm "$PROTO_BACKUP"
    elif [ -f "$proto_script" ]; then
         if grep -q "mtu:-1460" "$proto_script"; then
              sed -i -e "s/mtu:-1460/mtu:-1280/g" "$proto_script"
              # No message for estimated revert
         fi
    fi

    # 3. Remove ds_lite interface and firewall entry (No explicit message)
    uci -q batch <<EOF
delete network.ds_lite
local zone_count=\$(uci show firewall | grep -c "@zone\[")
local i=0
while [ \$i -lt \$zone_count ]; do
    local networks=\$(uci -q get firewall.@zone[\$i].network)
    if echo "\$networks" | grep -qw "ds_lite"; then
         del_list firewall.@zone[\$i].network='ds_lite'
    fi
    i=\$((i + 1))
done
commit network
commit firewall
EOF

    printf "%s%s%s\n" "$success_prefix" "$(get_message MSG_DSLITE_RESTORE_SUCCESS)" "$reset_color"
    printf "%s\n" "$(get_message MSG_REBOOT_REQUIRED)" # Use existing key

    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # Use existing key
    confirm_reboot=$?
    if [ $confirm_reboot -eq 0 ]; then
        printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_REBOOTING)" "$reset_color" # Use existing key
        reboot; exit 0
    elif [ $confirm_reboot -eq 2 ]; then
         printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_DSLITE_DONE_MENU)" "$reset_color"
         return 0
    else
        printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_DSLITE_DONE_REBOOT_LATER)" "$reset_color"
        return 0
    fi
}

# $1: Region Name or Code
# Returns 0 if East Japan, 1 if West Japan, 2 if Unknown
is_east_japan() {
    local region_input="$1"
    local east_prefs="Hokkaido Aomori Iwate Miyagi Akita Yamagata Fukushima Ibaraki Tochigi Gunma Saitama Chiba Tokyo Kanagawa Niigata Yamanashi Nagano Shizuoka"
    local west_prefs="Toyama Ishikawa Fukui Gifu Aichi Mie Shiga Kyoto Osaka Hyogo Nara Wakayama Tottori Shimane Okayama Hiroshima Yamaguchi Tokushima Kagawa Ehime Kochi Fukuoka Saga Nagasaki Kumamoto Oita Miyazaki Kagoshima Okinawa"
    local east_codes="JP-01 JP-02 JP-03 JP-04 JP-05 JP-06 JP-07 JP-08 JP-09 JP-10 JP-11 JP-12 JP-13 JP-14 JP-15 JP-19 JP-20 JP-22"
    local west_codes="JP-16 JP-17 JP-18 JP-21 JP-23 JP-24 JP-25 JP-26 JP-27 JP-28 JP-29 JP-30 JP-31 JP-32 JP-33 JP-34 JP-35 JP-36 JP-37 JP-38 JP-39 JP-40 JP-41 JP-42 JP-43 JP-44 JP-45 JP-46 JP-47"
    for pref in $east_prefs $east_codes; do if [ "$region_input" = "$pref" ]; then return 0; fi; done
    for pref in $west_prefs $west_codes; do if [ "$region_input" = "$pref" ]; then return 1; fi; done
    return 2
}

# --- Auto Detection Provider Function (Internal) ---
# Outputs: "Provider Name|AFTR Address|Region Text" on success, empty on failure
_detect_provider_internal() {
    local isp_as="" region="" detected_provider="" detected_aftr="" detected_region_text=""
    # Note: error_prefix and reset_color variables are removed as color function handles reset.

    local cache_as_file="${CACHE_DIR}/ip_as.tmp"
    local cache_region_code_file="${CACHE_DIR}/ip_region_code.tmp"
    local cache_region_name_file="${CACHE_DIR}/ip_region_name.tmp"

    if [ -f "$cache_as_file" ]; then isp_as=$(cat "$cache_as_file"); fi
    if [ -f "$cache_region_code_file" ]; then region=$(cat "$cache_region_code_file"); fi
    if [ -z "$region" ] && [ -f "$cache_region_name_file" ]; then region=$(cat "$cache_region_name_file"); fi

    if [ -z "$isp_as" ]; then
        # Use get_message for error reporting
        printf "%s\n" "$(color red "$(get_message MSG_DSLITE_ERR_NO_AS cache_file="$cache_as_file")")" >&2
        return 1
    fi

    case "$isp_as" in
        "$AS_TRANS")
            if [ -z "$region" ]; then
                 # Use get_message for error reporting
                 printf "%s\n" "$(color red "$(get_message MSG_DSLITE_ERR_NO_REGION)")" >&2
                 return 1
            fi
            is_east_japan "$region"
            local region_result=$?
            if [ $region_result -eq 0 ]; then
                detected_provider="Transix (East Japan)"; detected_aftr="$AFTR_TRANS_EAST"; detected_region_text="East Japan"
            elif [ $region_result -eq 1 ]; then
                detected_provider="Transix (West Japan)"; detected_aftr="$AFTR_TRANS_WEST"; detected_region_text="West Japan"
            else
                # Use get_message for error reporting
                printf "%s\n" "$(color red "$(get_message MSG_DSLITE_ERR_REGION_UNKNOWN region="$region")")" >&2
                return 1
            fi
            ;;
        "$AS_XPASS")
            detected_provider="Cross Pass"; detected_aftr="$AFTR_XPASS"
            ;;
        "$AS_V6CONNECT")
            detected_provider="v6 connect"; detected_aftr="$AFTR_V6CONNECT"
            ;;
        *)
            # Use get_message for error reporting
            printf "%s\n" "$(color red "$(get_message MSG_DSLITE_ERR_PROVIDER_UNKNOWN as_number="$isp_as")")" >&2
            return 1
            ;;
    esac

    echo "${detected_provider}|${detected_aftr}|${detected_region_text}"
    return 0
}

# --- Auto Detect and Apply Function (Called from menu.db) ---
auto_detect_and_apply() {
    local msg_prefix="" error_prefix="\033[31mError: " reset_color="\033[0m" # Keep for fallback if color not available
    if command -v color >/dev/null 2>&1; then
        msg_prefix=$(color blue "- ") error_prefix=$(color red "Error: ")
        # Note: reset_color variable is removed or unused when color function is available
    fi

    # 1. Cache check removed - Assuming cache exists or _detect_provider_internal handles it.

    # 2. Perform internal detection using cached info
    local detection_result
    detection_result=$(_detect_provider_internal) # Specific errors (red) printed to stderr within this function
    local detection_status=$?

    if [ $detection_status -ne 0 ]; then
        # Warning message for detection failure (using new key)
        if command -v get_message >/dev/null 2>&1; then
            printf "%s\n" "$(color yellow "$(get_message MSG_DSLITE_AUTO_DETECT_FAILED)")"
        else
            # Fallback if get_message is not available (use yellow color code directly)
            printf "\033[33mProvider detection failed. Returning to DS-Lite menu.\033[0m\n"
        fi
        # Log the failure for debugging
        debug_log "WARN" "DS-Lite auto-detection failed (exit code: $detection_status). Check previous specific errors."
        return 1
    fi

    # Parse detection result
    local detected_provider=$(echo "$detection_result" | cut -d'|' -f1)
    local detected_aftr=$(echo "$detection_result" | cut -d'|' -f2)
    local detected_region_text=$(echo "$detection_result" | cut -d'|' -f3)

    # 3. Display result and confirm with user (Revised format)
    printf "\n" # Add a blank line before the results

    # Get labels using get_message (assuming color function is available)
    local label_provider=$(get_message MSG_DSLITE_AUTO_PROVIDER_LABEL)
    local label_region=$(get_message MSG_DSLITE_AUTO_REGION_LABEL)
    local label_aftr=$(get_message MSG_DSLITE_AUTO_AFTR_LABEL)

    # Display results with blue labels
    printf "%s: %s\n" "$(color blue "$label_provider")" "$detected_provider"
    if [ -n "$detected_region_text" ]; then
        printf "%s: %s\n" "$(color blue "$label_region")" "$detected_region_text"
    fi
    printf "%s: %s\n" "$(color blue "$label_aftr")" "$detected_aftr"

    local confirm_auto=1
    confirm "MSG_CONFIRM_AUTO_SETTINGS" # Use specific key (without '?')
    confirm_auto=$?

    if [ $confirm_auto -eq 0 ]; then # Yes
        apply_dslite_settings "$detected_aftr" "$detected_provider"
        return $?
    else # No or Return
         # Warning message for user rejection (using existing key)
         if command -v get_message >/dev/null 2>&1; then
            printf "%s\n" "$(color yellow "$(get_message MSG_DSLITE_AUTO_CONFIG_REJECTED)")"
         else
            # Fallback if get_message is not available (use yellow color code directly)
            printf "\033[33mAuto-configuration cancelled by user. Returning to DS-Lite menu.\033[0m\n"
         fi
         # Log the user cancellation
         debug_log "INFO" "DS-Lite auto-configuration rejected by user."
        return 1
    fi
}

# --- Script Execution ---
# This script defines functions to be called from menu.db.
# It does not run main logic automatically when sourced.
# The entry point is triggered by the download command in menu.db,
# which then calls the specified function (e.g., auto_detect_and_apply).

: # No-op to ensure the script sourcing doesn't cause unexpected output or errors
