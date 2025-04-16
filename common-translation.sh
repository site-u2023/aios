#!/bin/sh

SCRIPT_VERSION="2025-04-12-00-05"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-29
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 24.10.0)
#
# ⚠️ IMPORTANT NOTICE:
# OpenWrt OS exclusively uses **Almquist Shell (ash)** and
# is **NOT** compatible with Bourne-Again Shell (bash).
#
# 📢 POSIX Compliance Guidelines:
# ✅ Use `[` instead of `[[` for conditions
# ✅ Use $(command) instead of backticks `command`
# ✅ Use $(( )) for arithmetic instead of let
# ✅ Define functions as func_name() {} (no function keyword)
# ✅ No associative arrays (declare -A is NOT supported)
# ✅ No here-strings (<<< is NOT supported)
# ✅ No -v flag in test or [[
# ✅ Avoid bash-specific string operations like ${var:0:3}　
# ✅ Avoid arrays entirely when possible (even indexed arrays can be problematic)
# ✅ Use printf followed by read instead of read -p
# ✅ Use printf instead of echo -e for portable formatting
# ✅ Avoid process substitution <() and >()
# ✅ Prefer case statements over complex if/elif chains
# ✅ Use command -v instead of which or type for command existence checks
# ✅ Keep scripts modular with small, focused functions
# ✅ Use simple error handling instead of complex traps
# ✅ Test scripts with ash/dash explicitly, not just bash
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
### =========================================================

# 基本定数の設定 
BASE_WGET="wget --no-check-certificate -q"
DEBUG_MODE="${DEBUG_MODE:-false}"
BIN_PATH="$(readlink -f "$0")"
BIN_DIR="$(dirname "$BIN_PATH")"
BIN_FILE="$(basename "$BIN_PATH")"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# オンライン翻訳を有効化
ONLINE_TRANSLATION_ENABLED="yes"

# API設定
API_TIMEOUT="${API_TIMEOUT:-5}"
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"
TRANSLATION_CACHE_DIR="${BASE_DIR}/translations"
CURRENT_API=""

# API設定追加
GOOGLE_TRANSLATE_URL="${GOOGLE_TRANSLATE_URL:-https://translate.googleapis.com/translate_a/single}"
LINGVA_URL="${LINGVA_URL:-https://lingva.ml/api/v1}"
API_LIST="${API_LIST:-google}"

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# 言語コード取得（APIのため）
get_api_lang_code() {
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        local api_lang=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "Using language code from message.ch: ${api_lang}"
        printf "%s\n" "$api_lang"
        return 0
    fi
    debug_log "DEBUG" "No message.ch found, defaulting to en"
    printf "en\n"
}

# URL安全エンコード関数（seqを使わない最適化版）
urlencode() {
    local string="$1"
    local encoded=""
    local i=0
    local c=""
    local length=${#string}
    while [ $i -lt $length ]; do
        c=$(printf "%s" "$string" | cut -c $((i + 1)))
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded="${encoded}$c" ;;
            " ") encoded="${encoded}%20" ;;
            *) encoded="${encoded}$(printf "%%%02X" "'$c")" ;;
        esac
        i=$((i + 1))
    done
    printf "%s\n" "$encoded"
}

# API Workerを利用する翻訳関数（差し替え）
translate_with_api_worker() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local temp_req="${TRANSLATION_CACHE_DIR}/api_worker_req.txt"
    local temp_resp="${TRANSLATION_CACHE_DIR}/api_worker_resp.json"
    local result=""
    local api_url="https://translate-api-worker.site-u.workers.dev/translate"

    mkdir -p "$(dirname "$temp_req")" 2>/dev/null
    printf "%s\n" "$text" > "$temp_req"

    # texts配列形式のJSON生成
    local texts_json
    texts_json=$(awk 'BEGIN{ORS="";print "["} {gsub(/\\/,"\\\\",$0);gsub(/"/,"\\\"",$0);printf("%s\"%s\"", NR==1?"":",",$0)} END{print "]"}' "$temp_req")
    local post_body="{\"texts\":${texts_json},\"source\":\"${source_lang}\",\"target\":\"${target_lang}\"}"

    $BASE_WGET --header="Content-Type: application/json" \
        --post-data="$post_body" \
        -O "$temp_resp" -T $API_TIMEOUT "$api_url"

    # translations配列から1つ目を抽出
    result=$(awk 'BEGIN { inarray=0 }
        /"translations"[ ]*:/ { inarray=1; sub(/.*"translations"[ ]*:[ ]*\[/, ""); }
        inarray {
            gsub(/\r/,"");
            while(match($0, /("[^"]*"|null)/)) {
                val=substr($0, RSTART, RLENGTH)
                gsub(/^"/,"",val)
                gsub(/"$/,"",val)
                if(val=="null") print ""; else print val
                exit
            }
            if(match($0,/\]/)){ exit }
        }' "$temp_resp")

    rm -f "$temp_req" "$temp_resp"
    printf "%s\n" "$result"
}

# Google翻訳APIを使用した翻訳関数（元ソースからAPI Workerに置換）
translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    translate_with_api_worker "$text" "$source_lang" "$target_lang"
}

# Lingva Translate APIを使用した翻訳関数（API Workerに置換）
translate_with_lingva() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    translate_with_api_worker "$text" "$source_lang" "$target_lang"
}

# APIを選択して翻訳
translate_text() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local result=""
    API_NAME="translate-api-worker.site-u.workers.dev"
    result=$(translate_with_api_worker "$text" "$source_lang" "$target_lang")
    printf "%s" "$result"
}

