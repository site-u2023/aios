#!/bin/sh

COMMON_VERSION="2025.03.19-05-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-19
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 24.10.0)
#
# ⚠️ IMPORTANT NOTICE:
# OpenWrt OS exclusively uses **Almquist Shell (ash)** and
# is **NOT** compatible with Bourne-Again Shell (bash).
#
# 📢 POSIX Compliance Guidelines:
# ✅ Use `[` instead of `[[` for conditions
# ✅ Use $(command) instead of backticks `command`
# ✅ Use $(( )) for arithmetic instead of let
# ✅ Define functions as func_name() {} (no function keyword)
# ✅ No associative arrays (declare -A is NOT supported)
# ✅ No here-strings (<<< is NOT supported)
# ✅ No -v flag in test or [[
# ✅ Avoid bash-specific string operations like ${var:0:3}
# ✅ Avoid arrays entirely when possible (even indexed arrays can be problematic)
# ✅ Use printf followed by read instead of read -p
# ✅ Use printf instead of echo -e for portable formatting
# ✅ Avoid process substitution <() and >()
# ✅ Prefer case statements over complex if/elif chains
# ✅ Use command -v instead of which or type for command existence checks
# ✅ Keep scripts modular with small, focused functions
# ✅ Use simple error handling instead of complex traps
# ✅ Test scripts with ash/dash explicitly, not just bash
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
### =========================================================

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="${BASE_WGET:-wget --no-check-certificate -q -O}"
# BASE_WGET="${BASE_WGET:-wget -O}"
DEBUG_MODE="${DEBUG_MODE:-false}"
BIN_PATH=$(readlink -f "$0")
BIN_DIR="$(dirname "$BIN_PATH")"
BIN_FILE="$(basename "$BIN_PATH")"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# メインメニューのセクション名を定義
MAIN_MENU="${MAIN_MENU:-openwrt-config}"

# メニュー履歴を追跡するためのグローバル変数
MENU_HISTORY=""
CURRENT_MENU=""
MENU_HISTORY_SEPARATOR=":"

# メニュー履歴にエントリを追加する関数
pop_menu_history() {
    debug_log "DEBUG" "Popping from menu history"
    
    # 履歴が空の場合は何も返さない
    if [ -z "$MENU_HISTORY" ]; then
        debug_log "DEBUG" "History is empty, nothing to pop"
        return
    fi
    
    # 最後のメニュー名とテキストを取得（履歴の末尾2項目を削除）
    local history_len=$(echo "$MENU_HISTORY" | tr -cd "$MENU_HISTORY_SEPARATOR" | wc -c)
    local menu_count=$((history_len / 2 + 1))  # メニュー数
    
    if [ "$menu_count" -le 1 ]; then
        # 残り1つの場合は全履歴をクリア
        local result="$MENU_HISTORY"
        MENU_HISTORY=""
        debug_log "DEBUG" "Popped last entry from history, now empty"
        echo "$result" | cut -d"$MENU_HISTORY_SEPARATOR" -f1
    else
        # 最後の2項目（メニュー名:テキスト）を削除
        local last_menu=$(echo "$MENU_HISTORY" | rev | cut -d"$MENU_HISTORY_SEPARATOR" -f3 | rev)
        MENU_HISTORY=$(echo "$MENU_HISTORY" | rev | cut -d"$MENU_HISTORY_SEPARATOR" -f3- | rev)
        debug_log "DEBUG" "Popped last entry, remaining history: $MENU_HISTORY"
        echo "$last_menu"
    fi
}

