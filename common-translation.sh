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

# 使用可能なAPIリスト（優先順位）
API_LIST="google,mymemory"

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

# 改良版Unicodeデコード関数
decode_unicode() {
    local input="$1"
    local temp_file="${TRANSLATION_CACHE_DIR}/unicode_decode.temp"
    
    # エスケープシーケンスがなければそのまま返す
    if ! printf "%s" "$input" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
        printf "%s\n" "$input"
        return 0
    fi
    
    printf "Decoding Unicode escape sequences...\n"
    debug_log "DEBUG" "Decoding Unicode escape sequences in translation response"
    
    # BusyBoxのawkによるUnicodeデコード処理
    printf "%s" "$input" | awk '
    BEGIN {
        # 16進数変換テーブル
        for (i = 0; i <= 9; i++) hex[i] = i
        hex["A"] = hex["a"] = 10
        hex["B"] = hex["b"] = 11
        hex["C"] = hex["c"] = 12
        hex["D"] = hex["d"] = 13
        hex["E"] = hex["e"] = 14
        hex["F"] = hex["f"] = 15
    }
    
    # 16進数を10進数に変換
    function hex_to_int(hex_str) {
        result = 0
        n = length(hex_str)
        for (i = 1; i <= n; i++) {
            result = result * 16 + hex[substr(hex_str, i, 1)]
        }
        return result
    }
    
    {
        line = $0
        result = ""
        
        while (match(line, /\\u[0-9a-fA-F]{4}/)) {
            # マッチ前の部分を追加
            result = result substr(line, 1, RSTART-1)
            
            # Unicodeコードポイントを抽出
            hex_val = substr(line, RSTART+2, 4)
            code = hex_to_int(hex_val)
            
            # UTF-8エンコーディングに変換
            if (code <= 0x7F) {
                # ASCII範囲
                result = result sprintf("%c", code)
            } else if (code <= 0x7FF) {
                # 2バイトシーケンス
                byte1 = 0xC0 + int(code / 64)
                byte2 = 0x80 + (code % 64)
                result = result sprintf("%c%c", byte1, byte2)
            } else {
                # 3バイトシーケンス
                byte1 = 0xE0 + int(code / 4096)
                byte2 = 0x80 + int((code % 4096) / 64)
                byte3 = 0x80 + (code % 64)
                result = result sprintf("%c%c%c", byte1, byte2, byte3)
            }
            
            # 残りの部分を更新
            line = substr(line, RSTART + RLENGTH)
        }
        
        # 残りの部分を追加
        print result line
    }' > "$temp_file"
    
    # 結果を返す
    cat "$temp_file"
    rm -f "$temp_file"
}

# Google翻訳API (非公式) での翻訳
translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local encoded_text=$(urlencode "$text")
    local temp_file="${TRANSLATION_CACHE_DIR}/google_response.tmp"
    
    # Google翻訳API進捗表示
    debug_log "DEBUG" "Using Google Translate API: ${source_lang} to ${target_lang}"
    
    # ユーザーエージェントを設定
    local ua="Mozilla/5.0 (Linux; OpenWrt) AppleWebKit/537.36"
    
    # API応答のエンコーディングを指定
    wget -q -O "$temp_file" -T "$WGET_TIMEOUT" \
         --user-agent="$ua" \
         "https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}" 2>/dev/null
    
    # 応答解析
    if [ -s "$temp_file" ]; then
        # 翻訳テキストの抽出を試行
        local translated=$(sed -n 's/^\[\[\["\([^"]*\)".*$/\1/p' "$temp_file")
        
        if [ -z "$translated" ]; then
            # 別の形式でも試行
            translated=$(grep -o '^\[\[\["[^"]*"' "$temp_file" | head -1 | sed 's/^\[\[\["\([^"]*\)".*/\1/')
        fi
        
        rm -f "$temp_file"
        
        if [ -n "$translated" ] && [ "$translated" != "$text" ]; then
            # Google翻訳API進捗表示
            printf "Google Translate API: Translation successful\n"
            debug_log "DEBUG" "Google Translate API: Translation successful"
            printf "%s\n" "$translated"
            return 0
        fi
    fi
    
    # Google翻訳API進捗表示
    printf "Google Translate API: Translation failed\n"
    debug_log "DEBUG" "Google Translate API: Translation failed"
    rm -f "$temp_file"
    return 1
}

