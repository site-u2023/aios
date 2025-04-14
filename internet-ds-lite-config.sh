#!/bin/sh
# POSIX-compliant script for configuring DS-Lite on OpenWrt with auto-detection
# Version: 2025.04.14-03-00 (Final version based on discussion)

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

    # Use color function if available for messages
    local msg_prefix=""
    local error_prefix="\033[31mError: " # Red color for errors
    local warning_prefix="\033[33mWarning: " # Yellow for warnings
    local success_prefix="\033[32m" # Green for success
    local reset_color="\033[0m"

    # Check if color function exists before using it
    if command -v color >/dev/null 2>&1; then
        msg_prefix=$(color blue "- ") # Example: Blue prefix for info
        error_prefix=$(color red "Error: ")
        warning_prefix=$(color yellow "Warning: ")
        success_prefix=$(color green "") # Green text for success message
    fi

    # Messages in English
    printf "%sApplying settings for %s...%s\n" "$msg_prefix" "$service_name" "$reset_color"

    # 1. Install ds-lite package silently
    printf "%sInstalling/Verifying ds-lite package...%s\n" "$msg_prefix" "$reset_color"
    if ! install_package ds-lite silent; then
        printf "%sFailed to install ds-lite package.%s\n" "$error_prefix" "$reset_color"
        return 1
    else
         printf "%sds-lite package installation/verification complete.%s\n" "$msg_prefix" "$reset_color"
    fi

    # 2. Backup original files
    printf "%sBacking up configuration files...%s\n" "$msg_prefix" "$reset_color"
    cp /etc/config/network "$NETWORK_BACKUP" 2>/dev/null
    if [ -f "$proto_script" ] && [ ! -f "$PROTO_BACKUP" ]; then
        cp "$proto_script" "$PROTO_BACKUP" 2>/dev/null
    elif [ ! -f "$proto_script" ]; then
         printf "%sProtocol script %s not found.%s\n" "$warning_prefix" "$proto_script" "$reset_color"
    fi

    # 3. Configure UCI settings
    printf "%sConfiguring network settings...%s\n" "$msg_prefix" "$reset_color"
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
delete network.ds_lite # Delete existing section first to avoid duplicates
set network.ds_lite=interface
set network.ds_lite.proto='dslite'
set network.ds_lite.peeraddr='$aftr_address'
set network.ds_lite.mtu='1460'
# Check if ds_lite is already in the zone before adding
local fw_networks=\$(uci -q get firewall.@zone[$FW_ZONE_INDEX].network)
if ! echo "\$fw_networks" | grep -qw "ds_lite"; then # Use -w for whole word match
    add_list firewall.@zone[$FW_ZONE_INDEX].network='ds_lite'
fi
commit dhcp
commit network
commit firewall
EOF
    if [ $? -ne 0 ]; then
         printf "%sFailed to apply UCI settings.%s\n" "$error_prefix" "$reset_color"
         # Attempt to restore backups if UCI fails? For now, just error out.
         return 1
    fi

    # 4. Modify proto script MTU
    if [ -f "$proto_script" ]; then
        printf "%sAdjusting protocol script MTU...%s\n" "$msg_prefix" "$reset_color"
        if grep -q "mtu:-1280" "$proto_script"; then
            sed -i -e "s/mtu:-1280/mtu:-1460/g" "$proto_script"
            if [ $? -ne 0 ]; then
                 printf "%sFailed to modify protocol script.%s\n" "$error_prefix" "$reset_color"
            fi
        else
            printf "%sProtocol script MTU already adjusted or pattern not found.%s\n" "$msg_prefix" "$reset_color"
        fi
    fi

    printf "%sSettings for %s applied successfully.%s\n" "$success_prefix" "$service_name" "$reset_color"
    printf "A reboot is required to activate the settings.\n" # Plain English message

    # Use aios confirm function with message key
    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # Assumes key exists in message DB
    confirm_reboot=$?

    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%sRebooting now...%s\n" "$msg_prefix" "$reset_color"
        reboot
        exit 0 # Exit after initiating reboot
    elif [ $confirm_reboot -eq 2 ]; then # Return
         printf "%sSettings saved. Returning to menu.%s\n" "$msg_prefix" "$reset_color"
         return 0 # Return to the calling menu/function (likely the selector)
    else # No
        printf "%sSettings saved, but a reboot is needed to take effect.%s\n" "$msg_prefix" "$reset_color"
        return 0
    fi
}

