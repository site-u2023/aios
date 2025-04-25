#!/bin/sh

SCRIPT_VERSION="2025-04-25-00-00" # Updated version based on last interaction time

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

# ------------------------------------------------------------------------------------------------

# --- Helper Function for Background Translation Task ---

# parallel_translate_task: Executes the specified translation function in the background.
# Assumes debug_log and the target translation function (e.g., translate_with_google) are available.
# Assumes the caller (create_language_db_parallel) has already verified the translation function exists.
# @param $1: item_id (Unique identifier, e.g., "Line-123")
# @param $2: source_text (The actual text to translate)
# @param $3: target_lang_code (e.g., "ja")
# @param $4: result_file_path (File to write the final text to)
# @param $5: translation_function_name (e.g., "translate_with_google")
# @stdout: (to result file) The translated text (on success) or original source_text (on failure).
# @stderr: Logs progress using debug_log.
# @return: 0 on success, 1 on translation failure.
parallel_translate_task() {
    local item_id="$1"
    local source_text="$2"
    local target_lang_code="$3"
    local result_file="$4"
    local translation_function_name="$5" # Function to call for translation
    local translated_text=""
    local exit_code=1 # Assume failure initially

    # NOTE: Existence check for translation_function_name removed as it's done by the caller.

    debug_log "DEBUG" "  [TASK $item_id] Starting '$translation_function_name' for: \"$(echo "$source_text" | cut -c 1-30)...\""

    # Call the specified translation function dynamically
    # Assuming the function takes (source_text, target_lang_code) and returns text on stdout, status code via $?
    translated_text=$("$translation_function_name" "$source_text" "$target_lang_code")
    exit_code=$?

    if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
        debug_log "DEBUG" "  [TASK $item_id] Translation successful via '$translation_function_name'."
        printf "%s\n" "$translated_text" > "$result_file"
        return 0 # Task success
    else
        debug_log "WARN" "  [TASK $item_id] Translation failed via '$translation_function_name' (Exit code: $exit_code). Using original text."
        printf "%s\n" "$source_text" > "$result_file" # Write original text on failure
        return 1 # Task failure (but we still write original text)
    fi
}

# ... (ファイル内の他の関数定義) ...

