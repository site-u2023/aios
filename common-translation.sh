#!/bin/sh

SCRIPT_VERSION="2025-04-08-00-10"

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

# 並列処理設定
TRANSLATION_PARALLEL_ENABLED="yes"
TRANSLATION_MAX_JOBS="4"  # 並列ジョブ数を4に設定

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

# URL安全エンコード関数（seqを使わない最適化版）
urlencode() {
    local string="$1"
    local encoded=""
    local i=0
    local c=""
    local length=${#string}
    
    while [ $i -lt $length ]; do
        c="${string:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded="${encoded}$c" ;;
            " ") encoded="${encoded}%20" ;;
            *) encoded="${encoded}$(printf "%%%02X" "'$c")" ;;
        esac
        
        i=$((i + 1))
    done
    
    printf "%s\n" "$encoded"
}

# URL安全エンコード関数
BAK_urlencode() {
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

# Google APIを使用した翻訳関数（高速化版）
translate_with_google() {
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"
    local ip_check_file="${CACHE_DIR}/network.ch"
    local wget_options=""
    local retry_count=0
    
    debug_log "DEBUG" "Starting Google Translate API request" "true"
    
    # ネットワーク接続状態を一度だけ確認
    [ ! -f "$ip_check_file" ] && check_network_connectivity
    
    # ネットワーク接続状態に基づいてwgetオプションを設定
    if [ -f "$ip_check_file" ]; then
        local network_type=$(cat "$ip_check_file")
        
        case "$network_type" in
            "v4") wget_options="-4" ;;
            "v6") wget_options="-6" ;;
            "v4v6") wget_options="-4" ;;
        esac
    fi
    
    # URLエンコード
    local encoded_text=$(urlencode "$text")
    local temp_file="${TRANSLATION_CACHE_DIR}/google_response.tmp"
    
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null
    
    # リトライループ
    while [ $retry_count -le $API_MAX_RETRIES ]; do
        [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ] && \
            wget_options=$([ "$wget_options" = "-4" ] && echo "-6" || echo "-4")
        
        # APIリクエスト送信 - 待機時間なしのシンプル版
        $BASE_WGET $wget_options -T $API_TIMEOUT --tries=1 -O "$temp_file" \
             --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
             "https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}" 2>/dev/null
        
        # 効率的なレスポンスチェック
        if [ -s "$temp_file" ] && grep -q '\[\[\["' "$temp_file"; then
            local translated=$(sed 's/\[\[\["//;s/",".*//;s/\\u003d/=/g;s/\\u003c/</g;s/\\u003e/>/g;s/\\u0026/\&/g;s/\\"/"/g' "$temp_file")
            
            if [ -n "$translated" ]; then
                rm -f "$temp_file"
                printf "%s\n" "$translated"
                return 0
            fi
        fi
        
        rm -f "$temp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
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

# 言語データベース作成関数（並列処理対応版）
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local temp_file="${TRANSLATION_CACHE_DIR}/translation_output.tmp"
    local cleaned_translation=""
    local current_api=""
    local ip_check_file="${CACHE_DIR}/network.ch"
    local parallel="${2:-$TRANSLATION_PARALLEL_ENABLED}"  # グローバル変数をデフォルトに
    local max_jobs="${3:-$TRANSLATION_MAX_JOBS}"         # グローバル変数をデフォルトに
    local start_time=$(date +%s)
    
    debug_log "DEBUG" "Creating language DB for target ${target_lang} with API language code ${api_lang}"
    
    # ベースDBファイル確認
    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi
    
    # DBファイル作成 (常に新規作成・上書き)
    cat > "$output_db" << EOF
