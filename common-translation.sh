#!/bin/sh

# SCRIPT_VERSION="2025-04-23-12-47" # Original version marker - Updated below
SCRIPT_VERSION="2025-04-24-00-06" # Updated version based on last interaction time

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

#----------------------------------------------------------------------------------------------------

# 翻訳DB作成関数 (責務: DBファイル作成、AIP関数呼び出し、時間計測) - バッチ処理版
# @param $1: aip_function_name (string) - The name of the AIP function to call (e.g., "translate_with_google")
# @param $2: api_endpoint_url (string) - The base API endpoint URL (Currently unused)
# @param $3: domain_name (string) - The domain name for basic progress display (e.g., "translate.googleapis.com")
# @param $4: target_lang_code (string) - The target language code (e.g., "ja")
# @return: 0 on success, 1 on base DB not found, 2 if any translation fails or mismatch occurs (writes original text for failures)
create_language_db() {
    local aip_function_name="$1"
    local api_endpoint_url="$2" # Unused
    local domain_name="$3"      # Used for simple message
    local target_lang_code="$4"

    # --- バッチサイズ設定 (ここで変更可能) ---
    local readonly BATCH_SIZE= # Process 2 lines at a time
    # ----------------------------------

    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local output_db="${BASE_DIR}/message_${target_lang_code}.db"
    local overall_success=0 # Assume success initially, 2 indicates at least one translation failed/mismatched
    # --- 時間計測用変数 ---
    local start_time=""
    local end_time=""
    local elapsed_seconds=""
    # ---------------------
    # --- Batch processing variables ---
    local batch_keys=""
    local batch_values=""
    local line_count=0
    # ----------------------------------

    # printf "DEBUG: Creating language DB (Batch Mode, Size=%s) for target '%s' using function '%s' with domain '%s'\n" "$BATCH_SIZE" "$target_lang_code" "$aip_function_name" "$domain_name" >&2 # Basic Debug

    if [ ! -f "$base_db" ]; then
        # printf "DEBUG: Base message DB not found: %s. Cannot create target DB.\n" "$base_db" >&2 # Basic Debug
        printf "ERROR: Translation process failed: Base DB not found at %s\n" "$base_db" >&2
        return 1
    fi

    # --- 計測開始 ---
    start_time=$(date +%s)
    # ---------------

    # Basic progress message (instead of spinner)
    printf "INFO: Currently translating: %s (Batch Size: %s)...\n" "$domain_name" "$BATCH_SIZE"

    # Create/overwrite the output DB with the header
    # POSIX compliant way to write multiple lines
    {
        printf "SCRIPT_VERSION=\"%s\"\n" "$(date +%Y.%m.%d-%H-%M)"
        printf "# Translation generated using: %s (Batch Size: %s)\n" "$aip_function_name" "$BATCH_SIZE"
        printf "# Target Language: %s\n" "$target_lang_code"
    } > "$output_db"

    # Loop through the base DB
    while IFS= read -r line; do
        # Skip comments and empty lines
        case "$line" in \#*|"") continue ;; esac
        # Process only lines for the default language
        case "$line" in "${DEFAULT_LANGUAGE}|"*) ;; *) continue ;; esac

        # Extract key and value
        local line_content=${line#*|}
        local key=${line_content%%=*}
        local value=${line_content#*=}

        # Skip if key or value extraction failed
        if [ -z "$key" ]; then # Value can be empty, key cannot
            # printf "DEBUG: Skipping malformed line (empty key): %s\n" "$line" >&2 # Basic Debug
            continue
        fi

        # Append key and value to batch variables (newline separated)
        if [ -z "$batch_keys" ]; then
            batch_keys="$key"
            batch_values="$value"
        else
            batch_keys=$(printf "%s\n%s" "$batch_keys" "$key")
            batch_values=$(printf "%s\n%s" "$batch_values" "$value")
        fi
        line_count=$((line_count + 1))

        # Process batch if it reaches BATCH_SIZE
        if [ "$line_count" -ge "$BATCH_SIZE" ]; then
            # printf "DEBUG: Processing batch of %s lines...\n" "$line_count" >&2 # Basic Debug
            process_translation_batch "$aip_function_name" "$target_lang_code" "$batch_keys" "$batch_values" "$output_db"
            local batch_result=$?
            if [ "$batch_result" -ne 0 ]; then
                overall_success=2 # Mark overall process as partially failed
                # printf "DEBUG: Batch processing reported failure/mismatch (Status: %s). Overall status set to partial failure.\n" "$batch_result" >&2 # Basic Debug
            fi
            # Reset batch variables
            batch_keys=""
            batch_values=""
            line_count=0
        fi

    done < "$base_db"

    # Process any remaining lines in the last batch
    if [ "$line_count" -gt 0 ]; then
        # printf "DEBUG: Processing final batch of %s lines...\n" "$line_count" >&2 # Basic Debug
        process_translation_batch "$aip_function_name" "$target_lang_code" "$batch_keys" "$batch_values" "$output_db"
        local batch_result=$?
        if [ "$batch_result" -ne 0 ]; then
            overall_success=2
             # printf "DEBUG: Final batch processing reported failure/mismatch (Status: %s). Overall status set to partial failure.\n" "$batch_result" >&2 # Basic Debug
        fi
    fi

    # --- 計測終了 & 計算 ---
    end_time=$(date +%s)
    elapsed_seconds=$((end_time - start_time))
    # ----------------------

    # Final status message (instead of spinner stop)
    if [ "$overall_success" -eq 0 ]; then
        printf "INFO: Language file created successfully (%s seconds)\n" "$elapsed_seconds"
    else
        printf "WARN: Translation partially completed (%s seconds). Some entries might use original text.\n" "$elapsed_seconds"
    fi

    # Add the completion marker key at the end of the file
    local marker_key="AIOS_TRANSLATION_COMPLETE_MARKER"
    printf "%s|%s=%s\n" "$target_lang_code" "$marker_key" "true" >> "$output_db"
    # printf "DEBUG: Completion marker added to %s\n" "$output_db" >&2 # Basic Debug

    # printf "DEBUG: Language DB creation process completed for %s\n" "$target_lang_code" >&2 # Basic Debug
    return "$overall_success" # Return 0 for success, 2 for partial failure/mismatch
}

# Processes a batch of keys and values for translation
# @param $1: aip_function_name (string) - Translation function name
# @param $2: target_lang_code (string) - Target language code
# @param $3: batch_keys (string) - Newline-separated keys
# @param $4: batch_values (string) - Newline-separated values to translate
# @param $5: output_db (string) - Path to the output database file
# @stdout: None (writes directly to output_db)
# @return: 0 if all lines in batch translated successfully and counts match,
#          2 if any translation failed OR line counts mismatch (uses original text)
process_translation_batch() {
    local aip_function_name="$1"
    local target_lang_code="$2"
    local batch_keys="$3"
    local batch_values="$4"
    local output_db="$5"

    # --- DEBUG: Log input parameters ---
    printf "DEBUG: [process_translation_batch] START\n" >&2
    printf "DEBUG:   aip_function_name: %s\n" "$aip_function_name" >&2
    printf "DEBUG:   target_lang_code: %s\n" "$target_lang_code" >&2
    printf "DEBUG:   output_db: %s\n" "$output_db" >&2
    printf "DEBUG:   batch_keys:\n<<<\n%s\n>>>\n" "$batch_keys" >&2
    printf "DEBUG:   batch_values:\n<<<\n%s\n>>>\n" "$batch_values" >&2
    # --- End DEBUG ---

    local translated_batch=""
    local exit_code=1 # Default to failure
    local awk_result=""
    local final_batch_status=2 # Default to failure/mismatch

    # --- Call AIP function for the entire batch ---
    if [ -n "$batch_values" ]; then
        printf "DEBUG: [process_translation_batch] Calling %s for batch...\n" "$aip_function_name" >&2
        translated_batch=$("$aip_function_name" "$batch_values" "$target_lang_code")
        exit_code=$?
        printf "DEBUG: [process_translation_batch] %s exited with %s\n" "$aip_function_name" "$exit_code" >&2
        printf "DEBUG: [process_translation_batch] translated_batch content:\n<<<\n%s\n>>>\n" "$translated_batch" >&2
    else
        printf "DEBUG: [process_translation_batch] Empty batch_values, skipping API call.\n" >&2
        return 0 # Empty batch, nothing to do
    fi

    # --- Process the result using awk (Revised for robustness) ---
    printf "DEBUG: [process_translation_batch] Preparing to call awk...\n" >&2
    awk_result=$(awk -v t_lang="$target_lang_code" \
                     -v keys="$batch_keys" \
                     -v originals="$batch_values" \
                     -v translated="$translated_batch" \
                     -v trans_ok="$exit_code" \
    'BEGIN {
        FS = "\n"; RS = "\n"; OFS = "\n"; # Set field/record separators
        # DEBUG: Print awk input variables
        printf "AWK_DEBUG: START\n" > "/dev/stderr";
        printf "AWK_DEBUG:   t_lang=%s\n", t_lang > "/dev/stderr";
        printf "AWK_DEBUG:   trans_ok=%s\n", trans_ok > "/dev/stderr";
        printf "AWK_DEBUG:   keys:\n<<<\n%s\n>>>\n", keys > "/dev/stderr";
        printf "AWK_DEBUG:   originals:\n<<<\n%s\n>>>\n", originals > "/dev/stderr";
        printf "AWK_DEBUG:   translated:\n<<<\n%s\n>>>\n", translated > "/dev/stderr";

        # Split inputs, handle potential empty trailing lines from split in some awk versions if needed
        num_keys = split(keys, key_arr);
        num_originals = split(originals, orig_arr);
        num_translated = 0; # Initialize
        if (translated != "") {
             num_translated = split(translated, trans_arr);
        }

        printf "AWK_DEBUG:   num_keys=%d, num_originals=%d, num_translated=%d\n", num_keys, num_originals, num_translated > "/dev/stderr";

        batch_status = 0; # Assume success initially
        use_translated = 0; # Flag to indicate if translated text should be used

        # Check if translation API call was successful AND returned something AND counts match
        if (trans_ok == 0 && translated != "" && num_translated > 0) {
            if (num_translated == num_keys) {
                use_translated = 1;
                printf "AWK_DEBUG: Translation OK and line counts match (%d). Setting use_translated=1.\n", num_keys > "/dev/stderr";
            } else {
                printf "AWK_DEBUG: Line count mismatch (Keys: %d, Translated: %d). Using original text.\n", num_keys, num_translated > "/dev/stderr";
                batch_status = 2; # Mark as partial failure due to mismatch
            }
        } else {
            # Translation API failed, returned empty, or split resulted in zero lines
            if (trans_ok != 0) { printf "AWK_DEBUG: Translation function failed (code %d). Using original text.\n", trans_ok > "/dev/stderr"; }
            if (translated == "") { printf "AWK_DEBUG: Translation function returned empty. Using original text.\n" > "/dev/stderr"; }
            if (num_translated == 0 && translated != "") { printf "AWK_DEBUG: split(translated) resulted in 0 lines. Using original text.\n" > "/dev/stderr"; }
            batch_status = 2; # Mark as partial failure
        }

        # Loop through keys and print either translated or original text WITH BOUNDS CHECKING
        for (i = 1; i <= num_keys; ++i) {
            # Ensure the key exists and is within bounds (already checked by loop condition i <= num_keys)
            if (key_arr[i] != "") {
                 printf "AWK_DEBUG: Processing index %d, key: %s\n", i, key_arr[i] > "/dev/stderr";
                 # Check if we should use translated text AND if the index is valid for trans_arr
                 if (use_translated == 1 && i <= num_translated && trans_arr[i] != "") {
                     # Use translated text if available and flag is set and index valid
                     printf "AWK_DEBUG:   Using translated: %s\n", trans_arr[i] > "/dev/stderr";
                     printf "%s|%s=%s\n", t_lang, key_arr[i], trans_arr[i];
                 } else {
                     # Use original text if translation failed, mismatched, index invalid, or specific translated line is empty
                     # Check if index is valid for orig_arr before accessing
                     if (i <= num_originals) {
                         printf "AWK_DEBUG:   Using original: %s (Reason: use_translated=%d, i=%d<=num_translated=%d check failed OR trans_arr[i] empty OR i=%d<=num_originals=%d check passed)\n", orig_arr[i], use_translated, i, num_translated, i, num_originals > "/dev/stderr";
                         printf "%s|%s=%s\n", t_lang, key_arr[i], orig_arr[i];
                     } else {
                         # This case should ideally not happen if num_keys == num_originals
                         printf "AWK_DEBUG:   ERROR: Index %d out of bounds for originals array (size %d)! Skipping key %s.\n", i, num_originals, key_arr[i] > "/dev/stderr";
                         batch_status = 2; # Mark failure
                     }

                     # If we intended to use translated but fell back, ensure status is failure
                     if (use_translated == 1) {
                          if (i > num_translated) { printf "AWK_DEBUG:   Fell back because index %d > num_translated %d\n", i, num_translated > "/dev/stderr"; }
                          else if (trans_arr[i] == "") { printf "AWK_DEBUG:   Fell back because translated line %d was empty.\n", i > "/dev/stderr"; }
                          batch_status = 2;
                     }
                 }
            } else {
                 printf "AWK_DEBUG: Skipping empty key at index %d.\n", i > "/dev/stderr";
            }
        }
        # Print the final batch status
        printf "AWK_DEBUG: Final batch_status=%d\n", batch_status > "/dev/stderr";
        print batch_status;
        printf "AWK_DEBUG: END\n" > "/dev/stderr";
    }')
    # --- End of awk script ---

    # --- DEBUG: Log awk result ---
    printf "DEBUG: [process_translation_batch] awk script finished.\n" >&2
    printf "DEBUG: [process_translation_batch] awk_result:\n<<<\n%s\n>>>\n" "$awk_result" >&2
    # --- End DEBUG ---

    # Extract the batch status code (last line of awk_result)
    final_batch_status=$(printf "%s\n" "$awk_result" | tail -n 1)
    # Extract the lines to be written to the DB (all lines except the last)
    local lines_to_write=$(printf "%s\n" "$awk_result" | head -n -1)

    # Append the processed lines to the output DB
    if [ -n "$lines_to_write" ]; then
        printf "DEBUG: [process_translation_batch] Appending lines to %s:\n<<<\n%s\n>>>\n" "$output_db" "$lines_to_write" >&2
        printf "%s\n" "$lines_to_write" >> "$output_db"
    else
        printf "DEBUG: [process_translation_batch] No lines to append to DB.\n" >&2
    fi

    # Return the status code from awk
    printf "DEBUG: [process_translation_batch] Returning final_batch_status: %s\n" "$final_batch_status" >&2
    if [ "$final_batch_status" = "2" ]; then
        return 2
    elif [ "$final_batch_status" = "0" ]; then
        return 0
    else
        # Should not happen if awk script is correct, but return failure just in case
        printf "DEBUG: [process_translation_batch] WARNING: Unexpected final_batch_status '%s'. Returning 2.\n" "$final_batch_status" >&2
        return 2
    fi
}

# URL安全エンコード関数
# @param $1: string - The string to encode.
# @stdout: URL-encoded string.
urlencode() {
    # Removed 'local' keyword for POSIX sh compatibility (addresses shellcheck SC3043)
    string_to_encode="$1"
    encoded=""
    # Note: hex_byte and dec_code are primarily used within the subshell of the command substitution below.
    hex_byte=""
    dec_code=0

    # Use command substitution $(...) to capture the entire output of the pipeline and loop
    # This avoids the subshell issue where variable changes inside the loop are lost.
    encoded=$(printf "%s" "$string_to_encode" | hexdump -v -e '1/1 "%02X "' | tr ' ' '\n' | while read -r hex_byte; do
        # Skip empty lines possibly generated by tr
        if [ -z "$hex_byte" ]; then
            continue
        fi

        # Convert hex byte to decimal using POSIX arithmetic expansion
        dec_code=$((0x${hex_byte}))

        # Check if the decimal code corresponds to a URL-safe character (a-zA-Z0-9 . _ ~ -)
        # ASCII: 0-9 (48-57), A-Z (65-90), a-z (97-122), - (45), . (46), _ (95), ~ (126)
        # Use POSIX-compliant tests: { [ cond1 ] && [ cond2 ]; } instead of [ cond1 -a cond2 ] for better portability (addresses shellcheck SC2166)
        if \
           { [ "$dec_code" -ge 48 ] && [ "$dec_code" -le 57 ]; } || \
           { [ "$dec_code" -ge 65 ] && [ "$dec_code" -le 90 ]; } || \
           { [ "$dec_code" -ge 97 ] && [ "$dec_code" -le 122 ]; } || \
           [ "$dec_code" -eq 45 ] || \
           [ "$dec_code" -eq 46 ] || \
           [ "$dec_code" -eq 95 ] || \
           [ "$dec_code" -eq 126 ]; then
            # Safe character: print the character using awk's printf %c
            # Ensure awk command is POSIX compliant
            awk -v code="$dec_code" 'BEGIN { printf "%c", code }'
        elif [ "$dec_code" -eq 32 ]; then
            # Space: print %20 using POSIX printf %% for literal %
            printf "%%20"
        else
            # Other characters (including newline): print the percent-encoded hex byte
            # Use POSIX printf %% for literal %
            printf "%%%s" "$hex_byte"
        fi
        # No assignment to 'encoded' variable inside the loop body
    done) # End of command substitution

    # Output the final captured encoded string without a trailing newline
    printf "%s" "$encoded"
}

# -------------------------------------------------------------------------------------------------------------------------------------------

# URL安全エンコード関数（seqを使わない最適化版）
# @param $1: string - The string to encode.
# @stdout: URL-encoded string.
OK_urlencode() {
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

    # --- DEBUG: Log input parameters ---
    printf "DEBUG: [translate_with_google] START\n" >&2
    printf "DEBUG:   target_lang_code: %s\n" "$target_lang_code" >&2
    printf "DEBUG:   source_text (raw input):\n<<<\n%s\n>>>\n" "$source_text" >&2
    # --- End DEBUG ---
    
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
OK_create_language_db() {
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
         printf "%s\n" "$(color red "$(get_message "MSG_ERR_NO_TRANS_FUNC_VAR")")"
         
         return 1
    fi
    set -f; set -- $AI_TRANSLATION_FUNCTIONS; set +f
    for func_name in "$@"; do
        if type "$func_name" >/dev/null 2>&1; then selected_func="$func_name"; break; fi
    done
    if [ -z "$selected_func" ]; then
        debug_log "DEBUG" "translate_main: No available translation functions found from list: '${AI_TRANSLATION_FUNCTIONS}'."
        printf "%s\n" "$(color red "$(get_message "MSG_ERR_NO_TRANS_FUNC_AVAIL" "list=$AI_TRANSLATION_FUNCTIONS")")"
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
             printf "%s\n" "$(color red "$(get_message "MSG_ERR_TRANSLATION_FAILED" "lang=$lang_code")")"
        fi
        # --- 修正 --- 失敗時は display_detected_translation を呼び出さない
        return "$db_creation_result" # Propagate error code
    fi
}
