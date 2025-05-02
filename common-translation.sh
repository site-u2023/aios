#!/bin/sh

SCRIPT_VERSION="2025-05-02-03-03"

# 基本定数の設定
DEBUG_MODE="${DEBUG_MODE:-false}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}" # Used for message.ch, network.ch etc.
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
TR_DIR="${TR_DIR:-$BASE_DIR/translation}"

# オンライン翻訳を有効化 (create_language_db logic removed reliance on this, but keep for potential external checks)
ONLINE_TRANSLATION_ENABLED="yes"

# API設定 (Global defaults)
BASE_WGET="wget --no-check-certificate -q"
API_TIMEOUT="${API_TIMEOUT:-8}"
API_MAX_RETRIES="${API_MAX_RETRIES:-5}"
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
    # export RES_OPTIONS="timeout:1 attempts:1"

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

# Helper function
translate_single_line() {
    local line="$1"
    local lang="$2"
    local func="$3"

    case "$line" in
        *"|"*)
            local line_content=${line#*|}
            local key=${line_content%%=*}
            local value=${line_content#*=}
            local translated_text

            translated_text=$("$func" "$value" "$lang")
            # Use original value if translation is empty
            [ -z "$translated_text" ] && translated_text="$value"

            printf "%s|%s=%s\n" "$lang" "$key" "$translated_text"
        ;;
    esac
}

# --- Unified Parallel Translation Function (Handles both 19+ and <19 logic via argument) ---
# Previously named create_language_db_19
# @param $1: aip_function_name (string) - AIP function (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - API URL (for logging)
# @param $3: domain_name (string) - Domain name (for logging)
# @param $4: target_lang_code (string) - Target language code (e.g., "ja")
# @param $5: max_tasks_limit (integer) - The maximum number of parallel tasks allowed. # NEW ARGUMENT
# @return: 0:success, 1:critical error, 2:partial success
create_language_db_19() {
    # 引数受け取り
    local aip_function_name="$1"
    local api_endpoint_url="$2"  # Passed for logging/context, not used directly here
    local domain_name="$3"       # Passed for logging/context, not used directly here
    local target_lang_code="$4"
    local max_tasks_limit="$5"

    # 変数定義
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local final_output_dir="/tmp/aios"
    local final_output_file="${final_output_dir}/message_${target_lang_code}.db"
    local tmp_input_prefix="${TR_DIR}/message_${target_lang_code}.tmp.in."
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    local total_lines=0
    local i=0
    local pids=""
    local pid=""
    local exit_status=0 # 0:success, 1:critical error, 2:partial success

    # --- MODIFIED: Assuming max_tasks_limit is valid from the caller ---
    # Removed the input validation case statement as it's redundant
    # given the caller (create_language_db_parallel) provides a validated value.
    debug_log "DEBUG" "create_language_db_19: Using parallelism limit from argument: $max_tasks_limit"

    # --- Prepare directories and cleanup (Original Logic) ---
    mkdir -p "$TR_DIR" || { debug_log "DEBUG" "create_language_db_19: Failed to create temporary directory: $TR_DIR"; return 1; }
    mkdir -p "$final_output_dir" || { debug_log "DEBUG" "create_language_db_19: Failed to create final output directory: $final_output_dir"; return 1; }

    # shellcheck disable=SC2064
    trap "debug_log 'DEBUG' 'Trap cleanup (19): Removing temporary input files...'; rm -f ${tmp_input_prefix}*" INT TERM EXIT

    # --- Logging (Original Logic, limit source changed) ---
    debug_log "DEBUG" "create_language_db_19: Starting parallel translation for language '$target_lang_code'."
    local current_max_parallel_tasks="$max_tasks_limit" # Use the argument
    # Debug log moved up after validation removal

    # --- Check lines, Initialize Output File OR Split Base DB ---
    total_lines=$(awk 'NR>1 && !/^#/ && !/^$/ {c++} END{print c}' "$base_db")

    if [ "$total_lines" -le 0 ]; then
        # --- Case 1: No lines to translate ---
        debug_log "DEBUG" "create_language_db_19: No lines to translate."
        # Create an empty file (no header)
        >"$final_output_file"
        if [ $? -ne 0 ]; then
             debug_log "DEBUG" "create_language_db_19: Failed to create empty output file $final_output_file."
             exit_status=1
        else
             exit_status=0
        fi
        return "$exit_status"
    else
        # --- Case 2: Lines exist ---
        # Initialize empty file for appending (no header)
        >"$final_output_file"
        if [ $? -ne 0 ]; then
            debug_log "DEBUG" "create_language_db_19: Failed to initialize output file $final_output_file"
            return 1 # Critical error
        fi

        # --- Split the base DB ---
        debug_log "DEBUG" "create_language_db_19: Splitting $total_lines lines into $current_max_parallel_tasks tasks..."
        awk -v num_tasks="$current_max_parallel_tasks" \
            -v prefix="$tmp_input_prefix" \
            'BEGIN { valid_line_count=0 }
             NR > 1 && !/^#/ && !/^$/ {
                valid_line_count++;
                task_num = (valid_line_count - 1) % num_tasks + 1;
                print $0 >> (prefix task_num);
            }' "$base_db"
        if [ $? -ne 0 ]; then
            debug_log "DEBUG" "create_language_db_19: Failed to split base DB using awk."
            return 1 # Critical error
        fi
        debug_log "DEBUG" "create_language_db_19: Base DB split complete."

        # --- Execute tasks (Original Logic, uses the limit) ---
        debug_log "DEBUG" "create_language_db_19: Launching parallel translation tasks..."
        i=1
        while [ "$i" -le "$current_max_parallel_tasks" ]; do
            local tmp_input_file="${tmp_input_prefix}${i}"

            if [ ! -f "$tmp_input_file" ]; then
                 i=$((i + 1))
                 continue
            fi

            # Pass final output file path to child process (Original Logic)
            create_language_db "$tmp_input_file" "$final_output_file" "$target_lang_code" "$aip_function_name" &
            pid=$!
            pids="$pids $pid"
            debug_log "DEBUG" "create_language_db_19: Launched task $i (PID: $pid)"

            # --- Job control loop (Original Logic, uses limit) ---
            while [ "$(jobs -p | wc -l)" -ge "$current_max_parallel_tasks" ]; do
                sleep 1 # Use integer sleep for POSIX
            done

            i=$((i + 1))
        done

        # --- Wait for tasks (Original Logic) ---
        if [ -n "$pids" ]; then
             debug_log "DEBUG" "create_language_db_19: Waiting for tasks to complete..."
             for pid in $pids; do
                 wait "$pid"
                 local task_exit_status=$?
                 # Original logic for handling task exit status
                 if [ "$task_exit_status" -ne 0 ]; then
                     if [ "$task_exit_status" -eq 1 ]; then
                         debug_log "DEBUG" "create_language_db_19: Task PID $pid failed critically (status 1)."
                         exit_status=1
                     elif [ "$task_exit_status" -eq 2 ]; then
                         debug_log "DEBUG" "create_language_db_19: Task PID $pid completed partially (status 2)."
                         [ "$exit_status" -eq 0 ] && exit_status=2
                     else
                         debug_log "DEBUG" "create_language_db_19: Task PID $pid failed unexpectedly (status $task_exit_status)."
                         [ "$exit_status" -eq 0 ] && exit_status=1
                     fi
                 else
                     debug_log "DEBUG" "create_language_db_19: Task PID $pid completed successfully."
                 fi
             done
             debug_log "DEBUG" "create_language_db_19: All tasks finished processing (Overall status: $exit_status)."
        else
             debug_log "DEBUG" "create_language_db_19: No tasks were launched."
        fi

        # --- Add completion marker (Original Logic) ---
        if [ "$exit_status" -ne 1 ]; then
            # Use lock mechanism to append marker (Original Logic)
            local lock_dir="${final_output_file}.lock"
            local lock_retries=5
            local lock_acquired=0
            while [ "$lock_retries" -gt 0 ]; do
                if mkdir "$lock_dir" 2>/dev/null; then
                    lock_acquired=1
                    break
                fi
                lock_retries=$((lock_retries - 1))
                sleep 1 # Use POSIX compliant sleep
            done

            if [ "$lock_acquired" -eq 1 ]; then
                printf "%s|%s=%s\n" "$target_lang_code" "$marker_key" "true" >> "$final_output_file"
                if [ $? -ne 0 ]; then
                    debug_log "DEBUG" "create_language_db_19: Failed to append completion marker."
                else
                     debug_log "DEBUG" "create_language_db_19: Completion marker added."
                fi
                rmdir "$lock_dir" # Release lock (Original Logic)
            else
                debug_log "DEBUG" "create_language_db_19: Failed to acquire lock for appending marker."
            fi
        fi
    fi # End of if/else based on total_lines

    # Original comment: Temporary input files are deleted by trap

    return "$exit_status"
}

