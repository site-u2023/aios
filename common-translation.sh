#!/bin/sh

SCRIPT_VERSION="2025-04-23-12-47" # Updated version based on request time

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-04-23
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
CURRENT_API="" # This will be set within translate_main now

# API設定追加
GOOGLE_TRANSLATE_URL="${GOOGLE_TRANSLATE_URL:-https://translate.googleapis.com/translate_a/single}"
LINGVA_URL="${LINGVA_URL:-https://lingva.ml/api/v1}"
API_LIST="${API_LIST:-google}"
WGET_CAPABILITY_DETECTED="" # wget capabilities - Initialized by translate_main

# 翻訳キャッシュの初期化 (translate_mainから呼ばれるヘルパー関数)
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized by init_translation_cache"
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
        c="${string:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded="${encoded}$c" ;;
            " ") encoded="${encoded}%20" ;;
            *) encoded="${encoded}$(printf "%%%02X" "'$c")" ;;
        esac
        i=$((i + 1))
    done
    printf "%s\n" "$encoded"
}

# Lingva Translate APIを使用した翻訳関数
translate_with_lingva() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    local network_type=""

    # Network check performed by caller (translate_main)
    if [ -f "$ip_check_file" ]; then
        network_type=$(cat "$ip_check_file")
    fi

    case "$network_type" in
        "v4") wget_options="-4" ;;
        "v6") wget_options="-6" ;;
        *) wget_options="" ;;
    esac

    local encoded_text=$(urlencode "$text")
    local temp_file="${TRANSLATION_CACHE_DIR}/lingva_response.tmp"
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null

    while [ $retry_count -le $API_MAX_RETRIES ]; do
        if [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ]; then
            wget_options=$([ "$wget_options" = "-4" ] && echo "-6" || echo "-4")
            debug_log "DEBUG" "Retrying Lingva with wget option: $wget_options"
        fi

        $BASE_WGET $wget_options -T $API_TIMEOUT --tries=1 -O "$temp_file" \
             --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
             "${LINGVA_URL}/$source_lang/$target_lang/$encoded_text" 2>/dev/null

        if [ -s "$temp_file" ] && grep -q "translation" "$temp_file"; then
            local translated=$(sed 's/.*"translation"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/g' "$temp_file" | sed 's/\\"/"/g')
            if [ -n "$translated" ]; then
                rm -f "$temp_file" 2>/dev/null
                printf "%s\n" "$translated"
                return 0
            fi
        fi
        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        sleep 1
    done
    debug_log "DEBUG" "Lingva translation failed after ${API_MAX_RETRIES} attempts for text: $text"
    return 1
}

# Google翻訳APIを使用した翻訳関数 (高効率版)
translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    local network_type=""
    local temp_file="${TRANSLATION_CACHE_DIR}/google_response.tmp"
    local api_url=""

    # Network check performed by caller (translate_main)
    if [ -f "$ip_check_file" ]; then
        network_type=$(cat "$ip_check_file")
    fi

    case "$network_type" in
        "v4") wget_options="-4" ;;
        "v6") wget_options="-6" ;;
        *) wget_options="" ;;
    esac

    mkdir -p "$(dirname "$temp_file")" 2>/dev/null
    local encoded_text=$(urlencode "$text")
    api_url="${GOOGLE_TRANSLATE_URL}?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}"

    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        if [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ]; then
            if echo "$wget_options" | grep -q -- "-4"; then
                 wget_options="-6"
            else
                 wget_options="-4"
            fi
            debug_log "DEBUG" "Retrying Google with wget option: $wget_options"
        fi

        case "$WGET_CAPABILITY_DETECTED" in
            "full")
                wget --no-check-certificate $wget_options -L -T $API_TIMEOUT -q -O "$temp_file" \
                    --user-agent="Mozilla/5.0" "$api_url" 2>/dev/null
                ;;
            *) # basic, https_only, fallback
                wget --no-check-certificate $wget_options -T $API_TIMEOUT -q -O "$temp_file" \
                    "$api_url" 2>/dev/null
                ;;
        esac

        if [ -s "$temp_file" ]; then
            if grep -q '\[' "$temp_file"; then
                local translated=$(sed 's/\[\[\["//; s/",".*//; s/\\u003d/=/g; s/\\u003c/</g; s/\\u003e/>/g; s/\\u0026/\&/g; s/\\"/"/g; s/\\n/\n/g; s/\\r//g' "$temp_file")
                if [ -n "$translated" ]; then
                    rm -f "$temp_file" 2>/dev/null
                    printf "%s\n" "$translated"
                    return 0
                fi
            fi
        fi
        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        sleep 1
    done
    debug_log "DEBUG" "Google translation failed after ${API_MAX_RETRIES} attempts for text: $text"
    return 1
}

