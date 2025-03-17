#!/bin/sh

SCRIPT_VERSION="2025.03.17-01-00"

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
MENU_DB="${BASE_DIR}/menu.db"

# ディレクトリ存在確認
check_directories() {
    debug_log "DEBUG" "Checking required directories"
    for dir in "$CACHE_DIR" "$FEED_DIR" "$LOG_DIR"; do
        if [ ! -d "$dir" ]; then
            debug_log "DEBUG" "Creating directory: $dir"
            mkdir -p "$dir"
        fi
    done
}

# 終了関数
menu_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_EXIT_CONFIRMED")")"
    sleep 1
    exit 0
}

# 削除関数
remove_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_DELETE_CONFIRMED")")"
    [ -f "$0" ] && rm -f "$0"
    [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
    exit 0
}

# メニュー選択関数
selector() {
    # 必要なディレクトリを確認
    check_directories
    
    local choice=""
    local section_name="${1:-openwrt-config}"
    local menu_file="${CACHE_DIR}/menu_entries.tmp"
    local cmd_file="${CACHE_DIR}/menu_commands.tmp"
    local colors="red blue green magenta cyan yellow white white_black"
    local color_index=0
    local color_name=""
    local menu_count=0
    
    debug_log "DEBUG" "Starting selector with section: $section_name"
    
    # メニューDBの存在確認
    if [ ! -f "$MENU_DB" ]; then
        debug_log "DEBUG" "Menu database not found: $MENU_DB"
        printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_NO_MENU_DB")")"
        return 1
    fi
    
    # 一時ファイルの初期化
    : > "$menu_file"
    : > "$cmd_file"
    
    # セクションの処理
    debug_log "DEBUG" "Processing section [$section_name]"
    local in_section=0
    
    while IFS= read -r line; do
        # コメントと空行をスキップ
        case "$line" in
            \#*|"") continue ;;
        esac
        
        # セクション開始判定
        if echo "$line" | grep -q "^\[$section_name\]"; then
            in_section=1
            debug_log "DEBUG" "Found target section: [$section_name]"
            continue
        fi
        
        # 別セクション開始で処理終了
        if echo "$line" | grep -q "^\[.*\]"; then
            [ $in_section -eq 1 ] && break
            continue
        fi
        
        # セクション内の項目処理
        if [ $in_section -eq 1 ]; then
            # 項目名とコマンドを分離
            key=$(echo "$line" | cut -d' ' -f1)
            cmd=$(echo "$line" | cut -d' ' -f2-)
            
            # 表示色の選択
            color_index=$(( (menu_count % 8) + 1 ))
            color_name=$(echo "$colors" | cut -d' ' -f$color_index)
            [ -z "$color_name" ] && color_name="white"
            
            # メニュー項目とコマンドを保存
            printf "%s\n" "$(color "$color_name" "$(get_message "$key")")" >> "$menu_file"
            printf "%s\n" "$cmd" >> "$cmd_file"
            
            menu_count=$((menu_count+1))
            debug_log "DEBUG" "Added menu item $menu_count: $key -> $cmd"
        fi
    done < "$MENU_DB"
    
    # メニュー項目の存在確認
    if [ $menu_count -eq 0 ]; then
        debug_log "DEBUG" "No menu items found in section [$section_name]"
        printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_NO_MENU_ITEMS")")"
        return 1
    fi
    
    # メニュー表示
    cat "$menu_file"
    
    # 選択プロンプト表示
    printf "%s\n" "$(color green "$(get_message "CONFIG_SELECT_PROMPT" "$menu_count")")"
    
    # ユーザー入力
    read -r choice
    debug_log "DEBUG" "User input: $choice"
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_NUMBER")")"
        sleep 2
        return 0
    fi
    
    # 選択範囲チェック
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_CHOICE" "$menu_count")")"
        sleep 2
        return 0
    fi
    
    # 選択コマンド実行
    selected_cmd=$(sed -n "${choice}p" "$cmd_file")
    debug_log "DEBUG" "Executing command: $selected_cmd"
    
    # コマンド実行
    eval "$selected_cmd"
    
    # 一時ファイル削除
    rm -f "$menu_file" "$cmd_file"
}

# メイン関数
main() {
    # 引数があれば指定セクションを表示
    if [ $# -gt 0 ]; then
        selector "$1"
        return $?
    fi
    
    # 引数がなければデフォルトメニュー表示
    while true; do
        selector "openwrt-config"
    done
}

# スクリプト実行
main "$@"