display_breadcrumbs() {
    debug_log "DEBUG" "Building breadcrumb navigation chain"
    
    # メインメニューのテキスト取得
    local main_menu_text=$(get_message "MAIN_MENU_NAME")
    [ -z "$main_menu_text" ] && main_menu_text="● メインメニュー"
    
    # パンくずの初期値
    local breadcrumb="$(color white "$main_menu_text")"
    local separator=" > "
    
    # 履歴が空ならメインメニューのみ表示
    if [ -z "$MENU_HISTORY" ]; then
        debug_log "DEBUG" "No menu history, showing main menu only"
        printf "%s\n\n" "$breadcrumb"
        return
    fi
    
    # 逆順で表示テキストを抽出（一時ファイル不使用）
    local i=0
    local items=""
    
    IFS="$MENU_HISTORY_SEPARATOR"
    for item in $MENU_HISTORY; do
        i=$((i + 1))
        if [ $((i % 2)) -eq 0 ]; then
            # 表示テキストを逆順に追加
            items="$item $items"
        fi
    done
    unset IFS
    
    # パンくずを構築
    for item in $items; do
        breadcrumb="${breadcrumb}${separator}$(color white "$item")"
    done
    
    printf "%s\n\n" "$breadcrumb"
}

# エラーハンドリング関数 - 一元化された処理
handle_menu_error() {
    local error_type="$1"    # エラータイプ
    local section_name="$2"  # 現在のセクション名
    local previous_menu="$3" # 前のメニュー名
    local main_menu="$4"     # メインメニュー名
    local error_msg="$5"     # エラーメッセージキー（オプション）

    debug_log "ERROR" "$error_type in section [$section_name]"
    
    # エラーメッセージ表示
    local msg_key="${error_msg:-MSG_ERROR_OCCURRED}"
    printf "%s\n" "$(color red "$(get_message "$msg_key")")"
    
    sleep 2
    
    # エラー時にメニューに戻る処理
    if [ "$section_name" = "$main_menu" ]; then
        # メインメニューの場合は再表示（ループ）
        debug_log "DEBUG" "Main menu $error_type, reloading main menu"
        # 履歴をクリア
        MENU_HISTORY=""
        selector "$main_menu" "" 1
        return $?
    else
        # サブメニューの場合は前のメニューに戻る
        debug_log "DEBUG" "Returning to previous menu after $error_type"
        local prev_menu=$(pop_menu_history)
        [ -z "$prev_menu" ] && prev_menu="$main_menu"
        selector "$prev_menu" "" 1
        return $?
    fi
}

# 色の自動割り当て関数（9色対応）
get_auto_color() {
    local position="$1"
    local total_items="$2"
    
    debug_log "DEBUG" "Auto-assigning color for position $position of $total_items items"
    
    # 各メニュー項目数に対応する色配列を定義
    local colors_9="magenta purple indigo blue cyan green yellow orange red"
    local colors_8="purple indigo blue cyan green yellow orange red"
    local colors_7="purple indigo blue green yellow orange red"
    local colors_6="magenta blue cyan green yellow red"
    local colors_5="magenta blue green yellow red"
    local colors_4="blue green yellow red"
    local colors_3="blue green red"
    local colors_2="magent green"
    local colors_1="green"
    
    # 項目数に応じた色配列を選択
    local color_list=""
    case "$total_items" in
        9) color_list="$colors_9" ;;
        8) color_list="$colors_8" ;;
        7) color_list="$colors_7" ;;
        6) color_list="$colors_6" ;;
        5) color_list="$colors_5" ;;
        4) color_list="$colors_4" ;;
        3) color_list="$colors_3" ;;
        2) color_list="$colors_2" ;;
        1) color_list="$colors_1" ;;
        *) echo "white"; return ;; # フォールバック
    esac
    
    # 位置に対応する色を抽出（POSIXシェル互換）
    local i=1
    local selected_color="white" # フォールバック
    
    for color in $color_list; do
        if [ "$i" -eq "$position" ]; then
            selected_color="$color"
            break
        fi
        i=$((i + 1))
    done
    
    echo "$selected_color"
}

