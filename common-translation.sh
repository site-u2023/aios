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

# 言語コード取得
get_api_lang_code() {
    local openwrt_code="$1"
    local api_code=""
    
    # luci.chからの言語コードを優先
    if [ -f "${CACHE_DIR}/luci.ch" ]; then
        api_code=$(cat "${CACHE_DIR}/luci.ch")
        debug_log "DEBUG" "Using language code from luci.ch: ${api_code}"
        echo "$api_code"
        return 0
    fi
    
    # 小文字変換
    api_code=$(echo "$openwrt_code" | tr '[:upper:]' '[:lower:]')
    debug_log "DEBUG" "Using lowercase language code: ${api_code}"
    echo "$api_code"
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

# Unicodeエスケープシーケンスをデコードする関数
decode_unicode() {
    local text="$1"
    local result=""
    local temp_file="${TRANSLATION_CACHE_DIR}/unicode_decode_temp.txt"
    
    # OpenWrt環境に対応した最もシンプルな方法で実装
    # printf + echo でデコードを試みる
    printf "%b" "$(echo "$text" | sed 's/\\u/\\\\u/g')" > "$temp_file" 2>/dev/null
    
    if [ -s "$temp_file" ]; then
        result=$(cat "$temp_file")
        rm -f "$temp_file"
        echo "$result"
    else
        # デコードに失敗した場合は元のテキストを返す
        debug_log "DEBUG" "Unicode decoding failed, returning original text"
        echo "$text"
    fi
}

# 言語DB全体を一括翻訳
prepare_translation_db() {
    local target_lang="$1"
    local api_lang=$(get_api_lang_code "$target_lang")
    local db_file="${BASE_DIR}/messages_base.db"
    local cache_db="${TRANSLATION_CACHE_DIR}/${target_lang}_messages.db"
    
    # キャッシュDBが既に存在する場合はスキップ
    if [ -f "$cache_db" ]; then
        debug_log "DEBUG" "Translation cache DB exists for ${target_lang}"
        return 0
    fi
    
    # ネットワーク確認
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "DEBUG" "Network unavailable, cannot create translation cache"
        return 1
    fi
    
    debug_log "DEBUG" "Creating translation cache DB for ${target_lang}"
    
    # 一時ファイル
    local temp_db="${TRANSLATION_CACHE_DIR}/temp_${target_lang}.db"
    
    # US言語のエントリを抽出
    grep "^US|" "$db_file" > "$temp_db" 2>/dev/null
    
    # 各行を処理して翻訳＋DBに追加
    : > "$cache_db"  # 一旦DBを空にする
    
    # 翻訳バッチ作成 - 一度に全メッセージを翻訳
    local messages_file="${TRANSLATION_CACHE_DIR}/${target_lang}_messages.txt"
    local keys_file="${TRANSLATION_CACHE_DIR}/${target_lang}_keys.txt"
    
    # メッセージと対応するキーを抽出
    sed -n 's/^US|\([^=]*\)=\(.*\)/\2/p' "$temp_db" > "$messages_file"
    sed -n 's/^US|\([^=]*\)=.*/\1/p' "$temp_db" > "$keys_file"
    
    # 行数確認
    local line_count=$(wc -l < "$messages_file")
    debug_log "DEBUG" "Processing ${line_count} messages for translation"
    
    # 各行を処理
    local i=1
    while [ $i -le $line_count ]; do
        local key=$(sed -n "${i}p" "$keys_file")
        local value=$(sed -n "${i}p" "$messages_file")
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            debug_log "DEBUG" "Translating key: ${key}"
            
            # APIで翻訳
            local translated=$(curl -s -m 3 -X POST "https://libretranslate.de/translate" \
                -H "Content-Type: application/json" \
                -d "{\"q\":\"$value\",\"source\":\"en\",\"target\":\"$api_lang\",\"format\":\"text\"}" | \
                sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
            
            # バックアップAPI
            if [ -z "$translated" ]; then
                local encoded_text=$(urlencode "$value")
                translated=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" | \
                    sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
            fi
            
            # 翻訳に成功した場合のみDB登録
            if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
                # エスケープシーケンスが含まれる場合はデコード
                if echo "$translated" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
                    translated=$(decode_unicode "$translated")
                fi
                
                echo "${target_lang}|${key}=${translated}" >> "$cache_db"
                debug_log "DEBUG" "Added translation for key: ${key}"
            else
                # 翻訳失敗時は原文を使用
                echo "${target_lang}|${key}=${value}" >> "$cache_db"
                debug_log "DEBUG" "Using original text for key: ${key}"
            fi
        fi
        
        i=$((i + 1))
    done
    
    # 一時ファイルを削除
    rm -f "$temp_db" "$messages_file" "$keys_file"
    
    debug_log "DEBUG" "Translation cache DB created for ${target_lang} with $(grep -c "" "$cache_db") entries"
    return 0
}

# メッセージ取得関数
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
    
    # 翻訳キャッシュDBの確認
    if [ -z "$message" ] && [ "$actual_lang" != "US" ] && [ "$ONLINE_TRANSLATION_ENABLED" = "yes" ]; then
        # 翻訳キャッシュDBがなければ作成を試みる
        local cache_db="${TRANSLATION_CACHE_DIR}/${actual_lang}_messages.db"
        
        if [ ! -f "$cache_db" ]; then
            debug_log "DEBUG" "Translation cache DB not found for ${actual_lang}, creating it now"
            prepare_translation_db "$actual_lang"
        fi
        
        # キャッシュDBからメッセージを検索
        if [ -f "$cache_db" ]; then
            message=$(grep "^${actual_lang}|${key}=" "$cache_db" 2>/dev/null | cut -d'=' -f2-)
            if [ -n "$message" ]; then
                debug_log "DEBUG" "Found message in translation cache DB: ${key}"
            fi
        fi
        
        # キャッシュになければ英語から単一メッセージ翻訳
        if [ -z "$message" ]; then
            local us_message=$(grep "^US|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
            if [ -n "$us_message" ]; then
                debug_log "DEBUG" "No cached translation, using English message for key: ${key}"
                message="$us_message"
                
                # メニューキャッシュに追加（次回以降の参照用）
                if [ -f "$cache_db" ]; then
                    echo "${actual_lang}|${key}=${message}" >> "$cache_db"
                    debug_log "DEBUG" "Added English message to cache for future reference: ${key}"
                fi
            fi
        fi
    fi
    
    # メッセージが見つからない場合はキーをそのまま返す
    if [ -z "$message" ]; then
        debug_log "DEBUG" "No message found for key: ${key}, using key as display text"
        message="$key"
    else
        # Unicodeエスケープシーケンスをデコード
        if echo "$message" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
            message=$(decode_unicode "$message")
            debug_log "DEBUG" "Decoded Unicode escape sequences in message for key: ${key}"
        fi
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

# 初期化関数
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # 言語設定の取得
    if [ -f "${CACHE_DIR}/language.ch" ]; then
        local lang=$(cat "${CACHE_DIR}/language.ch")
        if [ "$lang" != "US" ] && [ "$lang" != "JP" ]; then
            debug_log "DEBUG" "Starting translation database preparation for ${lang}"
            prepare_translation_db "$lang" &
        fi
    fi
    
    debug_log "DEBUG" "Online translation module initialized with status: enabled"
}

# 初期化実行
init_translation
