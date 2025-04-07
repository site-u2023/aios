#!/bin/sh

SCRIPT_VERSION="2025-03-29-03-40"

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
API_LIST="google" # API_LIST="mymemory"

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

# URL安全エンコード関数
urlencode() {
    local string="$1"
    local encoded=""
    local i=0
    local c=""
    
    for i in $(seq 0 $((${#string} - 1))); do
        c="${string:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded="${encoded}$c" ;;
            " ") encoded="${encoded}%20" ;;
            *) encoded="${encoded}$(printf "%%%02X" "'$c")" ;;
        esac
    done
    
    printf "%s\n" "$encoded"
}

# フォールバック廃止版：translate_text関数
translate_text() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local result=""
    
    debug_log "DEBUG" "Starting translation using single API mode"
    
    # 設定されたAPIを取得（カンマ区切りの最初の項目のみ使用）
    local api=$(echo "$API_LIST" | cut -d ',' -f1)
    CURRENT_API="$api"
    
    debug_log "DEBUG" "Selected API: $CURRENT_API"
    
    case "$CURRENT_API" in          
        google)
            debug_log "DEBUG" "Using Google Translate API"
            result=$(translate_with_google "$text" "$source_lang" "$target_lang")
            
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                debug_log "DEBUG" "Google translation completed"
                echo "$result"
                return 0
            else
                debug_log "DEBUG" "Google translation failed"
                return 1
            fi
            ;;
            
        *)
            debug_log "DEBUG" "Unknown or invalid API specified: $CURRENT_API"
            return 1
            ;;
    esac
}

