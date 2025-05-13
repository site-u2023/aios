#!/bin/sh

SCRIPT_VERSION="2025.05.13-00-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-02-21
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

# システム制御
DEV_NULL="${DEV_NULL:-on}"       # サイレントモード制御（on=有効, unset=無効）
DEBUG_MODE="${DEBUG_MODE:-false}" # デバッグモード（true=有効, false=無効）

# パス・ファイル関連（resolve_path対応版）
INTERPRETER="${INTERPRETER:-ash}"  # デフォルトインタープリタ
BIN_DIR=""
BIN_PATH=""
BIN_FILE=""

# ベースディレクトリ設定
BASE_DIR="${BASE_DIR:-/tmp/aios}"      # 基本ディレクトリ
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}" # キャッシュディレクトリ
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}" # フィードディレクトリ
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"   # ログディレクトリ
TR_DIR="${TR_DIR:-$BASE_DIR/translation}"
DL_DIR="${DL_DIR:-$BASE_DIR/download}"

# スピナーデフォルト設定
SPINNER_DELAY="1" # デフォルトは秒単位
SPINNER_COLOR="white" # デフォルトのスピナー色
ANIMATION_ENABLED="1" # アニメーション有効/無効フラグ

# --- Set MAX_PARALLEL_TASKS ---
PARALLEL_LIMIT="5"
PARALLEL_PLUS="1"
CORE_COUNT=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 1)
MAX_PARALLEL_TASKS=$(( (CORE_COUNT + PARALLEL_PLUS > PARALLEL_LIMIT) * PARALLEL_LIMIT + (CORE_COUNT + PARALLEL_PLUS <= PARALLEL_LIMIT) * (CORE_COUNT + PARALLEL_PLUS) ))

# ダウンロード関連設定
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}" # 基本URL
DOWNLOAD_METHOD="${DOWNLOAD_METHOD:-direct}" # ダウンロード方式 (direct)

# wget関連設定
BASE_WGET="wget --no-check-certificate -q" # 基本wgetコマンド
WGET_TIMEOUT="${WGET_TIMEOUT:-8}"
WGET_MAX_RETRIES="${WGET_MAX_RETRIES:-5}"

# GitHub API認証関連
UPDATE_CACHE="${CACHE_DIR}/update.ch" # 更新情報キャッシュ

# メッセージ翻訳システムの設定
DEFAULT_LANGUAGE="${DEFAULT_LANGUAGE:-en}"  # デフォルト言語
MSG_MEMORY=""                          # メッセージキャッシュ
MSG_MEMORY_INITIALIZED="false"         # メモリキャッシュ初期化フラグ
MSG_MEMORY_LANG=""                     # メモリキャッシュの言語

# String Formatting Control within get_message function
GET_MESSAGE_FORMATTING_ENABLED="true"   # get_message 内でのフォーマット処理全体を有効にするか (true/false)
FORMAT_TYPE_UPPER_ENABLED="true"        # 'upper' (大文字) フォーマットを有効にするか (true/false)
FORMAT_TYPE_CAPITALIZE_ENABLED="true"   # 'capitalize' (先頭大文字) フォーマットを有効にするか (true/false)

# メッセージキャッシュ
MSG_MEMORY=""
MSG_MEMORY_INITIALIZED="false"
MSG_MEMORY_LANG=""

# 🔵　エラー・デバッグ　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------

handle_error() {
    local error_key="$1"
    local file="$2"
    local version="$3"
    local exit_required="${4:-no}"

    local error_message
    error_message=$(get_message "$error_key")

    # メッセージが取得できなかった場合のフォールバック
    if [ -z "$error_message" ]; then
        error_message="Unknown error occurred. Key: $error_key"
    fi

    # 変数を置換
    error_message=$(echo "$error_message" | sed -e "s/{file}/$file/g" -e "s/{version}/$version/g")

    # ログ記録 & 表示
    debug_log "DEBUG" "$error_message"
    echo -e "$(color red "$error_message")"

    if [ "$exit_required" = "yes" ]; then
        debug_log "DEBUG" "Critical error occurred, exiting: $error_message"
        exit 1
    else
        debug_log "DEBUG" "Non-critical error: $error_message"
        return 1
    fi
}

debug_log() {
    local level="$1"
    local message="$2"
    local file="$3"
    local version="$4"
    local debug_level="${DEBUG_LEVEL:-ERROR}"  # デフォルト値を設定

    # レベル判定のシンプル化
    case "$level" in
        "DEBUG"|"INFO"|"WARN"|"ERROR") ;;
        "")
            level="DEBUG"
            message="$1"
            file="$2"
            version="$3"
            ;;
        *)
            message="$1"
            file="$2"
            version="$3"
            level="DEBUG"
            ;;
    esac

    # バージョン情報のクリーニング（メッセージにバージョン情報が含まれる場合）
    if echo "$message" | grep -q "version\|Version"; then
        # バージョン情報部分を抽出してクリーニング
        local cleaned_message="$message"
        # aios - [2025-03-10... のようなパターンを検出
        if echo "$message" | grep -q " - "; then
            local prefix=$(echo "$message" | sed 's/ - .*//')
            local version_part=$(echo "$message" | sed 's/.* - //')
            
            # clean_version_string関数を呼び出し
            local cleaned_version=$(clean_version_string "$version_part")
            
            cleaned_message="$prefix - $cleaned_version"
        fi
        message="$cleaned_message"
    fi

    # 変数を置換
    message=$(echo "$message" | sed -e "s/{file}/$file/g" -e "s/{version}/$version/g")

    # ログレベル制御
    case "$DEBUG_LEVEL" in
        DEBUG)    allowed_levels="DEBUG INFO WARN ERROR" ;;
        INFO)     allowed_levels="INFO WARN ERROR" ;;
        WARN)     allowed_levels="WARN ERROR" ;;
        ERROR)    allowed_levels="ERROR" ;;
        *)        allowed_levels="ERROR" ;;
    esac

    if echo "$allowed_levels" | grep -q "$level"; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local log_message="[$timestamp] $level: $message"

        # カラー表示 - 標準エラー出力に出力
        case "$level" in
            "ERROR") printf "%s\n" "$(color red "$log_message")" >&2 ;;
            "WARN") printf "%s\n" "$(color yellow "$log_message")" >&2 ;;
            "INFO") printf "%s\n" "$(color cyan "$log_message")" >&2 ;;
            "DEBUG") printf "%s\n" "$(color white "$log_message")" >&2 ;;
        esac

        # ログファイルに記録
        if [ "$AIOS_INITIALIZED" = "true" ] && [ -d "$LOG_DIR" ]; then
            echo "$log_message" >> "$LOG_DIR/debug.log" 2>/dev/null
        fi
    fi
}

# 🔴　エラー・デバッグ　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　ヘルプ　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------

print_help() {
    printf "%s\n\n" "$(get_message "MSG_HELP_USAGE")"

    printf "%s\n" "$(get_message "MSG_HELP_OPTIONS_HEADER")"
    printf "  %-25s %s\n" "-h, --help" "$(get_message "MSG_HELP_HELP")"
    printf "  %-25s %s\n" "-v, --version" "$(get_message "MSG_HELP_VERSION")"
    printf "  %-25s %s\n" "-r, --reset" "$(get_message "MSG_HELP_RESET")"
    printf "  %-25s %s\n" "-d, --debug" "$(get_message "MSG_HELP_DEBUG")"
    printf "  %-25s %s\n" "-cf, --common_full" "$(get_message "MSG_HELP_FULL")"
    printf "  %-25s %s\n" "-cl, --common_light" "$(get_message "MSG_HELP_LIGHT")"
    printf "  %-25s %s\n" "-cd, --common_debug" "$(get_message "MSG_HELP_COMMON_DEBUG")"
    printf "  %-25s %s\n" "-dr, --dry-run" "$(get_message "MSG_HELP_DRY_RUN")"

    printf "\n%s\n" "$(get_message "MSG_HELP_LANGUAGE_HEADER")"
    printf "  %-25s %s\n" "US, JP, ..." "$(get_message "MSG_HELP_LANGUAGE")"

    printf "\n%s\n" "$(get_message "MSG_HELP_EXAMPLES_HEADER")"
    printf "  %s\n" "$(get_message "MSG_HELP_EXAMPLE1")"
    printf "  %s\n" "$(get_message "MSG_HELP_EXAMPLE2")"
    printf "  %s\n" "$(get_message "MSG_HELP_EXAMPLE3")"
    printf "  %s\n" "$(get_message "MSG_HELP_EXAMPLE4")"
}

# 🔴　ヘルプ　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　カラー系　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

# 基本色表示関数
color() {
    local c="$1"; shift
    case "$c" in
        red) printf "\033[38;5;196m%s\033[0m" "$*" ;;
        orange) printf "\033[38;5;208m%s\033[0m" "$*" ;;
        yellow) printf "\033[38;5;226m%s\033[0m" "$*" ;;
        green) printf "\033[38;5;46m%s\033[0m" "$*" ;;
        cyan) printf "\033[38;5;51m%s\033[0m" "$*" ;;
        blue) printf "\033[38;5;33m%s\033[0m" "$*" ;;
        indigo) printf "\033[38;5;57m%s\033[0m" "$*" ;;
        purple) printf "\033[38;5;129m%s\033[0m" "$*" ;;
        magenta) printf "\033[38;5;201m%s\033[0m" "$*" ;;
        white) printf "\033[37m%s\033[0m" "$*" ;;
        black) printf "\033[30m%s\033[0m" "$*" ;;
        *) printf "%s" "$*" ;;
    esac
}

# 端末の表示能力を検出する関数
detect_terminal_capability() {
    # 環境変数による明示的指定を最優先
    if [ -n "$AIOS_BANNER_STYLE" ]; then
        debug_log "DEBUG" "Using environment override: AIOS_BANNER_STYLE=$AIOS_BANNER_STYLE"
        echo "$AIOS_BANNER_STYLE"
        return 0
    fi
    
    # キャッシュが存在する場合はそれを使用
    if [ -f "$CACHE_DIR/banner_style.ch" ]; then
        CACHED_STYLE=$(cat "$CACHE_DIR/banner_style.ch")
        debug_log "DEBUG" "Using cached banner style: $CACHED_STYLE"
        echo "$CACHED_STYLE"
        return 0
    fi
    
    # デフォルトスタイル（安全なASCII）
    STYLE="ascii"
    
    # ロケールの確認
    LOCALE_CHECK=""
    if [ -n "$LC_ALL" ]; then
        LOCALE_CHECK="$LC_ALL"
    elif [ -n "$LANG" ]; then
        LOCALE_CHECK="$LANG"
    fi
    
    debug_log "DEBUG" "Checking locale: $LOCALE_CHECK"
    
    # UTF-8検出
    if echo "$LOCALE_CHECK" | grep -i "utf-\?8" >/dev/null 2>&1; then
        debug_log "DEBUG" "UTF-8 locale detected"
        STYLE="unicode"
    else
        debug_log "DEBUG" "Non-UTF-8 locale or unset locale"
    fi
    
    # ターミナル種別の確認
    if [ -n "$TERM" ]; then
        debug_log "DEBUG" "Checking terminal type: $TERM"
        case "$TERM" in
            *-256color|xterm*|rxvt*|screen*)
                STYLE="unicode"
                debug_log "DEBUG" "Advanced terminal detected"
                ;;
            dumb|vt100|linux)
                STYLE="ascii"
                debug_log "DEBUG" "Basic terminal detected"
                ;;
        esac
    fi
    
    # OpenWrt固有の検出
    if [ -f "/etc/openwrt_release" ]; then
        debug_log "DEBUG" "OpenWrt environment detected"
        # OpenWrtでの追加チェック（必要に応じて）
    fi
    
    # スタイルをキャッシュに保存（ディレクトリが存在する場合）
    if [ -d "$CACHE_DIR" ]; then
        echo "$STYLE" > "$CACHE_DIR/banner_style.ch"
        debug_log "DEBUG" "Banner style saved to cache: $STYLE"
    fi
    
    debug_log "DEBUG" "Selected banner style: $STYLE"
    echo "$STYLE"
}

