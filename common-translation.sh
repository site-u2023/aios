#!/bin/sh

# =========================================================
# 📌 OpenWrt用オンライン翻訳モジュール (POSIX準拠)
# =========================================================

# バージョン情報
SCRIPT_VERSION="2025.03.28-01-00"

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

# AWKを使用したUnicodeデコード
decode_unicode() {
    local input="$1"
    local temp_file="${TRANSLATION_CACHE_DIR}/unicode_decode.tmp"
    
    # Unicodeエスケープシーケンスがない場合はそのまま返す
    if ! echo "$input" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
        echo "$input"
        return 0
    fi
    
    debug_log "DEBUG" "Decoding Unicode escape sequences with AWK"
    echo "$input" > "$temp_file"
    
    # AWKでのデコード処理
    local result=$(awk '
    BEGIN {
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
    }' "$temp_file" 2>/dev/null)
    
    rm -f "$temp_file" 2>/dev/null
    
    if [ -n "$result" ]; then
        echo "$result"
    else
        # デコードに失敗した場合は元の文字列を返す
        debug_log "DEBUG" "Unicode decoding failed, returning original string"
        echo "$input"
    fi
}

# 言語DBを非同期で準備
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
    
    # ネットワーク確認 (ping実行前にマウント確認)
    if ! mountpoint -q /proc || ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "DEBUG" "Network unavailable, cannot create translation cache"
        return 1
    fi
    
    debug_log "DEBUG" "Creating translation cache DB for ${target_lang}"
    
    # US言語のエントリを抽出
    local temp_file="${TRANSLATION_CACHE_DIR}/temp_${target_lang}.txt"
    grep "^US|" "$db_file" > "$temp_file" 2>/dev/null
    
    # 翻訳キャッシュDBを初期化
    : > "$cache_db"
    
    # エントリ数を取得
    local total_entries=$(wc -l < "$temp_file")
    debug_log "DEBUG" "Total entries to translate: ${total_entries}"
    
    # 各行を処理
    local count=0
    while IFS= read -r line; do
        count=$((count + 1))
        
        # キーと値を抽出
        local key=$(echo "$line" | sed -n 's/^US|\([^=]*\)=.*/\1/p')
        local value=$(echo "$line" | sed -n 's/^US|[^=]*=\(.*\)/\1/p')
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            debug_log "DEBUG" "Processing entry ${count}/${total_entries}: ${key}"
            
            # キャッシュキー生成
            local cache_key=$(echo "${key}${value}${api_lang}" | md5sum | cut -d' ' -f1)
            local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_${cache_key}.txt"
            
            # キャッシュを確認
            if [ -f "$cache_file" ]; then
                local translated=$(cat "$cache_file")
                echo "${target_lang}|${key}=${translated}" >> "$cache_db"
                continue
            fi
            
            # オンライン翻訳を試みる
            local translated=""
            
            # MyMemory APIを試す
            local encoded_text=$(urlencode "$value")
            translated=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" 2>/dev/null | \
                sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
            
            # APIからの応答処理
            if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
                # Unicodeエスケープシーケンスをデコード
                local decoded=$(decode_unicode "$translated")
                
                # キャッシュに保存
                mkdir -p "$(dirname "$cache_file")"
                echo "$decoded" > "$cache_file"
                
                # DBに追加
                echo "${target_lang}|${key}=${decoded}" >> "$cache_db"
            else
                # 翻訳失敗時は原文をそのまま使用
                echo "${target_lang}|${key}=${value}" >> "$cache_db"
            fi
            
            # 1秒スリープ（レート制限対策）
            sleep 1
        fi
    done < "$temp_file"
    
    # 一時ファイルを削除
    rm -f "$temp_file"
    
    debug_log "DEBUG" "Translation cache DB created with $(wc -l < "$cache_db") entries"
    return 0
}

