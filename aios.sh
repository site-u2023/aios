#!/bin/sh

SCRIPT_VERSION="2025.04.29-00-01"

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
### 📌 AI Assistance Request: POSIX-Compliant Debugging Guide
### 
### When debugging or fixing errors in this POSIX shell script:
### 
### 1️⃣ Create a minimal reproducible test case (avoid bash features)
### 2️⃣ Test with ash/dash explicitly: dash ./test.sh
### 3️⃣ Use portable debugging methods: echo, printf, or set -x
### 4️⃣ Validate fixes against all POSIX compliance guidelines
### 5️⃣ Ensure the solution works in resource-constrained OpenWrt
### 
### ⚠️ IMPORTANT:
### - Avoid suggesting bash-specific solutions
### - Always test fixes with ash/dash before implementation
### - Prefer simple solutions over complex ones
### - Do not modify production code without test verification
### 
### 🛠️ Keep debugging simple, focused, and POSIX-compliant!
### =========================================================

# システム制御
DEV_NULL="${DEV_NULL:-on}"       # サイレントモード制御（on=有効, unset=無効）
DEBUG_MODE="${DEBUG_MODE:-false}" # デバッグモード（true=有効, false=無効）
DOWNLOAD_METHOD="${DOWNLOAD_METHOD:-api}" # ダウンロード方式 (api/direct)
# DOWNLOAD_METHOD="${DOWNLOAD_METHOD:-direct}" # ダウンロード方式 (api/direct)

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
# MAX_PARALLEL_TASKS="$(c=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 1); calculated_tasks=$((c + 1)); if [ "$calculated_tasks" -gt 5 ]; then echo 5; else echo "$calculated_tasks"; fi)"
PARALLEL_LIMIT="5"
CORE_COUNT=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 1)
MAX_PARALLEL_TASKS=$(( (CORE_COUNT + 1 > PARALLEL_LIMIT) * PARALLEL_LIMIT + (CORE_COUNT + 1 <= PARALLEL_LIMIT) * (CORE_COUNT + 1) ))

# ダウンロード関連設定
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}" # 基本URL
CACHE_BUST="?cache_bust=$(date +%s)" # キャッシュバスティングパラメータ

# wget関連設定
BASE_WGET="wget --no-check-certificate -q" # 基本wgetコマンド
BASE_WGET_AUTH_BEARER='wget --no-check-certificate -q -O "$1" --header="Authorization: Bearer $2" "$3"' # Bearer認証用
BASE_WGET_AUTH_TOKEN='wget --no-check-certificate -q -O "$1" --header="Authorization: token $2" "$3"'   # Token認証用

# GitHub API認証関連
GITHUB_TOKEN_FILE="/etc/aios_token" # GitHubトークン保存ファイル
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

# GitHub APIレート制限情報
API_REMAINING=""       # 残りAPI呼び出し回数
API_LIMIT=""           # APIレート制限値
API_RESET_TIME=""      # API制限リセット時間（分）
API_AUTH_METHOD=""     # 認証方法（token/bearer/direct）
API_LAST_CHECK=""      # 最終API確認時間（Unix時間）
API_CACHE_TTL="60"     # APIキャッシュ有効期間（秒）

# コミット情報キャッシュ関連
COMMIT_CACHE_DIR="${CACHE_DIR}/commits" # コミット情報キャッシュディレクトリ
COMMIT_CACHE_TTL="0" # コミットキャッシュ有効期間（30分=1800秒）
SKIP_CACHE="false"     # キャッシュスキップフラグ（true=キャッシュ無視）

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
    printf "  %-25s %s\n" "-u, --update" "$(get_message "MSG_HELP_UPDATE")"
    printf "  %-25s %s\n" "-f, --force" "$(get_message "MSG_HELP_FORCE")"
    printf "  %-25s %s\n" "-t, --token" "$(get_message "MSG_HELP_TOKEN")"
    printf "  %-25s %s\n" "-cf, --common_full" "$(get_message "MSG_HELP_FULL")"
    printf "  %-25s %s\n" "-cl, --common_light" "$(get_message "MSG_HELP_LIGHT")"
    printf "  %-25s %s\n" "-cd, --common_debug" "$(get_message "MSG_HELP_COMMON_DEBUG")"
    printf "  %-25s %s\n" "-dr, --dry-run" "$(get_message "MSG_HELP_DRY_RUN")"
    printf "  %-25s %s\n" "-nc, --no-cache" "Skip using cached version data"
    
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

# 🔴　カラー系　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　メッセージ系　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

# メモリへのメッセージ読み込み関数
into_memory_message() {
    local lang="$DEFAULT_LANGUAGE"
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        lang=$(cat "${CACHE_DIR}/message.ch")
    fi
    
    # メモリメッセージの初期化 - 基本的な補助メッセージのみを保持
    MSG_MEMORY=""
    
    # 基本メッセージの設定

    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_MAX_PARALLEL_TASKS=Maximum number of threads{:} {m}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|DOWNLOAD_PARALLEL_START=Downloading essential files"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|DOWNLOAD_PARALLEL_SUCCESS=Essential files downloaded successfully"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|DOWNLOAD_PARALLEL_FAILED=Parallel download failed in {f}{:} {e}{:}"$'\n'

    MSG_MEMORY="${MSG_MEMORY}${lang}|CONFIG_DOWNLOAD_SUCCESS=Downloaded {f}{v} {api}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|CONFIG_DOWNLOAD_UNNECESSARY=Latest Files{:}"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_RESET_COMPLETE=Reset completed. All cached data has been cleared"$'\n'
    MSG_MEMORY="${MSG_MEMORY}${lang}|MSG_DELETE_COMPLETE=Delete completed. All base data has been cleared"$'\n'
    
    # DBファイルが主要ソース
    
    MSG_MEMORY_INITIALIZED="true"
    MSG_MEMORY_LANG="$lang"
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

# --- get_message function (Handles message retrieval, normalization, and formatting) ---
# Usage: get_message <key> [format_type] [param1=value1] [param2=value2] ...
# format_type: "upper", "capitalize", "none" (default)
# Reads global variables: DEFAULT_LANGUAGE, CACHE_DIR, MSG_MEMORY_INITIALIZED, MSG_MEMORY_LANG, MSG_MEMORY,
#                         GET_MESSAGE_FORMATTING_ENABLED, FORMAT_TYPE_UPPER_ENABLED, FORMAT_TYPE_CAPITALIZE_ENABLED
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
        }
        END {
            # Iterate through parameters to perform replacements
            for (p_name in params) {
                # --- MODIFIED: Build case-insensitive regex dynamically ---
                regex_ci = "\\{" # Start regex with escaped {
                for (i = 1; i <= length(p_name); ++i) {
                    char = substr(p_name, i, 1)
                    lc = tolower(char)
                    uc = toupper(char)
                    # If char is not a letter (lc == uc), append it directly.
                    # Otherwise, append [lL] character class.
                    if (lc == uc) {
                        # Handle potential regex special characters within the name itself
                        # If char is a regex metacharacter that needs escaping, escape it.
                        # Basic example for backslash, extend if needed for ., *, +, ?, etc.
                        if (char == "\\") {
                             regex_ci = regex_ci "\\\\" # Append escaped backslash
                        } else if (char == "[") {
                             regex_ci = regex_ci "\\[" # Append escaped [
                        } else if (char == "]") {
                             regex_ci = regex_ci "\\]" # Append escaped ]
                        # Add other metacharacters like ., *, +, ?, ^, $, | if needed
                        } else {
                            regex_ci = regex_ci char # Append other non-letter chars directly
                        }
                    } else {
                        # Append character class for letters, e.g., [vV]
                        regex_ci = regex_ci "[" lc uc "]"
                    }
                }
                regex_ci = regex_ci "\\}" # End regex with escaped }
                # Example: if p_name is "Value1", regex_ci becomes "\{[vV][aA][lL][uU][eE]1\}"
                # --- END MODIFIED ---

                # Prepare the replacement value: escape \ and & for gsub
                current_value = params[p_name]
                gsub(/\\/, "\\\\", current_value) # Escape backslashes first
                gsub(/&/, "\\&", current_value)   # Escape ampersands

                # Perform the global substitution using the dynamically generated case-insensitive regex
                gsub(regex_ci, current_value, msg)
            }
            print msg # Output the final message
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

# 🔵　ネットワーク系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------

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

# 🔴 ネットワーク系　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------


# 🔵　トークン系　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

# コミット情報をキャッシュに保存する関数
save_commit_to_cache() {
    local file_path="$1"
    local version="$2"
    local auth_method="$3"
    local cache_file="${COMMIT_CACHE_DIR}/$(echo "$file_path" | tr '/' '_').commit"
    local timestamp=$(date +%s)
    
    debug_log "DEBUG" "Saving commit info to cache: $file_path -> $cache_file"
    
    # キャッシュフォルダがなければ作成
    [ -d "${COMMIT_CACHE_DIR}" ] || mkdir -p "${COMMIT_CACHE_DIR}"
    
    # キャッシュファイルに情報を書き込み
    {
        echo "VERSION=$version"
        echo "AUTH_METHOD=$auth_method"
        echo "TIMESTAMP=$timestamp"
        echo "TTL=$COMMIT_CACHE_TTL"
        echo "FILE_PATH=$file_path"
    } > "$cache_file"
    
    return 0
}

# キャッシュからコミット情報を取得する関数
get_commit_from_cache() {
    local file_path="$1"
    local force="$2"  # キャッシュ強制無視フラグ
    local cache_file="${COMMIT_CACHE_DIR}/$(echo "$file_path" | tr '/' '_').commit"
    
    # キャッシュスキップが有効またはforceフラグが指定されている場合はキャッシュを無視
    if [ "$SKIP_CACHE" = "true" ] || [ "$force" = "true" ] || [ "$FORCE" = "true" ]; then
        debug_log "DEBUG" "Skipping cache for $file_path (forced)"
        return 1
    fi
    
    # キャッシュファイルが存在しない場合
    if [ ! -f "$cache_file" ]; then
        debug_log "DEBUG" "No cache found for $file_path"
        return 1
    fi
    
    # キャッシュファイルから情報を読み込む
    . "$cache_file"
    
    # 必須変数が設定されているか確認
    if [ -z "$VERSION" ] || [ -z "$TIMESTAMP" ] || [ -z "$TTL" ]; then
        debug_log "DEBUG" "Invalid cache file for $file_path"
        return 1
    fi
    
    # TTLが0の場合は常にキャッシュを無効とする
    if [ "$TTL" = "0" ]; then
        debug_log "DEBUG" "Cache TTL is set to 0, forcing refresh for $file_path"
        return 1
    fi
    
    # キャッシュが有効期限内かチェック
    local current_time=$(date +%s)
    if [ $(( current_time - TIMESTAMP )) -gt "$TTL" ]; then
        debug_log "DEBUG" "Cache expired for $file_path ($(( (current_time - TIMESTAMP) / 60 )) minutes old)"
        return 1
    fi
    
    # キャッシュが有効な場合は結果を返す
    debug_log "DEBUG" "Using cached commit info for $file_path: $VERSION (age: $(( (current_time - TIMESTAMP) / 60 )) minutes)"
    echo "$VERSION $AUTH_METHOD"
    return 0
}

format_api_status() {
    local auth_method="$1"
    local remaining="$2"
    local limit="$3"
    local reset_minutes="$4"
    local status_text=""
    
    debug_log "DEBUG" "Formatting API status with auth_method=$auth_method, remaining=$remaining, limit=$limit, reset_minutes=$reset_minutes"
    
    if [ "$auth_method" = "token" ] || [ "$auth_method" = "header" ] || [ "$auth_method" = "user" ]; then
        # 認証API表示
        status_text="API: ${remaining}/${limit} TTL:${reset_minutes}m"
    elif [ "$auth_method" = "direct" ] && [ -n "$remaining" ] && [ -n "$limit" ]; then
        # 未認証APIでも残り回数が分かる場合
        status_text="API: ${remaining}/${limit} TTL:${reset_minutes}m"
    else
        # 直接ダウンロード時
        status_text="API: N/A TTL:${reset_minutes}m"
    fi
    
    echo "$status_text"
}

github_api_request() {
    local endpoint="$1"
    local token=$(get_github_token)
    local response=""
    local auth_method="direct"
    local temp_file="${CACHE_DIR}/api_request.tmp"
    local retry_count=0
    local max_retries=2

    # IP version option: use ip_type.ch, fall back to no option (default) if not found or unknown
    local local_wget_ipv_opt=""
    if [ -f "${CACHE_DIR}/ip_type.ch" ]; then
        local_wget_ipv_opt=$(cat "${CACHE_DIR}/ip_type.ch" 2>/dev/null)
        if [ -z "$local_wget_ipv_opt" ] || [ "$local_wget_ipv_opt" = "unknown" ]; then
            echo "Network is not available. (ip_type.ch is unknown or empty)" >&2
            return 1
        fi
    else
        echo "Network is not available. (ip_type.ch not found)" >&2
        return 1
    fi

    # wget command local variables
    local local_base_wget="$BASE_WGET $local_wget_ipv_opt"
    local local_base_wget_auth_bearer="wget --no-check-certificate -q $local_wget_ipv_opt -O \"\$1\" --header=\"Authorization: Bearer \$2\" \"\$3\""
    local local_base_wget_auth_token="wget --no-check-certificate -q $local_wget_ipv_opt -O \"\$1\" --header=\"Authorization: token \$2\" \"\$3\""

    # Check for wget header support
    if [ -z "$WGET_SUPPORTS_HEADER" ]; then
        if wget --help 2>&1 | grep -q -- "--header"; then
            export WGET_SUPPORTS_HEADER=1
        else
            export WGET_SUPPORTS_HEADER=0
        fi
    fi

    # GitHub API call with retry logic
    while [ $retry_count -le $max_retries ]; do
        if [ $retry_count -gt 0 ]; then
            debug_log "DEBUG" "Retry attempt $retry_count for API request: $endpoint"
            sleep 1  # wait before retry
        fi

        if [ -n "$token" ]; then
            debug_log "DEBUG" "Using token authentication for API request"

            # Auth method 1: Bearer header
            if [ "$WGET_SUPPORTS_HEADER" = "1" ]; then
                debug_log "DEBUG" "Trying Bearer authentication"
                eval $local_base_wget_auth_bearer "$temp_file" "$token" "https://api.github.com/$endpoint" 2>/dev/null

                if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
                    response=$(cat "$temp_file")
                    if ! echo "$response" | grep -q '"message":"Bad credentials"'; then
                        auth_method="bearer"
                        debug_log "DEBUG" "Bearer authentication successful"
                        break
                    else
                        debug_log "DEBUG" "Bearer authentication failed, trying token auth"
                        eval $local_base_wget_auth_token "$temp_file" "$token" "https://api.github.com/$endpoint" 2>/dev/null
                        if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
                            response=$(cat "$temp_file")
                            if ! echo "$response" | grep -q '"message":"Bad credentials"'; then
                                auth_method="token"
                                debug_log "DEBUG" "Token authentication successful"
                                break
                            else
                                debug_log "DEBUG" "Token authentication failed"
                            fi
                        fi
                    fi
                else
                    debug_log "DEBUG" "Empty response from Bearer authentication"
                fi
            fi

            # Auth method 2: wget user auth (no header support)
            if [ "$auth_method" = "direct" ] && [ "$WGET_SUPPORTS_HEADER" = "0" ]; then
                debug_log "DEBUG" "Trying user authentication"
                $local_base_wget -O "$temp_file" --user="$token" --password="x-oauth-basic" \
                         "https://api.github.com/$endpoint" 2>/dev/null

                if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
                    response=$(cat "$temp_file")
                    if ! echo "$response" | grep -q '"message":"Bad credentials"'; then
                        auth_method="user"
                        debug_log "DEBUG" "User authentication successful"
                        break
                    else
                        debug_log "DEBUG" "User authentication failed"
                    fi
                fi
            fi
        fi

        # Auth method 3: direct access fallback
        if [ "$auth_method" = "direct" ]; then
            debug_log "DEBUG" "Falling back to direct access"
            $local_base_wget -O "$temp_file" "https://api.github.com/$endpoint" 2>/dev/null

            if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
                response=$(cat "$temp_file")
                if ! echo "$response" | grep -q '"message":"API rate limit exceeded'; then
                    debug_log "DEBUG" "Direct access successful"
                    break
                fi
            fi
        fi

        retry_count=$((retry_count + 1))
    done

    # Check final result after retries
    if [ -z "$response" ]; then
        debug_log "DEBUG" "Empty response from API request after $max_retries retries"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi

    if echo "$response" | grep -q '"message":"API rate limit exceeded'; then
        debug_log "DEBUG" "GitHub API rate limit exceeded"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi

    # Auth error check
    if echo "$response" | grep -q '"message":"Bad credentials"'; then
        debug_log "DEBUG" "GitHub API authentication failed: Bad credentials"
        rm -f "$temp_file" 2>/dev/null
        return 2
    fi

    # Other error check
    if echo "$response" | grep -q '"message":"'; then
        local error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d':' -f2- | tr -d '"')
        debug_log "DEBUG" "GitHub API error: $error_msg"
        rm -f "$temp_file" 2>/dev/null
        return 3
    fi

    # Success
    echo "$response"
    rm -f "$temp_file" 2>/dev/null

    # Restore wget options (no longer necessary, but for compatibility)
    setup_wget_options
    return 0
}

