#!/bin/sh

SCRIPT_VERSION="2025-03-28-12-45"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-28
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
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!

# オンライン翻訳を有効化
ONLINE_TRANSLATION_ENABLED="yes"

# 翻訳キャッシュディレクトリ
TRANSLATION_CACHE_DIR="${BASE_DIR:-/tmp/aios}/translations"

# 翻訳API設定
TRANSLATION_API="${TRANSLATION_API:-mymemory}"
API_LIMIT_FILE="${CACHE_DIR}/api_limit.txt"

# APIステータス表示フラグ
API_STATUS_CHECKED=0

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# ユニコードエスケープシーケンスをデコードする関数（awk使用）
decode_unicode_awk() {
    local text="$1"
    
    # Unicode エスケープがない場合はそのまま返す
    case "$text" in
        *\\u*)
            debug_log "DEBUG" "Decoding Unicode escape sequences with awk"
            ;;
        *)
            echo "$text"
            return 0
            ;;
    esac
    
    # awkを使ってユニコードエスケープをデコード
    echo "$text" | awk '
        BEGIN {
            for(i=0; i<256; i++)
                ord[sprintf("%c",i)] = i;
        }
        
        function decode(s) {
            out = "";
            for(i=1; i<=length(s); i++) {
                c = substr(s, i, 1);
                if(c == "\\") {
                    if(substr(s, i+1, 1) == "u") {
                        hex = substr(s, i+2, 4);
                        i += 5;
                        # Convert hex to UTF-8
                        code = strtonum("0x" hex);
                        if(code <= 0x7F) {
                            out = out sprintf("%c", code);
                        } else if(code <= 0x7FF) {
                            out = out sprintf("%c%c", 0xC0 + int(code/64), 0x80 + (code % 64));
                        } else {
                            out = out sprintf("%c%c%c", 0xE0 + int(code/4096), 0x80 + int((code % 4096)/64), 0x80 + (code % 64));
                        }
                    } else {
                        out = out c;
                        i++;
                    }
                } else {
                    out = out c;
                }
            }
            return out;
        }
        
        {
            print decode($0);
        }
    '
}

process_translation() {
    local key="$1"
    local value="$2"
    
    # メッセージファイルからの翻訳の場合（ユニコードエスケープを含む）
    if echo "$value" | grep -q '\\u'; then
        debug_log "DEBUG" "Processing message with Unicode escapes"
        echo $(decode_unicode_awk "$value")
        return 0
    fi
    
    # それ以外の場合（APIからの翻訳など）はそのまま返す
    echo "$value"
}

# MyMemory APIを使用した翻訳関数の修正
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
    local temp_file="${CACHE_DIR}/mymemory_temp.json"
    
    # wgetでリクエスト実行
    wget -q -T 15 -O "$temp_file" "$url" 2>/dev/null
    
    # 失敗した場合
    if [ $? -ne 0 ] || [ ! -s "$temp_file" ]; then
        debug_log "WARNING" "MyMemory API request failed"
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
    fi
    
    rm -f "$temp_file"
    debug_log "WARNING" "MyMemory API translation failed"
    return 1
}

