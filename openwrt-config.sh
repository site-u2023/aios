#!/bin/sh

SCRIPT_VERSION="2025.03.17-10-45"

# メニューセレクター関数
selector() {
    section_name="${1:-openwrt-config}"
    menu_keys_file="${CACHE_DIR}/menu_keys.tmp"
    menu_displays_file="${CACHE_DIR}/menu_displays.tmp"
    menu_commands_file="${CACHE_DIR}/menu_commands.tmp"
    colors="red blue green magenta cyan yellow white white_black"
    menu_count=0
    
    [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Starting menu selector with section: $section_name"
    
    # メニューDBの存在確認
    if [ ! -f "${BASE_DIR}/menu.db" ]; then
        [ "$DEBUG_MODE" = "true" ] && echo "[ERROR] Menu database not found at ${BASE_DIR}/menu.db"
        printf "%s\n" "$(color red "メニューデータベースが見つかりません")"
        return 1
    fi
    
    [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Menu DB path: ${BASE_DIR}/menu.db"
    
    # キャッシュディレクトリの存在確認と作成
    if [ ! -d "$CACHE_DIR" ]; then
        [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Creating cache directory: $CACHE_DIR"
        mkdir -p "$CACHE_DIR" || {
            [ "$DEBUG_MODE" = "true" ] && echo "[ERROR] Failed to create cache directory: $CACHE_DIR"
            printf "%s\n" "$(color red "キャッシュディレクトリを作成できません")"
            return 1
        }
    fi
    
    # キャッシュファイルの初期化
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"
    touch "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"
    
    # デバッグ用に一時ファイルの存在を確認
    if [ "$DEBUG_MODE" = "true" ]; then
        for f in "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"; do
            if [ -f "$f" ]; then
                echo "[DEBUG] Temporary file created: $f"
            else
                echo "[ERROR] Failed to create temporary file: $f"
            fi
        done
    fi
    
    # セクション検索
    [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Searching for section [$section_name] in menu.db"
    in_section=0
    
    # ファイルを1行ずつ処理
    while IFS= read -r line || [ -n "$line" ]; do
        # コメントと空行をスキップ
        case "$line" in
            \#*|"") continue ;;
        esac
        
        # セクション開始をチェック
        if echo "$line" | grep -q "^\[$section_name\]"; then
            in_section=1
            [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Found target section: [$section_name]"
            continue
        fi
        
        # 別のセクション開始で終了
        if echo "$line" | grep -q "^\[.*\]"; then
            if [ $in_section -eq 1 ]; then
                [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Reached next section, stopping search"
                break
            fi
            continue
        fi
        
        # セクション内の項目を処理
        if [ $in_section -eq 1 ]; then
            # キーとコマンドを分離して保存
            key=$(echo "$line" | cut -d' ' -f1)
            cmd=$(echo "$line" | cut -d' ' -f2-)
            
            # カウンターをインクリメント
            menu_count=$((menu_count+1))
            
            # 各ファイルに情報を保存
            echo "$key" >> "$menu_keys_file"
            
            # 色の選択
            color_index=$(( (menu_count % 8) + 1 ))
            color_name=$(echo "$colors" | cut -d' ' -f$color_index)
            [ -z "$color_name" ] && color_name="white"
            
            # get_messageの呼び出し
            display_text=$(get_message "$key")
            if [ -z "$display_text" ] || [ "$display_text" = "$key" ]; then
                # メッセージが見つからない場合はキーをそのまま使用
                display_text="$key"
                [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] No message found for key: $key, using key as display text"
            fi
            
            # 表示テキストとコマンドを保存（[数字] 形式に変更）
            printf "%s\n" "$(color "$color_name" "[${menu_count}] $display_text")" >> "$menu_displays_file" 2>/dev/null
            printf "%s\n" "$cmd" >> "$menu_commands_file" 2>/dev/null
            
            [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Added menu item $menu_count: [$key] -> [$cmd]"
        fi
    done < "${BASE_DIR}/menu.db"
    
    # デバッグ: ファイル内容確認
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[DEBUG] Menu keys file content:"
        if [ -s "$menu_keys_file" ]; then
            cat "$menu_keys_file" | while IFS= read -r line; do
                echo "[DEBUG]  - $line"
            done
        else
            echo "[DEBUG]  (empty file)"
        fi
    fi
    
    # メニュー項目の確認
    if [ $menu_count -eq 0 ]; then
        [ "$DEBUG_MODE" = "true" ] && echo "[ERROR] No menu items found in section [$section_name]"
        printf "%s\n" "$(color red "セクション[$section_name]にメニュー項目がありません")"
        return 1
    fi
    
    [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Found $menu_count menu items"
    
    # メニュー表示
    printf "\n%s\n" "$(color white "==============================================================")"
    printf "%s\n" "$(color white "          CONFIG_HEADER        ")"
    printf "%s\n" "$(color white "==============================================================")"
    printf "\n"
    
    if [ -s "$menu_displays_file" ]; then
        cat "$menu_displays_file"
    else
        [ "$DEBUG_MODE" = "true" ] && echo "[ERROR] Menu display file is empty or cannot be read"
        printf "%s\n" "$(color red "メニュー表示ファイルが空か読めません")"
        return 1
    fi
    
    printf "\n"
    
    # 選択プロンプト表示
    selection_prompt=$(get_message "CONFIG_SELECT_PROMPT")
    # {0}をメニュー数で置換
    selection_prompt=$(echo "$selection_prompt" | sed "s/{0}/$menu_count/g")
    printf "%s" "$(color green "$selection_prompt")"
    
    # ユーザー入力
    choice=""
    if ! read -r choice; then
        [ "$DEBUG_MODE" = "true" ] && echo "[ERROR] Failed to read user input"
        return 1
    fi
    
    # 入力の正規化（利用可能な場合のみ）
    if command -v normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] User input: $choice"
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        error_msg=$(get_message "CONFIG_ERROR_NOT_NUMBER")
        printf "\n%s\n" "$(color red "$error_msg")"
        sleep 2
        return 0
    fi
    
    # 選択範囲チェック
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        error_msg=$(get_message "CONFIG_ERROR_INVALID_NUMBER")
        error_msg=$(echo "$error_msg" | sed "s/{0}/$menu_count/g")
        printf "\n%s\n" "$(color red "$error_msg")"
        sleep 2
        return 0
    fi
    
    # 選択されたキーとコマンドを取得
    selected_key=""
    selected_cmd=""
    
    selected_key=$(sed -n "${choice}p" "$menu_keys_file" 2>/dev/null)
    selected_cmd=$(sed -n "${choice}p" "$menu_commands_file" 2>/dev/null)
    
    if [ -z "$selected_key" ] || [ -z "$selected_cmd" ]; then
        [ "$DEBUG_MODE" = "true" ] && echo "[ERROR] Failed to retrieve selected menu item data"
        printf "%s\n" "$(color red "メニュー項目の取得に失敗しました")"
        return 1
    fi
    
    [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Selected key: $selected_key"
    [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Executing command: $selected_cmd"
    
    # コマンド実行前の表示
    msg=$(get_message "$selected_key")
    [ -z "$msg" ] && msg="$selected_key"
    download_msg=$(get_message "CONFIG_DOWNLOADING")
    download_msg=$(echo "$download_msg" | sed "s/{0}/$msg/g")
    printf "\n%s\n\n" "$(color blue "$download_msg")"
    sleep 1
    
    # コマンド実行
    eval "$selected_cmd"
    cmd_status=$?
    
    [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Command execution finished with status: $cmd_status"
    
    # 一時ファイル削除
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"
    
    return $cmd_status
}

# 終了関数
menu_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_EXIT_CONFIRMED")")"
    sleep 1
    exit 0
}

# 削除終了関数
remove_exit() {
    printf "%s\n" "$(color yellow "$(get_message "CONFIG_CONFIRM_DELETE")")"
    
    printf "%s " "$(color cyan "本当に削除してよろしいですか？ (y/n):")"
    choice=""
    read -r choice
    
    # 入力の正規化（利用可能な場合のみ）
    if command -v normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    
    case "$choice" in
        [Yy]|[Yy][Ee][Ss])
            printf "%s\n" "$(color green "$(get_message "CONFIG_DELETE_CONFIRMED")")"
            [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH"
            [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
            exit 0
            ;;
        *)
            printf "%s\n" "$(color blue "$(get_message "CONFIG_DELETE_CANCELED")")"
            return 0
            ;;
    esac
}

# メイン関数
main() {
    # デバッグモードでmenu.dbの内容を確認
    if [ "$DEBUG_MODE" = "true" ]; then
        if [ -f "${BASE_DIR}/menu.db" ]; then
            echo "[DEBUG] Menu DB exists at ${BASE_DIR}/menu.db"
            echo "[DEBUG] First 10 lines of menu.db:"
            head -n 10 "${BASE_DIR}/menu.db" | while IFS= read -r line; do
                echo "[DEBUG] menu.db> $line"
            done
        else
            echo "[ERROR] Menu DB not found at ${BASE_DIR}/menu.db"
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

main "$@"