SCRIPT_VERSION="$(date +%Y-%m-%d-%H-%M)"
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
    
    # 並列処理モードの場合
    if [ "$parallel" = "yes" ] || [ "$parallel" = "true" ]; then
        debug_log "INFO" "Using parallel translation mode with ${max_jobs} jobs" "true"
        
        # 一時ディレクトリ設定
        local temp_dir="${TRANSLATION_CACHE_DIR}/parallel"
        mkdir -p "$temp_dir"
        rm -f "$temp_dir/part_"* "$temp_dir/output_"* 2>/dev/null
        
        # 入力DBを分割（キーを抽出）
        local keys_file="${temp_dir}/keys.txt"
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" > "${temp_dir}/all_entries.txt"
        
        # 全エントリ数を取得して分割数を計算
        local total_entries=$(wc -l < "${temp_dir}/all_entries.txt")
        local entries_per_job=$(( (total_entries + max_jobs - 1) / max_jobs ))
        
        # スピナーを開始し、使用中のAPIと並列処理情報を表示
        start_spinner "$(color blue "Using API: $current_api (Parallel mode: ${max_jobs} jobs)")"
        
        # splitの代わりに手動でファイル分割
        local line_count=0
        local file_count=1
        local current_file="${temp_dir}/part_${file_count}"
        
        # ファイル初期化
        > "$current_file"
        
        # 全エントリを分割
        while IFS= read -r line; do
            # 現在のパートファイルに行を追加
            printf "%s\n" "$line" >> "$current_file"
            line_count=$((line_count + 1))
            
            # 分割サイズに達したら次のファイルを作成
            if [ $line_count -ge $entries_per_job ]; then
                line_count=0
                file_count=$((file_count + 1))
                current_file="${temp_dir}/part_${file_count}"
                > "$current_file"
            fi
        done < "${temp_dir}/all_entries.txt"
        
        # 各部分を並列処理
        local job_count=0
        for part in "$temp_dir"/part_*; do
            local part_name=$(basename "$part")
            local output_part="$temp_dir/output_${part_name}"
            
            # バックグラウンド処理開始
            (
                debug_log "DEBUG" "Processing part: $part_name" "true"
                
                # このパート内のすべての行を処理
                while IFS= read -r line; do
                    # キーと値を抽出
                    local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
                    local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")
                    
                    if [ -n "$key" ] && [ -n "$value" ]; then
                        # キャッシュキー生成
                        local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
                        local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
                        
                        # キャッシュを確認
                        if [ -f "$cache_file" ]; then
                            local translated=$(cat "$cache_file")
                            # APIから取得した言語コードを使用
                            printf "%s|%s=%s\n" "$api_lang" "$key" "$translated" >> "$output_part"
                            debug_log "DEBUG" "Using cached translation for key: ${key}"
                            continue
                        fi
                        
                        # ネットワーク接続確認
                        if [ -n "$network_status" ] && [ "$network_status" != "" ]; then
                            local result=""
                            local cleaned_translation=""
                            
                            # APIリストを解析して順番に試行
                            local api
                            for api in $(echo "$API_LIST" | tr ',' ' '); do
                                case "$api" in
                                    google)
                                        result=$(translate_with_google "$value" "$DEFAULT_LANGUAGE" "$api_lang" 2>/dev/null)
                                        
                                        if [ $? -eq 0 ] && [ -n "$result" ]; then
                                            cleaned_translation="$result"
                                            break
                                        else
                                            debug_log "DEBUG" "Google Translate API failed for key: ${key}"
                                        fi
                                        ;;
                                esac
                            done
                            
                            # 翻訳結果処理
                            if [ -n "$cleaned_translation" ]; then
                                # 基本的なエスケープシーケンスの処理
                                local decoded="$cleaned_translation"
                                
                                # キャッシュに保存
                                mkdir -p "$(dirname "$cache_file")"
                                printf "%s\n" "$decoded" > "$cache_file"
                                
                                # APIから取得した言語コードを使用してDBに追加
                                printf "%s|%s=%s\n" "$api_lang" "$key" "$decoded" >> "$output_part"
                            else
                                # 翻訳失敗時は原文をそのまま使用
                                printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_part"
                                debug_log "DEBUG" "All translation APIs failed, using original text for key: ${key}" 
                            fi
                        else
                            # ネットワーク接続がない場合は原文を使用
                            printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_part"
                            debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
                        fi
                    fi
                done < "$part"
                
                debug_log "DEBUG" "Completed part: $part_name" "true"
            ) &
            
            # ジョブカウントを更新
            job_count=$((job_count + 1))
            
            # 最大同時実行数を制御
            if [ "$job_count" -ge "$max_jobs" ]; then
                wait -n  # いずれかのジョブが完了するまで待機
                job_count=$((job_count - 1))
            fi
        done
        
        # すべてのバックグラウンドジョブが完了するまで待機
        wait
        
        # 結果のマージとソート
        cat "${temp_dir}"/output_* >> "$output_db"
        
        # 一時ファイルのクリーンアップ
        rm -rf "$temp_dir"
        
    else
        # 通常処理モード (既存コードと同じ)
        # スピナーを開始し、使用中のAPIを表示
        start_spinner "$(color blue "Using API: $current_api")"
        
        # 言語エントリを抽出
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" | while IFS= read -r line; do
            # キーと値を抽出
            local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
            local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")
            
            if [ -n "$key" ] && [ -n "$value" ]; then
                # キャッシュキー生成
                local cache_key=$(printf "%s%s%s" "$key" "$value" "$api_lang" | md5sum | cut -d' ' -f1)
                local cache_file="${TRANSLATION_CACHE_DIR}/${api_lang}_${cache_key}.txt"
                
                # キャッシュを確認
                if [ -f "$cache_file" ]; then
                    local translated=$(cat "$cache_file")
                    # APIから取得した言語コードを使用
                    printf "%s|%s=%s\n" "$api_lang" "$key" "$translated" >> "$output_db"
                    debug_log "DEBUG" "Using cached translation for key: ${key}"
                    continue
                fi
                
                # ネットワーク接続確認
                if [ -n "$network_status" ] && [ "$network_status" != "" ]; then
                    
                    # APIリストを解析して順番に試行
                    local api
                    for api in $(echo "$API_LIST" | tr ',' ' '); do
                        case "$api" in
                            google)
                                # 表示APIとの不一致チェック（表示更新）
                                if [ "$current_api" != "Google Translate API" ]; then
                                    stop_spinner "Switching API" "info"
                                    current_api="Google Translate API"
                                    start_spinner "$(color blue "Using API: $current_api")"
                                    debug_log "DEBUG" "Switching to Google Translate API"
                                fi
                                
                                result=$(translate_with_google "$value" "$DEFAULT_LANGUAGE" "$api_lang" 2>/dev/null)
                                
                                if [ $? -eq 0 ] && [ -n "$result" ]; then
                                    cleaned_translation="$result"
                                    break
                                else
                                    debug_log "DEBUG" "Google Translate API failed for key: ${key}"
                                fi
                                ;;
                        esac
                    done
                    
                    # 翻訳結果処理
                    if [ -n "$cleaned_translation" ]; then
                        # 基本的なエスケープシーケンスの処理
                        local decoded="$cleaned_translation"
                        
                        # キャッシュに保存
                        mkdir -p "$(dirname "$cache_file")"
                        printf "%s\n" "$decoded" > "$cache_file"
                        
                        # APIから取得した言語コードを使用してDBに追加
                        printf "%s|%s=%s\n" "$api_lang" "$key" "$decoded" >> "$output_db"
                    else
                        # 翻訳失敗時は原文をそのまま使用
                        printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
                        debug_log "DEBUG" "All translation APIs failed, using original text for key: ${key}" 
                    fi
                else
                    # ネットワーク接続がない場合は原文を使用
                    printf "%s|%s=%s\n" "$api_lang" "$key" "$value" >> "$output_db"
                    debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
                fi
            fi
        done
    fi
    
    # スピナー停止
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    stop_spinner "Translation completed in ${duration} seconds" "success"
    
    # 翻訳処理終了
    debug_log "DEBUG" "Language DB creation completed for ${api_lang}"
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

