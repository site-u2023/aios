
#!/bin/sh

SCRIPT_VERSION="2025-04-25-00-04" # Updated version based on last interaction time

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

# Number of parallel translation tasks to run concurrently
MAX_PARALLEL_TASKS="${MAX_PARALLEL_TASKS:-4}" # Default to 1 for initial testing

MESSAGE_DB="${MESSAGE_D:-message_en.db}"

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

# Google翻訳APIを使用した翻訳関数 (修正版 - デバッグログ完全削除)
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
             network_type="v4"
         fi
    fi
    network_type=$(cat "$ip_check_file" 2>/dev/null || echo "v4")

    case "$network_type" in
        "v4"|"v4v6") wget_options="-4" ;; # Treat v4v6 the same as v4
        "v6") wget_options="-6" ;;
        *) wget_options="" ;; # 不明な場合はオプションなし
    esac

    local encoded_text=$(urlencode "$source_text")
    api_url="https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang_code}&dt=t&q=${encoded_text}"

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

    rm -f "$temp_file" 2>/dev/null # 念のため削除
    printf "" # Output empty string on failure
    return 1 # Failure
}

# Function to process a chunk of the base DB and write translated lines to a temporary output file
# Usage: create_language_db <input_tmp_file> <output_tmp_file> <target_lang_code> <api_function_name>
create_language_db() {
    local input_file="$1"
    local output_file="$2"
    local target_lang_code="$3"
    local api_func="$4"
    local line=""
    local msg_key=""
    local source_text=""
    local translated_text=""
    local output_line=""
    local line_num=0
    local exit_status=0 # 0:success, 1:critical error, 2:partial success (some translations failed)

    # --- Argument Checks ---
    if [ -z "$input_file" ] || [ -z "$output_file" ] || [ -z "$target_lang_code" ] || [ -z "$api_func" ]; then
        debug_log "ERROR" "create_language_db - Missing required arguments."
        return 1 # Critical error
    fi
    if [ ! -f "$input_file" ]; then
        # This might happen legitimately if a split resulted in an empty file
        debug_log "INFO" "create_language_db - Input file not found or empty, skipping: $input_file"
        # Ensure output file exists even if empty
        touch "$output_file" || { debug_log "ERROR" "create_language_db - Failed to touch output file: $output_file"; return 1; } # Critical error
        return 0 # Success (empty input is not an error)
    fi
     if [ ! -r "$input_file" ]; then
        debug_log "ERROR" "create_language_db - Input file not readable: $input_file"
        return 1 # Critical error
     fi
    # Output file should have been created by the caller, check if writable directory
    local output_dir=$(dirname "$output_file")
     if [ ! -w "$output_dir" ]; then
        debug_log "ERROR" "create_language_db - Output directory not writable: $output_dir"
        return 1 # Critical error
     fi
     # Ensure output file exists and is writable (or can be created)
     # The caller (create_language_db_parallel) already creates it, but check again.
     touch "$output_file" || { debug_log "ERROR" "create_language_db - Failed to touch/ensure output file: $output_file"; return 1; } # Critical error


    debug_log "DEBUG" "create_language_db - Processing chunk: Input='$input_file', Output='$output_file', Lang='$target_lang_code', API='$api_func'"

    # --- Process Input File Line by Line ---
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$(($line_num + 1))

        # --- CHANGE START ---
        # Skip comment lines (starting with #) and empty lines immediately
        case "$line" in
            \#* | '')
                debug_log "DEBUG" "create_language_db - Skipping comment or empty line $line_num"
                continue
                ;;
        esac
        # --- CHANGE END ---

        debug_log "DEBUG" "create_language_db - Reading line $line_num: $line"

        # Skip lines not containing '=' (likely invalid format after comment/empty check)
        # We still need the '|' check for the expected format.
        if ! echo "$line" | grep -q '='; then
            debug_log "WARN" "create_language_db - Skipping line $line_num (no '=' found): $line"
            continue
        fi

        # Extract message key and source text
        # Expected format: xx|MSG_KEY=Source Text (xx| might be missing in base en.db)
        # Use parameter expansion for POSIX compliance
        local key_part=""
        local lang_prefix="" # Variable to hold potential language prefix

        # Check if '|' exists and split accordingly
        if echo "$line" | grep -q '|'; then
            lang_prefix="${line%%|*}" # Extract potential lang prefix (e.g., en)
            key_part="${line#*|}"     # Part after the first '|' (e.g., MSG_KEY=Source Text)
        else
            # If no '|', assume it's the base language file format (KEY=Value)
            debug_log "DEBUG" "create_language_db - No '|' found on line $line_num, assuming base format."
            key_part="$line"
            lang_prefix="" # No prefix
        fi

        # Now extract key and value from key_part
        msg_key="${key_part%%=*}"    # Extract key (e.g., MSG_KEY)
        source_text="${key_part#*=}" # Extract value (e.g., Source Text)

        if [ -z "$msg_key" ] || [ "$key_part" = "$msg_key" ]; then # Check if '=' was present after key
            debug_log "WARN" "create_language_db - Invalid line format (missing '=' or empty key) on line $line_num: $line"
            continue
        fi

        # --- Call Translation API ---
        debug_log "DEBUG" "create_language_db - Translating key '$msg_key' for lang '$target_lang_code'"
        # Use eval carefully to call the dynamic function name
        # Ensure api_func is validated or sourced from a controlled list if possible
        # Assuming api_func is safe here based on how it's passed
        if command -v "$api_func" > /dev/null 2>&1; then
            translated_text=$("$api_func" "$source_text" "$target_lang_code")
            local translate_exit_status=$?
            if [ $translate_exit_status -ne 0 ]; then
                debug_log "WARN" "create_language_db - API function '$api_func' failed for key '$msg_key' (exit status $translate_exit_status). Using original text."
                translated_text="$source_text" # Use original text on failure
                # If translation fails, mark as partial success (status 2) unless already critical (status 1)
                [ "$exit_status" -eq 0 ] && exit_status=2
            elif [ -z "$translated_text" ]; then
                 debug_log "WARN" "create_language_db - API function '$api_func' returned empty for key '$msg_key'. Using original text."
                 translated_text="$source_text" # Use original text if API returns empty
                 # Consider empty return also a partial success
                 [ "$exit_status" -eq 0 ] && exit_status=2
            fi
        else
            debug_log "ERROR" "create_language_db - API function '$api_func' not found."
            translated_text="$source_text" # Use original text if function not found
            exit_status=1 # Function not found is a critical error for this worker
            break # Stop processing this chunk if API function is missing
        fi

        # --- Write Output Line ---
        output_line="${target_lang_code}|${msg_key}=${translated_text}"
        debug_log "DEBUG" "create_language_db - Writing output line: $output_line"
        echo "$output_line" >> "$output_file"
        if [ $? -ne 0 ]; then
            debug_log "ERROR" "create_language_db - Failed to write to output file: $output_file"
            exit_status=1 # Treat write failure as critical
            break # Stop processing this chunk on write error
        fi

    done < "$input_file"

    debug_log "DEBUG" "create_language_db - Finished processing chunk: $input_file with status $exit_status"
    return $exit_status # Return accumulated status (0, 1, or 2)
}

