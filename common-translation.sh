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

# 言語DBファイル作成関数（行単位の安全な一括翻訳）
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR:-/tmp/aios}/messages_base.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR:-/tmp/aios}/messages_${api_lang}.db"
    local temp_dir="${TRANSLATION_CACHE_DIR}/temp_$$"
    local msg_file="${temp_dir}/messages.txt"
    local key_file="${temp_dir}/keys.txt"
    
    debug_log "DEBUG" "Creating language DB for ${target_lang}"
    
    # 一時ディレクトリ作成
    mkdir -p "$temp_dir"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found at: $base_db"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # DBファイル作成 (新規作成・上書き)
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"

SUPPORTED_LANGUAGES="${target_lang}"
SUPPORTED_LANGUAGE_${target_lang}="${target_lang}"

EOF
    
    # オンライン翻訳が無効なら翻訳せず置換するだけ
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^US|" "$base_db" | sed "s/^US|/${target_lang}|/" >> "$output_db"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # エントリ抽出とキャッシュ準備
    local entries_count=0
    local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_messages.cache"
    touch "$cache_file"
    
    # メッセージとキーを個別のファイルに抽出
    : > "$msg_file"
    : > "$key_file"
    
    debug_log "DEBUG" "Extracting message entries from base DB"
    
    grep "^US|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出
        local key_part=$(printf "%s" "$line" | sed 's/^US|\([^=]*\)=.*/\1/')
        local value_part=$(printf "%s" "$line" | sed 's/^US|[^=]*=\(.*\)/\1/')
        
        # キャッシュで既に翻訳済みかチェック
        local cache_key="${key_part}=${value_part}"
        local cache_hit=$(grep -F -x -m 1 "CACHE:${cache_key}=" "$cache_file" | sed 's/^CACHE:[^=]*=\(.*\)/\1/')
        
        if [ -n "$cache_hit" ]; then
            # キャッシュヒット
            debug_log "DEBUG" "Cache hit for: $key_part"
            printf "%s|%s=%s\n" "$target_lang" "$key_part" "$cache_hit" >> "$output_db"
        else
            # 翻訳対象に追加
            printf "%s\n" "$value_part" >> "$msg_file"
            printf "%s\n" "$key_part" >> "$key_file"
            entries_count=$((entries_count + 1))
        fi
    done
    
    # 翻訳が必要なエントリがなければ終了
    if [ "$entries_count" -eq 0 ]; then
        debug_log "DEBUG" "No entries need translation, using cached results"
        rm -rf "$temp_dir"
        return 0
    fi
    
    debug_log "DEBUG" "Found $entries_count entries requiring translation"
    
    # スピナー開始
    start_spinner "Processing translation..." "dot" "blue"
    
    # ファイル全体を翻訳
    local original_content=$(cat "$msg_file")
    local translated_content=""
    
    # ネットワーク接続確認
    if ping -c 1 -W 1 one.one.one.one >/dev/null 2>&1; then
        debug_log "DEBUG" "Network available, performing translation"
        
        # Google API で翻訳を試みる
        translated_content=$(translate_with_google "$original_content" "en" "$api_lang" 2>/dev/null)
        
        # 結果が空の場合は MyMemory API を試す
        if [ -z "$translated_content" ]; then
            debug_log "DEBUG" "Google API failed, trying MyMemory API"
            translated_content=$(translate_with_mymemory "$original_content" "en" "$api_lang" 2>/dev/null)
        fi
        
        # それでも失敗した場合は原文を使用
        if [ -z "$translated_content" ]; then
            debug_log "DEBUG" "All translation APIs failed, using original text"
            translated_content="$original_content"
        else
            debug_log "DEBUG" "Translation succeeded with API"
        fi
    else
        debug_log "DEBUG" "Network unavailable, using original text"
        translated_content="$original_content"
    fi
    
    # 翻訳結果を一時ファイルに保存
    local trans_file="${temp_dir}/translated.txt"
    printf "%s" "$translated_content" > "$trans_file"
    
    # 翻訳結果を行単位で分割
    local split_dir="${temp_dir}/split"
    mkdir -p "$split_dir"
    
    # 各行を個別のファイルに分割
    awk '{print > "'$split_dir'/line_" NR}' "$trans_file"
    
    # キーと翻訳結果を組み合わせてDBに書き込み
    debug_log "DEBUG" "Combining keys with translated values"
    
    local line_count=0
    while IFS= read -r key; do
        line_count=$((line_count + 1))
        local split_file="${split_dir}/line_${line_count}"
        
        if [ -f "$split_file" ]; then
            local trans_value=$(cat "$split_file")
            # 空の翻訳結果は元の値を使用
            if [ -z "$trans_value" ]; then
                debug_log "DEBUG" "Empty translation for key: $key, using original"
                local orig_value=$(grep "^US|${key}=" "$base_db" | sed 's/^US|[^=]*=\(.*\)/\1/')
                trans_value="$orig_value"
            fi
            
            # DBファイルとキャッシュに書き込み
            printf "%s|%s=%s\n" "$target_lang" "$key" "$trans_value" >> "$output_db"
            printf "CACHE:%s=%s=%s\n" "$key" "$(grep "^US|${key}=" "$base_db" | sed 's/^US|[^=]*=\(.*\)/\1/')" "$trans_value" >> "$cache_file"
        else
            debug_log "DEBUG" "Missing translation file for key: $key"
            # 対応する翻訳ファイルがない場合は元の値を使用
            local orig_value=$(grep "^US|${key}=" "$base_db" | sed 's/^US|[^=]*=\(.*\)/\1/')
            printf "%s|%s=%s\n" "$target_lang" "$key" "$orig_value" >> "$output_db"
        fi
    done < "$key_file"
    
    # スピナー停止
    stop_spinner "Translation complete" "success"
    
    # 一時ファイル削除
    rm -rf "$temp_dir"
    
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
    
    # US以外の場合のみ翻訳DBを作成
    if [ "$lang_code" != "US" ]; then
        # 翻訳DBを作成
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
    process_language_translation
    
    debug_log "DEBUG" "Translation module initialized with language processing"
    printf "Translation module initialization complete\n"
}

# スクリプト初期化（自動実行）
# init_translation
