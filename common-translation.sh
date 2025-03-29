#!/bin/sh

SCRIPT_VERSION="2025-03-29-01-40"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-02-21
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
### 📌 AI Assistance Request: POSIX-Compliant Debugging Guide
### 
### When debugging or fixing errors in this POSIX shell script:
### 
### 1️⃣ Create a minimal reproducible test case (avoid bash features)
### 2️⃣ Test with ash/dash explicitly: dash ./test.sh
### 3️⃣ Use portable debugging methods: echo, printf, or set -x
### 4️⃣ Validate fixes against all POSIX compliance guidelines
### 5️⃣ Ensure the solution works in resource-constrained OpenWrt
### 
### ⚠️ IMPORTANT:
### - Avoid suggesting bash-specific solutions
### - Always test fixes with ash/dash before implementation
### - Prefer simple solutions over complex ones
### - Do not modify production code without test verification
### 
### 🛠️ Keep debugging simple, focused, and POSIX-compliant!
### =========================================================

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
# 基本wgetコマンド - ヘッダー無し
BASE_WGET="wget --no-check-certificate -q -O"
# BASE_WGET="wget -O"
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

# デバッグログ関数
debug_log() {
    if [ "${DEBUG:-0}" -ge 1 ]; then
        local level="$1"
        local message="$2"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[${timestamp}] ${level}: ${message}" >&2
    fi
}

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
        echo "$api_lang"
        return 0
    fi
    
    # luci.chがない場合はデフォルトで英語
    debug_log "DEBUG" "No luci.ch found, defaulting to en"
    echo "en"
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
    
    echo "$encoded"
}

# シンプル化したUnicodeデコード関数
decode_unicode() {
    local input="$1"
    local temp_file="${TRANSLATION_CACHE_DIR}/unicode_decode_temp.txt"
    
    # エスケープシーケンスがなければそのまま返す
    if ! echo "$input" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
        echo "$input"
        return 0
    fi
    
    if [ "$DEV_NULL" != "on" ]; then
        echo "Decoding Unicode escape sequences in translation response"
    fi
    debug_log "DEBUG" "Starting Unicode decode process"
    
    # AWKを使用した汎用的なUnicodeデコード
    # ASH/BusyBox環境でも動作する簡易実装
    echo "$input" | awk '
    BEGIN {
        # 16進数から10進数への変換テーブル
        for (i = 0; i <= 9; i++) hex_to_dec[i] = i
        hex_to_dec["A"] = hex_to_dec["a"] = 10
        hex_to_dec["B"] = hex_to_dec["b"] = 11
        hex_to_dec["C"] = hex_to_dec["c"] = 12
        hex_to_dec["D"] = hex_to_dec["d"] = 13
        hex_to_dec["E"] = hex_to_dec["e"] = 14
        hex_to_dec["F"] = hex_to_dec["f"] = 15
    }
    
    # 16進数文字列を10進数に変換
    function hex_to_int(hex) {
        result = 0
        for (i = 1; i <= length(hex); i++) {
            result = result * 16 + hex_to_dec[substr(hex, i, 1)]
        }
        return result
    }
    
    {
        result = ""
        str = $0
        
        while (match(str, /\\u[0-9a-fA-F]{4}/)) {
            # エスケープシーケンスの前の部分
            result = result substr(str, 1, RSTART - 1)
            
            # Unicodeコードポイント（16進数）
            hex = substr(str, RSTART + 2, 4)
            
            # 対応する文字をそのまま追加
            # printfを使うとUTF-8として出力される
            printf "%s", result
            printf "%c", hex_to_int("0x" hex)
            
            # 残りの文字列を更新
            result = ""
            str = substr(str, RSTART + RLENGTH)
        }
        
        # 残りの部分を出力
        print result str
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
    
    # 英語でのAPIステータス表示
    if [ "$DEV_NULL" != "on" ]; then
        echo "Using Google Translate API: ${source_lang} to ${target_lang}"
    fi
    debug_log "DEBUG" "Translating with Google API: ${text}"
    
    # ユーザーエージェントを設定
    local ua="Mozilla/5.0 (Linux; OpenWrt) AppleWebKit/537.36"
    
    # リクエスト送信
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
            if [ "$DEV_NULL" != "on" ]; then
                echo "Google Translate API: Translation successful"
            fi
            echo "$translated"
            return 0
        fi
    fi
    
    if [ "$DEV_NULL" != "on" ]; then
        echo "Google Translate API: Translation failed"
    fi
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
    
    # 英語でのAPIステータス表示
    if [ "$DEV_NULL" != "on" ]; then
        echo "Using MyMemory API: ${source_lang} to ${target_lang}"
    fi
    debug_log "DEBUG" "Translating with MyMemory API: ${text}"
    
    # リクエスト送信
    wget -q -O "$temp_file" -T "$WGET_TIMEOUT" \
         "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=${source_lang}|${target_lang}" 2>/dev/null
    
    # 応答解析
    if [ -s "$temp_file" ]; then
        local translated=$(grep -o '"translatedText":"[^"]*"' "$temp_file" | head -1 | sed 's/"translatedText":"//;s/"$//')
        rm -f "$temp_file"
        
        if [ -n "$translated" ] && [ "$translated" != "$text" ]; then
            if [ "$DEV_NULL" != "on" ]; then
                echo "MyMemory API: Translation successful"
            fi
            echo "$translated"
            return 0
        fi
    fi
    
    if [ "$DEV_NULL" != "on" ]; then
        echo "MyMemory API: Translation failed"
    fi
    rm -f "$temp_file"
    return 1
}

# 複数APIを使った翻訳実行
translate_text() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local result=""
    
    # API実行開始メッセージ
    if [ "$DEV_NULL" != "on" ]; then
        echo "Starting translation process with API priority: ${API_LIST}"
    fi
    debug_log "DEBUG" "Attempting translation with multiple APIs"
    
    # Google API を試行
    if echo "$API_LIST" | grep -q "google"; then
        result=$(translate_with_google "$text" "$source_lang" "$target_lang")
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            debug_log "DEBUG" "Translation successful with Google API"
            echo "$result"
            return 0
        fi
    fi
    
    # MyMemory API を試行
    if echo "$API_LIST" | grep -q "mymemory"; then
        result=$(translate_with_mymemory "$text" "$source_lang" "$target_lang")
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            debug_log "DEBUG" "Translation successful with MyMemory API"
            echo "$result"
            return 0
        fi
    fi
    
    # すべて失敗した場合
    if [ "$DEV_NULL" != "on" ]; then
        echo "All translation APIs failed - no translation result obtained"
    fi
    debug_log "DEBUG" "All translation APIs failed"
    return 1
}

