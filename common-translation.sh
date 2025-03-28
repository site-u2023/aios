#!/bin/sh

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Common Translation Functions
#
# 📢 POSIX Compliance Guidelines:
# ✅ Use `[` instead of `[[` for conditions
# ✅ Use $(command) instead of backticks `command`
# ✅ Use $(( )) for arithmetic instead of let
# ✅ Define functions as func_name() {} (no function keyword)
# ✅ No associative arrays (declare -A is NOT supported)
# ✅ No here-strings (<<< is NOT supported)
# ✅ No -v flag in test or [[
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
# =========================================================

# 環境変数の設定
DEBUG="${DEBUG:-0}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-/tmp/aios}"
TRANSLATION_CACHE_DIR="${BASE_DIR}/translations"
CURRENT_LANGUAGE="${CURRENT_LANGUAGE:-en}"
ONLINE_TRANSLATION_ENABLED="${ONLINE_TRANSLATION_ENABLED:-yes}"

# デバッグログ関数
debug_log() {
    if [ "$DEBUG" -ge 1 ]; then
        local level="$1"
        local message="$2"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[${timestamp}] ${level}: ${message}" >&2
    fi
}

# ディレクトリの作成
mkdir -p "$TRANSLATION_CACHE_DIR" "$CACHE_DIR" 2>/dev/null

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

# AWKを使ったユニコードエスケープシーケンスのデコーダー
decode_unicode_awk() {
    local input="$1"
    
    # ユニコードエスケープがない場合は早期リターン
    case "$input" in
        *\\u*)
            debug_log "DEBUG" "Decoding unicode escape sequences with awk"
            ;;
        *)
            echo "$input"
            return 0
            ;;
    esac
    
    # awkスクリプトでデコード
    echo "$input" | awk '
    BEGIN {
        # 初期化
    }
    
    function decode(str) {
        result = ""
        i = 1
        len = length(str)
        
        while (i <= len) {
            char = substr(str, i, 1)
            if (char == "\\") {
                if (substr(str, i+1, 1) == "u") {
                    # ユニコードエスケープシーケンス (\uXXXX) を検出
                    hex = substr(str, i+2, 4)
                    i += 6
                    
                    # 16進数をコードポイントに変換
                    code = strtonum("0x" hex)
                    
                    # UTF-8エンコーディングに変換
                    if (code <= 0x7F) {
                        # 1バイト文字 (0xxxxxxx)
                        result = result sprintf("%c", code)
                    } else if (code <= 0x7FF) {
                        # 2バイト文字 (110xxxxx 10xxxxxx)
                        byte1 = 0xC0 + int(code / 64)
                        byte2 = 0x80 + (code % 64)
                        result = result sprintf("%c%c", byte1, byte2)
                    } else if (code <= 0xFFFF) {
                        # 3バイト文字 (1110xxxx 10xxxxxx 10xxxxxx)
                        byte1 = 0xE0 + int(code / 4096)
                        byte2 = 0x80 + int((code % 4096) / 64)
                        byte3 = 0x80 + (code % 64)
                        result = result sprintf("%c%c%c", byte1, byte2, byte3)
                    } else {
                        # 4バイト文字 (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
                        # ほとんど使われないため、簡略化
                        result = result "?"
                    }
                    i--  # ループで増加するため調整
                } else {
                    # その他のエスケープシーケンス
                    result = result char
                    i++
                }
            } else {
                # 通常の文字
                result = result char
            }
            i++
        }
        return result
    }
    
    {
        # 各行をデコードして出力
        print decode($0)
    }
    '
}

# MyMemory API を使用した翻訳関数（wget使用）
translate_with_mymemory() {
    local text="$1"
    local lang="$2"
    
    # Langdirはja_JPのような形式からja形式に変換
    local lang_short=$(echo "$lang" | cut -d'_' -f1)
    
    debug_log "DEBUG" "Using MyMemory API with wget to translate to ${lang_short}"
    
    # URLエンコード
    local encoded_text=$(urlencode "$text")
    
    # MyMemory APIへのリクエスト（認証情報なし）
    local url="https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${lang_short}"
    
    # 一時ファイル作成
    local temp_file="${CACHE_DIR}/mymemory_temp.txt"
    
    # wgetでリクエスト実行
    wget -q -T 15 -O "$temp_file" "$url" 2>/dev/null
    local wget_status=$?
    
    # 失敗した場合
    if [ $wget_status -ne 0 ] || [ ! -s "$temp_file" ]; then
        debug_log "WARNING" "MyMemory API request failed with status: ${wget_status}"
        rm -f "$temp_file"
        return 1
    fi
    
    # レスポンス解析
    if grep -q '"responseStatus":200' "$temp_file"; then
        # 翻訳テキスト抽出
        local translated=$(grep -o '"translatedText":"[^"]*"' "$temp_file" | head -1 | sed 's/"translatedText":"//;s/"$//')
        
        # 翻訳が空かチェック
        if [ -n "$translated" ] && [ "$translated" != "$text" ]; then
            debug_log "DEBUG" "MyMemory API translation successful"
            rm -f "$temp_file"
            echo "$translated"
            return 0
        fi
    elif grep -q '"responseStatus"' "$temp_file"; then
        # エラーステータスとメッセージの表示
        local status=$(grep -o '"responseStatus":"[^"]*"' "$temp_file" | head -1 | sed 's/"responseStatus":"//;s/"$//')
        local message=$(grep -o '"responseDetails":"[^"]*"' "$temp_file" | head -1 | sed 's/"responseDetails":"//;s/"$//')
        debug_log "WARNING" "MyMemory API error: status=${status}, message=${message}"
    fi
    
    rm -f "$temp_file"
    debug_log "WARNING" "MyMemory API translation failed"
    return 1
}

