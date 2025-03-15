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
printf "%s\n" "$(color yellow "$(get_message "MENU_OTHERS")")"
printf "%s\n" "$(color white_black "$(get_message "MENU_EXIT")")"
)

# ダウンロード用データ
menu_download() (
download "internet-config.sh" "chmod" "load"
download "system-config.sh" "chmod" "load"
download "package-install.sh" "chmod" "load"
download "adblocker-dns.sh" "chmod" "load"
download "accesspoint-setup.sh" "chmod" "load"
download "other-utilities.sh" "chmod" "load"
"exit" "" ""
)

# メニューセレクター関数（メニュー表示と選択処理）
selector() {
    local menu_title="$1"
    local menu_count=0
    local choice=""
    local i=0
    
    debug_log "DEBUG" "Starting menu selector function"
    
    # メニューデータを取得して行数をカウント
    local temp_file="${CACHE_DIR}/menu_selector_output.tmp"
    menyu_selector > "$temp_file" 2>/dev/null
    menu_count=$(wc -l < "$temp_file")
    debug_log "DEBUG" "Menu contains $menu_count items"
    
    # メニューヘッダー表示
    clear
    # プレースホルダーの置換を確実に行うため、直接変数を代入
    local header_text="$(get_message "CONFIG_HEADER")"
    header_text=$(echo "$header_text" | sed "s/{0}/$SCRIPT_NAME/g" | sed "s/{1}/$SCRIPT_VERSION/g")
    printf "%s\n" "$header_text"
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    if [ -n "$menu_title" ]; then
        local title_text="$(get_message "CONFIG_SECTION_TITLE")"
        title_text=$(echo "$title_text" | sed "s/{0}/$menu_title/g")
        printf "%s\n" "$title_text"
    fi
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # 番号付きでメニュー項目を表示
    i=1
    while IFS= read -r line; do
        # メニュー項目番号と内容を表示
        printf " [%d]: %s\n" "$i" "$line"
        i=$((i + 1))
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    # 選択プロンプト
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # プレースホルダーの置換を確実に行う
    local prompt_text="$(get_message "CONFIG_SELECT_PROMPT")"
    prompt_text=$(echo "$prompt_text" | sed "s/{0}/$menu_count/g")
    printf "%s " "$prompt_text"
    
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
        local error_text="$(get_message "CONFIG_ERROR_INVALID_NUMBER")"
        error_text=$(echo "$error_text" | sed "s/{0}/$menu_count/g")
        printf "%s\n" "$error_text"
        sleep 2
        return 0
    fi
    
    # 選択アクションの実行
    execute_menu_action "$choice"
    
    return $?
}

# 選択メニュー実行関数
execute_menu_action() {
    local choice="$1"
    local temp_file="${CACHE_DIR}/menu_download_commands.tmp"
    local command_line=""
    
    debug_log "DEBUG" "Processing menu selection: $choice"
    
    # メニューコマンドを取得
    menu_download > "$temp_file" 2>/dev/null
    command_line=$(sed -n "${choice}p" "$temp_file")
    rm -f "$temp_file"
    
    debug_log "DEBUG" "Selected command: $command_line"
    
    # 終了処理
    if [ "$command_line" = "\"exit\" \"\" \"\"" ]; then
        debug_log "DEBUG" "Exit option selected"
        
        local confirm_text="$(get_message "CONFIG_CONFIRM_DELETE")"
        if confirm "$confirm_text"; then
            debug_log "DEBUG" "User confirmed script deletion"
            rm -f "$0"
            printf "%s\n" "$(get_message "CONFIG_DELETE_CONFIRMED")"
            return 255
        else
            debug_log "DEBUG" "User cancelled script deletion"
            printf "%s\n" "$(get_message "CONFIG_DELETE_CANCELED")"
            sleep 2
            return 0
        fi
    fi
    
    # 通常コマンド実行
    debug_log "DEBUG" "Executing command: $command_line"
    eval "$command_line"
    
    return $?
}

# メイン関数
main() {
    local ret=0
    
    # キャッシュディレクトリ確保
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
