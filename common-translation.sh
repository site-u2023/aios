#!/bin/sh

SCRIPT_VERSION="2025-04-18-00-03"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-29
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
CURRENT_API=""

# API設定追加
GOOGLE_TRANSLATE_URL="${GOOGLE_TRANSLATE_URL:-https://translate.googleapis.com/translate_a/single}"
LINGVA_URL="${LINGVA_URL:-https://lingva.ml/api/v1}"
# API_LIST="${API_LIST:-lingva}"
API_LIST="${API_LIST:-google}"
WGET_CAPABILITY_DETECTED="" # wget capabilities (basic, https_only, full) - Initialized by init_translation

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# 言語コード取得（APIのため）
get_api_lang_code() {
    # message.chからの言語コードを使用
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        local api_lang=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "Using language code from message.ch: ${api_lang}"
        printf "%s\n" "$api_lang"
        return 0
    fi
    
    # message.chがない場合はデフォルトで英語
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
    
    # ネットワーク接続状態を一度だけ確認
    [ ! -f "$ip_check_file" ] && check_network_connectivity
    
    # ネットワーク接続状態に基づいてwgetオプションを設定
    if [ -f "$ip_check_file" ]; then
        local network_type=$(cat "$ip_check_file")
        
        case "$network_type" in
            "v4") wget_options="-4" ;;
            "v6") wget_options="-6" ;;
            "v4v6") wget_options="-4" ;;
        esac
    fi
    
    # URLエンコード
    local encoded_text=$(urlencode "$text")
    local temp_file="${TRANSLATION_CACHE_DIR}/lingva_response.tmp"
    
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null
    
    # リトライループ
    while [ $retry_count -le $API_MAX_RETRIES ]; do
        [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ] && \
            wget_options=$([ "$wget_options" = "-4" ] && echo "-6" || echo "-4")
        
        # APIリクエスト送信
        $BASE_WGET $wget_options -T $API_TIMEOUT --tries=1 -O "$temp_file" \
             --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
             "${LINGVA_URL}/$source_lang/$target_lang/$encoded_text" 2>/dev/null
        
        # レスポンスチェック
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
    done
    
    return 1
}

# 翻訳試行を行うヘルパー関数 (translate_with_google から呼ばれる)
# $1: wget_capability ("full" or "basic")
# $2: current_wget_options ("-4", "-6", or "")
# $3: api_url
# $4: temp_file path
# $5: key (for debug logging)
# 出力: 成功時は翻訳結果を標準出力、失敗時は空文字列を出力
# 戻り値: 成功時は0、失敗時は1
attempt_google_translation() {
    local wget_capability="$1"
    local current_wget_options="$2"
    local api_url="$3"
    local temp_file="$4"
    local key="$5"
    local wget_cmd_base=""
    local wget_status=1
    local translated_text="" # Renamed from 'translated'

    debug_log "DEBUG" "[Attempt] Executing attempt for key: ${key}"
    debug_log "DEBUG" "[Attempt] Capability: ${wget_capability}, Options: ${current_wget_options}"

    # wgetコマンドの基本部分を決定 (-L の有無)
    case "$wget_capability" in
        "full")
            wget_cmd_base="wget --no-check-certificate ${current_wget_options} -L -T ${API_TIMEOUT} -q -O"
            debug_log "DEBUG" "[Attempt] Using wget with -L"
            ;;
        *) # basic, https_only, etc.
            wget_cmd_base="wget --no-check-certificate ${current_wget_options} -T ${API_TIMEOUT} -q -O"
            debug_log "DEBUG" "[Attempt] Using wget without -L"
            ;;
    esac

    # wgetコマンドの実行
    debug_log "DEBUG" "[Attempt] Executing: ${wget_cmd_base} \"${temp_file}\" --user-agent=\"Mozilla/5.0\" \"${api_url}\""
    ${wget_cmd_base} "${temp_file}" --user-agent="Mozilla/5.0" "${api_url}" 2>/dev/null
    wget_status=$?
    debug_log "DEBUG" "[Attempt] wget exit status: ${wget_status}"

    # レスポンスチェックと結果処理 (OK_translate_with_google と同等の sed ロジック)
    if [ $wget_status -eq 0 ] && [ -s "$temp_file" ]; then
        # 柔軟なレスポンスチェック（grepでJSON配列の開始を確認）
        if grep -q '\[' "$temp_file"; then
            # sedで翻訳テキスト抽出とエスケープ解除
            translated_text=$(sed 's/\[\[\["//; s/",".*//; s/\\u003d/=/g; s/\\u003c/</g; s/\\u003e/>/g; s/\\u0026/\&/g; s/\\"/"/g; s/\\n/\n/g; s/\\r//g' "$temp_file")

            if [ -n "$translated_text" ] && [ "$translated_text" != "null" ]; then
                debug_log "DEBUG" "[Attempt] Translation successful for key '${key}'"
                printf "%s\n" "$translated_text" # 成功時、結果を標準出力へ
                return 0 # 成功
            else
                debug_log "WARNING" "[Attempt] Translation extraction failed or empty/null result for key '${key}'. Response content:"
                debug_log "WARNING" "$(cat "$temp_file")"
                return 1 # 失敗 (抽出エラー)
            fi
        else
            debug_log "WARNING" "[Attempt] Unexpected response format (no '[' found) for key '${key}'. Response content:"
            debug_log "WARNING" "$(cat "$temp_file")"
            return 1 # 失敗 (形式エラー)
        fi
    else
        debug_log "WARNING" "[Attempt] wget failed (status: ${wget_status}) or temp file empty for key '${key}'."
        return 1 # 失敗 (wgetエラー)
    fi
}