# 🔴　カラー系　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　メッセージ系　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

clear_input_buffer() {
    # 1行だけ（最新の入力値）を優先的に読む。改行のみなら何もしない。
    local first=1
    while IFS= read -t 1 -r dummy < /dev/tty; do
        # 1行目が空なら何もしない（本入力なし）
        if [ $first -eq 1 ]; then
            # もし空行でなければ"flush"しない
            if [ -n "$dummy" ]; then
                break
            fi
        fi
        first=0
    done 2>/dev/null
}

into_memory_message() {
    local lang="$DEFAULT_LANGUAGE"
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang=$(cat "${CACHE_DIR}/message.ch")
    fi

    # メモリメッセージの初期化 - 基本的な補助メッセージのみを保持
    MSG_MEMORY=""

    # 基本メッセージの設定

    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_BANNER_DECCRIPTION=Dedicated configuration software for OpenWRT"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_BANNER_NAME=All-in-One Scripts"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_BANNER_DISCLAIMER=WARNING{:} This script is used at your own risk"$'\n'
    
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_PASSWORD_NOTICE=Notice: Set a new password with 8 or more characters (Press Enter to skip)"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_ENTER_PASSWORD=Enter new password{;}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_CONFIRM_PASSWORD=Confirm new password{;}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_PASSWORD_ERROR=Invalid password. Enter a password with at least 8 characters and confirm by entering the same password twice"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_PASSWORD_SET_OK=Password set successfully"$'\n'
    
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_MAX_PARALLEL_TASKS=Maximum number of threads{:} {m}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|DOWNLOAD_PARALLEL_START=Downloading essential files"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|DOWNLOAD_PARALLEL_SUCCESS=Essential files downloaded successfully in {s} seconds"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|DOWNLOAD_PARALLEL_FAILED=Parallel download failed in task {f}{:} {e}"$'\n'

    MSG_MEMORY="${MSG_MEMORY}${lang}|CONFIG_DOWNLOAD_SUCCESS=Downloaded {f}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|CONFIG_DOWNLOAD_UNNECESSARY=Latest Files{:}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_RESET_COMPLETE=Reset completed. All cached data has been cleared"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_DELETE_COMPLETE=Delete completed. All base data has been cleared"$'\n'

    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_HOSTNAME_SET=Set hostname{;}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_ENTER_HOSTNAME=Enter new hostname{;}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_HOSTNAME_SET_OK=Hostname set to {h}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_HOSTNAME_ERROR=Failed to set hostname"$'\n'

    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_SSH_LAN_SET=Set SSH to LAN interface{:}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_SSH_LAN_SET_OK=SSH is now set to LAN interface"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_SSH_LAN_SET_FAIL=Failed to set SSH to LAN interface"$'\n'

    # DBファイルが主要ソース

    MSG_MEMORY_INITIALIZED="true"
    MSG_MEMORY_LANG="$lang"
}

# 表題部専用関数
print_section_title() {
    # $1: メッセージキー（省略時はSELECTED_MENU_KEY）
    # $2: 色（省略時はSELECTED_MENU_COLOR）

    local msg_key="${1:-$SELECTED_MENU_KEY}"
    local color_name="${2:-$SELECTED_MENU_COLOR}"

    # フォールバック対策
    [ -z "$msg_key" ] && msg_key="NO_TITLE_KEY"
    [ -z "$color_name" ] && color_name="blue"

    printf "\n%s\n\n" "$(color "$color_name" "$(get_message "$msg_key")")"
}

# 翻訳システムを初期化する関数
init_translation() {
    debug_log "DEBUG" "Initializing translation system"
    
    # message.chが無い場合、デフォルト言語を設定
    if [ ! -f "${CACHE_DIR}/message.ch" ] && [ -f "${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db" ]; then
        echo "$DEFAULT_LANGUAGE" > "${CACHE_DIR}/message.ch"
        debug_log "DEBUG" "Created default language settings: $DEFAULT_LANGUAGE"
    fi
    
    # メモリ内メッセージの初期化
    into_memory_message
    
    debug_log "DEBUG" "Translation module initialization complete"
    return 0
}

# メッセージDBファイルのパスを取得する関数
check_message_cache() {
    local lang="$1"
    
    # 言語パラメータの確認
    if [ -z "$lang" ]; then
        # 言語が指定されていない場合、message.chから取得
        if [ -f "${CACHE_DIR}/message.ch" ]; then
            lang=$(cat "${CACHE_DIR}/message.ch")
        else
            lang="$DEFAULT_LANGUAGE"
        fi
    fi
    
    # 言語固有DBの確認
    if [ -f "${BASE_DIR}/message_${lang}.db" ]; then
        echo "${BASE_DIR}/message_${lang}.db"
        return 0
    fi
    
    # デフォルト言語DBの確認
    if [ -f "${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db" ]; then
        echo "${BASE_DIR}/message_${DEFAULT_LANGUAGE}.db"
        return 0
    fi
    
    # 何も見つからない場合は空文字列
    echo ""
    return 0
}

# Function to format strings based on specified type
# Usage: format_string <format_type> <input_string>
# format_type: "upper" (all uppercase), "capitalize" (first letter uppercase, rest lowercase)
# Default: returns original string if type is unknown or empty
format_string() {
    local format_type="$1"
    local input_string="$2"
    local output_string=""
    local char=""
    local i=0
    local length=0

    # Check if input string is empty
    if [ -z "$input_string" ]; then
        printf "" # Use printf instead of echo for consistency
        return 0
    fi

    case "$format_type" in
        "upper")
            # Convert entire string to uppercase using shell loop and case
            length=${#input_string}
            while [ "$i" -lt "$length" ]; do
                char="${input_string:$i:1}"
                case "$char" in
                    a) output_string="${output_string}A" ;;
                    b) output_string="${output_string}B" ;;
                    c) output_string="${output_string}C" ;;
                    d) output_string="${output_string}D" ;;
                    e) output_string="${output_string}E" ;;
                    f) output_string="${output_string}F" ;;
                    g) output_string="${output_string}G" ;;
                    h) output_string="${output_string}H" ;;
                    i) output_string="${output_string}I" ;;
                    j) output_string="${output_string}J" ;;
                    k) output_string="${output_string}K" ;;
                    l) output_string="${output_string}L" ;;
                    m) output_string="${output_string}M" ;;
                    n) output_string="${output_string}N" ;;
                    o) output_string="${output_string}O" ;;
                    p) output_string="${output_string}P" ;;
                    q) output_string="${output_string}Q" ;;
                    r) output_string="${output_string}R" ;;
                    s) output_string="${output_string}S" ;;
                    t) output_string="${output_string}T" ;;
                    u) output_string="${output_string}U" ;;
                    v) output_string="${output_string}V" ;;
                    w) output_string="${output_string}W" ;;
                    x) output_string="${output_string}X" ;;
                    y) output_string="${output_string}Y" ;;
                    z) output_string="${output_string}Z" ;;
                    *) output_string="${output_string}${char}" ;; # Append non-lowercase chars as is
                esac
                i=$((i + 1))
            done
            ;;
        "capitalize")
            # Convert first letter to uppercase, rest to lowercase using shell loop and case
            # Extract first character and rest of the string (ash/bash extensions)
            local first_char="${input_string:0:1}"
            local rest_string="${input_string:1}"

            # Convert first char to uppercase
            case "$first_char" in
                a) output_string="A" ;;
                b) output_string="B" ;;
                c) output_string="C" ;;
                d) output_string="D" ;;
                e) output_string="E" ;;
                f) output_string="F" ;;
                g) output_string="G" ;;
                h) output_string="H" ;;
                i) output_string="I" ;;
                j) output_string="J" ;;
                k) output_string="K" ;;
                l) output_string="L" ;;
                m) output_string="M" ;;
                n) output_string="N" ;;
                o) output_string="O" ;;
                p) output_string="P" ;;
                q) output_string="Q" ;;
                r) output_string="R" ;;
                s) output_string="S" ;;
                t) output_string="T" ;;
                u) output_string="U" ;;
                v) output_string="V" ;;
                w) output_string="W" ;;
                x) output_string="X" ;;
                y) output_string="Y" ;;
                z) output_string="Z" ;;
                *) output_string="$first_char" ;; # Append non-lowercase first char as is
            esac

            # Convert rest of the string to lowercase
            length=${#rest_string}
            i=0 # Reset loop counter
            while [ "$i" -lt "$length" ]; do
                char="${rest_string:$i:1}"
                case "$char" in
                    A) output_string="${output_string}a" ;;
                    B) output_string="${output_string}b" ;;
                    C) output_string="${output_string}c" ;;
                    D) output_string="${output_string}d" ;;
                    E) output_string="${output_string}e" ;;
                    F) output_string="${output_string}f" ;;
                    G) output_string="${output_string}g" ;;
                    H) output_string="${output_string}h" ;;
                    I) output_string="${output_string}i" ;;
                    J) output_string="${output_string}j" ;;
                    K) output_string="${output_string}k" ;;
                    L) output_string="${output_string}l" ;;
                    M) output_string="${output_string}m" ;;
                    N) output_string="${output_string}n" ;;
                    O) output_string="${output_string}o" ;;
                    P) output_string="${output_string}p" ;;
                    Q) output_string="${output_string}q" ;;
                    R) output_string="${output_string}r" ;;
                    S) output_string="${output_string}s" ;;
                    T) output_string="${output_string}t" ;;
                    U) output_string="${output_string}u" ;;
                    V) output_string="${output_string}v" ;;
                    W) output_string="${output_string}w" ;;
                    X) output_string="${output_string}x" ;;
                    Y) output_string="${output_string}y" ;;
                    Z) output_string="${output_string}z" ;;
                    *) output_string="${output_string}${char}" ;; # Append non-uppercase chars as is
                esac
                i=$((i + 1))
            done
            ;;
        *)
            # Unknown or empty format type, return original string
            output_string="$input_string"
            ;;
    esac

    # Return the formatted string
    printf '%s' "$output_string"
    return 0
}

