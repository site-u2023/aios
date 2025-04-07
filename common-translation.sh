#!/bin/sh

SCRIPT_VERSION="2025-04-08-04-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-04-07
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

# メモリキャッシュ用変数
MEMORY_DB=""

# メモリDBに行を追加
add_to_memory_db() {
    local line="$1"
    MEMORY_DB="${MEMORY_DB}${line}\n"
}

# メモリDBをファイルに書き出し
flush_memory_db() {
    local file="$1"
    printf "%b" "$MEMORY_DB" > "$file"
}

# 翻訳キャッシュの初期化
init_translation_cache() {
    mkdir -p "${TRANSLATION_CACHE_DIR}"
    debug_log "DEBUG" "Translation cache directory initialized"
}

# 言語コード取得（APIのため）
get_api_lang_code() {
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        local api_lang=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "Using language code from message.ch: ${api_lang}"
        printf "%s\n" "$api_lang"
        return 0
    fi
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

# ネットワーク接続状態をチェックする関数
check_network_connectivity() {
    # ネットワーク状態をキャッシュファイルに書き込む
    local ip_check_file="${CACHE_DIR}/network.ch"
    touch "$ip_check_file" 2>/dev/null
    # ここでは単純化のため省略、実際にはIPv4, IPv6などを判定
    echo "v4" > "$ip_check_file"
}

# デバッグログ出力
debug_log() {
    local level="$1"
    local msg="$2"
    # 第3引数は省略可
    local force="${3:-false}"

    if [ "$DEBUG_MODE" = "true" ] || [ "$force" = "true" ]; then
        printf "[%s] %s: %s\n" "$(date +%H:%M:%S)" "$level" "$msg"
    fi
}

# スピナー開始（ダミー実装）
start_spinner() {
    local message="$1"
    debug_log "DEBUG" "Spinner start: $message"
}

# スピナー停止（ダミー実装）
stop_spinner() {
    local message="$1"
    local status="$2"
    debug_log "DEBUG" "Spinner stop: $message, status=$status"
}

# color関数（ダミー実装）
color() {
    local c="$1"
    local text="$2"
    # 実際にはANSIカラーなどを適用する場合
    printf "%s" "$text"
}

# get_message関数（ダミー実装）
get_message() {
    local key="$1"
    local info=""
    if [ -n "$2" ]; then
        info="$(echo "$2" | sed 's/^info=//')"
    fi
    # ダミーの動作: 単にキーとinfoを表示
    printf "[%s: %s]" "$key" "$info"
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

    [ ! -f "$ip_check_file" ] && check_network_connectivity

    if [ -f "$ip_check_file" ]; then
        local network_type=$(cat "$ip_check_file")
        case "$network_type" in
            "v4") wget_options="-4" ;;
            "v6") wget_options="-6" ;;
            "v4v6") wget_options="-4" ;;
        esac
    fi

    local encoded_text=$(urlencode "$text")
    local temp_file="${TRANSLATION_CACHE_DIR}/google_response.tmp"
    mkdir -p "$(dirname "$temp_file")" 2>/dev/null

    while [ $retry_count -le $API_MAX_RETRIES ]; do
        [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ] && \
            wget_options=$([ "$wget_options" = "-4" ] && echo "-6" || echo "-4")

        $BASE_WGET $wget_options -T $API_TIMEOUT --tries=1 -O "$temp_file" \
             --user-agent="Mozilla/5.0 (Linux; OpenWrt)" \
             "https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source_lang}&tl=${target_lang}&dt=t&q=${encoded_text}" 2>/dev/null

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

################################################################################
# 以下【追加】多行翻訳用関数: 人工的な区切り文字でまとめ→戻すアプローチ
################################################################################
translate_universal() {
    # Usage: translate_universal "複数行を含むテキスト" "source_lang" "target_lang"
    local text="$1"
    local source_lang="$2"
    local target_lang="$3"

    # 人工的な区切り文字を埋め込んで、一旦単一行にまとめる
    # sed置換で"\n"を<AIOS_LINE_SEP>に
    local joined="$(printf "%s" "$text" | sed 's/$/<AIOS_LINE_SEP>/g')"

    debug_log "DEBUG" "Performing universal translation with artificial delimiter"

    # 既存の関数translate_with_googleを流用。APIリクエスト時はjoinedを送る。
    local translated=""
    translated="$(translate_with_google "$joined" "$source_lang" "$target_lang" 2>/dev/null)"

    # 翻訳結果から<AIOS_LINE_SEP>を再び改行(\n)へ戻す
    if [ -n "$translated" ]; then
        printf "%s\n" "$translated" | sed 's/<AIOS_LINE_SEP>/\n/g'
    fi
}

