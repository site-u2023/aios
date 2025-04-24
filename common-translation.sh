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
    local char # This variable is no longer needed with the direct slicing
    local i=0
    local length=${#string} # POSIX compliant way to get length

    while [ "$i" -lt "$length" ]; do
        char="${string:$i:1}"

        case "$char" in
            [a-zA-Z0-9.~_-]) encoded="${encoded}$char" ;;
            " ") encoded="${encoded}%20" ;;
            *)
                encoded="${encoded}$(printf '%%%02X' "'$char")"
                ;;
        esac
        i=$((i + 1))
    done
    printf "%s\n" "$encoded"
}

# Lingva Translate APIを使用した翻訳関数 (修正版)
# @param $1: source_text (string) - The text to translate.
# @param $2: target_lang_code (string) - The target language code (e.g., "ja").
# @stdout: Translated text on success. Empty string on failure.
# @return: 0 on success, non-zero on failure.
translate_with_lingva() {
    local source_text="$1"
    local target_lang_code="$2"
    local source_lang="$DEFAULT_LANGUAGE" # Use the global default language

    local ip_check_file="${CACHE_DIR}/network.ch" # ok/版で使用
    local wget_options="" # ok/版で使用
    local retry_count=0
    local network_type="" # ok/版で使用
    local temp_file="${BASE_DIR}/lingva_response_$$.tmp" # Use PID for temp file uniqueness (current version style)
    local api_url=""
    local translated_text="" # Renamed from 'translated' in ok/ version for clarity

    # --- ok/版のロジック開始 ---
    # 必要なディレクトリを確保
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null

    # ネットワーク接続状態を確認 (check_network_connectivity は common-system.sh 等で定義・ロードされている前提)
    if [ ! -f "$ip_check_file" ]; then
         if type check_network_connectivity >/dev/null 2>&1; then
            check_network_connectivity
         else
             debug_log "DEBUG" "translate_with_lingva: check_network_connectivity function not found."
             network_type="v4" # デフォルト
         fi
    fi
    network_type=$(cat "$ip_check_file" 2>/dev/null || echo "v4")
    debug_log "DEBUG" "translate_with_lingva: Determined network type: ${network_type}"

    # ネットワークタイプに基づいてwgetオプションを設定 (ok/版のロジック)
    # ★★★ 変更点: v4v6 の場合も v4 と同じく -4 を使用する ★★★
    case "$network_type" in
        "v4"|"v4v6") wget_options="-4" ;; # Treat v4v6 the same as v4
        "v6") wget_options="-6" ;;
        *) wget_options="" ;;
    esac
    debug_log "DEBUG" "translate_with_lingva: Initial wget options based on network type: ${wget_options}"

    # URLエンコードとAPI URLを事前に構築
    # (urlencode 関数の修正は上記で行いました)
    local encoded_text=$(urlencode "$source_text")
    # API URL は ok/ 版と同じ LINGVA_URL グローバル変数を使用する想定だが、
    # 現在の構造では内部定義が推奨されるため、内部定義URLを使用する。
    local base_lingva_url="https://lingva.ml/api/v1" # Current version's internal URL
    api_url="${base_lingva_url}/${source_lang}/${target_lang_code}/${encoded_text}"
    debug_log "DEBUG" "translate_with_lingva: API URL: ${api_url}"

    # リトライループ (ok/版は <= だったが、 < の方が一般的)
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        # ★★★ 変更点: ループ開始直後の debug_log を削除 ★★★
        # debug_log "DEBUG" "translate_with_lingva: Attempting download (Try $((retry_count + 1))/${API_MAX_RETRIES}) with options '${wget_options}'"

        # ★★★ 変更点: v4v6 リトライ時の IP 切り替えロジックを削除 ★★★
        # (該当する if ブロックを削除)

        # ★★★ 変更点: wget コマンドを直接実行 (eval, -L判断削除) ★★★
        # -L オプションは元々 Lingva では使われていなかったので変更なし
        # --tries=1 は ok/版に合わせて残す
        wget --no-check-certificate $wget_options -T $API_TIMEOUT --tries=1 -q -O "$temp_file" \
             --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
             "$api_url"
        local wget_exit_code=$?
        # ★★★ 変更点ここまで ★★★

        # レスポンスチェック (ok/版のロジック)
        if [ "$wget_exit_code" -eq 0 ] && [ -s "$temp_file" ]; then
            debug_log "DEBUG" "translate_with_lingva: Download successful."
            # ok/版の grep 条件と sed 抽出
            if grep -q '"translation"' "$temp_file"; then
                 # ★★★ 変更点: sed コマンドを1行に統合 (元々1行だったが念のため確認) ★★★
                translated_text=$(sed -n 's/.*"translation"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$temp_file" | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g')
                 # ★★★ 変更点ここまで ★★★

                if [ -n "$translated_text" ]; then
                    debug_log "DEBUG" "translate_with_lingva: Translation extracted successfully."
                    rm -f "$temp_file" 2>/dev/null
                    printf "%s\n" "$translated_text" # ok/版は printf "%s"
                    return 0 # Success
                else
                    debug_log "DEBUG" "translate_with_lingva: Failed to extract translation using sed."
                fi
            else
                 debug_log "DEBUG" "translate_with_lingva: Response does not contain 'translation' key."
                 # head -n 3 "$temp_file" | while IFS= read -r log_line; do debug_log "DEBUG" "Response line: $log_line"; done
            fi
        else
            debug_log "DEBUG" "translate_with_lingva: wget failed (Exit code: $wget_exit_code) or temp file is empty."
        fi
        # --- ok/版のロジック終了 ---

        # ファイル削除とリトライカウント増加、スリープ
        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            # ★★★ 変更点: ループ末尾の debug_log を削除 ★★★
            # debug_log "DEBUG" "translate_with_lingva: Retrying after sleep..."
            sleep 1
        fi
    done

    debug_log "DEBUG" "translate_with_lingva: Translation failed after ${API_MAX_RETRIES} attempts for text starting with: $(echo "$source_text" | cut -c 1-50)"
    rm -f "$temp_file" 2>/dev/null
    printf "" # Output empty string on failure
    return 1 # Failure
}