# --- normalize_message function (Handles normalization EXCEPT braces) ---
# Arguments: $1: Input string, $2: Language code
normalize_message() {
    local input="$1"
    local lang="$2"
    local output="$input"
    local saved_locale="$LC_ALL"

    # Full-width to half-width normalization (Braces are handled in get_message)
    # output=$(echo "$output" | sed 's/｛/{/g; s/｝/}/g') # REMOVED - Handled by get_message
    output=$(echo "$output" | sed 's/：/:/g; s/∶/:/g; s/꞉/:/g; s/ː/:/g')
    output=$(echo "$output" | sed 's/；/;/g')
    output=$(echo "$output" | sed 's/　/ /g')
    output=$(echo "$output" | sed 's/＠/@/g')
    output=$(echo "$output" | sed 's/＼/\\/g') # Normalize full-width backslash

    # Placeholder space removal (using LC_ALL=C for safety)
    LC_ALL=C
    output=$(echo "$output" | sed 's/[[:space:]]\+{/{/g') # Space before {
    # output=$(echo "$output" | sed 's/}[[:space:]]\+/}/g') # Space after } (Keep commented out as per original)
    output=$(echo "$output" | sed 's/{[[:space:]]\+/{/g') # Space after { (inside)
    output=$(echo "$output" | sed 's/[[:space:]]\+}/}/g') # Space before } (inside)
    LC_ALL="$saved_locale"

    # Special placeholder replacement ( {;} is NOT replaced here )
    output=$(echo "$output" | sed 's/{:}/:/g') # {:} -> :
    output=$(echo "$output" | sed 's/{@}/\\n/g') # {@} -> newline (\n) - printf %b will interpret this

    # Language-specific number normalization
    case "${lang%%-*}" in
        ar) output=$(echo "$output" | sed 's/٠/0/g; s/١/1/g; s/٢/2/g; s/٣/3/g; s/٤/4/g; s/٥/5/g; s/٦/6/g; s/٧/7/g; s/٨/8/g; s/٩/9/g') ;;
        fa) output=$(echo "$output" | sed 's/۰/0/g; s/۱/1/g; s/۲/2/g; s/۳/3/g; s/۴/4/g; s/۵/5/g; s/۶/6/g; s/۷/7/g; s/۸/8/g; s/۹/9/g') ;;
        bn) output=$(echo "$output" | sed 's/০/0/g; s/۱/1/g; s/২/2/g; s/৩/3/g; s/৪/4/g; s/৫/5/g; s/৬/6/g; s/৭/7/g; s/৮/8/g; s/৯/9/g') ;;
        hi|mr|ne) output=$(echo "$output" | sed 's/०/0/g; s/१/1/g; s/२/2/g; s/३/3/g; s/४/4/g; s/५/5/g; s/६/6/g; s/७/7/g; s/८/8/g; s/९/9/g') ;;
        ja|zh|ko) output=$(echo "$output" | sed 's/０/0/g; s/１/1/g; s/２/2/g; s/３/3/g; s/４/4/g; s/５/5/g; s/６/6/g; s/７/7/g; s/８/8/g; s/９/9/g') ;;
    esac

    # Output using printf %s as per original function's behavior
    printf '%s' "$output"
    return 0
}

get_message() {
    local key="$1"
    local format_type="none" # Default format type
    local shift_count=1      # Default shift count (only key)
    local awk_script         # Local variable for awk script

    # Check if the second argument is a format type specifier
    if [ $# -ge 2 ]; then
        case "$2" in
            upper|capitalize|none)
                format_type="$2"
                shift_count=2
                ;;
        esac
    fi

    # Shift arguments based on whether format type was provided
    shift "$shift_count"

    local lang="$DEFAULT_LANGUAGE"
    local message=""
    local add_colon="false" # Initialize flag for adding colon

    # Get language code (assuming CACHE_DIR is defined)
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang=$(cat "${CACHE_DIR}/message.ch")
    fi

    # 1. Get message from DB file cache
    local db_file="$(check_message_cache "$lang")" # Assumes check_message_cache exists
    if [ -n "$db_file" ] && [ -f "$db_file" ]; then
        # Retrieve message for the specific language and key
        message=$(grep "^${lang}|${key}=" "$db_file" 2>/dev/null | cut -d'=' -f2-)
        # Fallback to default language if message not found for current language
        if [ -z "$message" ] && [ "$lang" != "$DEFAULT_LANGUAGE" ]; then
            local default_db_file="$(check_message_cache "$DEFAULT_LANGUAGE")"
            if [ -n "$default_db_file" ] && [ -f "$default_db_file" ]; then
                message=$(grep "^${DEFAULT_LANGUAGE}|${key}=" "$default_db_file" 2>/dev/null | cut -d'=' -f2-)
            fi
        fi
    fi

    # 2. Try memory cache if DB file cache failed
    if [ -z "$message" ]; then
        # Initialize memory cache if needed (assuming into_memory_message exists)
        if [ "$MSG_MEMORY_INITIALIZED" != "true" ] || [ "$MSG_MEMORY_LANG" != "$lang" ]; then
            into_memory_message
        fi
        # Retrieve message from memory cache
        if [ -n "$MSG_MEMORY" ]; then
            message=$(echo "$MSG_MEMORY" | grep "^${lang}|${key}=" 2>/dev/null | cut -d'=' -f2-)
            # Fallback to default language in memory cache
            if [ -z "$message" ] && [ "$lang" != "$DEFAULT_LANGUAGE" ]; then
                 message=$(echo "$MSG_MEMORY" | grep "^${DEFAULT_LANGUAGE}|${key}=" 2>/dev/null | cut -d'=' -f2-)
            fi
        fi
    fi

    # 3. Fallback to key itself if message not found
    if [ -z "$message" ]; then
        message="$key"
    fi

    # --- MODIFIED: Step 4: Detect and handle various colon markers ---
    # Handles {;}, {؛}, ｛;｝, and ｛؛｝ for multi-language and full-width support.
    case "$message" in
        *'{;}'*|*'{؛}'*|*'｛;｝'*|*'｛؛｝'*)
            # Found one of the markers. Remove all possible occurrences.
            # Remove standard half-width marker
            message="${message//\{;\}/}"
            # Remove Arabic semicolon marker
            message="${message//\{؛\}/}"
            # Remove full-width brace + half-width semicolon marker
            message="${message//｛;｝/}"
            # Remove full-width brace + Arabic semicolon marker
            message="${message//｛؛｝/}"
            add_colon="true"
            ;;
    esac
    # --- END MODIFIED ---

    # --- ADDED: Unconditionally normalize braces before replacement ---
    # Ensures full-width braces ｛｝ become half-width {} for awk compatibility
    # (This line was present in the provided source and remains unchanged)
    message=$(echo "$message" | sed 's/｛/{/g; s/｝/}/g')

    # --- MODIFIED: Parameter replacement using awk (Case-Insensitive, POSIX Compliant) ---
    # (The awk script and execution logic below are exactly as provided in the source and remain unchanged)
    awk_script='
        BEGIN { FS="=" }
        NR == 1 { msg = $0; next } # First line is the message template
        NR > 1 { # Subsequent lines are parameters name=value
            p_name = $1
            # Correctly get raw value even if it contains =
            p_value = substr($0, index($0, "=") + 1)
            params[p_name] = p_value # Store param in array (key is original case from input)
            
            # Also store lowercase version of parameter name using tr command
            cmd = "echo \"" p_name "\" | tr \"A-Z\" \"a-z\""
            cmd | getline p_name_lower
            close(cmd)
            params_lower[p_name_lower] = p_value
        }
        END {
            # Process parameters
            for (p_name in params) {
                # First do exact case match (original behavior)
                placeholder = "{" p_name "}"
                gsub(placeholder, params[p_name], msg)
            }
            
            # Now scan for case-insensitive matches
            i = 1
            result = ""
            while (i <= length(msg)) {
                # Look for opening brace
                if (substr(msg, i, 1) == "{") {
                    # Find matching closing brace
                    start_pos = i
                    i++
                    ph_name = ""
                    found_close = 0
                    
                    while (i <= length(msg)) {
                        c = substr(msg, i, 1)
                        if (c == "}") {
                            found_close = 1
                            break
                        }
                        ph_name = ph_name c
                        i++
                    }
                    
                    if (found_close) {
                        # Found complete placeholder
                        i++ # Move past closing brace
                        
                        # Convert placeholder name to lowercase using tr command
                        cmd = "echo \"" ph_name "\" | tr \"A-Z\" \"a-z\""
                        cmd | getline ph_name_lower
                        close(cmd)
                        
                        # Check if we have this parameter in lowercase form
                        if (ph_name_lower in params_lower) {
                            # We have a case-insensitive match, append value
                            result = result params_lower[ph_name_lower]
                        } else {
                            # No match, keep original placeholder
                            result = result "{" ph_name "}"
                        }
                    } else {
                        # No closing brace found, just add opening brace and continue
                        result = result "{"
                    }
                } else {
                    # Regular character, add to result
                    result = result substr(msg, i, 1)
                    i++
                }
            }
            
            print result
        }
    '
    # Execute awk script only if parameters are provided ($@ contains params after shift)
    if [ $# -gt 0 ]; then
        message=$( \
            ( \
                printf "%s\n" "$message"; \
                local param param_name param_value; \
                # Pass parameters to awk, one per line, handling '=' in value
                for param in "$@"; do \
                    param_name=$(echo "$param" | cut -d'=' -f1); \
                    param_value=$(echo "$param" | cut -d'=' -f2-); \
                    if [ -n "$param_name" ]; then \
                        printf "%s=%s\n" "$param_name" "$param_value"; \
                    fi; \
                done \
            ) | awk "$awk_script" \
        )
    fi

    # 6. Call normalize_message for remaining normalization
    # (This line was present in the provided source and remains unchanged)
    # Pass the potentially placeholder-replaced message and language
    message=$(normalize_message "$message" "$lang")

    # 7. Apply formatting (if enabled and type specified)
    # (This section was present in the provided source and remains unchanged)
    if [ "$GET_MESSAGE_FORMATTING_ENABLED" = "true" ]; then
        # Only proceed if formatting is globally enabled
        case "$format_type" in
            "upper")
                # Check if 'upper' format type is enabled
                if [ "$FORMAT_TYPE_UPPER_ENABLED" = "true" ]; then
                    message=$(format_string "upper" "$message") # Assumes format_string exists
                fi
                ;;
            "capitalize")
                # Check if 'capitalize' format type is enabled
                if [ "$FORMAT_TYPE_CAPITALIZE_ENABLED" = "true" ]; then
                    message=$(format_string "capitalize" "$message") # Assumes format_string exists
                fi
                ;;
            "none"|*)
                # Do nothing for "none" or unknown types
                ;;
        esac
    fi

    # 8. Append colon if marker {;} was present
    # (This logic remains the same, using the add_colon flag set in Step 4)
    if [ "$add_colon" = "true" ]; then
        message="${message}: " # Add colon and space
    fi

    # 9. Output the final message (using %b to interpret backslash escapes like \n from {@})
    # (This line was present in the provided source and remains unchanged)
    printf "%b" "$message"
    return 0
}

