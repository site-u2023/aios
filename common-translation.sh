#!/bin/sh

SCRIPT_VERSION="2025-03-28-11-58"

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

# オンライン翻訳を有効化
ONLINE_TRANSLATION_ENABLED="yes"

# 翻訳キャッシュディレクトリ
TRANSLATION_CACHE_DIR="${BASE_DIR:-/tmp/aios}/translations"

# 翻訳API設定
TRANSLATION_API="${TRANSLATION_API:-mymemory}"
API_LIMIT_FILE="${CACHE_DIR}/api_limit.txt"

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# APIの使用制限ステータスを確認
check_api_limit() {
    local api_name="$1"
    local now=$(date +%s)
    
    if [ -f "$API_LIMIT_FILE" ]; then
        local api_data=$(grep "^${api_name}:" "$API_LIMIT_FILE" 2>/dev/null)
        
        if [ -n "$api_data" ]; then
            local limit_until=$(echo "$api_data" | cut -d: -f2)
            local remaining=$(( limit_until - now ))
            
            if [ $remaining -gt 0 ]; then
                local hours=$(( remaining / 3600 ))
                local minutes=$(( (remaining % 3600) / 60 ))
                local seconds=$(( remaining % 60 ))
                debug_log "INFO" "${api_name} quota limit: ${hours}h ${minutes}m ${seconds}s remaining until reset"
                return 1
            else
                # 制限が解除されたので、ファイルから削除
                sed -i "/^${api_name}:/d" "$API_LIMIT_FILE" 2>/dev/null
            fi
        fi
    fi
    
    return 0
}

