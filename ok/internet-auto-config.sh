#!/bin/sh

SCRIPT_VERSION="2025.05.17-00-11"

PROVIDER_DATABASE_CONTENT=""
PROVIDER_DATABASE_INITIALIZED="false"

provider_data_definitions() {
    add_provider_record "4713|nttcom|NTT Communications|map-e|download internet-map-e.sh chmod load; internet_map_main"
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
    # ...（変数宣言・初期化）

    # 失敗時やN選択時は「manual_menu」変数に"1"をセット
    local manual_menu_needed=0

    # -- AS番号ファイル未発見
    if [ ! -f "${CACHE_DIR}/isp_as.ch" ]; then
        printf "\n%s\n" "$(color yellow "AS number cache file not found.")"
        manual_menu_needed=1
    else
        asn=$(cat "${CACHE_DIR}/isp_as.ch")
        if [ -z "$asn" ]; then
            printf "\n%s\n" "$(color yellow "AS number is empty.")"
            manual_menu_needed=1
        else
            connection_info=$(determine_connection_as "$asn")
            connection_type=$(echo "$connection_info" | cut -d'|' -f1)
            provider_key=$(echo "$connection_info" | cut -d'|' -f2)
            display_isp_name=$(echo "$connection_info" | cut -d'|' -f3)
            command_to_execute=$(echo "$connection_info" | cut -d'|' -f4)

            if [ "$connection_type" = "unknown" ]; then
                printf "\n%s\n" "$(color yellow "Unknown provider. Please select manually.")"
                manual_menu_needed=1
            else
                printf "\n%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" sp="$display_isp_name" tp="$connection_type")")"
                confirm "MSG_AUTO_CONFIG_CONFIRM"
                local confirm_status=$?
                if [ $confirm_status -ne 0 ]; then
                    manual_menu_needed=1
                else
                    eval "$command_to_execute"
                    [ $? -ne 0 ] && printf "\n%s\n" "$(color yellow "Command failed.")"
                fi
            fi
        fi
    fi

    # --- 集約: manual_menu_neededが1なら手動メニュー
    if [ "$manual_menu_needed" -eq 1 ]; then
        selector MENU_INTERNET
    fi
    return 0
}

internet_auto_config_main