# 言語DBファイルの作成関数
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR:-/tmp/aios}/messages_base.db"
    local output_db="${BASE_DIR:-/tmp/aios}/messages_${target_lang}.db"
    local api_lang=$(get_api_lang_code)
    
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

# ${target_lang}用翻訳データベース (自動生成)
# フォーマット: 言語コード|メッセージキー=メッセージテキスト

EOF
    
    # オンライン翻訳が無効なら翻訳せず置換するだけ
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^US|" "$base_db" | sed "s/^US|/${target_lang}|/" >> "$output_db"
        return 0
    fi
    
    # USエントリを抽出
    grep "^US|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出
        local key=$(echo "$line" | sed -n 's/^US|\([^=]*\)=.*/\1/p')
        local value=$(echo "$line" | sed -n 's/^US|[^=]*=\(.*\)/\1/p')
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            # キャッシュキー生成
            local cache_key=$(echo "${key}${value}${api_lang}" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_${cache_key}.txt"
            
            # キャッシュを確認
            if [ -f "$cache_file" ]; then
                local translated=$(cat "$cache_file")
                echo "${target_lang}|${key}=${translated}" >> "$output_db"
                debug_log "DEBUG" "Using cached translation for key: ${key}"
                continue
            fi
            
            # ネットワーク接続確認
            if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
                debug_log "DEBUG" "Translating text for key: ${key}"
                
                # 複数APIで翻訳を試行
                local translated=$(translate_text "$value" "en" "$api_lang")
                
                # 翻訳結果処理
                if [ -n "$translated" ]; then
                    # Unicodeエスケープシーケンスをデコード
                    local decoded=$(decode_unicode "$translated")
                    
                    # キャッシュに保存
                    mkdir -p "$(dirname "$cache_file")"
                    echo "$decoded" > "$cache_file"
                    
                    # DBに追加
                    echo "${target_lang}|${key}=${decoded}" >> "$output_db"
                    debug_log "DEBUG" "Added translation for key: ${key}"
                else
                    # 翻訳失敗時は原文をそのまま使用
                    echo "${target_lang}|${key}=${value}" >> "$output_db"
                    debug_log "DEBUG" "Translation failed, using original text for key: ${key}"
                fi
                
                # APIレート制限対策
                sleep 1
            else
                # ネットワーク接続がない場合は原文を使用
                echo "${target_lang}|${key}=${value}" >> "$output_db"
                debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
            fi
        fi
    done
    
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
}

# スクリプト初期化（自動実行）
init_translation