# 翻訳API呼び出しラッパー
translate_text() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local result=""

    # API selection is done in translate_main, just call the appropriate function
    case "$API_LIST" in
        google)
            result=$(translate_with_google "$text" "$source_lang" "$target_lang")
            ;;
        lingva)
            result=$(translate_with_lingva "$text" "$source_lang" "$target_lang")
            ;;
        *) # Default to Google
            result=$(translate_with_google "$text" "$source_lang" "$target_lang")
            ;;
    esac

    if [ -n "$result" ]; then
        printf "%s" "$result"
        return 0
    else
        return 1
    fi
}

# 翻訳DB作成関数 (責務: DBファイル作成のみ)
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang="$target_lang"
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local cleaned_translation=""
    local translation_attempted="false"

    debug_log "DEBUG" "Creating language DB for target ${target_lang} (API lang code ${api_lang})"

    if [ ! -f "$base_db" ]; then
        debug_log "ERROR" "Base message DB not found: $base_db. Cannot create target DB."
        return 1
    fi

    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
EOF

    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled in create_language_db, copying original text."
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" | sed "s/^${DEFAULT_LANGUAGE}|/${api_lang}|/" >> "$output_db"
        return 1
    fi

    local translation_success_count=0
    local translation_fail_count=0
    local cache_hit_count=0

    while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac
        if ! echo "$line" | grep -q "^${DEFAULT_LANGUAGE}|"; then continue; fi
        local line_content=${line#*|}
        local key=${line_content%%=*}
        local value=${line_content#*=}
        if [ -z "$key" ] || [ -z "$value" ]; then continue; fi

        local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
        local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"

        if [ -f "$cache_file" ]; then
            local translated=$(cat "$cache_file")
            printf "%s|%s=%s\n" "$api_lang" "$key" "$translated" >> "$output_db"
            cache_hit_count=$((cache_hit_count + 1))
            continue
        fi

        translation_attempted="true"
        cleaned_translation=$(translate_text "$value" "$DEFAULT_LANGUAGE" "$api_lang")

        if [ -n "$cleaned_translation" ]; then
            local decoded="$cleaned_translation"
            mkdir -p "$(dirname "$cache_file")"
            printf "%s\n" "$decoded" > "$cache_file"
            printf "%s|%s=%s\n" "$api_lang" "$key" "$decoded" >> "$output_db"
            translation_success_count=$((translation_success_count + 1))
        else
            printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
            debug_log "DEBUG" "Online translation failed for key: ${key}, using original text."
            translation_fail_count=$((translation_fail_count + 1))
        fi
    done < "$base_db"

    debug_log "DEBUG" "Translation stats for ${api_lang}: Success=$translation_success_count, Fail/Skipped=$translation_fail_count, CacheHit=$cache_hit_count"
    debug_log "DEBUG" "Language DB creation process completed for ${api_lang}"

    if [ "$translation_attempted" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# 翻訳情報を表示する関数
display_detected_translation() {
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

    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_ORIGINAL" "i=$source_db")")"
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_CURRENT" "i=$target_db")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SOURCE" "i=$source_lang")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_CODE" "i=$lang_code")")"

    debug_log "DEBUG" "Translation information display completed for ${lang_code}"
}

