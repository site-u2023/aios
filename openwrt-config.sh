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
    local selector_output=""
    local choice=""
    
    debug_log "DEBUG" "Starting menu selector function"
    
    # キャプチャ用一時ファイル
    local temp_file="${CACHE_DIR}/menu_selector_output.tmp"
    menyu_selector > "$temp_file" 2>/dev/null
    
    # メニュー項目数をカウント
    menu_count=$(wc -l < "$temp_file")
    debug_log "DEBUG" "Menu contains $menu_count items"
    
    # メニューヘッダー表示
    clear
    printf "%s\n" "$(get_message "CONFIG_HEADER" "$SCRIPT_NAME" "$SCRIPT_VERSION")"
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    [ -n "$menu_title" ] && printf "%s\n" "$(get_message "CONFIG_SECTION_TITLE" "$menu_title")"
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # 一時ファイルからメニュー項目を表示
    cat "$temp_file"
    rm -f "$temp_file"
    
    # 選択プロンプト
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    printf "%s" "$(get_message "CONFIG_SELECT_PROMPT" "max=$menu_count") "
    read -r choice
    
    # 入力値を正規化
    choice=$(normalize_input "$choice")
    debug_log "DEBUG" "User selected: $choice"
    
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
    process_selection "$choice"
    return $?
}

# 選択されたメニュー項目を処理
process_selection() {
    local selected_number="$1"
    local temp_file="${CACHE_DIR}/menu_download_output.tmp"
    local command_line=""
    
    debug_log "DEBUG" "Processing menu selection: $selected_number"
    
    # menu_download関数の出力をファイルに保存
    menu_download > "$temp_file" 2>/dev/null
    
    # 対応するダウンロードコマンドを取得
    command_line=$(sed -n "${selected_number}p" "$temp_file")
    rm -f "$temp_file"
    
    debug_log "DEBUG" "Selected command: $command_line"
    
    # 特殊コマンド「exit」の処理
    if [ "$command_line" = "\"exit\" \"\" \"\"" ]; then
        debug_log "DEBUG" "Exit option selected"
        
        if confirm "$(get_message "CONFIG_CONFIRM_DELETE")"; then
            debug_log "DEBUG" "User confirmed script deletion"
            rm -f "$0"
            printf "%s\n" "$(get_message "CONFIG_DELETE_CONFIRMED")"
            return 255
        else
            printf "%s\n" "$(get_message "CONFIG_DELETE_CANCELED")"
            sleep 2
            return 0
        fi
    fi
    
    # 通常コマンドの実行
    debug_log "DEBUG" "Executing command: $command_line"
    eval "$command_line"
    return $?
}

# メイン関数
main() {
    local ret=0
    
    # キャッシュディレクトリを確保
    [ ! -d "${CACHE_DIR}" ] && mkdir -p "${CACHE_DIR}"
    
    debug_log "DEBUG" "Starting menu config script"
    
    # メインループ
    while true; do
        selector "$(get_message "MENU_TITLE")"
        ret=$?
        
        if [ "$ret" -eq 255 ]; then
            debug_log "DEBUG" "Script terminating"
            break
        fi
    done
}

# スクリプト実行
main "$@"