# --- Test Function: Based on OK_create_language_db_all, uses subshell, v5 task management, AND v5 temporary file handling ---
# Modified to accept max parallel tasks limit as an argument.
# MODIFIED: Uses find for combining partial files for robustness.
# @param $1: aip_function_name (string) - AIP function (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - API URL (for logging)
# @param $3: domain_name (string) - Domain name (for logging)
# @param $4: target_lang_code (string) - Target language code (e.g., "ja")
# @param $5: max_tasks_limit (integer) - The maximum number of parallel tasks allowed. # NEW ARGUMENT
# @return: 0:success, 1:critical error, 2:partial success
create_language_db_all() {
    # 引数受け取り (変更なし)
    local aip_function_name="$1"
    local api_endpoint_url="$2"
    local domain_name="$3"
    local target_lang_code="$4"
    # --- MODIFIED: Receive the parallelism limit as the 5th argument ---
    local max_tasks_limit="$5"

    # 変数定義 (変更なし)
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local final_output_dir="/tmp/aios"
    local final_output_file="${final_output_dir}/message_${target_lang_code}.db"
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    local pids=""
    local pid=""
    local exit_status=0
    local line_from_awk=""

    # --- Input validation for the limit (変更なし) ---
    case "$max_tasks_limit" in
        ''|*[!0-9]*) # Empty or not a number
            debug_log "DEBUG" "create_language_db_all: Invalid or empty max_tasks_limit received ('$max_tasks_limit'). Defaulting to 1."
            max_tasks_limit=1
            ;;
        0) # Zero is not valid, default to 1
            debug_log "DEBUG" "create_language_db_all: Received max_tasks_limit=0. Defaulting to 1."
            max_tasks_limit=1
            ;;
        *) # Valid positive integer
            : # No action needed
            ;;
    esac
    debug_log "DEBUG" "create_language_db_all: Using parallelism limit: $max_tasks_limit"

    # --- Logging (Original Logic, limit source changed) ---
    debug_log "DEBUG" "create_language_db_all: Starting parallel translation (line-by-line, v5 task mgmt, v5 temp file test) for language '$target_lang_code'."
    local current_max_parallel_tasks="$max_tasks_limit" # Use the argument
    debug_log "DEBUG" "create_language_db_all: Max parallel tasks set from argument: $current_max_parallel_tasks"


    # --- MODIFIED: Initialize output file (remove header) ---
    # Ensure final directory exists before initializing file
    mkdir -p "$final_output_dir" || { debug_log "DEBUG" "create_language_db_all: Failed to create final output directory: $final_output_dir"; return 1; }
    >"$final_output_file"
    if [ $? -ne 0 ]; then
        debug_log "DEBUG" "create_language_db_all: Failed to initialize output file $final_output_file"
        exit_status=1
    else
        # --- メイン処理: 行ベースで並列翻訳 (Original Logic) ---
        # Note: awk does not use -v here, it pipes output
        awk 'NR>1 && !/^#/ && !/^$/' "$base_db" | while IFS= read -r line_from_awk; do
            # --- サブシェル内で translate_single_line を実行 (変更なし) ---
            ( # サブシェルの開始 (Original Logic)
                local current_line="$line_from_awk"
                local lang="$target_lang_code"
                local func="$aip_function_name"
                local outfile_base="$final_output_file" # Use the final output file base name

                # --- 一時ファイル名の生成と書き込み (Original Logic - v5方式) ---
                local translated_line
                translated_line=$(translate_single_line "$current_line" "$lang" "$func")
                if [ -n "$translated_line" ]; then
                     local partial_suffix=""
                     # Ensure TR_DIR exists for partial files
                     mkdir -p "$TR_DIR" || { debug_log "ERROR [Subshell]" "Failed to create TR_DIR: $TR_DIR"; exit 1; }
                     local partial_file_path="${TR_DIR}/$(basename "$outfile_base")" # Use TR_DIR for partial files

                     if date '+%N' >/dev/null 2>&1; then
                        partial_suffix="$$$(date '+%N')"
                     else
                        partial_suffix="$$$(date '+%S')"
                     fi

                     # Append to partial file in TR_DIR using printf (MODIFIED: path)
                     printf "%s\n" "$translated_line" >> "${partial_file_path}".partial_"$partial_suffix"
                     local write_status=$?
                     if [ "$write_status" -ne 0 ]; then
                         debug_log "ERROR [Subshell]" "Failed to append to partial file: ${partial_file_path}.partial_$partial_suffix"
                         exit 1 # Exit subshell with error (Original Logic)
                     fi
                fi
                exit 0 # Exit subshell successfully (Original Logic)
            ) & # Run subshell in background (Original Logic)

            pid=$!
            pids="$pids $pid"

            # --- MODIFIED: Use the passed limit for job control ---
            # Original comment: Parallel task limit control (v5 wait + sed method)
            while [ "$(jobs -p | wc -l)" -ge "$current_max_parallel_tasks" ]; do
                oldest_pid=$(echo "$pids" | cut -d' ' -f1)
                if [ -n "$oldest_pid" ]; then
                    # Original logic for waiting and removing PID
                    if wait "$oldest_pid" >/dev/null 2>&1; then
                        : # Success
                    else
                        # Log potential failure, but don't mark overall as failed just for this
                        debug_log "DEBUG" "create_language_db_all: Background task PID $oldest_pid may have failed or already exited."
                    fi
                    # Remove the PID using sed (Original Logic)
                    pids=$(echo "$pids" | sed "s/^$oldest_pid //")
                else
                    # Original logic for handling empty pids list
                    debug_log "DEBUG" "create_language_db_all: Could not get oldest_pid, maybe pids list is empty? Waiting briefly."
                    # --- MODIFIED: Use POSIX compliant sleep ---
                    sleep 1
                fi
            done
        done
        # Check pipeline exit status (Original Logic)
        local pipe_status=$?
        # Check specific pipe status codes if needed, but generally non-zero indicates an issue
        if [ "$pipe_status" -ne 0 ] && [ "$exit_status" -eq 0 ]; then
             debug_log "DEBUG" "create_language_db_all: Warning: Error during awk/while processing (pipe status: $pipe_status)."
             # Don't necessarily set exit_status=1 here, let subsequent steps handle errors
        fi

        # --- BGジョブが全て完了するまで待機 (変更なし) ---
        if [ "$exit_status" -ne 1 ]; then
            debug_log "DEBUG" "create_language_db_all: Waiting for remaining background tasks..."
            local wait_failed=0
            for pid in $pids; do
                if [ -n "$pid" ]; then
                    if wait "$pid"; then
                        : # Success
                    else
                        wait_failed=1
                        debug_log "DEBUG" "create_language_db_all: Remaining task PID $pid failed or exited with non-zero status."
                    fi
                fi
            done
            # If any wait failed AND current status is success(0), set to partial(2)
            if [ "$wait_failed" -eq 1 ] && [ "$exit_status" -eq 0 ]; then
                exit_status=2
            fi
            debug_log "DEBUG" "create_language_db_all: All background tasks finished."
        fi

        # --- MODIFIED: 部分出力を結合 (find + cat + find delete 方式) ---
        if [ "$exit_status" -ne 1 ]; then
            debug_log "DEBUG" "create_language_db_all: Combining partial results using find..."
            # Define pattern relative to TR_DIR
            local partial_pattern="$(basename "$final_output_file")"".partial_*"
            local found_partial=0

            # Check if any partial files exist in TR_DIR
            # Use find within TR_DIR, use -print -quit to exit after first match
            if (cd "$TR_DIR" && find . -maxdepth 1 -name "$partial_pattern" -print -quit | grep -q .); then
                found_partial=1
            fi

            if [ "$found_partial" -eq 1 ]; then
                 debug_log "DEBUG" "create_language_db_all: Found partial files matching '$partial_pattern' in $TR_DIR."
                 # Combine using find -exec cat {} + within TR_DIR, append to final output file
                 # Using a subshell to change directory temporarily
                 if (cd "$TR_DIR" && find . -maxdepth 1 -name "$partial_pattern" -exec cat {} + >> "$final_output_file"); then
                      debug_log "DEBUG" "create_language_db_all: Partial files combined successfully into $final_output_file."
                      # Remove using find -delete within TR_DIR
                      if (cd "$TR_DIR" && find . -maxdepth 1 -name "$partial_pattern" -delete); then
                         debug_log "DEBUG" "create_language_db_all: Partial files removed from $TR_DIR using find -delete."
                      else
                         debug_log "DEBUG" "create_language_db_all: Warning: Failed to remove partial files from $TR_DIR using find -delete."
                         # This might not be critical, but log it.
                      fi
                 else
                     debug_log "DEBUG" "create_language_db_all: Failed to combine partial files using find/cat."
                     # If cat fails, it's likely a more critical issue
                     [ "$exit_status" -eq 0 ] && exit_status=1 # Set to critical error if not already failed
                 fi
            else
                debug_log "DEBUG" "create_language_db_all: No partial files found in $TR_DIR matching '$partial_pattern' to combine."
                # Check if the final output file is empty and no partials were found
                if [ ! -s "$final_output_file" ]; then
                    # If base_db had lines but no partials were created and final file is empty,
                    # it might indicate all subshells failed silently or translation returned nothing.
                    # Check if base_db actually had lines to process
                    local base_lines_exist=$(awk 'NR>1 && !/^#/ && !/^$/ {print "yes"; exit}' "$base_db")
                    if [ -n "$base_lines_exist" ]; then
                         debug_log "DEBUG" "create_language_db_all: Warning: Base DB had lines, but no partial files were generated and final file is empty. Potential issue."
                         # Set to partial success if currently success
                         [ "$exit_status" -eq 0 ] && exit_status=2
                    fi
                fi
            fi
        fi

        # --- 完了マーカーを付加 (変更なし) ---
        if [ "$exit_status" -ne 1 ]; then
            printf "%s|%s=%s\n" "$target_lang_code" "$marker_key" "true" >> "$final_output_file"
            if [ $? -ne 0 ]; then
                debug_log "DEBUG" "create_language_db_all: Failed to append completion marker."
                # This failure might warrant setting status to 2 if currently 0
                [ "$exit_status" -eq 0 ] && exit_status=2
            else
                debug_log "DEBUG" "create_language_db_all: Completion marker added."
            fi
        fi
    fi # End of initial file initialization check

    return "$exit_status"
}