# Function to create language DB by processing base DB in parallel
# Usage: create_language_db_parallel <aip_function_name> <api_endpoint_url> <domain_name> <target_lang_code>
create_language_db_parallel() {
    # --- 引数受け取りを4つに変更 ---
    local aip_function_name="$1" # 第1引数: AIP関数名
    local api_endpoint_url="$2"  # 第2引数: APIエンドポイントURL (New)
    local domain_name="$3"       # 第3引数: ドメイン名 (New)
    local target_lang_code="$4"  # 第4引数: ターゲット言語コード
    # ------------------------------
    local base_db="${BASE_DIR}/${MESSAGE_DB}"
    local final_output_dir="/tmp/aios"
    local final_output_file="${final_output_dir}/message_${target_lang_code}.db"
    local tmp_input_prefix="${TR_DIR}/message_${target_lang_code}.tmp.in."
    local tmp_output_prefix="${TR_DIR}/message_${target_lang_code}.tmp.out."
    local header=""
    local total_lines=0
    local lines_per_task=0
    local extra_lines=0
    local i=0
    local pids=""
    local pid=""
    local exit_status=0

    # --- Pre-checks ---
    if [ ! -f "$base_db" ]; then
        debug_log "ERROR" "Base DB file not found: $base_db"
        return 1
    fi
    # --- 引数チェック: 修正後の引数名を使用 ---
    if [ -z "$aip_function_name" ]; then
        debug_log "ERROR" "AIP function name is empty."
        return 1
    fi
    # api_endpoint_url and domain_name can be empty depending on the function, so no strict check here.
    if [ -z "$target_lang_code" ]; then
        debug_log "ERROR" "Target language code is empty."
        return 1
    fi
    # ------------------------------------------

    # --- Prepare directories and cleanup ---
    mkdir -p "$TR_DIR" || { debug_log "ERROR" "Failed to create temporary directory: $TR_DIR"; return 1; }
    mkdir -p "$final_output_dir" || { debug_log "ERROR" "Failed to create final output directory: $final_output_dir"; return 1; }

    # Setup trap for cleanup
    # shellcheck disable=SC2064 # We want $tmp_input_prefix and $tmp_output_prefix to expand now
    trap "debug_log 'INFO' 'Cleaning up temporary files...'; rm -f ${tmp_input_prefix}* ${tmp_output_prefix}*; exit \$exit_status" INT TERM EXIT

    # --- ログ出力: 修正後の引数名を使用 ---
    debug_log "INFO" "Starting parallel translation for language '$target_lang_code' using function '$aip_function_name' (API: '$api_endpoint_url', Domain: '$domain_name')."
    # -------------------------------------
    debug_log "INFO" "Base DB: $base_db"
    debug_log "INFO" "Temporary file directory: $TR_DIR"
    debug_log "INFO" "Final output file: $final_output_file"
    debug_log "INFO" "Max parallel tasks: $MAX_PARALLEL_TASKS"

    # --- Extract Header ---
    header=$(head -n 1 "$base_db")
    if [ -z "$header" ]; then
       debug_log "WARN" "Base DB might be empty or header could not be read."
    fi

    # --- Split Base DB (excluding header) using awk ---
    debug_log "INFO" "Splitting base DB into $MAX_PARALLEL_TASKS parts..."
    total_lines=$(($(wc -l < "$base_db") - 1))
    if [ "$total_lines" -le 0 ]; then
        debug_log "INFO" "No lines to translate (excluding header)."
        echo "$header" > "$final_output_file"
        return 0
    fi

    lines_per_task=$(($total_lines / $MAX_PARALLEL_TASKS))
    extra_lines=$(($total_lines % $MAX_PARALLEL_TASKS))

    if [ "$lines_per_task" -eq 0 ] && [ "$total_lines" -gt 0 ]; then
        lines_per_task=1
        debug_log "WARN" "Fewer lines ($total_lines) than tasks ($MAX_PARALLEL_TASKS). Some tasks might process few or no lines."
    fi

    # --- awk splitting logic: Use target_lang_code for temp file names ---
    awk -v num_tasks="$MAX_PARALLEL_TASKS" \
        -v prefix="$tmp_input_prefix" \
        'NR > 1 {
            task_num = (NR - 2) % num_tasks + 1;
            print $0 >> (prefix task_num);
         }' "$base_db"

    if [ $? -ne 0 ]; then
        debug_log "ERROR" "Failed to split base DB using awk."
        # Ensure temporary files potentially created by awk are removed by the trap
        return 1
    fi
    # ------------------------------------------------------------------
    debug_log "INFO" "Base DB split complete."

    # --- Execute tasks in parallel ---
    debug_log "INFO" "Launching parallel translation tasks..."
    i=1
    while [ "$i" -le "$MAX_PARALLEL_TASKS" ]; do
        local tmp_input_file="${tmp_input_prefix}${i}"
        local tmp_output_file="${tmp_output_prefix}${i}"

        # Ensure temp input file exists (awk should create it, but handle edge cases)
        if [ ! -f "$tmp_input_file" ]; then
             debug_log "WARN" "Temporary input file ${tmp_input_file} not found after split, creating empty file."
             touch "$tmp_input_file" || { debug_log "ERROR" "Failed to touch temporary input file: $tmp_input_file"; exit_status=1; break; }
        fi
        # Ensure temp output file exists and is empty
        >"$tmp_output_file" || { debug_log "ERROR" "Failed to create temporary output file: $tmp_output_file"; exit_status=1; break; }

        # --- Launch create_language_db (子プロセス) in the background ---
        # 子プロセスが期待する引数の順番 (tmp_in, tmp_out, lang_code, api_func) で渡す
        # 親プロセスが受け取った $target_lang_code と $aip_function_name を使用
        create_language_db "$tmp_input_file" "$tmp_output_file" "$target_lang_code" "$aip_function_name" &
        # ----------------------------------------------------------------
        pid=$!
        pids="$pids $pid"
        debug_log "DEBUG" "Launched task $i (PID: $pid) for input $tmp_input_file"

        i=$(($i + 1))
    done

    # --- Wait for all tasks to complete ---
    debug_log "INFO" "Waiting for $MAX_PARALLEL_TASKS tasks to complete..."
    for pid in $pids; do
        wait "$pid"
        local task_exit_status=$?
        if [ "$task_exit_status" -ne 0 ]; then
            # Allow status 2 (partial success from child) without setting overall failure yet
            if [ "$task_exit_status" -ne 2 ]; then
                debug_log "ERROR" "Task with PID $pid failed with critical exit status $task_exit_status."
                exit_status=1 # Set overall critical failure
            else
                 debug_log "WARN" "Task with PID $pid completed with partial success (exit status 2)."
                 # If any task returns 2, set overall status to 2 (unless already 1)
                 [ "$exit_status" -eq 0 ] && exit_status=2
            fi
        else
            debug_log "DEBUG" "Task with PID $pid completed successfully (exit status 0)."
        fi
    done

    # If a critical error occurred (status 1), return immediately
    if [ "$exit_status" -eq 1 ]; then
         debug_log "ERROR" "One or more translation tasks failed critically. Aborting combination."
         return 1
    fi

    debug_log "INFO" "All translation tasks completed (Overall status: $exit_status)."

    # --- Combine results ---
    debug_log "INFO" "Combining results into final output file: $final_output_file"
    # Write header first (overwrite file) - このヘッダー部分は後で元の関数に合わせて修正が必要
    echo "$header" > "$final_output_file" || { debug_log "ERROR" "Failed to write header to $final_output_file"; exit_status=1; return 1; }

    # Append results from all temp output files
    # Use find and cat for robustness, handle potential errors during append
    local combined_successfully=0
    find "$TR_DIR" -name "message_${target_lang_code}.tmp.out.*" -print0 | xargs -0 -r cat >> "$final_output_file"
    if [ $? -ne 0 ]; then
         debug_log "ERROR" "Failed to combine temporary output files into $final_output_file"
         # Even if combination fails, some parts might have succeeded, so return existing status (likely 2 if any task had partial success)
         if [ "$exit_status" -eq 0 ]; then exit_status=1; fi # If no task error, set combination error
         combined_successfully=1
    fi

    if [ "$combined_successfully" -ne 0 ]; then
        return "$exit_status" # Return error status (1 or 2)
    fi

    # --- 完了マーカーの追加 (後で実装) ---
    # --- 時間計測・スピナー制御 (後で実装) ---

    # If exit_status is still 0 (all tasks succeeded, combination succeeded), log success.
    # If exit_status is 2 (some tasks had partial success, combination succeeded), log partial success.
    if [ "$exit_status" -eq 0 ]; then
         debug_log "INFO" "Successfully created language DB (Full Success): $final_output_file"
    elif [ "$exit_status" -eq 2 ]; then
         debug_log "WARN" "Created language DB with some translations potentially missing (Partial Success): $final_output_file"
    fi


    # Cleanup is handled by trap on EXIT
    # --- 戻り値 (成功:0, 部分成功:2, 致命的エラー:1) ---
    return "$exit_status"
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
