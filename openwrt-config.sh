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

# メニューセレクター関数（メニュー表示と選択処理）
selector() {
    local menu_title="$1"
    local menu_count=0
    
    debug_log "DEBUG" "Loading menu selector data"
    
    # メニュー項目数をカウント
    menu_count=$(menyu_selector | wc -l)
    debug_log "DEBUG" "Menu contains $menu_count items"
    
    # clear
    printf "%s\n" "$(get_message "CONFIG_HEADER" "$SCRIPT_NAME" "$SCRIPT_VERSION")"
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    [ -n "$menu_title" ] && printf "%s\n" "$(get_message "CONFIG_SECTION_TITLE" "$menu_title")"
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # メニュー表示（関数の出力をそのまま表示）
    menyu_selector
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    printf "%s" "$(get_message "CONFIG_SELECT_PROMPT" "max=$menu_count") "
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
    execute_menu_action "$choice"
    
    return $?
}

# メニュー項目実行関数
execute_menu_action() {
    local choice="$1"
    local current_line=0
    local command=""
    
    debug_log "DEBUG" "Processing menu selection: $choice"
    
    # menu_download関数を実行し、選択された行のコマンドを取得
    menu_download | {
        while IFS= read -r line; do
            current_line=$((current_line + 1))
            
            if [ "$current_line" -eq "$choice" ]; then
                command="$line"
                debug_log "DEBUG" "Selected command: $command"
                
                # 終了オプションの処理
                if [ "$command" = "\"exit\" \"\" \"\"" ]; then
                    if confirm "$(get_message "CONFIG_CONFIRM_DELETE")"; then
                        debug_log "DEBUG" "User requested script deletion"
                        rm -f "$0"
                        printf "%s\n" "$(get_message "CONFIG_DELETE_CONFIRMED")"
                        exit 255
                    else
                        debug_log "DEBUG" "User cancelled script deletion"
                        printf "%s\n" "$(get_message "CONFIG_DELETE_CANCELED")"
                    fi
                else
                    # 通常のコマンド実行
                    debug_log "DEBUG" "Executing command: $command"
                    eval "$command"
                fi
                break
            fi
        done
    }
    
    return 0
}

# メイン関数
main() {
    debug_log "DEBUG" "Starting menu selector script"
    
    # メインループ
    while true; do
        selector "$(get_message "MENU_TITLE")"
    done
}

# スクリプト実行
main "$@"
