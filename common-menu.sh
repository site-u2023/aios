#!/bin/sh

# メニューセレクター関数 - POSIX準拠版
selector() {
    # グローバル変数かパラメータからセクション名を取得
    local section_name=""
    if [ -n "$1" ]; then
        section_name="$1"
    elif [ -n "$SELECTOR_MENU" ]; then
        section_name="$SELECTOR_MENU"
    else
        section_name="openwrt-config"
    fi
    
    debug_log "DEBUG" "Starting menu selector with section: $section_name"
    
    # メインメニュー名を設定（グローバル変数か既定値）
    local main_menu="${MAIN_MENU:-openwrt-config}"
    
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
    
    # キャッシュファイルの初期化
    local menu_keys_file="${CACHE_DIR}/menu_keys.tmp"
    local menu_displays_file="${CACHE_DIR}/menu_displays.tmp"
    local menu_commands_file="${CACHE_DIR}/menu_commands.tmp"
    local menu_colors_file="${CACHE_DIR}/menu_colors.tmp"
    local menu_count=0
    
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    touch "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    
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
            # 色、キー、コマンドを分離
            local color_name=$(echo "$line" | cut -d' ' -f1)
            local key=$(echo "$line" | cut -d' ' -f2)
            local cmd=$(echo "$line" | cut -d' ' -f3-)
            
            debug_log "DEBUG" "Parsing line: color=$color_name, key=$key, cmd=$cmd"
            
            # カウンターをインクリメント
            menu_count=$((menu_count+1))
            
            # 各ファイルに情報を保存
            echo "$key" >> "$menu_keys_file"
            echo "$cmd" >> "$menu_commands_file"
            echo "$color_name" >> "$menu_colors_file"
            
            # get_messageの呼び出し
            local display_text=$(get_message "$key")
            if [ -z "$display_text" ] || [ "$display_text" = "$key" ]; then
                # メッセージが見つからない場合はキーをそのまま使用
                display_text="$key"
                debug_log "DEBUG" "No message found for key: $key, using key as display text"
            fi
            
            # 表示テキストを保存（[数字] 形式）
            printf "%s\n" "$(color "$color_name" "[${menu_count}] $display_text")" >> "$menu_displays_file" 2>/dev/null
            
            debug_log "DEBUG" "Added menu item $menu_count: [$key] -> [$cmd] with color: $color_name"
        fi
    done < "${BASE_DIR}/menu.db"
    
    # メニュー項目の確認
    if [ $menu_count -eq 0 ]; then
        debug_log "ERROR" "No menu items found in section [$section_name]"
        printf "%s\n" "$(color red "セクション[$section_name]にメニュー項目がありません")"
        
        # メインメニューに戻る処理（主要な修正箇所）
        if [ "$section_name" != "$main_menu" ]; then
            debug_log "INFO" "Returning to main menu after error"
            printf "%s\n" "$(color blue "メインメニューに戻ります...")"
            sleep 2
            selector "$main_menu"
            return $?
        fi
        
        return 1
    fi
    
    debug_log "DEBUG" "Found $menu_count menu items"
    
    # タイトルヘッダーを表示
    local title=$(get_message "MENU_TITLE")
    
    # MENU_TITLEの後に1つの空白と[セクション名]を表示
    printf "\n%s\n\n" "$(color white_black "${title} [$section_name]")"
    
    if [ -s "$menu_displays_file" ]; then
        cat "$menu_displays_file"
    else
        debug_log "ERROR" "Menu display file is empty or cannot be read"
        printf "%s\n" "$(color red "メニュー表示ファイルが空か読めません")"
        
        # メインメニューに戻る処理
        if [ "$section_name" != "$main_menu" ]; then
            debug_log "INFO" "Returning to main menu after error"
            printf "%s\n" "$(color blue "メインメニューに戻ります...")"
            sleep 2
            selector "$main_menu"
            return $?
        fi
        
        return 1
    fi
    
    printf "\n"
    
    # 選択プロンプト表示
    local selection_prompt=$(get_message "CONFIG_SELECT_PROMPT")
    # {0}をメニュー数で置換
    selection_prompt=$(echo "$selection_prompt" | sed "s/{0}/$menu_count/g")
    printf "%s" "$(color green "$selection_prompt")"
    
    # ユーザー入力
    local choice=""
    if ! read -r choice; then
        debug_log "ERROR" "Failed to read user input"
        
        # メインメニューに戻る処理
        if [ "$section_name" != "$main_menu" ]; then
            debug_log "INFO" "Returning to main menu after input error"
            printf "%s\n" "$(color blue "メインメニューに戻ります...")"
            sleep 2
            selector "$main_menu"
            return $?
        fi
        
        return 1
    fi
    
    # 入力の正規化（利用可能な場合のみ）
    if command -v normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    debug_log "DEBUG" "User input: $choice"
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        local error_msg=$(get_message "CONFIG_ERROR_NOT_NUMBER")
        printf "\n%s\n" "$(color red "$error_msg")"
        sleep 2
        # 同じメニューを再表示
        selector "$section_name"
        return $?
    fi
    
    # 選択範囲チェック
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        local error_msg=$(get_message "CONFIG_ERROR_INVALID_NUMBER")
        error_msg=$(echo "$error_msg" | sed "s/{0}/$menu_count/g")
        printf "\n%s\n" "$(color red "$error_msg")"
        sleep 2
        # 同じメニューを再表示
        selector "$section_name"
        return $?
    fi
    
    # 選択されたキーとコマンドを取得
    local selected_key=""
    local selected_cmd=""
    local selected_color=""
    
    selected_key=$(sed -n "${choice}p" "$menu_keys_file" 2>/dev/null)
    selected_cmd=$(sed -n "${choice}p" "$menu_commands_file" 2>/dev/null)
    selected_color=$(sed -n "${choice}p" "$menu_colors_file" 2>/dev/null)
    
    if [ -z "$selected_key" ] || [ -z "$selected_cmd" ]; then
        debug_log "ERROR" "Failed to retrieve selected menu item data"
        printf "%s\n" "$(color red "メニュー項目の取得に失敗しました")"
        
        # メインメニューに戻る処理
        if [ "$section_name" != "$main_menu" ]; then
            debug_log "INFO" "Returning to main menu after menu item error"
            printf "%s\n" "$(color blue "メインメニューに戻ります...")"
            sleep 2
            selector "$main_menu"
            return $?
        }
        
        return 1
    fi
    
    debug_log "DEBUG" "Selected key: $selected_key"
    debug_log "DEBUG" "Selected color: $selected_color"
    debug_log "DEBUG" "Executing command: $selected_cmd"
    
    # コマンド実行前の表示
    local msg=$(get_message "$selected_key")
    [ -z "$msg" ] && msg="$selected_key"
    local download_msg=$(get_message "CONFIG_DOWNLOADING")
    download_msg=$(echo "$download_msg" | sed "s/{0}/$msg/g")
    printf "\n%s\n\n" "$(color "$selected_color" "$download_msg")"
    sleep 1
    
    # コマンド実行
    eval "$selected_cmd"
    local cmd_status=$?
    
    debug_log "DEBUG" "Command execution finished with status: $cmd_status"
    
    # エラー発生時にメインメニューに戻る
    if [ $cmd_status -ne 0 ]; then
        debug_log "ERROR" "Command execution failed with status: $cmd_status"
        # メインメニューに戻る処理（ただしメインメニュー実行中のエラーは除く）
        if [ "$section_name" != "$main_menu" ]; then
            debug_log "INFO" "Returning to main menu after command error"
            printf "%s\n" "$(color blue "メインメニューに戻ります...")"
            sleep 2
            selector "$main_menu"
            return $?
        fi
    fi
    
    # 一時ファイル削除
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    
    return $cmd_status
}
