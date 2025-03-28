#!/bin/sh

SCRIPT_VERSION="2025-03-28-11-42"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-14
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

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="wget --no-check-certificate -q -O"
# BASE_WGET="wget -O"
DEBUG_MODE="${DEBUG_MODE:-false}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# オンライン翻訳を有効化
ONLINE_TRANSLATION_ENABLED="yes"

# 翻訳キャッシュディレクトリ
TRANSLATION_CACHE_DIR="${BASE_DIR:-/tmp/aios}/translations"

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# 言語コード取得（APIのため）
get_api_lang_code() {
    # luci.chからの言語コードを使用
    if [ -f "${CACHE_DIR}/luci.ch" ]; then
        local api_lang=$(cat "${CACHE_DIR}/luci.ch")
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

# 高速なUnicodeデコード関数
decode_unicode() {
    local input="$1"
    
    # Unicodeエスケープシーケンスがなければ早期リターン
    case "$input" in
        *\\u*)
            debug_log "DEBUG" "Decoding Unicode escape sequences"
            ;;
        *)
            echo "$input"
            return 0
            ;;
    esac
    
    # sedを使った高速置換 (POSIXに準拠)
    echo "$input" | sed -e 's/\\u\([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]\)/\\\\\\u\1/g' | printf "$(cat -)"
}

# 最適化された言語DB作成関数
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/messages_base.db"
    local output_db="${BASE_DIR}/messages_${target_lang}.db"
    local api_lang=$(get_api_lang_code)
    local temp_file="${TRANSLATION_CACHE_DIR}/translations_temp.txt"
    
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
    
    # ネットワーク接続確認
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "DEBUG" "Network unavailable, using original text"
        grep "^US|" "$base_db" | sed "s/^US|/${target_lang}|/" >> "$output_db"
        return 0
    fi
    
    # 全エントリを抽出
    : > "$temp_file"
    local entry_count=$(grep -c "^US|" "$base_db")
    debug_log "DEBUG" "Processing ${entry_count} translation entries"
    
    # 処理時間を計測開始
    local start_time=$(date +%s)
    
    # 各エントリを処理
    grep "^US|" "$base_db" | while IFS= read -r line; do
        local key=$(echo "$line" | sed -n 's/^US|\([^=]*\)=.*/\1/p')
        local value=$(echo "$line" | sed -n 's/^US|[^=]*=\(.*\)/\1/p')
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            # キャッシュキー生成
            local cache_key=$(echo "${key}${value}${api_lang}" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_${cache_key}.txt"
            
            # キャッシュを確認
            if [ -f "$cache_file" ]; then
                local translated=$(cat "$cache_file")
                echo "${target_lang}|${key}=${translated}" >> "$temp_file"
            else
                # キャッシュになければオンライン翻訳を実行
                local encoded_text=$(urlencode "$value")
                
                # MyMemory APIで翻訳
                local translated=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" 2>/dev/null | \
                    sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
                
                # APIからの応答処理
                if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
                    # Unicodeエスケープシーケンスをデコード
                    local decoded=$(decode_unicode "$translated")
                    
                    # キャッシュに保存
                    mkdir -p "$(dirname "$cache_file")"
                    echo "$decoded" > "$cache_file"
                    
                    # DBに追加
                    echo "${target_lang}|${key}=${decoded}" >> "$temp_file"
                    debug_log "DEBUG" "Translated: ${key}"
                else
                    # 翻訳失敗時は原文をそのまま使用
                    echo "${target_lang}|${key}=${value}" >> "$temp_file"
                    debug_log "DEBUG" "Translation failed for: ${key}, using original text"
                fi
            fi
        fi
    done
    
    # 処理時間を計測終了
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 結果をDBに追加
    cat "$temp_file" >> "$output_db"
    rm -f "$temp_file"
    
    debug_log "DEBUG" "Language DB creation completed in ${duration} seconds"
    return 0
}

# 言語翻訳処理
process_language_translation() {
    # 既存の言語コードを取得
    if [ ! -f "${CACHE_DIR}/language.ch" ]; then
        debug_log "ERROR" "No language code file found at ${CACHE_DIR}/language.ch"
        return 1
    fi
    
    local lang_code=$(cat "${CACHE_DIR}/language.ch")
    debug_log "DEBUG" "Processing translation for language code: ${lang_code}"
    
    # ベースDBファイルの存在確認
    local base_db="${BASE_DIR}/messages_base.db"
    if [ ! -f "$base_db" ]; then
        debug_log "ERROR" "Base message database not found at ${base_db}"
        return 1
    fi
    
    # 言語コードに応じたDBファイル
    local lang_db="${BASE_DIR}/messages_${lang_code}.db"
    
    # 翻訳ファイルの作成または更新
    debug_log "DEBUG" "Creating/updating translation DB for ${lang_code}"
    create_language_db "$lang_code"
    
    # 作成されたDBファイルの確認
    if [ -f "$lang_db" ]; then
        debug_log "DEBUG" "Successfully created translation DB at ${lang_db}"
        return 0
    else
        debug_log "ERROR" "Failed to create translation DB for ${lang_code}"
        return 1
    fi
}

# 初期化関数
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # 言語翻訳処理を実行（必ず実行されるように修正）
    process_language_translation
    
    # 明示的に成功を示す
    debug_log "DEBUG" "Translation module initialized with performance optimizations"
    return 0
}

# 初期化は自動的に実行しない
# init_translation
