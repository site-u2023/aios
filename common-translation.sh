#!/bin/sh

# =========================================================
# 📌 OpenWrt用多言語翻訳モジュール (POSIX準拠)
# =========================================================

# バージョン情報
SCRIPT_VERSION="2025-03-28-04"

# オンライン翻訳を有効化
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
decode_unicode() {
    local input="$1"
    
    # Unicodeエスケープシーケンスがない場合はそのまま返す
    if ! echo "$input" | grep -q '\\u[0-9a-fA-F]\{4\}'; then
        echo "$input"
        return 0
    fi
    
    debug_log "DEBUG" "Decoding Unicode escape sequences with AWK"
    
    # AWKでのデコード処理
    awk '
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
        line = $0
        result = ""
        
        while (match(line, /\\u[0-9a-fA-F]{4}/)) {
            pre = substr(line, 1, RSTART-1)
            unicode = substr(line, RSTART, RLENGTH)
            post = substr(line, RSTART+RLENGTH)
            
            code = hex2dec(substr(unicode, 3))
            
            # UTF-8エンコーディング
            if (code <= 0x7f) {
                utf8 = sprintf("%c", code)
            } else if (code <= 0x7ff) {
                utf8 = sprintf("%c%c", 0xc0 + int(code/64), 0x80 + (code%64))
            } else {
                utf8 = sprintf("%c%c%c", 0xe0 + int(code/4096), 0x80 + int((code%4096)/64), 0x80 + (code%64))
            }
            
            result = result pre utf8
            line = post
        }
        
        print result line
    }' <<EOF
$input
EOF
}

# 言語DBファイルの作成関数
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/messages_base.db"
    local output_db="${BASE_DIR}/messages_${target_lang}.db"
    local api_lang=$(get_api_lang_code "$target_lang")
    
    debug_log "DEBUG" "Creating language DB for ${target_lang}"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi
    
    # DBファイル作成 (常に新規作成・上書き)
    : > "$output_db"
    
    # ヘッダー情報を書き込み
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"

SUPPORTED_LANGUAGES="$target_lang"
SUPPORTED_LANGUAGE_$target_lang="$target_lang"

# ${target_lang}用翻訳データベース (自動生成)
# フォーマット: 言語コード|メッセージキー=メッセージテキスト

EOF
    
    # オンライン翻訳が無効なら翻訳せずベースをコピー
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^US|" "$base_db" | sed "s/^US|/$target_lang|/" >> "$output_db"
        return 0
    fi
    
    # USエントリを抽出して翻訳
    local temp_us="${TRANSLATION_CACHE_DIR}/us_entries.tmp"
    grep "^US|" "$base_db" > "$temp_us"
    
    # 全エントリー数をカウント
    local total_entries=$(wc -l < "$temp_us")
    debug_log "DEBUG" "Total entries to translate: ${total_entries}"
    
    # 各行の処理
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
                echo "${target_lang}|${key}=${translated}" >> "$output_db"
                continue
            fi
            
            # オンライン翻訳
            local encoded_text=$(urlencode "$value")
            local translated=""
            
            # ネットワーク接続確認
            if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
                # MyMemory APIで翻訳
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
                    echo "${target_lang}|${key}=${decoded}" >> "$output_db"
                    debug_log "DEBUG" "Added translation for key: ${key}"
                    
                    # APIレート制限対策
                    sleep 1
                else
                    # 翻訳失敗時は原文をそのまま使用
                    echo "${target_lang}|${key}=${value}" >> "$output_db"
                    debug_log "DEBUG" "Translation failed, using original text for key: ${key}"
                fi
            else
                # ネットワーク接続がない場合は原文を使用
                echo "${target_lang}|${key}=${value}" >> "$output_db"
                debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
            fi
        fi
    done < "$temp_us"
    
    # 一時ファイル削除
    rm -f "$temp_us"
    
    debug_log "DEBUG" "Language DB creation completed for ${target_lang} with ${count} entries"
    return 0
}

# country_write関数の拡張 - この関数は元のcountry_write関数に統合する
# (normalize_language実行前に翻訳処理を行うサンプル)
process_language_translation() {
    # 既存の言語コードを取得
    if [ ! -f "${CACHE_DIR}/language.ch" ]; then
        debug_log "DEBUG" "No language code found in cache"
        return 1
    fi
    
    local lang_code=$(cat "${CACHE_DIR}/language.ch")
    debug_log "DEBUG" "Processing translation for language: ${lang_code}"
    
    # USとJP以外の場合のみ翻訳DBを作成
    if [ "$lang_code" != "US" ] && [ "$lang_code" != "JP" ]; then
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
    debug_log "DEBUG" "Translation module initialized successfully"
}

# 初期化実行
init_translation