# 言語翻訳処理（並列処理オプション追加）
process_language_translation() {
    local parallel="${1:-$TRANSLATION_PARALLEL_ENABLED}"
    local max_jobs="${2:-$TRANSLATION_MAX_JOBS}"
    
    # CPU情報を読み取り、並列ジョブ数を設定
    if [ -f "${CACHE_DIR}/cpu_core.ch" ]; then
        local cpu_cores=$(cat "${CACHE_DIR}/cpu_core.ch")
        if [ -n "$cpu_cores" ] && [ "$cpu_cores" -gt 0 ]; then
            max_jobs="$cpu_cores"
            debug_log "DEBUG" "Reading CPU cores from config: ${max_jobs}"
        fi
    fi
    
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
        # 翻訳DBを作成（並列処理オプション付き）
        create_language_db "$lang_code" "$parallel" "$max_jobs"
        
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
    
    # CPU情報を読み取り、並列ジョブ数を設定
    if [ -f "${CACHE_DIR}/cpu_core.ch" ]; then
        local cpu_cores=$(cat "${CACHE_DIR}/cpu_core.ch")
        if [ -n "$cpu_cores" ] && [ "$cpu_cores" -gt 0 ]; then
            TRANSLATION_MAX_JOBS="$cpu_cores"
            debug_log "INFO" "Using CPU cores from config: ${TRANSLATION_MAX_JOBS}"
        fi
    fi
    
    # 言語翻訳処理を実行（並列処理を有効化）
    process_language_translation "$TRANSLATION_PARALLEL_ENABLED" "$TRANSLATION_MAX_JOBS"
    
    debug_log "DEBUG" "Translation module initialized with parallel processing (${TRANSLATION_MAX_JOBS} cores)"
}

# スクリプト初期化（自動実行）
# init_translation
