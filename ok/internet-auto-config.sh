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

# --- Debug Logging Function (should be loaded by aios) ---
# Fallback logger (should not be needed if aios is loaded correctly)
if ! command -v debug_log >/dev/null 2>&1; then
    debug_log() {
        local level="$1"
        local message="$2"
        echo "${level}: ${message}" >&2
    }
    debug_log "DEBUG" "debug_log function not found initially, using basic fallback. This might indicate an issue loading 'aios'."
fi

# --- Check if essential functions from aios are loaded ---
# If not, it indicates a problem, but we don't re-load aios here.
if ! command -v download >/dev/null 2>&1; then
    debug_log "ERROR" "Core 'download' function from aios not found. Cannot proceed."
    # Error messages are hardcoded in English
    # Use color function if available for error message
    if command -v color >/dev/null 2>&1; then
        printf "%s\n" "$(color red "Error: Core aios functions are missing. Cannot run $SCRIPT_NAME.")" >&2
    else
        printf "Error: Core aios functions are missing. Cannot run %s.\n" "$SCRIPT_NAME" >&2
    fi
    exit 1
fi
# Check for get_message as well, crucial for user feedback
if ! command -v get_message >/dev/null 2>&1; then
     debug_log "ERROR" "Core 'get_message' function from aios not found. User messages will be limited."
     # Basic fallback for get_message
     get_message() { echo "$1"; }
fi
# Check for confirm function, load common-country if needed
if ! command -v confirm >/dev/null 2>&1; then
     debug_log "DEBUG" "'confirm' function not found. Attempting to load from common-country.sh"
     if [ -f "$AIOS_COMMON_COUNTRY" ]; then
          # shellcheck source=/dev/null
          . "$AIOS_COMMON_COUNTRY"
          if ! command -v confirm >/dev/null 2>&1; then
               debug_log "ERROR" "Failed to load 'confirm' function from common-country.sh. Cannot proceed."
               if command -v color >/dev/null 2>&1; then
                   printf "%s\n" "$(color red "Error: Required 'confirm' function is missing.")" >&2
               else
                   printf "Error: Required 'confirm' function is missing.\n" >&2
               fi
               exit 1
          fi
     else
          debug_log "ERROR" "common-country.sh not found. Cannot load 'confirm' function."
          if command -v color >/dev/null 2>&1; then
              printf "%s\n" "$(color red "Error: Required 'confirm' function is missing.")" >&2
          else
              printf "Error: Required 'confirm' function is missing.\n" >&2
          fi
          exit 1
     fi
fi
# Check for color function, load if needed
if ! command -v color >/dev/null 2>&1; then
     debug_log "DEBUG" "'color' function not found. Attempting to load from common-color.sh"
     if [ -f "$AIOS_COMMON_COLOR" ]; then
          # shellcheck source=/dev/null
          . "$AIOS_COMMON_COLOR"
     else
          debug_log "ERROR" "common-color.sh not found. Color output disabled."
          # Basic fallback for color
          color() { printf "%s" "$2"; }
     fi
fi

# --- Function Definitions ---

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