# メニュー項目の処理関数
process_menu_items() {
    local section_name="$1"
    local menu_keys_file="$2"
    local menu_displays_file="$3"
    local menu_commands_file="$4"
    local menu_colors_file="$5"
    
    debug_log "DEBUG" "Processing menu items for section: $section_name"
    
    local menu_count=0
    local total_normal_items=0
    local in_section=0
    
    # まず、セクション内の通常項目数をカウント（特殊項目を除く）
    while IFS= read -r line || [ -n "$line" ]; do
        # コメントと空行をスキップ
        case "$line" in
            \#*|"") continue ;;
        esac
        
        # セクション開始をチェック
        if echo "$line" | grep -q "^\[$section_name\]"; then
            in_section=1
            debug_log "DEBUG" "Found target section for counting: [$section_name]"
            continue
        fi
        
        # 別のセクション開始で終了
        if echo "$line" | grep -q "^\[.*\]"; then
            if [ $in_section -eq 1 ]; then
                debug_log "DEBUG" "Reached next section, stopping count"
                break
            fi
            continue
        fi
        
        # セクション内の項目をカウント
        if [ $in_section -eq 1 ]; then
            total_normal_items=$((total_normal_items+1))
        fi
    done < "${BASE_DIR}/menu.db"
    
    debug_log "DEBUG" "Total normal menu items in section [$section_name]: $total_normal_items"
    
    # セクション検索（2回目）- 項目を処理
    in_section=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        # コメントと空行をスキップ
        case "$line" in
            \#*|"") continue ;;
        esac
        
        # セクション開始をチェック
        if echo "$line" | grep -q "^\[$section_name\]"; then
            in_section=1
            debug_log "DEBUG" "Found target section for processing: [$section_name]"
            continue
        fi
        
        # 別のセクション開始で終了
        if echo "$line" | grep -q "^\[.*\]"; then
            if [ $in_section -eq 1 ]; then
                debug_log "DEBUG" "Reached next section, stopping processing"
                break
            fi
            continue
        fi
        
        # セクション内の項目を処理
        if [ $in_section -eq 1 ]; then
            # カウンターをインクリメント
            menu_count=$((menu_count+1))
            
            # 色指定の有無をチェック
            # 先頭が「色名 キー」の形式か「キー」だけか判断
            if echo "$line" | grep -q -E "^[a-z_]+[ ]"; then
                # 色指定あり: 色、キー、コマンドを分離
                local color_name=$(echo "$line" | cut -d' ' -f1)
                local key=$(echo "$line" | cut -d' ' -f2)
                local cmd=$(echo "$line" | cut -d' ' -f3-)
                
                debug_log "DEBUG" "Color specified in line: color=$color_name, key=$key, cmd=$cmd"
            else
                # 色指定なし: キーとコマンドを分離
                local key=$(echo "$line" | cut -d' ' -f1)
                local cmd=$(echo "$line" | cut -d' ' -f2-)
                
                # 自動色割り当て - 位置と総項目数を渡す
                local color_name=$(get_auto_color "$menu_count" "$total_normal_items")
                
                debug_log "DEBUG" "No color specified, auto-assigned: color=$color_name, key=$key, cmd=$cmd"
            fi
            
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
            printf "%s\n" "$(color "$color_name" "[$menu_count] $display_text")" >> "$menu_displays_file" 2>/dev/null
            
            debug_log "DEBUG" "Added menu item $menu_count: [$key] -> [$cmd] with color: $color_name"
        fi
    done < "${BASE_DIR}/menu.db"
    
    debug_log "DEBUG" "Read $menu_count regular menu items from menu.db"
    
    # 処理したメニュー項目数を返す
    echo "$menu_count"
}