# LibreTranslate API を使用した翻訳関数（wget使用）
translate_with_libretranslate() {
    local text="$1"
    local lang="$2"
    
    # Langdirはja_JPのような形式からja形式に変換
    local lang_short=$(echo "$lang" | cut -d'_' -f1)
    
    debug_log "DEBUG" "Using LibreTranslate API with wget to translate to ${lang_short}"
    
    # 動作確認済みのエンドポイント
    local endpoint="https://translate.argosopentech.com/translate"
    
    # URLエンコード
    local encoded_text=$(urlencode "$text")
    
    # POSTデータ作成
    local post_data="q=${encoded_text}&source=en&target=${lang_short}&format=text"
    local post_file="${CACHE_DIR}/libretranslate_post.txt"
    local temp_file="${CACHE_DIR}/libretranslate_temp.txt"
    
    # POSTデータをファイルに書き込み
    mkdir -p "$(dirname "$post_file")" 2>/dev/null
    echo "$post_data" > "$post_file"
    
    # wgetでPOSTリクエスト実行
    wget -q -T 15 --post-file="$post_file" -O "$temp_file" "$endpoint" 2>/dev/null
    local wget_status=$?
    
    # 失敗した場合
    if [ $wget_status -ne 0 ] || [ ! -s "$temp_file" ]; then
        debug_log "WARNING" "LibreTranslate API request failed with status: ${wget_status}"
        rm -f "$temp_file" "$post_file"
        return 1
    fi
    
    # エラーレスポンスのチェック
    if grep -q "Too many requests\|Error\|error" "$temp_file"; then
        debug_log "WARNING" "LibreTranslate API returned error response"
        rm -f "$temp_file" "$post_file"
        return 1
    fi
    
    # 翻訳テキスト抽出
    local translated=$(grep -o '"translatedText":"[^"]*"' "$temp_file" | head -1 | sed 's/"translatedText":"//;s/"$//')
    
    # 翻訳が空かチェック
    if [ -n "$translated" ] && [ "$translated" != "$text" ]; then
        debug_log "DEBUG" "LibreTranslate API translation successful"
        rm -f "$temp_file" "$post_file"
        echo "$translated"
        return 0
    fi
    
    rm -f "$temp_file" "$post_file"
    debug_log "WARNING" "LibreTranslate API translation failed"
    return 1
}

# 翻訳キャッシュの取得または設定
get_set_translation_cache() {
    local text="$1"
    local lang="$2"
    local value="$3"
    local cache_file="${TRANSLATION_CACHE_DIR}/${lang}.cache"
    
    # キャッシュディレクトリが存在しない場合は作成
    mkdir -p "$TRANSLATION_CACHE_DIR" 2>/dev/null
    
    # テキストからキャッシュキー生成
    local key=$(echo "$text" | md5sum | cut -d' ' -f1)
    
    # 値が指定されていない場合は取得モード
    if [ -z "$value" ]; then
        # キャッシュファイルが存在するかチェック
        if [ -f "$cache_file" ]; then
            # キャッシュからデータを取得
            local cached_value=$(grep "^${key}=" "$cache_file" | cut -d'=' -f2-)
            if [ -n "$cached_value" ]; then
                debug_log "DEBUG" "Cache hit for ${text} in language ${lang}"
                echo "$cached_value"
                return 0
            fi
        fi
        # キャッシュミス
        return 1
    else
        # 設定モード - キャッシュにデータを保存
        # キャッシュファイルが存在するかチェック
        touch "$cache_file" 2>/dev/null
        
        # 既存のエントリを削除（もしあれば）
        if grep -q "^${key}=" "$cache_file" 2>/dev/null; then
            sed -i "/^${key}=/d" "$cache_file"
        fi
        
        # 新しいエントリを追加
        echo "${key}=${value}" >> "$cache_file"
        
        debug_log "DEBUG" "Cached translation for ${text} in language ${lang}"
        return 0
    fi
}

