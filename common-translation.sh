#!/bin/sh

# =========================================================
# 📌 OpenWrt用オンライン翻訳モジュール (POSIX準拠)
# =========================================================

# オンライン翻訳を常に有効化
ONLINE_TRANSLATION_ENABLED="yes"

# 翻訳キャッシュディレクトリ
TRANSLATION_CACHE_DIR="${CACHE_DIR}/translations"

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# APIで使用する言語コードを取得
get_api_lang_code() {
    local target_lang="$1"
    local api_lang=""
    
    # luci.ch (APIで使用する言語コード) を優先使用
    if [ -f "${CACHE_DIR}/luci.ch" ]; then
        api_lang=$(cat "${CACHE_DIR}/luci.ch")
        debug_log "DEBUG" "Using language code from luci.ch: ${api_lang}"
        echo "$api_lang"
        return 0
    fi
    
    # luci.chがない場合は小文字変換
    api_lang=$(echo "$target_lang" | tr '[:upper:]' '[:lower:]')
    debug_log "DEBUG" "Using lowercase language code: ${api_lang}"
    echo "$api_lang"
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

# ユニコードエスケープシーケンスをデコード
unicode_decode() {
    local text="$1"
    
    # Unicodeエスケープシーケンス(\uXXXX)をデコード
    echo "$text" | sed 's/\\u\([0-9a-fA-F]\{4\}\)/\\\\\\U\1/g' | xargs -0 printf "%b"
}

# オンライン翻訳実行
translate_text() {
    local source_text="$1"
    local target_lang="$2"
    
    # 空テキスト確認
    if [ -z "$source_text" ]; then
        debug_log "DEBUG" "Empty source text, skipping translation"
        echo "$source_text"
        return 1
    fi
    
    # API用言語コード取得 (luci.chから)
    local api_lang=$(get_api_lang_code "$target_lang")
    
    # キャッシュキー生成
    local cache_key=$(echo "${source_text}${api_lang}" | md5sum | cut -d' ' -f1)
    local cache_dir="${TRANSLATION_CACHE_DIR}/${api_lang}"
    local cache_file="${cache_dir}/${cache_key}"
    
    # キャッシュ確認
    if [ -f "$cache_file" ]; then
        debug_log "DEBUG" "Using cached translation for hash: ${cache_key}"
        cat "$cache_file"
        return 0
    fi
    
    # ネットワーク確認
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "DEBUG" "Network unavailable, using original text"
        echo "$source_text"
        return 1
    fi
    
    debug_log "DEBUG" "Attempting translation to ${api_lang}"
    mkdir -p "$cache_dir"
    
    # 翻訳API呼び出し
    local translation=""
    local encoded_text=$(urlencode "$source_text")
    
    # LibreTranslate API
    debug_log "DEBUG" "Trying LibreTranslate API"
    translation=$(curl -s -m 3 -X POST "https://libretranslate.de/translate" \
        -H "Content-Type: application/json" \
        -d "{\"q\":\"$source_text\",\"source\":\"en\",\"target\":\"$api_lang\",\"format\":\"text\"}" | \
        sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    
    # MyMemory API (バックアップ)
    if [ -z "$translation" ]; then
        debug_log "DEBUG" "Trying MyMemory API"
        translation=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" | \
            sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    fi
    
    # Unicodeエスケープシーケンスをデコード
    if [ -n "$translation" ] && echo "$translation" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
        debug_log "DEBUG" "Decoding Unicode escape sequences"
        translation=$(unicode_decode "$translation")
    fi
    
    # 翻訳成功確認
    if [ -n "$translation" ] && [ "$translation" != "$source_text" ]; then
        debug_log "DEBUG" "Translation successful, caching result"
        echo "$translation" > "$cache_file"
        echo "$translation"
        return 0
    else
        debug_log "DEBUG" "Translation failed, using original text"
        echo "$source_text"
        return 1
    fi
}

# get_message関数 - メッセージキーからテキストを取得し必要に応じて翻訳
get_message() {
    local key="$1"
    local params="$2"
    local message=""
    local db_lang=""
    local actual_lang=""
    
    # DB言語とユーザー言語の取得
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        db_lang=$(cat "${CACHE_DIR}/message.ch")
    else
        db_lang="US"
    fi
    
    if [ -f "${CACHE_DIR}/language.ch" ]; then
        actual_lang=$(cat "${CACHE_DIR}/language.ch")
    else
        actual_lang="$db_lang"
    fi
    
    # データベースからメッセージを検索
    local db_file="${BASE_DIR}/messages_base.db"
    if [ -f "${CACHE_DIR}/message_db.ch" ]; then
        db_file=$(cat "${CACHE_DIR}/message_db.ch")
    fi
    
    # 現在の言語でメッセージを検索
    message=$(grep "^${db_lang}|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
    
    # メッセージが見つからず、オンライン翻訳が有効な場合
    if [ -z "$message" ] && [ "$ONLINE_TRANSLATION_ENABLED" = "yes" ]; then
        # US言語からメッセージを取得
        message=$(grep "^US|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
        
        if [ -n "$message" ] && [ "$actual_lang" != "US" ]; then
            debug_log "DEBUG" "Found English message, attempting translation for key: ${key}"
            
            # 翻訳実行
            local translated_message=$(translate_text "$message" "$actual_lang")
            
            if [ $? -eq 0 ] && [ -n "$translated_message" ] && [ "$translated_message" != "$message" ]; then
                debug_log "DEBUG" "Translation successful for key: ${key}"
                message="$translated_message"
            else
                debug_log "DEBUG" "Translation failed for key: ${key}, using English message"
            fi
        fi
    fi
    
    # メッセージが見つからない場合はキーをそのまま返す
    if [ -z "$message" ]; then
        debug_log "DEBUG" "No message found for key: ${key}, using key as display text"
        message="$key"
    fi
    
    # パラメータ置換処理
    if [ -n "$params" ]; then
        var_name=$(echo "$params" | cut -d'=' -f1)
        var_value=$(echo "$params" | cut -d'=' -f2-)
        
        if [ -n "$var_name" ] && [ -n "$var_value" ]; then
            debug_log "DEBUG" "Replacing placeholder {${var_name}} with value"
            var_value_esc=$(echo "$var_value" | sed 's/[\/&]/\\&/g')
            message=$(echo "$message" | sed "s|{$var_name}|$var_value_esc|g")
        fi
    fi
    
    echo "$message"
}

# 初期化実行
init_translation_cache
debug_log "DEBUG" "Online translation module initialized with status: enabled"