# Google翻訳APIを使用した翻訳関数 (修正版 - ループ内デバッグログ削除)
# @param $1: source_text (string) - The text to translate.
# @param $2: target_lang_code (string) - The target language code (e.g., "ja").
# @stdout: Translated text on success. Empty string on failure.
# @return: 0 on success, non-zero on failure.
translate_with_google() {
    local source_text="$1"
    local target_lang_code="$2"
    local source_lang="$DEFAULT_LANGUAGE" # Use the global default language

    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    local network_type=""
    local temp_file="${BASE_DIR}/google_response_$$.tmp" # Use PID for temp file uniqueness (current version style)
    local api_url=""
    local translated_text="" # Renamed from 'translated' in ok/ version for clarity

    mkdir -p "$(dirname "$temp_file")" 2>/dev/null

    if [ ! -f "$ip_check_file" ]; then
         if type check_network_connectivity >/dev/null 2>&1; then
            check_network_connectivity
         else
             debug_log "DEBUG" "translate_with_google: check_network_connectivity function not found."
             network_type="v4"
         fi
    fi
    network_type=$(cat "$ip_check_file" 2>/dev/null || echo "v4")
    debug_log "DEBUG" "translate_with_google: Determined network type: ${network_type}"

    case "$network_type" in
        "v4"|"v4v6") wget_options="-4" ;; # Treat v4v6 the same as v4
        "v6") wget_options="-6" ;;
        *) wget_options="" ;; # 不明な場合はオプションなし
    esac
    debug_log "DEBUG" "translate_with_google: Initial wget options based on network type: ${wget_options}"

    local encoded_text=$(urlencode "$source_text")
    api_url="https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang_code}&dt=t&q=${encoded_text}"
    debug_log "DEBUG" "translate_with_google: API URL: ${api_url}"

    # リトライループ
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        wget --no-check-certificate $wget_options -T $API_TIMEOUT -q -O "$temp_file" --user-agent="Mozilla/5.0" "$api_url"
        local wget_exit_code=$?

        if [ "$wget_exit_code" -eq 0 ] && [ -s "$temp_file" ]; then
            if grep -q '^\s*\[\[\["' "$temp_file"; then
                translated_text=$(sed -e 's/^\s*\[\[\["//' -e 's/",".*//' "$temp_file" | sed -e 's/\\u003d/=/g' -e 's/\\u003c/</g' -e 's/\\u003e/>/g' -e 's/\\u0026/\&/g' -e 's/\\"/"/g' -e 's/\\n/\n/g' -e 's/\\r//g' -e 's/\\\\/\\/g')
                if [ -n "$translated_text" ]; then
                    rm -f "$temp_file" 2>/dev/null
                    printf "%s\n" "$translated_text"
                    return 0 # Success
                fi
            fi
        fi
        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            sleep 1
        fi
    done

    debug_log "DEBUG" "translate_with_google: Translation failed after ${API_MAX_RETRIES} attempts for text starting with: $(echo "$source_text" | cut -c 1-50)"
    rm -f "$temp_file" 2>/dev/null # 念のため削除
    printf "" # Output empty string on failure
    return 1 # Failure
}