# 特殊メニュー項目追加関数
add_special_menu_items() {
    local section_name="$1"
    local is_main_menu="$2"
    local menu_count="$3"
    local menu_keys_file="$4"
    local menu_displays_file="$5"
    local menu_commands_file="$6"
    local menu_colors_file="$7"
    
    debug_log "DEBUG" "Adding special menu items for section: $section_name"
    
    local special_items_count=0
    
    # メインメニューの場合は [10]と[00]を追加
    if [ "$is_main_menu" -eq 1 ]; then
        # [10] EXIT - 終了 (旧[0])
        menu_count=$((menu_count+1))
        special_items_count=$((special_items_count+1))
        echo "MENU_EXIT" >> "$menu_keys_file"
        echo "menu_exit" >> "$menu_commands_file"
        echo "white" >> "$menu_colors_file"
    
        local exit_text=$(get_message "MENU_EXIT")
        [ -z "$exit_text" ] && exit_text="終了"
        printf "%s\n" "$(color white "[10] $exit_text")" >> "$menu_displays_file"
    
        debug_log "DEBUG" "Added special EXIT item [10] to main menu"
        
        # [00] REMOVE - 削除
        menu_count=$((menu_count+1))
        special_items_count=$((special_items_count+1))
        echo "MENU_REMOVE" >> "$menu_keys_file"
        echo "remove_exit" >> "$menu_commands_file"
        echo "white_black" >> "$menu_colors_file"
    
        local remove_text=$(get_message "MENU_REMOVE")
        [ -z "$remove_text" ] && remove_text="削除"
        printf "%s\n" "$(color white_black "[00] $remove_text")" >> "$menu_displays_file"
    
        debug_log "DEBUG" "Added special REMOVE item [00] to main menu"
    else
        # サブメニューの場合は [0]と[10]を追加
        # [0] BACK - 前に戻る (旧[9])
        menu_count=$((menu_count+1))
        special_items_count=$((special_items_count+1))
        echo "MENU_BACK" >> "$menu_keys_file"

        # 履歴の階層数をカウント
        local history_count=0
        if [ -n "$MENU_HISTORY" ]; then
            history_count=$(echo "$MENU_HISTORY" | tr -cd "$MENU_HISTORY_SEPARATOR" | wc -c)
            history_count=$((history_count / 2 + 1))  # ペア数に変換
            debug_log "DEBUG" "Menu history levels: $history_count"
        fi

        # 履歴が1階層のみならメインメニューに直接戻る
        if [ $history_count -le 1 ]; then
            echo "return_menu" >> "$menu_commands_file"
            debug_log "DEBUG" "Using return_menu for single-level history"
        else
            # 2階層以上あれば前のメニューに戻る
            echo "go_back_menu" >> "$menu_commands_file"
            debug_log "DEBUG" "Using go_back_menu for multi-level history ($history_count levels)"
        fi

        echo "white" >> "$menu_colors_file"

        local back_text=$(get_message "MENU_BACK")
        [ -z "$back_text" ] && back_text="戻る"
        printf "%s\n" "$(color white "[0] $back_text")" >> "$menu_displays_file"

        debug_log "DEBUG" "Added special BACK item [0] to sub-menu"
    
        # [10] EXIT - 終了 (旧[0])
        menu_count=$((menu_count+1))
        special_items_count=$((special_items_count+1))
        echo "MENU_EXIT" >> "$menu_keys_file"
        echo "menu_exit" >> "$menu_commands_file"
        echo "white" >> "$menu_colors_file"
    
        local exit_text=$(get_message "MENU_EXIT")
        [ -z "$exit_text" ] && exit_text="終了"
        printf "%s\n" "$(color white "[10] $exit_text")" >> "$menu_displays_file"
    
        debug_log "DEBUG" "Added special EXIT item [10] to sub-menu"
    fi
    
    debug_log "DEBUG" "Added $special_items_count special menu items"
    
    # 特殊メニュー項目数と合計メニュー項目数を返す
    echo "$special_items_count $menu_count"
}

