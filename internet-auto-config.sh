#!/bin/sh

SCRIPT_VERSION="2025.05.17-00-11"

# OpenWrt network helper functions
. /lib/functions/network.sh

PROVIDER_DATABASE_CONTENT=""
PROVIDER_DATABASE_INITIALIZED="false"

provider_data_definitions() {
    # AS番号|PD条件|AFTR名|内部キー|表示名|方式|コマンド
    # 設定可能ISPのみコマンド記述、未対応は空欄
    add_provider_record "2518|2404:8e00::/28||v6plus|v6 Plus (JPNE)|map-e|download internet-map-e.sh chmod load; internet_map_main"
    add_provider_record "2515|240b:10:200::/40||nuro|NURO Hikari|map-e|download internet-map-e-nuro.sh chmod load; internet_map_nuro_main"
    add_provider_record "4713|240d:1a::/28||ocn|OCN MAP-E|map-e|download internet-map-e.sh chmod load; internet_map_main"
    add_provider_record "2519|||transix|transix|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main"
    add_provider_record "2527|||cross|Cross Pass|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main"
    add_provider_record "4737|||v6connect|v6 Connect|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main"
    # 例: DS-Lite AFTR名判定
    add_provider_record "||gw.transix.jp|transix|transix|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main"
    add_provider_record "||xpass.jp|cross|Cross Pass|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main"
    add_provider_record "||gw.v6connect.jp|v6connect|v6 Connect|ds-lite|download internet-ds-lite-config.sh chmod load; internet_dslite_main"
    # 設定未対応例
    add_provider_record "4713|240d:1a::/28||plala|Plala MAP-E|map-e|"
}

get_device_network_info() {
    # WAN6インターフェース名を自動判定
    local net_if6=""
    network_find_wan6 net_if6
    [ -z "$net_if6" ] && net_if6="wan6" # フォールバック

    # PD（Prefix Delegation）取得
    local pd_prefix=""
    network_get_prefix6 pd_prefix "$net_if6"

    # グローバルIPv6アドレス取得（参考用）
    local global_ipv6=""
    network_get_ipaddr6 global_ipv6 "$net_if6"

    # AFTR名（DS-Lite/MAP-E時）取得
    local aftr_name=""
    if [ -x /sbin/ifstatus ]; then
        aftr_name=$(ifstatus "$net_if6" 2>/dev/null | grep -o '"aftr": *"[^"]*"' | sed 's/"aftr": *"\([^"]*\)"/\1/')
    fi
    [ -z "$aftr_name" ] && aftr_name=$(uci -q get network.dslite.peeraddr 2>/dev/null)
    [ -z "$aftr_name" ] && aftr_name=$(uci -q get network.map.peeraddr 2>/dev/null)

    # 結果をエコー（フォーマット: aftr|pd|wan6|global_ipv6）
    printf "%s|%s|%s|%s\n" "${aftr_name:-}" "${pd_prefix:-}" "${net_if6:-}" "${global_ipv6:-}"
}

get_provider_data_by_aftr() {
    local aftr_name="$1"
    local result=""
    if [ "$PROVIDER_DATABASE_INITIALIZED" = "false" ]; then
        provider_data_definitions
        PROVIDER_DATABASE_INITIALIZED="true"
    fi
    if [ -n "$aftr_name" ] && [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
        result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v aftr="$aftr_name" '{ if (tolower($5) ~ tolower(aftr)) { print $0; exit } }')
    fi
    if [ -n "$result" ]; then
        debug_log "DEBUG" "get_provider_data_by_aftr: Found data for AFTR $aftr_name: $result"
        echo "$result"
        return 0
    else
        debug_log "DEBUG" "get_provider_data_by_aftr: No data found for AFTR $aftr_name"
        return 1
    fi
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

determine_connection_auto() {
    local input_asn="$1"
    local input_pd="$2"
    local input_aftr="$3"
    local PROVIDER_DATABASE_CONTENT=""
    provider_data_definitions

    local result=""

    # 1. AFTR名一致
    if [ -n "$input_aftr" ]; then
        result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v aftr="$input_aftr" '{if($3==aftr){print $6 "|" $4 "|" $5 "|" $7; exit}}')
    fi

    # 2. AS+PD一致
    if [ -z "$result" ] && [ -n "$input_asn" ] && [ -n "$input_pd" ]; then
        result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v asn="$input_asn" -v pd="$input_pd" '{if($1==asn && index(pd,$2)==1){print $6 "|" $4 "|" $5 "|" $7; exit}}')
    fi

    # 3. ASのみ一致
    if [ -z "$result" ] && [ -n "$input_asn" ]; then
        result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v asn="$input_asn" '{if($1==asn){print $6 "|" $4 "|" $5 "|" $7; exit}}')
    fi

    # 4. PDのみ一致
    if [ -z "$result" ] && [ -n "$input_pd" ]; then
        result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v pd="$input_pd" '{if(index(pd,$2)==1){print $6 "|" $4 "|" $5 "|" $7; exit}}')
    fi

    # 5. 不明
    if [ -z "$result" ]; then
        result="unknown|unknown|unknown|"
    fi

    echo "$result"
}

internet_auto_config_main() {
    # ...（変数宣言・初期化）

    local manual_menu_needed=0

    if [ ! -f "${CACHE_DIR}/isp_as.ch" ]; then
        printf "\n%s\n" "$(color yellow "AS number cache file not found.")"
        manual_menu_needed=1
    else
        asn=$(cat "${CACHE_DIR}/isp_as.ch")
        if [ -z "$asn" ]; then
            printf "\n%s\n" "$(color yellow "AS number is empty.")"
            manual_menu_needed=1
        else
            # --- ここでPD・AFTR名も取得
            device_info=$(get_device_network_info)
            aftr_name=$(echo "$device_info" | cut -d'|' -f1)
            pd_prefix=$(echo "$device_info" | cut -d'|' -f2)
            # asnは従来通り
            connection_info=$(determine_connection_auto "$asn" "$pd_prefix" "$aftr_name")
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

    if [ "$manual_menu_needed" -eq 1 ]; then
        selector MENU_INTERNET
    fi
    return 0
}
internet_auto_config_main
