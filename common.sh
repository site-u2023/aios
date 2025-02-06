#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
COMMON_FUNCTIONS_SH_VERSION="2025.02.05-rc1"
echo "common-functions.sh Last update: $COMMON_FUNCTIONS_SH_VERSION"

# === 基本定数の設定 ===
BASE_WGET="wget --quiet -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
SUPPORTED_VERSIONS="${SUPPORTED_VERSIONS:-19.07 21.02 22.03 23.05 24.10.0 SNAPSHOT}"
SUPPORTED_LANGUAGES="${SUPPORTED_LANGUAGES:-en ja zh-cn zh-tw id ko de ru}"

#########################################################################
# color: ANSI エスケープシーケンスを使って色付きメッセージを出力する関数
# 引数1: 色の名前 (例: red, green, blue_white など)
# 引数2以降: 出力するメッセージ
#########################################################################

color() {
    local color_code
    color_code=$(color_code_map "$1")
    shift
    echo -e "${color_code}$*$(color_code_map "reset")"
}

#########################################################################
# color_code_map: カラー名から ANSI エスケープシーケンスを返す関数
# 引数: 色の名前
#########################################################################

color_code_map() {
    local color="$1"
    case "$color" in
        "red") echo "\033[1;31m" ;;
        "green") echo "\033[1;32m" ;;
        "yellow") echo "\033[1;33m" ;;
        "blue") echo "\033[1;34m" ;;
        "magenta") echo "\033[1;35m" ;;
        "cyan") echo "\033[1;36m" ;;
        "white") echo "\033[1;37m" ;;
        "red_underline") echo "\033[4;31m" ;;
        "green_underline") echo "\033[4;32m" ;;
        "yellow_underline") echo "\033[4;33m" ;;
        "blue_underline") echo "\033[4;34m" ;;
        "magenta_underline") echo "\033[4;35m" ;;
        "cyan_underline") echo "\033[4;36m" ;;
        "white_underline") echo "\033[4;37m" ;;
        "red_white") echo "\033[1;41m" ;;
        "green_white") echo "\033[1;42m" ;;
        "yellow_white") echo "\033[1;43m" ;;
        "blue_white") echo "\033[1;44m" ;;
        "magenta_white") echo "\033[1;45m" ;;
        "cyan_white") echo "\033[1;46m" ;;
        "white_black") echo "\033[7;40m" ;;
        "reset") echo "\033[0;39m" ;;
        *) echo "\033[0;39m" ;;  # デフォルトでリセット
    esac
}

#########################################################################
# handle_error: エラーおよび警告メッセージの処理
# 引数1: メッセージ
# 引数2: エラーレベル ('fatal' または 'warning')
#########################################################################
handle_error() {
    local message="$1"
    local level="${2:-fatal}"  # デフォルトは致命的エラー

    if [ "$level" = "warning" ]; then
        color yellow "$(get_message 'MSG_VERSION_MISMATCH_WARNING'): $message"
    else
        color red "$(get_message 'MSG_ERROR_OCCURRED'): $message"
        exit 1
    fi
}

#########################################################################
# エラーハンドリング強化
#########################################################################
load_common_functions() {
    if [ ! -f "${BASE_DIR}/common-functions.sh" ]; then
        ensure_file "common-functions.sh"
    fi

    if ! grep -q "COMMON_FUNCTIONS_SH_VERSION" "${BASE_DIR}/common-functions.sh"; then
        handle_error "Invalid common-functions.sh file structure."
    fi

    . "${BASE_DIR}/common-functions.sh" || handle_error "Failed to load common-functions.sh"
    check_version_compatibility
}

#########################################################################
# check_country: 言語のサポート確認とデフォルト言語の設定
#########################################################################
check_country() {
    if [ -f "${BASE_DIR}/language_cache" ]; then
        SELECTED_LANGUAGE=$(cat "${BASE_DIR}/language_cache")
    else
        echo -e "\033[1;32mSelect your language:\033[0m"

        # サポート言語リストを表示
        i=1
        for lang in $SUPPORTED_LANGUAGES; do
            echo "$i) $lang"
            i=$((i+1))
        done

        # 入力受付ループ
        while true; do
            read -p "Enter number or language (e.g., en, ja): " input

            # 数字入力の場合
            if echo "$input" | grep -qE
::contentReference[oaicite:0]{index=0}
 
