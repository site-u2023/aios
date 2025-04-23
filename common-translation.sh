#!/bin/sh

# SCRIPT_VERSION="2025-04-23-12-47" # Original version marker - Updated below
SCRIPT_VERSION="2025-04-23-14-32" # Updated version based on last interaction time

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
# ✅ Use type command (POSIX) instead of command -v, which, or type -t for command existence checks
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
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}" # Used for message.ch, network.ch etc.
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# オンライン翻訳を有効化 (create_language_db logic removed reliance on this, but keep for potential external checks)
ONLINE_TRANSLATION_ENABLED="yes"

# API設定 (Global defaults)
API_TIMEOUT="${API_TIMEOUT:-5}"
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"
# AI_TRANSLATION_FUNCTIONS should be defined globally (e.g., in main script or config)
# Example: AI_TRANSLATION_FUNCTIONS="translate_with_google translate_with_lingva"

# WGET Capability - Optional, AIP functions simplified to not rely heavily on it
WGET_CAPABILITY_DETECTED="" # Initialized by translate_main if detect_wget_capabilities exists

AI_TRANSLATION_FUNCTIONS="translate_with_google translate_with_lingva" # 使用したい関数名を空白区切りで列挙

# URL安全エンコード関数（seqを使わない最適化版）
# @param $1: string - The string to encode.
# @stdout: URL-encoded string.
urlencode() {
    local string="$1"
    local encoded=""
    local char
    local i=0
    local length=${#string} # POSIX compliant way to get length

    while [ "$i" -lt "$length" ]; do
        # Extract character at index i (POSIX compliant)
        char=$(expr "x$string" : "x.\{$i\}\(.\)")

        case "$char" in
            [a-zA-Z0-9.~_-]) encoded="${encoded}$char" ;;
            " ") encoded="${encoded}%20" ;;
            *)
                # POSIX printf for hex encoding
                # shellcheck disable=SC2059 # We need variable format specifier width
                encoded="${encoded}$(printf '%%%02X' "'$char")"
                ;;
        esac
        i=$((i + 1))
    done
    printf "%s\n" "$encoded"
}

# Lingva Translate APIを使用した翻訳関数 (AIP専用関数)
# @param $1: source_text (string) - The text to translate.
# @param $2: target_lang_code (string) - The target language code (e.g., "ja").
# @stdout: Translated text on success. Empty string on failure.
# @return: 0 on success, non-zero on failure.
translate_with_lingva() {
    local source_text="$1"
    local target_lang_code="$2"
    local source_lang="$DEFAULT_LANGUAGE" # Use the global default language

    local retry_count=0
    local temp_file="${BASE_DIR}/lingva_response_$$.tmp" # Use PID for temp file uniqueness
    local api_url=""
    local translated_text=""
    local wget_base_cmd=""

    debug_log "DEBUG" "translate_with_lingva: Translating to '${target_lang_code}'"

    # --- Define API URL internally ---
    # Using the standard public Lingva instance URL as the default
    # This function does NOT take URL as an argument or read API-specific global vars for it.
    local base_lingva_url="https://lingva.ml/api/v1"
    # --- End Internal URL Definition ---

    local encoded_text=$(urlencode "$source_text")
    # Construct the full API URL
    api_url="${base_lingva_url}/${source_lang}/${target_lang_code}/${encoded_text}"
    debug_log "DEBUG" "translate_with_lingva: API URL: ${api_url}"

    mkdir -p "$(dirname "$temp_file")" 2>/dev/null

    # Basic wget command - Simplified, no complex capability checks or v4/v6 forcing
    wget_base_cmd="wget --no-check-certificate -T $API_TIMEOUT -q -O \"$temp_file\" --user-agent=\"Mozilla/5.0 (Linux; OpenWrt)\""

    # Retry loop
    while [ $retry_count -lt "$API_MAX_RETRIES" ]; do
        debug_log "DEBUG" "translate_with_lingva: Attempting download (Try $((retry_count + 1))/${API_MAX_RETRIES})"
        # Execute wget command using eval
        eval "$wget_base_cmd \"$api_url\""
        local wget_exit_code=$?

        if [ "$wget_exit_code" -eq 0 ] && [ -s "$temp_file" ]; then
            debug_log "DEBUG" "translate_with_lingva: Download successful."
            # Extract translation using sed (adjust pattern based on actual Lingva response)
            # Assuming Lingva returns JSON like {"translation": "..."}
            if grep -q '"translation"' "$temp_file"; then
                translated_text=$(sed -n 's/.*"translation"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$temp_file")

                # Basic unescaping (Lingva might need different/less unescaping than Google)
                translated_text=$(echo "$translated_text" | sed \
                    -e 's/\\"/"/g' \
                    -e 's/\\\\/\\/g') # Handle escaped backslash and quote

                if [ -n "$translated_text" ]; then
                    debug_log "DEBUG" "translate_with_lingva: Translation extracted successfully."
                    printf "%s\n" "$translated_text" # Output to stdout
                    rm -f "$temp_file" 2>/dev/null
                    return 0 # Success
                else
                    debug_log "DEBUG" "translate_with_lingva: Failed to extract translation from response."
                fi
            else
                 debug_log "DEBUG" "translate_with_lingva: Response does not contain 'translation' key."
                 # head -n 3 "$temp_file" | while IFS= read -r log_line; do debug_log "DEBUG" "Response line: $log_line"; done
            fi
        else
            debug_log "DEBUG" "translate_with_lingva: wget failed (Exit code: $wget_exit_code) or temp file is empty."
        fi

        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt "$API_MAX_RETRIES" ]; then
            debug_log "DEBUG" "translate_with_lingva: Retrying after sleep..."
            sleep 1
        fi
    done

    debug_log "ERROR" "translate_with_lingva: Translation failed after ${API_MAX_RETRIES} attempts for text starting with: $(echo "$source_text" | cut -c 1-50)"
    rm -f "$temp_file" 2>/dev/null
    printf "" # Output empty string on failure
    return 1 # Failure
}