# 🔴　メッセージ系　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　ネットワーク系・OSバージョン　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------

# ネットワーク接続状態を確認する関数
check_network_connectivity() {
    local ip_check_file="${CACHE_DIR}/network.ch"
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    local ret4=1
    local ret6=1

    # デフォルトのIPバージョンオプション（空=システム設定に従う）
    WGET_IPV_OPT=""

    debug_log "DEBUG: Checking IPv4 connectivity"
    # ping -c 1 -w 3 8.8.8.8 >/dev/null 2>&1
    ping -4 -c 1 -w 3 one.one.one.one >/dev/null 2>&1
    ret4=$?

    debug_log "DEBUG: Checking IPv6 connectivity"
    # ping6 -c 1 -w 3 2001:4860:4860::8888 >/dev/null 2>&1
    ping -6  -c 1 -w 3 one.one.one.one >/dev/null 2>&1
    ret6=$?

    if [ "$ret4" -eq 0 ] && [ "$ret6" -eq 0 ]; then
        # v4v6デュアルスタック - 両方成功
        echo "dual stacks" > "${ip_check_file}"
        echo "-4" > "${ip_type_file}"
        WGET_IPV_OPT="-4"
        debug_log "DEBUG: Dual-stack (v4v6) connectivity detected"
    elif [ "$ret4" -eq 0 ]; then
        # IPv4のみ成功
        echo "v4" > "${ip_check_file}"
        echo "-4" > "${ip_type_file}"
        WGET_IPV_OPT="-4"
        debug_log "DEBUG: IPv4-only connectivity detected"
    elif [ "$ret6" -eq 0 ]; then
        # IPv6のみ成功
        echo "v6" > "${ip_check_file}"
        echo "-6" > "${ip_type_file}"
        WGET_IPV_OPT="-6"
        debug_log "DEBUG: IPv6-only connectivity detected"
    else
        # 両方失敗
        echo "unknown" > "${ip_check_file}"
        echo "unknown" > "${ip_type_file}"
        WGET_IPV_OPT="unknown"
        debug_log "DEBUG: No network connectivity detected"
        printf "\033[31mPlease connect to the network.\033[0m\n"
        exit 1
    fi
}

setup_wget_options() {
    # ip_type.chの内容をWGET_IPV_OPTにセットするラッパー
    if [ -f "${CACHE_DIR}/ip_type.ch" ]; then
        WGET_IPV_OPT=$(cat "${CACHE_DIR}/ip_type.ch")
        # 空やunknownの場合は空文字列
        if [ -z "$WGET_IPV_OPT" ] || [ "$WGET_IPV_OPT" = "unknown" ]; then
            WGET_IPV_OPT=""
        fi
    else
        WGET_IPV_OPT=""
    fi
    debug_log "DEBUG" "wget IP version updated to: ${WGET_IPV_OPT}"
}

# デバイス情報キャッシュを初期化・保存する関数
init_device_cache() {
   
    # アーキテクチャ情報の保存
    if [ ! -f "${CACHE_DIR}/architecture.ch" ]; then
        local arch
        arch=$(uname -m)
        echo "$arch" > "${CACHE_DIR}/architecture.ch"
        debug_log "DEBUG" "Created architecture cache: $arch"
    fi

    # OSバージョン情報の保存
    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        local version=""
        # OpenWrtバージョン取得
        if [ -f "/etc/openwrt_release" ]; then
            # ファイルからバージョン抽出
            version=$(grep -E "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2)
            echo "$version" > "${CACHE_DIR}/osversion.ch"
            debug_log "DEBUG" "Created OS version cache: $version"
        else
            echo "unknown" > "${CACHE_DIR}/osversion.ch"
            debug_log "DEBUG" "Could not determine OS version"
        fi
    fi

    # /etc/apk/world.base の初期スナップショット作成
    if [ -f "/etc/apk/world" ]; then
        if [ ! -f "/etc/apk/world.base" ]; then
            # /etc/apk/world.base が存在しない場合のみ作成を試みる
            if cp "/etc/apk/world" "/etc/apk/world.base"; then
                debug_log "DEBUG" "init_device_cache: Created /etc/apk/world.base"
            fi
        else
            debug_log "DEBUG" "init_device_cache: /etc/apk/world.base already exists."
        fi
    fi
 
    return 0
}

# 🔴 ネットワーク系・OSバージョン　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------


# 🔵　スピナー系　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------
start_spinner() {
    local message="$1"
    local spinner_color="${2:-$SPINNER_COLOR}"
    local anim_type="${3:-spinner}" 
    
    # グローバル変数を設定
    SPINNER_MESSAGE="$message"
    SPINNER_TYPE="$anim_type"
    SPINNER_COLOR="$spinner_color"
    
    if [ "$ANIMATION_ENABLED" -eq "0" ]; then
        debug_log "DEBUG: Animation disabled, showing static message"
        return
    fi

    SPINNER_DELAY="${SPINNER_DELAY:-1}"  # アニメーションディレイ値（秒）
    debug_log "DEBUG: Using standard animation mode (1s)"

    # カーソル非表示
    printf "\033[?25l"

    # アニメーションタイプに応じた文字セット
    case "$anim_type" in
        spinner)
            SPINNER_CHARS="- \\ | /"
            ;;
        dot)
            SPINNER_CHARS=". .. ... .... ....."
            ;;
        figure)
            SPINNER_CHARS="0 1 2 3 4 5 6 7 8 9"
            ;;
        circle)
            # 環境依存
            SPINNER_CHARS="◷ ◶ ◵ ◴"
            ;;
        square)
            # 環境依存
            SPINNER_CHARS="◳ ◲ ◱ ◰"
            ;;
        emoji)
            # 環境依存
            SPINNER_CHARS="💩 👺 😀 👽 😈 💀"
            ;;
        moon)
            # 環境依存
            SPINNER_CHARS="🌑 🌘 🌗 🌖 🌝 🌔 🌓 🌒"
            ;;
        bloc)
            # 環境依存
            SPINNER_CHARS="⠧ ⠏ ⠛ ⠹ ⠼ ⠶"
            ;;
        bloc2)
            # 環境依存
            SPINNER_CHARS="⢿ ⣻ ⣽ ⣾ ⣷ ⣯ ⣟ ⡿"
            ;;
        *)
            SPINNER_CHARS="- \\ | /"
            ;;
    esac

    debug_log "DEBUG: Starting spinner with message: $message, type: $anim_type, delay: $SPINNER_DELAY"

    # 直前のスピナープロセスがまだ実行中の場合は停止
    if [ -n "$SPINNER_PID" ]; then
        ps | grep -v grep | grep -q "$SPINNER_PID" 2>/dev/null
        if [ $? -eq 0 ]; then
            debug_log "DEBUG: Stopping previous spinner process PID: $SPINNER_PID"
            kill "$SPINNER_PID" >/dev/null 2>&1
            wait "$SPINNER_PID" 2>/dev/null || true
        fi
    fi

    # メッセージファイルの設定
    SPINNER_MSG_FILE="${CACHE_DIR}/spinner_msg_$$.tmp"
    mkdir -p "${CACHE_DIR}" 2>/dev/null
    printf "%s" "$message" > "$SPINNER_MSG_FILE"
    debug_log "DEBUG: Created spinner message file: $SPINNER_MSG_FILE"

    # バックグラウンドでスピナーを実行
    (
        i=0
        local curr_msg="$message"
        
        while true; do
            # ファイルから新しいメッセージを読み取る
            if [ -f "$SPINNER_MSG_FILE" ]; then
                new_msg=$(cat "$SPINNER_MSG_FILE" 2>/dev/null)
                if [ -n "$new_msg" ] && [ "$new_msg" != "$curr_msg" ]; then
                    curr_msg="$new_msg"
                fi
            fi
            
            for char in $SPINNER_CHARS; do
                printf "\r\033[K%s %s" "$curr_msg" "$(color "$SPINNER_COLOR" "$char")"

                # usleep関連のコードを削除し、常にsleepを使用
                sleep "$SPINNER_DELAY"
                
                # アニメーションサイクル中のメッセージ更新チェック
                if [ -f "$SPINNER_MSG_FILE" ]; then
                    new_msg=$(cat "$SPINNER_MSG_FILE" 2>/dev/null)
                    if [ -n "$new_msg" ] && [ "$new_msg" != "$curr_msg" ]; then
                        curr_msg="$new_msg"
                        break  # 新しいメッセージがあれば次のサイクルへ
                    fi
                fi
            done
        done
    ) &
    SPINNER_PID=$!
    debug_log "DEBUG: Spinner started with PID: $SPINNER_PID"
}

# スピナー停止関数
stop_spinner() {
    local message="$1"
    local status="${2:-success}"

    if [ "$ANIMATION_ENABLED" -eq "0" ]; then
        # アニメーション無効時はメッセージがあれば表示 (改行あり)
        if [ -n "$message" ]; then
            printf "%s\n" "$message"
        fi
        return
    fi

    debug_log "DEBUG: Stopping spinner with message: $message, status: $status"

    # メッセージファイルを削除
    if [ -f "$SPINNER_MSG_FILE" ]; then
        rm -f "$SPINNER_MSG_FILE" 2>/dev/null
        debug_log "DEBUG: Removed spinner message file: $SPINNER_MSG_FILE"
    fi

    # プロセスが存在するか確認
    if [ -n "$SPINNER_PID" ]; then
        # プロセスが実際に存在するか確認
        ps | grep -v grep | grep -q "$SPINNER_PID" 2>/dev/null
        if [ $? -eq 0 ]; then
            debug_log "DEBUG: Process found, killing PID: $SPINNER_PID"
            kill "$SPINNER_PID" >/dev/null 2>&1
            wait "$SPINNER_PID" 2>/dev/null || true
            unset SPINNER_PID
            printf "\r\033[K"  # 行をクリア

            # メッセージが空でない場合のみ表示 (改行あり)
            if [ -n "$message" ]; then
                # 成功/失敗に応じたメッセージカラー
                if [ "$status" = "success" ]; then
                    printf "%s\n" "$(color green "$message")"
                else
                    printf "%s\n" "$(color yellow "$message")"
                fi
            fi
        else
            debug_log "DEBUG: Process not found for PID: $SPINNER_PID"
            unset SPINNER_PID
            # プロセスが見つからなくても、メッセージがあれば表示 (改行あり)
            if [ -n "$message" ]; then
                 if [ "$status" = "success" ]; then
                     printf "%s\n" "$(color green "$message")"
                 else
                     printf "%s\n" "$(color yellow "$message")"
                 fi
            fi
        fi
    # SPINNER_PID がない場合でも、メッセージがあれば表示 (改行あり)
    elif [ -n "$message" ]; then
        if [ "$status" = "success" ]; then
            printf "%s\n" "$(color green "$message")"
        else
            printf "%s\n" "$(color yellow "$message")"
        fi
    fi

    # 入力バッファクリア
    clear_input_buffer
    
    # カーソル表示
    printf "\033[?25h"
}