# 言語データベース作成関数（ループ最適化版）
create_language_db() {
    local target_lang="$1"
    local base_db="${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
    local api_lang=$(get_api_lang_code)
    local output_db="${BASE_DIR}/message_${api_lang}.db"
    local temp_file="${TRANSLATION_CACHE_DIR}/translation_output.tmp"
    local cleaned_translation=""
    local current_api=""
    local ip_check_file="${CACHE_DIR}/network.ch"

    debug_log "DEBUG" "Creating language DB for target ${target_lang} with API language code ${api_lang}"

    if [ ! -f "$base_db" ]; then
        debug_log "DEBUG" "Base message DB not found"
        return 1
    fi

    local output_content="SCRIPT_VERSION=\"$(date +%Y.%m.%d-%H-%M)\""

    if [ "$ONLINE_TRANSLATION_ENABLED" != "yes" ]; then
        debug_log "DEBUG" "Online translation disabled, using original text"
        grep "^${DEFAULT_LANGUAGE}|" "$base_db" > "$temp_file"

        while IFS= read -r line; do
            output_content="${output_content}
$(echo "$line" | sed "s/^${DEFAULT_LANGUAGE}|/${api_lang}|/")"
        done < "$temp_file"

        rm -f "$temp_file"
        printf "%s\n" "$output_content" > "$output_db"
        return 0
    fi

    printf "\n"

    if [ ! -f "$ip_check_file" ]; then
        debug_log "DEBUG" "Network status file not found, checking connectivity"
        check_network_connectivity
    fi

    local network_status=""
    if [ -f "$ip_check_file" ]; then
        network_status=$(cat "$ip_check_file")
        debug_log "DEBUG" "Network status: ${network_status}"
    else
        debug_log "DEBUG" "Could not determine network status"
    fi

    local first_api=$(echo "$API_LIST" | cut -d',' -f1)
    case "$first_api" in
        google) current_api="Google Translate API" ;;
        *) current_api="Unknown API" ;;
    esac

    debug_log "DEBUG" "Initial API based on API_LIST priority: $current_api"
    start_spinner "$(color blue "Using API: $current_api")"

    grep "^${DEFAULT_LANGUAGE}|" "$base_db" > "$temp_file"

    if [ -z "$network_status" ] || [ "$network_status" = "" ]; then
        debug_log "DEBUG" "Network unavailable, using original text for all entries"
        while IFS= read -r line; do
            local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
            local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")

            if [ -n "$key" ] && [ -n "$value" ]; then
                output_content="${output_content}
${api_lang}|${key}=${value}"
            fi
        done < "$temp_file"
    else
        while IFS= read -r line; do
            local key=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|\([^=]*\)=.*/\1/p")
            local value=$(printf "%s" "$line" | sed -n "s/^${DEFAULT_LANGUAGE}|[^=]*=\(.*\)/\1/p")

            if [ -n "$key" ] && [ -n "$value" ]; then
                local translated=""
                local api
                for api in $(echo "$API_LIST" | tr ',' ' '); do
                    case "$api" in
                        google)
                            if [ "$current_api" != "Google Translate API" ]; then
                                stop_spinner "Switching API" "info"
                                current_api="Google Translate API"
                                start_spinner "$(color blue "Using API: $current_api")"
                                debug_log "DEBUG" "Switching to Google Translate API"
                            fi

                            # ▼▼▼ 従来の単行翻訳から人工区切り多行翻訳に置き換え可 ▼▼▼
                            # result=$(translate_with_google "$value" "$DEFAULT_LANGUAGE" "$api_lang" 2>/dev/null)
                            result=$(translate_universal "$value" "$DEFAULT_LANGUAGE" "$api_lang")
                            # ▲▲▲ 多行対応のtranslate_universalを利用 ▲▲▲

                            if [ $? -eq 0 ] && [ -n "$result" ]; then
                                cleaned_translation="$result"
                                break
                            else
                                debug_log "DEBUG" "Google Translate API failed for key: ${key}"
                            fi
                            ;;
                    esac
                done

                if [ -n "$cleaned_translation" ]; then
                    translated="$cleaned_translation"
                else
                    translated="$value"
                    debug_log "DEBUG" "All translation APIs failed, using original text for key: ${key}"
                fi

                output_content="${output_content}
${api_lang}|${key}=${translated}"
            fi
        done < "$temp_file"
    fi

    rm -f "$temp_file"
    printf "%s\n" "$output_content" > "$output_db"

    stop_spinner "Translation completed" "success"
    debug_log "DEBUG" "Language DB creation completed for ${api_lang}"
    return 0
}

# 翻訳情報を表示する関数
display_detected_translation() {
    local show_success_message="${1:-false}"

    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
    else
        lang_code="$DEFAULT_LANGUAGE"
    fi

    local source_lang="$DEFAULT_LANGUAGE"
    local source_db="message_${source_lang}.db"
    local target_db="message_${lang_code}.db"

    debug_log "DEBUG" "Displaying translation information for language code: ${lang_code}"

    if [ "$source_lang" = "$lang_code" ] && [ "$source_db" = "$target_db" ]; then
        debug_log "DEBUG" "Source and target languages are identical: ${lang_code}"
    fi

    if [ "$show_success_message" = "true" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_TRANSLATION_SUCCESS")")"
    fi

    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_ORIGINAL" "info=$source_db")")"
    printf "%s\n" "$(color white "$(get_message "MSG_TRANSLATION_SOURCE_CURRENT" "info=$target_db")")"

    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SOURCE" "info=$source_lang")")"
    printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_CODE" "info=$lang_code")")"

    debug_log "DEBUG" "Translation information display completed for ${lang_code}"
}

# 言語翻訳処理
process_language_translation() {
    local lang_code=""
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang_code=$(cat "${CACHE_DIR}/message.ch")
        debug_log "DEBUG" "Processing translation for language code: ${lang_code}"
    else
        debug_log "DEBUG" "No language code found in message.ch, using default"
        lang_code="$DEFAULT_LANGUAGE"
    fi

    local is_default_language=false
    if [ "$lang_code" = "$DEFAULT_LANGUAGE" ]; then
        is_default_language=true
        debug_log "DEBUG" "Selected language is the default language (${lang_code})"
    fi

    if [ "$is_default_language" = "false" ]; then
        create_language_db "$lang_code"
        display_detected_translation "false"
    else
        debug_log "DEBUG" "Skipping DB creation for default language: ${lang_code}"
        if [ "${DEFAULT_LANG_DISPLAYED:-false}" = "false" ]; then
            debug_log "DEBUG" "Displaying information for default language once"
            display_detected_translation "false"
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
    init_translation_cache
    process_language_translation
    debug_log "DEBUG" "Translation module initialized with language processing"
}

# スクリプト初期化（自動実行）
# init_translation