# --- Test Function: Based on OK_create_language_db_all, uses subshell, v5 task management, AND v5 temporary file handling ---
# Modified to accept max parallel tasks limit as an argument.
# @param $1: aip_function_name (string) - AIP function (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - API URL (for logging)
# @param $3: domain_name (string) - Domain name (for logging)
# @param $4: target_lang_code (string) - Target language code (e.g., "ja")
# @param $5: max_tasks_limit (integer) - The maximum number of parallel tasks allowed. # NEW ARGUMENT
# @return: 0:success, 1:critical error, 2:partial success
OK_create_language_db_all() {
    # 引数受け取り
    local aip_function_name="$1"
    local api_endpoint_url="$2"
    local domain_name="$3"
    local target_lang_code="$4"
    # --- MODIFIED: Receive the parallelism limit as the 5th argument ---
    local max_tasks_limit="$5"

    # 変数定義
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local final_output_dir="/tmp/aios"
    local final_output_file="${final_output_dir}/message_${target_lang_code}.db"
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    local pids=""
    local pid=""
    local exit_status=0
    local line_from_awk=""

    # --- Input validation for the limit ---
    case "$max_tasks_limit" in
        ''|*[!0-9]*) # Empty or not a number
            debug_log "DEBUG" "create_language_db_all: Invalid or empty max_tasks_limit received ('$max_tasks_limit'). Defaulting to 1."
            max_tasks_limit=1
            ;;
        0) # Zero is not valid, default to 1
            debug_log "DEBUG" "create_language_db_all: Received max_tasks_limit=0. Defaulting to 1."
            max_tasks_limit=1
            ;;
        *) # Valid positive integer
            : # No action needed
            ;;
    esac
    debug_log "DEBUG" "create_language_db_all: Using parallelism limit: $max_tasks_limit"

    # --- Logging (Original Logic, limit source changed) ---
    debug_log "DEBUG" "create_language_db_all: Starting parallel translation (line-by-line, v5 task mgmt, v5 temp file test) for language '$target_lang_code'."
    local current_max_parallel_tasks="$max_tasks_limit" # Use the argument
    debug_log "DEBUG" "create_language_db_all: Max parallel tasks set from argument: $current_max_parallel_tasks"


    # --- MODIFIED: Initialize output file (remove header) ---
    >"$final_output_file"
    if [ $? -ne 0 ]; then
        debug_log "DEBUG" "create_language_db_all: Failed to initialize output file $final_output_file"
        exit_status=1
    else
        # --- メイン処理: 行ベースで並列翻訳 (Original Logic) ---
        # Note: awk does not use -v here, it pipes output
        awk 'NR>1 && !/^#/ && !/^$/' "$base_db" | while IFS= read -r line_from_awk; do
            # --- サブシェル内で translate_single_line を実行 ---
            ( # サブシェルの開始 (Original Logic)
                local current_line="$line_from_awk"
                local lang="$target_lang_code"
                local func="$aip_function_name"
                local outfile="$final_output_file" # Use the final output file directly (or base name)

                # --- 一時ファイル名の生成と書き込み (Original Logic - v5方式) ---
                local translated_line
                translated_line=$(translate_single_line "$current_line" "$lang" "$func")
                if [ -n "$translated_line" ]; then
                     local partial_suffix=""
                     if date '+%N' >/dev/null 2>&1; then
                        partial_suffix="$$$(date '+%N')"
                     else
                        partial_suffix="$$$(date '+%S')"
                     fi

                     # Append to partial file using printf (Original Logic - v5方式)
                     printf "%s\n" "$translated_line" >> "$outfile".partial_"$partial_suffix"
                     local write_status=$?
                     if [ "$write_status" -ne 0 ]; then
                         debug_log "ERROR [Subshell]" "Failed to append to partial file: $outfile.partial_$partial_suffix"
                         exit 1 # Exit subshell with error (Original Logic)
                     fi
                fi
                exit 0 # Exit subshell successfully (Original Logic)
            ) & # Run subshell in background (Original Logic)

            pid=$!
            pids="$pids $pid"

            # --- MODIFIED: Use the passed limit for job control ---
            # Original comment: Parallel task limit control (v5 wait + sed method)
            while [ "$(jobs -p | wc -l)" -ge "$current_max_parallel_tasks" ]; do
                oldest_pid=$(echo "$pids" | cut -d' ' -f1)
                if [ -n "$oldest_pid" ]; then
                    # Original logic for waiting and removing PID
                    if wait "$oldest_pid" >/dev/null 2>&1; then
                        : # Success
                    else
                        debug_log "DEBUG" "create_language_db_all: Background task PID $oldest_pid may have failed."
                    fi
                    # Remove the PID using sed (Original Logic)
                    pids=$(echo "$pids" | sed "s/^$oldest_pid //")
                else
                    # Original logic for handling empty pids list
                    debug_log "DEBUG" "create_language_db_all: Could not get oldest_pid, maybe pids list is empty? Waiting briefly."
                    # --- MODIFIED: Use POSIX compliant sleep ---
                    sleep 1
                fi
            done
        done
        # Check pipeline exit status (Original Logic)
        local pipe_status=$?
        if [ "$pipe_status" -ne 0 ] && [ "$exit_status" -eq 0 ]; then
             debug_log "DEBUG" "create_language_db_all: Error during awk/while processing (pipe status: $pipe_status)."
             exit_status=1
        fi

        # --- BGジョブが全て完了するまで待機 ---
        if [ "$exit_status" -ne 1 ]; then
            debug_log "DEBUG" "create_language_db_all: Waiting for remaining background tasks..."
            local wait_failed=0
            for pid in $pids; do
                if [ -n "$pid" ]; then
                    if wait "$pid"; then
                        : # Success
                    else
                        wait_failed=1
                        debug_log "DEBUG" "create_language_db_all: Remaining task PID $pid failed."
                    fi
                fi
            done
            if [ "$wait_failed" -eq 1 ] && [ "$exit_status" -eq 0 ]; then
                exit_status=2
            fi
            debug_log "DEBUG" "create_language_db_all: All background tasks finished."
        fi

        # --- 部分出力を結合 (変更なし - v5 ls + cat 方式) ---
        if [ "$exit_status" -ne 1 ]; then
            debug_log "DEBUG" "create_language_db_all: Combining partial results using ls..."
            local partial_files=$(ls "$final_output_file".partial_* 2>/dev/null)
            if [ -n "$partial_files" ]; then
                # shellcheck disable=SC2086 # Intentionally splitting $partial_files like v5
                if cat $partial_files >> "$final_output_file"; then
                     # shellcheck disable=SC2086 # Intentionally splitting $partial_files like v5
                     if rm -f $partial_files; then
                         debug_log "DEBUG" "create_language_db_all: Partial files combined and removed."
                     else
                         debug_log "DEBUG" "create_language_db_all: Failed to remove partial files after combining."
                     fi
                else
                     debug_log "DEBUG" "create_language_db_all: Failed to combine partial files using ls/cat."
                     exit_status=1 # Critical error (Original Logic)
                fi
            else
                debug_log "DEBUG" "create_language_db_all: No partial files found to combine."
            fi
        fi

        # --- 完了マーカーを付加 ---
        if [ "$exit_status" -ne 1 ]; then
            printf "%s|%s=%s\n" "$target_lang_code" "$marker_key" "true" >> "$final_output_file"
            if [ $? -ne 0 ]; then
                debug_log "DEBUG" "create_language_db_all: Failed to append completion marker."
            else
                debug_log "DEBUG" "create_language_db_all: Completion marker added."
            fi
        fi
    fi # End of initial file initialization check

    return "$exit_status"
}