# スピナーメッセージ更新関数
update_spinner() {
    local message="$1"
    local spinner_color="${2:-$SPINNER_COLOR}"
    
    if [ "$ANIMATION_ENABLED" -eq "0" ]; then
        debug_log "DEBUG: Animation disabled, not updating spinner message"
        return
    fi
    
    # メッセージと色を更新
    SPINNER_MESSAGE="$message"
    
    # 色が指定されている場合のみ更新
    if [ -n "$spinner_color" ]; then
        SPINNER_COLOR="$spinner_color"
    fi
    
    # メッセージファイルを更新
    if [ -f "$SPINNER_MSG_FILE" ]; then
        printf "%s" "$message" > "$SPINNER_MSG_FILE"
        debug_log "DEBUG: Updated spinner message file with: $message"
    else
        debug_log "DEBUG: Spinner message file not found: $SPINNER_MSG_FILE"
    fi
}

# 🔴　スピナー系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　ダウンロード系　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

version_is_newer() {
    local current="$1"  # リモートバージョン
    local reference="$2"  # ローカルバージョン
    
    debug_log "DEBUG" "Comparing: Remote=$current, Local=$reference"
    
    # どちらかが不明の場合は更新必要
    if echo "$current $reference" | grep -q "No version\|unknown"; then
        debug_log "DEBUG" "Unknown version detected, update required"
        return 0
    fi
    
    # 完全一致の場合は更新不要
    if [ "$current" = "$reference" ]; then
        debug_log "DEBUG" "Exact match: No update needed"
        return 1
    fi
    
    # 日付部分を抽出（YYYY.MM.DD形式）
    local current_date=$(echo "$current" | grep -o "[0-9][0-9][0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]" | head -1)
    local reference_date=$(echo "$reference" | grep -o "[0-9][0-9][0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]" | head -1)
    
    # 日付が抽出できなかった場合は更新が必要
    if [ -z "$current_date" ] || [ -z "$reference_date" ]; then
        debug_log "DEBUG" "Date extraction failed: Update for safety"
        return 0
    fi
    
    # 日付を数値に変換（区切り文字を削除）
    local current_num=$(echo "$current_date" | tr -d '.')
    local reference_num=$(echo "$reference_date" | tr -d '.')
    
    # 数値比較（日付形式）
    if [ "$current_num" -gt "$reference_num" ]; then
        debug_log "DEBUG" "Remote date is newer: Update required"
        return 0  # リモート（current）が新しい
    elif [ "$current_num" -lt "$reference_num" ]; then
        debug_log "DEBUG" "Local date is newer: No update needed"
        return 1  # ローカル（reference）が新しい
    fi
    
    # 日付が同じ場合はSHA部分を比較
    local current_sha=$(echo "$current" | grep -o "\-[a-z0-9]*" | sed 's/^-//' | head -1)
    local reference_sha=$(echo "$reference" | grep -o "\-[a-z0-9]*" | sed 's/^-//' | head -1)
    
    # SHA情報をデバッグ出力
    debug_log "DEBUG" "SHA comparison: Remote=$current_sha, Local=$reference_sha"
    
    # 直接DL時の特別処理: ハッシュの先頭7文字だけ比較して異なる場合のみ更新
    if [ -n "$current_sha" ] && [ -n "$reference_sha" ]; then
        # どちらかにdirectというマークがあれば直接DLモードと判断
        if echo "$current $reference" | grep -q "direct"; then
            # 先頭7文字だけ比較（SHA-1とSHA-256を混在比較する場合の対策）
            local current_short=$(echo "$current_sha" | head -c 7)
            local reference_short=$(echo "$reference_sha" | head -c 7)
            
            if [ "$current_short" != "$reference_short" ]; then
                debug_log "DEBUG" "Different file hash in direct mode: Update required"
                return 0  # 異なるハッシュ
            else
                debug_log "DEBUG" "Same file hash in direct mode: No update needed"
                return 1  # 同一ハッシュ
            fi
        elif [ "$current_sha" != "$reference_sha" ]; then
            debug_log "DEBUG" "Different SHA: Update required"
            return 0  # 異なるコミット
        fi
    fi
    
    debug_log "DEBUG" "Same version or unable to compare: No update needed"
    return 1  # 同一バージョン
}

detect_wget_capabilities() {
    debug_log "DEBUG" "Detecting wget capabilities for current environment"

    local temp_file="${CACHE_DIR}/wget_help.tmp"
    local test_file="${CACHE_DIR}/wget_test_header.tmp"
    local header_support="no"
    local user_support="no"
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    local wget_options=""

    # IP type判定（ip_type.chの内容をそのままwget_optionsに設定。unknownや空の場合はオプション無し）
    if [ -f "$ip_type_file" ]; then
        wget_options=$(cat "$ip_type_file" 2>/dev/null)
        if [ -z "$wget_options" ] || [ "$wget_options" = "unknown" ]; then
            wget_options=""
        fi
    else
        wget_options=""
    fi

    # wgetのヘルプを一時ファイルに保存（--helpがサポートされていない場合のため空ファイル作成）
    touch "$temp_file"
    wget $wget_options --help > "$temp_file" 2>&1 || true

    # デバッグ用にwgetヘルプ内容の先頭行を記録
    debug_log "DEBUG" "wget help output beginning:"
    head -3 "$temp_file" | while read line; do
        debug_log "DEBUG" "  $line"
    done

    # OpenWrt/BusyBox wgetの検出（特徴的な出力パターン）
    if grep -q "BusyBox" "$temp_file" || ! grep -q "\-\-header" "$temp_file"; then
        debug_log "DEBUG" "Detected BusyBox wget without header support"
        rm -f "$temp_file"
        echo "limited"
        return 1
    fi

    # ヘッダーオプションのサポートを確認 - より厳密なパターン
    if grep -q -- "--header=" "$temp_file" || grep -q -- "--header " "$temp_file"; then
        debug_log "DEBUG" "wget supports header authentication"
        header_support="yes"
    fi

    # 基本認証のサポートを確認 - より厳密なパターン
    if grep -q -- "--user=" "$temp_file" || grep -q -- "--user " "$temp_file"; then
        debug_log "DEBUG" "wget supports basic authentication"
        user_support="yes"
    fi

    # 実際に機能テストを行う（ヘルプテキスト検出のバックアップ）
    if [ "$header_support" = "yes" ]; then
        debug_log "DEBUG" "Testing header support with actual command"
        rm -f "$temp_file"
        echo "header"
        return 0
    elif [ "$user_support" = "yes" ]; then
        debug_log "DEBUG" "Basic authentication is supported"
        rm -f "$temp_file"
        echo "basic"
        return 0
    else
        debug_log "DEBUG" "No authentication methods supported"
        rm -f "$temp_file"
        echo "limited"
        return 1
    fi
}


clean_version_string() {
    local version_str="$1"
    
    # 1. 改行と復帰を削除
    local cleaned=$(printf "%s" "$version_str" | tr -d '\n\r')
    
    # 2. 角括弧を削除
    cleaned=$(printf "%s" "$cleaned" | sed 's/\[//g; s/\]//g')
    
    # 3. ANSIエスケープコードを削除
    cleaned=$(printf "%s" "$cleaned" | sed 's/\x1b\[[0-9;]*[mK]//g')
    
    # 4. バージョン番号の抽出（シンプルな方法）
    if echo "$cleaned" | grep -q '20[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]'; then
        # 年.月.日 形式のバージョンを抽出
        local date_part=$(printf "%s" "$cleaned" | grep -o '20[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]')
        
        # バージョン文字列の残りの部分があれば追加
        if echo "$cleaned" | grep -q "${date_part}-"; then
            local remainder=$(printf "%s" "$cleaned" | sed "s/.*${date_part}-//; s/[^0-9a-zA-Z-].*//")
            printf "%s-%s" "$date_part" "$remainder"
        else
            printf "%s" "$date_part"
        fi
    else
        # バージョンが見つからない場合は元の文字列をクリーニングしたものを返す
        printf "%s" "$cleaned"
    fi
}

download() {
    local file_name="$1"
    shift

    # デフォルト設定
    local chmod_mode="false"
    local hidden_mode="false"
    local quiet_mode="false"
    local interpreter_name=""
    local load_mode="false"

    # オプション解析
    while [ $# -gt 0 ]; do
        case "$1" in
            chmod)   chmod_mode="true" ;;
            hidden)  hidden_mode="true" ;;
            quiet)   quiet_mode="true" ;;
            bash|python3|node|perl)
                interpreter_name="$1"
                ;;
            load)   load_mode="true" ;;
            *)
                ;;
        esac
        shift
    done
    [ -z "$interpreter_name" ] && interpreter_name="ash"

    # ファイル名が空の場合は即失敗
    if [ -z "$file_name" ]; then
        debug_log "DEBUG" "download: filename is empty"
        return 1
    fi

    local file_path="${BASE_DIR}/${file_name}"

    # download_fetch_file 呼び出し (バージョン引数を削除)
    if ! download_fetch_file "$file_name" "$chmod_mode"; then
        debug_log "DEBUG" "download: download_fetch_file failed for $file_name"
        return 1
    fi

    # シングル時のみDL成功メッセージ表示（抑制/隠し/静音モード除外）
    if [ "$hidden_mode" = "false" ] && [ "$quiet_mode" = "false" ]; then
        # メッセージキー CONFIG_DOWNLOAD_SUCCESS を使用し、ファイル名のみ渡す
        printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_SUCCESS" "f=$file_name")"
    fi

    # load モードの処理 (変更なし)
    if [ "$load_mode" = "true" ]; then
        if [ -f "$file_path" ]; then
            debug_log "DEBUG" "download: Sourcing downloaded file due to load option: $file_path"
            # POSIX準拠: . コマンドを使用
            . "$file_path"
            local source_status=$?
            if [ $source_status -ne 0 ]; then
                debug_log "DEBUG" "download: Sourcing downloaded file failed with status $source_status: $file_path"
            fi
        fi
    fi

    return 0
}

