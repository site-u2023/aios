#!/bin/sh

# オンライン翻訳の有効/無効フラグ（デフォルトでは無効）
ONLINE_TRANSLATION_ENABLED="${ONLINE_TRANSLATION_ENABLED:-no}"

# 翻訳キャッシュ初期化
init_translation_cache() {
    mkdir -p "${CACHE_DIR}/translations"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# 高信頼性翻訳関数
translate_text() {
    local source_text="$1"
    local target_lang="$2"
    local cache_key=$(echo "${source_text}${target_lang}" | md5sum | cut -d' ' -f1)
    local cache_dir="${CACHE_DIR}/translations/${target_lang}"
    local cache_file="${cache_dir}/${cache_key}"
    
    # キャッシュ確認
    if [ -f "$cache_file" ]; then
        debug_log "DEBUG" "Using cached translation for hash: ${cache_key}"
        cat "$cache_file"
        return 0
    fi
    
    # ネットワーク確認（1秒タイムアウト）
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "DEBUG" "Network unavailable, skipping translation"
        echo "$source_text"
        return 1
    fi
    
    debug_log "DEBUG" "Attempting translation of text to ${target_lang}"
    mkdir -p "$cache_dir"
    
    # 翻訳結果変数
    local translation=""
    
    # マッピングテーブル（message.chの言語コードをAPIの言語コードに変換）
    case "$target_lang" in
        "JP") api_lang="ja" ;;
        "US") api_lang="en" ;;
        "EG") api_lang="ar" ;;
        "ES") api_lang="es" ;;
        *) api_lang="$target_lang" ;;
    esac
    
    # API 1: LibreTranslate公開インスタンス
    if [ -z "$translation" ]; then
        translation=$(curl -s -m 3 -X POST "https://libretranslate.de/translate" \
            -H "Content-Type: application/json" \
            -d "{\"q\":\"$source_text\",\"source\":\"en\",\"target\":\"$api_lang\",\"format\":\"text\"}" | \
            sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    fi
    
    # API 2: MyMemory API (1,000 words/day)
    if [ -z "$translation" ]; then
        translation=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=$source_text&langpair=en|$api_lang" | \
            sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    fi
    
    # 翻訳成功確認
    if [ -n "$translation" ]; then
        debug_log "DEBUG" "Translation successful, caching result"
        echo "$translation" > "$cache_file"
        echo "$translation"
        return 0
    else
        debug_log "DEBUG" "Translation failed, returning original text"
        echo "$source_text"
        return 1
    fi
}

# URL安全にエンコードする関数
urlencode() {
    local string="$1"
    local length="${#string}"
    local i=0
    
    for i in $(seq 0 $((length-1))); do
        local c="${string:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "%s" "$c" ;;
            *) printf "%%%02X" "'$c" ;;
        esac
    done
}

