#!/bin/sh

SCRIPT_VERSION="2025.04.21-00-05" # Version for this script

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-04-21
#
# Description: Automatically detects IPoE connection type (MAP-E/DS-Lite)
#              based on AS number and applies the corresponding configuration.
#
# ... (Header comments omitted for brevity) ...
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
### =========================================================

# --- Basic Constants ---
SCRIPT_NAME=$(basename "$0")
# Assuming BASE_DIR, CACHE_DIR, LOG_DIR are inherited or defined by the calling environment (aios)
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
DEBUG_LEVEL="${DEBUG_LEVEL:-INFO}" # Inherit or default

# --- Dependent Script Paths ---
MAP_E_SCRIPT_NAME="internet-map-e.sh"
DS_LITE_SCRIPT_NAME="internet-ds-lite-config.sh"
MAP_E_SCRIPT="${BASE_DIR}/${MAP_E_SCRIPT_NAME}"
DS_LITE_SCRIPT="${BASE_DIR}/${DS_LITE_SCRIPT_NAME}"

# --- Common Script Paths (needed for standalone debugging or if aios doesn't load them) ---
AIOS_COMMON_COUNTRY="${BASE_DIR}/common-country.sh" # Needed for confirm()
AIOS_COMMON_COLOR="${BASE_DIR}/common-color.sh" # Needed for color()

# --- Function to retrieve provider data based on AS Number ---
# Arguments: $1: AS Number (numeric, without "AS" prefix)
# Output: Pipe-separated string: AS_NUM|INTERNAL_KEY|DISPLAY_NAME|CONNECTION_TYPE|AFTR_ADDRESS
#         (e.g., 4713|ocn|OCN Virtual Connect|map-e|)
# Returns: 0 if found, 1 if not found.
get_provider_data_by_as() {
    local search_asn="$1"
    local result=""

    # --- Provider Database (Here Document) ---
    # Format: AS_NUM|INTERNAL_KEY|DISPLAY_NAME|CONNECTION_TYPE|AFTR_ADDRESS
    # AFTR_ADDRESS is empty for MAP-E. DISPLAY_NAME does NOT need quotes.
    local provider_db=$(cat <<-'EOF'
4713|ocn|OCN Virtual Connect|map-e|
2518|v6plus|v6 Plus|map-e|
2519|transix|transix|ds-lite|gw.transix.jp
2527|cross|Cross Pass|ds-lite|2001:f60:0:200::1:1
4737|v6connect|v6 Connect|ds-lite|gw.v6connect.net
EOF
)
    # --- End of Database ---

    # Search for the AS number in the database (first column match using pipe delimiter)
    # Use grep and head -n 1 to find the first matching line
    result=$(echo "$provider_db" | grep "^${search_asn}|" | head -n 1) # Use pipe in grep

    if [ -n "$result" ]; then
        debug_log "DEBUG" "get_provider_data_by_as: Found data for ASN $search_asn: $result"
        echo "$result"
        return 0
    else
        debug_log "DEBUG" "get_provider_data_by_as: No data found for ASN $search_asn"
        return 1
    fi
}

# --- Function to determine connection type and details based on AS Number ---
# Retrieves data using get_provider_data_by_as and formats the output.
# Arguments: $1: AS Number (string, potentially with "AS" prefix)
# Output: "CONNECTION_TYPE|INTERNAL_KEY|AFTR_ADDRESS" (e.g., "map-e|ocn|", "ds-lite|transix|gw.transix.jp")
#         or "unknown||" if not found.
# Returns: 0 on success (found or not found), 1 on error (e.g., empty ASN).
determine_connection_by_as() {
    local input_asn="$1"
    local numeric_asn=""
    local provider_data=""
    local conn_type="unknown"
    local internal_key=""
    local aftr_addr=""

    debug_log "DEBUG" "Determining connection type for Input ASN: $input_asn"

    # Check if ASN is provided
    if [ -z "$input_asn" ]; then
        debug_log "DEBUG" "ASN is empty, cannot determine connection type."
        echo "unknown||"
        return 1 # Indicate error due to missing input
    fi

    # Remove "AS" prefix if present
    numeric_asn=$(echo "$input_asn" | sed 's/^AS//i')

    # Get provider data using the modified function (pipe-separated)
    provider_data=$(get_provider_data_by_as "$numeric_asn")

    # Parse the pipe-separated result using cut
    if [ $? -eq 0 ] && [ -n "$provider_data" ]; then
        # Fields: 1:AS, 2:KEY, 3:NAME, 4:TYPE, 5:AFTR
        conn_type=$(echo "$provider_data" | cut -d'|' -f4)
        internal_key=$(echo "$provider_data" | cut -d'|' -f2)
        aftr_addr=$(echo "$provider_data" | cut -d'|' -f5) # Might be empty

        debug_log "DEBUG" "Parsed data: Type=$conn_type, Key=$internal_key, AFTR=$aftr_addr"
    else
        # Not found, keep defaults (unknown||)
        debug_log "DEBUG" "ASN $numeric_asn not found in provider database."
    fi

    # Output in the required format
    echo "${conn_type}|${internal_key}|${aftr_addr}"
    return 0 # Return 0 whether found or not, as the function's job is to determine
}