# ユーザー選択処理関数
handle_user_selection() {
    local section_name="$1"
    local is_main_menu="$2"
    local menu_count="$3"
    local menu_choices="$4"
    local menu_keys_file="$5"
    local menu_displays_file="$6"
    local menu_commands_file="$7"
    local menu_colors_file="$8"
    local main_menu="$9"
    
    debug_log "DEBUG" "Handling user selection for section: $section_name"
    
    # 選択プロンプト表示（特殊項目を含む）
    if [ $is_main_menu -eq 1 ]; then
        # メインメニュー用のプロンプト（10, 00を含む）
        local selection_prompt=$(get_message "CONFIG_MAIN_SELECT_PROMPT")
    
        # メッセージキーが見つからない場合は独自に構築
        if [ -z "$selection_prompt" ] || [ "$selection_prompt" = "CONFIG_MAIN_SELECT_PROMPT" ]; then
            local base_prompt=$(get_message "CONFIG_SELECT_PROMPT")
            # ベースプロンプトから括弧部分を抽出して修正
            local base_text=$(echo "$base_prompt" | sed 's/(.*)//g')
            selection_prompt="${base_text}(1-$menu_choices, 10=終了, 00=削除): "
            debug_log "DEBUG" "Created custom main menu prompt: $selection_prompt"
        fi
    else
        # サブメニュー用のプロンプト（0, 10を含む）
        local selection_prompt=$(get_message "CONFIG_SUB_SELECT_PROMPT")
    
        # メッセージキーが見つからない場合は独自に構築
        if [ -z "$selection_prompt" ] || [ "$selection_prompt" = "CONFIG_SUB_SELECT_PROMPT" ]; then
            local base_prompt=$(get_message "CONFIG_SELECT_PROMPT")
            # ベースプロンプトから括弧部分を抽出して修正
            local base_text=$(echo "$base_prompt" | sed 's/(.*)//g')
            selection_prompt="${base_text}(1-$menu_choices, 0=戻る, 10=終了): "
            debug_log "DEBUG" "Created custom sub-menu prompt: $selection_prompt"
        fi
    fi
    
    # {0}をメニュー数で置換
    selection_prompt=$(echo "$selection_prompt" | sed "s/{0}/$menu_choices/g")
    printf "%s" "$(color white "$selection_prompt")"
    
    # ユーザー入力
    local choice=""
    if ! read -r choice; then
        # エラーハンドラーを呼び出し
        handle_menu_error "read_input" "$section_name" "" "$main_menu" "MSG_ERROR_OCCURRED"
        return 1
    fi
    
    # 入力の正規化（利用可能な場合のみ）
    if command -v normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    debug_log "DEBUG" "User input: $choice"
    
    # 特殊入力の処理
    local real_choice=""
    case "$choice" in
        "10")
            # [10]は常にEXIT (旧[0])
            if [ $is_main_menu -eq 1 ]; then
                real_choice=$((menu_count - 2 + 1)) # メインメニューの場合
            else
                real_choice=$menu_count # サブメニューの場合
            fi
            debug_log "DEBUG" "Special input [10] mapped to item: $real_choice"
            ;;
        "00")
            # [00]は常にREMOVE（メインメニューのみ）
            if [ $is_main_menu -eq 1 ]; then
                real_choice=$menu_count
                debug_log "DEBUG" "Special input [00] mapped to item: $real_choice"
            else
                printf "\n%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_NUMBER")")"
                sleep 2
                return 0 # リトライが必要
            fi
            ;;
        "0")
            # [0]は常にRETURN（サブメニューのみ）(旧[9])
            if [ $is_main_menu -eq 0 ]; then
                real_choice=$((menu_count - 1))
                debug_log "DEBUG" "Special input [0] mapped to item: $real_choice"
            else
                printf "\n%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_NUMBER")")"
                sleep 2
                return 0 # リトライが必要
            fi
            ;;
        *)
            # 数値チェック
            if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
                printf "\n%s\n" "$(color red "$(get_message "CONFIG_ERROR_NOT_NUMBER")")"
                sleep 2
                return 0 # リトライが必要
            fi
        
            # 選択範囲チェック（通常メニュー項目のみ）
            if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_choices" ]; then
                local error_msg=$(get_message "CONFIG_ERROR_INVALID_NUMBER")
                error_msg=$(echo "$error_msg" | sed "s/PLACEHOLDER/$menu_choices/g")
                printf "\n%s\n" "$(color red "$error_msg")"
                sleep 2
                return 0 # リトライが必要
            fi
        
            # 通常入力の場合はそのままの値を使用
            real_choice=$choice
            ;;
    esac
    
    # 選択されたキーとコマンドを取得
    local selected_key=""
    local selected_cmd=""
    local selected_color=""
    
    selected_key=$(sed -n "${real_choice}p" "$menu_keys_file" 2>/dev/null)
    selected_cmd=$(sed -n "${real_choice}p" "$menu_commands_file" 2>/dev/null)
    selected_color=$(sed -n "${real_choice}p" "$menu_colors_file" 2>/dev/null)
    
    if [ -z "$selected_key" ] || [ -z "$selected_cmd" ]; then
        # エラーハンドラーを呼び出し
        handle_menu_error "invalid_selection" "$section_name" "" "$main_menu" "MSG_ERROR_OCCURRED"
        return 1
    fi
    
    debug_log "DEBUG" "Selected key: $selected_key"
    debug_log "DEBUG" "Selected color: $selected_color"
    debug_log "DEBUG" "Executing command: $selected_cmd"
    
    # コマンド実行前の表示
    local selected_text=$(get_message "$selected_key")
    [ -z "$selected_text" ] && selected_text="$selected_key"
    
    # プレースホルダー置換による表示
    local download_msg=$(get_message "CONFIG_DOWNLOADING" "0=$selected_text")
    
    printf "\n%s\n\n" "$(color "$selected_color" "$download_msg")"
    sleep 1
    
    # コマンド実行 - セレクターコマンドの特別処理
    if echo "$selected_cmd" | grep -q "^selector "; then
        # セレクターコマンドの場合、サブメニューへ移動
        local next_menu=$(echo "$selected_cmd" | cut -d' ' -f2)
        debug_log "DEBUG" "Detected submenu navigation: $next_menu"
        
        # 一時ファイル削除
        rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
        
        # 次のメニューを表示（表示テキストを親メニュー情報として渡す）
        selector "$next_menu" "$selected_text" 0
        return $?
    else
        # 通常コマンドの実行
        eval "$selected_cmd"
        local cmd_status=$?
        
        debug_log "DEBUG" "Command execution finished with status: $cmd_status"
        
        # コマンド実行エラー時、前のメニューに戻る
        if [ $cmd_status -ne 0 ]; then
            # エラーハンドラーを呼び出し
            handle_menu_error "command_failed" "$section_name" "" "$main_menu" "MSG_ERROR_OCCURRED"
            return 1
        fi
    fi
    
    return $cmd_status
}