# 既存のget_message関数を拡張した実装
get_message_with_translation() {
    local key="$1"
    local params="$2"  # パラメータ文字列
    local lang="${lang:-US}" 
    local db_file="${db_file:-${BASE_DIR}/messages_base.db}" 
    local message=""

    # メッセージDBがダウンロードされた後の言語設定処理
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang=$(cat "${CACHE_DIR}/message.ch")
    elif [ -n "$ACTIVE_LANGUAGE" ]; then
        lang="$ACTIVE_LANGUAGE"
    fi
    
    # インメモリメッセージから検索
    into_memory_message
    if [ -n "$MSG_MEMORY" ]; then
        # 言語固有のメモリ内メッセージを検索
        message=$(echo "$MSG_MEMORY" | grep "^${lang}|${key}=" 2>/dev/null | cut -d'=' -f2-)
    fi

    # メッセージが見つからなかった場合かつDBファイルが存在する場合は検索
    if [ -z "$message" ] && [ -f "$db_file" ]; then
        # 現在の言語でDBファイルを検索
        message=$(grep "^${lang}|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
    fi
    
    # --- ここからオンライン翻訳機能の追加部分 ---
    # 言語が英語以外で、メッセージが見つからず、オンライン翻訳が有効な場合
    if [ -z "$message" ] && [ "$lang" != "US" ] && [ "$ONLINE_TRANSLATION_ENABLED" = "yes" ]; then
        # 英語メッセージを取得
        local english_message=$(grep "^US|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
        
        if [ -n "$english_message" ]; then
            debug_log "DEBUG" "Message found in English, attempting online translation"
            # 翻訳を実行
            message=$(translate_text "$english_message" "$lang")
            
            # 翻訳に成功した場合（翻訳結果が英語と異なる場合）
            if [ $? -eq 0 ] && [ -n "$message" ] && [ "$message" != "$english_message" ]; then
                debug_log "DEBUG" "Successfully translated message for key: $key"
            else
                # 翻訳に失敗した場合は英語を使用
                message="$english_message"
                debug_log "DEBUG" "Translation failed, using English message"
            fi
        fi
    fi
    # --- オンライン翻訳機能の追加部分終了 ---
    
    # 言語固有のメッセージが見つからない場合、英語をチェック
    if [ -z "$message" ] && [ "$lang" != "US" ]; then
        message=$(grep "^US|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
    fi
    
    # それでもメッセージが見つからない場合はキーをそのまま返す
    if [ -z "$message" ]; then
        debug_log "WARNING" "Message not found for key: ${key}"
        message="$key"
    fi
    
    # パラメータ置換処理
    if [ -n "$params" ]; then
        var_name=$(echo "$params" | cut -d'=' -f1)
        var_value=$(echo "$params" | cut -d'=' -f2-)
        
        if [ -n "$var_name" ] && [ -n "$var_value" ]; then
            debug_log "DEBUG" "Replacing placeholder {$var_name} with value"
            var_value_esc=$(echo "$var_value" | sed 's/[\/&]/\\&/g')
            message=$(echo "$message" | sed "s|{$var_name}|$var_value_esc|g")
        fi
    fi
    
    echo "$message"
    return 0
}

# オンライン翻訳機能の初期化
init_online_translation() {
    # 設定ファイルからフラグを読み込む（なければデフォルトでオフ）
    if [ -f "${CACHE_DIR}/config/translation.conf" ]; then
        . "${CACHE_DIR}/config/translation.conf"
    else
        # デフォルト設定
        ONLINE_TRANSLATION_ENABLED="no"
        mkdir -p "${CACHE_DIR}/config"
        echo "ONLINE_TRANSLATION_ENABLED=\"no\"" > "${CACHE_DIR}/config/translation.conf"
    fi
    
    # 翻訳キャッシュ初期化
    init_translation_cache
    
    debug_log "INFO" "Online translation feature is ${ONLINE_TRANSLATION_ENABLED}"
}

# オンライン翻訳を有効化する関数
enable_online_translation() {
    ONLINE_TRANSLATION_ENABLED="yes"
    mkdir -p "${CACHE_DIR}/config"
    echo "ONLINE_TRANSLATION_ENABLED=\"yes\"" > "${CACHE_DIR}/config/translation.conf"
    debug_log "INFO" "Online translation feature enabled"
}

# オンライン翻訳を無効化する関数
disable_online_translation() {
    ONLINE_TRANSLATION_ENABLED="no"
    mkdir -p "${CACHE_DIR}/config"
    echo "ONLINE_TRANSLATION_ENABLED=\"no\"" > "${CACHE_DIR}/config/translation.conf"
    debug_log "INFO" "Online translation feature disabled"
}

# 翻訳キャッシュをクリアする関数
clear_translation_cache() {
    rm -rf "${CACHE_DIR}/translations"
    mkdir -p "${CACHE_DIR}/translations"
    debug_log "INFO" "Translation cache cleared"
}