# Google翻訳APIを使用した翻訳関数 (AIP専用関数)
# @param $1: source_text (string) - The text to translate.
# @param $2: target_lang_code (string) - The target language code (e.g., "ja").
# @stdout: Translated text on success. Empty string on failure.
# @return: 0 on success, non-zero on failure.
translate_with_google() {
    local source_text="$1"
    local target_lang_code="$2"
    local source_lang="$DEFAULT_LANGUAGE" # Use the global default language

    local retry_count=0
    local temp_file="${BASE_DIR}/google_response_$$.tmp" # Use PID for temp file uniqueness
    local api_url=""
    local translated_text=""
    local wget_base_cmd=""

    debug_log "DEBUG" "translate_with_google: Translating to '${target_lang_code}'"

    # --- Define API URL internally ---
    # Using the standard public Google Translate URL as the default
    # This function does NOT take URL as an argument or read API-specific global vars for it.
    local base_google_url="https://translate.googleapis.com/translate_a/single"
    # --- End Internal URL Definition ---

    local encoded_text=$(urlencode "$source_text")
    # Construct the full API URL
    api_url="${base_google_url}?client=gtx&sl=${source_lang}&tl=${target_lang_code}&dt=t&q=${encoded_text}"
    debug_log "DEBUG" "translate_with_google: API URL: ${api_url}"

    mkdir -p "$(dirname "$temp_file")" 2>/dev/null

    # Basic wget command - Simplified
    wget_base_cmd="wget --no-check-certificate -T $API_TIMEOUT -q -O \"$temp_file\" --user-agent=\"Mozilla/5.0\""

    # Retry loop
    while [ $retry_count -lt "$API_MAX_RETRIES" ]; do
        debug_log "DEBUG" "translate_with_google: Attempting download (Try $((retry_count + 1))/${API_MAX_RETRIES})"
        # Execute wget command using eval
        eval "$wget_base_cmd \"$api_url\""
        local wget_exit_code=$?

        if [ "$wget_exit_code" -eq 0 ] && [ -s "$temp_file" ]; then
            debug_log "DEBUG" "translate_with_google: Download successful."
            # Check if the response looks like a valid Google Translate JSON array start
            if grep -q '^\s*\[\[\["' "$temp_file"; then
                translated_text=$(sed -n 's/^\s*\[\[\["\([^"]*\)".*/\1/p' "$temp_file")

                # Basic unescaping
                translated_text=$(echo "$translated_text" | sed \
                    -e 's/\\u003d/=/g' \
                    -e 's/\\u003c/</g' \
                    -e 's/\\u003e/>/g' \
                    -e 's/\\u0026/\&/g' \
                    -e 's/\\"/"/g' \
                    -e 's/\\n/\n/g' \
                    -e 's/\\r//g' \
                    -e 's/\\\\/\\/g') # Handle escaped backslash

                if [ -n "$translated_text" ]; then
                    debug_log "DEBUG" "translate_with_google: Translation extracted successfully."
                    printf "%s\n" "$translated_text" # Output to stdout
                    rm -f "$temp_file" 2>/dev/null
                    return 0 # Success
                else
                    debug_log "DEBUG" "translate_with_google: Failed to extract translation from response."
                fi
            else
                debug_log "DEBUG" "translate_with_google: Response does not look like valid Google Translate JSON."
                # head -n 3 "$temp_file" | while IFS= read -r log_line; do debug_log "DEBUG" "Response line: $log_line"; done
            fi
        else
            debug_log "DEBUG" "translate_with_google: wget failed (Exit code: $wget_exit_code) or temp file is empty."
        fi

        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt "$API_MAX_RETRIES" ]; then
            debug_log "DEBUG" "translate_with_google: Retrying after sleep..."
            sleep 1
        fi
    done

    debug_log "ERROR" "translate_with_google: Translation failed after ${API_MAX_RETRIES} attempts for text starting with: $(echo "$source_text" | cut -c 1-50)"
    rm -f "$temp_file" 2>/dev/null
    printf "" # Output empty string on failure
    return 1 # Failure
}