# Function to create language-specific message database
# Arguments:
#   $1: target_lang (e.g., "ja") - ignored if ONLINE_TRANSLATION_ENABLED=yes
create_language_db() {
    local target_lang="$1" # Parameter is kept for potential future use, but api_lang is used for output filename and processing
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code) # Use the API-compatible language code
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local temp_file="${TRANSLATION_CACHE_DIR}/translation_output.tmp" # Check if this is still needed
    local cleaned_translation=""
    local current_api="" # Initialize current_api
    local ip_check_file="${CACHE_DIR}/network.ch"
    local network_status=""
    local aip_function_name="" # To store the selected AIP function name
    # --- 時間計測用変数 ---
    local start_time=""
    local end_time=""
    local elapsed_seconds=""
    # ---------------------
    local spinner_started="false" # To track if spinner was started
    local overall_success=0 # Track overall success (0=success)

    debug_log "DEBUG" "Creating language DB for target ${target_lang} using API language code ${api_lang}"

    # Check base DB file
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found: ${base_db}"
        printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_FAILED")")" >&2
        return 1
    fi

    # --- 計測開始 ---
    start_time=$(date +%s)
    # ---------------

    # --- Determine which AIP function to use ---
    # This logic should ideally be centralized if used elsewhere
    # (Assuming API_LIST is set externally or has a default)
    local domain_name="" # Domain name for spinner
    case "$API_LIST" in
        google)
            aip_function_name="aip_google_translate"
            domain_name="translate.googleapis.com"
            ;;
        lingva)
            aip_function_name="aip_lingva_translate"
            domain_name="lingva.ml"
            ;;
        *)
            # Default to Google if API_LIST is not set or invalid
            aip_function_name="aip_google_translate"
            domain_name="translate.googleapis.com"
            ;;
    esac

    if [ -z "$aip_function_name" ] || ! type "$aip_function_name" >/dev/null 2>&1; then
         debug_log "ERROR" "Selected AIP function '$aip_function_name' is not available. Falling back to original text."
         # Set overall_success or handle error as needed
         overall_success=2 # Indicate partial failure/fallback
         # Fallback logic: Copy original text instead of translating
         # This part needs careful consideration based on desired behavior
         # For now, let's assume we proceed but use original text (handled below)
         ONLINE_TRANSLATION_ENABLED="no" # Force offline mode if function is missing
    else
         debug_log "DEBUG" "Using AIP function: $aip_function_name ($domain_name)"
    fi
    # --- End AIP function determination ---


    # Start spinner if available
    if type start_spinner >/dev/null 2>&1; then
        # Use the determined domain_name for the spinner message
        start_spinner "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name")")" "blue"
        spinner_started="true"
        debug_log "DEBUG" "Spinner started for domain: ${domain_name}"
    else
        debug_log "DEBUG" "start_spinner function not found. Spinner not shown."
        # Display message directly if spinner is not available
        printf "%s\n" "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name")")"
    fi


    # Create/overwrite the output DB file with header
    # Use api_lang for the output filename
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
# Translation generated using: ${aip_function_name}
# Target Language: ${api_lang}
EOF


    # Check network connectivity only if online translation is intended
    if [ "$ONLINE_TRANSLATION_ENABLED" = "yes" ]; then
        if [ ! -f "$ip_check_file" ]; then
            debug_log "DEBUG" "Network status file not found, checking connectivity"
            if type check_network_connectivity >/dev/null 2>&1; then
                check_network_connectivity
            else
                debug_log "ERROR" "check_network_connectivity function not found, cannot check network"
                 network_status="" # Assume no network
            fi
        fi
        # Get network status if file exists
        if [ -f "$ip_check_file" ]; then
            network_status=$(cat "$ip_check_file")
            debug_log "DEBUG" "Network status: ${network_status}"
        else
            debug_log "DEBUG" "Could not determine network status, assuming offline"
            network_status="" # Assume offline if file check failed or function was missing
        fi
        # If no network, force offline mode for the rest of the function
        if [ -z "$network_status" ]; then
            debug_log "INFO" "Network unavailable, proceeding in offline mode (using original text)."
            ONLINE_TRANSLATION_ENABLED="no"
        fi
    fi


    # Loop through the base DB entries using redirection (more efficient than pipe)
    while IFS= read -r line; do
        # Skip comment lines and empty lines efficiently
        case "$line" in \#*|"") continue ;; esac

        # --- MODIFIED PART: Use case statement for efficient language/other line check ---
        case "$line" in
            "${DEFAULT_LANGUAGE}|"*)
                # Line starts with the default language prefix, proceed
                ;;
            *)
                # Line does NOT start with the default language prefix (e.g., SCRIPT_VERSION), skip
                continue
                ;;
        esac
        # --- END MODIFIED PART ---

        # Extract key and value using shell parameter expansion (efficient)
        # Assumes format "LANG|KEY=VALUE" and we've already filtered for DEFAULT_LANGUAGE
        local line_content=${line#*|}   # Remove "LANG|" prefix
        local key=${line_content%%=*}    # Extract key before first '='
        local value=${line_content#*=}   # Extract value after first '='

        # Skip if key or value extraction failed (e.g., line format issue)
        if [ -z "$key" ] || [ -z "$value" ]; then
            debug_log "WARNING" "Skipping malformed line: $line"
            continue
        fi

        # --- Translation or Original Text Logic ---
        local translated_text=""
        local exit_code=1 # Default to failure

        # Only attempt online translation if enabled and function is valid
        if [ "$ONLINE_TRANSLATION_ENABLED" = "yes" ] && [ "$overall_success" -ne 2 ]; then # Check overall_success in case function was invalid
            # Generate cache key
            local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"

            # Check cache first
            if [ -f "$cache_file" ]; then
                translated_text=$(cat "$cache_file")
                exit_code=0 # Cache hit is success
                debug_log "DEBUG" "Cache hit for key '$key'"
            else
                # Cache miss, call the AIP function
                translated_text=$("$aip_function_name" "$value" "$api_lang") # Pass api_lang as target
                exit_code=$?
                debug_log "DEBUG" "API call for key '$key' (Exit code: $exit_code)"

                # Save to cache if successful and result is not empty
                if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
                    mkdir -p "$(dirname "$cache_file")"
                    printf "%s\n" "$translated_text" > "$cache_file"
                fi
            fi
        else
            # Offline mode or AIP function failed initialization, use original value
            translated_text="$value"
            exit_code=0 # Using original text is considered "successful" for this line's processing
            if [ "$overall_success" -ne 2 ]; then # Avoid redundant log if function failed init
                 debug_log "DEBUG" "Using original text for key '$key' (Offline mode or network unavailable)"
            fi
        fi

        # --- Output Line ---
        # Always output a line, either translated or original
        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            # Basic unescaping might be needed depending on API output, handle here if necessary
            # local decoded=$(printf "%b" "$translated_text")
            printf "%s|%s=%s\n" "$api_lang" "$key" "$translated_text" >> "$output_db"
        else
            # Log failure and use original value if translation failed and wasn't handled by offline mode
             debug_log "WARNING" "Translation failed (Code: $exit_code) or empty result for key '$key'. Using original value."
             overall_success=2 # Mark as partial failure if an online attempt failed
            printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
        fi
        # --- End Output Line ---

    done < "$base_db" # Read from the base DB file

    # --- 計測終了 & 計算 ---
    end_time=$(date +%s)
    elapsed_seconds=$((end_time - start_time))
    # ----------------------

    # Stop spinner after the loop
    if [ "$spinner_started" = "true" ]; then
        if type stop_spinner >/dev/null 2>&1; then
            local final_message=""
            local spinner_status="success" # Default to success color/icon

            if [ "$overall_success" -eq 0 ]; then
                final_message=$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds")
            elif [ "$overall_success" -eq 2 ]; then
                # Partial failure (some translations failed, or AIP function invalid)
                final_message=$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds") # Assuming a partial success key exists
                spinner_status="warning" # Use a warning color/icon
            else
                # Complete failure (e.g., base DB not found - handled earlier, but as fallback)
                final_message=$(get_message "MSG_TRANSLATION_FAILED")
                spinner_status="failure"
            fi
            # Fallback if message key doesn't exist or get_message fails
            if [ -z "$final_message" ]; then
                final_message="Translation process finished (${elapsed_seconds}s)."
            fi

            stop_spinner "$final_message" "$spinner_status"
            debug_log "INFO" "Translation task completed in ${elapsed_seconds} seconds. Status: ${spinner_status}"
        else
            debug_log "DEBUG" "stop_spinner function not found."
            # Print final status directly if spinner stop is unavailable
            if [ "$overall_success" -eq 0 ]; then
                 printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Translation created (${elapsed_seconds}s)")")"
            else
                 printf "%s\n" "$(color yellow "$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")")" # Assuming partial key
            fi
        fi
    fi

    # Add the completion marker key at the end of the file
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    printf "%s|%s=%s\n" "$api_lang" "$marker_key" "true" >> "$output_db"
    debug_log "DEBUG" "Completion marker added to ${output_db}"

    debug_log "DEBUG" "Language DB creation process completed for ${api_lang}"
    return "$overall_success" # Return 0 for full success, 1 for critical fail, 2 for partial
}

