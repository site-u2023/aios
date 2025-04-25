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

# =========================================================
# Single Translation Task (for Parallel Execution) - Latest
# =========================================================
# parallel_translate_task: Executes a single translation using a specified function.
# Writes the result as a DB entry (msgid + msgstr) to a result file.
# Assumes debug_log is available and sourced.
# @param $1: item_id (Unique identifier for the task, e.g., "Line-123")
# @param $2: source_text (Text to translate - the msgid content)
# @param $3: target_lang_code (e.g., "ja")
# @param $4: result_file (Path to write the DB entry)
# @param $5: translation_function_name (Name of the function to call for translation)
# @stdout: None directly. Writes DB entry to $result_file.
# @stderr: Logs progress using debug_log.
# @return: 0 on successful translation and file writing, 1 on translation failure, 2 on file writing failure.
parallel_translate_task() {
    local item_id="$1"
    local source_text="$2"
    local target_lang_code="$3"
    local result_file="$4"
    local translation_function_name="$5"

    local translated_content=""
    local translation_exit_code=1

    debug_log "DEBUG" "  [TASK $item_id] Starting '$translation_function_name' for: \"$(echo "$source_text" | cut -c 1-30)...\""

    # Execute the translation function
    # Ensure source_text is passed correctly, handle potential quoting issues if necessary
    translated_content=$("$translation_function_name" "$source_text" "$target_lang_code")
    translation_exit_code=$?

    local final_msgstr_content=""

    # Determine msgstr content based on translation result
    if [ "$translation_exit_code" -eq 0 ] && [ -n "$translated_content" ]; then
        debug_log "DEBUG" "  [TASK $item_id] Translation successful via '$translation_function_name'."
        final_msgstr_content="$translated_content"
    else
        debug_log "WARN" "  [TASK $item_id] Translation failed via '$translation_function_name' (Exit code: $translation_exit_code). Using original text for msgstr."
        final_msgstr_content="$source_text" # Use original source text as msgstr on failure
        # Update exit code if translation was technically successful but empty
        if [ "$translation_exit_code" -eq 0 ] && [ -z "$translated_content" ]; then
            translation_exit_code=1 # Treat empty success as failure for return code
        fi
    fi

    # Escape potential backslashes and double quotes in msgid and msgstr content
    # Use simple sed, avoid complex regex if possible for BusyBox compatibility
    local escaped_msgid=$(echo "$source_text" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    local escaped_msgstr=$(echo "$final_msgstr_content" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

    # Write the complete entry to the result file
    # Overwrite result file first with msgid
    printf "msgid \"%s\"\n" "$escaped_msgid" > "$result_file"
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "  [TASK $item_id] Failed to write msgid to $result_file."
        return 2 # File writing failure
    fi
    # Append msgstr to the result file
    printf "msgstr \"%s\"\n" "$escaped_msgstr" >> "$result_file"
     if [ $? -ne 0 ]; then
        debug_log "ERROR" "  [TASK $item_id] Failed to write msgstr to $result_file."
        # Consider removing the partially written file?
        # rm -f "$result_file"
        return 2 # File writing failure
    fi

    # Return the original translation exit code (0 for success, 1 for failure/empty)
    # This exit code is NOT currently captured by the caller function in the simplified design.
    return "$translation_exit_code"
}

# --- Ensure the rest of common-translation.sh is also up-to-date ---
# ... (other functions like debug_log, translate_with_google etc.) ...

# create_language_db_parallel function (as provided in the previous correct version)
# =========================================================
# Parallel Language Database Creation - Revised (grep exit code fix)
# =========================================================
# ... (The rest of the create_language_db_parallel function) ...

# =========================================================
# Parallel Language Database Creation - Revised (grep exit code fix)
# =========================================================
# create_language_db_parallel: Creates a language DB file by translating msgids in parallel.
# Pre-counts tasks and uses a for loop for launching.
# Waits for the expected number of result files before assembly.
# Final DB is assembled by concatenating temporary files (order not preserved).
# Integrity is checked by comparing source msgid count with generated msgid count.
# Correctly handles grep exit codes (0=match, 1=no match, >1=error).
# Assumes BASE_DIR, DEFAULT_LANGUAGE, MAX_PARALLEL_TASKS, debug_log,
# and parallel_translate_task are available and sourced.
# @param $1: api_name
# @param $2: api_url (Optional)
# @param $3: domain
# @param $4: target_lang_code
# @stdout: None directly. Writes final .db file.
# @stderr: Logs progress using debug_log.
# @return: 0 on complete success, 1 on critical error, 2 if any task reported failure (simplified check).
create_language_db_parallel() {
    local api_name="$1"
    # local api_url="$2"
    local domain="$3"
    local target_lang_code="$4"
    local source_lang_code="$DEFAULT_LANGUAGE"
    local translation_function_name="translate_with_${api_name}"

    local source_dir="${BASE_DIR}/locale/${source_lang_code}"
    local target_dir="${BASE_DIR}/locale/${target_lang_code}"
    local source_db="${source_dir}/${domain}.db"
    local target_db="${target_dir}/${domain}.db"
    local target_db_tmp="${target_dir}/${domain}.db.tmp"
    local marker_file="${target_db}.completed" # Overall completion marker

    local return_code=0 # 0=success, 1=critical error, 2=partial (task failure - simplified check)

    # --- Pre-checks ---
    debug_log "INFO" "Starting parallel DB creation (grep exit code fix) for domain '$domain', target '$target_lang_code' using '$translation_function_name'."

    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir" || { debug_log "ERROR" "Failed to create target directory: $target_dir"; return 1; }
        debug_log "INFO" "Created target directory: $target_dir"
    fi

    if [ ! -f "$source_db" ]; then
        debug_log "ERROR" "Source DB file not found: $source_db"
        return 1
    fi

    # --- Count expected translatable msgids ---
    local expected_msgid_count=0
    expected_msgid_count=$(awk '/^msgid[ \t]+".*"$/ { msgid_line = $0; getline; if ($0 ~ /^msgstr[ \t]+""$/ && msgid_line != "msgid \"\"") count++ } END { print count }' "$source_db")
    if [ $? -ne 0 ] || ! echo "$expected_msgid_count" | grep -qE '^[0-9]+$'; then
        debug_log "ERROR" "Failed to count expected msgids in $source_db. Found: '$expected_msgid_count'"
        return 1
    fi
    debug_log "INFO" "Expected translatable msgid count from source: $expected_msgid_count"

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
         msgid_block = msgid_block $0;
     }
     next;
}
/^msgstr[ \t]+""$/ {
     if (msgid_block != "" && msgid_block != "\"\"") {
         item_id = "Line-" line_num
         # Output format: item_id|source_text|result_file
         printf "%s|%s|%s/%s.txt\n", item_id, msgid_block, tmp_dir, item_id
     }
     msgid_block = ""; next;
}
EOF
    # --- End AWK script file creation ---

    # --- Pre-generate task list and count tasks ---
    local task_list=""
    local task_count=0
    debug_log "INFO" "Generating task list..."
    task_list=$(awk -f "$awk_script_file" -v tmp_dir="$tmp_dir" "$source_db")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "Failed to generate task list using awk."
        if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then rm -rf "$tmp_dir"; fi
        return 1
    fi
    if [ -n "$task_list" ]; then
         task_count=$(echo "$task_list" | wc -l)
    else
         task_count=0
    fi
    debug_log "INFO" "Generated task list with $task_count tasks."

    # Clean previous temporary output and marker files
    rm -f "$target_db_tmp" "$marker_file"

    # --- Launch Background Translation Tasks using for loop ---
    debug_log "INFO" "Launching $task_count translation tasks..."
    if [ "$task_count" -gt 0 ]; then
        printf '%s\n' "$task_list" | while IFS='|' read -r item_id source_text result_f; do
            if [ -n "$item_id" ] && [ -n "$source_text" ] && [ -n "$result_f" ]; then
                while [ "$(jobs -p | wc -l)" -ge "$MAX_PARALLEL_TASKS" ]; do
                    sleep 1
                done
                debug_log "DEBUG" "Launching task $item_id for source text starting with: $(echo "$source_text" | cut -c 1-30)..."
                parallel_translate_task "$item_id" "$source_text" "$target_lang_code" "$result_f" "$translation_function_name" &
            else
                 debug_log "WARN" "Skipping invalid line from task list: $item_id|$source_text|$result_f"
            fi
        done
    fi
    debug_log "INFO" "Finished launching tasks."

    # --- Wait for all result files to be created ---
    local current_file_count=0
    local wait_timeout=$(( task_count * 2 + 10 ))
    local wait_start_time=$(date +%s)
    local elapsed_time=0

    if [ "$task_count" -gt 0 ]; then
        debug_log "INFO" "Waiting for $task_count result files to appear in $tmp_dir (timeout: ${wait_timeout}s)..."
        while [ "$current_file_count" -lt "$task_count" ]; do
            current_file_count=$(ls "$tmp_dir"/*.txt 2>/dev/null | wc -l)
            if ! echo "$current_file_count" | grep -qE '^[0-9]+$'; then
                 current_file_count=0
            fi
            elapsed_time=$(( $(date +%s) - wait_start_time ))
            if [ "$elapsed_time" -ge "$wait_timeout" ]; then
                debug_log "ERROR" "Timeout waiting for result files. Expected $task_count, found $current_file_count after ${elapsed_time}s."
                if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then rm -rf "$tmp_dir"; fi
                return 1
            fi
            if [ "$current_file_count" -lt "$task_count" ]; then
                debug_log "DEBUG" "Found $current_file_count/$task_count files. Waiting 1 second..."
                sleep 1
            fi
        done
        debug_log "INFO" "All $task_count result files found in $tmp_dir after ${elapsed_time}s."
    else
        debug_log "INFO" "No tasks were launched, skipping file wait loop."
    fi

    # --- Assemble Final DB File by Concatenating Results ---
    debug_log "INFO" "Assembling final DB file by concatenating results from $tmp_dir..."
    rm -f "$target_db_tmp" # Ensure clean temp file

    local generated_msgid_count=0
    local any_task_failed_simple=0

    if [ -z "$(ls -A "$tmp_dir"/*.txt 2>/dev/null | head -n 1)" ] && [ "$task_count" -gt 0 ]; then
        debug_log "WARN" "Tasks were launched ($task_count), but no result files (*.txt) found in $tmp_dir. The final DB will be empty."
        touch "$target_db_tmp"
        any_task_failed_simple=1
        generated_msgid_count=0
    elif [ "$task_count" -eq 0 ]; then
         debug_log "INFO" "No tasks were launched. Creating empty target DB."
         touch "$target_db_tmp"
         generated_msgid_count=0
    else
        # Files exist, proceed with concatenation
        cat ${tmp_dir}/*.txt > "$target_db_tmp"
        if [ $? -ne 0 ]; then
             debug_log "ERROR" "Failed to concatenate result files into $target_db_tmp."
             return_code=1
        else
             # --- 修正: Count msgids and handle grep exit code ---
             generated_msgid_count=$(grep -c '^msgid[ \t]' "$target_db_tmp")
             local grep_c_exit_code=$?
             if [ "$grep_c_exit_code" -eq 0 ]; then
                 debug_log "INFO" "Generated msgid count in temporary DB: $generated_msgid_count"
             elif [ "$grep_c_exit_code" -eq 1 ]; then
                 # No match found, count is 0
                 debug_log "INFO" "Generated msgid count in temporary DB: 0 (No msgid lines found)"
                 generated_msgid_count=0
             else
                 # grep error (exit code > 1)
                 debug_log "ERROR" "Failed to count msgids in generated file $target_db_tmp (grep exit code: $grep_c_exit_code)."
                 return_code=1
             fi
             # --- 修正終了 ---

             # --- 修正: Simple check for failed tasks and handle grep exit code ---
             # Check only if return_code is still 0
             if [ "$return_code" -eq 0 ]; then
                 grep -q -E '^msgstr "This one should fail the translation"$' "$target_db_tmp"
                 local grep_q_exit_code=$?
                 if [ "$grep_q_exit_code" -eq 0 ]; then
                     # Match found - indicates potential failure
                     debug_log "WARN" "Detected potential task failure (original text used as msgstr)."
                     any_task_failed_simple=1
                 elif [ "$grep_q_exit_code" -eq 1 ]; then
                     # No match found - expected for successful tasks
                     : # Do nothing
                 else
                     # grep error (exit code > 1)
                     debug_log "ERROR" "Failed to check for failed tasks in $target_db_tmp (grep exit code: $grep_q_exit_code)."
                     return_code=1
                 fi
             fi
             # --- 修正終了 ---
        fi
    fi

    # --- Finalization ---
    if [ "$return_code" -eq 1 ]; then
        : # Critical error already occurred
    elif [ "$expected_msgid_count" -ne "$generated_msgid_count" ]; then
        debug_log "ERROR" "Integrity check failed: Expected $expected_msgid_count msgids, but generated file contains $generated_msgid_count msgids."
        return_code=1
    elif [ "$any_task_failed_simple" -eq 1 ]; then
        debug_log "WARN" "Parallel DB creation completed, but potential task failures detected. (Count matched: $generated_msgid_count)"
        return_code=2
    else
        debug_log "INFO" "Parallel DB creation completed successfully. (Count matched: $generated_msgid_count)"
        return_code=0
    fi

    # Move final file into place
    if [ "$return_code" -ne 1 ] && [ -f "$target_db_tmp" ]; then
         mv "$target_db_tmp" "$target_db"
         if [ $? -eq 0 ]; then
             debug_log "INFO" "Successfully created target DB: $target_db (Order not preserved)"
             if [ "$return_code" -eq 0 ] || [ "$return_code" -eq 2 ]; then
                 touch "$marker_file"
                 debug_log "INFO" "Created completion marker file: $marker_file"
             fi
         else
             debug_log "ERROR" "Failed to move temporary DB file to $target_db"
             return_code=1
         fi
    elif [ "$return_code" -ne 1 ]; then
         debug_log "ERROR" "Final temporary DB file ($target_db_tmp) not found before move operation."
         return_code=1
    fi

    # --- Cleanup ---
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        debug_log "DEBUG" "Removing temporary directory: $tmp_dir"
        rm -rf "$tmp_dir"
    fi
    # --- Cleanup End ---

    debug_log "INFO" "Finished parallel DB creation for domain '$domain'. Final return code: $return_code"
    return "$return_code"
}


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
#               checks/creates the translation DB if needed (not default lang and DB doesn't exist),
#               and displays translation info ONLY AFTER confirmation/creation or if DB exists.
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
    # local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER" # Marker check removed

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

    # 3. Check if target DB exists (Marker check removed)
    target_db="${BASE_DIR}/message_${lang_code}.db"
    debug_log "DEBUG" "translate_main: Checking for existing target DB: ${target_db}"

    if [ -f "$target_db" ]; then
         debug_log "DEBUG" "translate_main: Target DB '${target_db}' exists for '${lang_code}'. Assuming complete."
         # --- 修正 --- ファイルが存在すれば表示して終了
         display_detected_translation
         return 0 # <<< Early return: DB exists
    else
        debug_log "DEBUG" "translate_main: Target DB '${target_db}' does not exist. Proceeding with creation."
    fi

    # --- Proceed with Translation Process ---
    # (Steps 4 & 5: Find function, determine domain - remain the same as previous version)
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


    # 6. Call create_language_db_parallel (Assuming this is the intended function now)
    debug_log "DEBUG" "translate_main: Calling create_language_db_parallel for language '${lang_code}' using function '${selected_func}'"
    # Note: create_language_db_parallel expects slightly different args (api_name, api_url (unused), domain_name, lang_code)
    # We need to adapt the call here. Let's assume domain_name is sufficient for api_name context.
    create_language_db_parallel "$selected_func" "" "$domain_name" "$lang_code" # Pass selected_func as api_name
    db_creation_result=$?
    debug_log "DEBUG" "translate_main: create_language_db_parallel finished with status: ${db_creation_result}"

    # 7. Handle Result and Display Info ONLY on Success or Partial Success
    if [ "$db_creation_result" -eq 0 ] || [ "$db_creation_result" -eq 2 ]; then # Check for 0 (success) or 2 (partial)
        debug_log "DEBUG" "translate_main: Language DB creation successful or partially successful for ${lang_code}."
        # --- 修正 --- DB作成成功/部分成功後に表示
        display_detected_translation
        return "$db_creation_result" # Return the actual result code (0 or 2)
    else
        debug_log "DEBUG" "translate_main: Language DB creation failed for ${lang_code} (Exit status: ${db_creation_result})."
        if [ "$db_creation_result" -ne 1 ]; then # Avoid duplicate msg if base DB missing (code 1)
             printf "%s\n" "$(color yellow "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code")")"
        fi
        # --- 修正 --- 失敗時は display_detected_translation を呼び出さない
        return "$db_creation_result" # Propagate error code (likely 1)
    fi
}