# =========================================================
# Parallel Language Database Creation
# =========================================================
# create_language_db_parallel: Creates a language DB file by translating msgids in parallel.
# Uses a specified translation function (e.g., translate_with_google) via parallel_translate_task.
# Handles background processes, temporary files, and result aggregation while preserving order.
# Assumes BASE_DIR, DEFAULT_LANGUAGE, MAX_PARALLEL_TASKS, debug_log,
# and parallel_translate_task are available and sourced.
# Assumes the specified translation function (e.g., translate_with_google) is also available.
# @param $1: api_name (e.g., "google", "deepl" - used for function name construction)
# @param $2: api_url (Optional, currently unused by this function's core logic)
# @param $3: domain (e.g., "messages")
# @param $4: target_lang_code (e.g., "ja")
# @stdout: None directly. Writes final .db file.
# @stderr: Logs progress using debug_log.
# @return: 0 on complete success, 1 on critical error (setup, file issues), 2 on partial success (some translations failed).
create_language_db_parallel() {
    local api_name="$1"
    # local api_url="$2" # Kept for signature consistency if needed later
    local domain="$3"
    local target_lang_code="$4"
    local source_lang_code="$DEFAULT_LANGUAGE"
    local translation_function_name="translate_with_${api_name}"

    local source_dir="${BASE_DIR}/locale/${source_lang_code}"
    local target_dir="${BASE_DIR}/locale/${target_lang_code}"
    local source_db="${source_dir}/${domain}.db"
    local target_db="${target_dir}/${domain}.db"
    local target_db_tmp="${target_dir}/${domain}.db.tmp" # Temporary file for final assembly
    local marker_file="${target_db}.completed" # Marker for successful completion

    local return_code=0 # 0=success, 1=critical error, 2=partial success

    # --- Pre-checks ---
    debug_log "INFO" "Starting parallel DB creation for domain '$domain', target '$target_lang_code' using '$translation_function_name'."

    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir" || { debug_log "ERROR" "Failed to create target directory: $target_dir"; return 1; }
        debug_log "INFO" "Created target directory: $target_dir"
    fi

    if [ ! -f "$source_db" ]; then
        debug_log "ERROR" "Source DB file not found: $source_db"
        return 1
    fi

    # --- Prepare for Parallel Processing ---
    local tmp_dir=$(mktemp -d -p "${TMP_DIR:-/tmp}" "parallel_translate_${domain}_XXXXXX")
    if [ -z "$tmp_dir" ] || [ ! -d "$tmp_dir" ]; then
        debug_log "ERROR" "Failed to create temporary directory."
        return 1
    fi
    debug_log "DEBUG" "Created temporary directory for results: $tmp_dir"

    # --- Create AWK script file ---
    local awk_script_file="${tmp_dir}/parse_db.awk"
    cat > "$awk_script_file" << 'EOF'
BEGIN { msgid_block = ""; line_num = 0 }
/^[ \t]*#/ || /^[ \t]*$/ { next }
/^msgid[ \t]+".*"$/ {
    if (msgid_block != "") { msgid_block = "" }
    gsub(/^msgid[ \t]+"/, ""); gsub(/"$/, "");
    msgid_block = $0;
    line_num = NR; next;
}
/^".*"$/ {
     if (msgid_block != "") {
         gsub(/^"/, ""); gsub(/"$/, "");
         # Append with newline for potential multiline representation if needed later,
         # but for task argument, just concatenate.
         msgid_block = msgid_block $0;
     }
     next;
}
/^msgstr[ \t]+""$/ {
     if (msgid_block != "") {
         item_id = "Line-" line_num
         # Use awk's printf for safer output formatting, especially if msgid_block contains special chars
         printf "EXECUTE:|%s|%s|%s|%s/%s.txt|%s\n", item_id, msgid_block, target_lang, tmp_dir, item_id, trans_func
     }
     msgid_block = ""; next;
}
EOF
    # --- End AWK script file creation ---

    local pids="" # Store background process IDs
    local task_count=0

    # Clean previous temporary output and marker files
    rm -f "$target_db_tmp" "$marker_file"

    # --- Launch Background Translation Tasks ---
    debug_log "INFO" "Parsing source DB and launching translation tasks using awk script: $awk_script_file"
    # --- Modified AWK execution: use -f option ---
    awk -f "$awk_script_file" \
        -v tmp_dir="$tmp_dir" \
        -v target_lang="$target_lang_code" \
        -v trans_func="$translation_function_name" \
        "$source_db" | while IFS='|' read -r prefix item_id source_text target_l result_f trans_f rest; do
        # --- End Modified AWK execution ---

        # Use IFS='|' to correctly parse pipe-delimited fields
        # Check if the line starts with EXECUTE: and has the expected number of fields
        if [ "$prefix" = "EXECUTE:" ] && [ -n "$item_id" ] && [ -n "$source_text" ] && [ -n "$target_l" ] && [ -n "$result_f" ] && [ -n "$trans_f" ]; then

                # Limit parallel processes
                while [ "$(jobs -p | wc -l)" -ge "$MAX_PARALLEL_TASKS" ]; do
                    sleep 0.5 # Wait before launching next task
                done

                # Launch the task in the background
                debug_log "DEBUG" "Launching task $item_id for source text starting with: $(echo "$source_text" | cut -c 1-30)..."
                # Pass arguments correctly quoted
                parallel_translate_task "$item_id" "$source_text" "$target_l" "$result_f" "$trans_f" &
                pids="$pids $!" # Store the PID
                task_count=$((task_count + 1))
        else
                # Read might have failed or line format was unexpected
                # Handle potential full line read if IFS didn't match
                local full_line="${prefix}${IFS}${item_id}${IFS}${source_text}${IFS}${target_l}${IFS}${result_f}${IFS}${trans_f}${IFS}${rest}"
                if [ -n "$full_line" ]; then # Avoid logging empty lines from potential read failures
                     # Avoid logging if the line is just "EXECUTE:" due to printf format change
                     if [ "$full_line" != "EXECUTE:" ]; then
                          debug_log "WARN" "Unexpected line format from awk or read error: $full_line"
                     fi
                fi
        fi
    done

    # --- Wait for all background tasks to complete ---
    debug_log "INFO" "Launched $task_count tasks. Waiting for completion..."
    local failed_tasks=0
    if [ -n "$pids" ]; then
        # Trim leading space from pids if necessary
        pids=$(echo "$pids" | sed 's/^ //')
        for pid in $pids; do
            wait "$pid"
            local task_exit_code=$?
            if [ "$task_exit_code" -ne 0 ]; then
                failed_tasks=$((failed_tasks + 1))
                # Log which PID failed for better debugging, though mapping PID to item_id is complex here
                debug_log "WARN" "Task with PID $pid failed with exit code $task_exit_code."
            fi
        done
        debug_log "INFO" "All tasks completed. Number of failed tasks: $failed_tasks"
    else
        debug_log "INFO" "No tasks were launched."
    fi

    # --- Assemble Final DB File (Order-Preserving) ---
    debug_log "INFO" "Assembling final DB file from source and results..."
    rm -f "$target_db_tmp" # Ensure temp file is clean before assembly
    local current_msgid_content=""
    local msgid_line_start=0
    local line_num=0
    local in_msgid_block=0 # Flag to track if we are inside a msgid block

    ( # Use subshell to handle file reading redirection properly
    while IFS= read -r src_line || [ -n "$src_line" ]; do
        line_num=$((line_num + 1))

        # Preserve comments and empty lines
        if echo "$src_line" | grep -qE '^[ \t]*#|^[ \t]*$'; then
            printf "%s\n" "$src_line"
            # If we were in a msgid block, it ended unexpectedly. Write it out.
            if [ "$in_msgid_block" -eq 1 ] && [ -n "$current_msgid_content" ]; then
                 printf "msgid \"%s\"\n" "$current_msgid_content" # Consider escaping here too if needed
                 printf "msgstr \"\"\n" # Write empty msgstr
                 debug_log "WARN" "msgid block starting line $msgid_line_start ended unexpectedly by comment/empty line $line_num."
                 current_msgid_content=""
                 in_msgid_block=0
            fi
            continue
        fi

        # Start of msgid block
        if echo "$src_line" | grep -q '^msgid[ \t]'; then
            # If previous msgid block exists, write it with empty msgstr (error case)
            if [ "$in_msgid_block" -eq 1 ] && [ -n "$current_msgid_content" ]; then
                printf "msgid \"%s\"\n" "$current_msgid_content" # Consider escaping here too if needed
                printf "msgstr \"\"\n" # Write empty msgstr for previous block
                debug_log "WARN" "New msgid block started line $line_num before previous block (line $msgid_line_start) had msgstr."
            fi
            # Extract content, removing msgid " and trailing "
            current_msgid_content=$(echo "$src_line" | sed -e 's/^msgid[ \t]*"//' -e 's/"$//')
            msgid_line_start=$line_num # Record the starting line number
            in_msgid_block=1
            continue # Continue reading lines for potential multiline msgid/msgstr
        fi

        # Continuation of msgid (multiline)
        if echo "$src_line" | grep -q '^"'; then
             if [ "$in_msgid_block" -eq 1 ]; then
                 # Append content, removing leading/trailing "
                 # Add a literal newline character for correct multiline representation
                 current_msgid_content="${current_msgid_content}\\n$(echo "$src_line" | sed -e 's/^"//' -e 's/"$//')"
             else
                 # Stray continuation line without preceding msgid - write directly? Or error?
                 printf "%s\n" "$src_line"
                 debug_log "WARN" "Stray continuation line found at line $line_num: $src_line"
             fi
             continue
        fi

        # msgstr line - This indicates end of msgid block; time to write results
        if echo "$src_line" | grep -q '^msgstr[ \t]'; then
             if [ "$in_msgid_block" -eq 1 ] && [ -n "$current_msgid_content" ]; then
                 local item_id="Line-${msgid_line_start}" # Reconstruct item_id based on msgid start line
                 local result_file="${tmp_dir}/${item_id}.txt"

                 # Write the collected msgid block (potentially multiline)
                 printf "msgid \""
                 # Escape quotes and backslashes within the msgid content before printing
                 printf "%b" "$current_msgid_content" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
                 printf "\"\n"

                 # Read the corresponding result file if it exists
                 if [ -f "$result_file" ]; then
                     # Read entire file content, potentially multiple lines
                     result_content=$(cat "$result_file")
                     # Escape quotes and backslashes in the result content for .db format
                     escaped_result_content=$(echo "$result_content" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
                     printf "msgstr \"%s\"\n" "$escaped_result_content" # Write the translated msgstr
                 else
                     debug_log "WARN" "Result file not found for $item_id (msgid starting line $msgid_line_start). Writing empty msgstr."
                     printf "msgstr \"\"\n" # Write empty msgstr if result file is missing
                 fi
             elif echo "$src_line" | grep -q '^msgstr[ \t]+""$'; then
                 # Original source had msgid "" and msgstr "" - preserve it
                 printf "msgid \"\"\n"
                 printf "msgstr \"\"\n"
             else
                 # msgstr line without a preceding valid msgid block (error in source file?)
                 # Or maybe a non-empty msgstr in the source? Preserve it.
                 printf "msgid \"\"\n" # Assume missing msgid
                 printf "%s\n" "$src_line" # Write the original msgstr line
                 debug_log "WARN" "msgstr line found at $line_num without a preceding msgid block."
             fi
             current_msgid_content="" # Reset for the next block
             msgid_line_start=0
             in_msgid_block=0
             continue
        fi

        # Any other unexpected lines - write them directly to preserve structure? Or log error?
        printf "%s\n" "$src_line"
        debug_log "WARN" "Unexpected line format encountered at line $line_num: $src_line"
        # If we were in a msgid block, it ended unexpectedly.
         if [ "$in_msgid_block" -eq 1 ] && [ -n "$current_msgid_content" ]; then
              printf "msgid \"%s\"\n" "$current_msgid_content" # Consider escaping
              printf "msgstr \"\"\n" # Write empty msgstr
              debug_log "WARN" "msgid block starting line $msgid_line_start ended unexpectedly by unknown line format $line_num."
              current_msgid_content=""
              in_msgid_block=0
         fi

    done < "$source_db" # Read from the original source DB

    # Handle potential last msgid block if the file ends without a final msgstr
    if [ "$in_msgid_block" -eq 1 ] && [ -n "$current_msgid_content" ]; then
        printf "msgid \""
        # Escape quotes and backslashes within the msgid content before printing
        printf "%b" "$current_msgid_content" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
        printf "\"\n"
        printf "msgstr \"\"\n"
        debug_log "WARN" "File ended while still in msgid block starting line $msgid_line_start."
    fi
    ) > "$target_db_tmp" # Write the assembled output to the temporary file

    # --- Finalization ---
    if [ "$failed_tasks" -gt 0 ]; then
        debug_log "WARN" "Parallel DB creation completed with $failed_tasks failed translation task(s)."
        return_code=2 # Partial success
    else
        # Check if any result files were actually expected but missing (logged during assembly)
        # For now, assume 0 failed tasks means full success.
        debug_log "INFO" "Parallel DB creation completed successfully."
        return_code=0 # Full success
    fi

    # Move final file into place
    if [ -f "$target_db_tmp" ]; then
        # Check if tmp file is empty - might indicate total failure despite exit codes
        if [ ! -s "$target_db_tmp" ] && [ "$task_count" -gt 0 ]; then
             debug_log "ERROR" "Final temporary DB file ($target_db_tmp) is empty after assembly. Critical error likely occurred."
             rm -f "$target_db_tmp"
             return_code=1
        else
            mv "$target_db_tmp" "$target_db"
            if [ $? -eq 0 ]; then
                debug_log "INFO" "Successfully created target DB: $target_db"
                # Create marker file only on full or partial success (adjust as needed)
                if [ "$return_code" -eq 0 ] || [ "$return_code" -eq 2 ]; then
                    touch "$marker_file"
                fi
            else
                debug_log "ERROR" "Failed to move temporary DB file to $target_db"
                rm -f "$target_db_tmp" # Clean up temp file on move failure
                return_code=1 # Critical error
            fi
        fi
    else
        debug_log "ERROR" "Final temporary DB file ($target_db_tmp) not found after assembly."
        return_code=1 # Critical error
    fi

    # --- Cleanup ---
    # Remove the temporary awk script file
    rm -f "$awk_script_file"
    # if [ -d "$tmp_dir" ]; then
    #     debug_log "DEBUG" "Removing temporary directory: $tmp_dir"
    #     rm -rf "$tmp_dir"
    # fi

    debug_log "INFO" "Finished parallel DB creation for domain '$domain'. Final return code: $return_code"
    return "$return_code"
}

# ... (ファイル内の他の関数) ...

# ---------------------------------------------------------------------------------------------

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

# 翻訳DB作成関数 (責務: DBファイル作成、AIP関数呼び出し、スピナー制御、時間計測)
# @param $1: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - The base API endpoint URL (Currently unused, kept for potential future compatibility or logging)
# @param $3: domain_name (string) - The domain name for spinner display (e.g., "translate.googleapis.com")
# @param $4: target_lang_code (string) - The target language code (e.g., "ja")
# @return: 0 on success, 1 on base DB not found, 2 if any translation fails (writes original text for failures)
create_language_db() {
    local aip_function_name="$1"
    local api_endpoint_url="$2" # Unused in current logic, passed for context
    local domain_name="$3"      # Explicitly passed domain name for spinner
    local target_lang_code="$4"

    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local output_db="${BASE_DIR}/message_${target_lang_code}.db"
    local spinner_started="false"
    local overall_success=0 # Assume success initially, 2 indicates at least one translation failed
    # --- 時間計測用変数 ---
    local start_time=""
    local end_time=""
    local elapsed_seconds=""
    # ---------------------

    debug_log "DEBUG" "Creating language DB for target '${target_lang_code}' using function '${aip_function_name}' with domain '${domain_name}'"

    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found: $base_db. Cannot create target DB."
        # Ensure get_message exists and handles missing keys gracefully
        printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_FAILED" "default=Translation process failed")")" >&2
        return 1
    fi

    # --- 計測開始 ---
    start_time=$(date +%s)
    # ---------------

    # Start spinner before the loop (Removed type check)
    # Assuming start_spinner is always available
    start_spinner "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name" "default=Currently translating: $domain_name")")" 
    spinner_started="true"
    debug_log "DEBUG" "Spinner started for domain: ${domain_name}"
    # If start_spinner wasn't found, script would likely error here or previously

    # Create/overwrite the output DB with the header
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
# Translation generated using: ${aip_function_name}
# Target Language: ${target_lang_code}
EOF

    # Loop through the base DB using efficient redirection and case statements
    while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac

        case "$line" in
            "${DEFAULT_LANGUAGE}|"*)
                ;;
            *)
                continue
                ;;
        esac

        # Extract key and value using shell parameter expansion
        local line_content=${line#*|} # Remove "LANG|" prefix
        local key=${line_content%%=*}   # Get key before '='
        local value=${line_content#*=}  # Get value after '='

        # Skip if key or value extraction failed (basic check)
        if [ -z "$key" ] || [ -z "$value" ]; then
             debug_log "DEBUG" "Skipping malformed line: $line"
            continue
        fi

        # --- Directly call the provided AIP function (Removed type check) ---
        local translated_text=""
        local exit_code=1 # Default to failure

        # Assuming $aip_function_name points to an existing function
        translated_text=$("$aip_function_name" "$value" "$target_lang_code")
        exit_code=$?
        # If $aip_function_name was invalid, script errors here

        # --- Output Line ---
        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$translated_text" >> "$output_db"
        else
             if [ "$exit_code" -ne 0 ]; then # Log only if the function call failed
                 debug_log "DEBUG" "Translation failed (Exit code: $exit_code) for key '$key'. Using original value."
             else
                 debug_log "DEBUG" "Translation resulted in empty string for key '$key'. Using original value."
             fi
             overall_success=2 # Mark as partial failure
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$value" >> "$output_db"
        fi
        # --- End Output Line ---

    done < "$base_db" # Read directly from the base DB

    # --- 計測終了 & 計算 ---
    end_time=$(date +%s)
    elapsed_seconds=$((end_time - start_time))
    # ----------------------

    # Stop spinner after the loop (Removed type check)
    if [ "$spinner_started" = "true" ]; then
        # Assuming stop_spinner is always available
        local final_message=""
        local spinner_status="success" # Default: success

        if [ "$overall_success" -eq 0 ]; then
            final_message=$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Language file created successfully (${elapsed_seconds}s)")
        else
            final_message=$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")
            spinner_status="warning" # Indicate warning state
        fi

        stop_spinner "$final_message" "$spinner_status"
        debug_log "DEBUG" "Translation task completed in ${elapsed_seconds} seconds. Status: ${spinner_status}"
        # If stop_spinner wasn't found, script would likely error here
    else
        # This else block handles the case where the spinner wasn't started
        # (which shouldn't happen now without the type check failure path,
        # unless start_spinner itself fails internally).
        # Print final status directly if spinner wasn't started (or stop_spinner unavailable)
         if [ "$overall_success" -eq 0 ]; then
             printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Language file created successfully (${elapsed_seconds}s)")")"
         else
             printf "%s\n" "$(color yellow "$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")")"
         fi
    fi

    # Add the completion marker key at the end of the file
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    printf "%s|%s=%s\n" "$target_lang_code" "$marker_key" "true" >> "$output_db"
    debug_log "DEBUG" "Completion marker added to ${output_db}"

    debug_log "DEBUG" "Language DB creation process completed for ${target_lang_code}"
    return "$overall_success" # Return 0 for success, 2 for partial failure
}

