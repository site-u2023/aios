#!/bin/sh

SCRIPT_VERSION="2025.05.17-00-00"

PROVIDER_DATABASE_CONTENT=""
PROVIDER_DATABASE_INITIALIZED="false"

provider_data_definitions() {
    add_provider_record "4713|ocn|OCN Virtual Connect|map-e|"
    add_provider_record "2518|v6plus|v6 Plus|map-e|"
    add_provider_record "2519|transix|transix|ds-lite|gw.transix.jp"
    add_provider_record "2527|cross|Cross Pass|ds-lite|2001:f60:0:200::1:1"
    add_provider_record "4737|v6connect|v6 Connect|ds-lite|gw.v6connect.net"
    add_provider_record "2515|nuro|NURO Hikari|map-e|"
}

add_provider_record() {
    if [ -n "$1" ]; then
        PROVIDER_DATABASE_CONTENT="${PROVIDER_DATABASE_CONTENT}${1}
    fi
}

get_provider_data_by_as() {
    local search_asn="$1"
    local result=""

    if [ "$PROVIDER_DATABASE_INITIALIZED" = "false" ]; then
        provider_data_definitions
        PROVIDER_DATABASE_INITIALIZED="true" # provider_data_definitions 呼び出し後にフラグを立てる
    fi

    if [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
        result=$(echo "$PROVIDER_DATABASE_CONTENT" | grep "^${search_asn}|" | head -n 1)
    else
        result="" 
    fi

    if [ -n "$result" ]; then
        debug_log "DEBUG" "get_provider_data_by_as: Found data for ASN $search_asn: $result"
        echo "$result"
        return 0
    else
        debug_log "DEBUG" "get_provider_data_by_as: No data found for ASN $search_asn"
        return 1
    fi
}

determine_connection_as() {
    local input_asn="$1"
    local numeric_asn=""
    local provider_data=""
    local conn_type="unknown"
    local internal_key=""
    local aftr_addr=""
    local display_name="Unknown Provider"

    debug_log "DEBUG" "Determining connection type for Input ASN: $input_asn"

    if [ -z "$input_asn" ]; then
        debug_log "ERROR" "ASN is empty, cannot determine connection type."
        echo "unknown|||$display_name"
        return 1
    fi

    numeric_asn=$(echo "$input_asn" | sed 's/^AS//i')
    provider_data=$(get_provider_data_by_as "$numeric_asn")

    if [ $? -eq 0 ] && [ -n "$provider_data" ]; then
        # Fields: 1:AS, 2:KEY, 3:DISPLAY_NAME, 4:TYPE, 5:AFTR
        conn_type=$(echo "$provider_data" | cut -d'|' -f4)
        internal_key=$(echo "$provider_data" | cut -d'|' -f2)
        display_name=$(echo "$provider_data" | cut -d'|' -f3) # Get display name from DB
        aftr_addr=$(echo "$provider_data" | cut -d'|' -f5)

        debug_log "DEBUG" "Parsed data: Type=$conn_type, Key=$internal_key, AFTR=$aftr_addr, Name=$display_name"
    else
        debug_log "WARN" "ASN $numeric_asn not found in provider database. Type set to 'unknown'." # Changed DEBUG to WARN
    fi

    echo "${conn_type}|${internal_key}|${aftr_addr}|${display_name}"
    return 0
}

internet_auto_config_main() {
    local asn=""
    local connection_info=""
    local connection_type=""
    local provider_key=""
    local aftr_address_from_db=""
    local display_isp_name=""
    local exit_code=0

    debug_log "DEBUG" "Starting automatic internet configuration detection process..."

    debug_log "DEBUG" "Checking prerequisites..."

    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    if [ ! -f "$ip_type_file" ]; then
        debug_log "WARN" "IP type cache file not found: ${ip_type_file}. This might affect context for the calling script."
    fi
    if [ ! -f "${CACHE_DIR}/isp_as.ch" ]; then
        debug_log "ERROR" "AS number cache file not found: ${CACHE_DIR}/isp_as.ch. Cannot proceed with detection."
        echo "unknown|||AS cache missing"
        return 1
    fi

    debug_log "DEBUG" "Retrieving AS number..."
    asn=$(cat "${CACHE_DIR}/isp_as.ch")
    if [ -z "$asn" ]; then
        debug_log "ERROR" "Failed to retrieve AS number from cache, or cache file is empty."
        echo "unknown|||AS cache read error"
        return 1
    fi
    debug_log "INFO" "Detected AS Number: $asn"

    debug_log "DEBUG" "Determining connection type using ASN..."
    connection_info=$(determine_connection_as "$asn")
    
    connection_type=$(echo "$connection_info" | cut -d'|' -f1)
    provider_key=$(echo "$connection_info" | cut -d'|' -f2)
    aftr_address_from_db=$(echo "$connection_info" | cut -d'|' -f3)
    display_isp_name=$(echo "$connection_info" | cut -d'|' -f4)

    debug_log "INFO" "Determined: Type='$connection_type', Key='$provider_key', AFTR_DB='$aftr_address_from_db', DisplayName='$display_isp_name'"

    if [ "$connection_type" != "unknown" ]; then
        local final_display_name_for_msg="$display_isp_name"
        if [ -z "$final_display_name_for_msg" ] || [ "$final_display_name_for_msg" = "Unknown Provider" ]; then
             if [ -n "$provider_key" ]; then
                final_display_name_for_msg="$provider_key (key)"
             else
                final_display_name_for_msg="Unknown Provider"
             fi
        fi
        printf "%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$final_display_name_for_msg" tp="$connection_type")")"
        exit_code=0
    else
        printf "%s\n" "$(color yellow "$(get_message "MSG_AUTO_CONFIG_UNKNOWN" as="$asn" sp="$display_isp_name")")"
        exit_code=1
    fi

    echo "${connection_type}|${provider_key}|${aftr_address_from_db}|${display_isp_name}"
    
    if [ "$exit_code" -eq 0 ]; then
        debug_log "INFO" "Automatic internet configuration detection process completed. Results passed to stdout."
    else
        debug_log "WARN" "Automatic internet configuration detection process completed with 'unknown' type. Results passed to stdout."
    fi

    return $exit_code
}