# Google Translate APIを使用してテキストを翻訳する関数（リトライ、IPバージョン切り替え、wget能力対応、ヘルパー関数使用）
# $1: 翻訳対象のキー (デバッグ用)
# $2: ターゲット言語コード (例: "ja")
# $3: ソース言語コード (例: "en")
# $4: Google Apps Script API URL (または Google Translate API URL)
# 出力: 成功時は翻訳結果を標準出力、失敗時は空文字列を出力し、ステータスコード1を返す
translate_with_google() {
    local key="$1"
    local target_lang="$2"
    local source_lang="$3"
    local api_url="$4" # This could be Apps Script URL or direct Google Translate URL

    debug_log "DEBUG" "translate_with_google called for key: '${key}', target: ${target_lang}, source: ${source_lang}"
    debug_log "DEBUG" "Using API URL: ${api_url}"

    # ネットワーク接続タイプを取得
    local network_type=""
    if [ -f "${CACHE_DIR}/network.ch" ]; then
        network_type=$(cat "${CACHE_DIR}/network.ch")
    fi
    debug_log "DEBUG" "Network type from cache: ${network_type}"

    # wgetオプションの初期化 (-4 or -6 or empty)
    local wget_options=""
    if [ "$network_type" = "v4v6" ] || [ "$network_type" = "v4" ]; then
        wget_options="-4"
    elif [ "$network_type" = "v6" ]; then
        wget_options="-6"
    fi
    debug_log "DEBUG" "Initial wget options: ${wget_options}"

    # リトライ時にIPバージョンを切り替えるかどうかを事前に判定
    local can_alternate_ip=false
    if [ "$network_type" = "v4v6" ]; then
        can_alternate_ip=true
        debug_log "DEBUG" "IP alternation enabled for v4v6 network"
    fi

    # 一時ファイルの準備 (TMP_DIR を使用)
    local TMP_DIR="${TMP_DIR:-/tmp}"
    local temp_file="${TMP_DIR}/translation_result.$$"
    mkdir -p "$TMP_DIR" 2>/dev/null
    trap 'rm -f "$temp_file"' EXIT INT TERM HUP

    # リトライカウンター
    local retry_count=0
    local attempt_status=1
    local translated_text=""

    # リトライループ
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        debug_log "DEBUG" "Translation attempt ${retry_count} for key: ${key}"

        # v4v6の場合のみネットワークタイプを切り替え (リトライ時)
        if [ $retry_count -gt 0 ] && [ "$can_alternate_ip" = true ]; then
            case "$wget_options" in
                *-4*) wget_options="-6" ;;
                *)    wget_options="-4" ;;
            esac
            debug_log "DEBUG" "Alternating IP, retrying with wget option: $wget_options"
        fi

        # ヘルパー関数を呼び出して翻訳を試行し、結果とステータスを取得
        # WGET_CAPABILITY_DETECTED は init_translation で設定されている想定
        translated_text=$(attempt_google_translation "$WGET_CAPABILITY_DETECTED" "$wget_options" "$api_url" "$temp_file" "$key")
        attempt_status=$?

        # 試行結果を確認
        if [ $attempt_status -eq 0 ]; then
            # ヘルパー関数が成功 (戻り値 0)
            debug_log "DEBUG" "Translation successful on attempt ${retry_count} for key '${key}'"
            # ヘルパー関数が標準出力した翻訳結果をそのまま出力
            printf "%s\n" "$translated_text"
            # rm -f "$temp_file" # Trap will handle cleanup
            trap - EXIT INT TERM HUP # Remove trap before successful return
            return 0 # 成功
        else
            # ヘルパー関数が失敗 (戻り値 1)
            debug_log "DEBUG" "Attempt ${retry_count} failed for key '${key}'"
        fi

        # リトライ準備
        retry_count=$((retry_count + 1))
        debug_log "DEBUG" "Preparing for retry ${retry_count} of ${API_MAX_RETRIES}"
        sleep 1
    done

    # 最大リトライ回数を超えた場合
    debug_log "ERROR" "Translation failed for key '${key}' after ${API_MAX_RETRIES} retries."
    # rm -f "$temp_file" # Trap will handle cleanup
    # trap - EXIT INT TERM HUP # Trap will be removed on exit anyway
    return 1
}