# メインのセレクター関数（リファクタリング版）
selector() {
    local section_name="$1"        # 表示するセクション名
    local parent_display_text="$2" # 親メニューの表示テキスト（パンくず用）
    local skip_history="$3"        # 履歴に追加しない場合は1
    
    # セクション名が指定されていない場合はメインメニューを使用
    if [ -z "$section_name" ]; then
        section_name="${MAIN_MENU:-openwrt-config}"
    fi
    
    debug_log "DEBUG" "Starting menu selector with section: $section_name"
    
    # 現在のセクションを記録
    CURRENT_MENU="$section_name"
    
    # 履歴管理（skipが指定されていない場合のみ）
    if [ "$skip_history" != "1" ]; then
        # メインメニューに戻る場合は履歴をクリア
        if [ "$section_name" = "$MAIN_MENU" ]; then
            MENU_HISTORY=""
            debug_log "DEBUG" "Cleared menu history for main menu"
        else
            # 親メニューの表示テキストが指定されている場合のみ履歴に追加
            if [ -n "$parent_display_text" ]; then
                push_menu_history "$section_name" "$parent_display_text"
            fi
        fi
    fi
    
    # メインメニュー名を取得
    local main_menu="${MAIN_MENU}"
    
    # メインメニューかどうかの判定
    local is_main_menu=0
    if [ "$section_name" = "$main_menu" ]; then
        is_main_menu=1
        debug_log "DEBUG" "Current section is the main menu"
    else
        debug_log "DEBUG" "Current section is a sub-menu"
    fi
    
    # キャッシュファイルの初期化
    local menu_keys_file="${CACHE_DIR}/menu_keys.tmp"
    local menu_displays_file="${CACHE_DIR}/menu_displays.tmp"
    local menu_commands_file="${CACHE_DIR}/menu_commands.tmp"
    local menu_colors_file="${CACHE_DIR}/menu_colors.tmp"
    
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    touch "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    
    # メニュー項目の処理
    local menu_count=$(process_menu_items "$section_name" "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file")
    
    # 特殊メニュー項目の追加
    local special_result=$(add_special_menu_items "$section_name" "$is_main_menu" "$menu_count" "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file")
    local special_items_count=$(echo "$special_result" | cut -d' ' -f1)
    menu_count=$(echo "$special_result" | cut -d' ' -f2)
    
    debug_log "DEBUG" "Total menu items after adding special items: $menu_count"
    
    # メニュー項目の確認
    if [ $menu_count -eq 0 ]; then
        # エラーハンドラーを呼び出し
        handle_menu_error "no_items" "$section_name" "" "$main_menu" ""
        return $?
    fi
    
    # タイトルヘッダーを表示
    local menu_title_template=$(get_message "MENU_TITLE")
    local menu_title=$(echo "$menu_title_template" | sed "s/{0}/$section_name/g")
    
    # パンくずリストを表示
    display_breadcrumbs
    
    # メニュー項目を表示
    if [ -s "$menu_displays_file" ]; then
        cat "$menu_displays_file"
    else
        # エラーハンドラーを呼び出し
        handle_menu_error "empty_display" "$section_name" "" "$main_menu" "MSG_ERROR_OCCURRED"
        return $?
    fi
    
    printf "\n"
    
    # 通常メニュー項目数（特殊項目を除く）
    local menu_choices=$((menu_count - special_items_count))
    
    # ユーザー選択の処理（リトライのためのループ）
    while true; do
        # ユーザー選択処理を呼び出し
        handle_user_selection "$section_name" "$is_main_menu" "$menu_count" "$menu_choices" \
            "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file" "$main_menu"
        
        local selection_status=$?
        
        # リターンコードが0の場合はリトライ
        if [ $selection_status -ne 0 ]; then
            break
        fi
        
        # リトライの場合は現在のメニューを再表示
        selector "$section_name" "" 1
        return $?
    done
    
    # 一時ファイル削除
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    
    return $selection_status
}