# 単一メッセージ翻訳
translate_single_message() {
    local key="$1"
    local value="$2"
    local target_lang="$3"
    local api_lang=$(get_api_lang_code "$target_lang")
    local cache_db="${TRANSLATION_CACHE_DIR}/${target_lang}_messages.db"
    
    # キャッシュキーの生成
    local cache_key=$(echo "${key}${value}${api_lang}" | md5sum | cut -d' ' -f1)
    local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_${cache_key}.txt"
    
    # キャッシュを確認
    if [ -f "$cache_file" ]; then
        debug_log "DEBUG" "Using cached translation for key: ${key}"
        cat "$cache_file"
        return 0
    fi
    
    # オンライン翻訳が無効の場合は原文を返す
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation is disabled, using original text"
        echo "$value"
        return 1
    fi
    
    # ネットワーク確認
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "DEBUG" "Network unavailable for translation"
        echo "$value"
        return 1
    fi
    
    debug_log "DEBUG" "Translating message for key: ${key}"
    
    # キーと値のチェック
    if [ -z "$key" ] || [ -z "$value" ]; then
        debug_log "DEBUG" "Empty key or value, cannot translate"
        echo "$value"
        return 1
    fi
    
    # MyMemory APIで翻訳
    local encoded_text=$(urlencode "$value")
    local translated=$(curl -s -m 3 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" 2>/dev/null | \
        sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
    
    # APIからの応答処理
    if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
        # Unicodeエスケープシーケンスをデコード
        local decoded=$(decode_unicode "$translated")
        
        # キャッシュに保存
        mkdir -p "$(dirname "$cache_file")"
        echo "$decoded" > "$cache_file"
        
        # キャッシュDBに追加
        if [ -f "$cache_db" ]; then
            echo "${target_lang}|${key}=${decoded}" >> "$cache_db"
        else
            mkdir -p "$(dirname "$cache_db")"
            echo "${target_lang}|${key}=${decoded}" > "$cache_db"
        fi
        
        echo "$decoded"
        return 0
    fi
    
    # 翻訳できなかった場合は原文を返す
    debug_log "DEBUG" "Translation failed, using original text for key: ${key}"
    echo "$value"
    return 1
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
    
    # メッセージデータベースのパスを確認
    local db_file="${BASE_DIR}/messages_base.db"
    if [ -f "${CACHE_DIR}/message_db.ch" ]; then
        db_file=$(cat "${CACHE_DIR}/message_db.ch")
    fi
    
    # 現在の言語でメッセージを検索
    if [ -f "$db_file" ]; then
        message=$(grep "^${db_lang}|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
    fi
    
    # 翻訳キャッシュDBの確認
    if [ -z "$message" ] && [ "$actual_lang" != "US" ] && [ "$ONLINE_TRANSLATION_ENABLED" = "yes" ]; then
        # 翻訳キャッシュDBの確認
        local cache_db="${TRANSLATION_CACHE_DIR}/${actual_lang}_messages.db"
        
        if [ -f "$cache_db" ]; then
            message=$(grep "^${actual_lang}|${key}=" "$cache_db" 2>/dev/null | cut -d'=' -f2-)
            if [ -n "$message" ]; then
                debug_log "DEBUG" "Found message in translation cache for key: ${key}"
            fi
        fi
        
        # 英語メッセージを代替として使用
        if [ -z "$message" ] && [ -f "$db_file" ]; then
            local us_message=$(grep "^US|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
            if [ -n "$us_message" ]; then
                debug_log "DEBUG" "No cached translation, using English message for key: ${key}"
                message="$us_message"
            fi
        fi
    fi
    
    # 翻訳結果が見つからない場合はキーをそのまま返す
    if [ -z "$message" ]; then
        debug_log "DEBUG" "No message found for key: ${key}, using key as fallback"
        message="$key"
    else
        # Unicodeエスケープシーケンスをデコード
        if echo "$message" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
            message=$(decode_unicode "$message")
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

# メニューキーの事前翻訳
preload_menu_translations() {
    local target_lang="$1"
    local menu_db="${BASE_DIR}/menu.db"
    local base_db="${BASE_DIR}/messages_base.db"
    
    # メニューキーファイルが存在しなければスキップ
    if [ ! -f "$menu_db" ] || [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Menu or message DB not found, skipping menu preload"
        return 1
    fi
    
    debug_log "DEBUG" "Preloading essential menu translations for ${target_lang}"
    
    # 必要なメニューキーのリスト（重要度順）
    local menu_keys="MAIN_MENU_NAME MENU_EXIT MENU_BACK MENU_REMOVE CONFIG_MAIN_SELECT_PROMPT"
    
    # 各キーを処理
    for key in $menu_keys; do
        # 英語のメッセージを取得
        local us_message=$(grep "^US|${key}=" "$base_db" 2>/dev/null | cut -d'=' -f2-)
        if [ -n "$us_message" ]; then
            debug_log "DEBUG" "Preloading menu key: ${key}"
            translate_single_message "$key" "$us_message" "$target_lang" > /dev/null
            # OpenWrtの制限に合わせて整数値のスリープ
            sleep 1
        fi
    done
    
    debug_log "DEBUG" "Finished preloading essential menu translations"
    return 0
}

# 初期化関数
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # 言語設定の取得
    if [ -f "${CACHE_DIR}/language.ch" ]; then
        local lang=$(cat "${CACHE_DIR}/language.ch")
        if [ "$lang" != "US" ] && [ "$lang" != "JP" ]; then
            debug_log "DEBUG" "Initializing translation for language: ${lang}"
            
            # 重要なメニューキーを先に翻訳
            preload_menu_translations "$lang"
            
            # 全体の翻訳DBを非同期で準備（エラーをリダイレクト）
            prepare_translation_db "$lang" > /dev/null 2>&1 &
        fi
    fi
    
    debug_log "DEBUG" "Online translation module initialized"
}

# 初期化実行
init_translation