# Restore original settings (Renamed for menu.db consistency)
restore_dslite_settings() {
    local proto_script="/lib/netifd/proto/dslite.sh"
    local msg_prefix=""
    local error_prefix="\033[31mError: "
    local warning_prefix="\033[33mWarning: "
    local success_prefix="\033[32m"
    local reset_color="\033[0m"

    if command -v color >/dev/null 2>&1; then
        msg_prefix=$(color blue "- ")
        error_prefix=$(color red "Error: ")
        warning_prefix=$(color yellow "Warning: ")
        success_prefix=$(color green "")
    fi

    # Messages in English
    printf "%sRestoring previous settings...%s\n" "$msg_prefix" "$reset_color"

    # 1. Restore network config
    if [ -f "$NETWORK_BACKUP" ]; then
        cp "$NETWORK_BACKUP" /etc/config/network
        rm "$NETWORK_BACKUP"
        printf "%sNetwork configuration restored.%s\n" "$msg_prefix" "$reset_color"
    else
        printf "%sNetwork configuration backup not found.%s\n" "$warning_prefix" "$reset_color"
    fi

    # 2. Restore proto script
    if [ -f "$PROTO_BACKUP" ]; then
        cp "$PROTO_BACKUP" "$proto_script"
        rm "$PROTO_BACKUP"
        printf "%sProtocol script restored.%s\n" "$msg_prefix" "$reset_color"
    elif [ -f "$proto_script" ]; then
         # Attempt to revert MTU change if backup is missing
         if grep -q "mtu:-1460" "$proto_script"; then
              sed -i -e "s/mtu:-1460/mtu:-1280/g" "$proto_script"
              printf "%sReverted protocol script MTU to default (estimated).%s\n" "$msg_prefix" "$reset_color"
         fi
    fi

    # 3. Remove ds_lite interface and firewall entry
    printf "%sRemoving DS-Lite interface and firewall rules...%s\n" "$msg_prefix" "$reset_color"
    uci -q batch <<EOF
delete network.ds_lite
# Remove ds_lite from firewall zone (safer loop)
local zone_count=\$(uci show firewall | grep -c "@zone\[")
local i=0
while [ \$i -lt \$zone_count ]; do
    local networks=\$(uci -q get firewall.@zone[\$i].network)
    if echo "\$networks" | grep -qw "ds_lite"; then # Use -w for whole word match
         del_list firewall.@zone[\$i].network='ds_lite'
         printf "%sRemoved ds_lite from firewall zone %s.%s\n" "$msg_prefix" "\$i" "$reset_color"
    fi
    i=\$((i + 1))
done
commit network
commit firewall
EOF

    printf "%sSettings restored successfully.%s\n" "$success_prefix" "$reset_color"
    printf "A reboot is required for changes to take effect.\n" # English message

    # Use aios confirm function with message key
    local confirm_reboot=1
    confirm "MSG_CONFIRM_REBOOT" # Assumes key exists
    confirm_reboot=$?

    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%sRebooting now...%s\n" "$msg_prefix" "$reset_color"
        reboot
        exit 0 # Exit after initiating reboot
    elif [ $confirm_reboot -eq 2 ]; then # Return
         printf "%sSettings restored. Returning to menu.%s\n" "$msg_prefix" "$reset_color"
         return 0 # Return to the calling menu/function
    else # No
        printf "%sSettings restored, but a reboot is needed to take effect.%s\n" "$msg_prefix" "$reset_color"
        return 0
    fi
}

