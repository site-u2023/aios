#!/bin/sh
# aios.sh (初期エントリースクリプト)
# License: CC0
AIOS_VERSION="2025.02.10-1"
echo "aios.sh Last update: $AIOS_VERSION"

DEBUG_MODE=false
INPUT_LANG=""

# オプション解析
while [ $# -gt 0 ]; do
    case "$1" in
        -d|--debug|-debug) DEBUG_MODE=true ;;
        -reset|--reset|-r) RESET_CACHE=true ;;
        -help|--help|-h) SHOW_HELP=true ;;
        *)
            if [ -z "$INPUT_LANG" ]; then
                INPUT_LANG="$1"  # 最初の非オプション引数を言語コードとして扱う
            fi
            ;;
    esac
    shift
done

export INPUT_LANG

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
# メイン処理
#################################
delete_aios() {
    rm -rf "${BASE_DIR}" /usr/bin/aios
    echo "Initialized aios"
}

delete_aios
mkdir -p "$BASE_DIR"
download_common
check_common "full"
packages
download_script aios