# Google翻訳APIを使用した翻訳関数 (高効率版:54秒)
OK_translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    local network_type=""
    local temp_file="${TRANSLATION_CACHE_DIR}/google_response.tmp"
    local api_url=""

    # wgetの機能を検出（キャッシュ対応版） - この行を削除
    # local wget_capability=$(detect_wget_capabilities) # Removed: Use global WGET_CAPABILITY_DETECTED instead

    # 必要なディレクトリを確保
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null

    # ネットワーク接続状態を確認
    # Ensure check_network_connectivity is defined (likely in common-system.sh) and loaded
    if [ ! -f "$ip_check_file" ]; then
         if type check_network_connectivity >/dev/null 2>&1; then
            check_network_connectivity
         else
             debug_log "ERROR" "check_network_connectivity function not found."
             # Decide how to handle missing network check function
         fi
    fi
    network_type=$(cat "$ip_check_file" 2>/dev/null || echo "v4") # Default to v4 if file missing

    # ネットワークタイプに基づいてwgetオプションを設定
    case "$network_type" in
        "v4") wget_options="-4" ;;
        "v6") wget_options="-6" ;;
        *) wget_options="" ;; # Includes v4v6, let wget decide or alternate later
    esac

    # URLエンコードとAPI URLを事前に構築
    local encoded_text=$(urlencode "$text")
    api_url="https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}"

    # リトライループ
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        # v4v6の場合のみネットワークタイプを切り替え
        if [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ]; then
            # Alternate between -4 and -6 for v4v6
             if echo "$wget_options" | grep -q -- "-4"; then
                 wget_options="-6"
             else
                 wget_options="-4"
             fi
             debug_log "DEBUG" "Retrying with wget option: $wget_options"
        fi

        # wget機能に基づいてコマンドを構築 (グローバル変数 WGET_CAPABILITY_DETECTED を使用)
        case "$WGET_CAPABILITY_DETECTED" in # Changed from _WGET_CAPABILITY
            "full")
                # 完全版wgetの場合、リダイレクトフォローを有効化
                wget --no-check-certificate $wget_options -L -T $API_TIMEOUT -q -O "$temp_file" \
                    --user-agent="Mozilla/5.0" \
                    "$api_url" 2>/dev/null
                ;;
            *) # Includes "basic", "https_only", and fallback/error cases
                # BusyBox wgetの場合、最小限のオプションのみ使用 (-L は使わない)
                wget --no-check-certificate $wget_options -T $API_TIMEOUT -q -O "$temp_file" \
                    "$api_url" 2>/dev/null
                ;;
        esac

        # レスポンス処理
        if [ -s "$temp_file" ]; then
            # 柔軟なレスポンスチェック（両方のwget出力に対応）
            if grep -q '\[' "$temp_file"; then
                # Extract translation, handle potential escapes
                local translated=$(sed 's/\[\[\["//; s/",".*//; s/\\u003d/=/g; s/\\u003c/</g; s/\\u003e/>/g; s/\\u0026/\&/g; s/\\"/"/g; s/\\n/\n/g; s/\\r//g' "$temp_file")

                if [ -n "$translated" ]; then
                    rm -f "$temp_file" 2>/dev/null
                    printf "%s\n" "$translated" # Use printf for better newline handling
                    return 0
                fi
            fi
        fi

        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        # Add a small delay before retrying? (e.g., sleep 1) - Already present below? No, it was outside the loop before. Consider adding it here.
        sleep 1 # Short sleep to potentially avoid API rate limits on retries
    done

    debug_log "DEBUG" "Google translation failed after ${API_MAX_RETRIES} attempts for text: $text" # Log the text for debugging
    return 1
}