# $1: Region Name or Code
# Returns 0 if East Japan, 1 if West Japan, 2 if Unknown
is_east_japan() {
    local region_input="$1"
    # Lists remain the same
    local east_prefs="Hokkaido Aomori Iwate Miyagi Akita Yamagata Fukushima Ibaraki Tochigi Gunma Saitama Chiba Tokyo Kanagawa Niigata Yamanashi Nagano Shizuoka"
    local west_prefs="Toyama Ishikawa Fukui Gifu Aichi Mie Shiga Kyoto Osaka Hyogo Nara Wakayama Tottori Shimane Okayama Hiroshima Yamaguchi Tokushima Kagawa Ehime Kochi Fukuoka Saga Nagasaki Kumamoto Oita Miyazaki Kagoshima Okinawa"
    local east_codes="JP-01 JP-02 JP-03 JP-04 JP-05 JP-06 JP-07 JP-08 JP-09 JP-10 JP-11 JP-12 JP-13 JP-14 JP-15 JP-19 JP-20 JP-22"
    local west_codes="JP-16 JP-17 JP-18 JP-21 JP-23 JP-24 JP-25 JP-26 JP-27 JP-28 JP-29 JP-30 JP-31 JP-32 JP-33 JP-34 JP-35 JP-36 JP-37 JP-38 JP-39 JP-40 JP-41 JP-42 JP-43 JP-44 JP-45 JP-46 JP-47"

    for pref in $east_prefs $east_codes; do
        if [ "$region_input" = "$pref" ]; then return 0; fi
    done
    for pref in $west_prefs $west_codes; do
        if [ "$region_input" = "$pref" ]; then return 1; fi
    done
    return 2
}

# --- Auto Detection Provider Function (Internal) ---
# Outputs: "Provider Name|AFTR Address|Region Text" on success, empty on failure
_detect_provider_internal() {
    local isp_as="" region="" detected_provider="" detected_aftr="" detected_region_text=""
    local error_prefix="\033[31mError: " reset_color="\033[0m"
    if command -v color >/dev/null 2>&1; then error_prefix=$(color red "Error: "); fi

    # Read directly from cache files
    local cache_as_file="${CACHE_DIR}/ip_as.tmp"
    local cache_region_code_file="${CACHE_DIR}/ip_region_code.tmp"
    local cache_region_name_file="${CACHE_DIR}/ip_region_name.tmp"

    if [ -f "$cache_as_file" ]; then isp_as=$(cat "$cache_as_file"); fi
    if [ -f "$cache_region_code_file" ]; then region=$(cat "$cache_region_code_file"); fi
    # Fallback to region name if code is not available
    if [ -z "$region" ] && [ -f "$cache_region_name_file" ]; then region=$(cat "$cache_region_name_file"); fi

    if [ -z "$isp_as" ]; then
        # Error message in English, sent to stderr
        printf "%sISP AS information cache file not found (%s). Cannot auto-detect.%s\n" "$error_prefix" "$cache_as_file" "$reset_color" >&2
        return 1
    fi

    # Detection logic remains the same
    case "$isp_as" in
        "$AS_TRANS")
            if [ -z "$region" ]; then
                 printf "%sTransix detected, but region information is missing. Cannot determine East/West.%s\n" "$error_prefix" "$reset_color" >&2
                 return 1
            fi
            is_east_japan "$region"
            local region_result=$?
            if [ $region_result -eq 0 ]; then
                detected_provider="Transix (East Japan)"; detected_aftr="$AFTR_TRANS_EAST"; detected_region_text="East Japan"
            elif [ $region_result -eq 1 ]; then
                detected_provider="Transix (West Japan)"; detected_aftr="$AFTR_TRANS_WEST"; detected_region_text="West Japan"
            else
                printf "%sTransix detected, but could not determine East/West from region '%s'.%s\n" "$error_prefix" "$region" "$reset_color" >&2
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
            printf "%sNo known DS-Lite provider matches AS number '%s'.%s\n" "$error_prefix" "$isp_as" "$reset_color" >&2
            return 1
            ;;
    esac

    # Output result separated by pipe for easy parsing
    echo "${detected_provider}|${detected_aftr}|${detected_region_text}"
    return 0
}

