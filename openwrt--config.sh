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
MENU_DB="${BASE_DIR}/menu.db"

menu_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_EXIT_CONFIRMED")")"
    sleep 1
    exit 0
}

remove_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_DELETE_CONFIRMED")")"
    [ -f "$0" ] && rm -f "$0"
    [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
    exit 0
}

# メニューデータベースからメニュー項目とコマンドを読み込む
selector() {
    choice=""
    local section_name="openwrt-config"
    local menu_file="${CACHE_DIR}/menu_entries.tmp"
    local cmd_file="${CACHE_DIR}/menu_commands.tmp"
    local color_list="red blue green magenta cyan yellow white white_black"
    local color_index=0
    local color_name=""
    local menu_count=0
    
    # メニューデータベースが存在するか確認
    if [ ! -f "$MENU_DB" ]; then
        debug_log "DEBUG" "Menu database not found: $MENU_DB"
        printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_NO_MENU_DB")")"
        return 1
    fi
    
    # 一時ファイルをクリア
    : > "$menu_file"
    : > "$cmd_file"
    
    # 対象セクションのデータを抽出
    debug_log "DEBUG" "Extracting menu items from section [$section_name]"
    local in_section=0
    
    # メニューデータベースから項目を読み込み
    while IFS= read -r line; do
        # 空行やコメント行をスキップ
        case "$line" in
            \#*|"") continue ;;
        esac
        
        # セクションの開始を検出
        if echo "$line" | grep -q "^\[$section_name\]"; then
            in_section=1
            debug_log "DEBUG" "Found section [$section_name]"
            continue
        fi
        
        # 別のセクションの開始を検出したら終了
        if echo "$line" | grep -q "^\[.*\]"; then
            [ $in_section -eq 1 ] && break
            continue
        fi
        
        # 対象セクション内の項目を処理
        if [ $in_section -eq 1 ]; then
            # 項目名とコマンドを分離
            key=$(echo "$line" | cut -d' ' -f1)
            cmd=$(echo "$line" | cut -d' ' -f2-)
            
            # 現在の色を取得
            color_name=$(echo "$color_list" | cut -d' ' -f$((color_index+1)))
            [ -z "$color_name" ] && color_name="white"
            
            # 項目名からメッセージを取得して色付けしてメニューに追加
            printf "%s\n" "$(color "$color_name" "$(get_message "$key")")" >> "$menu_file"
            
            # コマンドを保存
            printf "%s\n" "$cmd" >> "$cmd_file"
            
            # 色インデックスとメニューカウントを更新
            color_index=$((color_index+1))
            menu_count=$((menu_count+1))
        fi
    done < "$MENU_DB"
    
    # メニュー項目が見つからない場合
    if [ $menu_count -eq 0 ]; then
        debug_log "DEBUG" "No menu items found in section [$section_name]"
        printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_NO_MENU_ITEMS")")"
        return 1
    fi
    
    # メニュー項目を表示
    cat "$menu_file"
    
    # 選択プロンプト
    printf "%s\n" "$(color green "$(get_message "CONFIG_SELECT_PROMPT" "$menu_count")")"
    
    # ユーザー入力を読み取り
    read -r choice
    debug_log "DEBUG" "User selected option: $choice"
    
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
    
    # 選択したコマンドを取得して実行
    selected_cmd=$(sed -n "${choice}p" "$cmd_file")
    debug_log "DEBUG" "Executing command: $selected_cmd"
    
    # コマンド行を実行
    eval "$selected_cmd"
    
    # クリーンアップ
    rm -f "$menu_file" "$cmd_file"
}

# メイン関数
main() {
    while true; do
        selector
    done
}

# スクリプト実行
main "$@"