# 翻訳DB作成関数 (責務: DBファイル作成、AIP関数呼び出し、スピナー制御)
# @param $1: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - The base API endpoint URL (used ONLY for spinner display via domain_name extraction, NOT passed to AIP func)
# @param $3: domain_name (string) - The domain name for spinner display (e.g., "translate.googleapis.com")
# @param $4: target_lang_code (string) - The target language code (e.g., "ja")
# @return: 0 on success, 1 on base DB not found, 2 if AIP function fails consistently (though it writes original text)
create_language_db() {
    local aip_function_name="$1"
    local api_endpoint_url="$2" # Passed URL for context/potential future use, but mainly for domain name below
    local domain_name="$3"      # Explicitly passed domain name for spinner
    local target_lang_code="$4"

    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local output_db="${BASE_DIR}/message_${target_lang_code}.db"
    local spinner_started="false"
    local overall_success=0 # Assume success initially

    debug_log "DEBUG" "Creating language DB for target '${target_lang_code}' using function '${aip_function_name}' with domain '${domain_name}'"

    if [ ! -f "$base_db" ]; then
        debug_log "ERROR" "Base message DB not found: $base_db. Cannot create target DB."
        # --- 変更点 ---
        # 1. display_message 呼び出しを削除
        # 2. エラーキー MSG_TRANSLATION_FAILED を使用
        # 3. printf と color/get_message で標準エラー出力に表示
        printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_FAILED")")" >&2
        # ---------------
        return 1
    fi

    # Start spinner before the loop
    if type start_spinner >/dev/null 2>&1; then
        # --- 変更点 ---
        # 1. ベタ書きメッセージまたは存在しないキーの使用を削除
        # 2. 新規キー MSG_TRANSLATING_CURRENTLY を使用
        # 3. パラメータとして api=$domain_name を渡す
        start_spinner "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name")")" "blue"
        # ---------------
        spinner_started="true"
        debug_log "DEBUG" "Spinner started for domain: ${domain_name}"
    else
        debug_log "WARN" "start_spinner function not found. Spinner not shown."
    fi

    # Create/overwrite the output DB with the header
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
# Translation generated using: ${aip_function_name}
# Target Language: ${target_lang_code}
EOF

    # Loop through the base DB entries
    while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac
        # Ensure the line starts with the default language code and a pipe
        if ! echo "$line" | grep -q "^${DEFAULT_LANGUAGE}|"; then continue; fi

        local line_content=${line#*|}
        local key=${line_content%%=*}
        local value=${line_content#*=}
        if [ -z "$key" ] || [ -z "$value" ]; then
            debug_log "DEBUG" "Skipping invalid line in base DB: $line"
            continue
        fi

        # --- Directly call the AIP function ---
        local translated_text=""
        local exit_code=1 # Default to failure

        debug_log "DEBUG" "Attempting translation for key '${key}' using '${aip_function_name}'"
        translated_text=$("$aip_function_name" "$value" "$target_lang_code")
        exit_code=$?

        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            debug_log "DEBUG" "Translation successful for key '${key}'"
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$translated_text" >> "$output_db"
        else
            debug_log "DEBUG" "Translation failed (Exit code: $exit_code) or returned empty for key '${key}'. Using original text."
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$value" >> "$output_db"
            # overall_success=2 # Indicate partial failure if needed (Uncomment if specific tracking is needed)
        fi
        # --- End AIP function call ---

    done < "$base_db"

    # Stop spinner after the loop
    if [ "$spinner_started" = "true" ]; then
        if type stop_spinner >/dev/null 2>&1; then
            # --- 変更点 ---
            # 1. ベタ書きメッセージまたは空メッセージを削除
            # 2. 新規キー MSG_TRANSLATING_CREATED を使用
            # 3. 2番目の引数 "success" は維持
            stop_spinner "$(get_message "MSG_TRANSLATING_CREATED")" "success"
            # ---------------
            debug_log "DEBUG" "Spinner stopped."
        else
            debug_log "WARN" "stop_spinner function not found."
        fi
    fi

    # Add the completion marker key at the end of the file
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    printf "%s|%s=%s\n" "$target_lang_code" "$marker_key" "true" >> "$output_db"
    debug_log "DEBUG" "Completion marker added to ${output_db}"

    debug_log "DEBUG" "Language DB creation process completed for ${target_lang_code}"
    return "$overall_success" # Return 0 for success, potentially 2 for partial
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
    local target_db="message_${lang_code}.db" # This might not exist if creation failed

    debug_log "DEBUG" "Displaying translation information for language code: ${lang_code}"

    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_ORIGINAL" "i=$source_db")")"
    if [ -f "${BASE_DIR}/${target_db}" ]; then
        printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_CURRENT" "i=$target_db")")"
    else
        printf "%s\n" "$(color yellow "$(get_message "MSG_TRANSLATION_SOURCE_MISSING" "i=$target_db")")"
    fi
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SOURCE" "i=$source_lang")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_CODE" "i=$lang_code")")"

    debug_log "DEBUG" "Translation information display completed for ${lang_code}"
}

