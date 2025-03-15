#!/bin/sh

SCRIPT_VERSION="2025.03.16-00-00"

# 基本定数の設定 
BASE_WGET="${BASE_WGET:-wget --no-check-certificate -q -O}"
DEBUG_MODE="${DEBUG_MODE:-false}"
BIN_PATH=$(readlink -f "$0")
BIN_DIR="$(dirname "$BIN_PATH")"
BIN_FILE="$(basename "$BIN_PATH")"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

menu_exit() {
    printf "%s\n" "終了が確認されました。"
    sleep 1
    exit 0
}

remove_exit() {
    printf "%s\n" "スクリプトと関連ディレクトリを削除しています..."
    [ -f "$0" ] && rm -f "$0"
    [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
    exit 0
}

# メニュー表示用データ
menyu_selector() {
    printf "%s\n" "$(color red "$(get_message "MENU_INTERNET")")"
    printf "%s\n" "$(color blue "$(get_message "MENU_SYSTEM")")"
    printf "%s\n" "$(color green "$(get_message "MENU_PACKAGES")")"
    printf "%s\n" "$(color magenta "$(get_message "MENU_ADBLOCKER")")"
    printf "%s\n" "$(color cyan "$(get_message "MENU_ACCESSPOINT")")"
    printf "%s\n" "$(color yellow "$(get_message "MENU_OTHERS")")"
    printf "%s\n" "$(color white "$(get_message "MENU_EXIT")")"
    printf "%s\n" "$(color white_black "$(get_message "MENU_REMOVE")")"
}

# ダウンロード用データ
menu_download() {
    echo 'download "internet-config.sh" "chmod" "load"'
    echo 'download "system-config.sh" "chmod" "load"'
    echo 'download "package-install.sh" "chmod" "load"'
    echo 'download "adblocker-dns.sh" "chmod" "load"'
    echo 'download "accesspoint-setup.sh" "chmod" "load"'
    echo 'download "other-utilities.sh" "chmod" "load"'
    echo 'menu_exit'
    echo 'remove_exit'
}

# メニュー表示と選択処理
selector() {
    choice=""
    
    # メニュー表示
    menyu_selector
    
    # 選択プロンプト
    printf "番号を選択してください (1-8): "
    
    # ユーザー入力を読み取り
    read -r choice
    echo "DEBUG: User input: $choice" >&2
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        printf "無効な入力です。もう一度入力してください。\n"
        sleep 2
        return 0
    fi
            
    tmp_file="${CACHE_DIR}/menu_commands.tmp"
    
    # メニューコマンドを取得
    menu_download > "$tmp_file"
    
    # 選択した行を抽出して表示
    selected_line=$(sed -n "${choice}p" "$tmp_file")
    echo "DEBUG: Extracted line: $selected_line"
    
    # コマンド行を実行
    eval "$selected_line"
    
    # クリーンアップ
    rm -f "$tmp_file"
}

# メイン関数
main() {
    while true; do
        selector
    done
}

# スクリプト実行
main "$@"
