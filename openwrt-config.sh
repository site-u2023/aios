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

# デバッグメッセージを出力する関数
debug_log() {
    if [ "$DEBUG" = "1" ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# メニューセレクター関数（メニュー表示と選択処理）
selector() {
    local menu_title="$1"
    local choice=""
    
    # メニュー表示ヘッダー
    clear
    printf "%s\n" "$(get_message "CONFIG_HEADER" "$SCRIPT_NAME" "$SCRIPT_VERSION")"
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    [ -n "$menu_title" ] && printf "%s\n" "$(get_message "CONFIG_SECTION_TITLE" "$menu_title")"
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # メニュー項目数を計算（行数をカウント）
    local menu_count=$(menyu_selector | wc -l)
    debug_log "Menu contains $menu_count items"
    
    # メニュー表示（menyu_selector関数の出力をそのまま表示）
    menyu_selector
    
    # メニュー選択プロンプト
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    printf "%s" "$(get_message "CONFIG_SELECT_PROMPT" "max=$menu_count")"
    read -r choice
    
    # 入力値を正規化（全角→半角）
    choice=$(normalize_input "$choice")
    
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
    
    # 選択された項目に基づいて対応するコマンドを実行
    execute_menu_item "$choice"
    
    return 0
}

# 選択されたメニュー項目を実行する関数
execute_menu_item() {
    local choice="$1"
    local i=1
    local cmd=""
    
    debug_log "Processing choice: $choice"
    
    # menu_downloadの出力を保存して処理
    menu_download | {
        while IFS= read -r line; do
            if [ "$i" = "$choice" ]; then
                cmd="$line"
                break
            fi
            i=$((i + 1))
        done
        
        debug_log "Selected command: $cmd"
        
        # 選択されたコマンドを評価して実行
        if [ "$cmd" = "\"exit\" \"\" \"\"" ]; then
            if confirm "$(get_message "CONFIG_CONFIRM_DELETE")"; then
                debug_log "User requested script deletion"
                rm -f "$0"
                printf "%s\n" "$(get_message "CONFIG_DELETE_CONFIRMED")"
            else
                printf "%s\n" "$(get_message "CONFIG_DELETE_CANCELED")"
            fi
            return 255
        else
            # コマンドを実行
            eval "$cmd"
        fi
    }
    
    return 0
}

# 確認ダイアログを表示する関数
confirm() {
    local message="$1"
    local answer=""
    
    printf "%s " "$message"
    read -r answer
    
    case "$answer" in
        [Yy]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# メイン関数
main() {
    # メインループ
    while true; do
        selector "$(get_message "MENU_TITLE")"
        ret=$?
        
        # selector関数が255を返した場合（exit選択時）はループを終了
        if [ $ret -eq 255 ]; then
            break
        fi
    done
}

# スクリプト実行
main "$@"