download_parallel() {
    local start_time end_time elapsed_seconds
    local max_parallel current_jobs pids pid job_index # max_parallel をローカル変数として宣言
    local overall_status fail_flag_file first_failed_command first_error_message
    local script_path load_targets load_target retry
    local exported_vars log_file_prefix stdout_log stderr_log error_info_file
    local line command_line cmd_status
    local loaded_files source_success source_status
    local osversion # OSバージョン用ローカル変数

    start_time=$(date +%s)
    end_time=""
    elapsed_seconds=0

    overall_status=0
    fail_flag_file="${DL_DIR}/dl_failed_flag"
    first_failed_command=""
    first_error_message=""
    script_path="$0"
    exported_vars="BASE_DIR CACHE_DIR DL_DIR LOG_DIR DOWNLOAD_METHOD SKIP_CACHE DEBUG_MODE DEFAULT_LANGUAGE BASE_URL GITHUB_TOKEN_FILE COMMIT_CACHE_DIR COMMIT_CACHE_TTL FORCE"
    log_file_prefix="${LOG_DIR}/download_parallel_task_"

    # --- OS Version Detection ---
    # osversion.ch から読み込み、最初の '.' より前の部分を抽出
    osversion=$(cat "${CACHE_DIR}/osversion.ch" 2>/dev/null || echo "unknown")
    osversion="${osversion%%.*}"
    debug_log "DEBUG" "download_parallel: Detected OS major version: '$osversion'"

    # --- OSバージョンに応じた最大並列タスク数の設定 ---
    # この関数内で使用する実際の並列数を決定
    if [ "$osversion" = "19" ]; then
        # OpenWrt 19.x の場合は CORE_COUNT を使用
        max_parallel="$CORE_COUNT"
        # max_parallel=$((CORE_COUNT * 2))
        debug_log "DEBUG" "Detected OpenWrt 19.x (Major version '$osversion'). Setting max parallel tasks to CORE_COUNT ($max_parallel)."
    else
        # それ以外の場合はグローバル変数 MAX_PARALLEL_TASKS を使用
        max_parallel="$MAX_PARALLEL_TASKS"
        # max_parallel=$((CORE_COUNT * 2))
        debug_log "DEBUG" "Detected OS Major version '$osversion' (Not 19). Setting max parallel tasks using global MAX_PARALLEL_TASKS ($max_parallel)."
    fi
    # --- OSバージョンに応じた最大並列タスク数の設定ここまで ---

    # 決定された並列数を表示
    printf "%s\n" "$(color white "$(get_message "MSG_MAX_PARALLEL_TASKS" "m=$max_parallel")")"
    debug_log "DEBUG" "Effective max parallel download tasks set to: $max_parallel"

    # --- 以下、既存の処理 ---
    if ! mkdir -p "$DL_DIR"; then
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED')" "failure"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (directory creation) in %s seconds.\n" "$elapsed_seconds"
        return 1
    fi
    if ! mkdir -p "$LOG_DIR"; then
        debug_log "DEBUG" "Failed to create log directory: $LOG_DIR" >&2
    fi
    rm -f "$fail_flag_file" 2>/dev/null

    start_spinner "$(color blue "$(get_message 'DOWNLOAD_PARALLEL_START')")"

    if [ ! -f "$script_path" ]; then
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED')" "failure"
        debug_log "DEBUG" "Script path '$script_path' is not found"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (script not found) in %s seconds.\n" "$elapsed_seconds"
        return 1
    fi

    # download_files()関数のコマンド部のみ抽出（パイプなしで一時ファイルに保存）
    local cmd_tmpfile load_tmpfile
    cmd_tmpfile="${DL_DIR}/cmd_list_$$.txt"
    load_tmpfile="${DL_DIR}/load_targets_$$.txt"
    rm -f "$cmd_tmpfile" "$load_tmpfile" 2>/dev/null

    awk '
        BEGIN { in_func=0; }
        /^download_files\(\) *\{/ { in_func=1; next }
        /^}/ { if(in_func){in_func=0} }
        in_func && !/^[ \t]*$/ && !/^[ \t]*#/ { print }
    ' "$script_path" > "$cmd_tmpfile"

    # コマンドリストをquiet化しつつ一時ファイルに保存
    > "$cmd_tmpfile.quiet"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
            download*)
                if ! echo "$line" | grep -qw "quiet"; then
                    line="$line quiet"
                fi
                ;;
        esac
        printf "%s\n" "$line" >> "$cmd_tmpfile.quiet"
    done < "$cmd_tmpfile"

    mv "$cmd_tmpfile.quiet" "$cmd_tmpfile"

    # コマンドリストが空なら終了
    if ! grep -q . "$cmd_tmpfile"; then
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_SUCCESS')" "success"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download completed (no tasks) in %s seconds.\n" "$elapsed_seconds"
        rm -f "$cmd_tmpfile" "$load_tmpfile"
        return 0
    fi

    # ロード対象ファイル収集
    > "$load_tmpfile"
    while IFS= read -r command_line; do
        case "$command_line" in
            *'"load"')
                set -- $command_line
                if [ "$#" -ge 2 ]; then
                    load_fname=$2
                    load_fname=${load_fname#\"}
                    load_fname=${load_fname%\"}
                    if [ -n "$load_fname" ]; then
                        printf "%s\n" "$load_fname" >> "$load_tmpfile"
                    fi
                fi
                ;;
        esac
    done < "$cmd_tmpfile"

    eval "export $exported_vars"
    pids=""
    job_index=0

    while IFS= read -r command_line || [ -n "$command_line" ]; do
        [ -z "$command_line" ] && continue
        job_index=$((job_index + 1))
        task_name=$(printf "%03d" "$job_index")
        stdout_log="${log_file_prefix}${task_name}.stdout.log"
        stderr_log="${log_file_prefix}${task_name}.stderr.log"
        error_info_file="${DL_DIR}/error_info_${task_name}.txt"

        (
            eval "$command_line" >"$stdout_log" 2>"$stderr_log"
            cmd_status=$?
            if [ $cmd_status -ne 0 ]; then
                debug_log "DEBUG" "[$$][$task_name] Command failed: $command_line"
                {
                    echo "$command_line"
                    if [ -s "$stderr_log" ]; then
                        grep -v '^[[:space:]]*$' "$stderr_log" | head -n 1
                    else
                        echo "No error output captured"
                    fi
                } >"$error_info_file"
                exit 1
            fi
            exit 0
        ) &
        pid=$!
        pids="$pids $pid"

        # 並列数制御（決定された max_parallel を使用）
        set -- $pids
        if [ $# -ge "$max_parallel" ]; then
            wait "$1"
            pids=""
            shift
            while [ $# -gt 0 ]; do
                pids="$pids $1"
                shift
            done
        fi
    done < "$cmd_tmpfile"

    # 残りのジョブを待機
    for pid in $pids; do
        wait "$pid" || overall_status=1
    done

    # エラー処理
    if ls "$DL_DIR"/error_info_*.txt 2>/dev/null | grep -q .; then
        overall_status=1
        first_error_file=$(ls "$DL_DIR"/error_info_*.txt 2>/dev/null | sort | head -n 1)
        if [ -n "$first_error_file" ]; then
            first_failed_command=$(head -n 1 "$first_error_file" 2>/dev/null)
            first_error_message=$(sed -n '2p' "$first_error_file" 2>/dev/null)
            first_error_message=$(printf '%s' "$first_error_message" | tr -cd '[:print:]\t' | head -c 100)
        fi
    fi

    # ロード対象ファイルのsource
    if [ $overall_status -eq 0 ] && [ -s "$load_tmpfile" ]; then
        loaded_files=""
        while IFS= read -r load_file; do
            [ -z "$load_file" ] && continue
            # 重複ロードチェック
            echo "$loaded_files" | grep -qxF "$load_file" && continue

            full_load_path="${BASE_DIR}/$load_file"
            retry=1
            source_success=0
            while [ $retry -le 3 ]; do
                # === source コマンドを実行し、終了ステータスを取得 ===
                . "$full_load_path"
                source_status=$?
                # === ステータスを確認 ===
                if [ $source_status -eq 0 ]; then
                    source_success=1
                    # ★ 成功した場合、確認のため標準エラー出力にメッセージを表示 (任意) ★
                    # printf "OK: Sourced '%s' successfully.\n" "$full_load_path" >&2
                    break
                else
                    # ★★★ 失敗した場合、詳細なエラーメッセージを標準エラー出力に表示 ★★★
                    printf "ERROR: Failed sourcing '%s' on attempt %d. Status: %d\n" "$full_load_path" "$retry" "$source_status" >&2
                    sleep 1
                fi
                retry=$((retry + 1))
            done
            loaded_files="${loaded_files}${load_file}\n" # 改行区切りで記録
            if [ $source_success -ne 1 ]; then
                # ★★★ 最終的に失敗した場合のエラーメッセージ ★★★
                # $retry はループ終了時の値 (試行回数+1) なので、$((retry - 1)) で試行回数を表示
                printf "ERROR: Aborting load process. Failed to source '%s' after %d attempts. Final Status: %d\n" "$full_load_path" $((retry - 1)) "$source_status" >&2
                overall_status=1
                if [ -z "$first_failed_command" ]; then
                    first_failed_command="source $load_file"
                    # 終了ステータスをメッセージに追加
                    first_error_message="Failed after retries (status $source_status)"
                fi
                break # 最初の永続的な失敗で 'while read' ループを抜ける
            fi
        done < "$load_tmpfile"
    fi

    rm -f "$cmd_tmpfile" "$load_tmpfile"

    # --- 最終ステータス判定と終了処理 ---
    if [ $overall_status -eq 0 ]; then
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        success_message="$(get_message 'DOWNLOAD_PARALLEL_SUCCESS' "s=${elapsed_seconds}")"
        stop_spinner "$success_message" "success"
        return 0
    else
        [ -z "$first_failed_command" ] && first_failed_command="Unknown task"
        [ -z "$first_error_message" ] && first_error_message="Check logs in $LOG_DIR"
        failure_message="$(get_message 'DOWNLOAD_PARALLEL_FAILED' "f=$first_failed_command" "e=$first_error_message")"
        stop_spinner "$failure_message" "failure"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (task: %s) in %s seconds.\n" "$first_failed_command" "$elapsed_seconds"
        return 1
    fi
}

# @FUNCTION: download_fetch_file
# @DESCRIPTION: Fetches a single file using wget with retries and cache busting (if DOWNLOAD_METHOD=direct).
# @PARAM: $1 - File name (relative path from BASE_URL).
# @PARAM: $2 - Flag ("true" or "false") to apply chmod +x.
# @RETURN: 0 on success, non-zero on failure.
download_fetch_file() {
    local file_name="$1"
    local chmod_mode="$2"             # Second argument is now the second ($2)
    local install_path="${BASE_DIR}/$file_name"
    local remote_url="${BASE_URL}/$file_name"
    local wget_options=""
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    local retry_count=0
    # Use global wget settings directly
    local max_retries="${WGET_MAX_RETRIES}" # Use WGET_MAX_RETRIES (Correctly uses the global variable)
    local wget_timeout="${WGET_TIMEOUT}"     # Use WGET_TIMEOUT (Correctly uses the global variable)
    local wget_exit_code=1 # Default to failure

    # Debug log using the actual values from global variables
    debug_log "DEBUG" "download_fetch_file called for ${file_name}. Chmod: ${chmod_mode}. Max retries: ${max_retries:-[WGET_MAX_RETRIES not set]}, Timeout: ${wget_timeout:-[WGET_TIMEOUT not set]}s"

    # Apply dynamic cache busting only if DOWNLOAD_METHOD is 'direct'
    if [ "$DOWNLOAD_METHOD" = "direct" ]; then
        local cache_bust_param="?cache_bust=$(date +%s)"
        remote_url="${remote_url}${cache_bust_param}"
        debug_log "DEBUG" "Cache busting applied dynamically (DOWNLOAD_METHOD=direct): ${remote_url}"
    else
        debug_log "DEBUG" "Cache busting skipped (DOWNLOAD_METHOD is not 'direct')"
    fi

    debug_log "DEBUG" "Downloading from ${remote_url} to ${install_path}"

    # Check network availability via ip_type.ch
    if [ ! -f "$ip_type_file" ]; then
        debug_log "DEBUG" "download_fetch_file: Network check failed (ip_type.ch not found)" >&2
        return 1
    fi
    wget_options=$(cat "$ip_type_file" 2>/dev/null)
    if [ -z "$wget_options" ] || [ "$wget_options" = "unknown" ]; then
        debug_log "DEBUG" "download_fetch_file: Network check failed (ip_type.ch is unknown or empty)" >&2
        return 1
    fi

    # --- wget retry logic start ---
    while [ "$retry_count" -lt "$max_retries" ]; do
        if [ "$retry_count" -gt 0 ]; then
            debug_log "DEBUG" "download_fetch_file: Retrying download for $file_name (Attempt $((retry_count + 1))/$max_retries)..."
            sleep 1 # Wait 1 second before retrying
        fi

        # Execute wget with specified timeout and options
        wget --no-check-certificate $wget_options -T "$wget_timeout" -q -O "$install_path" "$remote_url" 2>/dev/null
        wget_exit_code=$?

        if [ "$wget_exit_code" -eq 0 ]; then
            debug_log "DEBUG" "download_fetch_file: wget command successful for $file_name."
            break # Exit loop on success
        else
            debug_log "DEBUG" "download_fetch_file: wget command failed for $file_name with exit code $wget_exit_code."
        fi
        retry_count=$((retry_count + 1))
    done
    # --- wget retry logic end ---

    # --- Check final result ---
    if [ "$wget_exit_code" -ne 0 ]; then
        debug_log "DEBUG" "download_fetch_file: Download failed for $file_name after $max_retries attempts."
        rm -f "$install_path" 2>/dev/null # Clean up incomplete file
        return 1
    fi

    # --- Validate downloaded file ---
    if [ ! -f "$install_path" ]; then
        debug_log "DEBUG" "download_fetch_file: Downloaded file not found after successful wget: $file_name"
        return 1
    fi
    if [ ! -s "$install_path" ]; then
        debug_log "DEBUG" "download_fetch_file: Downloaded file is empty after successful wget: $file_name"
        rm -f "$install_path" 2>/dev/null # Clean up empty file
        return 1
    fi
    debug_log "DEBUG" "download_fetch_file: File successfully downloaded and verified: ${install_path}"

    # --- Set permissions if requested ---
    if [ "$chmod_mode" = "true" ]; then
        chmod +x "$install_path"
        debug_log "DEBUG" "download_fetch_file: chmod +x applied to $file_name"
    fi

    return 0
}

download() {
    local file_name="$1"
    shift

    # デフォルト設定
    local chmod_mode="false"
    local force_mode="false"
    local hidden_mode="false"
    local quiet_mode="false"
    local interpreter_name=""
    local load_mode="false"

    # オプション解析
    while [ $# -gt 0 ]; do
        case "$1" in
            chmod)   chmod_mode="true" ;;
            force)   force_mode="true" ;;
            hidden)  hidden_mode="true" ;;
            quiet)   quiet_mode="true" ;;
            bash|python3|node|perl)
                interpreter_name="$1"
                ;;
            load)   load_mode="true" ;;
            *)
                ;;
        esac
        shift
    done
    [ -z "$interpreter_name" ] && interpreter_name="ash"

    # ファイル名が空の場合は即失敗
    if [ -z "$file_name" ]; then
        debug_log "DEBUG" "download: filename is empty"
        return 1
    fi

    local file_path="${BASE_DIR}/${file_name}"

    # 強制DL判定
    if [ "$force_mode" = "true" ]; then
        debug_log "DEBUG" "download: force mode enabled for $file_name"
    fi

    # ダウンロードスキップ判定 (ファイル存在有無のみ)
    if [ "$force_mode" != "true" ] && [ -f "$file_path" ]; then
        debug_log "DEBUG" "download: File already exists and force mode is off for $file_name; skipping download."
        # chmod要求ありなら実行
        if [ "$chmod_mode" = "true" ]; then
            chmod +x "$file_path" 2>/dev/null || debug_log "DEBUG" "download: chmod +x failed for existing file $file_path"
        fi
        # シングル時のみ最新版メッセージ出力（抑制/隠し/静音モード除外）
        if [ "$hidden_mode" = "false" ] && [ "$quiet_mode" = "false" ]; then
            printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_UNNECESSARY" "f=$file_name")"
        fi

        if [ "$load_mode" = "true" ]; then
            if [ -f "$file_path" ]; then
                debug_log "DEBUG" "download: Sourcing existing file due to load option: $file_path"
                . "$file_path"
                local source_status=$?
                if [ $source_status -ne 0 ]; then
                    debug_log "DEBUG" "download: Sourcing existing file failed with status $source_status: $file_path"
                fi
            fi
        fi
        return 0
    fi

    if ! download_fetch_file "$file_name" "$chmod_mode"; then
        debug_log "DEBUG" "download: download_fetch_file failed for $file_name"
        return 1
    fi

    # シングル時のみDL成功メッセージ表示（抑制/隠し/静音モード除外）
    if [ "$hidden_mode" = "false" ] && [ "$quiet_mode" = "false" ]; then

        printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_SUCCESS" "f=$file_name")"
    fi

    if [ "$load_mode" = "true" ]; then
        if [ -f "$file_path" ]; then
            debug_log "DEBUG" "download: Sourcing downloaded file due to load option: $file_path"
            . "$file_path"
            local source_status=$?
            if [ $source_status -ne 0 ]; then
                debug_log "DEBUG" "download: Sourcing downloaded file failed with status $source_status: $file_path"
            fi
        fi
    fi

    return 0
}