# --- Main Parallel Execution Wrapper ---
# Routes to the appropriate worker function based on OS version, passing the pre-calculated parallelism limit.
# Uses the original OK_create_language_db_parallel logic and relies on global CORE_COUNT and MAX_PARALLEL_TASKS.
create_language_db_parallel() {
    local aip_function_name="$1"
    local api_endpoint_url="$2"  # Passed for logging/context
    local domain_name="$3"       # Used for spinner message
    local target_lang_code="$4"

    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local exit_status=1 # デフォルトは失敗(1)
    local total_lines=0 # 翻訳対象行数

    # --- Time measurement variables ---
    local start_time=""
    local end_time=""
    local elapsed_seconds=0

    # --- Spinner variables ---
    local spinner_started="false"

    # --- OS Version Detection (Original Logic) ---
    local osversion
    # osversion.ch から読み込み、最初の '.' より前の部分を抽出
    osversion=$(cat "${CACHE_DIR}/osversion.ch" 2>/dev/null || echo "unknown")
    osversion="${osversion%%.*}"
    debug_log "DEBUG" "create_language_db_parallel: Detected OS major version: '$osversion'"

    # --- Pre-checks (Original Logic) ---
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "create_language_db_parallel: Base DB file not found: $base_db"
        printf "%s\n" "$(color red "$(get_message "MSG_ERR_BASE_DB_NOT_FOUND" "file=$base_db" "default=Base DB not found: $base_db")")" >&2
        return 1 # 致命的エラー
    fi
    if [ -z "$aip_function_name" ] || [ -z "$target_lang_code" ]; then
        debug_log "DEBUG" "create_language_db_parallel: Missing required arguments."
        printf "%s\n" "$(color red "$(get_message "MSG_ERR_MISSING_ARGS" "default=Missing required arguments for parallel translation.")")" >&2
        return 1 # 致命的エラー
    fi

    # --- Calculate total lines (for final message) (Original Logic) ---
    # コメント行と空行を除いた行数をカウント
    total_lines=$(awk 'NR>1 && !/^#/ && !/^$/ {c++} END{print c}' "$base_db")
    debug_log "DEBUG" "create_language_db_parallel: Total valid lines to translate: $total_lines"

    # --- Start Timing and Spinner (Original Logic) ---
    start_time=$(date +%s)
    local spinner_msg_key="MSG_TRANSLATING_CURRENTLY"
    local spinner_default_msg="Currently translating: $domain_name"
    # スピナーを開始
    start_spinner "$(color blue "$(get_message "$spinner_msg_key" "api=$domain_name" "default=$spinner_default_msg")")"
    spinner_started="true"

    # --- OS バージョンに基づいた分岐と関数呼び出し (MODIFIED Section) ---
    # This section now passes the appropriate global variable as the last argument
    if [ "$osversion" = "19" ]; then
        # OpenWrt 19 の場合は _19 関数を呼び出す
        # Use global $CORE_COUNT calculated outside this function
        debug_log "DEBUG" "create_language_db_parallel: Routing to create_language_db_19 for OS version 19 with limit from global CORE_COUNT ($CORE_COUNT)"
        # Pass original arguments ("$@") and the global CORE_COUNT as the last argument
        create_language_db_19 "$@" "$CORE_COUNT"
        exit_status=$? # _19 関数の終了ステータスを取得
    else
        # OpenWrt 19 以外の場合は _all 関数を呼び出す
        # Use global $MAX_PARALLEL_TASKS calculated outside this function
        debug_log "DEBUG" "create_language_db_parallel: Routing to create_language_db_all for OS version '$osversion' with limit from global MAX_PARALLEL_TASKS ($MAX_PARALLEL_TASKS)"
        # Pass original arguments ("$@") and the global MAX_PARALLEL_TASKS as the last argument
        create_language_db_all "$@" "$MAX_PARALLEL_TASKS"
        exit_status=$? # _all 関数の終了ステータスを取得
    fi
    debug_log "DEBUG" "create_language_db_parallel: Worker function finished with status: $exit_status"

    # --- Stop Timing and Spinner (Original Logic) ---
    end_time=$(date +%s)
    # start_time が空でないことを確認 (Original Logic)
    [ -n "$start_time" ] && elapsed_seconds=$((end_time - start_time)) || elapsed_seconds=0

    # スピナーが開始されていた場合のみ停止処理 (Original Logic)
    if [ "$spinner_started" = "true" ]; then
        local final_message=""
        local spinner_status="success" # デフォルトは成功

        # 終了ステータスに基づいて最終メッセージとスピナーステータスを決定 (Original Logic)
        if [ "$exit_status" -eq 0 ]; then
             # 成功した場合
             if [ "$total_lines" -gt 0 ]; then
                 # 翻訳行があった場合
                 final_message=$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Language file created successfully (${elapsed_seconds}s)")
             else
                 # 翻訳行がなかった場合 (total_lines が 0)
                 final_message=$(get_message "MSG_TRANSLATION_NO_LINES_COMPLETE" "s=$elapsed_seconds" "default=Translation finished: No lines needed translation (${elapsed_seconds}s)")
             fi
        elif [ "$exit_status" -eq 2 ]; then
            # 部分的成功の場合
            final_message=$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")
            spinner_status="warning" # ステータスを警告に
        else # exit_status が 1 (致命的エラー) またはその他の場合
            # 失敗した場合
            final_message=$(get_message "MSG_TRANSLATION_FAILED" "s=$elapsed_seconds" "default=Translation process failed after ${elapsed_seconds}s.")
            spinner_status="error" # ステータスをエラーに
        fi
        # スピナーを停止 (Original Logic)
        stop_spinner "$final_message" "$spinner_status"
        debug_log "DEBUG" "create_language_db_parallel: Task completed in ${elapsed_seconds} seconds. Overall Status: ${exit_status}"
    else
        # スピナーが開始されていなかった場合 (フォールバック表示) (Original Logic)
         if [ "$exit_status" -eq 0 ]; then
             printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Language file created successfully (${elapsed_seconds}s)")")"
         elif [ "$exit_status" -eq 2 ]; then
             printf "%s\n" "$(color yellow "$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")")"
         else
             printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_FAILED" "s=$elapsed_seconds" "default=Translation process failed after ${elapsed_seconds}s.")")"
         fi
    fi

    # 最終的な終了ステータスを返す (Original Logic)
    return "$exit_status"
}