# APIの使用制限を記録
set_api_limit() {
    local api_name="$1"
    local hours="$2"
    local now=$(date +%s)
    local limit_until=$(( now + hours * 3600 ))
    
    mkdir -p "$(dirname "$API_LIMIT_FILE")"
    
    # 既存のエントリがあれば削除
    if [ -f "$API_LIMIT_FILE" ]; then
        sed -i "/^${api_name}:/d" "$API_LIMIT_FILE" 2>/dev/null
    fi
    
    # 新しいエントリを追加
    echo "${api_name}:${limit_until}" >> "$API_LIMIT_FILE"
    debug_log "WARNING" "${api_name} API quota exceeded, locked for ${hours} hours"
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

# オフライン翻訳（ローカル辞書を使用）
translate_offline() {
    local text="$1"
    local target_lang="$2"
    local dictionary_file="${BASE_DIR}/dictionary_${target_lang}.txt"
    
    # 辞書ファイルがなければ元のテキストを返す
    if [ ! -f "$dictionary_file" ]; then
        debug_log "DEBUG" "Dictionary file not found for ${target_lang}"
        echo "$text"
        return 1
    fi
    
    # 辞書から翻訳を検索
    local result=$(grep "^${text}=" "$dictionary_file" | cut -d= -f2-)
    
    # 翻訳が見つからなければ元のテキストを返す
    if [ -n "$result" ]; then
        debug_log "DEBUG" "Found offline translation for: ${text}"
        echo "$result"
        return 0
    fi
    
    # 見つからなかった場合
    debug_log "DEBUG" "No offline translation found for: ${text}"
    echo "$text"
    return 1
}

# MyMemory APIを使用して翻訳
translate_mymemory() {
    local text="$1"
    local source_lang="en"
    local target_lang="$2"
    local encoded_text=$(urlencode "$text")
    local translated=""
    
    # API制限をチェック
    if ! check_api_limit "mymemory"; then
        debug_log "DEBUG" "MyMemory API quota still exceeded, skipping"
        return 1
    fi
    
    debug_log "DEBUG" "Using MyMemory API to translate: ${text}"
    translated=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=${source_lang}|${target_lang}" 2>/dev/null)
    
    # APIエラーをチェック
    if echo "$translated" | grep -q "YOU USED ALL AVAILABLE FREE TRANSLATIONS"; then
        debug_log "WARNING" "MyMemory API quota exceeded"
        set_api_limit "mymemory" 24  # 24時間制限
        return 1
    fi
    
    # 翻訳テキストを抽出
    translated=$(echo "$translated" | sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    
    # 結果をチェック
    if [ -n "$translated" ] && [ "$translated" != "$text" ]; then
        debug_log "DEBUG" "MyMemory API translation successful"
        echo "$translated"
        return 0
    fi
    
    debug_log "DEBUG" "MyMemory API translation failed or unchanged"
    return 1
}

# LibreTranslate APIを使用して翻訳
translate_libretranslate() {
    local text="$1"
    local source_lang="en"
    local target_lang="$2"
    local translated=""
    
    # API制限をチェック
    if ! check_api_limit "libretranslate"; then
        debug_log "DEBUG" "LibreTranslate API quota still exceeded, skipping"
        return 1
    fi
    
    debug_log "DEBUG" "Using LibreTranslate API to translate: ${text}"
    translated=$(curl -s -m 3 -X POST 'https://libretranslate.de/translate' \
        -H 'Content-Type: application/json' \
        -d "{\"q\":\"$text\",\"source\":\"$source_lang\",\"target\":\"$target_lang\",\"format\":\"text\"}" 2>/dev/null)
    
    # APIエラーをチェック
    if echo "$translated" | grep -q "Too many requests" || echo "$translated" | grep -q "Error"; then
        debug_log "WARNING" "LibreTranslate API quota exceeded or error"
        set_api_limit "libretranslate" 1  # 1時間制限
        return 1
    fi
    
    # 翻訳テキストを抽出
    translated=$(echo "$translated" | sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    
    # 結果をチェック
    if [ -n "$translated" ] && [ "$translated" != "$text" ]; then
        debug_log "DEBUG" "LibreTranslate API translation successful"
        echo "$translated"
        return 0
    fi
    
    debug_log "DEBUG" "LibreTranslate API translation failed or unchanged"
    return 1
}

# テキストを翻訳する関数（複数のAPIに対応）
translate_text() {
    local text="$1"
    local target_lang="$2"
    local result=""
    
    # 空のテキストは処理しない
    if [ -z "$text" ]; then
        echo ""
        return 0
    fi
    
    # まずオフライン翻訳を試みる
    result=$(translate_offline "$text" "$target_lang")
    if [ "$result" != "$text" ]; then
        debug_log "DEBUG" "Using offline translation"
        echo "$result"
        return 0
    fi
    
    # ネットワーク接続確認
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "WARNING" "Network unavailable, cannot translate online"
        echo "$text"
        return 1
    fi
    
    # 各APIを順番に試す
    case "$TRANSLATION_API" in
        mymemory)
            result=$(translate_mymemory "$text" "$target_lang")
            if [ $? -eq 0 ]; then
                echo "$result"
                return 0
            fi
            
            # MyMemoryが失敗したらLibreTranslateを試す
            TRANSLATION_API="libretranslate"
            debug_log "DEBUG" "Switching to LibreTranslate API"
            ;;
    esac
    
    # LibreTranslateを試す
    result=$(translate_libretranslate "$text" "$target_lang")
    if [ $? -eq 0 ]; then
        echo "$result"
        return 0
    fi
    
    # すべて失敗した場合は元のテキストを返す
    debug_log "WARNING" "All translation APIs failed, using original text"
    echo "$text"
    return 1
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
        debug_log "ERROR" "Base message DB not found at ${base_db}"
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
    
    # API制限の状態を表示
    debug_log "INFO" "Checking API limits before translation"
    check_api_limit "mymemory"
    check_api_limit "libretranslate"
    
    # 全エントリを抽出
    : > "$temp_file"
    local entry_count=$(grep -c "^US|" "$base_db")
    debug_log "DEBUG" "Processing ${entry_count} translation entries using ${TRANSLATION_API} API"
    
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
                debug_log "DEBUG" "Using cached translation for: ${key}"
            else
                # キャッシュになければオンライン翻訳を実行
                local translated=$(translate_text "$value" "$api_lang")
                
                # 翻訳結果を処理
                if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
                    # キャッシュに保存
                    mkdir -p "$(dirname "$cache_file")"
                    echo "$translated" > "$cache_file"
                    
                    # DBに追加
                    echo "${target_lang}|${key}=${translated}" >> "$temp_file"
                    debug_log "DEBUG" "Added new translation for: ${key}"
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
    
    # API制限の状態を再度表示
    debug_log "INFO" "Checking API limits after translation"
    check_api_limit "mymemory"
    check_api_limit "libretranslate"
    
    debug_log "DEBUG" "Language DB creation completed in ${duration} seconds"
    return 0
}

# 言語翻訳処理
process_language_translation() {
    # 既存の言語コードを取得
    if [ ! -f "${CACHE_DIR}/language.ch" ]; then
        debug_log "ERROR" "No language code found at ${CACHE_DIR}/language.ch"
        return 1
    fi
    
    local lang_code=$(cat "${CACHE_DIR}/language.ch")
    debug_log "DEBUG" "Processing translation for language: ${lang_code}"
    
    # 言語DBの存在確認
    local lang_db="${BASE_DIR}/messages_${lang_code}.db"
    
    # 言語DBが存在しない場合または強制更新フラグがある場合のみ作成
    if [ ! -f "$lang_db" ] || [ -f "${CACHE_DIR}/force_translation_update" ]; then
        debug_log "DEBUG" "Creating translation DB for language: ${lang_code}"
        create_language_db "$lang_code"
        
        # 強制更新フラグがあれば削除
        [ -f "${CACHE_DIR}/force_translation_update" ] && rm -f "${CACHE_DIR}/force_translation_update"
    else
        debug_log "DEBUG" "Translation DB already exists for language: ${lang_code}"
    fi
    
    return 0
}

# 初期化関数
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # 言語翻訳処理を実行
    process_language_translation
    
    debug_log "DEBUG" "Translation module initialized with performance optimizations"
    return 0
}

# デバッグ用：APIの制限状態を表示
show_api_limit_status() {
    if [ ! -f "$API_LIMIT_FILE" ]; then
        echo "No API limits set"
        return 0
    fi
    
    local now=$(date +%s)
    
    echo "===== API Quota Status ====="
    while IFS=: read -r api_name limit_until; do
        if [ -n "$api_name" ] && [ -n "$limit_until" ]; then
            local remaining=$(( limit_until - now ))
            
            if [ $remaining -gt 0 ]; then
                local hours=$(( remaining / 3600 ))
                local minutes=$(( (remaining % 3600) / 60 ))
                local seconds=$(( remaining % 60 ))
                echo "${api_name}: Quota exceeded - Reset in ${hours}h ${minutes}m ${seconds}s"
            else
                echo "${api_name}: Quota available"
            fi
        fi
    done < "$API_LIMIT_FILE"
    echo "============================="
}

# 初期化は外部から呼び出す
if [ "${1:-}" = "init" ]; then
    init_translation
elif [ "${1:-}" = "status" ]; then
    show_api_limit_status
fi