save_github_token() {
    token="$1"
    
    if [ -z "$token" ]; then
        debug_log "DEBUG" "Empty token provided, cannot save"
        return 1
    fi
    
    # トークンを保存して権限を設定
    echo "$token" > "$GITHUB_TOKEN_FILE"
    chmod 600 "$GITHUB_TOKEN_FILE"
    
    if [ $? -eq 0 ]; then
        debug_log "DEBUG" "GitHub token saved to $GITHUB_TOKEN_FILE"
        return 0
    else
        debug_log "DEBUG" "Failed to save token to $GITHUB_TOKEN_FILE"
        return 1
    fi
}

get_github_token() {
    local token=""
    
    if [ -f "$GITHUB_TOKEN_FILE" ] && [ -r "$GITHUB_TOKEN_FILE" ]; then
        # 改行や余分なスペースを削除したトークンを返す
        token=$(cat "$GITHUB_TOKEN_FILE" | tr -d '\n\r\t ' | head -1)
        if [ -n "$token" ]; then
            echo "$token"
            return 0
        fi
    fi
    
    # 環境変数からの取得（不要な文字も削除）
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN" | tr -d '\n\r\t '
        return 0
    fi
    
    return 1
}

# トークンセットアップ関数の改善版
setup_github_token() {
    echo "GitHub API Token Setup"
    echo "======================"
    
    # wget機能チェック
    local wget_capability=$(detect_wget_capabilities)
    debug_log "DEBUG" "Detected wget capability: $wget_capability"
    
    # トークン認証が利用できない場合は警告して終了
    if [ "$wget_capability" = "limited" ]; then
        echo "ERROR: GitHub API token authentication is not supported on this system."
        echo "Your version of wget does not support the required authentication methods."
        echo "API requests will be limited to 60 calls per hour."
        echo ""
        echo "This system uses a wget version without authentication support." 
        debug_log "DEBUG" "Token authentication not supported due to limited wget capabilities"
        return 1
    fi
    
    echo "This will save a GitHub Personal Access Token to $GITHUB_TOKEN_FILE"
    echo "The token will be used for API requests to avoid rate limits."
    echo ""
    
    printf "Enter your GitHub Personal Access Token: "
    read -r token
    echo ""
    
    if [ -n "$token" ]; then
        if save_github_token "$token"; then
            echo "Token has been saved successfully!"
            echo "API requests will now use authentication (up to 5000 calls per hour)."
            echo ""
            
            # 使用可能な認証方法の表示
            case "$wget_capability" in
                header)
                    echo "Your system supports header authentication (optimal)."
                    ;;
                basic)
                    echo "Your system supports basic authentication."
                    ;;
            esac
        else
            echo "Failed to save token. Please check permissions."
        fi
    else
        echo "No token entered. Operation cancelled."
    fi
}

# 🔴　トークン系　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------


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

