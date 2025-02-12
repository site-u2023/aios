#!/bin/sh
# aios.sh (初期エントリースクリプト)
# License: CC0
AIOS_VERSION="2025.02.12-2"
echo -e "\033[7;40maios.sh Updated to version $AIOS_VERSION \033[0m"

DEBUG_MODE=false
RESET_CACHE=false
SHOW_HELP=false
INPUT_LANG="${1:-}"  # `$1` をそのままセット（デフォルトなし）

# デバッグモード設定
[ "$2" = "-d" ] && DEBUG_MODE=true

# オプション解析
while [ $# -gt 0 ]; do
    case "$1" in
        -d|--debug|-debug) DEBUG_MODE=true ;;
        -reset|--reset|-r) RESET_CACHE=true ;;
        -help|--help|-h) SHOW_HELP=true ;;
    esac
    shift
done

export DEBUG_MODE INPUT_LANG  # 環境変数として渡す

# BASE_WGET="wget -O" # テスト用
BASE_WGET="wget --quiet -O"
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"

#################################
# デバッグログ出力関数
#################################
debug_log() {
    if $DEBUG_MODE; then
        echo "DEBUG: $*" | tee -a "$BASE_DIR/debug.log"
    fi
}

debug_log "aios.sh received INPUT_LANG: '$INPUT_LANG' and DEBUG_MODE: '$DEBUG_MODE'"

#################################
# 共通ファイルのダウンロードと読み込み
#################################
download_common() {
    if [ ! -f "${BASE_DIR}/common.sh" ]; then
        ${BASE_WGET} "${BASE_DIR}/common.sh" "${BASE_URL}/common.sh" || {
            echo "Failed to download common.sh"
            exit 1
        }
    fi
    source "${BASE_DIR}/common.sh" || {
        echo "Failed to source common.sh"
        exit 1
    }
}

#################################
# インストール
#################################
packages() {
    install_packages yn ttyd luci-app-ttyd uci
}

#################################
# delete_aios
#################################
delete_aios() {
    rm -rf "${BASE_DIR}" /usr/bin/aios
    echo "Initialized aios"
}

#################################
# mkdir_aios
#################################
mkdir_aios() {
    mkdir -p "$BASE_DIR"
}
#################################
# メイン処理
#################################
if [ "$SHOW_HELP" = true ]; then
    print_help
    exit 0
fi

if [ "$RESET_CACHE" = true ]; then
    reset_cache
fi

delete_aios
mkdir_aios
download_common
check_common "full" "$INPUT_LANG"
packages
download_script aios