# Google APIを使用した翻訳関数（処理改善版）
translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    
    debug_log "DEBUG" "Starting Google Translate API request"
    
    # ネットワーク接続状態ファイルが存在しない場合は接続確認を実行
    if [ ! -f "$ip_check_file" ]; then
        debug_log "DEBUG" "Network connectivity status file not found, checking connectivity"
        check_network_connectivity
    fi
    
    # ネットワーク接続状態に基づいてwgetオプションを設定
    if [ -f "$ip_check_file" ]; then
        local network_type=$(cat "$ip_check_file")
        debug_log "DEBUG" "Detected network type: $network_type"
        
        case "$network_type" in
            "v4")
                wget_options="-4"  # IPv4のみ使用
                debug_log "DEBUG" "Using IPv4 for API request"
                ;;
            "v6")
                wget_options="-6"  # IPv6のみ使用
                debug_log "DEBUG" "Using IPv6 for API request"
                ;;
            "v4v6")
                # IPv4を優先使用
                wget_options="-4"
                debug_log "DEBUG" "Both available, prioritizing IPv4 for API request"
                ;;
            *)
                debug_log "DEBUG" "No network connectivity info, API request may fail"
                ;;
        esac
    fi
    
    # 長いテキスト処理の最適化
    local use_post=false
    if [ ${#text} -gt 1500 ]; then
        use_post=true
        debug_log "DEBUG" "Long text detected, using POST method"
    fi
    
    # URLエンコード
    local encoded_text=$(urlencode "$text")
    local temp_file="${TRANSLATION_CACHE_DIR}/google_response.tmp"
    
    # ディレクトリが存在しなければ作成
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null
    
    # リトライループ
    while [ $retry_count -le $API_MAX_RETRIES ]; do
        if [ $retry_count -gt 0 ]; then
            debug_log "DEBUG" "Retry attempt $retry_count for Google Translate API"
            # デュアルスタック環境でIPバージョンを切り替え
            if [ "$network_type" = "v4v6" ]; then
                if [ "$wget_options" = "-4" ]; then
                    wget_options="-6"
                    debug_log "DEBUG" "Switching to IPv6 for retry"
                else
                    wget_options="-4"
                    debug_log "DEBUG" "Switching to IPv4 for retry"
                fi
            fi
            # リトライ間隔を追加
            sleep 1
        fi
        
        debug_log "DEBUG" "Sending request to Google Translate API with options: $wget_options"
        
        # POST/GETメソッド分岐
        if [ "$use_post" = "true" ]; then
            # POSTリクエストを使用して大きなテキストを送信
            $BASE_WGET $wget_options -T $API_TIMEOUT -O "$temp_file" \
                --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
                --post-data="sl=${source_lang}&tl=${target_lang}&q=${encoded_text}" \
                "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t" 2>/dev/null
        else
            # 通常のGETリクエスト
            $BASE_WGET $wget_options -T $API_TIMEOUT -O "$temp_file" \
                --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
                "https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}" 2>/dev/null
        fi
        
        local wget_status=$?
        debug_log "DEBUG" "wget exit code: $wget_status"
        
        # レスポンスチェック
        if [ -s "$temp_file" ]; then
            if grep -q '\[\[\["' "$temp_file"; then
                local translated=$(sed 's/\[\[\["//;s/",".*//;s/\\u003d/=/g;s/\\u003c/</g;s/\\u003e/>/g;s/\\u0026/\&/g;s/\\"/"/g' "$temp_file")
                
                if [ -n "$translated" ]; then
                    debug_log "DEBUG" "Google API returned valid translation"
                    echo "$translated"
                    rm -f "$temp_file"
                    return 0
                fi
            fi
        fi
        
        debug_log "DEBUG" "Google API translation attempt failed"
        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        
        # 一定時間待機してからリトライ
        [ $retry_count -le $API_MAX_RETRIES ] && sleep 2
    done
    
    debug_log "DEBUG" "Google API translation failed after all retry attempts"
    return 1
}

# 言語データベース作成関数（高速化対応版）
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local temp_file="${TRANSLATION_CACHE_DIR}/translation_output.tmp"
    local cleaned_translation=""
    local current_api=""
    local ip_check_file="${CACHE_DIR}/network.ch"
    local total_lines=0
    local processed=0
    
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
        check_network_connectivity
    fi
    
    # ネットワーク接続状態を取得
    local network_status=""
    if [ -f "$ip_check_file" ]; then
        network_status=$(cat "$ip_check_file")
        debug_log "DEBUG" "Network status: ${network_status}"
    else
        debug_log "DEBUG" "Could not determine network status"
    fi
    
    # API_LISTから初期APIを決定
    local first_api=$(echo "$API_LIST" | cut -d',' -f1)
    case "$first_api" in
        google) current_api="Google Translate API" ;;
        *) current_api="Unknown API" ;;
    esac
    
    debug_log "DEBUG" "Initial API based on API_LIST priority: $current_api"
    
    # スピナーを開始し、使用中のAPIを表示
    start_spinner "$(color blue "Using API: $current_api")"
    
    # 全行カウント
    total_lines=$(grep "^${DEFAULT_LANGUAGE}|" "$base_db" | wc -l)
    debug_log "DEBUG" "Total entries to translate: $total_lines"
    
    # バッチ最適化1: キャッシュの事前チェック
    debug_log "DEBUG" "Pre-checking translation cache"
    local cache_hits=0
    local total_processed=0
    
    # テンポラリファイル作成（一時的な処理用）
    local cached_entries_file="${TRANSLATION_CACHE_DIR}/cached_entries.tmp"
    local uncached_entries_file="${TRANSLATION_CACHE_DIR}/uncached_entries.tmp"
    > "$cached_entries_file"
    > "$uncached_entries_file"
    
    # キャッシュ状態のプリスキャン
    grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出
        local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
        local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            # キャッシュキー生成
            local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
            
            # キャッシュを確認
            if [ -f "$cache_file" ]; then
                local translated=$(cat "$cache_file")
                # APIから取得した言語コードを使用
                printf "%s|%s=%s\n" "$api_lang" "$key" "$translated" >> "$output_db"
                printf "%s\n" "$key" >> "$cached_entries_file"
                cache_hits=$((cache_hits + 1))
            else
                # 未キャッシュ項目を記録
                printf "%s|%s\n" "$key" "$value" >> "$uncached_entries_file"
            fi
            
            total_processed=$((total_processed + 1))
            if [ $((total_processed % 10)) -eq 0 ]; then
                stop_spinner "Cached: $cache_hits/$total_processed" "info"
                start_spinner "$(color blue "Using API: $current_api")"
            fi
        fi
    done
    
    debug_log "DEBUG" "Cache pre-check complete. $cache_hits/$total_processed entries cached."
    stop_spinner "Pre-check: $cache_hits/$total_processed entries already cached" "info"
    
    # 翻訳が必要な項目数
    local uncached_count=$(wc -l < "$uncached_entries_file")
    
    if [ $uncached_count -eq 0 ]; then
        debug_log "DEBUG" "All entries found in cache, no translation needed"
        start_spinner "$(color blue "Translation completed")"
        stop_spinner "All translations found in cache" "success"
        rm -f "$cached_entries_file" "$uncached_entries_file"
        return 0
    fi
    
    # バッチ最適化2: 未キャッシュ項目を並列処理
    debug_log "DEBUG" "Processing $uncached_count uncached entries"
    start_spinner "$(color blue "Translating ${uncached_count} uncached entries")"
    
    # 処理カウンター
    local processed=0
    
    # 並列リクエスト最適化バージョン
    while IFS='|' read -r key value; do
        debug_log "DEBUG" "Translating key: $key"
        
        # 元のテキストをエスケープして安全に処理
        local safe_value=$(printf "%s" "$value" | sed 's/"/\\"/g')
        
        # ネットワーク接続確認
        if [ -n "$network_status" ] && [ "$network_status" != "" ]; then
            # APIを使用して翻訳
            local result=$(translate_with_google "$safe_value" "$DEFAULT_LANGUAGE" "$api_lang" 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                # 技術用語対応: "SPLIT"という単語が含まれている場合はそのまま使用
                if echo "$safe_value" | grep -q "SPLIT"; then
                    result="$safe_value"
                fi
                
                # キャッシュキー生成
                local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
                local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
                
                # キャッシュに保存
                mkdir -p "$(dirname "$cache_file")"
                printf "%s\n" "$result" > "$cache_file"
                
                # APIから取得した言語コードを使用してDBに追加
                printf "%s|%s=%s\n" "$api_lang" "$key" "$result" >> "$output_db"
                debug_log "DEBUG" "Translated key: $key"
            else
                # 翻訳失敗時は原文をそのまま使用
                printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
                debug_log "DEBUG" "Translation failed for key: $key, using original text"
            fi
        else
            # ネットワーク接続がない場合は原文を使用
            printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
            debug_log "DEBUG" "Network unavailable, using original text for key: $key"
        fi
        
        processed=$((processed + 1))
        
        # 進捗表示更新
        if [ $((processed % 5)) -eq 0 ] || [ $processed -eq $uncached_count ]; then
            stop_spinner "Translated: $processed/$uncached_count" "info"
            start_spinner "$(color blue "Translating: $processed/$uncached_count")"
        fi
    done < "$uncached_entries_file"
    
    # 処理完了
    stop_spinner "Translation completed: $total_processed entries processed" "success"
    
    # 一時ファイル削除
    rm -f "$cached_entries_file" "$uncached_entries_file"
    
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
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_ORIGINAL" "info=$source_db")")"
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_CURRENT" "info=$target_db")")"
    
    # 言語コード情報表示
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SOURCE" "info=$source_lang")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_CODE" "info=$lang_code")")"
    
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
    
    # 選択言語とデフォルト言語の一致フラグ
    local is_default_language=false
    if [ "$lang_code" = "$DEFAULT_LANGUAGE" ]; then
        is_default_language=true
        debug_log "DEBUG" "Selected language is the default language (${lang_code})"
    fi
    
    # デフォルト言語以外の場合のみ翻訳DBを作成
    if [ "$is_default_language" = "false" ]; then
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
    
    # 言語翻訳処理を実行
    process_language_translation
    
    debug_log "DEBUG" "Translation module initialized with language processing"
}

# スクリプト初期化（自動実行）
# init_translation
