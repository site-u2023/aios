#!/bin/sh
# aios.sh (初期エントリースクリプト)
# License: CC0
AIOS_VERSION="2025.02.06-8"
echo "aios.sh Last update: $AIOS_VERSION"

BASE_WGET="wget -O" # テスト用
# BASE_WGET="wget --quiet -O"
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"
INPUT_LANG="$1"

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

    # 読み込み
    source "${BASE_DIR}/common.sh" || {
        echo "Failed to source common.sh"
        exit 1
    }
}

#################################
# インストール
#################################
packages() {
    # パッケージグループ (yn: 確認あり / なし: 確認不要)
    PACKAGE_LIST=(
        "yn ttyd"  # `yn` はインストール時に確認をとる
        "luci-app-ttyd uci"
    )

    for package_group in "${PACKAGE_LIST[@]}"; do
        install_packages $package_group
    done
}

#################################
# メイン処理
#################################
delete_aios
make_directory
download_common
check_common full
packages  # ← `aios.sh` で `packages()` を実行
download_script aios