# LibreTranslate APIを使用した翻訳関数の修正
translate_with_libretranslate() {
    local text="$1"
    local lang="$2"
    
    # Langdirはja_JPのような形式からja形式に変換
    local lang_short=$(echo "$lang" | cut -d'_' -f1)
    
    debug_log "DEBUG" "Using LibreTranslate API with wget to translate to ${lang_short}"
    
    # エンドポイントの指定（動作確認済み）
    local endpoint="https://translate.argosopentech.com/translate"
    
    # URLエンコード
    local encoded_text=$(urlencode "$text")
    
    # POSTデータ作成
    local post_data="q=${encoded_text}&source=en&target=${lang_short}&format=text"
    local post_file="${CACHE_DIR}/libretranslate_post.txt"
    local temp_file="${CACHE_DIR}/libretranslate_temp.json"
    
    # POSTデータをファイルに書き込み
    echo "$post_data" > "$post_file"
    
    # wgetでPOSTリクエスト実行
    wget -q -T 15 --post-file="$post_file" -O "$temp_file" "$endpoint" 2>/dev/null
    
    # 失敗した場合
    if [ $? -ne 0 ] || [ ! -s "$temp_file" ]; then
        debug_log "WARNING" "LibreTranslate API request failed"
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

# APIの使用制限ステータスを確認
check_api_limit() {
    local api_name="$1"
    local now=$(date +%s)
    local show_log="${2:-1}"  # デフォルトは表示する
    
    if [ -f "$API_LIMIT_FILE" ]; then
        local api_data=$(grep "^${api_name}:" "$API_LIMIT_FILE" 2>/dev/null)
        
        if [ -n "$api_data" ]; then
            local limit_until=$(echo "$api_data" | cut -d: -f2)
            local remaining=$(( limit_until - now ))
            
            if [ $remaining -gt 0 ]; then
                if [ "$show_log" = "1" ]; then
                    local hours=$(( remaining / 3600 ))
                    local minutes=$(( (remaining % 3600) / 60 ))
                    local seconds=$(( remaining % 60 ))
                    debug_log "INFO" "${api_name} API quota exceeded: ${hours}h ${minutes}m ${seconds}s remaining until reset"
                fi
                return 1
            else
                # 制限が解除されたので、ファイルから削除
                sed -i "/^${api_name}:/d" "$API_LIMIT_FILE" 2>/dev/null
                if [ "$show_log" = "1" ]; then
                    debug_log "INFO" "${api_name} API quota has been reset and is now available"
                fi
            fi
        elif [ "$show_log" = "1" ]; then
            debug_log "INFO" "${api_name} API is available for translation requests"
        fi
    elif [ "$show_log" = "1" ]; then
        debug_log "INFO" "${api_name} API has no recorded usage limits"
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
    if ! check_api_limit "mymemory" 0; then
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
    if ! check_api_limit "libretranslate" 0; then
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

translate_text() {
    local text="$1"
    local lang="$2"
    local retry_count=0
    local max_retries=2  # 最大リトライ回数
    local tried_apis=""
    local current_api=""
    
    debug_log "DEBUG" "Translating text to ${lang}: ${text}"
    
    # APIが未選択の場合は選択する
    if [ -z "$TRANSLATION_API" ] || [ "$TRANSLATION_API" != "mymemory" ] && [ "$TRANSLATION_API" != "libretranslate" ]; then
        TRANSLATION_API="mymemory"  # デフォルト
        debug_log "DEBUG" "No API selected, defaulting to ${TRANSLATION_API}"
    fi
    
    # リトライループ
    while [ $retry_count -lt $max_retries ]; do
        current_api="$TRANSLATION_API"
        debug_log "DEBUG" "Try #$((retry_count + 1)) with $current_api API"
        
        # 既に試したAPIかどうかチェック
        if echo "$tried_apis" | grep -q "$current_api"; then
            debug_log "DEBUG" "API $current_api already tried, switching APIs"
            # 別のAPIに切り替え
            if [ "$current_api" = "mymemory" ]; then
                TRANSLATION_API="libretranslate"
            else
                TRANSLATION_API="mymemory"
            fi
        else
            # このAPIはまだ試していない
            tried_apis="${tried_apis} ${current_api}"
            
            local result=""
            if [ "$current_api" = "mymemory" ]; then
                result=$(translate_with_mymemory "$text" "$lang")
                if [ -n "$result" ]; then
                    debug_log "DEBUG" "MyMemory translation successful"
                    echo "$result"
                    return 0
                else
                    debug_log "INFO" "Switching to LibreTranslate API after MyMemory API failure"
                    TRANSLATION_API="libretranslate"
                fi
            elif [ "$current_api" = "libretranslate" ]; then
                result=$(translate_with_libretranslate "$text" "$lang")
                if [ -n "$result" ]; then
                    debug_log "DEBUG" "LibreTranslate translation successful"
                    echo "$result"
                    return 0
                else
                    debug_log "INFO" "Switching to MyMemory API after LibreTranslate API failure"
                    TRANSLATION_API="mymemory"
                fi
            fi
        fi
        
        # 両方のAPIを試したか確認
        if echo "$tried_apis" | grep -q "mymemory" && echo "$tried_apis" | grep -q "libretranslate"; then
            debug_log "DEBUG" "Both APIs tried in this cycle"
            retry_count=$((retry_count + 1))
            
            if [ $retry_count -lt $max_retries ]; then
                debug_log "DEBUG" "Retrying translation after a short pause"
                sleep 2  # 少し待ってからリトライ
                tried_apis=""  # リセットして再試行
            fi
        fi
    done
    
    # すべての試行が失敗
    debug_log "ERROR" "All translation attempts failed for text: ${text}"
    debug_log "INFO" "Internet connectivity test: $(ping -c 1 -W 2 8.8.8.8 2>&1)"
    debug_log "INFO" "DNS resolution test: $(nslookup api.mymemory.translated.net 2>&1 | grep -E "Address|error")"
    
    return 1
}

check_all_apis() {
    if [ "$API_STATUS_CHECKED" = "0" ]; then
        API_STATUS_CHECKED=1
        
        debug_log "INFO" "Checking all translation APIs status"
        
        # オンライン翻訳が無効の場合
        if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
            debug_log "INFO" "Online translation is disabled in configuration"
            # API無効の場合は normalize_language を呼び出し
            normalize_language
            return 1
        fi
        
        # ネットワーク接続確認
        if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
            debug_log "WARNING" "Network is unavailable - cannot use online translation APIs"
            # ネットワーク接続できない場合は normalize_language を呼び出し
            normalize_language
            return 1
        fi
        
        # オフライン翻訳の状態を確認
        local api_lang=$(get_api_lang_code)
        local dictionary_file="${BASE_DIR}/dictionary_${api_lang}.txt"
        
        if [ -f "$dictionary_file" ]; then
            local dict_entries=$(grep -c "=" "$dictionary_file" 2>/dev/null)
            debug_log "INFO" "Offline dictionary for ${api_lang} is available with ${dict_entries} entries"
        else
            debug_log "INFO" "No offline dictionary found for ${api_lang}"
        fi
        
        # 各APIの状態を確認
        local mymemory_available=0
        local libretranslate_available=0
        
        check_api_limit "mymemory" 1 && mymemory_available=1
        check_api_limit "libretranslate" 1 && libretranslate_available=1
        
        # 使用するAPIを決定
        if [ $mymemory_available -eq 1 ]; then
            TRANSLATION_API="mymemory"
            debug_log "INFO" "Selected MyMemory as primary translation API"
        elif [ $libretranslate_available -eq 1 ]; then
            TRANSLATION_API="libretranslate"
            debug_log "INFO" "Selected LibreTranslate as primary translation API"
        else
            debug_log "WARNING" "No translation APIs are available - using default US language"
            # APIが使えない場合は normalize_language を呼び出し
            normalize_language
            return 1
        fi
        
        return 0
    else
        # 2回目以降は簡易チェックのみで詳細なログは出力しない
        if check_api_limit "mymemory" 0; then
            TRANSLATION_API="mymemory"
            return 0
        elif check_api_limit "libretranslate" 0; then
            TRANSLATION_API="libretranslate"
            return 0
        else
            # すべてのAPIが利用不可の場合は normalize_language 呼び出し
            debug_log "WARNING" "All translation APIs are unavailable, using default language"
            normalize_language
            return 1
        fi
    fi
}

# オンライン翻訳が利用可能か確認
is_online_translation_available() {
    # オンライン翻訳が有効で、ネットワークが利用可能で、少なくとも1つのAPIが使用可能
    if [ "$ONLINE_TRANSLATION_ENABLED" = "yes" ] && ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        if check_api_limit "mymemory" 0 || check_api_limit "libretranslate" 0; then
            return 0
        fi
    fi
    return 1
}

create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/messages_base.db"
    local output_db="${BASE_DIR}/messages_${target_lang}.db"
    local api_lang=$(get_api_lang_code)
    local temp_file="${TRANSLATION_CACHE_DIR}/translations_temp.txt"
    local api_failure_count=0
    local max_api_failures=3  # 連続失敗の許容回数
    
    debug_log "DEBUG" "Creating language DB for ${target_lang} with API language code ${api_lang}"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "ERROR" "Base message DB not found at ${base_db}"
        normalize_language
        return 1
    fi
    
    # すべてのAPIの状態を確認
    check_all_apis
    
    # オンライン翻訳が利用可能か確認
    if ! is_online_translation_available; then
        debug_log "WARNING" "Online translation unavailable. Skipping DB creation for ${target_lang}"
        normalize_language
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
    
    # 全エントリを抽出
    : > "$temp_file"
    local entry_count=$(grep -c "^US|" "$base_db")
    debug_log "DEBUG" "Processing ${entry_count} translation entries using ${TRANSLATION_API} API"
    
    # 処理時間を計測開始
    local start_time=$(date +%s)
    local successful_translations=0
    
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
                successful_translations=$((successful_translations + 1))
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
                    successful_translations=$((successful_translations + 1))
                    
                    # API失敗カウンターをリセット
                    api_failure_count=0
                else
                    # 翻訳失敗時は原文をそのまま使用
                    echo "${target_lang}|${key}=${value}" >> "$temp_file"
                    debug_log "DEBUG" "Translation failed for: ${key}, using original text"
                    
                    # API失敗カウンターを増やす
                    api_failure_count=$((api_failure_count + 1))
                    
                    # 連続した失敗が多すぎる場合は中断
                    if [ $api_failure_count -ge $max_api_failures ]; then
                        debug_log "WARNING" "Too many consecutive API failures (${api_failure_count}). Aborting translation."
                        break
                    fi
                fi
            fi
        fi
    done
    
    # 処理時間を計測終了
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 成功した翻訳が少なすぎる場合はDBを作成しない
    if [ "$successful_translations" -lt 10 ]; then
        debug_log "WARNING" "Too few successful translations (${successful_translations}). Removing incomplete DB."
        rm -f "$output_db"
        rm -f "$temp_file"
        
        # 翻訳に失敗した場合はnormalize_language呼び出し
        debug_log "INFO" "Falling back to default language"
        normalize_language
        
        return 1
    fi
    
    # 結果をDBに追加
    cat "$temp_file" >> "$output_db"
    rm -f "$temp_file"
    
    debug_log "INFO" "Language DB creation completed in ${duration} seconds with ${successful_translations} translations"
    
    # 最終的に使用したAPIを表示
    debug_log "INFO" "Translation completed using ${TRANSLATION_API} API"
    
    return 0
}

process_language_translation() {
    # 既存の言語コードを取得
    if [ ! -f "${CACHE_DIR}/language.ch" ]; then
        debug_log "ERROR" "No language code found at ${CACHE_DIR}/language.ch"
        return 1
    fi
    
    local lang_code=$(cat "${CACHE_DIR}/language.ch")
    debug_log "INFO" "Processing translation for language: ${lang_code}"
    
    # 言語DBの存在確認
    local lang_db="${BASE_DIR}/messages_${lang_code}.db"
    
    # 言語DBが存在しない場合または強制更新フラグがある場合のみ作成
    if [ ! -f "$lang_db" ] || [ -f "${CACHE_DIR}/force_translation_update" ]; then
        debug_log "INFO" "Attempting to create translation DB for language: ${lang_code}"
        
        # create_language_dbが失敗した場合（APIが使えない場合など）は
        # normalize_language 呼び出し
        if create_language_db "$lang_code"; then
            debug_log "INFO" "Translation DB created successfully for ${lang_code}"
        else
            debug_log "WARNING" "Translation DB creation failed, using default language"
            normalize_language
        fi
        
        # 強制更新フラグがあれば削除
        [ -f "${CACHE_DIR}/force_translation_update" ] && rm -f "${CACHE_DIR}/force_translation_update"
    else
        debug_log "INFO" "Translation DB already exists for language: ${lang_code}"
    fi
    
    return 0
}

# 初期化関数
init_translation() {
    # キャッシュディレクトリ初期化
    init_translation_cache
    
    # 言語翻訳処理を実行
    process_language_translation
    
    debug_log "INFO" "Translation module initialized - using available APIs and fallback when needed"
    return 0
}

# デバッグ用：APIの制限状態を表示
show_api_limit_status() {
    debug_log "INFO" "===== Translation API Status ====="
    
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "INFO" "Online translation is disabled in configuration"
        return 0
    fi
    
    # ネットワーク接続確認
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "WARNING" "Network is unavailable - cannot use online translation APIs"
        return 1
    fi
    
    local now=$(date +%s)
    
    if [ ! -f "$API_LIMIT_FILE" ]; then
        debug_log "INFO" "No API usage limits are currently set - all APIs should be available"
    else
        while IFS=: read -r api_name limit_until; do
            if [ -n "$api_name" ] && [ -n "$limit_until" ]; then
                local remaining=$(( limit_until - now ))
                
                if [ $remaining -gt 0 ]; then
                    local hours=$(( remaining / 3600 ))
                    local minutes=$(( (remaining % 3600) / 60 ))
                    local seconds=$(( remaining % 60 ))
                    debug_log "INFO" "${api_name}: Quota exceeded - Reset in ${hours}h ${minutes}m ${seconds}s"
                else
                    debug_log "INFO" "${api_name}: Quota available"
                fi
            fi
        done < "$API_LIMIT_FILE"
    fi
    
    # 使用するAPIを表示
    if is_online_translation_available; then
        debug_log "INFO" "Using ${TRANSLATION_API} API for translation"
    else
        debug_log "WARNING" "No translation APIs are currently available"
        debug_log "INFO" "Will use default language (US) if needed"
    fi
    
    debug_log "INFO" "=================================="
    return 0
}

# 初期化は外部から呼び出す
if [ "${1:-}" = "init" ]; then
    init_translation
elif [ "${1:-}" = "status" ]; then
    show_api_limit_status
fi