create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local temp_file="${TRANSLATION_CACHE_DIR}/translation_output.tmp"
    local cleaned_translation=""
    local current_api=""
    local ip_check_file="${CACHE_DIR}/network.ch"

    debug_log "DEBUG" "Creating language DB for target ${target_lang} with API language code ${api_lang}"
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi

    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
EOF

    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" | sed "s/^${DEFAULT_LANGUAGE}|/${api_lang}|/" >> "$output_db"
        return 0
    fi

    printf "\n"

    if [ ! -f "$ip_check_file" ]; then
        debug_log "DEBUG" "Network status file not found, checking connectivity"
        check_network_connectivity
    fi

    local network_status=""
    if [ -f "$ip_check_file" ]; then
        network_status=$(cat "$ip_check_file")
        debug_log "DEBUG" "Network status: ${network_status}"
    else
        debug_log "DEBUG" "Could not determine network status"
    fi

    translate_text "dummy" "$DEFAULT_LANGUAGE" "$api_lang" > /dev/null 2>&1
    current_api="$API_NAME"
    if [ -z "$current_api" ]; then
        current_api="Translation API"
    fi

    start_spinner "$(color blue "Currently translating: $current_api")"

    grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do
        local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
        local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")
        if [ -n "$key" ] && [ -n "$value" ]; then
            local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
            if [ -f "$cache_file" ]; then
                local translated=$(cat "$cache_file")
                printf "%s|%s=%s\n" "$api_lang" "$key" "$translated" >> "$output_db"
                continue
            fi
            if [ -n "$network_status" ] && [ "$network_status" != "" ]; then
                cleaned_translation=$(translate_text "$value" "$DEFAULT_LANGUAGE" "$api_lang")
                if [ -n "$cleaned_translation" ]; then
                    local decoded="$cleaned_translation"
                    mkdir -p "$(dirname "$cache_file")"
                    printf "%s\n" "$decoded" > "$cache_file"
                    printf "%s|%s=%s\n" "$api_lang" "$key" "$decoded" >> "$output_db"
                else
                    printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
                    debug_log "DEBUG" "All translation APIs failed, using original text for key: ${key}" 
                fi
            else
                printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
                debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
            fi
        fi
    done

    stop_spinner "Language file created successfully" "success"
    debug_log "DEBUG" "Language DB creation completed for ${api_lang}"
    return 0
}

display_detected_translation() {
    local show_success_message="${1:-false}"
    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
    else
        lang_code="$DEFAULT_LANGUAGE"
    fi
    local source_lang="$DEFAULT_LANGUAGE"
    local source_db="message_${source_lang}.db"
    local target_db="message_${lang_code}.db"
    debug_log "DEBUG" "Displaying translation information for language code: ${lang_code}"
    if [ "$source_lang" = "$lang_code" ] && [ "$source_db" = "$target_db" ]; then
        debug_log "DEBUG" "Source and target languages are identical: ${lang_code}"
    fi
    if [ "$show_success_message" = "true" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATION_SUCCESS")")"
    fi
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_ORIGINAL" "i=$source_db")")"
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_CURRENT" "i=$target_db")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SOURCE" "i=$source_lang")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_CODE" "i=$lang_code")")"
    debug_log "DEBUG" "Translation information display completed for ${lang_code}"
}

process_language_translation() {
    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "Processing translation for language code: ${lang_code}"
    else
        debug_log "DEBUG" "No language code found in message.ch, using default"
        lang_code="$DEFAULT_LANGUAGE"
    fi
    local is_default_language=false
    if [ "$lang_code" = "$DEFAULT_LANGUAGE" ]; then
        is_default_language=true
        debug_log "DEBUG" "Selected language is the default language (${lang_code})"
    fi
    if [ "$is_default_language" = "false" ]; then
        create_language_db "$lang_code"
        display_detected_translation "false"
    else
        debug_log "DEBUG" "Skipping DB creation for default language: ${lang_code}"
        if [ "${DEFAULT_LANG_DISPLAYED:-false}" = "false" ]; then
            debug_log "DEBUG" "Displaying information for default language once"
            display_detected_translation "false"
            DEFAULT_LANG_DISPLAYED=true
        else
            debug_log "DEBUG" "Default language info already displayed, skipping"
        fi
    fi
    printf "\n"
    return 0
}

init_translation() {
    init_translation_cache
    process_language_translation
    debug_log "DEBUG" "Translation module initialized with language processing"
}

# スクリプト初期化（自動実行しない：必要時に明示呼び出し）
# init_translation