# MyMemoryで翻訳を取得
translate_with_mymemory() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local encoded_text=$(urlencode "$text")
    local temp_file="${TRANSLATION_CACHE_DIR}/mymemory_response.tmp"
    
    # MyMemoryAPI進捗表示
    debug_log "DEBUG" "Using MyMemory API: ${source_lang} to ${target_lang}"
    
    # リクエスト送信
    wget -q -O "$temp_file" -T "$WGET_TIMEOUT" \
         "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=${source_lang}|${target_lang}" 2>/dev/null
    
    # 応答解析
    if [ -s "$temp_file" ]; then
        local translated=$(grep -o '"translatedText":"[^"]*"' "$temp_file" | head -1 | sed 's/"translatedText":"//;s/"$//')
        rm -f "$temp_file"
        
        if [ -n "$translated" ] && [ "$translated" != "$text" ]; then
            # MyMemoryAPI進捗表示
            printf "MyMemory API: Translation successful\n"
            debug_log "DEBUG" "MyMemory API: Translation successful"
            printf "%s\n" "$translated"
            return 0
        fi
    fi
    
    # MyMemoryAPI進捗表示
    printf "MyMemory API: Translation failed\n"
    debug_log "DEBUG" "MyMemory API: Translation failed"
    rm -f "$temp_file"
    return 1
}

# 複数APIを使った翻訳実行
translate_text() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local result=""
    
    # 全体進捗表示
    debug_log "DEBUG" "Starting translation process with API priority: ${API_LIST}"
    
    # Google API を試行
    if printf "%s" "$API_LIST" | grep -q "google"; then
        result=$(translate_with_google "$text" "$source_lang" "$target_lang")
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            debug_log "DEBUG" "Translation successful with Google API"
            printf "%s\n" "$result"
            return 0
        fi
    fi
    
    # MyMemory API を試行
    if printf "%s" "$API_LIST" | grep -q "mymemory"; then
        result=$(translate_with_mymemory "$text" "$source_lang" "$target_lang")
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            debug_log "DEBUG" "Translation successful with MyMemory API"
            printf "%s\n" "$result"
            return 0
        fi
    fi
    
    # 全体進捗表示
    printf "All translation APIs failed - no translation result obtained\n"
    debug_log "DEBUG" "All translation APIs failed - no translation result obtained"
    return 1
}

# 言語DBファイルの作成関数
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR:-/tmp/aios}/messages_base.db"
    local output_db="${BASE_DIR:-/tmp/aios}/messages_${target_lang}.db"
    local api_lang=$(get_api_lang_code)
    local temp_file="${TRANSLATION_CACHE_DIR}/temp_translation_output.txt"
    local cleaned_translation=""
    local current_api=""
    
    debug_log "DEBUG" "Creating language DB for ${target_lang} with API language code ${api_lang}"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi
    
    # DBファイル作成 (常に新規作成・上書き)
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"

SUPPORTED_LANGUAGES="${target_lang}"
SUPPORTED_LANGUAGE_${target_lang}="${target_lang}"

