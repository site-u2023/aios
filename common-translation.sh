
#!/bin/sh

SCRIPT_VERSION="2025-04-28-00-01"

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
TR_DIR="${TR_DIR:-$BASE_DIR/translation}"

# オンライン翻訳を有効化 (create_language_db logic removed reliance on this, but keep for potential external checks)
ONLINE_TRANSLATION_ENABLED="yes"

# API設定 (Global defaults)
API_TIMEOUT="${API_TIMEOUT:-5}"
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"
# AI_TRANSLATION_FUNCTIONS should be defined globally (e.g., in main script or config)
# Example: AI_TRANSLATION_FUNCTIONS="translate_with_google translate_with_lingva"

# WGET Capability - Optional, AIP functions simplified to not rely heavily on it
WGET_CAPABILITY_DETECTED="" # Initialized by translate_main if detect_wget_capabilities exists

AI_TRANSLATION_FUNCTIONS="translate_with_google" # 使用したい関数名を空白区切りで列挙

# --- Set MAX_PARALLEL_TASKS ---
MAX_PARALLEL_TASKS="${MAX_PARALLEL_TASKS:-$(head -n 1 "${CACHE_DIR}/cpu_core.ch" 2>/dev/null)}"

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

GOOD_translate_with_google() {
    local source_text="$1"
    local target_lang_code="$2"
    local source_lang="$DEFAULT_LANGUAGE" # Use the global default language

    # --- network.ch依存をip_type.chに変更 ---
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    local wget_options=""
    local retry_count=0
    # --- temp_file関連の変数は元から未使用 ---
    local api_url=""
    local translated_text=""
    local wget_exit_code=0
    local response_data="" # Variable to store wget output

    # Ensure BASE_DIR exists (still needed for potential cache files, etc.)
    mkdir -p "$BASE_DIR" 2>/dev/null || { debug_log "DEBUG" "translate_with_google: Failed to create base directory $BASE_DIR"; return 1; }

    # --- IPバージョン判定（ip_type.chの内容をそのままwget_optionsに） ---
    if [ ! -f "$ip_type_file" ]; then
        echo "Network is not available. (ip_type.ch not found)" >&2
        return 1
    fi
    wget_options=$(cat "$ip_type_file" 2>/dev/null)
    if [ -z "$wget_options" ] || [ "$wget_options" = "unknown" ]; then
        echo "Network is not available. (ip_type.ch is unknown or empty)" >&2
        return 1
    fi

    local encoded_text=$(urlencode "$source_text")
    if [ -z "$source_lang" ] || [ -z "$target_lang_code" ]; then
        debug_log "DEBUG" "translate_with_google: Source or target language code is empty (source='$source_lang', target='$target_lang_code')."
        return 1
    fi
    api_url="https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang_code}&dt=t&q=${encoded_text}"

    # RES_OPTIONSによるDNSタイムアウト短縮（関数内限定）
    export RES_OPTIONS="timeout:1 attempts:1"

    # リトライループ
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        response_data=""
        response_data=$(wget --no-check-certificate $wget_options -T $API_TIMEOUT -q -O - --user-agent="Mozilla/5.0" "$api_url")
        wget_exit_code=$?
        if [ "$wget_exit_code" -eq 0 ] && [ -n "$response_data" ]; then
            if echo "$response_data" | grep -q '^\s*\[\[\["'; then
                translated_text=$(printf %s "$response_data" | awk '
                BEGIN { out = "" }
                /^\s*\[\[\["/ {
                sub(/^\s*\[\[\["/, "")
                split($0, a, /","/)
                out = a[1]
                gsub(/\\u003d/, "=", out)
                gsub(/\\u003c/, "<", out)
                gsub(/\\u003e/, ">", out)
                gsub(/\\u0026/, "&", out)
                gsub(/\\"/, "\"", out)
                gsub(/\\n/, "\n", out)
                gsub(/\\r/, "", out)
                gsub(/\\\\/, "\\", out)
                print out
                exit
            }
            ')
                    
                if [ -n "$translated_text" ]; then
                    printf "%s\n" "$translated_text"
                    return 0 # Success
                fi
            fi
        else
            # Log wget failure or empty response
            if [ "$wget_exit_code" -ne 0 ]; then
                debug_log "DEBUG" "translate_with_google: wget failed with exit code $wget_exit_code"
            elif [ -z "$response_data" ]; then
                 debug_log "DEBUG" "translate_with_google: wget succeeded (code 0) but response data is empty!"
            fi
            # Fall through to retry logic
        fi

        # --- Retry Logic ---
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            debug_log "DEBUG" "translate_with_google: Retrying in 1 second..."
            sleep 1
        fi
    done

    debug_log "DEBUG" "translate_with_google: Failed to translate '$source_text' after $API_MAX_RETRIES attempts."
    printf "" # Output empty string on failure
    return 1 # Failure
}


translate_with_google() {
    local source_text="$1"
    local target_lang_code="$2"
    local source_lang="$DEFAULT_LANGUAGE" # Use the global default language

    # --- network.ch依存をip_type.chに変更 ---
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    local wget_options=""
    local retry_count=0
    # --- temp_file関連の変数は元から未使用 ---
    local api_url=""
    local translated_text=""
    local wget_exit_code=0
    local response_data="" # Variable to store wget output

    # Ensure BASE_DIR exists (still needed for potential cache files, etc.)
    mkdir -p "$BASE_DIR" 2>/dev/null || { debug_log "DEBUG" "translate_with_google: Failed to create base directory $BASE_DIR"; return 1; }

    # --- IPバージョン判定（ip_type.chの内容をそのままwget_optionsに） ---
    if [ ! -f "$ip_type_file" ]; then
        echo "Network is not available. (ip_type.ch not found)" >&2
        return 1
    fi
    wget_options=$(cat "$ip_type_file" 2>/dev/null)
    if [ -z "$wget_options" ] || [ "$wget_options" = "unknown" ]; then
        echo "Network is not available. (ip_type.ch is unknown or empty)" >&2
        return 1
    fi

    local encoded_text=$(urlencode "$source_text")
    if [ -z "$source_lang" ] || [ -z "$target_lang_code" ]; then
        debug_log "DEBUG" "translate_with_google: Source or target language code is empty (source='$source_lang', target='$target_lang_code')."
        return 1
    fi
    api_url="https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang_code}&dt=t&q=${encoded_text}"

    # RES_OPTIONSによるDNSタイムアウト短縮（関数内限定）
    export RES_OPTIONS="timeout:1 attempts:1"

    # リトライループ
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        response_data=""
        response_data=$(wget --no-check-certificate $wget_options -T $API_TIMEOUT -q -O - --user-agent="Mozilla/5.0" "$api_url")
        wget_exit_code=$?
        if [ "$wget_exit_code" -eq 0 ] && [ -n "$response_data" ]; then
            if echo "$response_data" | grep -q '^\s*\[\[\["'; then
                translated_text=$(printf %s "$response_data" | sed -e 's/^\s*\[\[\["//' \
                    -e 's/",".*//' \
                    -e 's/\\u003d/=/g' \
                    -e 's/\\u003c/</g' \
                    -e 's/\\u003e/>/g' \
                    -e 's/\\u0026/\&/g' \
                    -e 's/\\"/"/g' \
                    -e 's/\\n/\n/g' \
                    -e 's/\\r//g' \
                    -e 's/\\\\/\\/g')
                    
                if [ -n "$translated_text" ]; then
                    printf "%s\n" "$translated_text"
                    return 0 # Success
                fi
            fi
        else
            # Log wget failure or empty response
            if [ "$wget_exit_code" -ne 0 ]; then
                debug_log "DEBUG" "translate_with_google: wget failed with exit code $wget_exit_code"
            elif [ -z "$response_data" ]; then
                 debug_log "DEBUG" "translate_with_google: wget succeeded (code 0) but response data is empty!"
            fi
            # Fall through to retry logic
        fi

        # --- Retry Logic ---
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            debug_log "DEBUG" "translate_with_google: Retrying in 1 second..."
            sleep 1
        fi
    done

    debug_log "DEBUG" "translate_with_google: Failed to translate '$source_text' after $API_MAX_RETRIES attempts."
    printf "" # Output empty string on failure
    return 1 # Failure
}

OK_translate_with_google() {
    local source_text="$1"
    local target_lang_code="$2"
    local source_lang="$DEFAULT_LANGUAGE" # Use the global default language

    # --- network.ch依存をip_type.chに変更 ---
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    local wget_options=""
    local retry_count=0
    # --- temp_file関連の変数は元から未使用 ---
    local api_url=""
    local translated_text=""
    local wget_exit_code=0
    local response_data="" # Variable to store wget output

    # Ensure BASE_DIR exists (still needed for potential cache files, etc.)
    mkdir -p "$BASE_DIR" 2>/dev/null || { debug_log "DEBUG" "translate_with_google: Failed to create base directory $BASE_DIR"; return 1; }

    # --- IPバージョン判定（ip_type.chの内容をそのままwget_optionsに） ---
    if [ ! -f "$ip_type_file" ]; then
        echo "Network is not available. (ip_type.ch not found)" >&2
        return 1
    fi
    wget_options=$(cat "$ip_type_file" 2>/dev/null)
    if [ -z "$wget_options" ] || [ "$wget_options" = "unknown" ]; then
        echo "Network is not available. (ip_type.ch is unknown or empty)" >&2
        return 1
    fi

    local encoded_text=$(urlencode "$source_text")
    if [ -z "$source_lang" ] || [ -z "$target_lang_code" ]; then
        debug_log "DEBUG" "translate_with_google: Source or target language code is empty (source='$source_lang', target='$target_lang_code')."
        return 1
    fi
    api_url="https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang_code}&dt=t&q=${encoded_text}"

    # リトライループ
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        response_data=""
        response_data=$(wget --no-check-certificate $wget_options -T $API_TIMEOUT -q -O - --user-agent="Mozilla/5.0" "$api_url")
        wget_exit_code=$?
        if [ "$wget_exit_code" -eq 0 ] && [ -n "$response_data" ]; then
            if echo "$response_data" | grep -q '^\s*\[\[\["'; then
                translated_text=$(echo "$response_data" | sed -e 's/^\s*\[\[\["//' -e 's/",".*//' | sed -e 's/\\u003d/=/g' -e 's/\\u003c/</g' -e 's/\\u003e/>/g' -e 's/\\u0026/\&/g' -e 's/\\"/"/g' -e 's/\\n/\n/g' -e 's/\\r//g' -e 's/\\\\/\\/g')

                if [ -n "$translated_text" ]; then
                    printf "%s\n" "$translated_text"
                    return 0 # Success
                fi
            fi
        else
            # Log wget failure or empty response
            if [ "$wget_exit_code" -ne 0 ]; then
                debug_log "DEBUG" "translate_with_google: wget failed with exit code $wget_exit_code"
            elif [ -z "$response_data" ]; then
                 debug_log "DEBUG" "translate_with_google: wget succeeded (code 0) but response data is empty!"
            fi
            # Fall through to retry logic
        fi

        # --- Retry Logic ---
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            debug_log "DEBUG" "translate_with_google: Retrying in 1 second..."
            # sleep 1 # Use integer sleep
        fi
    done

    debug_log "DEBUG" "translate_with_google: Failed to translate '$source_text' after $API_MAX_RETRIES attempts."
    printf "" # Output empty string on failure
    return 1 # Failure
}

# Function to create language DB by processing base DB in parallel (with spinner and timing - Revised Spinner Keys)
# Usage: create_language_db_parallel <aip_function_name> <api_endpoint_url> <domain_name> <target_lang_code>
create_language_db_parallel() {
    local aip_function_name="$1"
    local api_endpoint_url="$2"  # Passed for logging/context
    local domain_name="$3"       # Used for spinner message
    local target_lang_code="$4"

    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local final_output_dir="/tmp/aios" # Consider making this configurable or use BASE_DIR
    local final_output_file="${final_output_dir}/message_${target_lang_code}.db"
    local tmp_input_prefix="${TR_DIR}/message_${target_lang_code}.tmp.in."
    local tmp_output_prefix="${TR_DIR}/message_${target_lang_code}.tmp.out."
    # --- Time measurement variables ---
    local start_time=""
    local end_time=""
    local elapsed_seconds=""
    # --- Spinner variables ---
    local spinner_started="false" # Flag to track spinner state
    # --- Marker Key ---
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    # ---------------------
    local total_lines=0
    local lines_per_task=0
    local extra_lines=0
    local i=0
    local pids=""
    local pid=""
    local exit_status=0 # 0:success, 1:critical error, 2:partial success

    # --- Pre-checks ---
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base DB file not found: $base_db"
        printf "%s\n" "$(color red "$(get_message "MSG_ERR_BASE_DB_NOT_FOUND" "file=$base_db" "default=Base DB not found: $base_db")")" >&2
        return 1
    fi
    if [ -z "$aip_function_name" ] || [ -z "$target_lang_code" ]; then
        debug_log "DEBUG" "Missing required arguments: AIP function name or target language code."
        printf "%s\n" "$(color red "$(get_message "MSG_ERR_MISSING_ARGS" "default=Missing required arguments for parallel translation.")")" >&2
        return 1
    fi

    # --- Prepare directories and cleanup ---
    mkdir -p "$TR_DIR" || { debug_log "DEBUG" "Failed to create temporary directory: $TR_DIR"; return 1; }
    mkdir -p "$final_output_dir" || { debug_log "DEBUG" "Failed to create final output directory: $final_output_dir"; return 1; }

    # Trap for file cleanup on INT, TERM, or EXIT
    # shellcheck disable=SC2064
    trap "debug_log 'DEBUG' 'Trap cleanup: Removing temporary files...'; rm -f ${tmp_input_prefix}* ${tmp_output_prefix}*" INT TERM EXIT

    # --- Logging ---
    debug_log "DEBUG" "Starting parallel translation for language '$target_lang_code' using function '$aip_function_name' (API: '$api_endpoint_url', Domain: '$domain_name')."
    debug_log "DEBUG" "Base DB: $base_db"
    debug_log "DEBUG" "Temporary file directory: $TR_DIR"
    debug_log "DEBUG" "Final output file: $final_output_file"
    debug_log "DEBUG" "Max parallel tasks: $MAX_PARALLEL_TASKS"

    # --- Start Timing and Spinner ---
    start_time=$(date +%s)
    # --- CHANGE: Use MSG_TRANSLATING_CURRENTLY from old function ---
    local spinner_msg_key="MSG_TRANSLATING_CURRENTLY"
    local spinner_default_msg="Currently translating: $domain_name" # Default matches old function
    # Use 'api' parameter name consistent with old function's get_message call
    start_spinner "$(color blue "$(get_message "$spinner_msg_key" "api=$domain_name" "default=$spinner_default_msg")")"
    # -----------------------------------------------------------
    spinner_started="true"
    # --------------------------------

    # --- Split Base DB ---
    debug_log "DEBUG" "Splitting base DB into $MAX_PARALLEL_TASKS parts..."
    total_lines=$(awk 'NR>1{c++} END{print c}' "$base_db")
    if [ "$total_lines" -le 0 ]; then
        debug_log "DEBUG" "No lines to translate (excluding header)."
        # Write header only
        cat > "$final_output_file" <<-EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
# Translation generated using: ${aip_function_name}
# Target Language: ${target_lang_code}
EOF
        if [ $? -ne 0 ]; then
             debug_log "DEBUG" "Failed to write header to $final_output_file"
             exit_status=1
        fi
    else
        # Calculate lines per task
        lines_per_task=$((total_lines / MAX_PARALLEL_TASKS))
        extra_lines=$((total_lines % MAX_PARALLEL_TASKS))
        if [ "$lines_per_task" -eq 0 ] && [ "$total_lines" -gt 0 ]; then
            lines_per_task=1
            debug_log "DEBUG" "Fewer lines ($total_lines) than tasks ($MAX_PARALLEL_TASKS). Adjusting tasks."
        fi

        # awk splitting logic
        awk -v num_tasks="$MAX_PARALLEL_TASKS" \
            -v prefix="$tmp_input_prefix" \
            'NR > 1 {
                task_num = (NR - 2) % num_tasks + 1;
                print $0 >> (prefix task_num);
            }' "$base_db"
        if [ $? -ne 0 ]; then
            debug_log "DEBUG" "Failed to split base DB using awk."
            exit_status=1
            if [ "$spinner_started" = "true" ]; then
                # Use a specific message key or a default one for split failure
                stop_spinner "$(get_message "MSG_TRANSLATION_FAILED_SPLIT" "default=Translation failed during DB split.")" "error"
            fi
            return 1
        fi
        debug_log "DEBUG" "Base DB split complete."
    fi
    # ---------------------

    # --- Execute tasks only if split was successful and lines exist ---
    if [ "$exit_status" -eq 0 ] && [ "$total_lines" -gt 0 ]; then
        debug_log "DEBUG" "Launching parallel translation tasks..."
        i=1
        while [ "$i" -le "$MAX_PARALLEL_TASKS" ]; do
            local tmp_input_file="${tmp_input_prefix}${i}"
            local tmp_output_file="${tmp_output_prefix}${i}"

            if [ ! -f "$tmp_input_file" ]; then
                 debug_log "DEBUG" "Temporary input file ${tmp_input_file} not found (likely no lines for this task), skipping task $i."
                 i=$(($i + 1))
                 continue
            fi
            >"$tmp_output_file" || {
                debug_log "DEBUG" "Failed to create temporary output file: $tmp_output_file";
                exit_status=1;
                if [ "$spinner_started" = "true" ]; then
                    stop_spinner "$(get_message "MSG_TRANSLATION_FAILED_TMPFILE" "default=Translation failed creating temporary file.")" "error"
                fi
                return 1
                break;
            }

            # Launch create_language_db in the background (Child process)
            # Ensure the child function receives the arguments it expects
            # Original child expected: base_db, output_db, target_lang, api_func
            # Here we pass the chunk files as base_db and output_db for the child
            create_language_db "$tmp_input_file" "$tmp_output_file" "$target_lang_code" "$aip_function_name" &
            pid=$!
            pids="$pids $pid"
            debug_log "DEBUG" "Launched task $i (PID: $pid) for input $tmp_input_file"
            i=$(($i + 1))
        done

        # --- Wait for tasks ---
        if [ -n "$pids" ]; then
             debug_log "DEBUG" "Waiting for launched tasks to complete..."
             for pid in $pids; do
                 wait "$pid"
                 local task_exit_status=$?
                 if [ "$task_exit_status" -ne 0 ]; then
                     if [ "$task_exit_status" -ne 2 ]; then
                         debug_log "DEBUG" "Task with PID $pid failed with critical exit status $task_exit_status."
                         exit_status=1
                     else
                          debug_log "DEBUG" "Task with PID $pid completed with partial success (exit status 2)."
                          [ "$exit_status" -eq 0 ] && exit_status=2
                     fi
                 else
                     debug_log "DEBUG" "Task with PID $pid completed successfully (exit status 0)."
                 fi
             done
             debug_log "DEBUG" "All launched tasks completed (Overall status: $exit_status)."
        else
             debug_log "DEBUG" "No tasks were launched."
        fi
    fi
    # -------------------------------------------------

    # --- Combine results if no critical error occurred ---
    if [ "$exit_status" -ne 1 ]; then
        if [ "$total_lines" -gt 0 ]; then
            debug_log "DEBUG" "Combining results into final output file: $final_output_file"
            # Write header using cat << EOF
            cat > "$final_output_file" <<-EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
# Translation generated using: ${aip_function_name}
# Target Language: ${target_lang_code}
EOF
            if [ $? -ne 0 ]; then
                 debug_log "DEBUG" "Failed to write header to $final_output_file"
                 exit_status=1
            else
                # Append results
                find "$TR_DIR" -name "message_${target_lang_code}.tmp.out.*" -print0 | xargs -0 -r cat >> "$final_output_file"
                if [ $? -ne 0 ]; then
                     debug_log "DEBUG" "Failed to combine temporary output files into $final_output_file"
                     if [ "$exit_status" -eq 0 ]; then exit_status=1; fi
                else
                     debug_log "DEBUG" "Successfully combined results."
                     # Add completion marker
                     printf "%s|%s=%s\n" "$target_lang_code" "$marker_key" "true" >> "$final_output_file"
                     debug_log "DEBUG" "Completion marker added to ${final_output_file}"
                fi
            fi
        elif [ "$exit_status" -eq 0 ]; then
             debug_log "DEBUG" "No lines were translated, final file contains only header."
        fi
    fi
    # ----------------------------------------------------

    # --- Stop Timing and Spinner (Final step before return) ---
    end_time=$(date +%s)
    if [ -n "$start_time" ]; then
        elapsed_seconds=$((end_time - start_time))
    else
        elapsed_seconds=0
    fi

    if [ "$spinner_started" = "true" ]; then
        local final_message=""
        local spinner_status="success"

        # --- CHANGE: Use message keys from old function ---
        if [ "$exit_status" -eq 0 ]; then
             if [ "$total_lines" -gt 0 ]; then
                 # Use MSG_TRANSLATING_CREATED for success
                 final_message=$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Language file created successfully (${elapsed_seconds}s)")
             else
                 # Keep specific message for zero lines case
                 final_message=$(get_message "MSG_TRANSLATION_NO_LINES_COMPLETE" "s=$elapsed_seconds" "default=Translation finished: No lines needed translation (${elapsed_seconds}s)")
             fi
        elif [ "$exit_status" -eq 2 ]; then
            # Use MSG_TRANSLATION_PARTIAL for partial success
            final_message=$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")
            spinner_status="warning"
        else # exit_status is 1 (critical error)
            # Use a generic failure key or keep the specific critical one
            # Using MSG_TRANSLATION_FAILED as a generic failure message from old context
            final_message=$(get_message "MSG_TRANSLATION_FAILED" "s=$elapsed_seconds" "default=Translation process failed after ${elapsed_seconds}s.")
            spinner_status="error"
        fi
        # ----------------------------------------------------
        stop_spinner "$final_message" "$spinner_status"
        debug_log "DEBUG" "Parallel translation task completed in ${elapsed_seconds} seconds. Overall Status: ${exit_status}"
    else
        # Fallback print (remains the same, uses corrected keys)
         if [ "$exit_status" -eq 0 ]; then
             printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Language file created successfully (${elapsed_seconds}s)")")"
         elif [ "$exit_status" -eq 2 ]; then
             printf "%s\n" "$(color yellow "$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")")"
         else
             printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_FAILED" "s=$elapsed_seconds" "default=Translation process failed after ${elapsed_seconds}s.")")"
         fi
    fi
    # -------------------------------

    return "$exit_status"
}

# Child function called by create_language_db_parallel (Revised: I/O Buffering with %b)
# This function now processes a *chunk* of the base DB and writes output once using %b.
# @param $1: input_chunk_file (string) - Path to the temporary input file containing a chunk of lines.
# @param $2: output_chunk_file (string) - Path to the temporary output file for this chunk.
# @param $3: target_lang_code (string) - The target language code (e.g., "ja").
# @param $4: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google").
# @return: 0 on success, 1 on critical error (read/write failure), 2 if any translation fails within this chunk (but write succeeded).
create_language_db() {
    local input_chunk_file="$1"
    local output_chunk_file="$2"
    local target_lang_code="$3"
    local aip_function_name="$4"

    local overall_success=0 # Assume success initially for this chunk, 2 indicates at least one translation failed
    local output_buffer=""  # Initialize buffer variable

    # Check if input file exists
    if [ ! -f "$input_chunk_file" ]; then
        debug_log "ERROR" "Child process: Input chunk file not found: $input_chunk_file"
        return 1 # Critical error for this child
    fi

    # Loop through the input chunk file
    while IFS= read -r line; do
        # Skip comments and empty lines
        case "$line" in \#*|"") continue ;; esac

        # Ensure line starts with the default language prefix
        case "$line" in
            "${DEFAULT_LANGUAGE}|"*)
                ;;
            *)
                continue
                ;;
        esac

        # Extract key and value
        local line_content=${line#*|}
        local key=${line_content%%=*}
        local value=${line_content#*=}

        if [ -z "$key" ] || [ -z "$value" ]; then
            continue
        fi

        # Call the provided AIP function
        local translated_text=""
        local exit_code=1

        translated_text=$("$aip_function_name" "$value" "$target_lang_code")
        exit_code=$?

        # --- CHANGE: Format line WITHOUT trailing \n, append literal '\n' to buffer ---
        local output_line=""
        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            # Format successful translation *without* newline
            output_line=$(printf "%s|%s=%s" "$target_lang_code" "$key" "$translated_text")
        else
            overall_success=2
            # Format original value *without* newline
            output_line=$(printf "%s|%s=%s" "$target_lang_code" "$key" "$value")
        fi
        # Append the formatted line and a literal '\n' sequence to the buffer
        output_buffer="${output_buffer}${output_line}\\n"
        # -------------------------------------------------------------------------

    done < "$input_chunk_file" # Read from the chunk input file

    # --- CHANGE: Write the entire buffer using printf %b to interpret \n ---
    printf "%b" "$output_buffer" > "$output_chunk_file"
    local write_status=$?
    if [ "$write_status" -ne 0 ]; then
        debug_log "ERROR" "Child: Failed to write buffer using %%b to output chunk file: $output_chunk_file (Exit code: $write_status)"
        return 1 # Critical error for this child
    fi
    # ----------------------------------------------------------------------

    # Return overall status (0 or 2) only if write was successful
    return "$overall_success"
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
#               checks if the translation DB already exists (simple file existence check).
#               If it exists, displays info. If not, creates it using the parallel function.
#               Does NOT take language code as an argument.
# @PARAM: None
# @RETURN: 0 on success/no translation needed, 1 on critical error,
#          propagates create_language_db_parallel exit code on failure.
translate_main() {
    # --- Initialization ---
    # (Wget detection logic remains the same)
    if type detect_wget_capabilities >/dev/null 2>&1; then
        WGET_CAPABILITY_DETECTED=$(detect_wget_capabilities)
        debug_log "DEBUG" "translate_main: Wget capability detected: ${WGET_CAPABILITY_DETECTED}"
    else
        debug_log "DEBUG" "translate_main: detect_wget_capabilities function not found. Assuming basic wget."
        WGET_CAPABILITY_DETECTED="basic"
    fi
    # --- End Initialization ---

    # --- Translation Control Logic ---
    local lang_code=""
    local is_default_lang="false"
    local target_db=""
    local db_creation_result=1 # Default to failure/not run

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
        # Default language: display nothing and exit successfully
        return 0
    fi

    debug_log "DEBUG" "translate_main: Target language (${lang_code}) requires processing."

    # 3. Check if target DB exists (Simple file existence check)
    target_db="${BASE_DIR}/message_${lang_code}.db"
    debug_log "DEBUG" "translate_main: Checking for existing target DB: ${target_db}"

    if [ -f "$target_db" ]; then
        debug_log "DEBUG" "translate_main: Target DB '${target_db}' exists for '${lang_code}'. Assuming valid and displaying info."
        # If file exists, display info and return success
        display_detected_translation
        return 0 # <<< Early return: DB exists
    else
        debug_log "DEBUG" "translate_main: Target DB '${target_db}' does not exist. Proceeding with creation."
    fi
    # --- End DB check ---

    # --- Proceed with Translation Process ---
    # 4. Find the first available translation function...
    local selected_func=""
    local func_name=""
    if [ -z "$AI_TRANSLATION_FUNCTIONS" ]; then
         debug_log "DEBUG" "translate_main: AI_TRANSLATION_FUNCTIONS global variable is not set or empty."
         printf "%s\n" "$(color yellow "$(get_message "MSG_ERR_NO_TRANS_FUNC_VAR")")"
         return 1
    fi
    set -f; set -- $AI_TRANSLATION_FUNCTIONS; set +f
    for func_name in "$@"; do
        if type "$func_name" >/dev/null 2>&1; then selected_func="$func_name"; break; fi
    done
    if [ -z "$selected_func" ]; then
        debug_log "DEBUG" "translate_main: No available translation functions found from list: '${AI_TRANSLATION_FUNCTIONS}'."
        printf "%s\n" "$(color yellow "$(get_message "MSG_ERR_NO_TRANS_FUNC_AVAIL" "list=$AI_TRANSLATION_FUNCTIONS")")"
        return 1
    fi
    debug_log "DEBUG" "translate_main: Selected translation function: ${selected_func}"

    # 5. Determine API URL and Domain Name (for context, currently unused in called functions)
    local api_endpoint_url=""
    local domain_name=""
    case "$selected_func" in
        "translate_with_google") api_endpoint_url="https://translate.googleapis.com/translate_a/single"; domain_name="translate.googleapis.com" ;;
        "translate_with_lingva") api_endpoint_url="https://lingva.ml/api/v1/"; domain_name="lingva.ml" ;;
        *) debug_log "DEBUG" "translate_main: Unknown function ${selected_func}, setting placeholder API info."; api_endpoint_url="N/A"; domain_name="$selected_func" ;;
    esac
    debug_log "DEBUG" "translate_main: Using API info context: URL='${api_endpoint_url}', Domain='${domain_name}'"


    # 6. Call create_language_db_parallel (MODIFIED)
    debug_log "DEBUG" "translate_main: Calling create_language_db_parallel for language '${lang_code}' using function '${selected_func}'"
    create_language_db_parallel "$selected_func" "$api_endpoint_url" "$domain_name" "$lang_code" # MODIFIED: Call the parallel control function
    db_creation_result=$?
    debug_log "DEBUG" "translate_main: create_language_db_parallel finished with status: ${db_creation_result}"

    # 7. Handle Result and Display Info ONLY on Success
    if [ "$db_creation_result" -eq 0 ]; then
        debug_log "DEBUG" "translate_main: Language DB creation successful for ${lang_code}."
        # Display info only after successful creation
        display_detected_translation
        return 0 # Success
    else
        debug_log "DEBUG" "translate_main: Language DB creation failed for ${lang_code} (Exit status: ${db_creation_result})."
        # Propagate specific create_language_db errors if possible (e.g., base DB missing),
        # otherwise show general failure. create_language_db_parallel returns 0 or 2.
        # create_language_db returns 1 if base DB missing. Parallel wrapper doesn't pass this up.
        # So we only check for the overall failure (status 2) from the parallel function.
        if [ "$db_creation_result" -eq 2 ]; then
             printf "%s\n" "$(color yellow "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code")")"
        # else: Could add handling for other potential non-zero codes if the parallel function changes
        fi
        # Do not display info on failure
        return "$db_creation_result" # Propagate error code (likely 2 from parallel func)
    fi
}