push_menu_history() {
    local menu_name="$1"    # メニューセクション名
    local display_text="$2" # 表示テキスト
    
    debug_log "DEBUG" "Adding to menu history: $menu_name ($display_text)"
    
    # メニュー名がINIヘッダーとして存在するか確認
    if ! grep -q "^\[$menu_name\]" "${BASE_DIR}/menu.db"; then
        debug_log "DEBUG" "Warning: Menu section [$menu_name] not found in menu.db"
    fi
    
    # 履歴の最大深度を設定（安全対策）
    local max_history_depth=10
    local current_depth=0
    
    if [ -n "$MENU_HISTORY" ]; then
        current_depth=$(echo "$MENU_HISTORY" | tr -cd "$MENU_HISTORY_SEPARATOR" | wc -c)
        current_depth=$((current_depth / 2 + 1))
    fi
    
    # 履歴の追加
    if [ -z "$MENU_HISTORY" ]; then
        # 履歴が空の場合は直接設定
        MENU_HISTORY="${menu_name}${MENU_HISTORY_SEPARATOR}${display_text}"
    else
        # 既存の履歴の後に追加
        MENU_HISTORY="${menu_name}${MENU_HISTORY_SEPARATOR}${display_text}${MENU_HISTORY_SEPARATOR}${MENU_HISTORY}"
        
        # 最大深度を超える場合は古い履歴を切り詰める
        if [ "$current_depth" -ge "$max_history_depth" ]; then
            debug_log "DEBUG" "History depth exceeded maximum ($max_history_depth), truncating oldest entries"
            # 最大深度内に収まるように履歴を切り詰める処理
            local items_to_keep=$((max_history_depth * 2))
            MENU_HISTORY=$(echo "$MENU_HISTORY" | cut -d"$MENU_HISTORY_SEPARATOR" -f1-"$items_to_keep")
        fi
    fi
    
    debug_log "DEBUG" "Current menu history: $MENU_HISTORY"
}

