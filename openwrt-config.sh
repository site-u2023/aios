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
printf "%s\n" "$(color red "$(get_message "MENU_INTERNET")")"
printf "%s\n" "$(color blue "$(get_message "MENU_SYSTEM")")"
printf "%s\n" "$(color green "$(get_message "MENU_PACKAGES")")"
printf "%s\n" "$(color magenta "$(get_message "MENU_ADBLOCKER")")"
printf "%s\n" "$(color cyan "$(get_message "MENU_ACCESSPOINT")")"
printf "%s\n" "$(color yellow "$(get_message "MENU_HOMEASSISTANT")")"
printf "%s\n" "$(color white "$(get_message "MENU_OTHERS")")"
printf "%s\n" "$(color white_black "$(get_message "MENU_EXIT")")"
)

# ダウンロード用データ
menu_download() (
download "internet-setup.sh" "chmod" "load"
download "system-setup.sh" "chmod" "load"
download "package-install.sh" "chmod" "load"
download "adblocker-dns.sh" "chmod" "load"
download "accesspoint-setup.sh" "chmod" "load"
download "homeassistant-install.sh" "chmod" "load"
download "other-utilities.sh" "chmod" "load"
"exit" "" ""
)

# メニュー表示用基本関数
print_menu() {
    printf -- '%s %s %s\n' "$1" "$2" "$3"
}

# メニューセレクター関数（メニュー表示と選択処理）
selector() {
    local menu_title="$1"
    local selector_data=""
    local download_data=""
    local menu_count=0
    
    debug_log "DEBUG" "Loading menu display data: $menyu_selector"
    menyu_selector
    
    debug_log "DEBUG" "Loading menu download data $menu_download"
    menu_download
    
    # メニュー項目数をカウント
    menu_count=$(echo "$selector_data" | wc -l)
    debug_log "DEBUG" "Menu contains $menu_count items"
    
    # clear
    printf "%s\n" "$(get_message "CONFIG_HEADER" "$SCRIPT_NAME" "$SCRIPT_VERSION")"
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    [ -n "$menu_title" ] && printf "%s\n" "$(get_message "CONFIG_SECTION_TITLE" "$menu_title")"
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # メニュー項目表示（多言語対応版）
    echo "$selector_data" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            # 行の要素を抽出
            local num=$(echo "$line" | cut -d '"' -f 2)
            local color_name=$(echo "$line" | cut -d '"' -f 4)
            local title_id=$(echo "$line" | cut -d '"' -f 6)
            
            # メッセージDBからタイトルを取得
            local title=$(get_message "$title_id")
            
            printf " %s%s\n" "$(color "$color_name" "[$num]: ")" "$(color "$color_name" "$title")"
        fi
    done
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    printf "%s" "$(get_message "CONFIG_SELECT_PROMPT" "max=$menu_count")"
    read -r choice
    
    # 入力値チェック
    if ! echo "$choice" | grep -q '^[0-9]\+$'; then
        printf "%s\n" "$(get_message "CONFIG_ERROR_NOT_NUMBER")"
        sleep 2
        return 0
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        printf "%s\n" "$(get_message "CONFIG_ERROR_INVALID_NUMBER" "max=$menu_count")"
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
        if confirm "$(get_message "CONFIG_CONFIRM_DELETE")"; then
            debug_log "DEBUG" "User requested script deletion"
            rm -f "$0"
            printf "%s\n" "$(get_message "CONFIG_DELETE_CONFIRMED")"
        else
            printf "%s\n" "$(get_message "CONFIG_DELETE_CANCELED")"
        fi
        return 255
    fi
    
    # ダウンロードと実行
    printf "%s\n" "$(get_message "CONFIG_DOWNLOADING" "file=$script")"
    if download "$script" "$opt1" "$opt2"; then
        debug_log "DEBUG" "Successfully processed $script"
    else
        printf "%s\n" "$(get_message "CONFIG_DOWNLOAD_FAILED" "file=$script")"
        sleep 2
    fi
    
    return 0
}

# メイン関数
main() {
    
    # メインループ
    while true; do
        selector "$(get_message "MENU_TITLE")"
    done
}

# スクリプト実行
main "$@"
