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
    # For DS-Lite, AFTR_ADDRESS can be a domain name or an IP address.
    local provider_db=$(cat <<-'EOF'
4713|ocn|OCN Virtual Connect|map-e|
2518|v6plus|v6 Plus|map-e|
2519|transix|transix|ds-lite|gw.transix.jp
2527|cross|Cross Pass|ds-lite|2001:f60:0:200::1:1
4737|v6connect|v6 Connect|ds-lite|gw.v6connect.net
2515|nuro|NURO Hikari|map-e|
EOF
)
    # --- End of Database ---

    result=$(echo "$provider_db" | grep "^${search_asn}|" | head -n 1)

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
    local asn=""
    local connection_info=""
    local connection_type=""
    local provider_key=""
    local aftr_address_from_db="" # AFTR from provider_db (domain or IP)
    local display_isp_name=""     # Display name from provider_db, possibly updated
    local exit_code=0

    debug_log "DEBUG" "Starting automatic internet configuration process..."

    # --- 1. Prerequisite Checks & Downloads ---
    debug_log "DEBUG" "Checking prerequisites..."
    print_section_title # Assumed to be available

    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    if [ ! -f "$ip_type_file" ]; then
        debug_log "ERROR" "IP type cache file not found: ${ip_type_file}"
        printf "%s\n" "$(color red "Error: Required cache file 'ip_type.ch' not found.")" >&2
        return 1
    fi
    if [ ! -f "${CACHE_DIR}/isp_as.ch" ]; then
        debug_log "ERROR" "AS number cache file not found: ${CACHE_DIR}/isp_as.ch"
        printf "%s\n" "$(color red "Error: Required cache file 'isp_as.ch' not found.")" >&2
        return 1
    fi

    # Check and download dependent scripts if missing
    # General MAP-E script
    if [ ! -f "$MAP_E_SCRIPT" ]; then
        debug_log "INFO" "MAP-E script ($MAP_E_SCRIPT_NAME) not found, attempting download..."
        download "$MAP_E_SCRIPT_NAME" "chmod" "hidden"
        if [ ! -f "$MAP_E_SCRIPT" ]; then
            debug_log "ERROR" "Failed to download MAP-E script: $MAP_E_SCRIPT_NAME"
            printf "%s\n" "$(color red "Error: Failed to download required script '$MAP_E_SCRIPT_NAME'.")" >&2
            return 1 # Essential for non-NURO MAP-E
        fi
    fi
    # NURO MAP-E script
    if [ ! -f "$MAP_E_NURO_SCRIPT" ]; then
        debug_log "INFO" "NURO MAP-E script ($MAP_E_NURO_SCRIPT_NAME) not found, attempting download..."
        download "$MAP_E_NURO_SCRIPT_NAME" "chmod" "hidden"
        if [ ! -f "$MAP_E_NURO_SCRIPT" ]; then
            debug_log "ERROR" "Failed to download NURO MAP-E script: $MAP_E_NURO_SCRIPT_NAME"
            printf "%s\n" "$(color red "Error: Failed to download required script '$MAP_E_NURO_SCRIPT_NAME'.")" >&2
            # This might only be an error if provider_key is "nuro" later.
            # For now, let's assume it's needed if we proceed with NURO.
        fi
    fi
    # DS-Lite script
    if [ ! -f "$DS_LITE_SCRIPT" ]; then
        debug_log "INFO" "DS-Lite script ($DS_LITE_SCRIPT_NAME) not found, attempting download..."
        download "$DS_LITE_SCRIPT_NAME" "chmod" "hidden"
        if [ ! -f "$DS_LITE_SCRIPT" ]; then
            debug_log "ERROR" "Failed to download DS-Lite script: $DS_LITE_SCRIPT_NAME"
            printf "%s\n" "$(color red "Error: Failed to download required script '$DS_LITE_SCRIPT_NAME'.")" >&2
            return 1 # Essential for DS-Lite
        fi
    fi

    # --- 2. Network Connectivity Check (ip_type.ch利用) ---
    # (Commented out as per original script state)
    # ...

    # --- 3. Get AS Number ---
    debug_log "DEBUG" "Retrieving AS number..."
    asn=$(cat "${CACHE_DIR}/isp_as.ch")
    if [ -z "$asn" ]; then
        debug_log "ERROR" "Failed to retrieve AS number from cache."
        printf "%s\n" "$(color red "Error: Could not retrieve AS number for automatic detection.")" >&2
        return 1
    fi
    debug_log "INFO" "Detected AS Number: $asn"

    # --- 4. Determine Connection Type ---
    debug_log "DEBUG" "Determining connection type using ASN..."
    connection_info=$(determine_connection_by_as "$asn")
    connection_type=$(echo "$connection_info" | cut -d'|' -f1)
    provider_key=$(echo "$connection_info" | cut -d'|' -f2)
    aftr_address_from_db=$(echo "$connection_info" | cut -d'|' -f3)
    display_isp_name=$(echo "$connection_info" | cut -d'|' -f4)

    debug_log "INFO" "Determined connection type: $connection_type, Provider key: $provider_key, AFTR (from DB): $aftr_address_from_db, Display Name: $display_isp_name"

    # --- 4a. Confirm with User (Skip for 'unknown') ---
    if [ "$connection_type" != "unknown" ]; then
        local final_display_name="$display_isp_name"
        if [ -z "$final_display_name" ]; then
            final_display_name="$provider_key"
        fi

        printf "%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$final_display_name" tp="$connection_type")")"

        local confirm_apply=1
        confirm "MSG_AUTO_CONFIG_CONFIRM"
        confirm_apply=$?

        if [ $confirm_apply -ne 0 ]; then
            debug_log "INFO" "User declined to apply the automatically detected settings."
            return 0
        fi
        debug_log "INFO" "User confirmed applying settings for $final_display_name ($connection_type)."
    fi

    # --- 5. Execute Configuration Based on Type ---
    case "$connection_type" in
        "map-e")
            if [ "$provider_key" = "nuro" ]; then
                debug_log "DEBUG" "NURO MAP-E connection confirmed. Sourcing NURO MAP-E script..."
                if [ ! -f "$MAP_E_NURO_SCRIPT" ]; then # Re-check if download failed earlier but user confirmed
                    debug_log "ERROR" "NURO MAP-E script ($MAP_E_NURO_SCRIPT_NAME) is missing and required."
                    printf "%s\n" "$(color red "Error: Required script '$MAP_E_NURO_SCRIPT_NAME' is missing.")" >&2
                    exit_code=1
                elif . "$MAP_E_NURO_SCRIPT"; then
                    debug_log "DEBUG" "NURO MAP-E script ($MAP_E_NURO_SCRIPT_NAME) sourced successfully."
                    if command -v internet_map_nuro_main >/dev/null 2>&1; then # NURO script specific main function
                        debug_log "DEBUG" "Executing internet_map_nuro_main function from $MAP_E_NURO_SCRIPT_NAME"
                        internet_map_nuro_main
                    else
                        debug_log "ERROR" "Function 'internet_map_nuro_main' not found in $MAP_E_NURO_SCRIPT_NAME."
                        printf "%s\n" "$(color red "Error: Required function 'internet_map_nuro_main' not found in script '$MAP_E_NURO_SCRIPT_NAME'.")" >&2
                        exit_code=1
                    fi
                else
                    debug_log "ERROR" "Failed to source NURO MAP-E script: $MAP_E_NURO_SCRIPT_NAME"
                    printf "%s\n" "$(color red "Error: Failed to load script '$MAP_E_NURO_SCRIPT_NAME'.")" >&2
                    exit_code=1
                fi
            else # Other MAP-E providers
                debug_log "DEBUG" "Generic MAP-E connection confirmed. Sourcing MAP-E script..."
                if [ ! -f "$MAP_E_SCRIPT" ]; then # Re-check
                    debug_log "ERROR" "MAP-E script ($MAP_E_SCRIPT_NAME) is missing and required."
                    printf "%s\n" "$(color red "Error: Required script '$MAP_E_SCRIPT_NAME' is missing.")" >&2
                    exit_code=1
                elif . "$MAP_E_SCRIPT"; then
                    debug_log "DEBUG" "MAP-E script ($MAP_E_SCRIPT_NAME) sourced successfully."
                    if command -v internet_map_main >/dev/null 2>&1; then
                        debug_log "DEBUG" "Executing internet_map_main function from $MAP_E_SCRIPT_NAME"
                        internet_map_main
                    else
                        debug_log "ERROR" "Function 'internet_map_main' not found in $MAP_E_SCRIPT_NAME."
                        printf "%s\n" "$(color red "Error: Required function 'internet_map_main' not found in script '$MAP_E_SCRIPT_NAME'.")" >&2
                        exit_code=1
                    fi
                else
                    debug_log "ERROR" "Failed to source MAP-E script: $MAP_E_SCRIPT_NAME"
                    printf "%s\n" "$(color red "Error: Failed to load script '$MAP_E_SCRIPT_NAME'.")" >&2
                    exit_code=1
                fi
            fi
            ;;
        "ds-lite")
            debug_log "DEBUG" "DS-Lite connection confirmed. Loading DS-Lite script..."
            if [ -z "$aftr_address_from_db" ] && [ "$provider_key" != "transix" ]; then
                debug_log "ERROR" "AFTR address is empty for DS-Lite (Provider: $provider_key) and not Transix. Cannot proceed."
                printf "%s\n" "$(color red "$(get_message "MSG_DSLITE_AFTR_EMPTY" pk="$provider_key")")" >&2
                exit_code=1
            fi

            if [ "$exit_code" -eq 0 ]; then
                if [ ! -f "$DS_LITE_SCRIPT" ]; then # Re-check
                    debug_log "ERROR" "DS-Lite script ($DS_LITE_SCRIPT_NAME) is missing and required."
                    printf "%s\n" "$(color red "Error: Required script '$DS_LITE_SCRIPT_NAME' is missing.")" >&2
                    exit_code=1
                elif . "$DS_LITE_SCRIPT"; then
                    if command -v apply_dslite_settings >/dev/null 2>&1; then
                        debug_log "INFO" "Executing apply_dslite_settings from $DS_LITE_SCRIPT_NAME with AFTR (from DB): $aftr_address_from_db, Provider Display: $display_isp_name, Provider Key: $provider_key"
                        if apply_dslite_settings "$aftr_address_from_db" "$display_isp_name" "$provider_key"; then
                            debug_log "INFO" "DS-Lite script executed successfully."
                        else
                            debug_log "ERROR" "DS-Lite script execution failed."
                            exit_code=1
                        fi
                    else
                        debug_log "ERROR" "Function 'apply_dslite_settings' not found in $DS_LITE_SCRIPT_NAME."
                        printf "%s\n" "$(color red "Error: Required function 'apply_dslite_settings' not found in script '$DS_LITE_SCRIPT_NAME'.")" >&2
                        exit_code=1
                    fi
                else
                    debug_log "ERROR" "Failed to source DS-Lite script: $DS_LITE_SCRIPT_NAME"
                    printf "%s\n" "$(color red "Error: Failed to load script '$DS_LITE_SCRIPT_NAME'.")" >&2
                    exit_code=1
                fi
            fi
            ;;
        "unknown")
            debug_log "WARN" "Could not automatically determine the IPoE connection type for ASN $asn."
            printf "%s\n" "$(color yellow "$(get_message "MSG_AUTO_CONFIG_UNKNOWN" as="$asn")")"
            exit_code=1
            ;;
        *)
            debug_log "ERROR" "Unexpected connection type returned: $connection_type"
            printf "%s\n" "$(color red "Error: Unexpected value encountered: $connection_type")" >&2
            exit_code=1
            ;;
    esac

    if [ "$exit_code" -eq 0 ]; then
        debug_log "INFO" "Automatic internet configuration process completed or handed over to a sub-script."
    else
        debug_log "ERROR" "Automatic internet configuration process finished with errors."
    fi

    return $exit_code
}

# --- Script Execution ---
# This script primarily defines functions to be called by other parts of aios (e.g., a menu).
# Example test (uncomment to run directly after sourcing):
internet_auto_config_main
