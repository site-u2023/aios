#!/bin/sh

SCRIPT_VERSION="2025-03-29-03-40"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-29
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
### =========================================================

# 基本定数の設定 
BASE_WGET="wget --no-check-certificate -q"
DEBUG_MODE="${DEBUG_MODE:-false}"
BIN_PATH="$(readlink -f "$0")"
BIN_DIR="$(dirname "$BIN_PATH")"
BIN_FILE="$(basename "$BIN_PATH")"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# オンライン翻訳を有効化
ONLINE_TRANSLATION_ENABLED="yes"

# API設定
API_TIMEOUT="${API_TIMEOUT:-5}"
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"
TRANSLATION_CACHE_DIR="${BASE_DIR}/translations"
CURRENT_API=""
API_LIST="google" # API_LIST="mymemory"

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# 言語コード取得（APIのため）
get_api_lang_code() {
    # message.chからの言語コードを使用
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        local api_lang=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "Using language code from message.ch: ${api_lang}"
        printf "%s\n" "$api_lang"
        return 0
    fi
    
    # message.chがない場合はデフォルトで英語
    debug_log "DEBUG" "No message.ch found, defaulting to en"
    printf "en\n"
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
    
    printf "%s\n" "$encoded"
}

# Google APIを使用した翻訳関数（IPv4/IPv6対応）
translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    
    debug_log "DEBUG" "Starting Google Translate API request (optimized)"
    
    # ネットワーク接続状態ファイルが存在しない場合は接続確認を実行
    if [ ! -f "$ip_check_file" ]; then
        check_network_connectivity
    fi
    
    # ネットワーク接続状態に基づいてwgetオプションを設定
    if [ -f "$ip_check_file" ]; then
        local network_type=$(cat "$ip_check_file")
        
        case "$network_type" in
            "v4")
                wget_options="-4"  # IPv4のみ使用
                ;;
            "v6")
                wget_options="-6"  # IPv6のみ使用
                ;;
            "v4v6")
                # IPv4を優先使用
                wget_options="-4"
                ;;
        esac
    fi
    
    # URLエンコード
    local encoded_text=$(urlencode "$text")
    local temp_file="${TRANSLATION_CACHE_DIR}/google_response.tmp"
    
    # ディレクトリが存在しなければ作成
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null
    
    # リトライループ
    while [ $retry_count -le $API_MAX_RETRIES ]; do
        if [ $retry_count -gt 0 ]; then
            # デュアルスタック環境でIPバージョンを切り替え
            if [ "$network_type" = "v4v6" ]; then
                if [ "$wget_options" = "-4" ]; then
                    wget_options="-6"
                else
                    wget_options="-4"
                fi
            fi
            sleep 1
        fi
        
        # 大きな文字列の場合はPOSTメソッドを使用
        if [ ${#encoded_text} -gt 1500 ]; then
            # POSTリクエストを使用して大きなテキストを送信
            $BASE_WGET $wget_options -T $API_TIMEOUT -O "$temp_file" \
                 --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
                 --post-data="sl=${source_lang}&tl=${target_lang}&q=${encoded_text}" \
                 "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t" 2>/dev/null
        else
            # 通常のGETリクエスト
            $BASE_WGET $wget_options -T $API_TIMEOUT -O "$temp_file" \
                 --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
                 "https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}" 2>/dev/null
        fi
        
        local wget_status=$?
        
        # レスポンスチェック
        if [ -s "$temp_file" ]; then
            if grep -q '\[\[\["' "$temp_file"; then
                local translated=$(sed 's/\[\[\["//;s/",".*//;s/\\u003d/=/g;s/\\u003c/</g;s/\\u003e/>/g;s/\\u0026/\&/g;s/\\"/"/g' "$temp_file")
                
                if [ -n "$translated" ]; then
                    rm -f "$temp_file"
                    echo "$translated"
                    return 0
                fi
            fi
        fi
        
        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        
        # 一定時間待機してからリトライ
        [ $retry_count -le $API_MAX_RETRIES ] && sleep 2
    done
    
    return 1
}


# フォールバック廃止版：translate_text関数
translate_text() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local result=""
    
    debug_log "DEBUG" "Starting translation using single API mode"
    
    # 設定されたAPIを取得（カンマ区切りの最初の項目のみ使用）
    local api=$(echo "$API_LIST" | cut -d ',' -f1)
    CURRENT_API="$api"
    
    debug_log "DEBUG" "Selected API: $CURRENT_API"
    
    case "$CURRENT_API" in          
        google)
            debug_log "DEBUG" "Using Google Translate API"
            result=$(translate_with_google "$text" "$source_lang" "$target_lang")
            
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                debug_log "DEBUG" "Google translation completed"
                echo "$result"
                return 0
            else
                debug_log "DEBUG" "Google translation failed"
                return 1
            fi
            ;;
            
        *)
            debug_log "DEBUG" "Unknown or invalid API specified: $CURRENT_API"
            return 1
            ;;
    esac
}