# Child function called by create_language_db_parallel (Revised for Chunk Buffering + Single Lock)
# This function now processes a *chunk* of the base DB, buffers results in memory,
# and appends to the final output file using a single lock acquisition per chunk.
# @param $1: input_chunk_file (string) - Path to the temporary input file containing a chunk of lines.
# @param $2: final_output_file (string) - Path to the final output file (e.g., message_ja.db).
# @param $3: target_lang_code (string) - The target language code (e.g., "ja").
# @param $4: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google").
# @return: 0 on success, 1 on critical error (read/write/lock failure), 2 if any translation fails within this chunk (but writes were successful).
create_language_db() {
    local input_chunk_file="$1"
    local final_output_file="$2"
    local target_lang_code="$3"
    local aip_function_name="$4"

    local overall_success=0 # Assume success initially for this chunk, 2 indicates at least one translation failed
    local output_buffer="" # Buffer to store translated lines for this chunk

    # --- Lock related settings ---
    local lock_dir="${final_output_file}.lock"
    # Use global overrides if set, otherwise default
    local lock_max_retries="${LOCK_MAX_RETRIES:-10}"
    local lock_sleep_interval="${LOCK_SLEEP_INTERVAL:-1}"

    # Check if input file exists
    if [ ! -f "$input_chunk_file" ]; then
        debug_log "ERROR" "Child: Input chunk file not found: $input_chunk_file"
        return 1 # Critical error for this child
    fi

    # Loop through the input chunk file and buffer results
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

        # --- Debug log before translation call ---
        # debug_log "DEBUG" "Child: Translating key '$key' for lang '$target_lang_code' using '$aip_function_name'"
        translated_text=$("$aip_function_name" "$value" "$target_lang_code")
        exit_code=$?
        # --- Debug log after translation call ---
        # if [ "$exit_code" -ne 0 ]; then
        #     debug_log "DEBUG" "Child: Translation failed for key '$key' (exit code: $exit_code)"
        # fi

        # --- Prepare output line ---
        local output_line=""
        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            # Format successful translation *without* newline here
            output_line=$(printf "%s|%s=%s" "$target_lang_code" "$key" "$translated_text")
        else
            # Set partial success if any translation fails
            overall_success=2
            # Format original value *without* newline here
            output_line=$(printf "%s|%s=%s" "$target_lang_code" "$key" "$value")
        fi

        # Append the formatted line followed by a newline to the buffer
        # Using printf ensures consistent newline handling
        output_buffer="${output_buffer}$(printf "%s\n" "$output_line")"

    done < "$input_chunk_file" # Read from the chunk input file

    # --- Write the entire buffer to the final output file with a single lock ---
    if [ -n "$output_buffer" ]; then
        local lock_retries="$lock_max_retries"
        local lock_acquired=0
        while [ "$lock_retries" -gt 0 ]; do
            # Try to acquire lock
            if mkdir "$lock_dir" 2>/dev/null; then
                lock_acquired=1
                # --- Lock acquired successfully ---
                echo "$output_buffer" >> "$final_output_file"
                local write_status=$?
                # Release lock
                rmdir "$lock_dir"
                local rmdir_status=$?

                if [ "$write_status" -ne 0 ]; then
                    debug_log "ERROR" "Child: Failed to append buffer to $final_output_file (Write status: $write_status)"
                    # Write failure is a critical error
                    # Ensure lock dir is removed if rmdir failed but write failed
                    [ -d "$lock_dir" ] && rmdir "$lock_dir" 2>/dev/null
                    return 1
                fi
                if [ "$rmdir_status" -ne 0 ]; then
                    # Lock release failure is a warning (write likely succeeded)
                    debug_log "WARNING" "Child: Failed to remove lock directory $lock_dir (rmdir status: $rmdir_status)"
                fi
                # Exit lock retry loop on success
                break
            else
                # --- Lock acquisition failed ---
                lock_retries=$((lock_retries - 1))
                # Wait before retrying if not the last attempt
                if [ "$lock_retries" -gt 0 ]; then
                     sleep "$lock_sleep_interval"
                fi
            fi
        done # End lock retry loop

        # Check if lock was ultimately acquired
        if [ "$lock_acquired" -eq 0 ]; then
            debug_log "ERROR" "Child: Failed to acquire lock for $final_output_file after $lock_max_retries attempts."
            # Lock acquisition failure is a critical error
            return 1
        fi
    else
        debug_log "DEBUG" "Child: Output buffer is empty for chunk '$input_chunk_file', nothing to write."
    fi
    # --- End buffer writing ---

    # Return overall success status for this chunk (0, 1, or 2)
    # If a critical error (1) occurred above, it would have returned already.
    return "$overall_success"
}