EOF
    
    # オンライン翻訳が無効なら翻訳せず置換するだけ
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^US|" "$base_db" | sed "s/^US|/${target_lang}|/" >> "$output_db"
        return 0
    fi
    
    # 翻訳処理開始
    printf "言語データベース作成開始: %s\n" "$target_lang"
    
    # 使用するAPIを表示（最初に一度だけ）
    if printf "%s" "$API_LIST" | grep -q "google"; then
        current_api="Google Translate API"
    fi
    
    # スピナーを開始し、使用中のAPIを表示
    start_spinner "翻訳に使用するAPI: $current_api" "dot"
    
    # USエントリを抽出
    grep "^US|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出
        local key=$(printf "%s" "$line" | sed -n 's/^US|\([^=]*\)=.*/\1/p')
        local value=$(printf "%s" "$line" | sed -n 's/^US|[^=]*=\(.*\)/\1/p')
        
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
            if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
                debug_log "DEBUG" "Translating text for key: ${key}"
                
                # Google API を試行
                if printf "%s" "$API_LIST" | grep -q "google"; then
                    # Google翻訳APIを使用中
                    if [ "$current_api" != "Google Translate API" ]; then
                        # APIが変わった場合、スピナーを停止して新しいAPIでスピナーを開始
                        stop_spinner "翻訳API切り替え" "success"
                        current_api="Google Translate API"
                        start_spinner "翻訳に使用するAPI: $current_api" "dot"
                    fi
                    
                    # 翻訳実行
                    local result=$(translate_with_google "$value" "en" "$api_lang" 2>/dev/null)
                    
                    if [ $? -eq 0 ] && [ -n "$result" ]; then
                        # 翻訳成功
                        cleaned_translation="$result"
                    else
                        # Google APIが失敗した場合、MyMemory APIを試す
                        if printf "%s" "$API_LIST" | grep -q "mymemory"; then
                            # APIが変わることを通知
                            stop_spinner "Google API失敗、MyMemory APIに切り替え" "error"
                            current_api="MyMemory API"
                            start_spinner "翻訳に使用するAPI: $current_api" "dot"
                            
                            # MyMemory APIで翻訳を試行
                            result=$(translate_with_mymemory "$value" "en" "$api_lang" 2>/dev/null)
                            
                            if [ $? -eq 0 ] && [ -n "$result" ]; then
                                # 翻訳成功
                                cleaned_translation="$result"
                            else
                                # すべてのAPIが失敗
                                cleaned_translation=""
                            fi
                        else
                            # MyMemory APIが無効
                            cleaned_translation=""
                        fi
                    fi
                elif printf "%s" "$API_LIST" | grep -q "mymemory"; then
                    # Google APIがなく、MyMemory APIのみ使用する場合
                    if [ "$current_api" != "MyMemory API" ]; then
                        # APIが変わった場合、スピナーを停止して新しいAPIでスピナーを開始
                        stop_spinner "翻訳API切り替え" "success"
                        current_api="MyMemory API"
                        start_spinner "翻訳に使用するAPI: $current_api" "dot"
                    fi
                    
                    # 翻訳実行
                    local result=$(translate_with_mymemory "$value" "en" "$api_lang" 2>/dev/null)
                    
                    if [ $? -eq 0 ] && [ -n "$result" ]; then
                        # 翻訳成功
                        cleaned_translation="$result"
                    else
                        # 翻訳失敗
                        cleaned_translation=""
                    fi
                else
                    # 有効なAPIがない
                    cleaned_translation=""
                fi
                
                # 翻訳結果処理
                if [ -n "$cleaned_translation" ]; then
                    # Unicodeエスケープシーケンスをデコード
                    local decoded=$(decode_unicode "$cleaned_translation")
                    
                    # キャッシュに保存
                    mkdir -p "$(dirname "$cache_file")"
                    printf "%s\n" "$decoded" > "$cache_file"
                    
                    # DBに追加
                    printf "%s|%s=%s\n" "$target_lang" "$key" "$decoded" >> "$output_db"
                    debug_log "DEBUG" "Added translation for key: ${key}"
                else
                    # 翻訳失敗時は原文をそのまま使用
                    printf "%s|%s=%s\n" "$target_lang" "$key" "$value" >> "$output_db"
                    debug_log "DEBUG" "Translation failed, using original text for key: ${key}"
                }
                
                # APIレート制限対策
                sleep 1
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
    printf "言語データベース作成完了: %s\n" "$target_lang"
    debug_log "DEBUG" "Language DB creation completed for ${target_lang}"
    return 0
}

