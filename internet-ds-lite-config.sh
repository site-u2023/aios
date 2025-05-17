#!/bin/sh

SCRIPT_VERSION="2025.05.17-06-15" # Version for this script reflecting simplified DS-Lite handling

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-05-17
#
# Description: Automatically detects IPoE connection type (MAP-E/DS-Lite)
#              based on AS number and passes relevant info to sub-scripts.
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
# AIOS_COMMON_MESSAGE, AIOS_COMMON_DEBUG, AIOS_COMMON_DOWNLOAD are assumed to be loaded

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
# Output: "CONNECTION_TYPE|INTERNAL_KEY|AFTR_ADDRESS_FROM_DB|DISPLAY_NAME"
#         (e.g., "map-e|ocn||OCN Virtual Connect", "ds-lite|transix|gw.transix.jp|transix")
#         or "unknown|||" if not found.
# Returns: 0 on success (found or not found), 1 on error (e.g., empty ASN).
determine_connection_by_as() {
    local input_asn="$1"
    local numeric_asn=""
    local provider_data=""
    local conn_type="unknown"
    local internal_key=""
    local aftr_addr_from_db="" # AFTR from provider_db (domain or IP)
    local display_name=""      # Display name from provider_db

    debug_log "DEBUG" "Determining connection type for Input ASN: $input_asn"

    if [ -z "$input_asn" ]; then
        debug_log "DEBUG" "ASN is empty, cannot determine connection type."
        echo "unknown|||"
        return 1
    fi

    numeric_asn=$(echo "$input_asn" | sed 's/^AS//i')
    provider_data=$(get_provider_data_by_as "$numeric_asn")

    if [ $? -eq 0 ] && [ -n "$provider_data" ]; then
        # Fields: 1:AS, 2:KEY, 3:DISPLAY_NAME, 4:TYPE, 5:AFTR
        conn_type=$(echo "$provider_data" | cut -d'|' -f4)
        internal_key=$(echo "$provider_data" | cut -d'|' -f2)
        display_name=$(echo "$provider_data" | cut -d'|' -f3) # Get display name
        aftr_addr_from_db=$(echo "$provider_data" | cut -d'|' -f5)

        debug_log "DEBUG" "Parsed data: Type=$conn_type, Key=$internal_key, AFTR_DB=$aftr_addr_from_db, Name=$display_name"
    else
        debug_log "DEBUG" "ASN $numeric_asn not found in provider database."
    fi

    echo "${conn_type}|${internal_key}|${aftr_addr_from_db}|${display_name}"
    return 0
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

    if [ ! -f "$MAP_E_SCRIPT" ]; then
        debug_log "INFO" "MAP-E script not found, attempting download..."
        download "$MAP_E_SCRIPT_NAME" "chmod" "hidden"
        if [ ! -f "$MAP_E_SCRIPT" ]; then
            debug_log "ERROR" "Failed to download MAP-E script: $MAP_E_SCRIPT_NAME"
            printf "%s\n" "$(color red "Error: Failed to download required script '$MAP_E_SCRIPT_NAME'.")" >&2
            return 1
        fi
    fi
    if [ ! -f "$DS_LITE_SCRIPT" ]; then
        debug_log "INFO" "DS-Lite script not found, attempting download..."
        download "$DS_LITE_SCRIPT_NAME" "chmod" "hidden"
        if [ ! -f "$DS_LITE_SCRIPT" ]; then
            debug_log "ERROR" "Failed to download DS-Lite script: $DS_LITE_SCRIPT_NAME"
            printf "%s\n" "$(color red "Error: Failed to download required script '$DS_LITE_SCRIPT_NAME'.")" >&2
            return 1
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
    connection_info=$(determine_connection_by_as "$asn") # Now returns display_name as 4th field
    connection_type=$(echo "$connection_info" | cut -d'|' -f1)
    provider_key=$(echo "$connection_info" | cut -d'|' -f2)
    aftr_address_from_db=$(echo "$connection_info" | cut -d'|' -f3)
    display_isp_name=$(echo "$connection_info" | cut -d'|' -f4) # Get display_name from determine_connection_by_as

    debug_log "INFO" "Determined connection type: $connection_type, Provider key: $provider_key, AFTR (from DB): $aftr_address_from_db, Display Name: $display_isp_name"

    # --- 4a. Confirm with User (Skip for 'unknown') ---
    if [ "$connection_type" != "unknown" ]; then
        # display_isp_name is already populated from determine_connection_by_as
        # If display_isp_name was empty from DB, determine_connection_by_as would have kept it empty.
        # We can use provider_key as a fallback if display_isp_name is truly empty.
        local final_display_name="$display_isp_name"
        if [ -z "$final_display_name" ]; then
            final_display_name="$provider_key" # Fallback to key if name is empty
        fi

        printf "%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$final_display_name" tp="$connection_type")")"

        local confirm_apply=1
        confirm "MSG_AUTO_CONFIG_CONFIRM" # Assumes confirm function is available
        confirm_apply=$?

        if [ $confirm_apply -ne 0 ]; then
            debug_log "INFO" "User declined to apply the automatically detected settings."
            return 0 # User cancelled, not an error
        fi
        debug_log "INFO" "User confirmed applying settings for $final_display_name ($connection_type)."
    fi

    # --- 5. Execute Configuration Based on Type ---
    case "$connection_type" in
        "map-e")
            debug_log "DEBUG" "MAP-E connection confirmed. Sourcing MAP-E script..."
            if . "$MAP_E_SCRIPT"; then
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
            ;;
        "ds-lite")
            debug_log "DEBUG" "DS-Lite connection confirmed. Loading DS-Lite script..."
            if [ -z "$aftr_address_from_db" ] && [ "$provider_key" != "transix" ]; then # Transix might get AFTR dynamically
                debug_log "ERROR" "AFTR address is empty for DS-Lite (Provider: $provider_key) and not Transix. Cannot proceed."
                printf "%s\n" "$(color red "$(get_message "MSG_DSLITE_AFTR_EMPTY" pk="$provider_key")")" >&2
                exit_code=1
            fi

            if [ "$exit_code" -eq 0 ]; then
                if . "$DS_LITE_SCRIPT"; then
                    if command -v apply_dslite_settings >/dev/null 2>&1; then
                        debug_log "INFO" "Executing apply_dslite_settings from $DS_LITE_SCRIPT_NAME with AFTR (from DB): $aftr_address_from_db, Provider Display: $display_isp_name, Provider Key: $provider_key"
                        # Pass the AFTR from DB, display name, and provider key.
                        # internet-ds-lite-config.sh will handle resolution and region if needed.
                        if apply_dslite_settings "$aftr_address_from_db" "$display_isp_name" "$provider_key"; then
                            debug_log "INFO" "DS-Lite script executed successfully."
                        else
                            debug_log "ERROR" "DS-Lite script execution failed."
                            # Error message should be handled by apply_dslite_settings
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
            exit_code=1 # Considered an error for auto-config flow
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
# Example test (uncomment to run directly after sourcing, ensure common scripts are available):
# SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# . "${SCRIPT_DIR}/../common/common-color.sh" # Adjust path as needed
# . "${SCRIPT_DIR}/../common/common-debug.sh"
# . "${SCRIPT_DIR}/../common/common-message.sh"
# . "${SCRIPT_DIR}/../common/common-country.sh"
# . "${SCRIPT_DIR}/../common/common-download.sh"
# print_section_title() { printf "\n--- %s ---\n" "$1"; } # Dummy for testing
# # Mock dependent scripts and functions for testing if needed
# touch "${BASE_DIR}/${MAP_E_SCRIPT_NAME}"
# touch "${BASE_DIR}/${DS_LITE_SCRIPT_NAME}"
# # Mock apply_dslite_settings in the test environment if DS_LITE_SCRIPT is complex
# # echo 'apply_dslite_settings() { echo "Mock DS-Lite Apply Called with: $@"; return 0; }' > "${BASE_DIR}/${DS_LITE_SCRIPT_NAME}"
# # mkdir -p "$CACHE_DIR"
# # echo "AS12345" > "${CACHE_DIR}/isp_as.ch"
# # echo "v6" > "${CACHE_DIR}/ip_type.ch"
# internet_auto_config_main

: # Ensure script can be sourced without error if no main execution at the end