# 効率的な言語データベース作成関数
create_language_db_optimized() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local current_api=""
    
    debug_log "DEBUG" "Creating language DB (optimized) for target ${target_lang} with API language code ${api_lang}"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi
    
    # DBファイル作成 (常に新規作成・上書き)
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
EOF
    
    # オンライン翻訳が無効なら翻訳せず置換するだけ
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" | sed "s/^${DEFAULT_LANGUAGE}|/${api_lang}|/" >> "$output_db"
        return 0
    fi
    
    # 翻訳処理開始
    printf "\n"
    
    # API_LISTから初期APIを決定
    local first_api=$(echo "$API_LIST" | cut -d',' -f1)
    case "$first_api" in
        google) current_api="Google Translate API" ;;
        *) current_api="Unknown API" ;;
    esac
    
    # まず前処理としてキャッシュ状態をチェック
    debug_log "DEBUG" "Pre-checking cache status for all entries"
    local total_entries=$(grep "^${DEFAULT_LANGUAGE}|" "$base_db" | wc -l)
    local cached_entries=0
    local uncached_entries=0
    local uncached_keys=""
    local uncached_values=""
    
    # キャッシュのプリチェック - これにより全体の処理効率が向上
    grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出
        local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
        local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")
        
        # キャッシュキー生成
        local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
        local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
        
        if [ -f "$cache_file" ]; then
            # キャッシュ見つかった - 直接DBに書き込み
            local translated=$(cat "$cache_file")
            printf "%s|%s=%s\n" "$api_lang" "$key" "$translated" >> "$output_db"
            cached_entries=$((cached_entries + 1))
        else
            # キャッシュなし - 翻訳要対象リストに追加
            if [ -n "$uncached_keys" ]; then
                uncached_keys="${uncached_keys}|#SEP#|${key}"
                uncached_values="${uncached_values}|#SEP#|${value}"
            else
                uncached_keys="${key}"
                uncached_values="${value}"
            fi
            uncached_entries=$((uncached_entries + 1))
        fi
    done
    
    debug_log "DEBUG" "Cache check completed: ${cached_entries} cached, ${uncached_entries} need translation"
    
    # キャッシュ済みだけの場合は早期終了
    if [ $uncached_entries -eq 0 ]; then
        debug_log "DEBUG" "All entries found in cache, no translation needed"
        return 0
    fi
    
    # 未キャッシュ項目を翻訳する処理
    if [ -n "$uncached_keys" ] && [ -n "$uncached_values" ]; then
        start_spinner "$(color blue "Using API: $current_api (Processing ${uncached_entries} entries)")"
        
        # キーと値のペアをIFSで分割して処理
        IFS='|#SEP#|'
        set -- $uncached_keys
        
        # 各キーに対応する値を取得するためのカウンタ
        local i=1
        for key in "$@"; do
            # 対応する値を取得
            local value=$(echo "$uncached_values" | cut -d'|#SEP#|' -f$i)
            
            debug_log "DEBUG" "Translating key: ${key}"
            
            # 翻訳処理
            local translated=""
            local result=$(translate_with_google_optimized "$value" "$DEFAULT_LANGUAGE" "$api_lang" 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                translated="$result"
                
                # キャッシュキー生成
                local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
                local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
                
                # キャッシュに保存
                mkdir -p "$(dirname "$cache_file")"
                printf "%s\n" "$translated" > "$cache_file"
                
                # DBに追加
                printf "%s|%s=%s\n" "$api_lang" "$key" "$translated" >> "$output_db"
            else
                # 翻訳失敗の場合はオリジナルを使用
                printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
                debug_log "DEBUG" "Translation failed for key: ${key}, using original"
            fi
            
            # 進捗表示更新（10項目ごと）
            if [ $((i % 10)) -eq 0 ]; then
                stop_spinner "Translating... $i/$uncached_entries" "info"
                start_spinner "$(color blue "Using API: $current_api (Processing ${uncached_entries} entries)")"
            fi
            
            i=$((i + 1))
        done
        unset IFS
        
        stop_spinner "Translation completed" "success"
    fi
    
    debug_log "DEBUG" "Language DB creation completed for ${api_lang} using optimized process"
    return 0
}

