#!/bin/sh

SCRIPT_VERSION="2025.03.17-03-00"

# メニューセレクター関数
selector() {
    local section_name="${1:-openwrt-config}"
    local menu_file="${CACHE_DIR}/menu_entries.tmp"
    local cmd_file="${CACHE_DIR}/menu_commands.tmp"
    local colors="red blue green magenta cyan yellow white white_black"
    local menu_count=0
    
    debug_log "DEBUG" "Starting menu selector with section: $section_name"
    
    # メニューDBの存在確認
    if [ ! -f "${BASE_DIR}/menu.db" ]; then
        debug_log "ERROR" "Menu database not found at ${BASE_DIR}/menu.db"
        printf "%s\n" "$(color red "メニューデータベースが見つかりません")"
        return 1
    fi
    
    # デバッグ表示
    debug_log "DEBUG" "Menu DB path: ${BASE_DIR}/menu.db"
    
    # 一時ファイル初期化
    : > "$menu_file"
    : > "$cmd_file"
    
    # セクション検索
    debug_log "DEBUG" "Searching for section [$section_name] in menu.db"
    local in_section=0
    
    # ファイルを1行ずつ処理
    while IFS= read -r line; do
        # コメントと空行をスキップ
        case "$line" in
            \#*|"") continue ;;
        esac
        
        # セクション開始をチェック
        if echo "$line" | grep -q "^\[$section_name\]"; then
            in_section=1
            debug_log "DEBUG" "Found target section: [$section_name]"
            continue
        fi
        
        # 別のセクション開始で終了
        if echo "$line" | grep -q "^\[.*\]"; then
            if [ $in_section -eq 1 ]; then
                debug_log "DEBUG" "Reached next section, stopping search"
                break
            fi
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
            debug_log "DEBUG" "Added menu item: $key -> $cmd"
        fi
    done < "${BASE_DIR}/menu.db"
    
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
    printf "%s\n" "$(color green "スクリプトを終了します")"
    sleep 1
    exit 0
}

# 削除終了関数
remove_exit() {
    printf "%s\n" "$(color green "スクリプトと関連ディレクトリを削除します")"
    [ -f "$0" ] && rm -f "$0"
    [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
    exit 0
}

# メイン関数
main() {
    debug_log "DEBUG" "menu.db exists at ${BASE_DIR}/menu.db"
    
    if [ "$DEBUG_MODE" = "true" ]; then
        debug_log "DEBUG" "First 10 lines of menu.db:"
        head -n 10 "${BASE_DIR}/menu.db" | while read -r line; do
            debug_log "DEBUG" "menu.db> $line"
        done
    fi
    
    # 引数があれば指定セクションを表示
    if [ $# -gt 0 ]; then
        selector "$1"
        return $?
    fi
    
    # 引数がなければデフォルトセクションを表示
    while true; do
        selector "openwrt-config"
    done
}

# スクリプト実行
main "$@"