# --- Main function for automatic internet configuration ---
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
    if [ ! -f "${CACHE_DIR}/network.ch" ]; then
        debug_log "DEBUG" "Network status cache file not found: ${CACHE_DIR}/network.ch" # ERROR -> DEBUG
        printf "%s\n" "$(color red "Error: Required cache file 'network.ch' not found.")" >&2 # MODIFIED: Use color()
        return 1
    fi
    if [ ! -f "${CACHE_DIR}/isp_as.ch" ]; then
        debug_log "DEBUG" "AS number cache file not found: ${CACHE_DIR}/isp_as.ch" # ERROR -> DEBUG
        printf "%s\n" "$(color red "Error: Required cache file 'isp_as.ch' not found.")" >&2 # MODIFIED: Use color()
        return 1
    fi

    # Check and download dependent scripts if missing
    # Using download function inherited from aios
    if [ ! -f "$MAP_E_SCRIPT" ]; then
        debug_log "DEBUG" "MAP-E script not found, attempting download..." 
        download "$MAP_E_SCRIPT_NAME" "chmod" "hidden" # Download, set executable, hide verbose output
        if [ ! -f "$MAP_E_SCRIPT" ]; then
            debug_log "DEBUG" "Failed to download MAP-E script: $MAP_E_SCRIPT_NAME" # ERROR -> DEBUG
            printf "%s\n" "$(color red "Error: Failed to download required script '$MAP_E_SCRIPT_NAME'.")" >&2 # MODIFIED: Use color()
            return 1
        fi
    fi
     if [ ! -f "$DS_LITE_SCRIPT" ]; then
        debug_log "DEBUG" "DS-Lite script not found, attempting download..." 
        download "$DS_LITE_SCRIPT_NAME" "chmod" "hidden" # Download, set executable, hide verbose output
        if [ ! -f "$DS_LITE_SCRIPT" ]; then
            debug_log "DEBUG" "Failed to download DS-Lite script: $DS_LITE_SCRIPT_NAME" # ERROR -> DEBUG
            printf "%s\n" "$(color red "Error: Failed to download required script '$DS_LITE_SCRIPT_NAME'.")" >&2 # MODIFIED: Use color()
            return 1
        fi
    fi

    # --- 2. Network Connectivity Check ---
    debug_log "DEBUG" "Checking network connectivity..."
    network_status=$(cat "${CACHE_DIR}/network.ch")
    case "$network_status" in
        v6|v4v6)
            debug_log "DEBUG" "IPv6 connectivity confirmed ($network_status)."
            ;;
        *)
            debug_log "DEBUG" "IPv6 connectivity not available ($network_status). Cannot proceed with IPoE configuration." # ERROR -> DEBUG
            printf "%s\n" "$(color red "Error: IPv6 connectivity not available. Cannot proceed with IPoE auto-configuration.")" >&2 # MODIFIED: Use color()
            return 1
            ;;
    esac

    # --- 3. Get AS Number ---
    debug_log "DEBUG" "Retrieving AS number..."
    asn=$(cat "${CACHE_DIR}/isp_as.ch")
    if [ -z "$asn" ]; then
        debug_log "DEBUG" "Failed to retrieve AS number from cache." # ERROR -> DEBUG
        printf "%s\n" "$(color red "Error: Could not retrieve AS number for automatic detection.")" >&2 # MODIFIED: Use color()
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
        local numeric_asn=$(echo "$asn" | sed 's/^AS//i') # Need numeric ASN for lookup

        # Get provider data using the modified function (pipe-separated)
        provider_data=$(get_provider_data_by_as "$numeric_asn")
        if [ $? -eq 0 ] && [ -n "$provider_data" ]; then
            # Use cut to extract display name (field 3) and connection type (field 4)
            display_isp_name=$(echo "$provider_data" | cut -d'|' -f3)
            display_conn_type=$(echo "$provider_data" | cut -d'|' -f4)
        fi

        # Fallback if display info couldn't be retrieved
        if [ -z "$display_isp_name" ]; then
            debug_log "DEBUG" "Could not get valid display info for ASN '$numeric_asn'. Using key/type as fallback."
            display_isp_name="$provider_key" # Use the key as fallback name
            display_conn_type="$connection_type"
        fi

        # Display the detected result using MSG_AUTO_CONFIG_RESULT
        # Placeholders: sp (Service Provider), tp (Type)
        printf "\n%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$display_isp_name" tp="$display_conn_type")")"

        # Confirm with the user using MSG_AUTO_CONFIG_CONFIRM
        local confirm_apply=1
        # Use the corrected message key for confirmation
        # ja|MSG_AUTO_CONFIG_CONFIRM=これらの設定を適用します {yn}
        confirm "MSG_AUTO_CONFIG_CONFIRM" # confirm uses 'yn' by default
        confirm_apply=$?

        if [ $confirm_apply -ne 0 ]; then # User selected No (1) or Return (2)
            debug_log "DEBUG" "User declined to apply the automatically detected settings." 
            # No cancellation message needed as per request
            return 0 # Exit gracefully, not an error state
        fi
        # User selected Yes (0), proceed with configuration
        debug_log "DEBUG" "User confirmed applying settings for $display_isp_name ($display_conn_type)."
        printf "\n" # Add a newline for better separation before script execution output
    fi

    # --- 5. Execute Configuration Based on Type ---
    case "$connection_type" in
        "map-e")
            # MAP-E 設定処理 (引数なしで呼び出し)
            debug_log "DEBUG" "MAP-E connection confirmed. Loading MAP-E script..." 
            # Source the MAP-E script to make its functions available
            # shellcheck source=/dev/null
            if . "$MAP_E_SCRIPT"; then
                # Check if the main function exists in the sourced script
                if command -v internet_main >/dev/null 2>&1; then
                    debug_log "DEBUG" "Executing internet_main function from $MAP_E_SCRIPT_NAME"
                    # Execute the main function from internet-map-e.sh (no arguments needed)
                    if internet_main; then
                       debug_log "DEBUG" "MAP-E script executed successfully." 
                       # No explicit success message needed
                    else
                       debug_log "DEBUG" "MAP-E script execution failed." # ERROR -> DEBUG
                       printf "%s\n" "$(color red "Error: Execution of script '$MAP_E_SCRIPT_NAME' failed.")" >&2 # MODIFIED: Use color()
                       exit_code=1
                    fi
                else
                    debug_log "DEBUG" "Function 'internet_main' not found in $MAP_E_SCRIPT_NAME." # ERROR -> DEBUG
                    printf "%s\n" "$(color red "Error: Required function 'internet_main' not found in script '$MAP_E_SCRIPT_NAME'.")" >&2 # MODIFIED: Use color()
                    exit_code=1
                fi
            else
                debug_log "DEBUG" "Failed to source MAP-E script: $MAP_E_SCRIPT_NAME" # ERROR -> DEBUG
                printf "%s\n" "$(color red "Error: Failed to load script '$MAP_E_SCRIPT_NAME'.")" >&2 # MODIFIED: Use color()
                exit_code=1
            fi
            ;;
        "ds-lite")
            # DS-Lite 設定処理 (AFTRとキーを渡して呼び出し)
            debug_log "DEBUG" "DS-Lite connection confirmed. Loading DS-Lite script..." 
            # Source the DS-Lite script
            # shellcheck source=/dev/null
            if . "$DS_LITE_SCRIPT"; then
                 # Check if the apply function exists
                if command -v apply_dslite_settings >/dev/null 2>&1; then
                    debug_log "DEBUG" "Executing apply_dslite_settings function from $DS_LITE_SCRIPT_NAME with AFTR: $aftr_address, Key: $provider_key"
                    # Execute the configuration function from internet-ds-lite-config.sh
                    if apply_dslite_settings "$aftr_address" "$provider_key"; then
                        debug_log "DEBUG" "DS-Lite script executed successfully." 
                        # No explicit success message needed
                    else
                        debug_log "DEBUG" "DS-Lite script execution failed." # ERROR -> DEBUG
                        printf "%s\n" "$(color red "Error: Execution of script '$DS_LITE_SCRIPT_NAME' failed.")" >&2 # MODIFIED: Use color()
                        exit_code=1
                    fi
                else
                    debug_log "DEBUG" "Function 'apply_dslite_settings' not found in $DS_LITE_SCRIPT_NAME." # ERROR -> DEBUG
                    printf "%s\n" "$(color red "Error: Required function 'apply_dslite_settings' not found in script '$DS_LITE_SCRIPT_NAME'.")" >&2 # MODIFIED: Use color()
                    exit_code=1
                fi
            else
                debug_log "DEBUG" "Failed to source DS-Lite script: $DS_LITE_SCRIPT_NAME" # ERROR -> DEBUG
                printf "%s\n" "$(color red "Error: Failed to load script '$DS_LITE_SCRIPT_NAME'.")" >&2 # MODIFIED: Use color()
                exit_code=1
            fi
            ;;
        "unknown")
            # Unknown 処理 (get_message を使用)
            debug_log "DEBUG" "Could not automatically determine the IPoE connection type for ASN $asn."
            # Placeholder: as (AS Number)
            printf "%s\n" "$(color yellow "$(get_message "MSG_AUTO_CONFIG_UNKNOWN" as="$asn")")"
            exit_code=1 # Indicate failure or inability to auto-configure
            ;;
        *) # Should not happen
            debug_log "DEBUG" "Unexpected connection type returned: $connection_type" # ERROR -> DEBUG
            printf "%s\n" "$(color red "Error: Unexpected value encountered: $connection_type")" >&2 # MODIFIED: Use color()
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