# 言語データベース作成関数
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local temp_file="${TRANSLATION_CACHE_DIR}/translation_output.tmp"
    local cleaned_translation=""
    local current_api=""
    local ip_check_file="${CACHE_DIR}/network.ch"
    
    # バッチ処理用変数
    local batch_size=10  # 一度に処理する行数
    local batch_texts=""
    local batch_keys=""
    local separator="|||SPLIT|||"  # バッチ内テキスト区切り文字
    local total_count=0
    local batch_count=0
    
    debug_log "DEBUG" "Creating language DB with batch processing for target ${target_lang} with API language code ${api_lang}"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi
    
    # DBファイル作成 (常に新規作成・上書き)
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y.%m.%d-%H-%M)"
EOF
    
    # オンライン翻訳が無効なら翻訳せず置換するだけ
    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" | sed "s/^${DEFAULT_LANGUAGE}|/${api_lang}|/" >> "$output_db"
        return 0
    fi
    
    # 翻訳処理開始
    printf "\n"
    
    # ネットワーク接続状態を確認
    if [ ! -f "$ip_check_file" ]; then
        debug_log "DEBUG" "Network status file not found, checking connectivity"
        check_network_connectivity
    fi
    
    # ネットワーク接続状態を取得
    local network_status=""
    if [ -f "$ip_check_file" ]; then
        network_status=$(cat "$ip_check_file")
        debug_log "DEBUG" "Network status: ${network_status}"
    else
        debug_log "DEBUG" "Could not determine network status"
    fi
    
    # API_LISTから初期APIを決定
    local first_api=$(echo "$API_LIST" | cut -d',' -f1)
    case "$first_api" in
        google) current_api="Google Translate API" ;;
        *) current_api="Unknown API" ;;
    esac
    
    debug_log "DEBUG" "Initial API based on API_LIST priority: $current_api"
    
    # スピナーを開始し、使用中のAPIを表示
    start_spinner "$(color blue "Using API: $current_api (Batch Processing)")"
    
    # 翻訳が必要な総行数を取得
    total_count=$(grep "^${DEFAULT_LANGUAGE}|" "$base_db" | wc -l)
    debug_log "DEBUG" "Total entries to translate: $total_count"
    
    # 一時ファイルを作成
    > "$temp_file"
    
    # 言語エントリを抽出
    grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do
        # キーと値を抽出
        local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
        local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")
        
        # バッチに追加
        if [ -n "$batch_texts" ]; then
            batch_texts="${batch_texts}${separator}${value}"
            batch_keys="${batch_keys}${separator}${key}"
        else
            batch_texts="$value"
            batch_keys="$key"
        fi
        
        batch_count=$((batch_count + 1))
        
        # バッチサイズに達したか、最後の要素の場合に処理
        if [ $batch_count -ge $batch_size ] || [ $((total_count - batch_count)) -lt 1 ]; then
            debug_log "DEBUG" "Processing batch of $batch_count items"
            
            # キャッシュをまとめて確認
            local need_translation=false
            local translations=""
            
            # バッチ内の各テキストをカンマ区切りで処理
            IFS="$separator" 
            set -- $batch_texts
            local i=1
            local uncached_texts=""
            local uncached_keys=""
            local translation_results=""
            
            for value in "$@"; do
                # 対応するキーを取得
                local key=$(echo "$batch_keys" | cut -d"$separator" -f$i)
                
                # キャッシュキー生成
                local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
                local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
                
                # キャッシュを確認
                if [ -f "$cache_file" ]; then
                    local cached_translation=$(cat "$cache_file")
                    # APIから取得した言語コードを使用
                    printf "%s|%s=%s\n" "$api_lang" "$key" "$cached_translation" >> "$output_db"
                    debug_log "DEBUG" "Using cached translation for key: ${key}"
                    
                    if [ -n "$translation_results" ]; then
                        translation_results="${translation_results}${separator}${cached_translation}"
                    else
                        translation_results="${cached_translation}"
                    fi
                else
                    # キャッシュに無い場合は翻訳が必要
                    need_translation=true
                    if [ -n "$uncached_texts" ]; then
                        uncached_texts="${uncached_texts}${separator}${value}"
                        uncached_keys="${uncached_keys}${separator}${key}"
                    else
                        uncached_texts="${value}"
                        uncached_keys="${key}"
                    fi
                fi
                
                i=$((i+1))
            done
            unset IFS
            
            # 翻訳が必要な場合のみAPIを呼び出し
            if [ "$need_translation" = "true" ] && [ -n "$uncached_texts" ]; then
                debug_log "DEBUG" "Translating uncached items with API"
                
                # ネットワーク接続確認
                if [ -n "$network_status" ] && [ "$network_status" != "" ]; then
                    # APIリストを解析して順番に試行
                    local api
                    local batch_result=""
                    for api in $(echo "$API_LIST" | tr ',' ' '); do
                        case "$api" in
                            google)
                                # 表示APIとの不一致チェック（表示更新）
                                if [ "$current_api" != "Google Translate API" ]; then
                                    stop_spinner "Switching API" "info"
                                    current_api="Google Translate API"
                                    start_spinner "$(color blue "Using API: $current_api (Batch Processing)")"
                                    debug_log "DEBUG" "Switching to Google Translate API"
                                fi
                                
                                batch_result=$(translate_batch_with_google "$uncached_texts" "$DEFAULT_LANGUAGE" "$api_lang" 2>/dev/null)
                                
                                if [ $? -eq 0 ] && [ -n "$batch_result" ]; then
                                    cleaned_translation="$batch_result"
                                    break
                                else
                                    debug_log "DEBUG" "Google Translate API failed for batch"
                                fi
                                ;;
                        esac
                    done
                    
                    # 翻訳結果処理
                    if [ -n "$cleaned_translation" ]; then
                        # 翻訳結果を分割して処理
                        IFS="$separator"
                        set -- $uncached_keys
                        local j=1
                        for key in "$@"; do
                            # バッチ翻訳の結果から対応する部分を抽出（実際のAPIレスポース形式に合わせて調整）
                            local translated_part=$(echo "$cleaned_translation" | cut -d"$separator" -f$j)
                            if [ -z "$translated_part" ]; then
                                translated_part=$(echo "$uncached_texts" | cut -d"$separator" -f$j)
                            fi
                            
                            # キャッシュキー生成と保存
                            local value_to_cache=$(echo "$uncached_texts" | cut -d"$separator" -f$j)
                            local cache_key=$(printf "%s%s%s" "$key" "$value_to_cache" "$api_lang" | md5sum | cut -d' ' -f1)
                            local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
                            
                            # キャッシュに保存
                            mkdir -p "$(dirname "$cache_file")"
                            printf "%s\n" "$translated_part" > "$cache_file"
                            
                            # APIから取得した言語コードを使用してDBに追加
                            printf "%s|%s=%s\n" "$api_lang" "$key" "$translated_part" >> "$output_db"
                            
                            j=$((j+1))
                        done
                        unset IFS
                    else
                        # 翻訳失敗時は原文をそのまま使用
                        IFS="$separator"
                        set -- $uncached_keys
                        local j=1
                        for key in "$@"; do
                            local original_text=$(echo "$uncached_texts" | cut -d"$separator" -f$j)
                            printf "%s|%s=%s\n" "$api_lang" "$key" "$original_text" >> "$output_db"
                            debug_log "DEBUG" "All translation APIs failed, using original text for key: ${key}"
                            j=$((j+1))
                        done
                        unset IFS
                    fi
                else
                    # ネットワーク接続がない場合は原文を使用
                    IFS="$separator"
                    set -- $uncached_keys
                    local j=1
                    for key in "$@"; do
                        local original_text=$(echo "$uncached_texts" | cut -d"$separator" -f$j)
                        printf "%s|%s=%s\n" "$api_lang" "$key" "$original_text" >> "$output_db"
                        debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
                        j=$((j+1))
                    done
                    unset IFS
                fi
            fi
            
            # バッチをクリアして次のバッチに備える
            batch_texts=""
            batch_keys=""
            batch_count=0
        fi
    done
    
    # スピナー停止
    stop_spinner "Translation completed" "success"
    
    # 翻訳処理終了
    debug_log "DEBUG" "Language DB creation completed for ${api_lang} using batch processing"
    return 0
}

