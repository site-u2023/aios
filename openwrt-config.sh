#!/bin/sh

# =========================================================
# 📌 設定スクリプト
# 🚀 最終更新: 2025-03-15 06:37
# 
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 互換性: OpenWrt >= 19.07
# =========================================================

SCRIPT_VERSION="2025.03.15-06:37"
SCRIPT_NAME=$(basename "$0" .sh)
DEBUG=1

# メニュー表示用データ
menyu_selector() (
"1" "red" "MENU_INTERNET" 
"2" "blue" "MENU_SYSTEM"
"3" "green" "MENU_PACKAGES"
"4" "magenta" "MENU_ADBLOCKER"
"5" "cyan" "MENU_ACCESSPOINT"
"6" "yellow" "MENU_HOMEASSISTANT"
"7" "white" "MENU_OTHERS"
"8" "white_black" "MENU_EXIT"
)

# ダウンロード用データ
menu_download() (
"1" "internet-setup.sh" "chmod" "load"
"2" "system-setup.sh" "chmod" "load"
"3" "package-install.sh" "chmod" "load"
"4" "adblocker-dns.sh" "chmod" "load"
"5" "accesspoint-setup.sh" "chmod" "load"
"6" "homeassistant-install.sh" "chmod" "load"
"7" "other-utilities.sh" "chmod" "load"
"8" "exit" "" ""
)

# メニューセレクター関数（メニュー表示と選択処理）
selector() {
    local menu_title="$1"
    local selector_data=""
    local download_data=""
    local menu_count=0
    
    debug_log "DEBUG" "Loading menu display data"
    selector_data=$(menyu_selector)
    
    debug_log "DEBUG" "Loading menu download data"
    download_data=$(menu_download)
    
    # メニュー項目数をカウント
    menu_count=$(echo "$selector_data" | wc -l)
    debug_log "INFO" "Menu contains $menu_count items"
    
    clear
    echo_message "CONFIG_HEADER" "$SCRIPT_NAME" "$SCRIPT_VERSION"
    echo_message "CONFIG_SEPARATOR"
    [ -n "$menu_title" ] && echo_message "CONFIG_SECTION_TITLE" "$menu_title"
    echo_message "CONFIG_SEPARATOR"
    
    # メニュー項目表示（多言語対応版）
    echo "$selector_data" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            # 行の要素を抽出
            local num=$(echo "$line" | cut -d '"' -f 2)
            local color_name=$(echo "$line" | cut -d '"' -f 4)
            local title_id=$(echo "$line" | cut -d '"' -f 6)
            
            # メッセージDBからタイトルを取得
            local title=$(echo_message "$title_id")
            
            printf " %s%s\n" "$(color "$color_name" "[$num]: ")" "$(color "$color_name" "$title")"
        fi
    done
    
    echo_message "CONFIG_SEPARATOR"
    printf "%s" "$(echo_message "CONFIG_SELECT_PROMPT" "$menu_count")"
    read -r choice
    
    # 入力値チェック
    if ! echo "$choice" | grep -q '^[0-9]\+$'; then
        echo_message "CONFIG_ERROR_NOT_NUMBER"
        sleep 2
        return 0
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        echo_message "CONFIG_ERROR_INVALID_NUMBER" "$menu_count"
        sleep 2
        return 0
    fi
    
    # 選択アクションの実行
    local line_data=$(echo "$download_data" | sed -n "${choice}p")
    local script=$(echo "$line_data" | cut -d '"' -f 2)
    local opt1=$(echo "$line_data" | cut -d '"' -f 4)
    local opt2=$(echo "$line_data" | cut -d '"' -f 6)
    
    # 終了オプションの処理
    if [ "$script" = "exit" ]; then
        if confirm "CONFIG_CONFIRM_DELETE"; then
            debug_log "INFO" "User requested script deletion"
            rm -f "$0"
            echo_message "CONFIG_DELETE_CONFIRMED"
        else
            echo_message "CONFIG_DELETE_CANCELED"
        fi
        return 255
    fi
    
    # ダウンロードと実行
    echo_message "CONFIG_DOWNLOADING" "$script"
    if download "$script" "$opt1" "$opt2"; then
        debug_log "INFO" "Successfully processed $script"
    else
        echo_message "CONFIG_DOWNLOAD_FAILED" "$script"
        sleep 2
    fi
    
    return 0
}

# メイン関数
main() {
    debug_log "INFO" "Starting OpenWrt Config script v$SCRIPT_VERSION"
    
    # メインループ
    while true; do
        selector "OpenWrt 設定メニュー"
    done
}

# スクリプト実行
main "$@"
