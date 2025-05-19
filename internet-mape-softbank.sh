#!/bin/ash

SCRIPT_VERSION="2025.05.19-03-00" # バージョン更新

#
# setup_softbank_map_e.sh
# Concept script to configure MAP-E for SoftBank Hikari on OpenWrt
# based on potentially fixed parameters found in a blog post.
# This script is adapted to follow conventions similar to internet-map-e.sh
# for logging, using debug_log "LEVEL" "Message" format.
#
# THIS IS A CONCEPT AND REQUIRES VALIDATION OF PARAMETERS
# AND THOROUGH TESTING.
#

# Load OpenWrt standard functions
. /lib/functions.sh
. /lib/functions/network.sh

# --- Configuration: Potentially fixed MAP-E parameters ---
# These values are from the blog post and NEED VERIFICATION for general applicability.
="2400:2000:4:0:a000::1919"
SB_MAP_E_EA_LEN=""
SB_MAP_E_PSID_LEN=""
SB_MAP_E_PSID_OFFSET=""
# --- End of Configuration ---

get_delegated_prefix() {
    local USER_SPECIFIED_WAN_IF="$1"
    local IPV6_WAN_IF_TO_USE=""
    local DETECTED_WAN6_IF=""
    local PREFIX_WITH_LENGTH=""

    debug_log "DEBUG" "Attempting to determine IPv6 WAN interface."

    # Try to find the active IPv6 WAN interface (typically 'wan6')
    network_find_wan6 DETECTED_WAN6_IF
    if [ -n "$DETECTED_WAN6_IF" ]; then
        debug_log "DEBUG" "Auto-detected active IPv6 WAN interface: '$DETECTED_WAN6_IF'."
        IPV6_WAN_IF_TO_USE="$DETECTED_WAN6_IF"
    elif [ -n "$USER_SPECIFIED_WAN_IF" ]; then # Corrected: Removed {}
        debug_log "DEBUG" "Warning: Could not auto-detect active IPv6 WAN interface. Using user-specified interface: '$USER_SPECIFIED_WAN_IF'."
        IPV6_WAN_IF_TO_USE="$USER_SPECIFIED_WAN_IF"
    else
        debug_log "DEBUG" "Error: No IPv6 WAN interface could be determined (neither auto-detected nor specified)."
        return 1
    fi

    debug_log "DEBUG" "Attempting to get delegated prefix from interface '$IPV6_WAN_IF_TO_USE'."
    # network_get_prefix6 sets the first argument variable with the prefix/length
    network_get_prefix6 PREFIX_WITH_LENGTH "$IPV6_WAN_IF_TO_USE"

    if [ -n "$PREFIX_WITH_LENGTH" ]; then
        debug_log "DEBUG" "Found delegated prefix for '$IPV6_WAN_IF_TO_USE': $PREFIX_WITH_LENGTH"
        echo "$PREFIX_WITH_LENGTH"
        return 0
    else
        debug_log "DEBUG" "Error: Could not determine IPv6 delegated prefix for interface '$IPV6_WAN_IF_TO_USE'."
        debug_log "DEBUG" "Please ensure '$IPV6_WAN_IF_TO_USE' is up and has received a prefix delegation."
        return 1
    fi
}

