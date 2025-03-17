#!/bin/sh

SCRIPT_VERSION="2025.03.17-02-00"

# メニューセレクター関数
selector() {
    # メニューDBとキャッシュディレクトリのパス
    local menu_db="${BASE_DIR}/menu.db"
    local section_name="${1:-openwrt-config}"
    local menu_file="${CACHE_DIR}/menu_entries.tmp"
    local cmd_file="${CACHE_DIR}/menu_commands.tmp"
    
    # デバッグ出力
    debug_log "DEBUG" "Starting selector function with section: $section_name"
    
    # ディレクトリ確認
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR"
        debug_log "DEBUG" "Created cache directory: $CACHE_DIR"
    fi
    
    # menu.dbの存在確認
    if [ ! -f "$menu_db" ]; then
        debug_log "ERROR" "Menu database not found: $menu_db"
        printf "%s\n" "$(color red "メニューデータベースが見つかりません")"
        return 1
    fi
    
    # menu.dbの内容をデバッグ表示
    if [ "$DEBUG_MODE" = "true" ]; then
        debug_log "DEBUG" "Menu DB content:"
        cat "$menu_db" | while read -r line; do
            debug_log "DEBUG" "DB line: $line"
        done
    fi
    
    # 一時ファイル初期化
    : > "$menu_file"
    : > "$cmd_file"
    
    # セクションを検索して処理
    debug_log "DEBUG" "Looking for section [$section_name] in menu.db"
    local in_section=0
    local menu_count=0
    local colors="red blue green magenta cyan yellow white white_black"
    
    cat "$menu_db" | while IFS= read -r line; do
        # コメントと空行をスキップ
        case "$line" in
            \#*|"") continue ;;
        esac
        
        # セクション開始をチェック
        if echo "$line" | grep -q "^\[$section_name\]"; then
            in_section=1
            debug_log "DEBUG" "Found section: [$section_name]"
            continue
        fi
        
        # 別のセクション開始で終了
        if echo "$line" | grep -q "^\[.*\]"; then
            [ $in_section -eq 1 ] && break
            continue
        fi
        
        # セクション内の項目を処理
        if [ $in_section -eq 1 ]; then
            # キーとコマンドを分離
            key=$(echo "$line" | cut -d' ' -f1)
            cmd=$(echo "$line" | cut -d' ' -f2-)
            
            # 色の選択
            local color_index=$(( (menu_count % 8) + 1 ))
            local color_name=$(echo "$colors" | cut -d' ' -f$color_index)
            [ -z "$color_name" ] && color_name="white"
            
            # メニュー項目とコマンドを保存
            printf "%s\n" "$(color "$color_name" "$(get_message "$key")")" >> "$menu_file"
            printf "%s\n" "$cmd" >> "$cmd_file"
            
            menu_count=$((menu_count+1))
            debug_log "DEBUG" "Added menu item $menu_count: $key -> $cmd"
        fi
    done
    
    # menu_countを更新（パイプ内の値は失われるため）
    menu_count=$(wc -l < "$menu_file")
    
    # メニュー項目の確認
    if [ $menu_count -eq 0 ]; then
        debug_log "ERROR" "No menu items found in section [$section_name]"
        printf "%s\n" "$(color red "セクション[$section_name]にメニュー項目がありません")"
        return 1
    fi
    
    # メニュー表示
    cat "$menu_file"
    
    # 選択プロンプト
    printf "%s\n" "$(color green "数字を入力して選択してください (1-$menu_count):")"
    
    # ユーザー入力
    local choice=""
    read -r choice
    debug_log "DEBUG" "User input: $choice"
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        printf "%s\n" "$(color red "有効な数字を入力してください")"
        sleep 2
        return 0
    fi
    
    # 選択範囲チェック
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        printf "%s\n" "$(color red "選択は1～${menu_count}の範囲で入力してください")"
        sleep 2
        return 0
    fi
    
    # コマンド実行
    local selected_cmd=$(sed -n "${choice}p" "$cmd_file")
    debug_log "DEBUG" "Executing command: $selected_cmd"
    eval "$selected_cmd"
    
    # 一時ファイル削除
    rm -f "$menu_file" "$cmd_file"
}

# 終了関数
menu_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_EXIT_CONFIRMED")")"
    sleep 1
    exit 0
}

# 削除終了関数
remove_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_DELETE_CONFIRMED")")"
    [ -f "$0" ] && rm -f "$0"
    [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
    exit 0
}

# メイン関数
main() {
    # デバッグモード時にmenu.dbの確認
    if [ "$DEBUG_MODE" = "true" ]; then
        if [ -f "${BASE_DIR}/menu.db" ]; then
            debug_log "DEBUG" "menu.db exists at ${BASE_DIR}/menu.db"
            debug_log "DEBUG" "First 10 lines of menu.db:"
            head -n 10 "${BASE_DIR}/menu.db" | while read -r line; do
                debug_log "DEBUG" "menu.db> $line"
            done
        else
            debug_log "ERROR" "menu.db not found at ${BASE_DIR}/menu.db"
        fi
    fi
    
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