# メッセージファイルからの翻訳取得
get_message_translation() {
    local key="$1"
    local lang="$2"
    local default="$3"
    local message_file="${BASE_DIR}/messages.txt"
    
    # メッセージファイルが存在するかチェック
    if [ ! -f "$message_file" ]; then
        debug_log "WARNING" "Message file not found: ${message_file}"
        echo "$default"
        return 1
    fi
    
    # メッセージファイルから該当言語のエントリを検索
    local entry=$(grep "^${lang}|${key}=" "$message_file")
    
    if [ -n "$entry" ]; then
        # エントリが見つかった場合、値を抽出してデコード
        local value=$(echo "$entry" | cut -d'=' -f2-)
        local decoded=$(decode_unicode_awk "$value")
        
        if [ -n "$decoded" ]; then
            debug_log "DEBUG" "Found translation for ${key} in language ${lang}"
            echo "$decoded"
            return 0
        fi
    fi
    
    # 対応する翻訳が見つからない場合はデフォルト値を返す
    debug_log "DEBUG" "No translation found for ${key} in language ${lang}, using default"
    echo "$default"
    return 1
}

# オンライン翻訳関数
translate_text() {
    local text="$1"
    local lang="$2"
    local retry_count=0
    local max_retries=1
    
    debug_log "DEBUG" "Translating text to ${lang}: ${text}"
    
    # 空の場合はそのまま返す
    if [ -z "$text" ]; then
        echo ""
        return 0
    fi
    
    # オンライン翻訳が無効な場合は元のテキストを返す
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, returning original text"
        echo "$text"
        return 1
    fi
    
    # キャッシュをチェック
    local cached=$(get_set_translation_cache "$text" "$lang")
    if [ -n "$cached" ]; then
        echo "$cached"
        return 0
    fi
    
    # リトライループ
    while [ $retry_count -le $max_retries ]; do
        # まずMyMemory APIを試す
        local result=$(translate_with_mymemory "$text" "$lang")
        
        if [ -n "$result" ]; then
            # キャッシュに保存して返す
            get_set_translation_cache "$text" "$lang" "$result"
            echo "$result"
            return 0
        fi
        
        # 次にLibreTranslate APIを試す
        result=$(translate_with_libretranslate "$text" "$lang")
        
        if [ -n "$result" ]; then
            # キャッシュに保存して返す
            get_set_translation_cache "$text" "$lang" "$result"
            echo "$result"
            return 0
        fi
        
        # リトライカウントを増やす
        retry_count=$((retry_count + 1))
        
        # 最後のリトライでなければ少し待つ
        if [ $retry_count -le $max_retries ]; then
            debug_log "DEBUG" "Translation attempt ${retry_count} failed, retrying..."
            sleep 1
        fi
    done
    
    # すべての試行が失敗した場合、元のテキストを返す
    debug_log "ERROR" "All translation attempts failed for text: ${text}"
    echo "$text"
    return 1
}

# 翻訳関数 - 文字列が既に翻訳されていない場合のみ翻訳
translate() {
    local text="$1"
    local lang="${2:-$CURRENT_LANGUAGE}"
    
    # 翻訳要求が現在の言語と英語が同じ場合、または空のテキストの場合は処理をスキップ
    if [ "$lang" = "en" ] || [ -z "$text" ]; then
        echo "$text"
        return 0
    fi
    
    # 翻訳処理
    if echo "$text" | grep -q '\\u'; then
        # ユニコードエスケープシーケンスを含む場合はデコードのみ
        local decoded=$(decode_unicode_awk "$text")
        echo "$decoded"
    else
        # オンライン翻訳を試みる
        local translated=$(translate_text "$text" "$lang")
        echo "$translated"
    fi
}

# メッセージ取得関数
get_message() {
    local key="$1"
    local default="${2:-$key}"
    local lang="${3:-$CURRENT_LANGUAGE}"
    
    # 現在の言語が英語の場合はデフォルト値を返す
    if [ "$lang" = "en" ]; then
        echo "$default"
        return 0
    fi
    
    # メッセージファイルから翻訳を取得
    local message=$(get_message_translation "$key" "$lang" "")
    
    # 翻訳が見つからない場合はデフォルト値を返す
    if [ -z "$message" ]; then
        echo "$default"
        return 1
    fi
    
    # 正常に翻訳が見つかった場合
    echo "$message"
    return 0
}

# 現在の言語設定
set_language() {
    local lang="$1"
    
    # 言語が指定されていない場合は現在の言語を返す
    if [ -z "$lang" ]; then
        echo "$CURRENT_LANGUAGE"
        return 0
    fi
    
    # 言語を設定
    CURRENT_LANGUAGE="$lang"
    debug_log "INFO" "Language set to: ${CURRENT_LANGUAGE}"
    
    return 0
}

# エクスポートする関数
export -f urlencode
export -f decode_unicode_awk
export -f translate_with_mymemory
export -f translate_with_libretranslate
export -f get_set_translation_cache
export -f get_message_translation
export -f translate_text
export -f translate
export -f get_message
export -f set_language