# 言語DBファイルの作成関数
OK_create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR:-/tmp/aios}/messages_base.db"
    local output_db="${BASE_DIR:-/tmp/aios}/messages_${target_lang}.db"
    local api_lang=$(get_api_lang_code)
    local temp_file="${TRANSLATION_CACHE_DIR}/temp_translation_output.txt"
    local cleaned_translation=""
    
    debug_log "DEBUG" "Creating language DB for ${target_lang} with API language code ${api_lang}"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi
    
    # DBファイル作成 (常に新規作成・上書き)
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"

SUPPORTED_LANGUAGES="${target_lang}"
SUPPORTED_LANGUAGE_${target_lang}="${target_lang}"

EOF
    
    # オンライン翻訳が無効なら翻訳せず置換するだけ
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^US|" "$base_db" | sed "s/^US|/${target_lang}|/" >> "$output_db"
        return 0
    fi
    
    # 翻訳処理開始
    printf "Starting database creation for language: %s\n" "$target_lang"
    printf "Using translation APIs in this order: %s\n" "$API_LIST"
    
    # USエントリを抽出
    grep "^US|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出
        local key=$(printf "%s" "$line" | sed -n 's/^US|\([^=]*\)=.*/\1/p')
        local value=$(printf "%s" "$line" | sed -n 's/^US|[^=]*=\(.*\)/\1/p')
        
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
            if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
                debug_log "DEBUG" "Translating text for key: ${key}"
                
                # 複数APIで翻訳を試行（一時ファイルに出力）
                translate_text "$value" "en" "$api_lang" > "$temp_file" 2>&1
                
                # APIメッセージを取り除いて実際の翻訳結果のみ取得
                cleaned_translation=$(grep -v "Using Google Translate API:" "$temp_file" | grep -v "Google Translate API: Translation" | grep -v "Using MyMemory API:" | grep -v "MyMemory API: Translation")
                
                # 翻訳結果処理
                if [ -n "$cleaned_translation" ]; then
                    # Unicodeエスケープシーケンスをデコード
                    local decoded=$(decode_unicode "$cleaned_translation")
                    
                    # キャッシュに保存
                    mkdir -p "$(dirname "$cache_file")"
                    printf "%s\n" "$decoded" > "$cache_file"
                    
                    # DBに追加
                    printf "%s|%s=%s\n" "$target_lang" "$key" "$decoded" >> "$output_db"
                    debug_log "DEBUG" "Added translation for key: ${key}"
                else
                    # 翻訳失敗時は原文をそのまま使用
                    printf "%s|%s=%s\n" "$target_lang" "$key" "$value" >> "$output_db"
                    debug_log "DEBUG" "Translation failed, using original text for key: ${key}"
                fi
                
                # APIレート制限対策
                sleep 1
            else
                # ネットワーク接続がない場合は原文を使用
                printf "%s|%s=%s\n" "$target_lang" "$key" "$value" >> "$output_db"
                debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
            fi
        fi
    done
    
    # 翻訳処理終了
    printf "Database creation completed for language: %s\n" "$target_lang"
    printf "Translation APIs used: %s\n" "$API_LIST"
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
    
    # USとJP以外の場合のみ翻訳DBを作成
    if [ "$lang_code" != "US" ]; then
        # 翻訳DBを作成
        printf "Creating translation database for language %s...\n" "$lang_code"
        create_language_db "$lang_code"
    else
        debug_log "DEBUG" "Skipping DB creation for built-in language: ${lang_code}"
    fi
    
    return 0
}

# 初期化関数
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # 言語翻訳処理を実行
    printf "Initializing translation module...\n"
    process_language_translation
    
    debug_log "DEBUG" "Translation module initialized with language processing"
    printf "Translation module initialization complete\n"
}

# スクリプト初期化（自動実行）
# init_translation
