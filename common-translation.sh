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

# @FUNCTION: translate_main
# @DESCRIPTION: Main entry point for the translation feature. Initializes, checks language,
#               checks for existing complete translation DB based on a marker, and triggers
#               translation creation if necessary.
translate_main() {
    # --- Initialization ---
    init_translation_cache
    if type detect_wget_capabilities >/dev/null 2>&1; then
        WGET_CAPABILITY_DETECTED=$(detect_wget_capabilities)
        debug_log "DEBUG" "translate_main: Wget capability set globally: ${WGET_CAPABILITY_DETECTED}"
    else
        debug_log "ERROR" "translate_main: detect_wget_capabilities function not found."
        display_message "error" "$(get_message "MSG_ERR_FUNC_NOT_FOUND" "func=detect_wget_capabilities")"
        return 1
    fi
    debug_log "DEBUG" "translate_main: Translation module initialization part complete."
    # --- End Initialization ---

    # --- Translation Control Logic ---
    local lang_code=""
    local is_default_lang="false"
    local online_translation_needed="false" # Assume offline/cache is sufficient initially
    local spinner_started="false"
    local db_creation_result=1 # Default to failure
    local base_db=""
    local target_db=""
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER" # Define the marker key
    local target_last_line=""
    local target_last_key=""

    # 1. Determine Language Code
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "translate_main: Language code read from ${CACHE_DIR}/message.ch: ${lang_code}"
    else
        lang_code="$DEFAULT_LANGUAGE"
        debug_log "DEBUG" "translate_main: ${CACHE_DIR}/message.ch not found, using default language: ${lang_code}"
    fi

    # 2. Check if it's the default language
    [ "$lang_code" = "$DEFAULT_LANGUAGE" ] && is_default_lang="true"
    if [ "$is_default_lang" = "true" ]; then
        debug_log "DEBUG" "translate_main: Target language is the default language (${lang_code}). No translation needed."
        # Display info only once if it's the default language
        if [ "${TRANSLATION_INFO_DISPLAYED:-false}" = "false" ]; then
            debug_log "DEBUG" "translate_main: Displaying info for default language."
            display_detected_translation # Display default language info
            TRANSLATION_INFO_DISPLAYED=true
        fi
        return 0
    fi

    debug_log "DEBUG" "translate_main: Target language (${lang_code}) requires processing."

    # ★★★ START: New Cache Check Logic using Marker ★★★
    base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    target_db="${BASE_DIR}/message_${lang_code}.db"
    debug_log "DEBUG" "translate_main: Checking for existing target DB: ${target_db}"
    debug_log "DEBUG" "translate_main: Base DB for comparison: ${base_db}"

    if [ -f "$target_db" ] && [ -f "$base_db" ]; then
        debug_log "DEBUG" "translate_main: Both target DB and base DB exist. Checking marker key..."
        # Get the last non-comment, non-empty line from the target DB
        target_last_line=$(grep -v '^[[:space:]]*#\|^[[:space:]]*$' "$target_db" | tail -n 1)
        if [ -n "$target_last_line" ]; then
            # Extract the key part (between | and =)
            target_last_key=$(echo "$target_last_line" | sed -n 's/^[^|]*|\([^=]*\)=.*/\1/p')
            debug_log "DEBUG" "translate_main: Extracted last key from target DB: '${target_last_key}'"

            if [ -n "$target_last_key" ] && [ "$target_last_key" = "$marker_key" ]; then
                # Marker key found at the end of the target DB
                debug_log "INFO" "translate_main: Target DB '${target_db}' exists and ends with the marker key ('${marker_key}'). Translation assumed complete."
                # Display info only once if using cached/existing DB
                if [ "${TRANSLATION_INFO_DISPLAYED:-false}" = "false" ]; then
                    debug_log "DEBUG" "translate_main: Displaying info for existing target DB."
                    display_detected_translation
                    TRANSLATION_INFO_DISPLAYED=true
                fi
                return 0 # <<< Early return: Cache is valid
            else
                debug_log "INFO" "translate_main: Target DB exists, but the last key ('${target_last_key}') does not match the marker key ('${marker_key}') or key extraction failed. Proceeding with translation."
            fi
        else
            debug_log "WARN" "translate_main: Target DB '${target_db}' exists but appears to be empty or contains only comments/blank lines. Proceeding with translation."
        fi
    else
        if [ ! -f "$target_db" ]; then
            debug_log "INFO" "translate_main: Target DB '${target_db}' does not exist. Proceeding with translation."
        fi
        if [ ! -f "$base_db" ]; then
             # This case should ideally not happen if default DB is always present, but good to log.
            debug_log "WARN" "translate_main: Base DB '${base_db}' does not exist. Cannot perform marker check. Proceeding with translation."
        fi
    fi
    # ★★★ END: New Cache Check Logic using Marker ★★★

    # --- Proceed with Translation Process (only if cache check failed or DBs were missing) ---

    # 4. Pre-check if online translation is likely needed (Network, Settings, Cache)
    debug_log "DEBUG" "translate_main: Performing pre-check for online translation necessity."
    if ! check_network_connectivity; then
        debug_log "WARN" "translate_main: Network connectivity check failed."
        # Network is down, but check if all required keys are already cached
        if ! check_all_keys_in_cache "$lang_code"; then
            debug_log "ERROR" "translate_main: Network is down AND required keys are missing from cache for ${lang_code}."
            display_message "error" "$(get_message "MSG_ERR_NETWORK_AND_CACHE_MISS" "lang=$lang_code")"
            return 1 # Cannot proceed without network and cache
        else
            debug_log "INFO" "translate_main: Network is down, but all required keys found in cache for ${lang_code}. Proceeding with offline DB creation."
            online_translation_needed="false" # Force offline mode
        fi
    elif [ "$(config_get "$CONFIG_SECTION" "translation_mode" "$DEFAULT_TRANSLATION_MODE")" = "offline" ]; then
        debug_log "INFO" "translate_main: Translation mode set to 'offline'."
        # Offline mode, check cache
        if ! check_all_keys_in_cache "$lang_code"; then
            debug_log "ERROR" "translate_main: Offline mode is active AND required keys are missing from cache for ${lang_code}."
            display_message "error" "$(get_message "MSG_ERR_OFFLINE_AND_CACHE_MISS" "lang=$lang_code")"
            return 1 # Cannot proceed in offline mode without cache
        else
            debug_log "INFO" "translate_main: Offline mode is active, and all required keys found in cache for ${lang_code}. Proceeding with offline DB creation."
            online_translation_needed="false" # Ensure offline mode
        fi
    else
        # Online mode and network is up, check if cache is sufficient
        if check_all_keys_in_cache "$lang_code"; then
            debug_log "INFO" "translate_main: Online mode, network up, and all required keys found in cache for ${lang_code}. Proceeding with offline DB creation."
            online_translation_needed="false" # Cache is sufficient
        else
            debug_log "INFO" "translate_main: Online mode, network up, but required keys are missing from cache for ${lang_code}. Online translation will be attempted."
            online_translation_needed="true" # Cache miss, online needed
        fi
    fi

    # 5. Start Spinner (only if online translation is needed)
    if [ "$online_translation_needed" = "true" ]; then
        local current_api
        current_api=$(config_get "$CONFIG_SECTION" "translation_api" "$DEFAULT_TRANSLATION_API")
        debug_log "DEBUG" "translate_main: Online translation needed. Attempting API: ${current_api}"
        if type start_spinner >/dev/null 2>&1; then
            start_spinner "$(color blue "$(get_message "MSG_TRANSLATING" "api=$current_api")")" "blue"
            spinner_started="true"
            debug_log "DEBUG" "translate_main: Spinner started."
        else
            debug_log "WARN" "translate_main: start_spinner function not found. Spinner not shown."
        fi
    fi

    # 6. Create/Update Language DB
    debug_log "DEBUG" "translate_main: Calling create_language_db for language: ${lang_code}"
    create_language_db "$lang_code"
    db_creation_result=$?
    debug_log "DEBUG" "translate_main: create_language_db finished with status: ${db_creation_result}"

    # 7. Stop Spinner (if started)
    if [ "$spinner_started" = "true" ]; then
        if type stop_spinner >/dev/null 2>&1; then
            stop_spinner "" "" # Stop with default message (or none)
            debug_log "DEBUG" "translate_main: Spinner stopped."
        else
            debug_log "WARN" "translate_main: stop_spinner function not found."
        fi
    fi

    # 8. Handle Result and Display Info
    if [ "$db_creation_result" -eq 0 ]; then
        debug_log "INFO" "translate_main: Language DB creation/update successful for ${lang_code}."
        # Display success message only if online translation was attempted and succeeded
        if [ "$online_translation_needed" = "true" ]; then
             # Check if the API call was actually successful within create_language_db
             # We might need a more robust way to check this, e.g., a global var set by create_language_db
             # For now, assume db_creation_result=0 after online attempt means success.
             display_message "success" "$(get_message "MSG_TRANSLATION_SUCCESS" "lang=$lang_code")"
        fi
         # Display translation info regardless of online/offline, but only once
        if [ "${TRANSLATION_INFO_DISPLAYED:-false}" = "false" ]; then
             debug_log "DEBUG" "translate_main: Displaying info after successful DB creation."
             display_detected_translation
             TRANSLATION_INFO_DISPLAYED=true
        fi
    else
        debug_log "ERROR" "translate_main: Language DB creation/update failed for ${lang_code} (Exit status: ${db_creation_result})."
        # Display failure message (get_message should handle default if specific key missing)
        display_message "error" "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code")"
        # Optionally, attempt to load default language messages as a fallback?
        # Or just return the error code.
        return "$db_creation_result"
    fi

    debug_log "DEBUG" "translate_main: Function finished."
    return 0
}

# ★★★ 削除: この関数は不要になりました ★★★
# process_language_translation() { ... }

# ★★★ 削除: この関数は translate_main にリネーム・統合されました ★★★
# init_translation() { ... }

# スクリプト初期化（自動実行）
# translate_main # This line should be present in the main script (e.g., aios.sh) that sources this file.
                 # Do not call translate_main automatically within this library file itself.