# 翻訳DB作成関数 (責務: DBファイル作成、AIP関数呼び出し、スピナー制御)
# @param $1: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - The base API endpoint URL (used ONLY for spinner display via domain_name extraction, NOT passed to AIP func)
# @param $3: domain_name (string) - The domain name for spinner display (e.g., "translate.googleapis.com")
# @param $4: target_lang_code (string) - The target language code (e.g., "ja")
# @return: 0 on success, 1 on base DB not found, 2 if AIP function fails consistently (though it writes original text)
GREP_create_language_db() {
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
        debug_log "DEBUG" "Base message DB not found: $base_db. Cannot create target DB."
        printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_FAILED")")" >&2
        return 1
    fi

    # Start spinner before the loop
    if type start_spinner >/dev/null 2>&1; then
        start_spinner "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name")")" "blue"
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

    # --- 変更点: ループ処理を ok/ 版の grep | while 形式に変更 ---
    # Loop through the base DB entries (using grep | while like ok/ version)
    grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do
        # ok/版のループ内には case "$line" in \#*|"") continue ;; や grep チェックがなかったので、それに倣う
        # ただし、キー・バリュー抽出の失敗チェックは残す

        local line_content=${line#*|} # Remove "en|" prefix
        local key=${line_content%%=*}   # Get key before '='
        local value=${line_content#*=}  # Get value after '='

        if [ -z "$key" ] || [ -z "$value" ]; then
            # ★★★ 変更点: ループ内の debug_log を削除 ★★★ (元ソースに準拠)
            # debug_log "DEBUG" "Skipping invalid line from grep output: $line"
            continue
        fi

        # --- Directly call the AIP function (変更なし) ---
        local translated_text=""
        local exit_code=1 # Default to failure

        # ★★★ 変更点: ループ内の debug_log を削除 ★★★ (元ソースに準拠)
        # debug_log "DEBUG" "Attempting translation for key '${key}' using '${aip_function_name}'"
        translated_text=$("$aip_function_name" "$value" "$target_lang_code")
        exit_code=$?

        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            # ★★★ 変更点: ループ内の debug_log を削除 ★★★ (元ソースに準拠)
            # debug_log "DEBUG" "Translation successful for key '${key}'"
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$translated_text" >> "$output_db"
        else
            # ★★★ 変更点: ループ内の debug_log を削除 ★★★ (元ソースに準拠)
            # debug_log "DEBUG" "Translation failed (Exit code: $exit_code) or returned empty for key '${key}'. Using original text."
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$value" >> "$output_db"
            # overall_success=2 # Indicate partial failure if needed (Uncomment if specific tracking is needed)
        fi
        # --- End AIP function call ---

    done
    # --- 変更点 終了 ---

    # Stop spinner after the loop
    if [ "$spinner_started" = "true" ]; then
        if type stop_spinner >/dev/null 2>&1; then
            stop_spinner "$(get_message "MSG_TRANSLATING_CREATED")" "success"
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

# 翻訳DB作成関数 (責務: DBファイル作成、AIP関数呼び出し、スピナー制御、時間計測)
# @param $1: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - The base API endpoint URL (used ONLY for spinner display via domain_name extraction, NOT passed to AIP func)
# @param $3: domain_name (string) - The domain name for spinner display (e.g., "translate.googleapis.com")
# @param $4: target_lang_code (string) - The target language code (e.g., "ja")
# @return: 0 on success, 1 on base DB not found, 2 if AIP function fails consistently (though it writes original text)
OK_create_language_db() {
    local aip_function_name="$1"
    local api_endpoint_url="$2" # Passed URL for context/potential future use, but mainly for domain name below
    local domain_name="$3"      # Explicitly passed domain name for spinner
    local target_lang_code="$4"

    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local output_db="${BASE_DIR}/message_${target_lang_code}.db"
    local spinner_started="false"
    local overall_success=0 # Assume success initially
    # --- 時間計測用変数 ---
    local start_time=""
    local end_time=""
    local elapsed_seconds=""
    # ---------------------

    debug_log "DEBUG" "Creating language DB for target '${target_lang_code}' using function '${aip_function_name}' with domain '${domain_name}'"

    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found: $base_db. Cannot create target DB."
        printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_FAILED")")" >&2
        return 1
    fi

    # --- 計測開始 ---
    start_time=$(date +%s)
    # ---------------

    # Start spinner before the loop
    if type start_spinner >/dev/null 2>&1; then
        start_spinner "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name")")" "blue"
        spinner_started="true"
        debug_log "DEBUG" "Spinner started for domain: ${domain_name}"
    else
        debug_log "DEBUG" "start_spinner function not found. Spinner not shown."
    fi

    # Create/overwrite the output DB with the header
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
# Translation generated using: ${aip_function_name}
# Target Language: ${target_lang_code}
EOF

    LC_ALL=C grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do

        local line_content=${line#*|} # Remove "en|" prefix
        local key=${line_content%%=*}   # Get key before '='
        local value=${line_content#*=}  # Get value after '='

        if [ -z "$key" ] || [ -z "$value" ]; then
            continue
        fi

        # --- Directly call the AIP function ---
        local translated_text=""
        local exit_code=1 # Default to failure

        translated_text=$("$aip_function_name" "$value" "$target_lang_code")
        exit_code=$?

        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$translated_text" >> "$output_db"
        else
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$value" >> "$output_db"
        fi
        # --- End AIP function call ---

    done

    # --- 計測終了 & 計算 ---
    end_time=$(date +%s)
    elapsed_seconds=$((end_time - start_time))
    # ----------------------

    # Stop spinner after the loop
    if [ "$spinner_started" = "true" ]; then
        if type stop_spinner >/dev/null 2>&1; then
            # --- 変更点: 成功メッセージに時間を埋め込んでから stop_spinner に渡す ---
            local final_success_message=""
            if [ "$overall_success" -eq 0 ]; then
                 # get_message にパラメータ "s=$elapsed_seconds" を渡して時間を埋め込む
                final_success_message=$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds")
            else
                 # 失敗時は元のメッセージキー（時間なし）を使うか、別の失敗キーを使う (ここでは元のキーを使用)
                 # もし失敗時も時間を表示したい場合は、上の if ブロックの外で final_success_message を設定する
                final_success_message=$(get_message "MSG_TRANSLATING_CREATED") # 時間プレースホルダーは置換されない
            fi

            # stop_spinner の第1引数に最終的なメッセージを渡す
            # 第2引数は成功/失敗の状態を示す (ここでは "success" 固定だが、overall_successに応じて変えることも可能)
            stop_spinner "$final_success_message" "success" # "success" はスピナーの見た目（色やアイコン）に影響する想定
            # -----------------------------------------------------------------
            debug_log "DEBUG" "Translation task completed in ${elapsed_seconds} seconds." # INFOログはそのまま

            # --- 変更点: 以前提案した printf での別行表示は不要なため削除済み ---
        else
            debug_log "DEBUG" "stop_spinner function not found."
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
             debug_log "DEBUG" "translate_main: Target DB '${target_db}' exists and is complete for '${lang_code}'."
             # --- 修正 --- 既存DBが完了している場合にのみ表示
             display_detected_translation
             return 0 # <<< Early return: DB exists and is complete
        else
             debug_log "DEBUG" "translate_main: Target DB '${target_db}' exists but is incomplete for '${lang_code}'. Proceeding with creation."
        fi
    else
        debug_log "DEBUG" "translate_main: Target DB '${target_db}' does not exist. Proceeding with creation."
    fi

    # --- Proceed with Translation Process ---
    # (Steps 4 & 5: Find function, determine domain - remain the same as f7ff132)
    # 4. Find the first available translation function...
    local selected_func=""
    local func_name=""
    if [ -z "$AI_TRANSLATION_FUNCTIONS" ]; then
         debug_log "DEBUG" "translate_main: AI_TRANSLATION_FUNCTIONS global variable is not set or empty."
         display_message "error" "$(get_message "MSG_ERR_NO_TRANS_FUNC_VAR")"
         return 1
    fi
    set -f; set -- $AI_TRANSLATION_FUNCTIONS; set +f
    for func_name in "$@"; do
        if type "$func_name" >/dev/null 2>&1; then selected_func="$func_name"; break; fi
    done
    if [ -z "$selected_func" ]; then
        debug_log "DEBUG" "translate_main: No available translation functions found from list: '${AI_TRANSLATION_FUNCTIONS}'."
        display_message "error" "$(get_message "MSG_ERR_NO_TRANS_FUNC_AVAIL" "list=$AI_TRANSLATION_FUNCTIONS")"
        return 1
    fi
    debug_log "DEBUG" "translate_main: Selected translation function: ${selected_func}"

    # 5. Determine API URL and Domain Name for spinner...
    local api_endpoint_url=""
    local domain_name=""
    case "$selected_func" in
        "translate_with_google") api_endpoint_url="..."; domain_name="translate.googleapis.com" ;;
        "translate_with_lingva") api_endpoint_url="..."; domain_name="lingva.ml" ;;
        *) debug_log "DEBUG" "..."; api_endpoint_url="N/A"; domain_name="$selected_func" ;;
    esac
    debug_log "DEBUG" "translate_main: Using Domain '${domain_name}' for spinner..."


    # 6. Call create_language_db
    debug_log "DEBUG" "translate_main: Calling create_language_db for language '${lang_code}' using function '${selected_func}'"
    create_language_db "$selected_func" "$api_endpoint_url" "$domain_name" "$lang_code"
    db_creation_result=$?
    debug_log "DEBUG" "translate_main: create_language_db finished with status: ${db_creation_result}"

    # 7. Handle Result and Display Info ONLY on Success
    if [ "$db_creation_result" -eq 0 ]; then
        debug_log "DEBUG" "translate_main: Language DB creation successful for ${lang_code}."
        # --- 修正 --- DB作成成功後にのみ表示
        display_detected_translation
        return 0 # Success
    else
        debug_log "DEBUG" "translate_main: Language DB creation failed for ${lang_code} (Exit status: ${db_creation_result})."
        # --- 修正 --- 失敗時はエラーメッセージのみ表示 (display_messageは元々あった)
        if [ "$db_creation_result" -ne 1 ]; then # Avoid duplicate if base DB missing
             display_message "error" "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code")"
        fi
        # --- 修正 --- 失敗時は display_detected_translation を呼び出さない
        return "$db_creation_result" # Propagate error code
    fi
}