# 翻訳DB作成関数 (責務: DBファイル作成、AIP関数呼び出し、スピナー制御、時間計測)
# @param $1: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - The base API endpoint URL (Currently unused, kept for potential future compatibility or logging)
# @param $3: domain_name (string) - The domain name for spinner display (e.g., "translate.googleapis.com")
# @param $4: target_lang_code (string) - The target language code (e.g., "ja")
# @return: 0 on success, 1 on base DB not found, 2 if any translation fails (writes original text for failures)
CASE_create_language_db() {
    local aip_function_name="$1"
    local api_endpoint_url="$2" # Unused in current logic, passed for context
    local domain_name="$3"      # Explicitly passed domain name for spinner
    local target_lang_code="$4"

    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local output_db="${BASE_DIR}/message_${target_lang_code}.db"
    local spinner_started="false"
    local overall_success=0 # Assume success initially, 2 indicates at least one translation failed
    # --- 時間計測用変数 ---
    local start_time=""
    local end_time=""
    local elapsed_seconds=""
    # ---------------------

    debug_log "DEBUG" "Creating language DB for target '${target_lang_code}' using function '${aip_function_name}' with domain '${domain_name}'"

    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found: $base_db. Cannot create target DB."
        # Ensure get_message exists and handles missing keys gracefully
        printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_FAILED" "default=Translation process failed")")" >&2
        return 1
    fi

    # --- 計測開始 ---
    start_time=$(date +%s)
    # ---------------

    # Start spinner before the loop
    if type start_spinner >/dev/null 2>&1; then
        # Ensure get_message exists
        start_spinner "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name" "default=Currently translating: $domain_name")")" 
        spinner_started="true"
        debug_log "DEBUG" "Spinner started for domain: ${domain_name}"
    else
        debug_log "DEBUG" "start_spinner function not found. Spinner not shown."
         # Display message directly if spinner is not available
         printf "%s\n" "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name" "default=Currently translating: $domain_name")")"
    fi

    # Create/overwrite the output DB with the header
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
# Translation generated using: ${aip_function_name}
# Target Language: ${target_lang_code}
EOF

    # Loop through the base DB using efficient redirection and case statements
    while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac

        case "$line" in
            "${DEFAULT_LANGUAGE}|"*)
                ;;
            *)
                continue
                ;;
        esac

        # Extract key and value using shell parameter expansion
        local line_content=${line#*|} # Remove "LANG|" prefix
        local key=${line_content%%=*}   # Get key before '='
        local value=${line_content#*=}  # Get value after '='

        # Skip if key or value extraction failed (basic check)
        if [ -z "$key" ] || [ -z "$value" ]; then
             debug_log "DEBUG" "Skipping malformed line: $line"
            continue
        fi

        # --- Directly call the provided AIP function ---
        local translated_text=""
        local exit_code=1 # Default to failure

        # Check if the function actually exists before calling (optional safety)
        if type "$aip_function_name" >/dev/null 2>&1; then
            translated_text=$("$aip_function_name" "$value" "$target_lang_code")
            exit_code=$?
        else
             "AIP function '$aip_function_name' not found during loop execution."
            exit_code=1 # Mark as failure
            overall_success=2 # Mark overall as partial failure
        fi

        # --- Output Line ---
        if [ "$exit_code" -eq 0 ] && [ -n "$translated_text" ]; then
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$translated_text" >> "$output_db"
        else
             if [ "$exit_code" -ne 0 ]; then # Log only if the function call failed
                 debug_log "DEBUG" "Translation failed (Exit code: $exit_code) for key '$key'. Using original value."
             else
                 debug_log "DEBUG" "Translation resulted in empty string for key '$key'. Using original value."
             fi
             overall_success=2 # Mark as partial failure
            printf "%s|%s=%s\n" "$target_lang_code" "$key" "$value" >> "$output_db"
        fi
        # --- End Output Line ---

    done < "$base_db" # Read directly from the base DB

    # --- 計測終了 & 計算 ---
    end_time=$(date +%s)
    elapsed_seconds=$((end_time - start_time))
    # ----------------------

    # Stop spinner after the loop
    if [ "$spinner_started" = "true" ]; then
        if type stop_spinner >/dev/null 2>&1; then
            local final_message=""
            local spinner_status="success" # Default: success

            if [ "$overall_success" -eq 0 ]; then
                final_message=$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Language file created successfully (${elapsed_seconds}s)")
            else
                final_message=$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")
                spinner_status="warning" # Indicate warning state
            fi

            stop_spinner "$final_message" "$spinner_status"
             "Translation task completed in ${elapsed_seconds} seconds. Status: ${spinner_status}"
        else
            debug_log "DEBUG" "stop_spinner function not found."
             # Print final status directly if spinner stop is unavailable
             if [ "$overall_success" -eq 0 ]; then
                 printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATING_CREATED" "s=$elapsed_seconds" "default=Language file created successfully (${elapsed_seconds}s)")")"
             else
                 printf "%s\n" "$(color yellow "$(get_message "MSG_TRANSLATION_PARTIAL" "s=$elapsed_seconds" "default=Translation partially completed (${elapsed_seconds}s)")")"
             fi
        fi
    fi

    # Add the completion marker key at the end of the file
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    printf "%s|%s=%s\n" "$target_lang_code" "$marker_key" "true" >> "$output_db"
    debug_log "DEBUG" "Completion marker added to ${output_db}"

    debug_log "DEBUG" "Language DB creation process completed for ${target_lang_code}"
    return "$overall_success" # Return 0 for success, 2 for partial failure
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
        start_spinner "$(color blue "$(get_message "MSG_TRANSLATING_CURRENTLY" "api=$domain_name")")" 
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

        local line_content=${line#*|} # Remove "en|" prefix
        local key=${line_content%%=*}   # Get key before '='
        local value=${line_content#*=}  # Get value after '='

        if [ -z "$key" ] || [ -z "$value" ]; then
            continue
        fi

        # --- Directly call the AIP function (変更なし) ---
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
        if [ "$db_creation_result" -ne 1 ]; then # Avoid duplicate if base DB missing
             printf "%s\n" "$(color yellow "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code")")"
        fi
        # --- 修正 --- 失敗時は display_detected_translation を呼び出さない
        return "$db_creation_result" # Propagate error code
    fi
}
