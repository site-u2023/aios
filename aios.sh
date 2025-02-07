#!/bin/sh
# aios.sh (初期エントリースクリプト)
# License: CC0
echo aios.sh Last Update 20250207-1

AIOS_VERSION="2025.02.06-rc1"
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

#################################
# 簡易バージョンチェック
#################################
check_openwrt_local() {
    local version_file="/etc/openwrt_release"
    local current_version

    if [ ! -f "$version_file" ]; then
        echo "Error: OpenWrt version file not found!"
        exit 1
    fi

    current_version=$(awk -F"'" '/DISTRIB_RELEASE/ {print $2}' "$version_file" | cut -d'-' -f1)
    
    case "$current_version" in
        19.07|21.02|22.03|23.05|24.10.0|SNAPSHOT)
            echo "OpenWrt version $current_version is supported."
            ;;
        *)
            echo "Error: OpenWrt version $current_version is not supported!"
            exit 1
            ;;
    esac
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
    . "${BASE_DIR}/common.sh" || {
        echo "Failed to source common.sh"
        exit 1
    }
}

#################################
# パッケージリスト関数
#################################
packages() {
    echo "ttyd luci-app-ttyd"
}
#################################
# インストール+設定
#################################
install_ttyd() {
    local pkg_list
    pkg_list="$(packages)"  # "ttyd luci-app-ttyd"

    # MSG_INSTALL_PROMPT_PKG 内の {pkg} → "ttyd luci-app-ttyd" に置換
    if confirm_action "MSG_INSTALL_PROMPT_PKG" "$pkg_list"; then
        echo -e "\033[1;34mInstalling packages: $pkg_list...\033[0m"
        install_packages $pkg_list

        echo -e "\033[1;34mApplying ttyd settings...\033[0m"
        uci batch <<EOF
set ttyd.@ttyd[0]=ttyd
set ttyd.@ttyd[0].interface='@lan'
set ttyd.@ttyd[0].command='/bin/login -f root'
set ttyd.@ttyd[0].ipv6='1'
add_list ttyd.@ttyd[0].client_option='theme={"background": "black"}'
add_list ttyd.@ttyd[0].client_option='titleFixed=ttyd'
EOF

        uci commit ttyd || {
            echo "Failed to commit ttyd settings."
            exit 1
        }

        /etc/init.d/ttyd enable || {
            echo "Failed to enable ttyd service."
            exit 1
        }

        /etc/init.d/ttyd restart || {
            echo "Failed to restart ttyd service."
            exit 1
        }

        echo -e "\033[1;32m$(get_message 'MSG_SETTINGS_APPLIED' "$SELECTED_LANGUAGE")\033[0m"
    else
        echo -e "\033[1;33mSkipping installation of: $pkg_list\033[0m"
    fi
}

#################################
# メイン処理
#################################
delete_aios
check_openwrt_local
make_directory
check_common full
install_ttyd
download_file aios
