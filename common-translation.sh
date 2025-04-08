#!/bin/sh

SCRIPT_VERSION="2025-04-08-01-01"

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
LIBRETRANSLATE_URL="${LIBRETRANSLATE_URL:-https://translate.argosopentech.com/translate}"
LINGVA_URL="${LINGVA_URL:-https://lingva.ml/api/v1}"
# API_LIST="${API_LIST:-google,libretranslate,lingva}"
# API_LIST="${API_LIST:-lingva}"
# API_LIST="${API_LIST:-libretranslate}"
API_LIST="${API_LIST:-google}"

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

# LibreTranslate APIを使用した翻訳関数
translate_with_libretranslate() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    
    debug_log "DEBUG" "Starting LibreTranslate API request" "true"
    
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
    
    # 一時ファイル
    local temp_file="${TRANSLATION_CACHE_DIR}/libretranslate_response.tmp"
    
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null
    
    # リトライループ
    while [ $retry_count -le $API_MAX_RETRIES ]; do
        [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ] && \
            wget_options=$([ "$wget_options" = "-4" ] && echo "-6" || echo "-4")
        
        # POSTリクエスト作成
        $BASE_WGET $wget_options -T $API_TIMEOUT --tries=1 -O "$temp_file" \
            --header="Content-Type: application/json" \
            --post-data="{\"q\":\"$text\",\"source\":\"$source_lang\",\"target\":\"$target_lang\",\"format\":\"text\",\"api_key\":\"\"}" \
            "${LIBRETRANSLATE_URL}" 2>/dev/null
        
        # レスポンスチェック
        if [ -s "$temp_file" ] && grep -q "translatedText" "$temp_file"; then
            local translated=$(sed 's/.*"translatedText"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/g' "$temp_file" | sed 's/\\"/"/g')
            
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

# Lingva Translate APIを使用した翻訳関数
translate_with_lingva() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    
    debug_log "DEBUG" "Starting Lingva Translate API request" "true"
    
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

# Google APIを使用した翻訳関数（高速化版）
translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    local api_url="${GOOGLE_TRANSLATE_URL}"
    
    debug_log "DEBUG" "Starting Google Translate API request" "true"
    
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
    local temp_file="${TRANSLATION_CACHE_DIR}/google_response.tmp"
    
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null
    
    # リトライループ
    while [ $retry_count -le $API_MAX_RETRIES ]; do
        [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ] && \
            wget_options=$([ "$wget_options" = "-4" ] && echo "-6" || echo "-4")
        
        # APIリクエスト送信 - 待機時間なしのシンプル版
        $BASE_WGET $wget_options -T $API_TIMEOUT --tries=1 -O "$temp_file" \
             --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
             "${api_url}?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}" 2>/dev/null
        
        # 効率的なレスポンスチェック
        if [ -s "$temp_file" ] && grep -q '\[\[\["' "$temp_file"; then
            local translated=$(sed 's/\[\[\["//;s/",".*//;s/\\u003d/=/g;s/\\u003c/</g;s/\\u003e/>/g;s/\\u0026/\&/g;s/\\"/"/g' "$temp_file")
            
            if [ -n "$translated" ]; then
                rm -f "$temp_file"
                printf "%s\n" "$translated"
                return 0
            fi
        fi
        
        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
    done
    
    return 1
}

# 翻訳実行関数
translate_text() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local result=""
    
    debug_log "DEBUG" "Starting translation using single API mode"
    
    case "$API_LIST" in          
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
            
        libretranslate)
            debug_log "DEBUG" "Using LibreTranslate API"
            result=$(translate_with_libretranslate "$text" "$source_lang" "$target_lang")
            
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                debug_log "DEBUG" "LibreTranslate translation completed"
                echo "$result"
                return 0
            else
                debug_log "DEBUG" "LibreTranslate translation failed"
                return 1
            fi
            ;;
            
        lingva)
            debug_log "DEBUG" "Using Lingva Translate API"
            result=$(translate_with_lingva "$text" "$source_lang" "$target_lang")
            
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                debug_log "DEBUG" "Lingva translation completed"
                echo "$result"
                return 0
            else
                debug_log "DEBUG" "Lingva translation failed"
                return 1
            fi
            ;;
            
        *)
            debug_log "DEBUG" "Unknown or invalid API specified: $API_LIST"
            return 1
            ;;
    esac
}

# 言語データベース作成関数
create_language_db() {
    local lang_db_file="$1"
    local api_lang="$2"
    
    # 既存のデータベースがあれば削除
    [ -f "$lang_db_file" ] && rm "$lang_db_file"
    
    debug_log "DEBUG" "Creating language database with API language: $api_lang"
    
    # 言語ファイルの各行を処理
    local current_api=""
    local value=""
    local key=""
    local cleaned_translation=""
    local result=""
    
    # API設定を表示（単純にデフォルトAPIを使用）
    local api=$(echo "$API_LIST" | cut -d ',' -f1)
    CURRENT_API="$api"
    
    case "$CURRENT_API" in
        google) current_api="Google Translate API" ;;
        libretranslate) current_api="LibreTranslate API" ;;
        lingva) current_api="Lingva Translate API" ;;
        *) current_api="Unknown API" ;;
    esac
    
    debug_log "DEBUG" "Using API: $current_api"
    
    # message_en.dbの各行を処理
    while IFS= read -r line || [ -n "$line" ]; do
        # 空行やコメント行はスキップ
        [ -z "$line" ] || [ "${line#\#}" != "$line" ] && continue
        
        # キーと値を抽出
        key=$(echo "$line" | cut -d '|' -f2)
        value=$(echo "$line" | cut -d '=' -f2-)
        
        debug_log "DEBUG" "Processing key: $key, value: $value"
        
        # 翻訳処理
        cleaned_translation=""
        
        # キャッシュをチェック
        local cache_file="${TRANSLATION_CACHE_DIR}/${CURRENT_API}_${DEFAULT_LANGUAGE}_${api_lang}_$(echo "$value" | md5sum | cut -d ' ' -f1)"
        
        if [ -f "$cache_file" ]; then
            # キャッシュから翻訳を取得
            cleaned_translation=$(cat "$cache_file")
            debug_log "DEBUG" "Using cached translation for: $key"
        else
            # 現在設定されているAPIで翻訳
            debug_log "DEBUG" "Translating key: $key with $current_api"
            
            # 単一APIで翻訳（API_LISTの最初のAPIのみ使用）
            result=$(translate_text "$value" "$DEFAULT_LANGUAGE" "$api_lang" 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                cleaned_translation="$result"
                echo "$cleaned_translation" > "$cache_file"
                debug_log "DEBUG" "Translation successful and cached"
            else
                debug_log "DEBUG" "$current_api failed for key: ${key}"
                cleaned_translation="$value"  # 翻訳失敗時は元の値を使用
            fi
        fi
        
        # 結果を言語DBに書き込み
        echo "${DEFAULT_LANGUAGE}|${key}=${value}" >> "$lang_db_file"
        echo "${api_lang}|${key}=${cleaned_translation}" >> "$lang_db_file"
        
        debug_log "DEBUG" "Added to language DB: ${api_lang}|${key}=${cleaned_translation}"
    done < "${MESSAGE_FILE}"
    
    debug_log "DEBUG" "Language database created successfully"
    
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
