#!/bin/sh

SCRIPT_VERSION="2025.03.17-09-30"

# メニューセレクター関数
selector() {
    local section_name="${1:-openwrt-config}"
    local menu_keys_file="${CACHE_DIR}/menu_keys.tmp"
    local menu_displays_file="${CACHE_DIR}/menu_displays.tmp"
    local menu_commands_file="${CACHE_DIR}/menu_commands.tmp"
    local colors="red blue green magenta cyan yellow white white_black"
    local menu_count=0
    
    debug_log "DEBUG" "Starting menu selector with section: $section_name"
    
    # メニューDBの存在確認
    if [ ! -f "${BASE_DIR}/menu.db" ]; then
        debug_log "ERROR" "Menu database not found at ${BASE_DIR}/menu.db"
        printf "%s\n" "$(color red "メニューデータベースが見つかりません")"
        return 1
    fi
    
    debug_log "DEBUG" "Menu DB path: ${BASE_DIR}/menu.db"
    
    # キャッシュディレクトリの存在確認と作成
    if [ ! -d "$CACHE_DIR" ]; then
        debug_log "DEBUG" "Creating cache directory: $CACHE_DIR"
        mkdir -p "$CACHE_DIR" || {
            debug_log "ERROR" "Failed to create cache directory: $CACHE_DIR"
            printf "%s\n" "$(color red "キャッシュディレクトリを作成できません")"
            return 1
        }
    fi
    
    # キャッシュファイルの初期化 (リダイレクト演算子を使用)
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"
    touch "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"
    
    # デバッグ用に一時ファイルの存在を確認
    if [ "$DEBUG_MODE" = "true" ]; then
        for f in "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"; do
            if [ -f "$f" ]; then
                debug_log "DEBUG" "Temporary file created: $f"
            else
                debug_log "ERROR" "Failed to create temporary file: $f"
            fi
        done
    fi
    
    # セクション検索
    debug_log "DEBUG" "Searching for section [$section_name] in menu.db"
    local in_section=0
    
    # ファイルを1行ずつ処理
    while IFS= read -r line || [ -n "$line" ]; do
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
            # キーとコマンドを分離して保存
            local key=$(echo "$line" | cut -d' ' -f1)
            local cmd=$(echo "$line" | cut -d' ' -f2-)
            
            # カウンターをインクリメント
            menu_count=$((menu_count+1))
            
            # 各ファイルに情報を保存
            echo "$key" >> "$menu_keys_file"
            
            # 色の選択
            local color_index=$(( (menu_count % 8) + 1 ))
            local color_name=$(echo "$colors" | cut -d' ' -f$color_index)
            [ -z "$color_name" ] && color_name="white"
            
            # get_messageの呼び出しを追加
            local display_text=$(get_message "$key")
            if [ -z "$display_text" ] || [ "$display_text" = "$key" ]; then
                # メッセージが見つからない場合はキーをそのまま使用
                display_text="$key"
                debug_log "DEBUG" "No message found for key: $key, using key as display text"
            fi
            
            # 表示テキストとコマンドを保存
            printf "%s\n" "$(color "$color_name" "$menu_count. $display_text")" >> "$menu_displays_file" 2>/dev/null
            printf "%s\n" "$cmd" >> "$menu_commands_file" 2>/dev/null
            
            debug_log "DEBUG" "Added menu item $menu_count: [$key] -> [$cmd]"
        fi
    done < "${BASE_DIR}/menu.db"
    
    # デバッグ: ファイル内容確認
    if [ "$DEBUG_MODE" = "true" ]; then
        debug_log "DEBUG" "Menu keys file content:"
        if [ -s "$menu_keys_file" ]; then
            cat "$menu_keys_file" | while IFS= read -r line; do
                debug_log "DEBUG" "  - $line"
            done
        else
            debug_log "DEBUG" "  (empty file)"
        fi
    fi
    
    # メニュー項目の確認
    if [ $menu_count -eq 0 ]; then
        debug_log "ERROR" "No menu items found in section [$section_name]"
        printf "%s\n" "$(color red "セクション[$section_name]にメニュー項目がありません")"
        return 1
    fi
    
    debug_log "DEBUG" "Found $menu_count menu items"
    
    # メニュー表示
    printf "\n%s\n" "$(color white_black "===============================")"
    printf "%s\n" "$(color white_black "          メインメニュー         ")"
    printf "%s\n" "$(color white_black "===============================")"
    printf "\n"
    
    if [ -s "$menu_displays_file" ]; then
        cat "$menu_displays_file"
    else
        debug_log "ERROR" "Menu display file is empty or cannot be read"
        printf "%s\n" "$(color red "メニュー表示ファイルが空か読めません")"
        return 1
    fi
    
    printf "\n"
    
    # 選択プロンプト
    printf "%s " "$(color green "数字を入力して選択してください (1-$menu_count):")"
    
    # ユーザー入力
    local choice=""
    if ! read -r choice; then
        debug_log "ERROR" "Failed to read user input"
        return 1
    fi
    
    # 入力の正規化（利用可能な場合のみ）
    if type normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    debug_log "DEBUG" "User input: $choice"
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        printf "\n%s\n" "$(color red "有効な数字を入力してください")"
        sleep 2
        return 0
    fi
    
    # 選択範囲チェック
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        printf "\n%s\n" "$(color red "選択は1～${menu_count}の範囲で入力してください")"
        sleep 2
        return 0
    fi
    
    # 選択されたキーとコマンドを取得
    local selected_key=""
    local selected_cmd=""
    
    selected_key=$(sed -n "${choice}p" "$menu_keys_file" 2>/dev/null)
    selected_cmd=$(sed -n "${choice}p" "$menu_commands_file" 2>/dev/null)
    
    if [ -z "$selected_key" ] || [ -z "$selected_cmd" ]; then
        debug_log "ERROR" "Failed to retrieve selected menu item data"
        printf "%s\n" "$(color red "メニュー項目の取得に失敗しました")"
        return 1
    fi
    
    debug_log "DEBUG" "Selected key: $selected_key"
    debug_log "DEBUG" "Executing command: $selected_cmd"
    
    # コマンド実行前の表示
    local msg=$(get_message "$selected_key")
    [ -z "$msg" ] && msg="$selected_key"
    printf "\n%s\n\n" "$(color blue "${msg}を実行します...")"
    sleep 1
    
    # コマンド実行
    eval "$selected_cmd"
    local cmd_status=$?
    
    debug_log "DEBUG" "Command execution finished with status: $cmd_status"
    
    # 一時ファイル削除
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"
    
    return $cmd_status
}

