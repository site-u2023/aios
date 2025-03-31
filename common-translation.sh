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
BASE_WGET="wget --no-check-certificate -q -O"
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

# 翻訳キャッシュディレクトリ
TRANSLATION_CACHE_DIR="${BASE_DIR:-/tmp/aios}/translations"

# 使用可能なAPIリスト
# API_LIST="mymemory"
API_LIST="google"

# タイムアウト設定
WGET_TIMEOUT=10

# 現在使用中のAPI情報を格納する変数
CURRENT_API=""

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# 言語コード取得（APIのため）
get_api_lang_code() {
    # luci.chからの言語コードを使用
    if [ -f "${CACHE_DIR:-/tmp/aios}/luci.ch" ]; then
        local api_lang=$(cat "${CACHE_DIR:-/tmp/aios}/luci.ch")
        debug_log "DEBUG" "Using language code from luci.ch: ${api_lang}"
        printf "%s\n" "$api_lang"
        return 0
    fi
    
    # luci.chがない場合はデフォルトで英語
    debug_log "DEBUG" "No luci.ch found, defaulting to en"
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

# Google APIを使用した翻訳関数（IPv4/IPv6対応）
translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    
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
                # IPv4を優先使用（両方可能な場合はIPv4を使用）
                wget_options="-4"
                debug_log "DEBUG" "Both available, prioritizing IPv4 for API request"
                ;;
            *)
                debug_log "DEBUG" "No network connectivity, API request may fail"
                ;;
        esac
    fi
    
    # URLエンコード
    local encoded_text=$(urlencode "$text")
    local temp_file="/tmp/aios/translations/google_response.tmp"
    
    # ディレクトリが存在しなければ作成
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null
    
    debug_log "DEBUG" "Sending request to Google Translate API"
    wget $wget_options -q -O "$temp_file" -T 10 \
         --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
         "https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}" 2>/dev/null
    
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
    
    debug_log "DEBUG" "Google API translation failed"
    rm -f "$temp_file" 2>/dev/null
    return 1
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

# 言語データベース作成関数
# 特定の言語向けのメッセージDBを作成します
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR:-/tmp/aios}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR:-/tmp/aios}/message_${api_lang}.db"
    local temp_file="${TRANSLATION_CACHE_DIR}/temp_translation_output.txt"
    local cleaned_translation=""
    local current_api=""
    local ip_check_file="${CACHE_DIR}/network.ch"
    
    debug_log "DEBUG" "Creating language DB for ${target_lang} with API language code ${api_lang}"
    
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
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" | sed "s/^${DEFAULT_LANGUAGE}|/${target_lang}|/" >> "$output_db"
        return 0
    fi
    
    # 翻訳処理開始
    printf "言語データベースをAPIで作成中: %s\n" "$api_lang"
    
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
    
    # API_LISTから初期APIを決定（試行する最初のAPI）
    # 単純に最初のAPIを取得
    local first_api=$(echo "$API_LIST" | cut -d',' -f1)
    case "$first_api" in
        google) current_api="Google翻訳API" ;;
        *) current_api="不明なAPI" ;;
    esac
    
    debug_log "DEBUG" "Initial API based on API_LIST priority: $current_api"
    
    # スピナーを開始し、使用中のAPIを表示
    start_spinner "$(color blue "使用中のAPI: $current_api")" "dot"
    
    # 言語エントリを抽出
    grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出
        local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
        local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            # キャッシュキー生成
            local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_${cache_key}.txt"
            
            # キャッシュを確認
            if [ -f "$cache_file" ]; then
                local translated=$(cat "$cache_file")
                printf "%s|%s=%s\n" "$target_lang" "$key" "$translated" >> "$output_db"
                debug_log "DEBUG" "Using cached translation for key: ${key}"
                continue
            fi
            
            # ネットワーク接続確認
            if [ -n "$network_status" ] && [ "$network_status" != "" ]; then
                debug_log "DEBUG" "Translating text for key: ${key}"
                
                # APIリストを解析して順番に試行
                local api
                for api in $(echo "$API_LIST" | tr ',' ' '); do
                    case "$api" in
                        google)
                            # 表示APIとの不一致チェック（表示更新）
                            if [ "$current_api" != "Google翻訳API" ]; then
                                stop_spinner "APIを切り替えています" "info"
                                current_api="Google翻訳API"
                                start_spinner "$(color blue "使用中のAPI: $current_api")" "dot"
                                debug_log "DEBUG" "Switching to Google Translate API"
                            fi
                            
                            result=$(translate_with_google "$value" "$DEFAULT_LANGUAGE" "$api_lang" 2>/dev/null)
                            
                            if [ $? -eq 0 ] && [ -n "$result" ]; then
                                cleaned_translation="$result"
                                debug_log "DEBUG" "Google Translate API succeeded for key: ${key}"
                                break
                            else
                                debug_log "DEBUG" "Google Translate API failed for key: ${key}"
                            fi
                            ;;
                            
                        # 将来的に他のAPIを追加できるようにループ構造は維持
                    esac
                done
                
                # 翻訳結果処理
                if [ -n "$cleaned_translation" ]; then
                    # 基本的なエスケープシーケンスの処理
                    local decoded="$cleaned_translation"
                    
                    # キャッシュに保存
                    mkdir -p "$(dirname "$cache_file")"
                    printf "%s\n" "$decoded" > "$cache_file"
                    
                    # DBに追加
                    printf "%s|%s=%s\n" "$target_lang" "$key" "$decoded" >> "$output_db"
                    debug_log "DEBUG" "Added translation for key: ${key}"
                else
                    # 翻訳失敗時は原文をそのまま使用
                    printf "%s|%s=%s\n" "$target_lang" "$key" "$value" >> "$output_db"
                    debug_log "DEBUG" "All translation APIs failed, using original text for key: ${key}" 
                fi
            else
                # ネットワーク接続がない場合は原文を使用
                printf "%s|%s=%s\n" "$target_lang" "$key" "$value" >> "$output_db"
                debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
            fi
        fi
    done
    
    # スピナー停止
    stop_spinner "翻訳が完了しました" "success"
    
    # 翻訳処理終了
    printf "言語 %s のデータベース作成が完了しました\n" "${api_lang}"
    debug_log "DEBUG" "Language DB creation completed for ${target_lang}"
    return 0
}

# 言語翻訳処理
process_language_translation() {
    # 既存の言語コードを取得
    if [ ! -f "${CACHE_DIR:-/tmp/aios}/language.ch" ]; then
        debug_log "DEBUG" "No language code found in cache"
        return 1
    fi
    
    local lang_code=$(cat "${CACHE_DIR:-/tmp/aios}/language.ch")
    debug_log "DEBUG" "Processing translation for language: ${lang_code}"
    
    # デフォルト言語以外の場合のみ翻訳DBを作成
    if [ "$lang_code" != "$DEFAULT_LANGUAGE" ]; then
        # 翻訳DBを作成
        create_language_db "$lang_code"
    else
        debug_log "DEBUG" "Skipping DB creation for default language: ${lang_code}"
    fi
    
    return 0
}

# 初期化関数
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # 言語翻訳処理を実行
    process_language_translation
    
    debug_log "DEBUG" "Translation module initialized with language processing"
    printf "Translation module initialization complete\n"
}

# スクリプト初期化（自動実行）
# init_translation
