#!/bin/sh
# ttyd.sh (自動インストール版)
# License: CC0

TTYD_SH_VERSION="2025.02.05-rc1"
echo "ttyd.sh Last update: $TTYD_SH_VERSION"

BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"
INPUT_LANG="$1"

#################################
# パッケージリスト関数
#################################
packages() {
    echo "ttyd luci-app-ttyd"
}

#################################
# 共通ファイルのダウンロードと読み込み
#################################
download_common() {
    # common.sh が無ければ download_file() で入手
    if [ ! -f "${BASE_DIR}/common.sh" ]; then
        # ダウンロード前の確認が不要なら第3引数は空
        download_file "common.sh" "${BASE_DIR}/common.sh"
    fi

    # 読み込み
    . "${BASE_DIR}/common.sh" || {
        echo "Failed to source common.sh"
        exit 1
    }
}

#################################
# インストール+設定
#################################
install_and_configure_ttyd() {
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
download_common

# $1 (INPUT_LANG) が指定されていれば SELECTED_LANGUAGE を上書き
[ -n "$INPUT_LANG" ] && SELECTED_LANGUAGE="$INPUT_LANG"

check_country
download_supported_versions
check_openwrt

# すぐにインストール + 設定を行う
install_and_configure_ttyd