translate_text() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local result=""
    
    # APIのマッピングを定義とドメイン抽出
    API_NAME=""
    
    case "$API_LIST" in
        google)
            # ドメイン名を抽出
            API_NAME="translate.googleapis.com"
            result=$(translate_with_google "$text" "$source_lang" "$target_lang")
            ;;
        lingva)
            # ドメイン名を抽出
            API_NAME="lingva.ml"
            result=$(translate_with_lingva "$text" "$source_lang" "$target_lang")
            ;;
        *)
            API_NAME="translate.googleapis.com"
            # デフォルトでGoogleを使用
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

create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local temp_file="${TRANSLATION_CACHE_DIR}/translation_output.tmp"
    local cleaned_translation=""
    local current_api="" # Initialize current_api
    local ip_check_file="${CACHE_DIR}/network.ch"
    
    debug_log "DEBUG" "Creating language DB for target ${target_lang} with API language code ${api_lang}"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi
    
    # DBファイル作成 (常に新規作成・上書き)
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
EOF
    
    # オンライン翻訳が無効なら翻訳せず置換するだけ
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" | sed "s/^${DEFAULT_LANGUAGE}|/${api_lang}|/" >> "$output_db"
        return 0
    fi
    
    # 翻訳処理開始
    printf "\n"
    
    # ネットワーク接続状態を確認
    if [ ! -f "$ip_check_file" ]; then
        debug_log "DEBUG" "Network status file not found, checking connectivity"
        # Ensure check_network_connectivity is defined in common-system.sh and loaded
        if type check_network_connectivity >/dev/null 2>&1; then
            check_network_connectivity
        else
            debug_log "ERROR" "check_network_connectivity function not found"
            # Proceed assuming no network or handle error appropriately
        fi
    fi
    
    # ネットワーク接続状態を取得
    local network_status=""
    if [ -f "$ip_check_file" ]; then
        network_status=$(cat "$ip_check_file")
        debug_log "DEBUG" "Network status: ${network_status}"
    else
        debug_log "DEBUG" "Could not determine network status"
    fi
    
    # --- Optimization Start ---
    # API名をAPI_LISTに基づいて直接設定
    case "$API_LIST" in
        google)
            current_api="translate.googleapis.com"
            ;;
        lingva)
            current_api="lingva.ml"
            ;;
        *)
            # デフォルトでGoogleを使用
            current_api="translate.googleapis.com"
            ;;
    esac
    
    if [ -z "$current_api" ]; then
        current_api="Translation API" # Fallback name
    fi
    debug_log "DEBUG" "Using API based on API_LIST: $current_api"
    # --- Optimization End ---

    # スピナーを開始し、使用中のAPIを表示
    # Ensure start_spinner is defined in common-color.sh or similar and loaded
    if type start_spinner >/dev/null 2>&1; then
        start_spinner "$(color blue "Currently translating: $current_api")"
    else
        debug_log "WARNING" "start_spinner function not found, spinner not started"
    fi
    
    # 言語エントリを抽出して翻訳ループ
    grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出 (シェル組み込み文字列操作を使用)
        local line_content=${line#*|} # "en|" の部分を除去
        local key=${line_content%%=*}   # 最初の "=" より前の部分をキーとして取得
        local value=${line_content#*=}  # 最初の "=" より後の部分を値として取得
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            # キャッシュキー生成
            local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
            
            # キャッシュを確認
            if [ -f "$cache_file" ]; then
                local translated=$(cat "$cache_file")
                # APIから取得した言語コードを使用
                printf "%s|%s=%s\n" "$api_lang" "$key" "$translated" >> "$output_db"
                continue # 次の行へ
            fi
            
            # ネットワーク接続確認と翻訳
            if [ -n "$network_status" ] && [ "$network_status" != "" ]; then
                # ここで実際に翻訳APIを呼び出す
                cleaned_translation=$(translate_text "$value" "$DEFAULT_LANGUAGE" "$api_lang")
                
                # 翻訳結果処理
                if [ -n "$cleaned_translation" ]; then
                    # 基本的なエスケープシーケンスの処理
                    local decoded="$cleaned_translation"
                    
                    # キャッシュに保存
                    mkdir -p "$(dirname "$cache_file")"
                    printf "%s\n" "$decoded" > "$cache_file"
                    
                    # APIから取得した言語コードを使用してDBに追加
                    printf "%s|%s=%s\n" "$api_lang" "$key" "$decoded" >> "$output_db"
                else
                    # 翻訳失敗時は原文をそのまま使用
                    printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
                    debug_log "DEBUG" "Translation failed for key: ${key}, using original text" 
                fi
            else
                # ネットワーク接続がない場合は原文を使用
                printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
                debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
            fi
        fi
    done
    
    # スピナー停止
    # Ensure stop_spinner is defined and loaded
    if type stop_spinner >/dev/null 2>&1; then
        stop_spinner "Language file created successfully" "success"
    else
        debug_log "INFO" "Language file creation process finished (spinner function not found)"
        # Optionally print the success message directly if spinner isn't available
        printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATION_SUCCESS" "default=Language file created successfully")")"
    fi
    
    # 翻訳処理終了
    debug_log "DEBUG" "Language DB creation completed for ${api_lang}"
    return 0
}