# 翻訳情報を表示する関数
display_detected_translation() {
    # 引数の取得
    local show_success_message="${1:-false}"  # 成功メッセージ表示フラグ
    
    # 言語コードの取得
    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
    else
        lang_code="$DEFAULT_LANGUAGE"
    fi
    
    local source_lang="$DEFAULT_LANGUAGE"  # ソース言語
    local source_db="message_${source_lang}.db"
    local target_db="message_${lang_code}.db"
    
    debug_log "DEBUG" "Displaying translation information for language code: ${lang_code}"
    
    # 同じ言語でDB作成をスキップする場合もチェック
    if [ "$source_lang" = "$lang_code" ] && [ "$source_db" = "$target_db" ]; then
        debug_log "DEBUG" "Source and target languages are identical: ${lang_code}"
    fi
    
    # 成功メッセージの表示（オプション）
    if [ "$show_success_message" = "true" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATION_SUCCESS")")"
    fi
    
    # 翻訳ソース情報表示
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_ORIGINAL" "info=$source_db")")"
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_CURRENT" "info=$target_db")")"
    
    # 言語コード情報表示
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SOURCE" "info=$source_lang")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_CODE" "info=$lang_code")")"
    
    debug_log "DEBUG" "Translation information display completed for ${lang_code}"
}