# --- Auto Detect and Apply Function (Called from menu.db) ---
auto_detect_and_apply() {
    local msg_prefix="" error_prefix="\033[31mError: " reset_color="\033[0m"
    if command -v color >/dev/null 2>&1; then
        msg_prefix=$(color blue "- ") error_prefix=$(color red "Error: ")
    fi

    # 1. Check for cached location information (No process_location_info call)
    local cache_as_file="${CACHE_DIR}/ip_as.tmp"
    local cache_region_code_file="${CACHE_DIR}/ip_region_code.tmp"
    local cache_region_name_file="${CACHE_DIR}/ip_region_name.tmp"

    if [ ! -f "$cache_as_file" ]; then
         if [ ! -f "$cache_region_code_file" ] && [ ! -f "$cache_region_name_file" ]; then
              printf "%sLocation information cache files not found. Please run initial setup or check network.%s\n" "$error_prefix" "$reset_color"
         else
              printf "%sISP AS information cache file not found (%s). Cannot auto-detect.%s\n" "$error_prefix" "$cache_as_file" "$reset_color"
         fi
         # Display message and return to the main DS-Lite menu
         if command -v get_message >/dev/null 2>&1; then
             printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_AUTO_DETECT_FAILED)" "$reset_color"
         else
             printf "%sAuto-detection failed. Returning to DS-Lite menu.%s\n" "$msg_prefix" "$reset_color"
         fi
         return 1 # Return failure to menu system
    fi

    # 2. Perform internal detection using cached info
    local detection_result
    detection_result=$(_detect_provider_internal)
    local detection_status=$?

    if [ $detection_status -ne 0 ]; then
        # Error message already printed by _detect_provider_internal to stderr
        if command -v get_message >/dev/null 2>&1; then
            printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_AUTO_DETECT_FAILED)" "$reset_color"
        else
            printf "%sAuto-detection failed. Returning to DS-Lite menu.%s\n" "$msg_prefix" "$reset_color"
        fi
        return 1 # Return failure to menu system
    fi

    # Parse detection result
    local detected_provider=$(echo "$detection_result" | cut -d'|' -f1)
    local detected_aftr=$(echo "$detection_result" | cut -d'|' -f2)
    local detected_region_text=$(echo "$detection_result" | cut -d'|' -f3)

    # 3. Display result and confirm with user
    printf "\n--- Auto Detection Result ---\n"
    printf " Provider    : %s\n" "$detected_provider"
    if [ -n "$detected_region_text" ]; then printf " Region      : %s\n" "$detected_region_text"; fi
    printf " AFTR Address: %s\n" "$detected_aftr"
    printf "---------------------------\n"

    local confirm_auto=1
    confirm "MSG_CONFIRM_AUTO_SETTINGS" # Assumes key exists in message DB
    confirm_auto=$?

    if [ $confirm_auto -eq 0 ]; then # Yes
        # Apply settings
        apply_dslite_settings "$detected_aftr" "$detected_provider"
        # apply_dslite_settings handles reboot/exit or returns 0
        # If it returns 0, we also return 0 to indicate success without reboot yet
        return $?
    else # No or Return
        # User cancelled, display message and return failure to menu system
         if command -v get_message >/dev/null 2>&1; then
            printf "%s%s%s\n" "$msg_prefix" "$(get_message MSG_AUTO_DETECT_FAILED)" "$reset_color"
        else
            printf "%sAuto-detection cancelled. Returning to DS-Lite menu.%s\n" "$msg_prefix" "$reset_color"
        fi
        return 1 # Return failure to menu system (will show DS-Lite menu again)
    fi
}

# --- Script Execution ---
# This script defines functions to be called from menu.db.
# It does not run main logic automatically when sourced.
# The entry point is triggered by the download command in menu.db,
# which then calls the specified function (e.g., auto_detect_and_apply).

: # No-op to ensure the script sourcing doesn't cause unexpected output or errors
