#!/bin/sh
# aios.sh (初期エントリースクリプト)
# License: CC0
AIOS_VERSION="2025.02.14-1"
echo -e "\033[7;40maios.sh Updated to version $AIOS_VERSION \033[0m"

INPUT_LANG="${1:-}"  # ✅ `$1` は言語情報のみ受け付ける

export INPUT_LANG  # 環境変数として渡す

# 定数設定
BASE_WGET="wget --quiet -O"
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"

#################################
# デバッグログ出力関数
#################################
debug_log() {
    $DEBUG_MODE && echo "DEBUG: $*" | tee -a "$BASE_DIR/debug.log"
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
    . "${BASE_DIR}/common.sh" || {
        echo "Failed to load common.sh"
        exit 1
    }
}

#################################
# メイン処理
#################################
delete_aios() {
    rm -rf "${BASE_DIR}" /usr/bin/aios
    echo "Initialized aios"
}

mkdir_aios() {
    mkdir -p "$BASE_DIR"
}

delete_aios
mkdir_aios
download_common
check_common "$INPUT_LANG"
