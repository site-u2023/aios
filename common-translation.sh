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
# @DESCRIPTION: Main entry point for the translation feature. Checks language,
#               checks for existing translation DB, and triggers DB creation
#               using the first available function specified in AI_TRANSLATION_FUNCTIONS.
translate_main() {
    # --- Initialization ---
    # Wget capability detection (AIP functions might need this global variable)
    if type detect_wget_capabilities >/dev/null 2>&1; then
        WGET_CAPABILITY_DETECTED=$(detect_wget_capabilities)
        debug_log "DEBUG" "translate_main: Wget capability detected: ${WGET_CAPABILITY_DETECTED}"
    else
        # Log error but don't necessarily exit, AIP function might handle basic wget
        debug_log "ERROR" "translate_main: detect_wget_capabilities function not found."
        # Displaying message here might be too verbose, let AIP function fail if needed
        # display_message "error" "$(get_message "MSG_ERR_FUNC_NOT_FOUND" "func=detect_wget_capabilities")"
        WGET_CAPABILITY_DETECTED="basic" # Assume basic capability
    fi
    debug_log "DEBUG" "translate_main: Initialization part complete."
    # --- End Initialization ---

    # --- Translation Control Logic ---
    local lang_code=""
    local is_default_lang="false"
    local target_db=""
    local db_creation_result=1 # Default to failure

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
        # Use a simple flag to avoid repeated display in the same script run
        if [ "${TRANSLATION_INFO_DISPLAYED_DEFAULT:-false}" = "false" ]; then
            debug_log "DEBUG" "translate_main: Displaying info for default language."
            display_detected_translation # Display default language info
            TRANSLATION_INFO_DISPLAYED_DEFAULT=true
        fi
        return 0
    fi

    debug_log "DEBUG" "translate_main: Target language (${lang_code}) requires processing."

    # 3. Check if target DB already exists (Simple file check)
    target_db="${BASE_DIR}/message_${lang_code}.db"
    debug_log "DEBUG" "translate_main: Checking for existing target DB: ${target_db}"

    if [ -f "$target_db" ]; then
        debug_log "INFO" "translate_main: Target DB '${target_db}' already exists. Assuming translation is complete."
        # Display info only once if using existing DB
        if [ "${TRANSLATION_INFO_DISPLAYED_TARGET:-false}" = "false" ]; then
            debug_log "DEBUG" "translate_main: Displaying info for existing target DB."
            display_detected_translation
            TRANSLATION_INFO_DISPLAYED_TARGET=true
        fi
        return 0 # <<< Early return: DB exists
    fi

    debug_log "INFO" "translate_main: Target DB '${target_db}' does not exist. Proceeding with translation creation."

    # --- Proceed with Translation Process (DB does not exist) ---

    # 4. Find the first available translation function
    local selected_func=""
    local func_name=""
    # Read functions from global variable (space-separated)
    for func_name in $AI_TRANSLATION_FUNCTIONS; do
        debug_log "DEBUG" "translate_main: Checking availability of function: ${func_name}"
        # Check if the function is defined using POSIX compliant 'type'
        if type "$func_name" >/dev/null 2>&1; then
            debug_log "DEBUG" "translate_main: Function '${func_name}' is available."
            selected_func="$func_name"
            break # Use the first available function
        else
            debug_log "DEBUG" "translate_main: Function '${func_name}' is not defined or not found."
        fi
    done

    # Check if a function was selected
    if [ -z "$selected_func" ]; then
        debug_log "ERROR" "translate_main: No available translation functions found in AI_TRANSLATION_FUNCTIONS ('${AI_TRANSLATION_FUNCTIONS}')."
        display_message "error" "$(get_message "MSG_ERR_NO_TRANS_FUNC")"
        return 1
    fi

    debug_log "INFO" "translate_main: Selected translation function: ${selected_func}"

    # 5. Determine API URL and Domain Name based on the selected function
    local api_endpoint_url=""
    local domain_name=""
    case "$selected_func" in
        "translate_with_google")
            # Use the global variable for the base URL if defined, otherwise default
            api_endpoint_url="${GOOGLE_TRANSLATE_URL:-https://translate.googleapis.com/translate_a/single}"
            # Extract domain name (simple sed)
            domain_name=$(echo "$api_endpoint_url" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
            ;;
        "translate_with_lingva")
            api_endpoint_url="${LINGVA_URL:-https://lingva.ml/api/v1}"
            domain_name=$(echo "$api_endpoint_url" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
            ;;
        # Add cases for other potential AIP functions here
        # "translate_openai")
        #     api_endpoint_url="${OPENAI_API_URL:-https://api.openai.com/v1/...}" # Adjust URL
        #     domain_name="api.openai.com"
        #     ;;
        *)
            debug_log "ERROR" "translate_main: No URL/Domain mapping defined for selected function: ${selected_func}"
            display_message "error" "$(get_message "MSG_ERR_NO_URL_MAPPING" "func=$selected_func")"
            return 1
            ;;
    esac

    if [ -z "$api_endpoint_url" ] || [ -z "$domain_name" ]; then
         debug_log "ERROR" "translate_main: Failed to determine URL or Domain Name for function ${selected_func}."
         # Message already displayed in case block
         return 1
    fi

    debug_log "DEBUG" "translate_main: Using URL '${api_endpoint_url}' and Domain '${domain_name}' for function '${selected_func}'"

    # 6. Call create_language_db with the new arguments
    debug_log "DEBUG" "translate_main: Calling create_language_db for language '${lang_code}' using function '${selected_func}'"
    # Pass function name, API URL, domain name, and language code
    create_language_db "$selected_func" "$api_endpoint_url" "$domain_name" "$lang_code"
    db_creation_result=$?
    debug_log "DEBUG" "translate_main: create_language_db finished with status: ${db_creation_result}"

    # 7. Handle Result and Display Info
    if [ "$db_creation_result" -eq 0 ]; then
        debug_log "INFO" "translate_main: Language DB creation successful for ${lang_code} using ${selected_func}."
        # Display success message (optional, could be verbose)
        # display_message "success" "$(get_message "MSG_TRANSLATION_SUCCESS" "lang=$lang_code")"

        # Display translation info (only once per target language)
        if [ "${TRANSLATION_INFO_DISPLAYED_TARGET:-false}" = "false" ]; then
             debug_log "DEBUG" "translate_main: Displaying info after successful DB creation."
             display_detected_translation
             TRANSLATION_INFO_DISPLAYED_TARGET=true
        fi
        return 0 # Success
    else
        debug_log "ERROR" "translate_main: Language DB creation failed for ${lang_code} using ${selected_func} (Exit status: ${db_creation_result})."
        # Display failure message
        display_message "error" "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code")"
        return "$db_creation_result" # Propagate error code
    fi
}

# ★★★ 削除: この関数は不要になりました ★★★
# process_language_translation() { ... }

# ★★★ 削除: この関数は translate_main にリネーム・統合されました ★★★
# init_translation() { ... }

# スクリプト初期化（自動実行）
# translate_main # This line should be present in the main script (e.g., aios.sh) that sources this file.
                 # Do not call translate_main automatically within this library file itself.
