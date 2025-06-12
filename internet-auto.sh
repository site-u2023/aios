#!/bin/sh

SCRIPT_VERSION="2025.06.05-00-00"

# OpenWrt network helper functions
. /lib/functions/network.sh

PROVIDER_DATABASE_CONTENT=""
PROVIDER_DATABASE_INITIALIZED="false"

provider_data_definitions() {   
    add_provider_record "2518|240b::/16| |v6plus|v6 Plus|map-e|download internet-mape.sh chmod load; internet_map_main"
    add_provider_record "7413|2404:7a80::/30|gw.transix.jp|biglobe_dslite|BIGLOBE|ds-lite|download internet-dslite.sh chmod load; internet_dslite_main"
    add_provider_record "7413|2404:7a84::/30| |biglobe_mape|BIGLOBE|map-e|download internet-mape.sh chmod load; internet_map_main"
    add_provider_record "4713|2400:4150::/30| |ocn|OCN Virtual Connect|map-e|download internet-mape.sh chmod load; internet_map_main"
    add_provider_record "2519|2409:10::/28| |transix_dslite|transix|ds-lite|download internet-dslite.sh chmod load; internet_dslite_main"
    add_provider_record "2527|2001:f70::/29| |cross_dslite|Cross Pass|ds-lite|download internet-dslite.sh chmod load; internet_dslite_main"
    add_provider_record "4737|2405:6580::/29| |v6connect_dslite|v6 Connect|ds-lite|download internet-dslite.sh chmod load; internet_dslite_main"
    add_provider_record "2519|2409:250::/28|gw.transix.jp|transix_generic_dslite|transix|ds-lite|download internet-dslite.sh chmod load; internet_dslite_main"
    add_provider_record "2527|2001:0f70::/29|xpass.jp|cross_generic_dslite|Cross Pass|ds-lite|download internet-dslite.sh chmod load; internet_dslite_main"
    add_provider_record "4737|2405:6580::/29|gw.v6connect.jp|v6connect_generic_dslite|v6 Connect|ds-lite|download internet-dslite.sh chmod load; internet_dslite_main"
    add_provider_record "2515|240d:f::/32| |nuro|NURO Hikari|map-e|download internet-mape.sh chmod load; internet_map_main"
    add_provider_record "2497|2404:8e00::/32| |iijmio|IIJmio|map-e|download internet-mape.sh chmod load; internet_map_main"
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
    local numeric_asn=""

    # Remove "AS" prefix if present
    if echo "$search_asn" | grep -q "^AS"; then
        numeric_asn=$(echo "$search_asn" | sed 's/^AS//')
    else
        numeric_asn="$search_asn"
    fi
    debug_log "DEBUG" "get_provider_data_by_as: Original ASN:[$search_asn], Numeric ASN for search:[$numeric_asn]"


    if [ "$PROVIDER_DATABASE_INITIALIZED" = "false" ]; then
        provider_data_definitions
        PROVIDER_DATABASE_INITIALIZED="true"
    fi

    if [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
        # Use numeric_asn for grep
        result=$(echo "$PROVIDER_DATABASE_CONTENT" | grep "^${numeric_asn}|" | head -n 1)
    else
        result=""
    fi

    if [ -n "$result" ]; then
        debug_log "DEBUG" "get_provider_data_by_as: Found data for NumericASN $numeric_asn: $result"
        echo "$result"
        return 0
    else
        debug_log "DEBUG" "get_provider_data_by_as: No data found for NumericASN $numeric_asn"
        return 1
    fi
}

determine_connection_auto() {
    local input_asn="$1"
    local input_pd="$2"
    local input_aftr="$3"
    local numeric_asn=""

    # Remove "AS" prefix if present
    if echo "$input_asn" | grep -q "^AS"; then
        numeric_asn=$(echo "$input_asn" | sed 's/^AS//')
    else
        numeric_asn="$input_asn"
    fi

    debug_log "DEBUG" "determine_connection_auto: Entry - OrigASN:[$input_asn], NumericASN:[$numeric_asn], PD:[$input_pd], AFTR:[$input_aftr]"

    if [ "$PROVIDER_DATABASE_INITIALIZED" = "false" ]; then
        debug_log "DEBUG" "determine_connection_auto: Initializing provider database."
        provider_data_definitions
        PROVIDER_DATABASE_INITIALIZED="true"
        if [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
            debug_log "DEBUG" "determine_connection_auto: Provider database initialized and content is present."
        else
            debug_log "ERROR" "determine_connection_auto: Provider database initialized but content is EMPTY." # Changed to ERROR
            # データベースが空の場合、これ以上進んでも意味がないため早期リターンも検討可
            # echo "unknown|unknown|unknown|"
            # return
        fi
    else
        debug_log "DEBUG" "determine_connection_auto: Provider database already initialized."
    fi

    local result=""

    # 判定の優先順位:
    # 1. AFTR名が明確に一致するルール (DS-Liteなど、BIGLOBE DS-Liteもここで合致期待)
    # 2. 【新規】BIGLOBE MAP-E の特別ルール (AS7413 かつ AFTR名が空の場合)
    # 3. AS番号とPDプレフィックスが一致するルール (MAP-Eなど)
    # 4. AS番号のみが一致するルール
    # 5. PDプレフィックスのみが一致するルール

    # 1. AFTR name match
    #    ルール: DBのAFTR名フィールド($3)が空でなく、入力AFTR名(aftr_val)と一致する。
    debug_log "DEBUG" "determine_connection_auto: Step 1: Attempting specific AFTR match with AFTR:[$input_aftr]"
    if [ -n "$input_aftr" ] && [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
        result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v aftr_val="$input_aftr" \
            '{if($3!="" && $3==aftr_val){print $6 "|" $4 "|" $5 "|" $7; exit}}')
        if [ -n "$result" ]; then
            debug_log "DEBUG" "determine_connection_auto: Step 1: Specific AFTR match found: [$result]"
        else
            debug_log "DEBUG" "determine_connection_auto: Step 1: No specific AFTR match found for AFTR:[$input_aftr]"
        fi
    else
        debug_log "DEBUG" "determine_connection_auto: Step 1: Skipping specific AFTR match (input_aftr or DB content empty)."
    fi

    # 2. BIGLOBE MAP-E specific rule: AS=7413 AND input_aftr is empty
    #    ルール: DBのASフィールド($1)が"7413"、PDフィールド($2)が空、AFTRフィールド($3)が空。
    if [ -z "$result" ]; then # Only if previous step didn't find a match
        debug_log "DEBUG" "determine_connection_auto: Step 2: Attempting BIGLOBE MAP-E rule with NumericASN:[$numeric_asn], AFTR:[$input_aftr]"
        if [ "$numeric_asn" = "7413" ] && [ -z "$input_aftr" ] && [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
            result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' \
                '{if($1=="7413" && $2=="" && $3==""){print $6 "|" $4 "|" $5 "|" $7; exit}}')
            if [ -n "$result" ]; then
                debug_log "DEBUG" "determine_connection_auto: Step 2: BIGLOBE MAP-E (AS 7413, empty AFTR) match found: [$result]"
            else
                debug_log "DEBUG" "determine_connection_auto: Step 2: No BIGLOBE MAP-E rule match found (AS 7413, empty AFTR)."
            fi
        else
             debug_log "DEBUG" "determine_connection_auto: Step 2: Skipping BIGLOBE MAP-E rule (conditions not met: ASN!=7413 or AFTR not empty or DB empty)."
        fi
    fi

    # 3. AS+PD match
    #    ルール: DBのASフィールド($1)が入力AS番号(asn_val)と一致し、
    #            DBのPDフィールド($2)が空でなく、入力PDプレフィックス(pd_val)の先頭部分と一致する。
    if [ -z "$result" ]; then
        debug_log "DEBUG" "determine_connection_auto: Step 3: Attempting AS+PD match with NumericASN:[$numeric_asn], PD:[$input_pd]"
        if [ -n "$numeric_asn" ] && [ -n "$input_pd" ] && [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
            result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v asn_val="$numeric_asn" -v pd_val="$input_pd" \
                '{if($1==asn_val && $2!="" && index(pd_val,$2)==1){print $6 "|" $4 "|" $5 "|" $7; exit}}')
            if [ -n "$result" ]; then
                debug_log "DEBUG" "determine_connection_auto: Step 3: AS+PD match found: [$result]"
            else
                debug_log "DEBUG" "determine_connection_auto: Step 3: No AS+PD match found for NumericASN:[$numeric_asn], PD:[$input_pd]"
            fi
        else
            debug_log "DEBUG" "determine_connection_auto: Step 3: Skipping AS+PD match (NumericASN, PD or DB content empty)."
        fi
    fi

    # 4. AS only match
    #    ルール: DBのASフィールド($1)が入力AS番号(asn_val)と一致する。
    if [ -z "$result" ]; then
        debug_log "DEBUG" "determine_connection_auto: Step 4: Attempting AS only match with NumericASN:[$numeric_asn]"
        if [ -n "$numeric_asn" ] && [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
            result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v asn_val="$numeric_asn" \
                '{if($1==asn_val){print $6 "|" $4 "|" $5 "|" $7; exit}}')
            if [ -n "$result" ]; then
                debug_log "DEBUG" "determine_connection_auto: Step 4: AS only match found: [$result]"
            else
                debug_log "DEBUG" "determine_connection_auto: Step 4: No AS only match found for NumericASN:[$numeric_asn]"
            fi
        else
            debug_log "DEBUG" "determine_connection_auto: Step 4: Skipping AS only match (NumericASN or DB content empty)."
        fi
    fi

    # 5. PD only match
    #    ルール: DBのPDフィールド($2)が空でなく、入力PDプレフィックス(pd_val)の先頭部分と一致する。
    if [ -z "$result" ]; then
        debug_log "DEBUG" "determine_connection_auto: Step 5: Attempting PD only match with PD:[$input_pd]"
        if [ -n "$input_pd" ] && [ -n "$PROVIDER_DATABASE_CONTENT" ]; then
            result=$(echo "$PROVIDER_DATABASE_CONTENT" | awk -F'|' -v pd_val="$input_pd" \
                '{if($2!="" && index(pd_val,$2)==1){print $6 "|" $4 "|" $5 "|" $7; exit}}')
            if [ -n "$result" ]; then
                debug_log "DEBUG" "determine_connection_auto: Step 5: PD only match found: [$result]"
            else
                # 元のコードではこのケースのログがなかったので、整合性のために追加
                debug_log "DEBUG" "determine_connection_auto: Step 5: No PD only match found for PD:[$input_pd]"
            fi
        else
            debug_log "DEBUG" "determine_connection_auto: Step 5: Skipping PD only match (PD or DB content empty)."
        fi
    fi

    # 6. Unknown
    if [ -z "$result" ]; then
        debug_log "DEBUG" "determine_connection_auto: Step 6: No specific match found. Setting result to unknown."
        result="unknown|unknown|unknown|" # コマンドフィールドも空にするため、末尾の|を追加
    fi

    debug_log "DEBUG" "determine_connection_auto: Exit - Result:[$result]"
    echo "$result"
}


internet_auto_config_main() {
    local manual_menu_needed=0
    local asn=""
    local device_info=""
    local aftr_name=""
    local pd_prefix=""
    local global_ipv6="" 
    local connection_info=""
    local connection_type=""
    local provider_key=""
    local display_isp_name=""
    local command_to_execute=""

    if [ ! -f "${CACHE_DIR}/isp_as.ch" ]; then
        printf "\n"
        printf "%s\n" "$(color yellow "AS number cache file not found.")" 
        manual_menu_needed=1
    else
        asn=$(cat "${CACHE_DIR}/isp_as.ch")
        if [ -z "$asn" ]; then
            printf "\n"
            printf "%s\n" "$(color yellow "AS number is empty.")" 
            manual_menu_needed=1
        else
            device_info=$(get_device_network_info) 
            aftr_name=$(echo "$device_info" | cut -d'|' -f1)
            pd_prefix=$(echo "$device_info" | cut -d'|' -f2)
            global_ipv6=$(echo "$device_info" | cut -d'|' -f4) 

            connection_info=$(determine_connection_auto "$asn" "$pd_prefix" "$aftr_name")
            connection_type=$(echo "$connection_info" | cut -d'|' -f1)
            provider_key=$(echo "$connection_info" | cut -d'|' -f2)
            display_isp_name=$(echo "$connection_info" | cut -d'|' -f3)
            command_to_execute=$(echo "$connection_info" | cut -d'|' -f4)

            if [ "$connection_type" = "unknown" ]; then
                local diagnostic_info_a=""
                if [ -n "$asn" ]; then
                    diagnostic_info_a="AS: $asn"
                fi

                local pd_or_v6_info=""
                if [ -n "$pd_prefix" ] && [ "$pd_prefix" != "/" ]; then
                    pd_or_v6_info="PD: $pd_prefix"
                elif [ -n "$global_ipv6" ]; then
                    pd_or_v6_info="V6: $global_ipv6"
                fi

                if [ -n "$pd_or_v6_info" ]; then
                    if [ -n "$diagnostic_info_a" ]; then
                        diagnostic_info_a="$diagnostic_info_a $pd_or_v6_info"
                    else
                        diagnostic_info_a="$pd_or_v6_info"
                    fi
                fi

                if [ -n "$aftr_name" ]; then
                    if [ -n "$diagnostic_info_a" ]; then
                        diagnostic_info_a="$diagnostic_info_a $aftr_name"
                    else
                        diagnostic_info_a="AFTR: $aftr_name"
                    fi
                fi

                [ -z "$diagnostic_info_a" ] && diagnostic_info_a="N/A"
                
                local raw_msg_content_for_display
                raw_msg_content_for_display=$(get_message "MSG_AUTO_CONFIG_UNKNOWN" a="$diagnostic_info_a")
                printf "\n%s\n" "$(color yellow "$raw_msg_content_for_display")"
                manual_menu_needed=1
            else
                printf "\n"
                printf "%s\n" "$(color green "$(get_message "MSG_AUTO_CONFIG_RESULT" s="$display_isp_name" t="$connection_type")")"
                printf "\n"
                confirm "MSG_AUTO_CONFIG_CONFIRM"
                local confirm_status=$?
                if [ $confirm_status -ne 0 ]; then
                    manual_menu_needed=1
                else
                    eval "$command_to_execute"
                    [ $? -ne 0 ] && printf "\n%s\n" "$(color yellow "Command execution failed.")" 
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