display_detected_download() {
  local max_parallel="$1"
  local completed_tasks="$2"
  local total_tasks="$3"
  local elapsed_seconds="$4"

  # Display Max Threads (変更なし)
  printf "%s\n" "$(get_message "MSG_MAX_PARALLEL_TASKS" m="$max_parallel")"
  # Display Download Summary (変更なし)
  printf "%s\n" "$(get_message "MSG_DOWNLOAD_SUMMARY" c="$completed_tasks" t="$total_tasks" s="$elapsed_seconds")"
}

# 🔴　ダウンロード系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　バナー・デバイス情報　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

# メイン関数 - バナー表示の統合関数
# 引数: 
#   $1 - バナースタイル（省略可）: "unicode", "ascii", "asterisk", "auto"
print_banner() {
    # スタイル指定またはデフォルト「auto」
    BANNER_STYLE="${1:-auto}"
    
    # 自動検出が必要な場合
    if [ "$BANNER_STYLE" = "auto" ]; then
        BANNER_STYLE=$(detect_terminal_capability)
        debug_log "DEBUG" "Auto-detected banner style: $BANNER_STYLE"
    fi

    # スタイルに応じたバナー表示
    case "$BANNER_STYLE" in
        unicode|block)
            print_banner_unicode
            ;;
        ascii|hash|sharp)
            print_banner_ascii
            ;;
        *)
            # 不明なスタイルの場合はASCIIにフォールバック
            debug_log "DEBUG" "Unknown banner style: $BANNER_STYLE, using ASCII fallback"
            print_banner_ascii
            ;;
    esac
}

print_banner_ascii() {
    debug_log "DEBUG" "Displaying lowercase aios block ASCII art banner"
    
    # ASCIIアート
    printf "\n"
    printf "%s\n" "$(color white "all in one script")"
    printf "\n"
    
    # バナーメッセージ
    printf "%s\n" "$(color white "$(get_message "MSG_BANNER_DECCRIPTION")")"
    printf "%s\n" "$(color white "$(get_message "MSG_BANNER_NAME")")"
    printf "%s\n" "$(color red "$(get_message "MSG_BANNER_DISCLAIMER")")"
    printf "\n"

    debug_log "DEBUG" "Block style lowercase aios banner displayed successfully"
}

print_banner_unicode() {
    debug_log "DEBUG" "Displaying lowercase aios block ASCII art banner"
    
    # ASCIIアート（環境依存文字 - ブロック）
    printf "\n"
    printf "%s\n" "$(color magenta "               ██ █")"
    printf "%s\n" "$(color blue    "     ████      ███       ████      █████")"
    printf "%s\n" "$(color green   "        ██      ██      ██  ██    ██")"
    printf "%s\n" "$(color yellow  "     █████      ██      ██  ██     █████")"
    printf "%s\n" "$(color orange  "    ██  ██      ██      ██  ██         ██")"
    printf "%s\n" "$(color red     "     █████     ████      ████     ██████")"
    printf "\n"

    # バナーメッセージ
    printf "%s\n" "$(color white "$(get_message "MSG_BANNER_DECCRIPTION")")"
    printf "%s\n" "$(color white "$(get_message "MSG_BANNER_NAME")")"
    printf "%s\n" "$(color red "$(get_message "MSG_BANNER_DISCLAIMER")")"
    printf "\n"

    debug_log "DEBUG" "Block style lowercase aios banner displayed successfully"
}

print_information() {
    local cpucore=$(cat "${CACHE_DIR}/cpu_core.ch")
    local network=$(cat "${CACHE_DIR}/network.ch")
    local architecture=$(cat "${CACHE_DIR}/architecture.ch")
    local osversion=$(cat "${CACHE_DIR}/osversion.ch")
    local package_manager=$(cat "${CACHE_DIR}/package_manager.ch")
    local usbdevice=$(cat "${CACHE_DIR}/usbdevice.ch")

    # ファイルが存在しない場合のみメッセージを表示
    if [ ! -f "${CACHE_DIR}/message.ch" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_INFO_DEVICE")")"
    fi
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_NETWORK" "i=$network")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_CPUCORE" "i=$cpucore")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_ARCHITECTURE" "i=$architecture")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_OSVERSION" "i=$osversion")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_PACKAGEMANAGER" "i=$package_manager")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_USBDEVICE" "i=$usbdevice")")"
    printf "\n"
}

# 🔴　バナー・デバイス情報　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　メイン　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