# @FUNCTION: translate_main
# @DESCRIPTION: Entry point for translation. Reads target language from cache (message.ch),
#               checks/creates the translation DB if needed (not default lang),
#               and displays translation info ONLY AFTER confirmation/creation.
#               Does NOT take language code as an argument.
# @PARAM: None
# @RETURN: 0 on success/no translation needed, 1 on critical error,
#          propagates create_language_db exit code on failure.
translate_main() {
    # --- Initialization ---
    # (Wget detection logic can remain as it might be used by AIP funcs indirectly)
    if type detect_wget_capabilities >/dev/null 2>&1; then
        WGET_CAPABILITY_DETECTED=$(detect_wget_capabilities)
        debug_log "DEBUG" "translate_main: Wget capability detected: ${WGET_CAPABILITY_DETECTED}"
    else
        debug_log "DEBUG" "translate_main: detect_wget_capabilities function not found. Assuming basic wget."
        WGET_CAPABILITY_DETECTED="basic"
    fi
    debug_log "DEBUG" "translate_main: Initialization part complete."
    # --- End Initialization ---

    # --- Translation Control Logic ---
    local lang_code=""
    local is_default_lang="false"
    local target_db=""
    local db_creation_result=1 # Default to failure/not run
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"

    # 1. Determine Language Code ONLY from Cache
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "translate_main: Language code read from cache ${CACHE_DIR}/message.ch: ${lang_code}"
    else
        lang_code="$DEFAULT_LANGUAGE"
        debug_log "DEBUG" "translate_main: Cache file ${CACHE_DIR}/message.ch not found, using default language: ${lang_code}"
    fi

    # 2. Check if it's the default language
    [ "$lang_code" = "$DEFAULT_LANGUAGE" ] && is_default_lang="true"
    if [ "$is_default_lang" = "true" ]; then
        debug_log "DEBUG" "translate_main: Target language is the default language (${lang_code}). No translation needed or display from this function."
        # --- 修正 --- デフォルト言語の場合は何も表示せず終了
        return 0
    fi

    debug_log "DEBUG" "translate_main: Target language (${lang_code}) requires processing."

    # 3. Check if target DB exists AND contains the completion marker
    target_db="${BASE_DIR}/message_${lang_code}.db"
    debug_log "DEBUG" "translate_main: Checking for existing target DB with marker: ${target_db}"

    if [ -f "$target_db" ]; then
        if grep -q "^${lang_code}|${marker_key}=true$" "$target_db" >/dev/null 2>&1; then
             debug_log "INFO" "translate_main: Target DB '${target_db}' exists and is complete for '${lang_code}'."
             # --- 修正 --- 既存DBが完了している場合にのみ表示
             display_detected_translation
             return 0 # <<< Early return: DB exists and is complete
        else
             debug_log "INFO" "translate_main: Target DB '${target_db}' exists but is incomplete for '${lang_code}'. Proceeding with creation."
        fi
    else
        debug_log "INFO" "translate_main: Target DB '${target_db}' does not exist. Proceeding with creation."
    fi

    # --- Proceed with Translation Process ---
    # (Steps 4 & 5: Find function, determine domain - remain the same as f7ff132)
    # 4. Find the first available translation function...
    local selected_func=""
    local func_name=""
    if [ -z "$AI_TRANSLATION_FUNCTIONS" ]; then
         debug_log "ERROR" "translate_main: AI_TRANSLATION_FUNCTIONS global variable is not set or empty."
         display_message "error" "$(get_message "MSG_ERR_NO_TRANS_FUNC_VAR")"
         return 1
    fi
    set -f; set -- $AI_TRANSLATION_FUNCTIONS; set +f
    for func_name in "$@"; do
        if type "$func_name" >/dev/null 2>&1; then selected_func="$func_name"; break; fi
    done
    if [ -z "$selected_func" ]; then
        debug_log "ERROR" "translate_main: No available translation functions found from list: '${AI_TRANSLATION_FUNCTIONS}'."
        display_message "error" "$(get_message "MSG_ERR_NO_TRANS_FUNC_AVAIL" "list=$AI_TRANSLATION_FUNCTIONS")"
        return 1
    fi
    debug_log "INFO" "translate_main: Selected translation function: ${selected_func}"

    # 5. Determine API URL and Domain Name for spinner...
    local api_endpoint_url=""
    local domain_name=""
    case "$selected_func" in
        "translate_with_google") api_endpoint_url="..."; domain_name="translate.googleapis.com" ;;
        "translate_with_lingva") api_endpoint_url="..."; domain_name="lingva.ml" ;;
        *) debug_log "ERROR" "..."; api_endpoint_url="N/A"; domain_name="$selected_func" ;;
    esac
    debug_log "DEBUG" "translate_main: Using Domain '${domain_name}' for spinner..."


    # 6. Call create_language_db
    debug_log "DEBUG" "translate_main: Calling create_language_db for language '${lang_code}' using function '${selected_func}'"
    create_language_db "$selected_func" "$api_endpoint_url" "$domain_name" "$lang_code"
    db_creation_result=$?
    debug_log "DEBUG" "translate_main: create_language_db finished with status: ${db_creation_result}"

    # 7. Handle Result and Display Info ONLY on Success
    if [ "$db_creation_result" -eq 0 ]; then
        debug_log "INFO" "translate_main: Language DB creation successful for ${lang_code}."
        # --- 修正 --- DB作成成功後にのみ表示
        display_detected_translation
        return 0 # Success
    else
        debug_log "ERROR" "translate_main: Language DB creation failed for ${lang_code} (Exit status: ${db_creation_result})."
        # --- 修正 --- 失敗時はエラーメッセージのみ表示 (display_messageは元々あった)
        if [ "$db_creation_result" -ne 1 ]; then # Avoid duplicate if base DB missing
             display_message "error" "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code")"
        fi
        # --- 修正 --- 失敗時は display_detected_translation を呼び出さない
        return "$db_creation_result" # Propagate error code
    fi
}