config_softbank() {
    # Script-level argument validation
    if [ "$#" -ne 1 ]; then
        debug_log "DEBUG" "Error: Incorrect number of script arguments."
        echo "Usage: $(basename "$0") <user_specified_wan_interface_name>"
        echo "Example: $(basename "$0") wan (This name is used as a hint to find the IPv6 WAN interface)"
        return 1
    fi

    local USER_SPECIFIED_WAN_IF="$1"
    local MAP_IFACE_NAME="wan_map_sb" # Name for the new MAP-E interface
    local DELEGATED_IPV6_PREFIX
    local IPV6_LINK_IF="" # Interface for tunlink

    if [ -z "$USER_SPECIFIED_WAN_IF" ]; then
        debug_log "DEBUG" "Error: User-specified WAN interface name argument must not be empty."
        echo "Usage: $(basename "$0") <user_specified_wan_interface_name>"
        echo "Example: $(basename "$0") wan"
        return 1
    fi

    debug_log "DEBUG" "Starting SoftBank Hikari MAP-E configuration using interface hint: '$USER_SPECIFIED_WAN_IF'..."

    # 1. Check for required packages (is_package_installed is not defined in the provided source)
    # Assuming 'map' package check is handled elsewhere or not strictly needed here based on source.
    # if ! is_package_installed "map"; then
    #     debug_log "DEBUG" "Error: 'map' package is not installed. Please install it first (opkg update && opkg install map)."
    #     return 1
    # fi
    # debug_log "DEBUG" "Info: 'map' package is installed."

    # 2. Get IPv6 Delegated Prefix
    DELEGATED_IPV6_PREFIX=$(get_delegated_prefix "$USER_SPECIFIED_WAN_IF")
    if [ $? -ne 0 ] || [ -z "$DELEGATED_IPV6_PREFIX" ]; then
        debug_log "DEBUG" "Error: Failed to get IPv6 delegated prefix. Aborting MAP-E configuration."
        return 1
    fi

    debug_log "DEBUG" "Info: Using IPv6 Delegated Prefix for MAP-E: $DELEGATED_IPV6_PREFIX"
    debug_log "DEBUG" "Info: Using MAP-E BR IPv6 Address: $"
    debug_log "DEBUG" "Info: Using MAP-E EA-len: $SB_MAP_E_EA_LEN, PSID-len: $SB_MAP_E_PSID_LEN, Offset: $SB_MAP_E_PSID_OFFSET"

    # Determine the tunlink interface (should be the actual IPv6 WAN interface)
    network_find_wan6 IPV6_LINK_IF
    if [ -z "$IPV6_LINK_IF" ]; then
        debug_log "DEBUG" "Warning: Could not auto-detect active IPv6 WAN interface for tunlink. Falling back to user-specified hint: '$USER_SPECIFIED_WAN_IF'."
        IPV6_LINK_IF="$USER_SPECIFIED_WAN_IF"
    fi
    debug_log "DEBUG" "Info: Using '$IPV6_LINK_IF' for MAP-E tunlink."

    # 3. Configure MAP-E interface using uci
    debug_log "DEBUG" "Info: Configuring MAP-E interface '$MAP_IFACE_NAME'..."

    uci -q delete network."$MAP_IFACE_NAME"



    uci commit network
    debug_log "DEBUG" "Info: MAP-E interface '$MAP_IFACE_NAME' configured in UCI."

    # 4. Reload network configuration
    debug_log "DEBUG" "Info: Reloading network configuration..."
    if /etc/init.d/network reload; then
        debug_log "DEBUG" "Success: Network configuration reloaded. SoftBank Hikari MAP-E setup attempted."
        debug_log "DEBUG" "Please check your internet connectivity and system logs for details."
    else
        debug_log "DEBUG" "Error: Failed to reload network configuration."
        return 1
    fi

    return 0
}

internet_softbank_main() {
    local configure_status

    print_section_title "MENU_INTERNET_MAPE" # This function is not defined in the provided source.
    
    # `map` パッケージのインストール (install_package is not defined in the provided source)
    if ! install_package map hidden; then # This function is not defined in the provided source.
        debug_log "DEBUG" "internet_map_main: Failed to install 'map' package or it was already installed. Continuing."
        return 1
    fi
    
    # Call the core configuration function, passing all script arguments.
    # config_softbank will handle argument validation internally.
    config_softbank "$@"
    configure_status=$?

    # Log final status based on the return code of the configuration function.
    if [ "$configure_status" -eq 0 ]; then
        debug_log "DEBUG" "Info: SoftBank MAP-E configuration script finished successfully."
    else
        # Specific error messages and usage should have been printed by config_softbank
        debug_log "DEBUG" "Error: SoftBank MAP-E configuration script failed. Exit status: $configure_status."
    fi

    return "$configure_status"
}

internet_softbank_main