# Child function called by create_language_db_parallel (Revised for Direct Append + Lock)
# This function now processes a *chunk* of the base DB and directly appends to the final output file using a lock.
# @param $1: input_chunk_file (string) - Path to the temporary input file containing a chunk of lines.
# @param $2: final_output_file (string) - Path to the final output file (e.g., message_ja.db).
# @param $3: target_lang_code (string) - The target language code (e.g., "ja").
# @param $4: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google").
# @return: 0 on success, 1 on critical error (read/write/lock failure), 2 if any translation fails within this chunk (but writes were successful).
OK_create_language_db() {
    local input_chunk_file="$1"
    local final_output_file="$2" # 引数名を変更
    local target_lang_code="$3"
    local aip_function_name="$4"

    local overall_success=0 # Assume success initially for this chunk, 2 indicates at least one translation failed
    # local output_buffer=""  # 削除: バッファは使用しない

    # --- ロック関連設定 ---
    local lock_dir="${final_output_file}.lock"
    local lock_max_retries=10 # ロック取得のリトライ回数
    local lock_sleep_interval=1 # ロック取得失敗時の待機秒数

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

        # --- Prepare output line ---
        local output_line=""
        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            # Format successful translation *without* newline
            output_line=$(printf "%s|%s=%s" "$target_lang_code" "$key" "$translated_text")
        else
            # 翻訳失敗時は overall_success を 2 (部分的成功) に設定
            overall_success=2
            # Format original value *without* newline
            output_line=$(printf "%s|%s=%s" "$target_lang_code" "$key" "$value")
        fi

        # --- Append line to final output file with lock ---
        local lock_retries="$lock_max_retries"
        local lock_acquired=0
        while [ "$lock_retries" -gt 0 ]; do
            # mkdir でロック取得試行
            if mkdir "$lock_dir" 2>/dev/null; then
                lock_acquired=1
                # --- ロック取得成功 ---
                # printf でファイルに追記 (%s\n で改行を追加)
                printf "%s\n" "$output_line" >> "$final_output_file"
                local write_status=$?
                # rmdir でロック解放
                rmdir "$lock_dir"
                local rmdir_status=$?

                if [ "$write_status" -ne 0 ]; then
                    debug_log "ERROR" "Child: Failed to append line to $final_output_file (Write status: $write_status)"
                    # 書き込み失敗は致命的エラー
                    return 1
                fi
                if [ "$rmdir_status" -ne 0 ]; then
                    # ロック解放失敗は警告ログのみ（ファイル書き込みは成功している可能性）
                    debug_log "WARNING" "Child: Failed to remove lock directory $lock_dir (rmdir status: $rmdir_status)"
                fi
                # ロック取得・書き込み・解放成功したらループを抜ける
                break
            else
                # --- ロック取得失敗 ---
                lock_retries=$((lock_retries - 1))
                # 最後の試行でなければ待機
                if [ "$lock_retries" -gt 0 ]; then
                     sleep "$lock_sleep_interval"
                fi
            fi
        done # ロック取得リトライループ終了

        # リトライしてもロック取得できなかった場合
        if [ "$lock_acquired" -eq 0 ]; then
            debug_log "ERROR" "Child: Failed to acquire lock for $final_output_file after $lock_max_retries attempts."
            # ロック取得失敗は致命的エラー
            return 1
        fi
        # --- End Append line ---

    done < "$input_chunk_file" # Read from the chunk input file

    # 致命的エラー(1)が発生していなければ、最終的な成功ステータス(0 or 2)を返す
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