# 翻訳情報を表示する関数
display_detected_translation() {
    # 引数の取得
    local show_success_message="${1:-false}"  # 成功メッセージ表示フラグ
    
    # 言語コードの取得
    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
    else
        lang_code="$DEFAULT_LANGUAGE"
    fi
    
    local source_lang="$DEFAULT_LANGUAGE"  # ソース言語
    local source_db="message_${source_lang}.db"
    local target_db="message_${lang_code}.db"
    
    debug_log "DEBUG" "Displaying translation information for language code: ${lang_code}"
    
    # 同じ言語でDB作成をスキップする場合もチェック
    if [ "$source_lang" = "$lang_code" ] && [ "$source_db" = "$target_db" ]; then
        debug_log "DEBUG" "Source and target languages are identical: ${lang_code}"
    fi
    
    # 成功メッセージの表示（オプション）
    if [ "$show_success_message" = "true" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATION_SUCCESS")")"
    fi
    
    # 翻訳ソース情報表示
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_ORIGINAL" "i=$source_db")")"
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_CURRENT" "i=$target_db")")"
    
    # 言語コード情報表示
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SOURCE" "i=$source_lang")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_CODE" "i=$lang_code")")"
    
    debug_log "DEBUG" "Translation information display completed for ${lang_code}"
}

# 言語翻訳処理
process_language_translation() {
    # 言語コードの取得
    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "Processing translation for language code: ${lang_code}"
    else
        debug_log "DEBUG" "No language code found in message.ch, using default"
        lang_code="$DEFAULT_LANGUAGE"
    fi

    # デフォルト言語以外の場合のみ翻訳DBを作成
    if [ "$lang_code" != "$DEFAULT_LANGUAGE" ]; then
        debug_log "DEBUG" "Target language (${lang_code}) is different from default (${DEFAULT_LANGUAGE}), creating DB."
        # 翻訳DBを作成
        create_language_db "$lang_code"

        # 翻訳情報表示（成功メッセージなし）
        display_detected_translation "false"
    else
        # デフォルト言語の場合はDB作成をスキップ
        debug_log "DEBUG" "Skipping DB creation for default language: ${lang_code}"

        # 表示は1回だけ行う（静的フラグを使用）
        if [ "${DEFAULT_LANG_DISPLAYED:-false}" = "false" ]; then
            debug_log "DEBUG" "Displaying information for default language once"
            display_detected_translation "false"
            # 表示済みフラグを設定（POSIX準拠）
            DEFAULT_LANG_DISPLAYED=true
        else
            debug_log "DEBUG" "Default language info already displayed, skipping"
        fi
    fi

    printf "\n"

    return 0
}

# 初期化関数
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # --- Optimization Start ---
    # Detect wget capabilities once and store in global variable
    # Ensure detect_wget_capabilities is defined (likely in common-system.sh) and loaded
    if type detect_wget_capabilities >/dev/null 2>&1; then
        WGET_CAPABILITY_DETECTED=$(detect_wget_capabilities) # Changed variable name
        debug_log "DEBUG" "Wget capability set globally: ${WGET_CAPABILITY_DETECTED}" # Changed variable name
    else
        debug_log "ERROR" "detect_wget_capabilities function not found. Wget capability detection skipped."
        WGET_CAPABILITY_DETECTED="basic" # Fallback to basic if function not found, Changed variable name
    fi
    # --- Optimization End ---
    
    # 言語翻訳処理を実行
    process_language_translation
    
    debug_log "DEBUG" "Translation module initialized with language processing"
}
# スクリプト初期化（自動実行）
# init_translation
