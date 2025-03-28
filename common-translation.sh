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

# AWKを使用したUnicodeエスケープシーケンスのデコード
decode_unicode_awk() {
    local input="$1"
    local temp_file="${TRANSLATION_CACHE_DIR}/decode_unicode.tmp"
    
    # Unicodeエスケープシーケンスが含まれている場合のみ処理
    if echo "$input" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
        debug_log "DEBUG" "Decoding Unicode escape sequences with AWK"
        
        echo "$input" > "$temp_file"
        
        # AWKを使用したデコード処理
        local decoded=$(awk 'BEGIN {
            for (i = 0; i <= 255; i++)
                ord[sprintf("%c", i)] = i
        }
        
        function hex2dec(hex) {
            dec = 0
            for (i = 1; i <= length(hex); i++) {
                c = substr(hex, i, 1)
                if (c >= "0" && c <= "9") v = ord[c] - ord["0"]
                else if (c >= "a" && c <= "f") v = ord[c] - ord["a"] + 10
                else if (c >= "A" && c <= "F") v = ord[c] - ord["A"] + 10
                dec = dec * 16 + v
            }
            return dec
        }
        
        {
            while (match($0, /\\u[0-9a-fA-F]{4}/)) {
                unicode = substr($0, RSTART, RLENGTH)
                code = hex2dec(substr(unicode, 3))
                
                # UTF-8エンコーディング
                if (code <= 0x7f) {
                    utf8 = sprintf("%c", code)
                } else if (code <= 0x7ff) {
                    utf8 = sprintf("%c%c", 0xc0 + int(code/64), 0x80 + (code%64))
                } else {
                    utf8 = sprintf("%c%c%c", 0xe0 + int(code/4096), 0x80 + int((code%4096)/64), 0x80 + (code%64))
                }
                
                $0 = substr($0, 1, RSTART-1) utf8 substr($0, RSTART+RLENGTH)
            }
            print $0
        }' "$temp_file")
        
        rm -f "$temp_file"
        echo "$decoded"
    else
        # 通常のテキストはそのまま返す
        echo "$input"
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
    
    # US言語のエントリを抽出
    local temp_file="${TRANSLATION_CACHE_DIR}/temp_${target_lang}.txt"
    grep "^US|" "$db_file" > "$temp_file" 2>/dev/null
    
    # DBファイル初期化
    : > "$cache_db"
    
    # 処理する項目数
    local total=$(wc -l < "$temp_file")
    local count=0
    
    # 1行ずつ処理
    while IFS= read -r line; do
        count=$((count + 1))
        
        # キーと値を抽出
        local key=$(echo "$line" | sed -n 's/^US|\([^=]*\)=.*/\1/p')
        local value=$(echo "$line" | sed -n 's/^US|[^=]*=\(.*\)/\1/p')
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            debug_log "DEBUG" "Processing message ${count}/${total}: ${key}"
            
            # 個別のキャッシュファイル名
            local cache_key=$(echo "${key}${value}${api_lang}" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_${cache_key}.txt"
            
            # キャッシュがあればそれを使用
            if [ -f "$cache_file" ]; then
                local translated=$(cat "$cache_file")
                echo "${target_lang}|${key}=${translated}" >> "$cache_db"
                debug_log "DEBUG" "Using cached translation for ${key}"
            else
                # 翻訳API呼び出し
                local translated=""
                
                # MyMemory APIを試す
                local encoded_text=$(urlencode "$value")
                translated=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" | \
                    sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
                
                # 失敗した場合はLibreTranslateを試す
                if [ -z "$translated" ] || [ "$translated" = "$value" ]; then
                    debug_log "DEBUG" "First API failed, trying LibreTranslate for key: ${key}"
                    translated=$(curl -s -m 3 -X POST "https://libretranslate.de/translate" \
                        -H "Content-Type: application/json" \
                        -d "{\"q\":\"$value\",\"source\":\"en\",\"target\":\"$api_lang\",\"format\":\"text\"}" | \
                        sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
                fi
                
                # 翻訳結果の処理
                if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
                    # Unicodeエスケープシーケンスをデコード
                    local decoded=$(decode_unicode_awk "$translated")
                    
                    # キャッシュに保存
                    echo "$decoded" > "$cache_file"
                    
                    # DBにも追加
                    echo "${target_lang}|${key}=${decoded}" >> "$cache_db"
                    debug_log "DEBUG" "Added translated message for key: ${key}"
                else
                    # 翻訳失敗時は原文を使用
                    echo "${target_lang}|${key}=${value}" >> "$cache_db"
                    debug_log "DEBUG" "Translation failed, using original text for key: ${key}"
                fi
                
                # API呼び出しレート制限対策
                sleep 0.2
            fi
        fi
    done < "$temp_file"
    
    # 一時ファイル削除
    rm -f "$temp_file"
    
    debug_log "DEBUG" "Translation cache DB created with $(wc -l < "$cache_db") entries"
    return 0
}

# 単一メッセージの翻訳
translate_single_message() {
    local key="$1"
    local value="$2"
    local target_lang="$3"
    local api_lang=$(get_api_lang_code "$target_lang")
    
    # メニュー項目かどうかをチェック - 優先度の高いものを先に処理
    local is_priority=0
    if echo "$key" | grep -q "^MENU_\|^MSG_"; then
        is_priority=1
    fi
    
    # 優先度が低い場合はスキップすることもできる
    if [ "$is_priority" -eq 0 ] && [ "$TRANSLATE_ALL" != "yes" ]; then
        debug_log "DEBUG" "Skipping non-priority key: ${key}"
        echo "$value"
        return 0
    fi
    
    # キャッシュキーの生成
    local cache_key=$(echo "${key}${value}${api_lang}" | md5sum | cut -d' ' -f1)
    local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_${cache_key}.txt"
    
    # キャッシュファイルがあれば利用
    if [ -f "$cache_file" ]; then
        debug_log "DEBUG" "Using cached translation for single key: ${key}"
        cat "$cache_file"
        return 0
    fi
    
    # ネットワーク確認
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "DEBUG" "Network unavailable for translation"
        echo "$value"
        return 1
    fi
    
    debug_log "DEBUG" "Translating single message for key: ${key}"
    
    # MyMemory APIを試す
    local encoded_text=$(urlencode "$value")
    local translated=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" | \
        sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    
    # 失敗した場合はLibreTranslateを試す
    if [ -z "$translated" ] || [ "$translated" = "$value" ]; then
        debug_log "DEBUG" "First API failed, trying LibreTranslate"
        translated=$(curl -s -m 3 -X POST "https://libretranslate.de/translate" \
            -H "Content-Type: application/json" \
            -d "{\"q\":\"$value\",\"source\":\"en\",\"target\":\"$api_lang\",\"format\":\"text\"}" | \
            sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    fi
    
    # 翻訳結果の処理
    if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
        # Unicodeエスケープシーケンスをデコード
        local decoded=$(decode_unicode_awk "$translated")
        
        # キャッシュに保存
        mkdir -p "${TRANSLATION_CACHE_DIR}"
        echo "$decoded" > "$cache_file"
        
        # キャッシュDBにも追加
        local cache_db="${TRANSLATION_CACHE_DIR}/${target_lang}_messages.db"
        if [ -f "$cache_db" ]; then
            echo "${target_lang}|${key}=${decoded}" >> "$cache_db"
        else
            mkdir -p "$(dirname "$cache_db")"
            echo "${target_lang}|${key}=${decoded}" > "$cache_db"
        fi
        
        echo "$decoded"
        return 0
    fi
    
    # 翻訳失敗時は原文を返す
    debug_log "DEBUG" "Translation failed for single message key: ${key}"
    echo "$value"
    return 1
}

# 現在のメニューキーを同期的に事前翻訳
preload_menu_translations() {
    local target_lang="$1"
    local menu_db="${BASE_DIR}/menu.db"
    local us_db="${BASE_DIR}/messages_base.db"
    local cache_db="${TRANSLATION_CACHE_DIR}/${target_lang}_messages.db"
    local temp_keys="${TRANSLATION_CACHE_DIR}/menu_keys.tmp"
    
    # メニューDBが存在しない場合はスキップ
    if [ ! -f "$menu_db" ]; then
        debug_log "DEBUG" "Menu DB does not exist, skipping preload"
        return 1
    fi
    
    # 現在のメニューキーを抽出
    grep -o "MENU_[A-Z_]*" "$menu_db" | sort | uniq > "$temp_keys"
    
    debug_log "DEBUG" "Preloading menu translations for ${target_lang}"
    local total_keys=$(wc -l < "$temp_keys")
    local processed=0
    
    # 各メニューキーを処理
    while IFS= read -r key; do
        processed=$((processed + 1))
        
        # キャッシュDBに既にある場合はスキップ
        if [ -f "$cache_db" ] && grep -q "^${target_lang}|${key}=" "$cache_db"; then
            debug_log "DEBUG" "Menu key already in cache: ${key}"
            continue
        fi
        
        # 英語メッセージを取得
        local us_message=$(grep "^US|${key}=" "$us_db" 2>/dev/null | cut -d'=' -f2-)
        if [ -n "$us_message" ]; then
            debug_log "DEBUG" "Preloading menu key ${processed}/${total_keys}: ${key}"
            translate_single_message "$key" "$us_message" "$target_lang" > /dev/null
            # 翻訳間隔を空ける
            sleep 0.2
        fi
    done < "$temp_keys"
    
    rm -f "$temp_keys"
    debug_log "DEBUG" "Finished preloading ${processed} menu translations"
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
                debug_log "DEBUG" "No cached translation, translating message for key: ${key}"
                
                # メニューアイテムの場合のみ翻訳（リソース節約のため）
                if echo "$key" | grep -q "^MENU_\|^MSG_"; then
                    message=$(translate_single_message "$key" "$us_message" "$actual_lang")
                else
                    message="$us_message"
                fi
            fi
        fi
    fi
    
    # メッセージが見つからない場合はキーをそのまま返す
    if [ -z "$message" ]; then
        debug_log "DEBUG" "No message found for key: ${key}, using key as display text"
        message="$key"
    fi
    
    # Unicodeエスケープシーケンスをデコード
    if echo "$message" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
        message=$(decode_unicode_awk "$message")
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

# 初期化関数 - メニューアイテムを同期的に先行翻訳
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # 言語設定の取得
    if [ -f "${CACHE_DIR}/language.ch" ]; then
        local lang=$(cat "${CACHE_DIR}/language.ch")
        if [ "$lang" != "US" ] && [ "$lang" != "JP" ]; then
            debug_log "DEBUG" "Initializing translation system for ${lang}"
            
            # メニュー項目の先行翻訳（同期的に実行）
            preload_menu_translations "$lang"
            
            # 残りのメッセージを非同期で準備
            prepare_translation_db "$lang" > /dev/null 2>&1 &
        fi
    fi
    
    debug_log "DEBUG" "Online translation module initialized with status: enabled"
}

# 初期化実行
init_translation