check_api_rate_limit() {
    local token="$(get_github_token)"
    local temp_file="${CACHE_DIR}/api_limit.tmp"
    local auth_method="direct"
    local current_time=$(date +%s)
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    local WGET_IPV_OPT=""

    # IPバージョン設定（ip_type.ch利用、内容がunknownや空の場合はオプション無し）
    if [ -f "$ip_type_file" ]; then
        WGET_IPV_OPT=$(cat "$ip_type_file" 2>/dev/null)
        if [ -z "$WGET_IPV_OPT" ] || [ "$WGET_IPV_OPT" = "unknown" ]; then
            WGET_IPV_OPT=""
        fi
    else
        WGET_IPV_OPT=""
    fi

    # 先にキャッシュファイルをロード（初回実行時）
    if [ -z "$API_LAST_CHECK" ] && [ -f "${CACHE_DIR}/api_rate.ch" ]; then
        debug_log "DEBUG" "Loading API rate information from cache file"
        . "${CACHE_DIR}/api_rate.ch"
    fi

    # キャッシュ有効期間内の場合は保存値を返す
    if [ -n "$API_REMAINING" ] && [ $(( current_time - API_LAST_CHECK )) -lt ${API_CACHE_TTL:-60} ]; then
        debug_log "DEBUG" "Using cached API rate limit info: $API_REMAINING/$API_LIMIT, age: $(( current_time - API_LAST_CHECK ))s"
        echo "API: ${API_REMAINING}/${API_LIMIT} TTL:${API_RESET_TIME}m"
        return 0
    fi

    # 既存のファイルを削除
    [ -f "$temp_file" ] && rm -f "$temp_file"

    # wget機能と認証方法の検出（一度だけ実行）
    if [ -z "$WGET_CAPABILITY" ] && [ -n "$token" ]; then
        WGET_CAPABILITY=$(detect_wget_capabilities)
        debug_log "DEBUG" "Detected wget capability: $WGET_CAPABILITY"
        if [ "$WGET_CAPABILITY" = "limited" ] && [ -f "$GITHUB_TOKEN_FILE" ]; then
            debug_log "DEBUG" "GitHub token is set but authentication is not supported with current wget version"
        fi
    fi

    # 認証方法の選択
    if [ -n "$token" ] && [ "$WGET_CAPABILITY" != "limited" ]; then
        if [ "$WGET_CAPABILITY" = "header" ]; then
            $BASE_WGET $WGET_IPV_OPT -O "$temp_file" --header="Authorization: token $token" \
                "https://api.github.com/rate_limit" 2>/dev/null

            if [ -f "$temp_file" ] && [ -s "$temp_file" ] && ! grep -q "Bad credentials\|Unauthorized" "$temp_file"; then
                auth_method="token"
                debug_log "DEBUG" "Successfully authenticated with token header"
            fi
        elif [ "$WGET_CAPABILITY" = "basic" ]; then
            $BASE_WGET $WGET_IPV_OPT -O "$temp_file" --user="$token" --password="x-oauth-basic" \
                "https://api.github.com/rate_limit" 2>/dev/null

            if [ -f "$temp_file" ] && [ -s "$temp_file" ] && ! grep -q "Bad credentials\|Unauthorized" "$temp_file"; then
                auth_method="basic"
                debug_log "DEBUG" "Successfully authenticated with basic auth"
            fi
        fi
    fi

    # 非認証リクエスト（認証に失敗した場合または認証なしの場合）
    if [ "$auth_method" = "direct" ]; then
        debug_log "DEBUG" "Making direct API request"
        $BASE_WGET $WGET_IPV_OPT -O "$temp_file" "https://api.github.com/rate_limit" 2>/dev/null
    fi

    # レスポンス解析（元ソース通り）
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        local core_limit=$(grep -o '"limit"[ ]*:[ ]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
        local core_remaining=$(grep -o '"remaining"[ ]*:[ ]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
        local core_reset=$(grep -o '"reset"[ ]*:[ ]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
        if [ -z "$core_limit" ] || [ -z "$core_remaining" ] || [ -z "$core_reset" ]; then
            local core_section=$(sed -n '/"core":/,/},/p' "$temp_file")
            [ -z "$core_limit" ] && core_limit=$(echo "$core_section" | grep -o '"limit"[ ]*:[ ]*[0-9]\+' | head -1 | grep -o '[0-9]\+')
            [ -z "$core_remaining" ] && core_remaining=$(echo "$core_section" | grep -o '"remaining"[ ]*:[ ]*[0-9]\+' | head -1 | grep -o '[0-9]\+')
            [ -z "$core_reset" ] && core_reset=$(echo "$core_section" | grep -o '"reset"[ ]*:[ ]*[0-9]\+' | head -1 | grep -o '[0-9]\+')
        fi
        local reset_minutes=60
        if [ -n "$core_reset" ] && [ "$core_reset" -gt 1000000000 ]; then
            local now_time=$(date +%s)
            if [ "$core_reset" -gt "$now_time" ]; then
                local reset_seconds=$(( core_reset - now_time ))
                reset_minutes=$(( reset_seconds / 60 ))
                [ "$reset_minutes" -lt 1 ] && reset_minutes=1
            else
                reset_minutes=0
            fi
        else
            if [ "$auth_method" != "direct" ]; then
                reset_minutes=60
            else
                reset_minutes=5
            fi
        fi
        API_REMAINING=$core_remaining
        API_LIMIT=$core_limit
        API_RESET_TIME=$reset_minutes
        API_AUTH_METHOD=$auth_method
        API_LAST_CHECK=$current_time
        [ -z "$API_LIMIT" ] && API_LIMIT="?"
        [ -z "$API_REMAINING" ] && API_REMAINING="?"
    else
        if [ "$auth_method" != "direct" ]; then
            API_LIMIT="5000"
            API_REMAINING="?"
            API_RESET_TIME="60"
        else
            API_LIMIT="60"
            API_REMAINING="?"
            API_RESET_TIME="5"
        fi
        API_AUTH_METHOD=$auth_method
        API_LAST_CHECK=$current_time
    fi

    save_api_rate_cache

    local status_text="API: ${API_REMAINING}/${API_LIMIT} TTL:${API_RESET_TIME}m"
    debug_log "DEBUG" "Final API status: $status_text (auth_method=$auth_method)"

    [ -f "$temp_file" ] && rm -f "$temp_file"

    echo "$status_text"
}

# キャッシュにAPIレート制限情報を保存
save_api_rate_cache() {
    local cache_file="${CACHE_DIR}/api_rate.ch"
    
    # キャッシュディレクトリがなければ作成
    [ ! -d "$CACHE_DIR" ] && mkdir -p "$CACHE_DIR"
    
    # 保存内容の作成
    {
        echo "API_REMAINING=\"$API_REMAINING\""
        echo "API_LIMIT=\"$API_LIMIT\""
        echo "API_RESET_TIME=\"$API_RESET_TIME\""
        echo "API_AUTH_METHOD=\"$API_AUTH_METHOD\""
        echo "API_LAST_CHECK=\"$API_LAST_CHECK\""
    } > "$cache_file"
    
    debug_log "DEBUG" "API rate info cached to $cache_file"
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

get_commit_version() {
    local file_path="$1"
    local force_refresh="$2"  # キャッシュ強制更新フラグ
    local temp_file="${CACHE_DIR}/commit_info_$(echo "$file_path" | tr '/' '_').tmp" # ファイルごとに一意なAPI一時ファイル名
    local direct_file="${CACHE_DIR}/direct_file_$(echo "$file_path" | tr '/' '_').tmp" # ファイルごとに一意なDirect一時ファイル名
    local repo_owner="site-u2023" # リポジトリ情報はローカル変数として定義
    local repo_name="aios"
    local version="EMPTY_VERSION" # デバッグ用の初期値
    local auth_method="unknown"   # デバッグ用の初期値

    debug_log "DEBUG" "get_commit_version: Starting for file='$file_path', force_refresh='$force_refresh', DOWNLOAD_METHOD='$DOWNLOAD_METHOD', SKIP_CACHE='$SKIP_CACHE'"

    # --- DOWNLOAD_METHOD による分岐 ---
    if [ "$DOWNLOAD_METHOD" = "direct" ]; then
        debug_log "DEBUG" "get_commit_version: Direct download mode enabled for $file_path."

        # --- 直接ダウンロード処理 ---
        local retry_count=0
        local direct_download_success=0
        while [ $retry_count -le 1 ]; do
            # IPバージョン取得（ip_type.ch利用、unknownや空ならオプション無し）
            local current_wget_opt=""
            if [ -f "${CACHE_DIR}/ip_type.ch" ]; then
                current_wget_opt=$(cat "${CACHE_DIR}/ip_type.ch" 2>/dev/null)
                if [ -z "$current_wget_opt" ] || [ "$current_wget_opt" = "unknown" ]; then
                    current_wget_opt=""
                fi
            fi

            # リトライ時のIP切り替えはv4v6/v6/v4指定に依存しない（ip_type.chのみ参照、network.chは廃止）
            # （もしリトライ時にIPトグルが必要な場合は、ip_type.chの運用で切り替える）

            rm -f "$direct_file" 2>/dev/null # ダウンロード前に一時ファイルを削除
            debug_log "DEBUG" "get_commit_version(direct): Attempting download with wget opt '$current_wget_opt' to '$direct_file'"
            if wget -q --no-check-certificate ${current_wget_opt} -O "$direct_file" "https://raw.githubusercontent.com/$repo_owner/$repo_name/main/$file_path" 2>/dev/null; then
                debug_log "DEBUG" "get_commit_version(direct): wget command finished for '$direct_file'."
                if [ -s "$direct_file" ]; then
                    debug_log "DEBUG" "get_commit_version(direct): File '$direct_file' downloaded successfully and is not empty. Calculating hash."
                    local file_hash=$(sha256sum "$direct_file" 2>/dev/null | cut -c1-7)
                    rm -f "$direct_file" 2>/dev/null # ハッシュ取得後に一時ファイルを削除
                    local today=$(date +%Y.%m.%d)
                    version="$today-$file_hash" # version 変数を設定
                    auth_method="direct"        # auth_method 変数を設定
                    direct_download_success=1
                    debug_log "DEBUG" "get_commit_version(direct): Hash calculated: '$file_hash'. Generated version: '$version'. Auth: '$auth_method'."

                    setup_wget_options # wget設定を元に戻す
                    echo "$version $auth_method" # 最終的な出力
                    return 0
                else
                    debug_log "DEBUG" "get_commit_version(direct): wget command succeeded but '$direct_file' is empty or not found after download."
                    rm -f "$direct_file" 2>/dev/null
                fi
            else
                local wget_status=$?
                debug_log "DEBUG" "get_commit_version(direct): wget command failed with status $wget_status for '$direct_file'."
            fi
            retry_count=$((retry_count + 1))
            if [ $retry_count -le 1 ]; then sleep 1; fi # リトライ前に待機
        done # direct モードの while ループの終わり

        # 直接ダウンロード失敗時の処理
        debug_log "DEBUG" "get_commit_version(direct): Failed to download file directly after retries: $file_path"
        rm -f "$direct_file" 2>/dev/null
        setup_wget_options
        version="$(date +%Y.%m.%d)-unknown" # version 変数を設定
        auth_method="direct"                # auth_method 変数を設定
        debug_log "DEBUG" "get_commit_version(direct): Returning fallback version: '$version $auth_method'"
        echo "$version $auth_method" # 最終的な出力
        return 1
        # --- 直接ダウンロード処理ここまで ---

    fi # DOWNLOAD_METHOD = "direct" の if の終わり
    # --- DOWNLOAD_METHOD による分岐ここまで ---

    # --- 以下、DOWNLOAD_METHOD = "api" の場合の処理 ---
    debug_log "DEBUG" "get_commit_version(api): API download mode enabled for $file_path."

    # --- キャッシュチェック処理 ---
    local cache_checked="false"
    local proceed_to_api="true" # デフォルトはAPI呼び出しに進む

    if [ "$SKIP_CACHE" != "true" ] && [ "$force_refresh" != "true" ] && [ "$FORCE" != "true" ]; then
        cache_checked="true"
        debug_log "DEBUG" "get_commit_version(api): Attempting to retrieve from commit cache for '$file_path'."
        local cache_result=$(get_commit_from_cache "$file_path")
        local cache_status=$? # get_commit_from_cache の終了ステータス

        # キャッシュヒットの判定: ステータスが0 かつ 結果が空でないこと
        if [ $cache_status -eq 0 ] && [ -n "$cache_result" ]; then
            debug_log "DEBUG" "get_commit_version(api): Valid cache hit for '$file_path'. Returning cached value: '$cache_result'"
            echo "$cache_result"
            return 0 # キャッシュヒット、ここで終了
        else
            # キャッシュミスまたは無効なキャッシュの場合のログ
            if [ $cache_status -ne 0 ]; then
                 debug_log "DEBUG" "get_commit_version(api): Cache miss or invalid for '$file_path' (status: $cache_status)."
            elif [ -z "$cache_result" ]; then
                 # ステータスは0だが結果が空だった場合 (本来は起こらないはずだが念のため)
                 debug_log "DEBUG" "get_commit_version(api): Cache status was 0 but result was empty for '$file_path'. Treating as cache miss."
            fi
            proceed_to_api="true" # API呼び出しに進む
        fi
    else
         debug_log "DEBUG" "get_commit_version(api): Cache skipped for '$file_path' due to flags."
         proceed_to_api="true" # API呼び出しに進む
    fi # キャッシュチェックの if の終わり
    # --- キャッシュチェック処理ここまで ---

    # --- API呼び出しに進む場合のみ以下の処理を実行 ---
    if [ "$proceed_to_api" = "true" ]; then
        # API URL と認証方法の初期化
        local api_url="repos/${repo_owner}/${repo_name}/commits?path=${file_path}&per_page=1"
        auth_method="direct" # APIモードでも最初は direct から試す可能性がある (初期値)
        local retry_count=0
        local max_retries=2
        local token="$(get_github_token)"
        local api_call_successful="false" # API呼び出し成功フラグ

        # API呼び出しを試行（リトライロジック付き）
        while [ $retry_count -le $max_retries ]; do
            if [ $retry_count -gt 0 ]; then
                debug_log "DEBUG" "get_commit_version(api): Retry attempt $retry_count for API request: $file_path"
                sleep 1
            fi

            # IPバージョン取得（ip_type.ch利用、unknownや空ならオプション無し）
            local current_wget_opt=""
            if [ -f "${CACHE_DIR}/ip_type.ch" ]; then
                current_wget_opt=$(cat "${CACHE_DIR}/ip_type.ch" 2>/dev/null)
                if [ -z "$current_wget_opt" ] || [ "$current_wget_opt" = "unknown" ]; then
                    current_wget_opt=""
                fi
            fi

            # 認証方法に応じたAPI呼び出し
            rm -f "$temp_file" 2>/dev/null # API呼び出し前に一時ファイルを削除
            local current_api_auth_method="direct" # この試行での認証方法
            debug_log "DEBUG" "get_commit_version(api): Attempting API call. Token available: $( [ -n "$token" ] && echo "yes" || echo "no" ). WGET_CAPABILITY: '$WGET_CAPABILITY'. API_AUTH_METHOD (cached): '$API_AUTH_METHOD'."

            if [ -n "$token" ] && [ "$API_AUTH_METHOD" != "direct" ]; then # トークンがあり、キャッシュされた認証方法が direct 以外
                 if [ "$API_AUTH_METHOD" = "token" ] || [ "$WGET_CAPABILITY" = "header" ]; then
                     debug_log "DEBUG" "get_commit_version(api): Trying wget with token header auth."
                     wget -q --no-check-certificate ${current_wget_opt} -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/$api_url" 2>/dev/null
                     current_api_auth_method="token"
                 elif [ "$API_AUTH_METHOD" = "basic" ] || [ "$WGET_CAPABILITY" = "basic" ]; then
                     debug_log "DEBUG" "get_commit_version(api): Trying wget with basic auth."
                     wget -q --no-check-certificate ${current_wget_opt} -O "$temp_file" --user="$token" --password="x-oauth-basic" "https://api.github.com/$api_url" 2>/dev/null
                     current_api_auth_method="basic"
                 else
                     debug_log "DEBUG" "get_commit_version(api): Token available but no supported auth method found in cache/capability. Trying direct."
                     wget -q --no-check-certificate ${current_wget_opt} -O "$temp_file" "https://api.github.com/$api_url" 2>/dev/null
                     current_api_auth_method="direct" # フォールバック
                 fi
            else # トークンがない、またはキャッシュされた認証方法が direct
                debug_log "DEBUG" "get_commit_version(api): Trying wget with direct API call (no auth)."
                wget -q --no-check-certificate ${current_wget_opt} -O "$temp_file" "https://api.github.com/$api_url" 2>/dev/null
                current_api_auth_method="direct"
            fi # 認証方法分岐の if の終わり
            local wget_api_status=$?
            debug_log "DEBUG" "get_commit_version(api): wget API call finished with status $wget_api_status. Auth method tried: $current_api_auth_method."

            # 応答チェック
            if [ -s "$temp_file" ]; then
                debug_log "DEBUG" "get_commit_version(api): API response file '$temp_file' exists and is not empty."
                # エラーメッセージが含まれていないか確認
                if ! grep -q "API rate limit exceeded\|Not Found\|Bad credentials" "$temp_file"; then
                    debug_log "DEBUG" "get_commit_version(api): Successfully retrieved valid commit information via API."
                    auth_method=$current_api_auth_method # 成功した認証方法を保存
                    api_call_successful="true"
                    break # 成功したらループを抜ける
                else
                    debug_log "DEBUG" "get_commit_version(api): API response file '$temp_file' contains error messages."
                    # エラー内容をログに出力
                    grep "message" "$temp_file" | while IFS= read -r line; do debug_log "DEBUG" "  API Error: $line"; done
                fi # grep エラーチェックの if の終わり
            else
                 debug_log "DEBUG" "get_commit_version(api): API response file '$temp_file' is empty or not found after wget call."
            fi # 応答チェックの if の終わり

            retry_count=$((retry_count + 1))
            if [ $retry_count -le $max_retries ]; then sleep 1; fi
        done # API 呼び出しリトライの while の終わり

        # --- API呼び出し成功時の処理 ---
        if [ "$api_call_successful" = "true" ]; then
            debug_log "DEBUG" "get_commit_version(api): Processing successful API response from '$temp_file'."
            # APIレスポンスからコミット情報を抽出
            local commit_date=""
            local commit_sha=""

            # SHA抽出 (より堅牢な方法を試みる)
            commit_sha=$(grep -o '"sha"[[:space:]]*:[[:space:]]*"[a-f0-9]\{7,40\}"' "$temp_file" | head -1 | cut -d'"' -f4 | head -c 7)
            if [ -z "$commit_sha" ]; then # 最初のgrepが失敗した場合のフォールバック
                 commit_sha=$(grep -o '[a-f0-9]\{40\}' "$temp_file" | head -1 | head -c 7)
                 if [ -n "$commit_sha" ]; then debug_log "DEBUG" "get_commit_version(api): Extracted SHA using fallback grep: '$commit_sha'"; fi
            else
                 debug_log "DEBUG" "get_commit_version(api): Extracted SHA using primary grep: '$commit_sha'"
            fi # SHA抽出の if/else の終わり

            # 日付抽出 (より堅牢な方法を試みる)
            commit_date=$(grep -o '"date"[[:space:]]*:[[:space:]]*"[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T' "$temp_file" | head -1 | cut -d'"' -f4 | cut -dT -f1)
            if [ -z "$commit_date" ]; then # 最初のgrepが失敗した場合のフォールバック
                commit_date=$(grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z' "$temp_file" | head -1 | cut -dT -f1)
                 if [ -n "$commit_date" ]; then debug_log "DEBUG" "get_commit_version(api): Extracted Date using fallback grep: '$commit_date'"; fi
            else
                debug_log "DEBUG" "get_commit_version(api): Extracted Date using primary grep: '$commit_date'"
            fi # 日付抽出の if/else の終わり

            # 情報が取得できない場合はフォールバック
            if [ -z "$commit_date" ] || [ -z "$commit_sha" ]; then
                debug_log "DEBUG" "get_commit_version(api): Failed to extract commit SHA ('$commit_sha') or Date ('$commit_date') from API response. Using fallback values."
                # 念のため再度試行
                [ -z "$commit_sha" ] && commit_sha=$(tr -cd 'a-f0-9' < "$temp_file" | grep -o '[a-f0-9]\{40\}' | head -1 | head -c 7)
                [ -z "$commit_date" ] && commit_date=$(grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' "$temp_file" | head -1)

                [ -z "$commit_sha" ] && commit_sha="unknownsha" # より明確なフォールバック値
                [ -z "$commit_date" ] && commit_date=$(date +%Y-%m-%d)
                debug_log "DEBUG" "get_commit_version(api): Using fallback SHA='$commit_sha', Date='$commit_date'."
                # 抽出失敗時は認証方法を fallback とする
                auth_method="fallback"
            fi # 抽出失敗チェックの if の終わり

            # 結果の組み立て
            if [ -n "$commit_date" ] && [ -n "$commit_sha" ]; then
                local formatted_date=$(echo "$commit_date" | tr '-' '.')
                version="${formatted_date}-${commit_sha}" # version 変数を設定
                debug_log "DEBUG" "get_commit_version(api): Successfully generated version: '$version'. Auth: '$auth_method'."

                rm -f "$temp_file" 2>/dev/null
                setup_wget_options # ここで wget オプションを戻す
                save_commit_to_cache "$file_path" "$version" "$auth_method" # API成功時の認証方法を使う
                echo "$version $auth_method" # 最終的な出力
                return 0
            else
                # このポイントに到達することは通常ないはずだが、念のためエラーログ
                debug_log "DEBUG" "get_commit_version(api): Reached unexpected point after API success processing (date or sha empty). SHA='$commit_sha', Date='$commit_date'."
                # ここで return せずに下の API 失敗処理に進む方が安全かもしれない
            fi # バージョン生成チェックの if/else の終わり
        fi # api_call_successful = true の if の終わり

        # --- APIでの取得に失敗した場合: 直接ファイルダウンロードを試行 (APIモードのフォールバック) ---
        # api_call_successful が false の場合、または true だったが情報抽出・生成に失敗した場合
        if [ "$api_call_successful" = "false" ] || { [ "$api_call_successful" = "true" ] && [ -z "$version" ]; }; then
            # API成功でも version が空の場合のログを追加
            if [ "$api_call_successful" = "true" ] && [ -z "$version" ]; then
                 debug_log "DEBUG" "get_commit_version(api): API call was successful but version generation failed. Falling back to direct download."
            fi

            debug_log "DEBUG" "get_commit_version(api): API call failed or version gen failed, falling back to direct file check for $file_path (API mode fallback)"
            rm -f "$temp_file" 2>/dev/null # 不要なAPI応答ファイルを削除

            # --- 直接ダウンロード処理 (APIフォールバック用) ---
            retry_count=0 # リトライカウントをリセット
            local direct_download_fallback_success=0
            while [ $retry_count -le 1 ]; do
                # IPバージョン取得（ip_type.ch利用、unknownや空ならオプション無し）
                local current_wget_opt=""
                if [ -f "${CACHE_DIR}/ip_type.ch" ]; then
                    current_wget_opt=$(cat "${CACHE_DIR}/ip_type.ch" 2>/dev/null)
                    if [ -z "$current_wget_opt" ] || [ "$current_wget_opt" = "unknown" ]; then
                        current_wget_opt=""
                    fi
                fi

                rm -f "$direct_file" 2>/dev/null
                debug_log "DEBUG" "get_commit_version(api-fallback): Attempting download with wget opt '$current_wget_opt' to '$direct_file'"
                if wget -q --no-check-certificate ${current_wget_opt} -O "$direct_file" "https://raw.githubusercontent.com/$repo_owner/$repo_name/main/$file_path" 2>/dev/null; then
                    debug_log "DEBUG" "get_commit_version(api-fallback): wget command finished for '$direct_file'."
                    if [ -s "$direct_file" ]; then
                        debug_log "DEBUG" "get_commit_version(api-fallback): File '$direct_file' downloaded successfully. Calculating hash."
                        local file_hash=$(sha256sum "$direct_file" 2>/dev/null | cut -c1-7)
                        rm -f "$direct_file" 2>/dev/null
                        local today=$(date +%Y.%m.%d)
                        version="$today-$file_hash" # version 変数を設定
                        auth_method="directfallback" # APIフォールバックでのdirectアクセスを示す
                        direct_download_fallback_success=1
                        debug_log "DEBUG" "get_commit_version(api-fallback): Hash calculated: '$file_hash'. Generated version: '$version'. Auth: '$auth_method'."

                        setup_wget_options
                        save_commit_to_cache "$file_path" "$version" "$auth_method" # API失敗->Direct成功時もキャッシュ
                        echo "$version $auth_method" # 最終的な出力
                        return 0
                    else
                        debug_log "DEBUG" "get_commit_version(api-fallback): wget succeeded but '$direct_file' is empty or not found."
                        rm -f "$direct_file" 2>/dev/null
                    fi # ファイル存在チェックの if/else の終わり
                else
                     local wget_fb_status=$?
                     debug_log "DEBUG" "get_commit_version(api-fallback): wget command failed with status $wget_fb_status for '$direct_file'."
                fi # wget 成功チェックの if/else の終わり
                retry_count=$((retry_count + 1))
                if [ $retry_count -le 1 ]; then sleep 1; fi # リトライ前に待機
            done # Direct フォールバックリトライの while の終わり

            # 直接ダウンロードも失敗した場合 (APIフォールバック)
            debug_log "DEBUG" "get_commit_version(api-fallback): Failed to download file directly after retries: $file_path"
            rm -f "$direct_file" "$temp_file" 2>/dev/null
            setup_wget_options
            version="$(date +%Y.%m.%d)-apifail" # version 変数を設定
            auth_method="apifail"             # auth_method 変数を設定
            debug_log "DEBUG" "get_commit_version(api-fallback): Returning fallback version: '$version $auth_method'"
            echo "$version $auth_method" # 最終的な出力
            return 1
            # --- 直接ダウンロード処理 (APIフォールバック用) ここまで ---
        fi # API失敗 or version生成失敗の if の終わり
    fi # proceed_to_api = true の if の終わり

    # --- 全ての方法が失敗した場合 (通常ここには到達しないはず) ---
    # proceed_to_api が false (キャッシュヒットしたが return されなかった場合など、異常系)
    debug_log "DEBUG" "get_commit_version: Reached end of function unexpectedly for file '$file_path'. This should not happen."
    rm -f "$temp_file" "$direct_file" 2>/dev/null
    setup_wget_options
    version="$(date +%Y.%m.%d)-critical" # version 変数を設定
    auth_method="critical"             # auth_method 変数を設定
    echo "$version $auth_method" # 念のための最終出力
    return 1
}

# save_version_to_cache 関数 (grep -v ステータス処理修正)
# 変更点:
# 1. grep -v 実行後の終了ステータスチェックを修正。
#    ステータス 0 (成功) または 1 (指定パターンにマッチする行を除外した結果、何も残らなかった) を成功とみなし、
#    それ以外のステータス (2以上) をエラーとして扱うように変更。
save_version_to_cache() {
    local file_name="$1"
    local version="$2"
    local script_file="$3"
    local tmp_file="${script_file}.tmp.$$" # プロセス固有の一時ファイル名
    local lock_dir="${script_file}.lock"  # ロック用ディレクトリパス
    local lock_acquired=0                 # ロック取得フラグ (0: 未取得, 1: 取得済)

    debug_log "DEBUG" "save_version_to_cache: Called for file='$file_name', version='$version', script_file='$script_file', tmp_file='$tmp_file', lock_dir='$lock_dir'"

    if [ -z "$version" ]; then
        debug_log "DEBUG" "save_version_to_cache: Received empty version for file '$file_name'. Aborting cache save."
        return 1 # バージョンが空なら失敗
    fi

    # --- ロック取得試行 ---
    if mkdir "$lock_dir" 2>/dev/null; then
        lock_acquired=1
        debug_log "DEBUG" "save_version_to_cache: Lock acquired: $lock_dir"
    else
        debug_log "DEBUG" "save_version_to_cache: Could not acquire lock '$lock_dir', another process might be updating. Skipping cache update for '$file_name'."
        return 0 # ロック失敗は致命的エラーではないため成功として扱う (更新スキップ)
    fi

    # --- クリティカルセクション (ロック取得時のみ実行) ---
    local return_status=0 # このセクション内での処理ステータス

    # script_file が存在する場合の処理
    if [ -f "$script_file" ]; then
        debug_log "DEBUG" "save_version_to_cache [Lock acquired]: File '$script_file' exists. Filtering existing entry for '$file_name'."
        grep -v "^${file_name}=" "$script_file" > "$tmp_file"
        local grep_status=$?
        if [ "$grep_status" -eq 0 ] || [ "$grep_status" -eq 1 ]; then
            # ステータス 0 (成功) または 1 (マッチなし) は正常
            debug_log "DEBUG" "save_version_to_cache [Lock acquired]: Successfully filtered '$script_file' to '$tmp_file' (grep status: $grep_status)."
        else
            # ステータス 2 以上は grep コマンド自体のエラー
            debug_log "DEBUG" "save_version_to_cache [Lock acquired]: grep command failed with status $grep_status for '$script_file'."
            return_status=1 # 失敗ステータスを設定
        fi

        if [ "$return_status" -eq 0 ]; then
            debug_log "DEBUG" "save_version_to_cache [Lock acquired]: Appending new version '$version' for '$file_name' to '$tmp_file'."
            echo "${file_name}=${version}" >> "$tmp_file"

            if mv "$tmp_file" "$script_file"; then
                debug_log "DEBUG" "save_version_to_cache [Lock acquired]: Successfully moved '$tmp_file' to '$script_file'."
            else
                local mv_status=$?
                debug_log "DEBUG" "save_version_to_cache [Lock acquired]: mv command failed with status $mv_status. Failed to update '$script_file'."
                return_status=1 # 失敗ステータスを設定
                # mv失敗時は一時ファイルが残る可能性があるため削除
                rm -f "$tmp_file" 2>/dev/null
            fi
        else
             # grep失敗時は一時ファイルを削除
             rm -f "$tmp_file" 2>/dev/null
        fi
    else
        # script_file が存在しない場合の処理
        debug_log "DEBUG" "save_version_to_cache [Lock acquired]: File '$script_file' does not exist. Creating new file."
        if echo "${file_name}=${version}" > "$script_file"; then
             debug_log "DEBUG" "save_version_to_cache [Lock acquired]: Successfully created '$script_file' with initial version."
        else
             local echo_status=$?
             debug_log "DEBUG" "save_version_to_cache [Lock acquired]: echo command failed with status $echo_status. Failed to create '$script_file'."
             return_status=1 # 失敗ステータスを設定
        fi
    fi

    # --- ロック解放 ---
    if [ "$lock_acquired" -eq 1 ]; then
        if rmdir "$lock_dir"; then
            debug_log "DEBUG" "save_version_to_cache: Lock released: $lock_dir"
        else
            debug_log "DEBUG" "save_version_to_cache: Failed to release lock '$lock_dir'. Manual cleanup might be needed."
            # ロック解除失敗は関数の成否には影響させない
        fi
    fi

    return $return_status
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

    # バージョン管理
    local remote_version_info remote_version auth_method local_version
    remote_version_info=$(get_commit_version "$file_name" "$force_mode")
    if [ $? -ne 0 ] || [ -z "$remote_version_info" ]; then
        debug_log "DEBUG" "download: Failed to get remote version for $file_name"
        return 1
    fi
    remote_version=$(echo "$remote_version_info" | cut -d' ' -f1)
    auth_method=$(echo "$remote_version_info" | cut -d' ' -f2)

    # ローカルバージョン
    local script_file="${CACHE_DIR}/script.ch"
    if [ -f "$script_file" ]; then
        local_version=$(grep "^${file_name}=" "$script_file" | cut -d'=' -f2)
    fi
    [ -z "$local_version" ] && local_version=""

    local file_path="${BASE_DIR}/${file_name}"

    # 強制DL判定
    if [ "$force_mode" = "true" ]; then
        debug_log "DEBUG" "download: force mode enabled for $file_name"
    fi

    # バージョン一致判定（force未指定時のみスキップ）
    if [ "$force_mode" != "true" ] && [ "$remote_version" = "$local_version" ] && [ -f "$file_path" ]; then
        debug_log "DEBUG" "download: Local version up-to-date for $file_name ($local_version); skipping download."
        # chmod要求ありなら実行
        if [ "$chmod_mode" = "true" ]; then
            chmod +x "$file_path" 2>/dev/null || debug_log "DEBUG" "download: chmod +x failed for existing file $file_path"
        fi
        # シングル時のみ最新版メッセージ出力（抑制/隠し/静音モード除外）
        if [ "$hidden_mode" = "false" ] && [ "$quiet_mode" = "false" ]; then
            printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_UNNECESSARY" "f=$file_name" "v=$remote_version" "api=")"
        fi
        # 最新でもload_modeが有効ならsourceする
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

    local api_status
    if [ "$quiet_mode" = "false" ]; then
        api_status=$(check_api_rate_limit)
        debug_log "DEBUG" "download: API status: $api_status"
    else
        api_status="(Checked)" # 並列中はチェック済みとして表示
    fi

    if ! download_fetch_file "$file_name" "$remote_version" "$chmod_mode"; then
        debug_log "DEBUG" "download: download_fetch_file failed for $file_name"
        return 1
    fi

    if [ -n "$remote_version" ]; then
        if ! save_version_to_cache "$file_name" "$remote_version" "${CACHE_DIR}/script.ch" "$auth_method"; then
            debug_log "DEBUG" "download: save_version_to_cache failed for $file_name, but download itself succeeded."
        fi
    fi

    if [ "$chmod_mode" = "true" ]; then
        chmod +x "$file_path" 2>/dev/null || debug_log "DEBUG" "download: chmod +x failed after download for $file_path"
    fi

    # シングル時のみDL成功メッセージ表示（抑制/隠し/静音モード除外）
    if [ "$hidden_mode" = "false" ] && [ "$quiet_mode" = "false" ]; then
        printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_SUCCESS" "f=$file_name" "v=$remote_version" "api=$api_status")"
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

OK_download() {
    local file_name="$1"
    shift

    # デフォルト設定（local宣言は1回のみ！）
    local suppress_message="false"
    local chmod_mode="false"
    local force_mode="false"
    local hidden_mode="false"
    local quiet_mode="false"
    local interpreter_name=""
    local load_mode="false"

    # download_parallel 内のサブシェルから呼び出されたかを示すフラグ
    if [ "$IN_PARALLEL_DOWNLOAD" = "true" ]; then
        suppress_message="true"
        debug_log "DEBUG" "download: Running inside parallel task, suppressing individual success message for $file_name."
    fi

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

    # バージョン管理
    local remote_version_info remote_version auth_method local_version
    remote_version_info=$(get_commit_version "$file_name" "$force_mode")
    if [ $? -ne 0 ] || [ -z "$remote_version_info" ]; then
        debug_log "DEBUG" "download: Failed to get remote version for $file_name"
        return 1 # 失敗時は 1 を返す
    fi
    remote_version=$(echo "$remote_version_info" | cut -d' ' -f1)
    auth_method=$(echo "$remote_version_info" | cut -d' ' -f2)

    # ローカルバージョン
    local script_file="${CACHE_DIR}/script.ch"
    if [ -f "$script_file" ]; then
        local_version=$(grep "^${file_name}=" "$script_file" | cut -d'=' -f2)
    fi
    [ -z "$local_version" ] && local_version=""

    local file_path="${BASE_DIR}/${file_name}"

    # 強制DL判定
    if [ "$force_mode" = "true" ]; then
        debug_log "DEBUG" "download: force mode enabled for $file_name"
    fi

    # バージョン一致判定（force未指定時のみスキップ）
    if [ "$force_mode" != "true" ] && [ "$remote_version" = "$local_version" ] && [ -f "$file_path" ]; then
        debug_log "DEBUG" "download: Local version up-to-date for $file_name ($local_version); skipping download."
        # chmod要求ありなら実行
        if [ "$chmod_mode" = "true" ]; then
            chmod +x "$file_path" 2>/dev/null || debug_log "DEBUG" "download: chmod +x failed for existing file $file_path"
        fi
        # シングル時のみ最新版メッセージ出力（抑制/隠し/静音モード除外）
        if [ "$suppress_message" = "false" ] && [ "$hidden_mode" = "false" ] && [ "$quiet_mode" = "false" ]; then
            printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_UNNECESSARY" "f=$file_name" "v=$remote_version" "api=")"
        fi
        # 最新でもload_modeが有効ならsourceする
        if [ "$load_mode" = "true" ] && [ "$IN_PARALLEL_DOWNLOAD" != "true" ]; then
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

    # DL処理
    local api_status
    if [ "$suppress_message" = "false" ]; then
        api_status=$(check_api_rate_limit)
        debug_log "DEBUG" "download: API status: $api_status"
    else
        api_status="(Checked)" # 並列中はチェック済みとして表示
    fi

    if ! download_fetch_file "$file_name" "$remote_version" "$chmod_mode"; then
        debug_log "DEBUG" "download: download_fetch_file failed for $file_name"
        return 1 # 失敗時は 1 を返す（失敗時メッセージは表示しない）
    fi

    # バージョンキャッシュ保存
    if [ -n "$remote_version" ]; then
        if ! save_version_to_cache "$file_name" "$remote_version" "${CACHE_DIR}/script.ch" "$auth_method"; then
            debug_log "DEBUG" "download: save_version_to_cache failed for $file_name, but download itself succeeded."
        fi
    fi

    # chmod (download_fetch_file 内でも実行されるが、念のためここでも)
    if [ "$chmod_mode" = "true" ]; then
        chmod +x "$file_path" 2>/dev/null || debug_log "DEBUG" "download: chmod +x failed after download for $file_path"
    fi

    # シングル時のみDL成功メッセージ表示（抑制/隠し/静音モード除外）
    if [ "$suppress_message" = "false" ] && [ "$hidden_mode" = "false" ] && [ "$quiet_mode" = "false" ]; then
        printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_SUCCESS" "f=$file_name" "v=$remote_version" "api=$api_status")"
    fi

    # load_modeが有効ならsource
    if [ "$load_mode" = "true" ] && [ "$IN_PARALLEL_DOWNLOAD" != "true" ]; then
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

OK_download() {
    local file_name="$1"
    shift

    # download_parallel 内のサブシェルから呼び出されたかを示すフラグ
    local suppress_message="false"
    if [ "$IN_PARALLEL_DOWNLOAD" = "true" ]; then
        suppress_message="true"
        debug_log "DEBUG" "download: Running inside parallel task, suppressing individual success message for $file_name."
    fi

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

    # バージョン管理
    local remote_version_info remote_version auth_method local_version
    remote_version_info=$(get_commit_version "$file_name" "$force_mode")
    if [ $? -ne 0 ] || [ -z "$remote_version_info" ]; then
        debug_log "DEBUG" "download: Failed to get remote version for $file_name"
        return 1 # 失敗時は 1 を返す
    fi
    remote_version=$(echo "$remote_version_info" | cut -d' ' -f1)
    auth_method=$(echo "$remote_version_info" | cut -d' ' -f2)

    # ローカルバージョン
    local script_file="${CACHE_DIR}/script.ch"
    if [ -f "$script_file" ]; then
        local_version=$(grep "^${file_name}=" "$script_file" | cut -d'=' -f2)
    fi
    [ -z "$local_version" ] && local_version=""

    local file_path="${BASE_DIR}/${file_name}"

    # 強制DL判定
    if [ "$force_mode" = "true" ]; then
        debug_log "DEBUG" "download: force mode enabled for $file_name"
    fi

    # バージョン一致判定（force未指定時のみスキップ）
    if [ "$force_mode" != "true" ] && [ "$remote_version" = "$local_version" ] && [ -f "$file_path" ]; then
        debug_log "DEBUG" "download: Local version up-to-date for $file_name ($local_version); skipping download."
        # chmod要求ありなら実行
        if [ "$chmod_mode" = "true" ]; then
            chmod +x "$file_path" 2>/dev/null || debug_log "DEBUG" "download: chmod +x failed for existing file $file_path"
        fi
        
        # ★★★ 変更点: ファイルが最新でもload_modeが有効ならsourceする ★★★
        if [ "$load_mode" = "true" ] && [ "$IN_PARALLEL_DOWNLOAD" != "true" ]; then
            if [ -f "$file_path" ]; then
                debug_log "DEBUG" "download: Sourcing existing file due to load option: $file_path"
                . "$file_path"
                local source_status=$?
                if [ $source_status -ne 0 ]; then
                    debug_log "DEBUG" "download: Sourcing existing file failed with status $source_status: $file_path"
                    # sourceに失敗しても download 自体は成功しているので成功扱いとする
                fi
            fi
        fi
        # ★★★ 変更点ここまで ★★★
        
        return 0 # 成功時は 0 を返す
    fi

    # DL処理
    local api_status
    # APIレートチェックは並列実行中は行わない（download_parallel開始時に行う想定）
    if [ "$suppress_message" = "false" ]; then
        api_status=$(check_api_rate_limit)
        debug_log "DEBUG" "download: API status: $api_status"
    else
        api_status="(Checked)" # 並列中はチェック済みとして表示
    fi

    # DL実行
    if ! download_fetch_file "$file_name" "$remote_version" "$chmod_mode"; then
        debug_log "DEBUG" "download: download_fetch_file failed for $file_name"
        return 1 # 失敗時は 1 を返す
    fi

    # バージョンキャッシュ保存
    if [ -n "$remote_version" ]; then
        # save_version_to_cache が失敗しても download 自体の成否には影響させない
        if ! save_version_to_cache "$file_name" "$remote_version" "${CACHE_DIR}/script.ch" "$auth_method"; then
            debug_log "DEBUG" "download: save_version_to_cache failed for $file_name, but download itself succeeded."
        fi
    fi

    # chmod (download_fetch_file 内でも実行されるが、念のためここでも)
    if [ "$chmod_mode" = "true" ]; then
        chmod +x "$file_path" 2>/dev/null || debug_log "DEBUG" "download: chmod +x failed after download for $file_path"
    fi

    # サイレント/隠しモードでなく、かつ並列実行中でない場合のみ、DL成功メッセージ表示
    if [ "$suppress_message" = "false" ] && [ "$hidden_mode" = "false" ] && [ "$quiet_mode" = "false" ]; then
        printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_SUCCESS" "f=$file_name" "v=$remote_version" "api=$api_status")"
    fi

    # <<< Add: Source the file if load_mode is true after successful download
    if [ "$load_mode" = "true" ] && [ "$IN_PARALLEL_DOWNLOAD" != "true" ]; then
        if [ -f "$file_path" ]; then
            debug_log "DEBUG" "download: Sourcing downloaded file due to load option: $file_path"
            . "$file_path"
            local source_status=$?
            if [ $source_status -ne 0 ]; then
                debug_log "DEBUG" "download: Sourcing downloaded file failed with status $source_status: $file_path"
                # sourceに失敗しても download 自体は成功しているので成功扱いとする
            fi
        fi
    fi

    return 0 # 成功時は 0 を返す
}

download_parallel() {
    # 時間計測の開始
    local start_time=$(date +%s)
    local end_time=""
    local elapsed_seconds=0

    local total_lines
    local lines_per_task
    local task_count=0
    local max_parallel
    local pids=""
    local overall_status=0
    local tmp_dir="${DL_DIR}"
    local all_tasks_file="${tmp_dir}/dl_all_tasks.tmp"
    local task_file_prefix="${tmp_dir}/dl_task_"
    local load_targets_file="${tmp_dir}/load_targets.tmp"
    local pid job_index=0 wait_pid proc_status task_file
    local success_message failure_message spinner_message
    local script_path="$0"
    local task_base_name
    local stdout_log stderr_log log_file_prefix="${LOG_DIR}/download_parallel_task_"
    local fail_flag_file="${tmp_dir}/dl_failed_flag"
    local first_failed_task_name=""
    local first_error_message=""
    local error_info_file_prefix="${tmp_dir}/error_info_"
    #exported_varsはIN_PARALLEL_DOWNLOADを削除
    local exported_vars="BASE_DIR CACHE_DIR DL_DIR LOG_DIR DOWNLOAD_METHOD SKIP_CACHE DEBUG_MODE DEFAULT_LANGUAGE BASE_URL GITHUB_TOKEN_FILE COMMIT_CACHE_DIR COMMIT_CACHE_TTL FORCE"

    # --- 準備 ---
    max_parallel="${MAX_PARALLEL_TASKS:-1}"
    printf "%s\n" "$(color white "$(get_message "MSG_MAX_PARALLEL_TASKS" "m=$MAX_PARALLEL_TASKS")")"

    debug_log "DEBUG" "Effective max parallel download tasks: $max_parallel"

    if ! mkdir -p "$tmp_dir"; then 
        if [ ! -d "$tmp_dir" ]; then 
            debug_log "DEBUG" "Failed to create temporary directory for task definitions: $tmp_dir" >&2
            stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED')" "failure"
            end_time=$(date +%s)
            elapsed_seconds=$((end_time - start_time))
            printf "Download failed (directory creation) in %s seconds.\n" "$elapsed_seconds"
            return 1
        fi
    fi
    if ! mkdir -p "$LOG_DIR"; then if [ ! -d "$LOG_DIR" ]; then debug_log "DEBUG" "Failed to create log directory: $LOG_DIR" >&2; fi; fi
    rm -f "$fail_flag_file" "$load_targets_file" "${error_info_file_prefix}"*.txt 2>/dev/null

    start_spinner "$(color blue "$(get_message 'DOWNLOAD_PARALLEL_START')")"

    if [ ! -f "$script_path" ]; then 
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED')" "failure"
        debug_log "DEBUG" "Script path '$script_path' is not found"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (script not found) in %s seconds.\n" "$elapsed_seconds"
        return 1
    fi

    # download_files()の各行を抜き出す
    if ! awk '
        BEGIN { in_func=0; }
        /^download_files\(\) *\{/ { in_func=1; next }
        /^}/ { if(in_func){in_func=0} }
        in_func && !/^[ \t]*$/ && !/^[ \t]*#/ { print }
    ' "$script_path" > "$all_tasks_file"; then
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED' "param1=Failed to extract commands")" "failure"
        debug_log "DEBUG" "Failed to extract download_files() commands"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (command extraction) in %s seconds.\n" "$elapsed_seconds"
        return 1
    fi
    if ! [ -s "$all_tasks_file" ]; then
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_SUCCESS')" "success"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download completed (no tasks) in %s seconds.\n" "$elapsed_seconds"
        return 0
    fi

    total_lines=$(wc -l < "$all_tasks_file")
    if [ "$total_lines" -eq 0 ]; then
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_SUCCESS')" "success"
        rm -f "$all_tasks_file"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download completed (empty tasks) in %s seconds.\n" "$elapsed_seconds"
        return 0
    fi

    lines_per_task=$(( (total_lines + max_parallel - 1) / max_parallel )); [ "$lines_per_task" -eq 0 ] && lines_per_task=1
    rm -f "${task_file_prefix}"*.tmp 2>/dev/null

    # 1. タスク分割ファイルの生成 (downloadコマンドにはquiet引数を必ず付与)
    line_index=0
    while IFS= read -r task_line || [ -n "$task_line" ]; do
        local orig_line="$task_line"
        # downloadコマンドかつquiet引数がなければquietを付与
        case "$task_line" in
            download*)
                # すでにquietが含まれている場合はそのまま
                if ! echo "$task_line" | grep -qw "quiet"; then
                    task_line="$task_line quiet"
                fi
                ;;
        esac
        task_file="${task_file_prefix}$(printf "%03d" $((line_index % max_parallel))).tmp"
        echo "$task_line" >> "$task_file"
        line_index=$((line_index + 1))
    done < "$all_tasks_file"

    # 2. ロード対象ファイル生成
    > "$load_targets_file"
    while IFS= read -r task_line || [ -n "$task_line" ]; do
        trimmed_line=${task_line#"${task_line%%[![:space:]]*}"}
        case "$trimmed_line" in
            download*)
                case "$trimmed_line" in
                    *'"load"')
                        set -- $trimmed_line
                        if [ "$#" -ge 2 ]; then
                           load_fname=$2
                           load_fname=${load_fname#\"}
                           load_fname=${load_fname%\"}
                           if [ -n "$load_fname" ]; then
                               echo "$load_fname" >> "$load_targets_file"
                           fi
                        fi
                        ;;
                esac
                ;;
        esac
    done < "$all_tasks_file"

    rm -f "$all_tasks_file"
    task_count=$(find "$tmp_dir" -name "$(basename "$task_file_prefix")*.tmp" -type f 2>/dev/null | wc -l)
    if [ "$task_count" -eq 0 ]; then
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED' "param1=Failed to create task files")" "failure"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (task creation) in %s seconds.\n" "$elapsed_seconds"
        return 1
    fi

    # --- 並列実行 ---
    pids=""
    job_index=0
    export $exported_vars

    _run_sub_task_internal() {
        local _task_file_path="$1"
        local _stderr_log="$2"
        local _error_info_file="$3"
        local _task_base="$4"

        local sub_task_failed=0
        local failed_command=""
        local line_num=0

        while IFS= read -r command_line || [ -n "$command_line" ]; do
            line_num=$((line_num + 1))
            case "$command_line" in "" | \#*) continue ;; esac

            local eval_command=$(echo "$command_line" | sed 's/"load"//g')

            eval "$eval_command"
            local cmd_status=$?

            if [ "$cmd_status" -ne 0 ]; then
                debug_log "DEBUG" "[$$][$_task_base] Command failed with status $cmd_status: $command_line" >&2
                sub_task_failed=1
                failed_command="$command_line"
                break
            fi
        done < "$_task_file_path"

        if [ "$sub_task_failed" -eq 1 ]; then
            local error_detail="Unknown error"
            if [ -f "$_stderr_log" ] && [ -s "$_stderr_log" ]; then
                error_detail=$(grep -v '^[[:space:]]*$' "$_stderr_log" | head -n 1)
                if [ -z "$error_detail" ]; then error_detail=$(head -n 1 "$_stderr_log"); fi
            else
                error_detail="No error output captured"
            fi
            [ -z "$error_detail" ] && error_detail="See $_stderr_log"
            { echo "$_task_base"; echo "$error_detail"; } > "$_error_info_file" 2>/dev/null
            exit 1
        else
            exit 0
        fi
    }

    find "$tmp_dir" -name "$(basename "$task_file_prefix")*.tmp" -type f | sort | while IFS= read -r task_file; do
        task_base_name=$(basename "$task_file" .tmp)
        stdout_log="${log_file_prefix}${task_base_name}.stdout.log"
        stderr_log="${log_file_prefix}${task_base_name}.stderr.log"
        sub_error_info_file="${error_info_file_prefix}${task_base_name}.txt"
        _run_sub_task_internal "$task_file" "$stderr_log" "$sub_error_info_file" "$task_base_name" > "$stdout_log" 2> "$stderr_log" &
        pid=$!
        pids="$pids $pid"
        job_index=$((job_index + 1))

        if [ "$job_index" -ge "$max_parallel" ]; then
             first_pid_in_batch=$(echo "$pids" | awk '{print $1}')
             if [ -n "$first_pid_in_batch" ]; then
                 if wait "$first_pid_in_batch"; then
                     :
                 else
                     proc_status=$?
                     debug_log "DEBUG" "Background task (PID $first_pid_in_batch) failed with status $proc_status" >&2
                     touch "$fail_flag_file"
                 fi
                 pids=$(echo "$pids" | sed "s/^$first_pid_in_batch //; s/ $first_pid_in_batch / /; s/ $first_pid_in_batch$//")
                 job_index=$((job_index - 1))
             else
                 sleep 1
             fi
        fi
    done

    for pid in $pids; do
        case "$pid" in *[!0-9]* | "" | 0) continue ;; esac
        if wait "$pid"; then
            :
        else
            proc_status=$?
            debug_log "DEBUG" "Background task (PID $pid) failed with status $proc_status" >&2
            touch "$fail_flag_file"
        fi
    done

    if [ -f "$fail_flag_file" ]; then
        overall_status=1
        first_error_file=$(find "$tmp_dir" -name "${error_info_file_prefix}*.txt" -type f -print 2>/dev/null | sort | head -n 1)
        if [ -n "$first_error_file" ] && [ -f "$first_error_file" ]; then
             first_failed_task_name=$(head -n 1 "$first_error_file" 2>/dev/null)
             first_error_message=$(sed -n '2p' "$first_error_file" 2>/dev/null)
             if command -v printf >/dev/null; then first_error_message=$(printf '%s' "$first_error_message" | tr -cd '[:print:]\t' | head -c 100); else first_error_message=$(echo "$first_error_message" | tr -cd '[:print:]\t' | head -c 100); fi
        fi
    fi

    # DL完了後、ロード対象を親シェルでsource
    if [ $overall_status -eq 0 ] && [ -f "$load_targets_file" ]; then
        sleep 2
        while IFS= read -r load_file; do
            [ -z "$load_file" ] && continue
            local full_load_path="${BASE_DIR}/$load_file"
            . "$full_load_path"
            local source_status=$?
            if [ $source_status -ne 0 ]; then
                debug_log "DEBUG" "Source '$full_load_path' failed, retrying..."
                sleep 1
                . "$full_load_path"
                source_status=$?
            fi
            if [ $source_status -ne 0 ]; then
                debug_log "DEBUG" "Failed to source '$full_load_path'" >&2
                overall_status=1
                if ! [ -f "$fail_flag_file" ]; then
                    first_failed_task_name="source"
                    first_error_message="Failed to source $load_file"
                fi
                break
            fi
        done < "$load_targets_file"
    elif [ $overall_status -eq 0 ]; then
        :
    fi

    if [ $overall_status -eq 0 ]; then
        success_message="$(get_message 'DOWNLOAD_PARALLEL_SUCCESS')"
        stop_spinner "$success_message" "success"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download completed successfully in %s seconds.\n" "$elapsed_seconds"
        return 0
    else
        [ -z "$first_failed_task_name" ] && first_failed_task_name="Unknown task"
        [ -z "$first_error_message" ] && first_error_message="Check logs in $LOG_DIR"
        failure_message="$(get_message 'DOWNLOAD_PARALLEL_FAILED' "f=$first_failed_task_name" "e=$first_error_message")"
        stop_spinner "$failure_message" "failure"
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (task: %s) in %s seconds.\n" "$first_failed_task_name" "$elapsed_seconds"
        return 1
    fi
}

OK_download_parallel() {
    # 時間計測の開始
    local start_time=$(date +%s)
    local end_time=""
    local elapsed_seconds=0

    local total_lines
    local lines_per_task # Although calculated, not used for assignment anymore
    local task_count=0
    local max_parallel
    local pids=""
    local overall_status=0 # 0: success, 1: failure
    local tmp_dir="${DL_DIR}"
    local all_tasks_file="${tmp_dir}/dl_all_tasks.tmp"
    local task_file_prefix="${tmp_dir}/dl_task_"
    local load_targets_file="${tmp_dir}/load_targets.tmp" # ロード対象記録
    local pid job_index=0 wait_pid proc_status task_file
    local success_message failure_message spinner_message
    local script_path="$0" # Store the script path
    local task_base_name # For log file naming
    local stdout_log stderr_log log_file_prefix="${LOG_DIR}/download_parallel_task_"
    local fail_flag_file="${tmp_dir}/dl_failed_flag" # Keep original flag file
    # --- ADDED: Variables/prefix for capturing specific error details ---
    local first_failed_task_name=""
    local first_error_message=""
    local error_info_file_prefix="${tmp_dir}/error_info_" # Prefix for detail files
    # --- END ADDED ---
    local exported_vars="BASE_DIR CACHE_DIR DL_DIR LOG_DIR DOWNLOAD_METHOD SKIP_CACHE DEBUG_MODE DEFAULT_LANGUAGE BASE_URL GITHUB_TOKEN_FILE COMMIT_CACHE_DIR COMMIT_CACHE_TTL FORCE IN_PARALLEL_DOWNLOAD" # Added IN_PARALLEL_DOWNLOAD

    # --- 準備 ---
    max_parallel="${MAX_PARALLEL_TASKS:-1}"
    printf "%s\n" "$(color white "$(get_message "MSG_MAX_PARALLEL_TASKS" "m=$MAX_PARALLEL_TASKS")")"

    # [ "$CORE_COUNT" -ge 4 ] && max_parallel=5
    debug_log "DEBUG" "Effective max parallel download tasks: $max_parallel"

    if ! mkdir -p "$tmp_dir"; then 
        if [ ! -d "$tmp_dir" ]; then 
            debug_log "DEBUG" "Failed to create temporary directory for task definitions: $tmp_dir" >&2
            stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED')" "failure"
            
            # 時間計測
            end_time=$(date +%s)
            elapsed_seconds=$((end_time - start_time))
            printf "Download failed (directory creation) in %s seconds.\n" "$elapsed_seconds"
            
            # ★★★ 修正：早期リターン時にフラグをリセット ★★★
            IN_PARALLEL_DOWNLOAD="false"
            return 1
        fi
    fi
    if ! mkdir -p "$LOG_DIR"; then if [ ! -d "$LOG_DIR" ]; then debug_log "DEBUG" "Failed to create log directory: $LOG_DIR" >&2; fi; fi
    # --- MODIFIED: Also remove potential leftover error info files ---
    rm -f "$fail_flag_file" "$load_targets_file" "${error_info_file_prefix}"*.txt 2>/dev/null
    # --- END MODIFIED ---

    # --- スピナー ---
    # メッセージキーの引数を修正
    start_spinner "$(color blue "$(get_message 'DOWNLOAD_PARALLEL_START')")"

    # --- download_files()のコマンド抽出 ---
    if [ ! -f "$script_path" ]; then 
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED')" "failure"
        debug_log "DEBUG" "Script path '$script_path' is not found"
        
        # 時間計測
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (script not found) in %s seconds.\n" "$elapsed_seconds"
        
        # ★★★ 修正：早期リターン時にフラグをリセット ★★★
        IN_PARALLEL_DOWNLOAD="false"
        return 1
    fi
    # download_files()の各行を抜き出す (Keep original awk structure)
    if ! awk '
        BEGIN { in_func=0; }
        /^download_files\(\) *\{/ { in_func=1; next }
        /^}/ { if(in_func){in_func=0} }
        in_func && !/^[ \t]*$/ && !/^[ \t]*#/ { print }
    ' "$script_path" > "$all_tasks_file"; then
        # メッセージキーの引数を修正
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED' "param1=Failed to extract commands")" "failure"
        debug_log "DEBUG" "Failed to extract download_files() commands"
        
        # 時間計測
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (command extraction) in %s seconds.\n" "$elapsed_seconds"
        
        # ★★★ 修正：早期リターン時にフラグをリセット ★★★
        IN_PARALLEL_DOWNLOAD="false"
        return 1
    fi
    if ! [ -s "$all_tasks_file" ]; then
        # メッセージキーの引数を修正
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_SUCCESS')" "success"
        
        # 時間計測（空のタスクファイルなので成功と見なす）
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download completed (no tasks) in %s seconds.\n" "$elapsed_seconds"
        
        # ★★★ 修正：早期リターン時にフラグをリセット ★★★
        IN_PARALLEL_DOWNLOAD="false"
        return 0
    fi

    # --- コマンド分割＆ロード対象記録（剰余演算子使用） ---
    total_lines=$(wc -l < "$all_tasks_file")
    if [ "$total_lines" -eq 0 ]; then
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_SUCCESS')" "success"
        rm -f "$all_tasks_file"
        IN_PARALLEL_DOWNLOAD="false" # リセット
        
        # 時間計測（タスクがないので成功と見なす）
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download completed (empty tasks) in %s seconds.\n" "$elapsed_seconds"
        
        return 0 # Added cleanup
    fi

    lines_per_task=$(( (total_lines + max_parallel - 1) / max_parallel )); [ "$lines_per_task" -eq 0 ] && lines_per_task=1
    rm -f "${task_file_prefix}"*.tmp 2>/dev/null

    # 1. タスク分割ファイルの生成 (剰余演算子を使用)
    line_index=0
    while IFS= read -r task_line || [ -n "$task_line" ]; do
        # 行番号を並列数で割った余りを使ってファイル番号を決定
        task_file="${task_file_prefix}$(printf "%03d" $((line_index % max_parallel))).tmp"
        echo "$task_line" >> "$task_file"
        line_index=$((line_index + 1))
    done < "$all_tasks_file"

    # 2. ロード対象ファイル生成（インデント無視、POSIXシェル組み込みのみ）
    > "$load_targets_file"
    while IFS= read -r task_line || [ -n "$task_line" ]; do
        trimmed_line=${task_line#"${task_line%%[![:space:]]*}"}
        case "$trimmed_line" in
            download*)
                case "$trimmed_line" in
                    *'"load"')
                        set -- $trimmed_line
                        if [ "$#" -ge 2 ]; then # Ensure field exists
                           load_fname=$2
                           load_fname=${load_fname#\"}
                           load_fname=${load_fname%\"}
                           if [ -n "$load_fname" ]; then # Ensure not empty
                               echo "$load_fname" >> "$load_targets_file"
                           fi
                        fi
                        ;;
                esac
                ;;
        esac
    done < "$all_tasks_file"

    rm -f "$all_tasks_file"
    task_count=$(find "$tmp_dir" -name "$(basename "$task_file_prefix")*.tmp" -type f 2>/dev/null | wc -l) # Ensure only files counted
    if [ "$task_count" -eq 0 ]; then
        # メッセージキーの引数を修正
        stop_spinner "$(get_message 'DOWNLOAD_PARALLEL_FAILED' "param1=Failed to create task files")" "failure"
        # ★★★ 変更点: 早期リターン前にリセット ★★★
        IN_PARALLEL_DOWNLOAD="false" # リセット
        
        # 時間計測
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (task creation) in %s seconds.\n" "$elapsed_seconds"
        
        return 1
        # ★★★ 変更点ここまで ★★★
    fi

    # --- 並列実行 ---
    pids=""
    job_index=0
    export IN_PARALLEL_DOWNLOAD="true"
    export $exported_vars # 他の変数もエクスポート

    # --- ADDED: Define subshell task as a temporary function for ash compatibility ---
    # This function encapsulates the logic previously run inside the subshell (...)
    _run_sub_task_internal() {
        # Arguments passed to the function
        local _task_file_path="$1"
        local _stderr_log="$2"
        local _error_info_file="$3"
        local _task_base="$4"

        local sub_task_failed=0 # サブタスク失敗フラグ
        local failed_command="" # Store the failed command line
        local line_num=0 # Line number counter for debugging

        while IFS= read -r command_line || [ -n "$command_line" ]; do
            line_num=$((line_num + 1)) # Increment line number
            case "$command_line" in "" | \#*) continue ;; esac

            local eval_command=$(echo "$command_line" | sed 's/"load"//g')

            eval "$eval_command"
            local cmd_status=$?

            if [ "$cmd_status" -ne 0 ]; then
                # Add line number to debug log
                debug_log "DEBUG" "[$$][$_task_base] Command failed with status $cmd_status: $command_line" >&2
                sub_task_failed=1
                failed_command="$command_line"
                break
            fi
        done < "$_task_file_path"

        # Error reporting logic (same as before, now inside the function)
        if [ "$sub_task_failed" -eq 1 ]; then
            local error_detail="Unknown error"
            if [ -f "$_stderr_log" ] && [ -s "$_stderr_log" ]; then
                error_detail=$(grep -v '^[[:space:]]*$' "$_stderr_log" | head -n 1)
                if [ -z "$error_detail" ]; then error_detail=$(head -n 1 "$_stderr_log"); fi
            else
                error_detail="No error output captured"
            fi
            [ -z "$error_detail" ] && error_detail="See $_stderr_log"
            { echo "$_task_base"; echo "$error_detail"; } > "$_error_info_file" 2>/dev/null
            exit 1
        else
            exit 0
        fi
    }
    # --- END ADDED ---

    find "$tmp_dir" -name "$(basename "$task_file_prefix")*.tmp" -type f | sort | while IFS= read -r task_file; do # Ensure only files processed
        task_base_name=$(basename "$task_file" .tmp)
        stdout_log="${log_file_prefix}${task_base_name}.stdout.log"
        stderr_log="${log_file_prefix}${task_base_name}.stderr.log"
        # --- ADDED: Define unique error info file path for the subshell ---
        sub_error_info_file="${error_info_file_prefix}${task_base_name}.txt"
        # --- END ADDED ---
        # --- MODIFIED: Call the temporary function in the background instead of using (...) ---
        # Ensure arguments are properly quoted for safety
        _run_sub_task_internal "$task_file" "$stderr_log" "$sub_error_info_file" "$task_base_name" > "$stdout_log" 2> "$stderr_log" &
        # --- END MODIFIED ---
        pid=$!
        pids="$pids $pid"
        job_index=$((job_index + 1))

        # Wait for a process to finish if max parallel is reached
        if [ "$job_index" -ge "$max_parallel" ]; then
             first_pid_in_batch=$(echo "$pids" | awk '{print $1}')
             if [ -n "$first_pid_in_batch" ]; then
                 if wait "$first_pid_in_batch"; then
                     : # 成功時は何もしない
                 else
                     proc_status=$?
                     debug_log "DEBUG" "Background task (PID $first_pid_in_batch) failed with status $proc_status" >&2
                     touch "$fail_flag_file"
                 fi
                 pids=$(echo "$pids" | sed "s/^$first_pid_in_batch //; s/ $first_pid_in_batch / /; s/ $first_pid_in_batch$//") # Keep original sed
                 job_index=$((job_index - 1))
             else
                 sleep 1 # Keep original sleep
             fi
        fi
    done # End of find loop

    # --- 残ジョブ待機 ---
    for pid in $pids; do
        case "$pid" in *[!0-9]* | "" | 0) continue ;; esac # Keep original check
        if wait "$pid"; then
            : # 成功時は何もしない
        else
            proc_status=$?
            debug_log "DEBUG" "Background task (PID $pid) failed with status $proc_status" >&2
            touch "$fail_flag_file"
        fi
    done # End of wait loop

    # --- 失敗判定 ---
    if [ -f "$fail_flag_file" ]; then
        overall_status=1 # Set overall status based on flag file existence
        # --- ADDED: Try to read specific error info if flag file exists ---
        first_error_file=$(find "$tmp_dir" -name "${error_info_file_prefix}*.txt" -type f -print 2>/dev/null | sort | head -n 1)
        if [ -n "$first_error_file" ] && [ -f "$first_error_file" ]; then
             first_failed_task_name=$(head -n 1 "$first_error_file" 2>/dev/null)
             first_error_message=$(sed -n '2p' "$first_error_file" 2>/dev/null)
             # Sanitize error message
             if command -v printf >/dev/null; then first_error_message=$(printf '%s' "$first_error_message" | tr -cd '[:print:]\t' | head -c 100); else first_error_message=$(echo "$first_error_message" | tr -cd '[:print:]\t' | head -c 100); fi
        fi
        # --- END ADDED ---
    fi

    # --- DL完了後、ロード対象を親シェルでsource ---
    # --- 変更点: ファイル確認を省略 ---
    if [ $overall_status -eq 0 ] && [ -f "$load_targets_file" ]; then
        # スリープを維持（全体に対して1回のみ）
        sleep 2
        
        while IFS= read -r load_file; do
            [ -z "$load_file" ] && continue
            local full_load_path="${BASE_DIR}/$load_file"
            
            # ファイル読み込み（ファイル確認なし）
            . "$full_load_path"
            local source_status=$?
            
            # sourceに失敗した場合のみリトライ（現状の仕様を維持）
            if [ $source_status -ne 0 ]; then
                debug_log "DEBUG" "Source '$full_load_path' failed, retrying..."
                sleep 1
                . "$full_load_path"
                source_status=$?
            fi
            
            if [ $source_status -ne 0 ]; then
                debug_log "DEBUG" "Failed to source '$full_load_path'" >&2
                overall_status=1
                # エラー情報を記録（download中のエラーがなければ）
                if ! [ -f "$fail_flag_file" ]; then
                    first_failed_task_name="source"
                    first_error_message="Failed to source $load_file"
                fi
                break
            fi
        done < "$load_targets_file"
    elif [ $overall_status -eq 0 ]; then
        # load_targets_file が存在しないのは正常な場合もある
        : # 何もしない
    fi

    # --- 結果表示 ---
    if [ $overall_status -eq 0 ]; then
        # Use original success message key
        success_message="$(get_message 'DOWNLOAD_PARALLEL_SUCCESS')"
        stop_spinner "$success_message" "success"

        IN_PARALLEL_DOWNLOAD="false"
        
        # 時間計測（成功時）
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download completed successfully in %s seconds.\n" "$elapsed_seconds"
        
        return 0
    else
        # --- MODIFIED: Format failure message using captured info or fallback ---
        # Fallback if specific info wasn't captured
        [ -z "$first_failed_task_name" ] && first_failed_task_name="Unknown task"
        [ -z "$first_error_message" ] && first_error_message="Check logs in $LOG_DIR"
        # Use unified format f=... e=... for the message key
        failure_message="$(get_message 'DOWNLOAD_PARALLEL_FAILED' "f=$first_failed_task_name" "e=$first_error_message")"
        stop_spinner "$failure_message" "failure"

        IN_PARALLEL_DOWNLOAD="false"
        
        # 時間計測（失敗時）
        end_time=$(date +%s)
        elapsed_seconds=$((end_time - start_time))
        printf "Download failed (task: %s) in %s seconds.\n" "$first_failed_task_name" "$elapsed_seconds"
        
        return 1
        # --- END MODIFIED ---
    fi
}

download_check_version() {
    local file_name="$1"
    local script_file="${CACHE_DIR}/script.ch"
    local dummy_version="No version control"

    # バージョン情報の取得
    local remote_version_info=$(get_commit_version "$file_name")
    local remote_version=$(printf "%s" "$remote_version_info" | cut -d' ' -f1)
    local auth_method=$(printf "%s" "$remote_version_info" | cut -d' ' -f2) # get_commit_version が返した認証方法を取得
    local local_version=""

    # ローカルバージョンの取得
    if [ -f "$script_file" ]; then
        local_version=$(grep "^${file_name}=" "$script_file" | cut -d'=' -f2)
    fi
    [ -z "$local_version" ] && local_version="$dummy_version"

    local clean_remote_version=$(clean_version_string "$remote_version")
    local clean_local_version=$(clean_version_string "$local_version")

    # --- APIレート制限情報の取得 (direct モード時はスキップ) ---
    local api_status=""
    if [ "$DOWNLOAD_METHOD" = "direct" ]; then
        # direct モードの場合は API チェックをスキップし、固定値を設定
        # auth_method が 'direct' であることも確認 (get_commit_version が期待通り動作しているか)
        if [ "$auth_method" = "direct" ]; then
             api_status="API: N/A (Direct)"
             debug_log "DEBUG" "Direct download mode: Skipping API rate limit check for $file_name"
        else
             # direct モードなのに auth_method が direct でない場合は警告
             api_status="API: ??? (Inconsistent)"
             debug_log "DEBUG" "Inconsistent state: DOWNLOAD_METHOD=direct but auth_method=$auth_method for $file_name"
        fi
    else
        # api モードの場合は従来通りチェック
        api_status=$(check_api_rate_limit)
    fi
    # --- APIレート制限情報の取得ここまで ---

    # バージョン比較とダウンロード判断 (変更なし)
    local update_required=false

    if [ "$local_version" = "$dummy_version" ]; then
        debug_log "DEBUG" "First download: $file_name"
        update_required=true
    elif [ "$clean_remote_version" = "$clean_local_version" ]; then
        debug_log "DEBUG" "Exact match: No update needed for $file_name"
        update_required=false
    else
        debug_log "DEBUG" "Starting version comparison: $file_name"
        version_is_newer "$clean_remote_version" "$clean_local_version"
        if [ $? -eq 0 ]; then
            debug_log "DEBUG" "New version detected: Update required for $file_name"
            update_required=true
        else
            debug_log "DEBUG" "Existing version: No update needed for $file_name"
            update_required=false
        fi
    fi

    debug_log "DEBUG" "Remote version: $file_name - $clean_remote_version"
    debug_log "DEBUG" "Local version: $file_name - $clean_local_version"
    # ログに auth_method を追加して、get_commit_version の動作を確認しやすくする
    debug_log "DEBUG" "API status: $api_status (Auth method from get_commit_version: $auth_method)"

    # 結果を返す
    echo "${update_required}|${clean_remote_version}|${clean_local_version}|${api_status}"
    return 0
}

download_fetch_file() {
    local file_name="$1"
    local clean_remote_version="$2"
    local chmod_mode="$3"
    local install_path="${BASE_DIR}/$file_name"
    local script_file="${CACHE_DIR}/script.ch"
    
    debug_log "DEBUG" "download_fetch_file called for ${file_name}"
    
    # ダウンロードURLの設定
    local remote_url="${BASE_URL}/$file_name"
    
    # キャッシュバスティングの適用
    if [ "$FORCE" = "true" ] || echo "$clean_remote_version" | grep -q "direct"; then
        remote_url="${remote_url}${CACHE_BUST}"
    fi
    
    debug_log "DEBUG" "Downloading from ${remote_url} to ${install_path}"
    
    # IPバージョン判定（ip_type.ch利用、unknownや空ならエラー終了）
    local ip_type_file="${CACHE_DIR}/ip_type.ch"
    local wget_options=""
    if [ ! -f "$ip_type_file" ]; then
        echo "Network is not available. (ip_type.ch not found)" >&2
        return 1
    fi
    wget_options=$(cat "$ip_type_file" 2>/dev/null)
    if [ -z "$wget_options" ] || [ "$wget_options" = "unknown" ]; then
        echo "Network is not available. (ip_type.ch is unknown or empty)" >&2
        return 1
    fi
    
    # BusyBox wget向けに最適化した明示的なコマンド構文
    wget --no-check-certificate $wget_options -T $API_TIMEOUT -q -O "$install_path" "$remote_url" 2>/dev/null
    local wget_exit_code=$?
    
    if [ "$wget_exit_code" -ne 0 ]; then
        debug_log "DEBUG" "Download failed: $file_name"
        return 1
    fi
    
    # ファイル検証
    if [ ! -f "$install_path" ]; then
        debug_log "DEBUG" "Downloaded file not found: $file_name"
        return 1
    fi
    
    if [ ! -s "$install_path" ]; then
        debug_log "DEBUG" "Downloaded file is empty: $file_name"
        return 1
    fi
    
    debug_log "DEBUG" "File successfully downloaded to ${install_path}"
    
    # 権限設定
    if [ "$chmod_mode" = "true" ]; then
        chmod +x "$install_path"
        debug_log "DEBUG" "chmod +x applied to $file_name"
    fi
    
    # バージョン情報をキャッシュに保存
    save_version_to_cache "$file_name" "$clean_remote_version" "$script_file"
    
    return 0
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
    printf "%s\n" "$(color magenta "               ## #")"
    printf "%s\n" "$(color blue    "     ####      ###       ####      #####")"
    printf "%s\n" "$(color green   "        ##      ##      ##  ##    ##")"
    printf "%s\n" "$(color yellow  "     #####      ##      ##  ##     #####")"
    printf "%s\n" "$(color orange  "    ##  ##      ##      ##  ##         ##")"
    printf "%s\n" "$(color red     "     #####     ####      ####     ######")"
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
    FORCE="false"
    RESET="false"
    HELP="false"
    SKIP_DEVICE_DETECTION="false"
    SKIP_IP_DETECTION="false"
    SKIP_ALL_DETECTION="false"
    SKIP_CACHE="false"

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
            -f|--f|-force|--force)
                FORCE="true"
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
            -t|--t|-token|--token)
                setup_github_token
                exit 0
                ;;
            -ta|--ta|-test_api|--test_api)
                MODE="test_api"
                ;;
            -sc|--sc|-skip-cache|--skip-cache)
                SKIP_CACHE_DETECTION="true"
                ;;
            -sd|--sd|-skip-dev|--skip-dev)
                SKIP_DEVICE_DETECTION="true"
                ;;
            -scd|--scd|-skip-cache-device|--skip-cache-device)
                SKIP_CACHE_DEVICE_DETECTION="true"
                ;;
            -si|--si|-skip-ip|--skip-ip)
                SKIP_IP_DETECTION="true"
                ;;
            -sa|--sa|-skip-all|--skip-all)
                SKIP_ALL_DETECTION="true"
                ;;
            -nc|--nc|-no-cache|--no-cache)
                SKIP_CACHE="true"
                debug_log "DEBUG" "Cache disabled by command line option"
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

    # 環境変数設定
    export SELECTED_LANGUAGE DEBUG_MODE DEBUG_LEVEL MODE DRY_RUN LOGFILE FORCE RESET HELP SKIP_CACHE

    # デバッグ情報を出力
    debug_log "DEBUG" "$BIN_FILE: $SCRIPT_VERSION"
    debug_log "DEBUG" "check_option received args: $ORIGINAL_ARGS"
    debug_log "DEBUG" "check_option: MODE=$MODE, SKIP_CACHE=$SKIP_CACHE, SELECTED_LANGUAGE=$SELECTED_LANGUAGE"

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
            print_banner
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
            print_banner
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

# 初期化処理のメイン
main() {
    resolve_path "$0"

    # 必要なディレクトリを作成
    if ! make_directory; then
        debug_log "DEBUG" "Failed to create required directories"
        return 1
    fi

    check_network_connectivity

    check_option "$@"
}

# 🔴　メイン　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

# スクリプト実行
main "$@"
 
