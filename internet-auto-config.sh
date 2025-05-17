#!/bin/sh

SCRIPT_VERSION="2025.05.17-00-11"

PROVIDER_DATABASE_CONTENT=""
PROVIDER_DATABASE_INITIALIZED="false"

provider_data_definitions() {
    add_provider_record "4713|ocn|OCN Virtual Connect|map-e|download internet-map-e.sh chmod load; internet_map_main"
    add_provider_record "2518|v6plus|v6 Plus|map-e|download internet-map-e.sh chmod load; internet_map_main"
    add_provider_record "2519|transix|transix|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main"
    add_provider_record "2527|cross|Cross Pass|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main" 
    add_provider_record "4737|v6connect|v6 Connect|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main" 
    add_provider_record "2515|nuro|NURO Hikari|map-e|download internet-map-e-nuro.sh chmod load; internet_map_nuro_main"
}

add_provider_record() {
    if [ -n "$1" ]; then
        PROVIDER_DATABASE_CONTENT="${PROVIDER_DATABASE_CONTENT}$1"$'\n'
    fi
}

get_provider_data_by_as() {
    local search_asn="$1"
    local result=""

    if [ "$PROVIDER_DATABASE_INITIALIZED" = "false" ]; then
        provider_data_definitions
        PROVIDER_DATABASE_INITIALIZED="true"
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
    local display_name="Unknown Provider"
    local command_to_execute=""

    debug_log "DEBUG" "Determining connection type for Input ASN: $input_asn"

    if [ -z "$input_asn" ]; then
        debug_log "DEBUG" "ASN is empty, cannot determine connection type."
        echo "unknown||Unknown Provider|" 
        return 1
    fi

    numeric_asn=$(echo "$input_asn" | sed 's/^AS//i')
    provider_data=$(get_provider_data_by_as "$numeric_asn") 

    if [ $? -eq 0 ] && [ -n "$provider_data" ]; then
        conn_type=$(echo "$provider_data" | cut -d'|' -f4)
        internal_key=$(echo "$provider_data" | cut -d'|' -f2)
        display_name=$(echo "$provider_data" | cut -d'|' -f3)
        command_to_execute=$(echo "$provider_data" | cut -d'|' -f5)
        
        debug_log "DEBUG" "Parsed data: Type=$conn_type, Key=$internal_key, Name=$display_name, Command='$command_to_execute'"
    else
        debug_log "DEBUG" "ASN $numeric_asn not found in provider database. Type set to 'unknown'."
    fi

    echo "${conn_type}|${internal_key}|${display_name}|${command_to_execute}"
    return 0
}

internet_auto_config_main() {
    local asn=""
    local connection_info=""
    local connection_type=""
    local provider_key="" 
    local display_isp_name=""
    local command_to_execute=""
    local exit_code=0

    debug_log "DEBUG" "Starting automatic internet configuration detection process (Version: $SCRIPT_VERSION)"

    debug_log "DEBUG" "Checking prerequisites..."
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    if [ ! -f "$ip_type_file" ]; then
        debug_log "DEBUG" "IP type cache file not found: ${ip_type_file}."
    fi
    if [ ! -f "${CACHE_DIR}/isp_as.ch" ]; then
        debug_log "DEBUG" "AS number cache file not found: ${CACHE_DIR}/isp_as.ch."
        echo "unknown||"
        return 1
    fi

    debug_log "DEBUG" "Retrieving AS number..."
    asn=$(cat "${CACHE_DIR}/isp_as.ch")
    if [ -z "$asn" ]; then
        debug_log "DEBUG" "Failed to retrieve AS number from cache, or cache file is empty."
        # 同上
        echo "unknown||"
        return 1
    fi
    debug_log "DEBUG" "Detected AS Number: $asn"
    
    debug_log "DEBUG" "Determining connection type and command string..."
    connection_info=$(determine_connection_as "$asn")
    
    connection_type=$(echo "$connection_info" | cut -d'|' -f1)
    provider_key=$(echo "$connection_info" | cut -d'|' -f2) 
    display_isp_name=$(echo "$connection_info" | cut -d'|' -f3)
    command_to_execute=$(echo "$connection_info" | cut -d'|' -f4)

    debug_log "DEBUG" "Determined: Type='$connection_type', Key='$provider_key', Name='$display_isp_name', Command='$command_to_execute'"

    if [ "$connection_type" != "unknown" ]; then
        local final_display_name_for_msg="$display_isp_name"
        if [ -z "$final_display_name_for_msg" ] || [ "$final_display_name_for_msg" = "Unknown Provider" ]; then
             if [ -n "$provider_key" ]; then
                final_display_name_for_msg="$provider_key (key)"
             else
                final_display_name_for_msg="Unknown Provider"
             fi
        fi
        printf "\n%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$final_display_name_for_msg" tp="$connection_type")")"

        if [ -n "$command_to_execute" ]; then
            debug_log "DEBUG" "Preparing to execute command: $command_to_execute"
            
            local eval_status
            eval "$command_to_execute"
            eval_status=$?

            if [ $eval_status -eq 0 ]; then
                debug_log "DEBUG" "Command executed successfully."
                exit_code=0
            else
                debug_log "DEBUG" "Command execution failed with status $eval_status."
                exit_code=1
            fi
        else
            debug_log "DEBUG" "No command string defined for connection type '$connection_type' with key '$provider_key'."
        fi
    else 
        local unknown_display_name_for_msg="$display_isp_name"
        if [ "$unknown_display_name_for_msg" = "Unknown Provider" ] && [ -n "$asn" ]; then
            unknown_display_name_for_msg="AS$asn"
        elif [ -z "$unknown_display_name_for_msg" ]; then
             unknown_display_name_for_msg="N/A"
        fi
        printf "\n%s\n" "$(color yellow "$(get_message "MSG_AUTO_CONFIG_UNKNOWN" as="$asn" sp="$unknown_display_name_for_msg")")"
        exit_code=1
    fi

    echo "${connection_type}|${provider_key}|${display_isp_name}" 
    return $exit_code
}

internet_auto_config_main
