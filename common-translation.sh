#!/bin/sh

# =========================================================
# 📌 OpenWrt用多言語翻訳モジュール (POSIX準拠)
# =========================================================

# バージョン情報
SCRIPT_VERSION="2025-03-28-11-25"

# オンライン翻訳を有効化
ONLINE_TRANSLATION_ENABLED="yes"

# 翻訳キャッシュディレクトリ
TRANSLATION_CACHE_DIR="${BASE_DIR:-/tmp/aios}/translations"

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
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

# 一括翻訳処理 - 複数のテキストをまとめて翻訳
batch_translate() {
    local input_file="$1"
    local target_lang="$2"
    local api_lang="$3"
    local output_file="$4"
    local batch_size=5  # 一度に処理する行数
    local batch_count=0
    local total_lines=$(wc -l < "$input_file")
    local current_line=0
    local temp_file="${TRANSLATION_CACHE_DIR}/batch_temp.txt"
    local result_file="${TRANSLATION_CACHE_DIR}/batch_result.txt"
    
    debug_log "DEBUG" "Starting batch translation of ${total_lines} entries"
    
    # バッチごとに処理
    while [ $current_line -lt $total_lines ]; do
        # 一時ファイルをクリア
        : > "$temp_file"
        : > "$result_file"
        
        # 現在のバッチサイズを計算
        local remaining=$((total_lines - current_line))
        local current_batch_size=$batch_size
        if [ $remaining -lt $batch_size ]; then
            current_batch_size=$remaining
        fi
        
        # バッチのエントリを抽出
        sed -n "$((current_line + 1)),$((current_line + current_batch_size))p" "$input_file" > "$temp_file"
        
        # 各行を処理
        while IFS= read -r line; do
            local key=$(echo "$line" | sed -n 's/^US|\([^=]*\)=.*/\1/p')
            local value=$(echo "$line" | sed -n 's/^US|[^=]*=\(.*\)/\1/p')
            
            if [ -n "$key" ] && [ -n "$value" ]; then
                # キャッシュキー生成
                local cache_key=$(echo "${key}${value}${api_lang}" | md5sum | cut -d' ' -f1)
                local cache_file="${TRANSLATION_CACHE_DIR}/${target_lang}_${cache_key}.txt"
                
                # キャッシュを確認
                if [ -f "$cache_file" ]; then
                    local translated=$(cat "$cache_file")
                    echo "${target_lang}|${key}=${translated}" >> "$result_file"
                else
                    # キャッシュになければオンライン翻訳を実行
                    local encoded_text=$(urlencode "$value")
                    local translated=""
                    
                    if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
                        debug_log "DEBUG" "Translating text for key: ${key}"
                        
                        # MyMemory APIで翻訳
                        translated=$(curl -s -m 5 "https://api.mymemory.translated.net/get?q=${encoded_text}&langpair=en|${api_lang}" 2>/dev/null | \
                            sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p')
                        
                        # APIからの応答処理
                        if [ -n "$translated" ] && [ "$translated" != "$value" ]; then
                            # Unicodeエスケープシーケンスをデコード
                            local decoded=$(decode_unicode "$translated")
                            
                            # キャッシュに保存
                            mkdir -p "$(dirname "$cache_file")"
                            echo "$decoded" > "$cache_file"
                            
                            # 結果に追加
                            echo "${target_lang}|${key}=${decoded}" >> "$result_file"
                            debug_log "DEBUG" "Added translation for key: ${key}"
                        else
                            # 翻訳失敗時は原文をそのまま使用
                            echo "${target_lang}|${key}=${value}" >> "$result_file"
                            debug_log "DEBUG" "Translation failed, using original text for key: ${key}"
                        fi
                        
                        # APIレート制限対策 (短い待機時間)
                        sleep 0.5
                    else
                        # ネットワーク接続がない場合は原文を使用
                        echo "${target_lang}|${key}=${value}" >> "$result_file"
                        debug_log "DEBUG" "Network unavailable, using original text for key: ${key}"
                    fi
                fi
            fi
        done < "$temp_file"
        
        # 結果をメインの出力ファイルに追加
        cat "$result_file" >> "$output_file"
        
        # 次のバッチへ
        current_line=$((current_line + current_batch_size))
        batch_count=$((batch_count + 1))
        debug_log "DEBUG" "Completed batch ${batch_count}, processed ${current_line}/${total_lines} entries"
    done
    
    # 一時ファイルのクリーンアップ
    rm -f "$temp_file" "$result_file"
    debug_log "DEBUG" "Batch translation completed"
}

# 並行処理版の翻訳 - 複数ファイルを同時処理
parallel_process() {
    local base_db="$1"
    local target_lang="$2"
    local api_lang="$3"
    local output_db="$4"
    local max_jobs=3  # 同時実行数 (システムリソースに応じて調整)
    local temp_dir="${TRANSLATION_CACHE_DIR}/parallel"
    
    # 並行処理用の一時ディレクトリを作成
    mkdir -p "$temp_dir"
    debug_log "DEBUG" "Starting parallel processing with ${max_jobs} jobs"
    
    # 入力ファイルを分割
    local total_lines=$(grep -c "^US|" "$base_db")
    local lines_per_job=$(( (total_lines + max_jobs - 1) / max_jobs ))
    
    # 進行状況表示用の変数
    local job_count=0
    local pids=""
    
    # ジョブ分割と実行
    for i in $(seq 1 $max_jobs); do
        local start_line=$(( (i - 1) * lines_per_job + 1 ))
        local end_line=$(( i * lines_per_job ))
        
        # 分割ファイルを作成
        local split_file="${temp_dir}/part_${i}.txt"
        grep "^US|" "$base_db" | sed -n "${start_line},${end_line}p" > "$split_file"
        
        # 実際に行があるか確認
        if [ -s "$split_file" ]; then
            job_count=$((job_count + 1))
            local output_part="${temp_dir}/result_${i}.txt"
            
            # バックグラウンドでバッチ処理を実行
            batch_translate "$split_file" "$target_lang" "$api_lang" "$output_part" &
            pids="$pids $!"
            debug_log "DEBUG" "Started job ${job_count} with PID $! (lines ${start_line}-${end_line})"
        else
            rm -f "$split_file"
        fi
    done
    
    # すべてのジョブが完了するのを待つ
    for pid in $pids; do
        wait $pid
        debug_log "DEBUG" "Job with PID ${pid} completed"
    done
    
    # 結果を結合
    for result_file in "${temp_dir}"/result_*.txt; do
        if [ -f "$result_file" ]; then
            cat "$result_file" >> "$output_db"
        fi
    done
    
    # 一時ファイルをクリーンアップ
    rm -rf "$temp_dir"
    debug_log "DEBUG" "All parallel jobs completed and results combined"
}

# 最適化された言語DB作成関数
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
    
    # ネットワーク接続確認
    if ! ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        debug_log "DEBUG" "Network unavailable, using original text"
        grep "^US|" "$base_db" | sed "s/^US|/${target_lang}|/" >> "$output_db"
        return 0
    fi
    
    # 並行処理を使用して翻訳を実行
    parallel_process "$base_db" "$target_lang" "$api_lang" "$output_db"
    
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
    
    # 言語翻訳処理を実行
    process_language_translation
    
    debug_log "DEBUG" "Translation module initialized with performance optimizations"
}

# 初期化実行
init_translation