internet_auto_config_main() {
    local network_status=""
    local asn=""
    local connection_info=""
    local connection_type=""
    local provider_key=""
    local aftr_address=""
    local exit_code=0

    debug_log "DEBUG" "Starting automatic internet configuration process..." 

    # --- 1. Prerequisite Checks & Downloads ---
    debug_log "DEBUG" "Checking prerequisites..."

    # Check for required cache files
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    if [ ! -f "$ip_type_file" ]; then
        debug_log "DEBUG" "IP type cache file not found: ${ip_type_file}"
        printf "%s\n" "$(color red "Error: Required cache file 'ip_type.ch' not found.")" >&2
        return 1
    fi
    if [ ! -f "${CACHE_DIR}/isp_as.ch" ]; then
        debug_log "DEBUG" "AS number cache file not found: ${CACHE_DIR}/isp_as.ch"
        printf "%s\n" "$(color red "Error: Required cache file 'isp_as.ch' not found.")" >&2
        return 1
    fi

    # Check and download dependent scripts if missing
    if [ ! -f "$MAP_E_SCRIPT" ]; then
        debug_log "DEBUG" "MAP-E script not found, attempting download..." 
        download "$MAP_E_SCRIPT_NAME" "chmod" "hidden"
        if [ ! -f "$MAP_E_SCRIPT" ]; then
            debug_log "DEBUG" "Failed to download MAP-E script: $MAP_E_SCRIPT_NAME"
            printf "%s\n" "$(color red "Error: Failed to download required script '$MAP_E_SCRIPT_NAME'.")" >&2
            return 1
        fi
    fi
    if [ ! -f "$DS_LITE_SCRIPT" ]; then
        debug_log "DEBUG" "DS-Lite script not found, attempting download..." 
        download "$DS_LITE_SCRIPT_NAME" "chmod" "hidden"
        if [ ! -f "$DS_LITE_SCRIPT" ]; then
            debug_log "DEBUG" "Failed to download DS-Lite script: $DS_LITE_SCRIPT_NAME"
            printf "%s\n" "$(color red "Error: Failed to download required script '$DS_LITE_SCRIPT_NAME'.")" >&2
            return 1
        fi
    fi

    # --- 2. Network Connectivity Check (ip_type.ch利用) ---
    debug_log "DEBUG" "Checking network connectivity..."
    network_status=$(cat "$ip_type_file" 2>/dev/null)
    if [ -z "$network_status" ] || [ "$network_status" = "unknown" ]; then
        debug_log "DEBUG" "IPv6 connectivity not available ($network_status). Cannot proceed with IPoE configuration."
        printf "%s\n" "$(color red "Error: IPv6 connectivity not available. Cannot proceed with IPoE auto-configuration.")" >&2
        return 1
    fi
    case "$network_status" in
        v6|v4v6)
            debug_log "DEBUG" "IPv6 connectivity confirmed ($network_status)."
            ;;
        *)
            debug_log "DEBUG" "IPv6 connectivity not available ($network_status). Cannot proceed with IPoE configuration."
            printf "%s\n" "$(color red "Error: IPv6 connectivity not available. Cannot proceed with IPoE auto-configuration.")" >&2
            return 1
            ;;
    esac

    # --- 3. Get AS Number ---
    debug_log "DEBUG" "Retrieving AS number..."
    asn=$(cat "${CACHE_DIR}/isp_as.ch")
    if [ -z "$asn" ]; then
        debug_log "DEBUG" "Failed to retrieve AS number from cache."
        printf "%s\n" "$(color red "Error: Could not retrieve AS number for automatic detection.")" >&2
        return 1
    fi
    debug_log "DEBUG" "Detected AS Number: $asn" 

    # --- 4. Determine Connection Type ---
    debug_log "DEBUG" "Determining connection type using ASN..."
    connection_info=$(determine_connection_by_as "$asn")
    connection_type=$(echo "$connection_info" | cut -d'|' -f1)
    provider_key=$(echo "$connection_info" | cut -d'|' -f2)
    aftr_address=$(echo "$connection_info" | cut -d'|' -f3)

    debug_log "DEBUG" "Determined connection type: $connection_type, Provider key: $provider_key, AFTR: $aftr_address" 

    # --- 4a. Get Display Info and Confirm with User (Skip for 'unknown') ---
    if [ "$connection_type" != "unknown" ]; then
        local provider_data=""
        local display_isp_name=""
        local display_conn_type=""
        local numeric_asn=$(echo "$asn" | sed 's/^AS//i')

        provider_data=$(get_provider_data_by_as "$numeric_asn")
        if [ $? -eq 0 ] && [ -n "$provider_data" ]; then
            display_isp_name=$(echo "$provider_data" | cut -d'|' -f3)
            display_conn_type=$(echo "$provider_data" | cut -d'|' -f4)
        fi

        if [ -z "$display_isp_name" ]; then
            debug_log "DEBUG" "Could not get valid display info for ASN '$numeric_asn'. Using key/type as fallback."
            display_isp_name="$provider_key"
            display_conn_type="$connection_type"
        fi

        printf "\n%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$display_isp_name" tp="$display_conn_type")")"

        local confirm_apply=1
        confirm "MSG_AUTO_CONFIG_CONFIRM"
        confirm_apply=$?

        if [ $confirm_apply -ne 0 ]; then
            debug_log "DEBUG" "User declined to apply the automatically detected settings." 
            return 0
        fi
        debug_log "DEBUG" "User confirmed applying settings for $display_isp_name ($display_conn_type)."
        printf "\n"
    fi

    # --- 5. Execute Configuration Based on Type ---
    case "$connection_type" in
        "map-e")
            debug_log "DEBUG" "MAP-E connection confirmed. Loading MAP-E script..." 
            if . "$MAP_E_SCRIPT"; then
                if command -v internet_main >/dev/null 2>&1; then
                    debug_log "DEBUG" "Executing internet_main function from $MAP_E_SCRIPT_NAME"
                    if internet_main; then
                       debug_log "DEBUG" "MAP-E script executed successfully." 
                    else
                       debug_log "DEBUG" "MAP-E script execution failed."
                       printf "%s\n" "$(color red "Error: Execution of script '$MAP_E_SCRIPT_NAME' failed.")" >&2
                       exit_code=1
                    fi
                else
                    debug_log "DEBUG" "Function 'internet_main' not found in $MAP_E_SCRIPT_NAME."
                    printf "%s\n" "$(color red "Error: Required function 'internet_main' not found in script '$MAP_E_SCRIPT_NAME'.")" >&2
                    exit_code=1
                fi
            else
                debug_log "DEBUG" "Failed to source MAP-E script: $MAP_E_SCRIPT_NAME"
                printf "%s\n" "$(color red "Error: Failed to load script '$MAP_E_SCRIPT_NAME'.")" >&2
                exit_code=1
            fi
            ;;
        "ds-lite")
            debug_log "DEBUG" "DS-Lite connection confirmed. Loading DS-Lite script..." 
            if . "$DS_LITE_SCRIPT"; then
                if command -v apply_dslite_settings >/dev/null 2>&1; then
                    debug_log "DEBUG" "Executing apply_dslite_settings function from $DS_LITE_SCRIPT_NAME with AFTR: $aftr_address, Key: $provider_key"
                    if apply_dslite_settings "$aftr_address" "$provider_key"; then
                        debug_log "DEBUG" "DS-Lite script executed successfully." 
                    else
                        debug_log "DEBUG" "DS-Lite script execution failed."
                        printf "%s\n" "$(color red "Error: Execution of script '$DS_LITE_SCRIPT_NAME' failed.")" >&2
                        exit_code=1
                    fi
                else
                    debug_log "DEBUG" "Function 'apply_dslite_settings' not found in $DS_LITE_SCRIPT_NAME."
                    printf "%s\n" "$(color red "Error: Required function 'apply_dslite_settings' not found in script '$DS_LITE_SCRIPT_NAME'.")" >&2
                    exit_code=1
                fi
            else
                debug_log "DEBUG" "Failed to source DS-Lite script: $DS_LITE_SCRIPT_NAME"
                printf "%s\n" "$(color red "Error: Failed to load script '$DS_LITE_SCRIPT_NAME'.")" >&2
                exit_code=1
            fi
            ;;
        "unknown")
            debug_log "DEBUG" "Could not automatically determine the IPoE connection type for ASN $asn."
            printf "%s\n" "$(color yellow "$(get_message "MSG_AUTO_CONFIG_UNKNOWN" as="$asn")")"
            exit_code=1
            ;;
        *)
            debug_log "DEBUG" "Unexpected connection type returned: $connection_type"
            printf "%s\n" "$(color red "Error: Unexpected value encountered: $connection_type")" >&2
            exit_code=1
            ;;
    esac

    if [ "$exit_code" -eq 0 ]; then
        debug_log "DEBUG" "Automatic internet configuration process completed." 
    else
        debug_log "DEBUG" "Automatic internet configuration process finished with errors or was unable to complete."
    fi

    return $exit_code
}

# --- Script Execution ---
# This script primarily defines functions to be called by other parts of aios (e.g., a menu).
# Example test (uncomment to run directly after sourcing):
internet_auto_config_main
