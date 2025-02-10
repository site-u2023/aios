#!/bin/sh
# aios.sh (初期エントリースクリプト)
# License: CC0
AIOS_VERSION="2025.02.10-0"
echo "aios.sh Last update: $AIOS_VERSION"

# デフォルト設定
DEBUG_MODE=false
INPUT_LANG="en"  # デフォルト言語
BASE_WGET="wget --quiet -O"
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"

# コマンドラインオプション解析
while getopts "d" opt; do
    case "$opt" in
        d) DEBUG_MODE=true ;;
    esac
done
shift $((OPTIND - 1))

# `-d` の後の引数を言語コードとして認識
if [ -n "$1" ]; then
    INPUT_LANG="$1"
fi

export INPUT_LANG

#################################
# デバッグログ関数
#################################
debug_log() {
    if $DEBUG_MODE; then
        echo "DEBUG: $*" | tee -a "$BASE_DIR/debug.log"
    fi
}

debug_log "aios.sh received INPUT_LANG: '$INPUT_LANG' and DEBUG_MODE: '$DEBUG_MODE'"

#########################################################################
# delete_aios: 既存の aios 関連ファイルおよびディレクトリを削除して初期化する
#########################################################################
delete_aios() {
    rm -rf "${BASE_DIR}" /usr/bin/aios
    echo "Initialized aios"
}

#########################################################################
# make_directory: 必要なディレクトリ (BASE_DIR) を作成する
#########################################################################
make_directory() {
    mkdir -p "$BASE_DIR"
}

#########################################################################
# download_common: 共通ファイル (common.sh) のダウンロードと読み込み
#########################################################################
download_common() {
    if [ ! -f "${BASE_DIR}/common.sh" ]; then
        ${BASE_WGET} "${BASE_DIR}/common.sh" "${BASE_URL}/common.sh" || {
            echo "Failed to download common.sh"
            exit 1
        }
    fi

    # 読み込み
    source "${BASE_DIR}/common.sh" || {
        echo "Failed to source common.sh"
        exit 1
    }
}

#########################################################################
# packages: 必要なパッケージのインストール
#########################################################################
packages() {
    install_packages yn ttyd luci-app-ttyd uci
}

#########################################################################
# メイン処理
#########################################################################
delete_aios
make_directory
download_common
check_common "full" "$INPUT_LANG"
packages
download_script aios