get_menu_history_item() {
    local history="$1"
    local position="$2"
    local type="$3"
    
    # 履歴が空なら空文字を返す
    if [ -z "$history" ]; then
        echo ""
        return
    fi
    
    # 一時ファイルを使わず直接処理する方法
    local i=0
    local result=""
    local target_pos=0
    
    # タイプに応じて位置を調整
    if [ "$type" = "menu" ]; then
        target_pos=$((position * 2))
    elif [ "$type" = "text" ]; then
        target_pos=$((position * 2 + 1))
    fi
    
    IFS="$MENU_HISTORY_SEPARATOR"
    for item in $history; do
        if [ $i -eq $target_pos ]; then
            result="$item"
            break
        fi
        i=$((i + 1))
    done
    unset IFS
    
    echo "$result"
}

# メインメニューに戻る関数
return_menu() {
    debug_log "DEBUG" "Returning to main menu"
    
    # 履歴をクリア
    MENU_HISTORY=""
    
    # メインメニューを表示
    selector "${MAIN_MENU}" "" 1
    return $?
}

go_back_menu() {
    debug_log "DEBUG" "Processing go_back_menu function"
    
    # 履歴が空の場合はメインメニューへ
    if [ -z "$MENU_HISTORY" ]; then
        debug_log "DEBUG" "History is empty, returning to main menu"
        return_menu
        return $?
    fi
    
    # 履歴の構造: menu1:text1:menu2:text2:...
    # 最初のメニュー名（ヘッダー名）を取得
    local current_menu=$(echo "$MENU_HISTORY" | cut -d"$MENU_HISTORY_SEPARATOR" -f1)
    debug_log "DEBUG" "Current menu: $current_menu"
    
    # 履歴の区切り記号をカウント
    local sep_count=$(echo "$MENU_HISTORY" | tr -cd "$MENU_HISTORY_SEPARATOR" | wc -c)
    
    # 履歴が1階層分しかない場合はメインメニューへ
    if [ "$sep_count" -le 1 ]; then
        debug_log "DEBUG" "Only one level in history, returning to main menu"
        MENU_HISTORY=""
        return_menu
        return $?
    fi
    
    # 最初のペア（現在のメニュー+テキスト）を削除して前のメニューを取得
    local new_history=$(echo "$MENU_HISTORY" | cut -d"$MENU_HISTORY_SEPARATOR" -f3-)
    
    # 新しい履歴の先頭がメニュー名
    local prev_menu=$(echo "$new_history" | cut -d"$MENU_HISTORY_SEPARATOR" -f1)
    
    debug_log "DEBUG" "Previous menu key: $prev_menu"
    debug_log "DEBUG" "New history: $new_history"
    
    # メニュー名（INIヘッダー）の有効性を確認
    if [ -n "$prev_menu" ] && grep -q "^\[$prev_menu\]" "${BASE_DIR}/menu.db"; then
        # 履歴を更新
        MENU_HISTORY="$new_history"
        debug_log "DEBUG" "Valid previous menu found: $prev_menu"
        
        # 前のメニューへ移動
        selector "$prev_menu" "" 1
        return $?
    fi
    
    # 有効な前のメニューが見つからない場合はメインメニューへ
    debug_log "DEBUG" "No valid previous menu found, returning to main menu"
    MENU_HISTORY=""
    return_menu
    return $?
}

# 削除確認関数
remove_exit() {
    debug_log "DEBUG" "Starting remove_exit confirmation process"
    
    # 確認プロンプト表示
    if confirm "CONFIG_CONFIRM_DELETE"; then
        debug_log "DEBUG" "User confirmed deletion, proceeding with removal"
        printf "%s\n" "$(color green "$(get_message "CONFIG_DELETE_CONFIRMED")")"
        [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH"
        [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
        exit 0
    else
        debug_log "DEBUG" "User canceled deletion, returning to menu"
        printf "%s\n" "$(color white "$(get_message "CONFIG_DELETE_CANCELED")")"
        
        # メインメニューに戻る処理
        local main_menu="${MAIN_MENU}"
        debug_log "DEBUG" "Returning to main menu after cancellation"
        sleep 1
        
        # メインメニューを表示
        selector "$main_menu" "" 1
        return $?
    fi
}

# 標準終了関数
menu_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_EXIT_CONFIRMED")")"
    sleep 1
    exit 0
}