# 終了関数
menu_exit() {
    printf "%s\n" "$(color green "スクリプトを終了します")"
    sleep 1
    exit 0
}

# 削除終了関数
remove_exit() {
    printf "%s\n" "$(color yellow "警告: スクリプトと関連ディレクトリを削除しようとしています")"
    
    printf "%s " "$(color cyan "本当に削除してよろしいですか？ (y/n):")"
    local choice=""
    read -r choice
    
    # 入力の正規化（利用可能な場合のみ）
    if type normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    
    case "$choice" in
        [Yy]|[Yy][Ee][Ss])
            printf "%s\n" "$(color green "スクリプトと関連ディレクトリを削除します")"
            [ -f "$0" ] && rm -f "$0"
            [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
            exit 0
            ;;
        *)
            printf "%s\n" "$(color blue "削除をキャンセルしました")"
            return 0
            ;;
    esac
}

# メイン関数
main() {
    # デバッグモードでmenu.dbの内容を確認
    if [ "$DEBUG_MODE" = "true" ]; then
        if [ -f "${BASE_DIR}/menu.db" ]; then
            debug_log "DEBUG" "Menu DB exists at ${BASE_DIR}/menu.db"
            debug_log "DEBUG" "First 10 lines of menu.db:"
            head -n 10 "${BASE_DIR}/menu.db" | while IFS= read -r line; do
                debug_log "DEBUG" "menu.db> $line"
            done
        else
            debug_log "ERROR" "Menu DB not found at ${BASE_DIR}/menu.db"
        fi
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

# スクリプト自体が直接実行された場合のみ、mainを実行
if [ "$(basename "$0")" = "menu-selector.sh" ]; then
    main "$@"
fi