# ★★★ 修正: init_translation をリネームし、初期化と制御ロジックを統合 ★★★
# 翻訳機能のメイン入口関数 (初期化と制御を担当)
translate_main() {
    # --- 初期化処理 (旧 init_translation の内容) ---
    init_translation_cache # キャッシュディレクトリ初期化

    # wget機能の検出
    if type detect_wget_capabilities >/dev/null 2>&1; then
        WGET_CAPABILITY_DETECTED=$(detect_wget_capabilities)
        debug_log "DEBUG" "Wget capability set globally: ${WGET_CAPABILITY_DETECTED}"
    else
        debug_log "ERROR" "detect_wget_capabilities function not found. Wget capability detection skipped."
        WGET_CAPABILITY_DETECTED="basic" # Fallback
    fi
    debug_log "DEBUG" "Translation module initialization part complete."
    # --- 初期化処理ここまで ---

    # --- 翻訳制御ロジック (旧 translate_main の内容) ---
    local lang_code=""
    local is_default_lang="false"
    local online_translation_needed="false"
    local spinner_started="false"
    local current_api="" # API name for display
    local db_creation_result=1 # Default to 1 (no online translation attempted)

    # 1. 言語コード決定
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "translate_main: Using language code from message.ch: ${lang_code}"
    else
        debug_log "DEBUG" "translate_main: No message.ch found, using default language"
        lang_code="$DEFAULT_LANGUAGE"
    fi

    # 2. デフォルト言語か判定
    [ "$lang_code" = "$DEFAULT_LANGUAGE" ] && is_default_lang="true"
    if [ "$is_default_lang" = "true" ]; then
        debug_log "DEBUG" "translate_main: Target language is default (${lang_code}). Skipping online translation checks."
        if [ "${TRANSLATION_INFO_DISPLAYED:-false}" = "false" ]; then
            debug_log "DEBUG" "translate_main: Displaying info for default language."
            display_detected_translation
            TRANSLATION_INFO_DISPLAYED=true
        fi
        return 0
    fi

    debug_log "DEBUG" "translate_main: Target language (${lang_code}) requires processing."

    # 3. オンライン翻訳が必要か事前確認 (ネットワーク、設定、キャッシュ)
    local network_status=""
    local ip_check_file="${CACHE_DIR}/network.ch"
    if [ ! -f "$ip_check_file" ]; then
        if type check_network_connectivity >/dev/null 2>&1; then
             check_network_connectivity
        else
             debug_log "ERROR" "translate_main: check_network_connectivity function not found."
             network_status="" # Assume no network
        fi
    fi
    if [ -f "$ip_check_file" ]; then
        network_status=$(cat "$ip_check_file")
    fi

    if [ -n "$network_status" ] && [ "$network_status" != "" ] && [ "$ONLINE_TRANSLATION_ENABLED" = "yes" ]; then
        debug_log "DEBUG" "translate_main: Network available and online translation enabled. Checking cache..."
        local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
        local api_lang="$lang_code"

        if [ -f "$base_db" ]; then
            # --- Cache Check Loop ---
            while IFS= read -r line; do
                case "$line" in \#*|"") continue ;; esac
                if ! echo "$line" | grep -q "^${DEFAULT_LANGUAGE}|"; then continue; fi
                local line_content=${line#*|}
                local key=${line_content%%=*}
                local value=${line_content#*=}
                if [ -z "$key" ] || [ -z "$value" ]; then continue; fi

                local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
                local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"

                if [ ! -f "$cache_file" ]; then
                    debug_log "DEBUG" "translate_main: Cache miss for key '${key}'. Online translation needed."
                    online_translation_needed="true"
                    break
                fi
            done < "$base_db"
            # --- End Cache Check Loop ---
            if [ "$online_translation_needed" = "false" ]; then
                 debug_log "DEBUG" "translate_main: All translations found in cache."
            fi
        else
            debug_log "WARNING" "translate_main: Base message DB not found ($base_db). Assuming online translation might be needed."
            online_translation_needed="true"
        fi
    else
        debug_log "DEBUG" "translate_main: Network unavailable or online translation disabled. Skipping online translation."
        online_translation_needed="false"
    fi

    # 4. スピナー制御 (オンライン翻訳が必要な場合のみ)
    if [ "$online_translation_needed" = "true" ]; then
        case "$API_LIST" in
            google) current_api="translate.googleapis.com" ;;
            lingva) current_api="lingva.ml" ;;
            *) current_api="translate.googleapis.com" ;;
        esac
        [ -z "$current_api" ] && current_api="Translation API"
        debug_log "DEBUG" "translate_main: Starting spinner for API: $current_api"

        if type start_spinner >/dev/null 2>&1; then
            start_spinner "$(color blue "$(get_message "MSG_TRANSLATING" "api=$current_api")")" "blue"
            spinner_started="true"
        else
            debug_log "WARNING" "translate_main: start_spinner function not found."
        fi
    fi

    # 5. 翻訳DB作成指示
    create_language_db "$lang_code"
    db_creation_result=$? # Capture return value (0 if online attempted, 1 otherwise)

    # 6. スピナー停止 (開始されていた場合のみ)
    if [ "$spinner_started" = "true" ]; then
        if type stop_spinner >/dev/null 2>&1; then
            stop_spinner "" "" # Success message handled below
        else
            debug_log "INFO" "translate_main: Translation process finished (stop_spinner function not found)."
        fi
    fi

    # 7. 結果表示制御
    local show_success_msg="false"
    if [ "$online_translation_needed" = "true" ] && [ "$db_creation_result" -eq 0 ]; then
        show_success_msg="true"
    fi

    if [ "${TRANSLATION_INFO_DISPLAYED:-false}" = "false" ]; then
         debug_log "DEBUG" "translate_main: Displaying translation info."
         if [ "$show_success_msg" = "true" ]; then
              printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATION_SUCCESS")")"
         fi
         display_detected_translation
         TRANSLATION_INFO_DISPLAYED=true
    else
         debug_log "DEBUG" "translate_main: Translation info already displayed, skipping."
    fi
    # --- 翻訳制御ロジックここまで ---

    debug_log "DEBUG" "translate_main function finished."
    return 0 # translate_main itself succeeded
}

# ★★★ 削除: この関数は不要になりました ★★★
# process_language_translation() { ... }

# ★★★ 削除: この関数は translate_main にリネーム・統合されました ★★★
# init_translation() { ... }

# スクリプト初期化（自動実行）
# translate_main # This line should be present in the main script (e.g., aios.sh) that sources this file.
                 # Do not call translate_main automatically within this library file itself.