# 言語翻訳処理
process_language_translation() {
    # 言語コードの取得
    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "Processing translation for language code: ${lang_code}"
    else
        debug_log "DEBUG" "No language code found in message.ch, using default"
        lang_code="$DEFAULT_LANGUAGE"
    fi
    
    # 選択言語とデフォルト言語の一致フラグ
    local is_default_language=false
    if [ "$lang_code" = "$DEFAULT_LANGUAGE" ]; then
        is_default_language=true
        debug_log "DEBUG" "Selected language is the default language (${lang_code})"
    fi
    
    # デフォルト言語以外の場合のみ翻訳DBを作成
    if [ "$is_default_language" = "false" ]; then
        # 翻訳DBを作成
        create_language_db "$lang_code"
        
        # 翻訳情報表示（成功メッセージなし）
        display_detected_translation "false"
    else
        # デフォルト言語の場合はDB作成をスキップ
        debug_log "DEBUG" "Skipping DB creation for default language: ${lang_code}"
        
        # 表示は1回だけ行う（静的フラグを使用）
        if [ "${DEFAULT_LANG_DISPLAYED:-false}" = "false" ]; then
            debug_log "DEBUG" "Displaying information for default language once"
            display_detected_translation "false"
            # 表示済みフラグを設定（POSIX準拠）
            DEFAULT_LANG_DISPLAYED=true
        else
            debug_log "DEBUG" "Default language info already displayed, skipping"
        fi
    fi
    
    printf "\n"
    
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

# スクリプト初期化（自動実行）
# init_translation
