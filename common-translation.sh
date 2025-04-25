#!/bin/sh 

SCRIPT_VERSION="2025-04-25-00-01" # Updated version based on last interaction time

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

MESSAGE_DB="${MESSAGE_DB:-${BASE_DIR}/message_en.db}"

# Maximum number of parallel translation tasks. Can be overridden by environment variable.
MAX_PARALLEL_TASKS="${MAX_PARALLEL_TASKS:-2}"

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

# =========================================================
# Single Translation Task (for Parallel Execution) - New Function
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
        if [ "$translation_exit_code" -eq 0 ] && [ -z "$translated_content" ]; then
            translation_exit_code=1 # Treat empty success as failure for return code
        fi
    fi

    # Escape potential backslashes and double quotes
    local escaped_msgid=$(echo "$source_text" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    local escaped_msgstr=$(echo "$final_msgstr_content" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

    # Write the complete entry to the result file
    printf "msgid \"%s\"\n" "$escaped_msgid" > "$result_file"
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "  [TASK $item_id] Failed to write msgid to $result_file."
        return 2 # File writing failure
    fi
    printf "msgstr \"%s\"\n" "$escaped_msgstr" >> "$result_file"
     if [ $? -ne 0 ]; then
        debug_log "ERROR" "  [TASK $item_id] Failed to write msgstr to $result_file."
        return 2 # File writing failure
    fi

    # Return the original translation exit code (0 for success, 1 for failure/empty)
    return "$translation_exit_code"
}

# =========================================================
# Parallel Language Database Creation - Modified Function
# =========================================================
# create_language_db: Creates a language DB file by translating entries in parallel.
# Reads from MESSAGE_DB (e.g., en|KEY=Value), outputs .po format.
# Assumes MESSAGE_DB, MAX_PARALLEL_TASKS, debug_log, parallel_translate_task are available.
# @param $1: api_name (string) - Name of the translation function (e.g., translate_with_google).
# @param $2: api_url (string) - Optional API URL (unused in current logic).
# @param $3: domain_name (string) - Domain name for display/logging (e.g., "translate.googleapis.com").
# @param $4: target_lang_code (string) - The target language code (e.g., "ja").
# @stdout: None directly. Writes final .db file in .po format to ${BASE_DIR}/message_${target_lang_code}.db.
# @stderr: Logs progress using debug_log.
# @return: 0 on complete success, 1 on critical error, 2 if any task reported failure.
create_language_db() {
    local api_name="$1" # Name of the translation function (e.g., translate_with_google)
    # local api_url="$2" # Unused argument
    local domain_name="$3" # Domain name for logging/display
    local target_lang_code="$4"
    local translation_function_name="$api_name" # Use api_name as the function name

    local source_db="$MESSAGE_DB"
    # --- Modified: Use flat structure for target DB path ---
    local target_db="${BASE_DIR}/message_${target_lang_code}.db"
    # --- Modification End ---
    local target_db_tmp="${target_db}.tmp"
    # local target_dir="${BASE_DIR}/locale/${target_lang_code}" # Removed

    local return_code=0 # 0=success, 1=critical error, 2=partial

    # --- Pre-checks ---
    local display_name="${domain_name:-$api_name}"
    debug_log "INFO" "Starting parallel DB creation for target '$target_lang_code' using '$translation_function_name' ($display_name). Output: $target_db" # Log target path

    # --- Modified: Removed target directory creation ---
    # if [ ! -d "$target_dir" ]; then
    #     mkdir -p "$target_dir" || { debug_log "ERROR" "Failed to create target directory: $target_dir"; return 1; }
    #     debug_log "INFO" "Created target directory: $target_dir"
    # fi
    # --- Modification End ---

    if [ ! -f "$source_db" ]; then
        debug_log "ERROR" "Source DB file not found: $source_db (from MESSAGE_DB)"
        return 1
    fi

    # --- Count expected translatable entries based on MESSAGE_DB format ---
    local expected_entry_count=0
    expected_entry_count=$(grep -c '^en|' "$source_db")
    local grep_c_exit_code=$?
    if [ "$grep_c_exit_code" -eq 0 ]; then
        :
    elif [ "$grep_c_exit_code" -eq 1 ]; then
        expected_entry_count=0
    else
        debug_log "ERROR" "Failed to count expected entries in $source_db (grep exit code: $grep_c_exit_code)."
        return 1
    fi
    debug_log "INFO" "Expected translatable entry count from source ($source_db): $expected_entry_count"

    # --- Prepare for Parallel Processing ---
    local tmp_dir=$(mktemp -d -p "${TMP_DIR:-/tmp}" "parallel_translate_messages_${target_lang_code}_XXXXXX")
    if [ -z "$tmp_dir" ] || [ ! -d "$tmp_dir" ]; then
        debug_log "ERROR" "Failed to create temporary directory."
        return 1
    fi
    debug_log "DEBUG" "Created temporary directory for results: $tmp_dir"

    # --- Create AWK script file for parsing MESSAGE_DB format (en|KEY=Value) ---
    local awk_script_file="${tmp_dir}/parse_db.awk"
    cat > "$awk_script_file" << 'EOF'
BEGIN { FS="="; OFS="|" }
/^[ \t]*#/ || /^[ \t]*$/ { next }
/^en\|/ {
    line_content = substr($0, 4)
    eq_pos = index(line_content, "=")
    if (eq_pos > 0) {
        source_key = substr(line_content, 1, eq_pos - 1)
        source_value = substr(line_content, eq_pos + 1)
        if (source_key != "" && source_value != "") {
            item_id = "Entry-" NR
            printf "%s|%s|%s/%s.txt|%s\n", item_id, source_value, tmp_dir, item_id, source_key
        }
    }
}
EOF

    # --- Pre-generate task list and count tasks ---
    local task_list=""
    local task_count=0
    debug_log "INFO" "Generating task list from $source_db..."
    task_list=$(awk -f "$awk_script_file" -v tmp_dir="$tmp_dir" "$source_db")
    # Awk error check (slightly adjusted)
    if [ $? -ne 0 ] && [ -z "$task_list" ]; then
        debug_log "ERROR" "Failed to generate task list using awk (awk exit code non-zero and output empty)."
        if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then rm -rf "$tmp_dir"; fi
        return 1
    elif [ $? -ne 0 ]; then
         debug_log "WARN" "Awk script finished with potential warnings (check stderr), but generated a task list."
    fi
    # Count tasks
    if [ -n "$task_list" ]; then
         task_count=$(echo "$task_list" | grep -c '^')
    else
         task_count=0
    fi
    debug_log "INFO" "Generated task list with $task_count tasks."

    rm -f "$target_db_tmp"

    # --- Launch Background Translation Tasks ---
    debug_log "INFO" "Launching $task_count translation tasks (Max parallel: $MAX_PARALLEL_TASKS)..."
    if [ "$task_count" -gt 0 ]; then
        printf '%s\n' "$task_list" | while IFS='|' read -r item_id source_value result_f source_key; do
            if [ -n "$item_id" ] && [ -n "$result_f" ] && [ -n "$source_key" ]; then
                while [ "$(jobs -p | wc -l)" -ge "$MAX_PARALLEL_TASKS" ]; do
                    sleep 1
                done
                debug_log "DEBUG" "Launching task $item_id for key '$source_key' (value starts with: $(echo "$source_value" | cut -c 1-30)...)"
                parallel_translate_task "$item_id" "$source_value" "$target_lang_code" "$result_f" "$translation_function_name" "$source_key" &
            else
                 debug_log "WARN" "Skipping invalid line from task list: $item_id|$source_value|$result_f|$source_key"
            fi
        done
    fi
    debug_log "INFO" "Finished launching tasks."

    # --- Wait for all result files ---
    local current_file_count=0
    local wait_timeout=$(( task_count * 2 + 10 ))
    local wait_start_time=$(date +%s)
    local elapsed_time=0
    if [ "$task_count" -gt 0 ]; then
        debug_log "INFO" "Waiting for $task_count result files in $tmp_dir (timeout: ${wait_timeout}s)..."
        while [ "$current_file_count" -lt "$task_count" ]; do
            current_file_count=$(ls "$tmp_dir"/*.txt 2>/dev/null | wc -l)
            if ! echo "$current_file_count" | grep -qE '^[0-9]+$'; then current_file_count=0; fi
            elapsed_time=$(( $(date +%s) - wait_start_time ))
            if [ "$elapsed_time" -ge "$wait_timeout" ]; then
                debug_log "ERROR" "Timeout waiting for result files. Expected $task_count, found $current_file_count after ${elapsed_time}s."
                if [ "$(jobs -p)" ]; then kill $(jobs -p); fi
                if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then rm -rf "$tmp_dir"; fi
                return 1
            fi
            if [ "$current_file_count" -lt "$task_count" ]; then
                debug_log "DEBUG" "Found $current_file_count/$task_count files. Waiting..."
                sleep 1
            fi
        done
        debug_log "INFO" "All $task_count result files found in $tmp_dir after ${elapsed_time}s."
    else
        debug_log "INFO" "No tasks launched, skipping file wait."
    fi

    # --- Assemble Final DB File ---
    debug_log "INFO" "Assembling final DB file ($target_db_tmp) in .po format..."
    rm -f "$target_db_tmp"
    # Add .po header
    printf "msgid \"\"\n" > "$target_db_tmp"
    printf "msgstr \"\"\n" >> "$target_db_tmp"
    printf "\"Project-Id-Version: aios\\n\"\n" >> "$target_db_tmp"
    printf "\"POT-Creation-Date: %s\\n\"\n" "$(date -u +'%Y-%m-%d %H:%M+0000')" >> "$target_db_tmp"
    printf "\"Language: %s\\n\"\n" "$target_lang_code" >> "$target_db_tmp"
    printf "\"MIME-Version: 1.0\\n\"\n" >> "$target_db_tmp"
    printf "\"Content-Type: text/plain; charset=UTF-8\\n\"\n" >> "$target_db_tmp"
    printf "\"Content-Transfer-Encoding: 8bit\\n\"\n" >> "$target_db_tmp"
    printf "\n" >> "$target_db_tmp"

    local generated_msgid_count=0
    local any_task_failed_simple=0
    if [ -z "$(ls -A "$tmp_dir"/*.txt 2>/dev/null | head -n 1)" ] && [ "$task_count" -gt 0 ]; then
        debug_log "WARN" "No result files (*.txt) found in $tmp_dir. Final DB will contain only header."
        any_task_failed_simple=1
        generated_msgid_count=0
    elif [ "$task_count" -eq 0 ]; then
         debug_log "INFO" "No tasks launched. Final DB contains only header."
         generated_msgid_count=0
    else
        cat "$tmp_dir"/*.txt >> "$target_db_tmp"
        if [ $? -ne 0 ]; then
             debug_log "ERROR" "Failed to concatenate result files into $target_db_tmp."
             return_code=1
        else
             # Count non-empty msgids
             generated_msgid_count=$(grep -c '^msgid[ \t]"[^"]' "$target_db_tmp")
             local grep_c_exit_code=$?
             if [ "$grep_c_exit_code" -eq 0 ]; then
                 debug_log "INFO" "Generated non-empty msgid count: $generated_msgid_count"
             elif [ "$grep_c_exit_code" -eq 1 ]; then
                 generated_msgid_count=0
                 debug_log "INFO" "Generated non-empty msgid count: 0"
             else
                 debug_log "ERROR" "Failed to count msgids in $target_db_tmp (grep exit code: $grep_c_exit_code)."
                 return_code=1
             fi
             # Simple failure check (placeholder)
             if [ "$return_code" -eq 0 ]; then
                 grep -q -F 'msgstr "This one should fail the translation"' "$target_db_tmp" # Adjust if needed
                 if [ $? -eq 0 ]; then
                     debug_log "WARN" "Potential task failure detected (check logic if needed)."
                     any_task_failed_simple=1
                 elif [ $? -ne 1 ]; then
                     debug_log "ERROR" "Failed checking for failed tasks (grep exit code: $?)."
                     return_code=1
                 fi
             fi
        fi
    fi

    # --- Finalization ---
    if [ "$return_code" -eq 1 ]; then
        :
    elif [ "$expected_entry_count" -ne "$generated_msgid_count" ]; then
        debug_log "ERROR" "Integrity check failed: Expected $expected_entry_count entries, generated $generated_msgid_count non-empty msgids."
        return_code=1
    elif [ "$any_task_failed_simple" -eq 1 ]; then
        debug_log "WARN" "Parallel DB creation completed with potential task failures. (Count matched: $generated_msgid_count)"
        return_code=2
    else
        debug_log "INFO" "Parallel DB creation successful. (Count matched: $generated_msgid_count)"
        return_code=0
    fi

    # Move final file
    if [ "$return_code" -ne 1 ] && [ -f "$target_db_tmp" ]; then
         mv "$target_db_tmp" "$target_db"
         if [ $? -eq 0 ]; then
             debug_log "INFO" "Successfully created target DB: $target_db"
         else
             debug_log "ERROR" "Failed to move temporary DB file to $target_db"
             return_code=1
         fi
    elif [ "$return_code" -ne 1 ]; then
         debug_log "ERROR" "Final temporary DB file ($target_db_tmp) not found before move."
         return_code=1
    fi

    # --- Cleanup ---
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        debug_log "DEBUG" "Removing temporary directory: $tmp_dir"
        rm -rf "$tmp_dir"
    fi

    debug_log "INFO" "Finished parallel DB creation for '$target_lang_code'. Final return code: $return_code"
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

# 翻訳情報を表示する関数
# Modified: Uses MESSAGE_DB for source and flat path for target
display_detected_translation() {
    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
    else
        lang_code="$DEFAULT_LANGUAGE"
        debug_log "WARN" "display_detected_translation: message.ch not found, falling back to DEFAULT_LANGUAGE ($DEFAULT_LANGUAGE)."
    fi

    local source_lang="$DEFAULT_LANGUAGE"
    local source_db_path="$MESSAGE_DB"
    # --- Modified: Use flat structure for target DB path ---
    local target_db_path="${BASE_DIR}/message_${lang_code}.db"
    # --- Modification End ---

    debug_log "DEBUG" "Displaying translation information. Source: ${source_db_path}, Target Lang: ${lang_code}, Target Path: ${target_db_path}"

    # Display source DB info
    if [ -f "$source_db_path" ]; then
        printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_ORIGINAL" "i=$(basename "$source_db_path")" "default=Original Language file: $(basename "$source_db_path")")")"
    else
         printf "%s\n" "$(color red "$(get_message "MSG_TRANSLATION_SOURCE_MISSING" "i=$(basename "$source_db_path")" "default=Original Language file MISSING: $(basename "$source_db_path")")")"
    fi

    # Display target DB info only if not default language
    if [ "$lang_code" != "$DEFAULT_LANGUAGE" ]; then
        if [ -f "$target_db_path" ]; then
            printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_CURRENT" "i=$(basename "$target_db_path")" "default=Translated Language file: $(basename "$target_db_path")")")"
        else
            printf "%s\n" "$(color yellow "$(get_message "MSG_TRANSLATION_SOURCE_MISSING" "i=$(basename "$target_db_path")" "default=Translated Language file MISSING: $(basename "$target_db_path")")")"
        fi
    fi

    # Display language codes used
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SOURCE" "i=$source_lang" "default=Original language code (assumed): ${source_lang}")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_CODE" "i=$lang_code" "default=Target language code: ${lang_code}")")"

    debug_log "DEBUG" "Translation information display completed for ${lang_code}"
}

# =========================================================
# Main Translation Entry Point - Modified
# =========================================================
# @FUNCTION: translate_main
# @DESCRIPTION: Entry point for translation. Reads target language from cache (message.ch),
#               checks/creates the translation DB using parallel processing if needed,
#               and displays translation info after completion or if DB exists.
#               Uses flat path structure: ${BASE_DIR}/message_xx.db
# @PARAM: None
# @RETURN: 0 on success/no translation needed, 1 on critical error,
#          propagates create_language_db exit code (2 for partial).
translate_main() {
    # --- Initialization ---
    # (Initialization part remains the same)
    if type detect_wget_capabilities >/dev/null 2>&1; then
        WGET_CAPABILITY_DETECTED=$(detect_wget_capabilities)
        debug_log "DEBUG" "translate_main: Wget capability detected: ${WGET_CAPABILITY_DETECTED}"
    else
        debug_log "DEBUG" "translate_main: detect_wget_capabilities function not found."
        WGET_CAPABILITY_DETECTED="basic" # Default or keep empty? Assuming basic for now.
    fi
    debug_log "DEBUG" "translate_main: Initialization part complete."

    # --- Translation Control Logic ---
    local lang_code=""
    local is_default_lang="false"
    local target_db="" # Path to the target DB file
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
        debug_log "DEBUG" "translate_main: Target language is the default language (${lang_code}). No translation needed."
        # Optionally display info even for default language? Currently returns directly.
        # display_detected_translation # Uncomment if info display is desired for default lang too
        return 0
    fi

    debug_log "DEBUG" "translate_main: Target language (${lang_code}) requires processing."

    # --- Modified: Use flat structure for target DB path ---
    # 3. Check if target DB exists
    target_db="${BASE_DIR}/message_${lang_code}.db"
    # --- Modification End ---
    debug_log "DEBUG" "translate_main: Checking for existing target DB: ${target_db}"

    if [ -f "$target_db" ]; then
         debug_log "DEBUG" "translate_main: Target DB '${target_db}' exists for '${lang_code}'. Assuming complete."
         display_detected_translation # Display info if DB exists
         return 0 # Early return: DB exists
    else
        debug_log "DEBUG" "translate_main: Target DB '${target_db}' does not exist. Proceeding with creation."
    fi

    # --- Proceed with Translation Process ---
    # 4. Find the first available translation function...
    local selected_func=""
    local func_name=""
    if [ -z "$AI_TRANSLATION_FUNCTIONS" ]; then
         debug_log "DEBUG" "translate_main: AI_TRANSLATION_FUNCTIONS global variable is not set or empty."
         printf "%s\n" "$(color yellow "$(get_message "MSG_ERR_NO_TRANS_FUNC_VAR" "default=Error: AI_TRANSLATION_FUNCTIONS not set.")")"
         return 1
    fi
    # POSIX-compliant loop through space-separated list
    set -f; IFS=' '; set -- $AI_TRANSLATION_FUNCTIONS; set +f; IFS=$' \t\n'
    for func_name in "$@"; do
        if type "$func_name" >/dev/null 2>&1; then
            selected_func="$func_name"
            break
        fi
    done
    if [ -z "$selected_func" ]; then
        debug_log "DEBUG" "translate_main: No available translation functions found from list: '${AI_TRANSLATION_FUNCTIONS}'."
        printf "%s\n" "$(color yellow "$(get_message "MSG_ERR_NO_TRANS_FUNC_AVAIL" "list=$AI_TRANSLATION_FUNCTIONS" "default=Error: No available translation functions found from list: ${AI_TRANSLATION_FUNCTIONS}")")"
        return 1
    fi
    debug_log "DEBUG" "translate_main: Selected translation function: ${selected_func}"

    # 5. Determine Domain Name for display...
    local domain_name=""
    case "$selected_func" in
        "translate_with_google") domain_name="translate.googleapis.com" ;;
        "translate_with_lingva") domain_name="lingva.ml" ;;
        *) domain_name="$selected_func" ;; # Fallback to function name
    esac
    debug_log "DEBUG" "translate_main: Using Domain '${domain_name}' for display..."

    # 6. Call create_language_db
    debug_log "DEBUG" "translate_main: Calling create_language_db for language '${lang_code}' using function '${selected_func}'"
    create_language_db "$selected_func" "" "$domain_name" "$lang_code"
    db_creation_result=$?
    debug_log "DEBUG" "translate_main: create_language_db finished with status: ${db_creation_result}"

    # 7. Handle Result and Display Info ONLY on Success or Partial Success
    if [ "$db_creation_result" -eq 0 ] || [ "$db_creation_result" -eq 2 ]; then
        debug_log "DEBUG" "translate_main: Language DB creation successful or partially successful for ${lang_code}."
        display_detected_translation # Display info after creation
        return "$db_creation_result" # Return 0 or 2
    else
        debug_log "DEBUG" "translate_main: Language DB creation failed for ${lang_code} (Exit status: ${db_creation_result})."
        # Avoid duplicate message if base DB was missing (handled in create_language_db)
        if [ "$db_creation_result" -ne 1 ]; then
             printf "%s\n" "$(color yellow "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code" "default=Error: Translation process failed for ${lang_code}.")")"
        fi
        return "$db_creation_result" # Propagate error code (likely 1)
    fi
}
