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

# 言語DBファイルの作成関数
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/messages_base.db"
    local output_db="${BASE_DIR}/messages_${target_lang}.db"
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
                continue
            fi
            
            # オンライン翻訳
            local encoded_text=$(urlencode "$value")
            local translated=""
            
            # ネットワーク接続確認
            if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
                debug_log "DEBUG" "Translating text for key: ${key}"
                
                # MyMemory APIで翻訳（wgetを使用）
                local temp_file="${CACHE_DIR}/translation_temp.txt"
                wget -q -T 5 -O "$temp_file" "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" 2>/dev/null
                
                if [ -s "$temp_file" ]; then
                    translated=$(grep -o '"translatedText":"[^"]*"' "$temp_file" | sed 's/"translatedText":"//;s/"$//')
                    rm -f "$temp_file"
                    
                    # APIからの応答処理
                    if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
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
                else
                    # 翻訳リクエスト失敗時も原文を使用
                    echo "${target_lang}|${key}=${value}" >> "$output_db"
                    debug_log "DEBUG" "Translation request failed, using original text for key: ${key}"
                    rm -f "$temp_file"
                fi
                
                # APIレート制限対策
                #sleep 1
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
    if [ ! -f "${CACHE_DIR}/language.ch" ]; then
        debug_log "DEBUG" "No language code found in cache"
        return 1
    fi
    
    local lang_code=$(cat "${CACHE_DIR}/language.ch")
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