check_option() {
    # デフォルト値の設定
    ORIGINAL_ARGS="$@"
    MODE="full"
    SELECTED_LANGUAGE=""
    DEBUG_MODE="false"
    DEBUG_LEVEL="INFO"
    DRY_RUN="false"
    LOGFILE=""
    RESET="false" # RESET オプションはキャッシュ削除のため残す
    HELP="false"
    SKIP_DEVICE_DETECTION="false" # これらは残す
    SKIP_IP_DETECTION="false"     # これらは残す
    SKIP_ALL_DETECTION="false"    # これらは残す

    # 言語およびオプション引数の処理
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--h|-help|--help|-\?|--\?)
                HELP="true"
                print_help
                exit 0
                ;;
            -v|--v|-version|--version)
                script_version
                exit 0
                ;;
            -d|--d|-debug|--debug|-d1|--d1)
                DEBUG_MODE="true"
                DEBUG_LEVEL="DEBUG"
                ;;
            -cf|--cf|-common_full|--common_full)
                MODE="full"
                ;;
            -cl|--cl|-ocommon_light|--ocommon_light)
                MODE="light"
                ;;
            -cd|--cd|-common_debug|--common_debug|--common_debug)
                MODE="debug"
                ;;
            -r|--r|-resrt|--resrt)
                MODE="reset"
                RESET="true"
                ;;
            -del|--del|-delete|--delete)
                MODE="delete"
                ;;
            -dr|--dr|-dry-run|--dry-run)
                DRY_RUN="true"
                ;;
            -l|--l|-logfile|--logfile)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    LOGFILE="$2"
                    shift
                else
                    debug_log "DEBUG" "logfile requires a path argument"
                    exit 1
                fi
                ;;
            -sd|--sd|-skip-dev|--skip-dev)
                SKIP_DEVICE_DETECTION="true"
                ;;
            -si|--si|-skip-ip|--skip-ip)
                SKIP_IP_DETECTION="true"
                ;;
            -sa|--sa|-skip-all|--skip-all)
                SKIP_ALL_DETECTION="true"
                ;;
            -*)
                echo "Warning: Unknown option: $1" >&2
                ;;
            *)
                if [ -z "$SELECTED_LANGUAGE" ]; then
                    SELECTED_LANGUAGE="$1"
                fi
                ;;
        esac
        shift
    done

    # 環境変数設定 (FORCE, SKIP_CACHE を削除)
    export SELECTED_LANGUAGE DEBUG_MODE DEBUG_LEVEL MODE DRY_RUN LOGFILE RESET HELP

    # デバッグ情報を出力 (FORCE, SKIP_CACHE を削除)
    debug_log "DEBUG" "$BIN_FILE: $SCRIPT_VERSION"
    debug_log "DEBUG" "check_option received args: $ORIGINAL_ARGS"
    debug_log "DEBUG" "check_option: MODE=$MODE, SELECTED_LANGUAGE=$SELECTED_LANGUAGE"

    # 設定された言語を `check_common()` に渡す
    check_common "$SELECTED_LANGUAGE" "$MODE"
}

download_files() {
    download "common-system.sh" "chmod" "load"
    download "common-information.sh" "chmod" "load"
    download "common-translation.sh" "chmod" "load"
    download "common-color.sh" "chmod" "load"
    download "common-country.sh" "chmod" "load"
    download "common-menu.sh" "chmod" "load"
    download "common-package.sh" "chmod" "load"
    download "common-feed-package.sh" "chmod" "load"

    download "menu.db"
    download "country.db"
    download "message_${DEFAULT_LANGUAGE}.db"
    download "local-package.db"
    download "custom-package.db"
}

check_common() {
    local lang_code="$SELECTED_LANGUAGE"
    local mode="$MODE"

    debug_log "DEBUG" "check_common: MODE=$MODE"
    debug_log "DEBUG" "check_common: mode=$mode"

    # 言語設定の早期読み込み（追加）
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        debug_log "DEBUG" "Early loading language settings from cache"
        # 初期化フラグを設定して二重初期化を防止
        EARLY_LANG_LOADED=1
    fi

    # モードごとの処理
    case "$mode" in
        reset|return)
            if ! rm -rf "${CACHE_DIR}"; then
                debug_log "DEBUG" "Failed to remove cache directory: ${CACHE_DIR}"
                printf "%s%s%s\n" "$(color yellow "Reset failed: Could not remove cache directory.")"
                return 1
            fi
            # キャッシュディレクトリを再作成
            mkdir -p "${CACHE_DIR}" || {
                debug_log "DEBUG" "Failed to recreate cache directory: ${CACHE_DIR}"
                printf "%s%s%s\n" "$(color yellow "Reset partially failed: Cache removed but could not be recreated.")"
            }
            printf "%s%s%s\n" "$(color yellow "$(get_message "MSG_RESET_COMPLETE")")"
            exit 0
            ;;
        delete)
            if ! rm -rf "${BASE_DIR}"; then
                debug_log "DEBUG" "Failed to remove base directory: ${BASE_DIR}"
                printf "%s%s%s\n" "$(color yellow "Reset failed: Could not remove base directory.")"
                return 1
            fi
            # キャッシュディレクトリを再作成
            mkdir -p "${BASE_DIR}" || {
                debug_log "DEBUG" "Failed to recreate base directory: ${CACHE_DIR}"
                printf "%s%s%s\n" "$(color yellow "Reset partially failed: Base removed but could not be recreated.")"
            }
            printf "%s%s%s\n" "$(color yellow "$(get_message "MSG_DELETE_COMPLETE")")"
            exit 0
            ;;
        debug)
            download "common-system.sh" "hidden" "chmod" "load"
            download "common-information.sh" "hidden" "chmod" "load"
            download "common-color.sh" "hidden" "chmod" "load"
            download "common-country.sh" "hidden" "chmod" "load"
            download "common-menu.sh" "hidden" "chmod" "load"
            download "common-package.sh" "hidden" "chmod" "load"
            download "common-feed-package.sh" "hidden" "chmod" "load"
            download "menu.db" "hidden"
            download "country.db" "hidden"
            download "message_${DEFAULT_LANGUAGE}.db" "hidden"
            download "local-package.db" "hidden"
            download "custom-package.db" "hidden"
            print_information
            information_main
            country_main "$lang_code"
            translate_main
            install_package update
            selector "$MAIN_MENU" 
            return
            ;;
        full)
            download_parallel
            print_information
            information_main
            country_main "$lang_code"
            translate_main
            install_package update
            selector "$MAIN_MENU"
            return
            ;;
        light)
            ;;
        test_api)
            download "github_api_test.sh" "chmod" "load"
            exit 0
            ;;
        *)
            ;;
    esac
    
    return 0
}

# ディレクトリ削除処理
delete_aios() {
    if ! rm -rf "${BASE_DIR}"; then
        debug_log "DEBUG" "Failed to delete $BASE_DIR"
        return 1
    fi
    return 0
}

# 必要ディレクトリ作成
make_directory() {
    if ! mkdir -p "${BASE_DIR}" "$CACHE_DIR" "$LOG_DIR" "$DL_DIR" "$TR_DIR" "$FEED_DIR" "${CACHE_DIR}/commits"; then
        debug_log "DEBUG" "Failed to create required directories"
        return 1
    fi
    
    # .gitignoreファイルの作成（キャッシュディレクトリの内容をgitで無視する）
    if [ ! -f "${CACHE_DIR}/.gitignore" ]; then
        echo "*" > "${CACHE_DIR}/.gitignore" 2>/dev/null
    fi
    
    return 0
}

# シンボリックリンク多段解決対応 resolve_path
resolve_path() {
    local target="$1"
    local dir file
    while [ -L "$target" ]; do
        dir=$(cd "$(dirname "$target")" 2>/dev/null && pwd)
        target=$(readlink "$target")
        case "$target" in
            /*) ;; # 絶対パスならそのまま
            *) target="$dir/$target" ;;
        esac
    done
    dir=$(cd "$(dirname "$target")" 2>/dev/null && pwd)
    file=$(basename "$target")
    BIN_PATH="$dir/$file"
    BIN_DIR="$dir"
    BIN_FILE="$file"
    # printf "%s/%s\n" "$dir" "$file"
}

setup_password_hostname() {
    # パスワード設定（/etc/shadowのrootパスワードが未設定の場合のみ）
    local passwd_field new_password confirm_password
    passwd_field=$(awk -F: '/^root:/ {print $2}' /etc/shadow 2>/dev/null)
    if [ -z "$passwd_field" ] || [ "$passwd_field" = "*" ] || [ "$passwd_field" = "!" ]; then
        while :; do
            printf "%s\n" "$(color yellow "$(get_message "MSG_PASSWORD_NOTICE")")"
            printf "%s" "$(color white "$(get_message "MSG_ENTER_PASSWORD")")"
            read -s new_password
            printf "\n"
            [ -z "$new_password" ] && break
            [ ${#new_password} -lt 8 ] && {
                printf "%s\n\n" "$(color red "$(get_message "MSG_PASSWORD_ERROR")")"
                continue
            }
            printf "%s" "$(color magenta "$(get_message "MSG_CONFIRM_PASSWORD")")"
            read -s confirm_password
            printf "\n"
            [ "$new_password" != "$confirm_password" ] && {
                printf "%s\n" "$(color red "$(get_message "MSG_PASSWORD_ERROR")")"
                continue
            }
            (echo "$new_password"; echo "$new_password") | passwd root 1>/dev/null 2>&1
            if [ $? -eq 0 ]; then
                printf "%s\n" "$(color green "$(get_message "MSG_PASSWORD_SET_OK")")"
                break
            else
                printf "%s\n" "$(color red "$(get_message "MSG_PASSWORD_ERROR")")"
            fi
        done
    fi

    # ホストネーム設定（UCI値のみ初期値時のみ）
    local current_hostname new_hostname
    current_hostname=$(uci get system.@system[0].hostname 2>/dev/null)
    if [ -z "$current_hostname" ] || [ "$current_hostname" = "OpenWrt" ]; then
        printf "\n%s" "$(color white "$(get_message "MSG_ENTER_HOSTNAME")")"
        read new_hostname
        printf "\n"
        if [ -z "$new_hostname" ]; then
            :
        else
            uci set system.@system[0].hostname="$new_hostname"
            uci commit system
            echo "$new_hostname" > /etc/hostname 2>/dev/null
            if [ $? -eq 0 ]; then
                printf "%s\n\n" "$(color green "$(get_message "MSG_HOSTNAME_SET_OK" "h=$new_hostname")")"
            else
                printf "%s\n\n" "$(color red "$(get_message "MSG_HOSTNAME_ERROR")")"
            fi
        fi
    fi

    # SSH LAN設定（UCI値でInterfaceが未設定の場合のみ）
    local dropbear_interface
    dropbear_interface=$(uci get dropbear.@dropbear[0].Interface 2>/dev/null)
    if [ -z "$dropbear_interface" ]; then
        uci set dropbear.@dropbear[0].Interface='lan'
        uci commit dropbear
        /etc/init.d/dropbear restart 1>/dev/null 2>&1
        if [ $? -eq 0 ]; then
            printf "\n%s\n" "$(color white "$(get_message "MSG_SSH_LAN_SET_OK")")"
        else
            printf "%s\n" "$(color red "$(get_message "MSG_SSH_LAN_SET_FAIL")")"
        fi
    fi
}

# 初期化処理のメイン
main() {

    print_banner
    
    setup_password_hostname
    
    resolve_path "$0"

    make_directory
    
    check_network_connectivity
    
    init_device_cache
    
    check_option "$@"
}

# 🔴　メイン　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

# スクリプト実行
main "$@"
 
