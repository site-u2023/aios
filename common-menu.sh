#!/bin/sh

COMMON_VERSION="2025.04.15-00-00"

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
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
DEBUG_MODE="${DEBUG_MODE:-false}"
BIN_PATH=$(readlink -f "$0")
BIN_DIR="$(dirname "$BIN_PATH")"
BIN_FILE="$(basename "$BIN_PATH")"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# メニュー履歴を追跡するためのグローバル変数
MENU_HISTORY=""
CURRENT_MENU=""
MENU_HISTORY_SEPARATOR=":"

# 現在選択されているメニュー情報（グローバル変数）
SELECTED_MENU_KEY=""
SELECTED_MENU_COLOR=""

# メインメニューのセクション名を定義
unset MAIN_MENU
MAIN_MENU="${MAIN_MENU:-MAIN_MENU_NAME}"

# メニュー履歴にエントリを追加する関数
pop_menu_history() {
    debug_log "DEBUG" "Popping from menu history"

    # 履歴が空か確認
    if [ -z "$MENU_HISTORY" ]; then
        debug_log "DEBUG" "History is already empty, nothing to pop"
        echo ""
        return
    fi

    # 履歴のペア数をカウント (メニュー名:色)
    local pair_count=1
    if echo "$MENU_HISTORY" | grep -q "$MENU_HISTORY_SEPARATOR"; then
        local separator_count=$(echo "$MENU_HISTORY" | tr -cd "$MENU_HISTORY_SEPARATOR" | wc -c)
        pair_count=$(( (separator_count + 1) / 2 ))
    fi
    debug_log "DEBUG" "Current history pairs: $pair_count"

    if [ "$pair_count" -le 1 ]; then
        # ペアが1つ以下の場合は全履歴をクリアし、最初のメニュー名（最後のエントリ）を返す
        local last_menu=$(echo "$MENU_HISTORY" | cut -d"$MENU_HISTORY_SEPARATOR" -f1)
        MENU_HISTORY=""
        debug_log "DEBUG" "Popped last pair from history, now empty"
        echo "$last_menu"
    else
        # ペアが2つ以上の場合
        # 最後から2番目のメニュー名を取得（awk を使用）
        local last_menu=$(echo "$MENU_HISTORY" | awk -F"$MENU_HISTORY_SEPARATOR" '{print $(NF-1)}')

        # 最後のペア（2項目）を削除（awk を使用）
        MENU_HISTORY=$(echo "$MENU_HISTORY" | awk -v sep="$MENU_HISTORY_SEPARATOR" -F"$MENU_HISTORY_SEPARATOR" '{
            result = ""
            # NF-2 個のフィールドまでを再結合
            for (i = 1; i <= NF - 2; i++) {
                result = result (i > 1 ? sep : "") $i
            }
            print result
        }')

        debug_log "DEBUG" "Popped last pair, remaining history: $MENU_HISTORY"
        echo "$last_menu"
    fi
}

debug_breadcrumbs() {
    local history="$MENU_HISTORY"
    debug_log "DEBUG" "Raw history data: $history"
    
    local i=0
    IFS="$MENU_HISTORY_SEPARATOR"
    for item in $history; do
        debug_log "DEBUG" "History item $i: $item"
        i=$((i + 1))
    done
    unset IFS
}

# パンくずリストの表示関数（完全修正版）
display_breadcrumbs() {
    debug_log "DEBUG" "Building breadcrumb navigation with proper order and colors"
    
    # メインメニューの情報を取得
    local main_menu_key="MAIN_MENU_NAME"
    local main_menu_text=$(get_message "$main_menu_key")
    
    # メインメニューのデフォルト色
    local main_color="white_gray"
    
    # パンくずの区切り文字（表示用）
    local separator=" > "
    
    # パンくずの初期値
    local breadcrumb="$(color $main_color "$main_menu_text")"
    
    # 履歴が空ならメインメニューのみ表示
    if [ -z "$MENU_HISTORY" ]; then
        debug_log "DEBUG" "No menu history, showing main menu only"
        printf "%s\n" "$breadcrumb"
        return
    fi
    
    # 履歴形式: MENU_V&MIG:blue:MENU_INTERNET:magenta
    # これを逆順に処理して正しい階層順にする
    
    # セパレータで分割して配列風に扱う
    local history_items=""
    IFS="$MENU_HISTORY_SEPARATOR"
    for item in $MENU_HISTORY; do
        history_items="$item $history_items"
    done
    unset IFS
    
    # 逆順になった項目から、メニューと色のペアを再構築
    debug_log "DEBUG" "Reversed history items: $history_items"
    
    local menu_items=""
    local color_items=""
    local i=0
    
    # 空白区切りのリストから要素を取り出す
    for item in $history_items; do
        if [ $((i % 2)) -eq 0 ]; then
            # 偶数インデックスは色（逆順なので）
            color_items="$color_items $item"
        else
            # 奇数インデックスはメニュー（逆順なので）
            menu_items="$menu_items $item"
        fi
        i=$((i + 1))
    done
    
    debug_log "DEBUG" "Extracted and properly ordered: menus=[$menu_items], colors=[$color_items]"
    
    # メニューと色の数を確認
    local menu_count=0
    for menu in $menu_items; do
        menu_count=$((menu_count + 1))
    done
    
    local color_count=0
    for color in $color_items; do
        color_count=$((color_count + 1))
    done
    
    debug_log "DEBUG" "Menu count: $menu_count, Color count: $color_count"
    
    # メニュー項目を順に処理してパンくずを構築
    i=0
    for menu in $menu_items; do
        # メニューキーからテキストを取得
        local display_text=$(get_message "$menu")
        [ -z "$display_text" ] && display_text="$menu"
        
        # 対応する色を取得
        local menu_color="white"  # デフォルト色
        
        # 色リストからi番目の色を取得
        local j=0
        for color in $color_items; do
            if [ $j -eq $i ]; then
                menu_color="$color"
                debug_log "DEBUG" "Using color $menu_color for menu item $menu"
                break
            fi
            j=$((j + 1))
        done
        
        # 色情報がない、またはデフォルト値の場合、自動割り当て
        if [ -z "$menu_color" ] || [ "$menu_color" = "white" ]; then
            menu_color=$(get_auto_color "$((i+1))" "$menu_count")
            debug_log "DEBUG" "Auto-assigned color for menu level $i: $menu_color"
        fi
        
        # パンくずに追加
        breadcrumb="${breadcrumb}${separator}$(color $menu_color "$display_text")"
        i=$((i + 1))
    done
    
    # パンくずリストを出力（末尾に空行1つ）
    printf "%s\n" "$breadcrumb"
    
    debug_log "DEBUG" "Displayed breadcrumb for submenu with single newline"
}

# Error handling function - Logs errors ONLY, always returns 0, uses DEBUG level
handle_menu_error() {
    local error_type="$1"    # Error type (e.g., "command_failed", "no_items")
    local section_name="$2"  # Menu section where the error occurred
    # local previous_menu="$3" # Unused argument
    # local main_menu="$4"     # Unused argument in this simplified version
    # local error_msg_key="$5" # Argument kept for compatibility

    # Always log as DEBUG, regardless of error type
    debug_log "DEBUG" "Handling error type '$error_type' in section [$section_name]."

    # Return 0 to indicate the handler itself completed successfully
    # and should not disrupt the calling flow (e.g., selector loop)
    return 0
}

# Handle user selection - Removed the unwanted generic failure message display
handle_user_selection() {
    # Correct argument list matching the call from selector
    local section_name="$1"        # Current menu section name
    local is_main_menu="$2"        # 1 if main menu, 0 otherwise
    local menu_count="$3"          # Total menu items (including special)
    local num_normal_choices="$4"  # Number of normal choices (1 to N)
    local menu_keys_file="$5"      # Temp file with menu keys
    local menu_displays_file="$6"  # Temp file with display strings (unused here)
    local menu_commands_file="$7"  # Temp file with commands
    local menu_colors_file="$8"    # Temp file with colors
    local main_menu="$9"           # Main menu section name

    # --- Display Prompt ---
    local selection_prompt=""
    if [ "$is_main_menu" -eq 1 ]; then
        selection_prompt=$(get_message "CONFIG_MAIN_SELECT_PROMPT")
        selection_prompt=$(echo "$selection_prompt" | sed "s/{0}/$num_normal_choices/g")
    else
        selection_prompt=$(get_message "CONFIG_SUB_SELECT_PROMPT")
        selection_prompt=$(echo "$selection_prompt" | sed "s/{0}/$num_normal_choices/g")
    fi
    printf "%s" "$(color white "$selection_prompt")" # Display prompt before read

    # --- Read User Input with Failure Check ---
    local choice=""
    if ! read -r choice; then
        debug_log "ERROR" "Failed to read user input in section [$section_name]. Returning 1 to stop loop."
        return 1
    fi
    if command -v normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    debug_log "DEBUG" "User input: '$choice'"

    # --- Input Validation (Numeric Check) ---
    case "$choice" in
        ''|*[!0-9]*)
            printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_NOT_NUMBER")")"
            debug_log "DEBUG" "Invalid input (not a number): '$choice' in section [$section_name]. Returning 0 to retry."
            return 0
            ;;
    esac

    # --- Handle Special Selections (0, 10, 00) ---
    if [ "$choice" -eq 0 ]; then
        if [ "$is_main_menu" -eq 1 ]; then
             printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_NUMBER")")"
             debug_log "DEBUG" "'0' selected in main menu [$section_name]. Invalid. Returning 0 to retry."
             return 0
        fi
        debug_log "DEBUG" "User selected 0 (Go Back) in section [$section_name]."
        go_back_menu
        local go_back_status=$?
        debug_log "DEBUG" "go_back_menu returned status: $go_back_status"
        return $go_back_status
    fi
    if [ "$choice" -eq 10 ]; then
        debug_log "DEBUG" "User selected 10 (Exit) in section [$section_name]."
        menu_exit
        return 0
    fi
    if [ "$choice" -eq 00 ]; then
        if [ "$is_main_menu" -eq 0 ]; then
             printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_NUMBER")")"
             debug_log "DEBUG" "'00' selected in submenu [$section_name]. Invalid. Returning 0 to retry."
             return 0
        fi
        debug_log "DEBUG" "User selected 00 (Exit & Delete) in section [$section_name]."
        remove_exit
        local remove_status=$?
        debug_log "DEBUG" "remove_exit returned status: $remove_status"
        return $remove_status
    fi

    # --- Handle Normal Selections (1 to N) ---
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$num_normal_choices" ]; then
         printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_NUMBER")")"
         debug_log "DEBUG" "Selection '$choice' out of range (1-$num_normal_choices) in section [$section_name]. Returning 0 to retry."
         return 0
    fi

    # --- Get Action Details from Temp Files using the choice number ---
    local action=$(awk "NR==$choice" "$menu_commands_file")
    local selected_key=$(awk "NR==$choice" "$menu_keys_file")
    local selected_color=$(awk "NR==$choice" "$menu_colors_file")
    local type="command"
    if echo "$action" | grep -q "^selector "; then
        type="menu"
        action=$(echo "$action" | sed 's/^selector //')
    fi

    if [ -z "$action" ] || [ -z "$selected_key" ] || [ -z "$selected_color" ]; then
        debug_log "ERROR" "Failed to retrieve action details for choice '$choice' from temp files in section [$section_name]."
        # No generic message here either
        return 0
    fi

    debug_log "DEBUG" "Choice '$choice' mapped to: Key='$selected_key', Color='$selected_color', Action='$action', Type='$type'"

    # --- Execute Action ---
    if [ "$type" = "menu" ]; then
        debug_log "DEBUG" "User selected submenu '$action' from section [$section_name]."
        push_menu_history "$selected_key" "$selected_color"
        selector "$action"
        local submenu_status=$?
        debug_log "DEBUG" "Submenu selector '$action' returned status: $submenu_status"
        return $submenu_status
    elif [ "$type" = "command" ]; then
        debug_log "DEBUG" "Executing command: $action from section [$section_name]"
        local processed_action=""
        if ! processed_action=$(process_menu_yn "$action"); then
             debug_log "DEBUG" "Command cancelled by user via menu_yn confirmation."
             return 0
        fi
        action="$processed_action"

        (eval "$action")
        local cmd_status=$?

        if [ $cmd_status -eq 0 ]; then
            debug_log "DEBUG" "Command '$action' succeeded in section [$section_name]."
            debug_log "DEBUG" "Returning 0 from handle_user_selection (command success case) for section [$section_name]."
            return 0
        else
            debug_log "DEBUG" "Command '$action' failed with status $cmd_status in section [$section_name]."
            # *** REMOVED the printf line for MSG_COMMAND_FAILED_RETRY ***
            debug_log "DEBUG" "Returning 0 from handle_user_selection (command failed case) for section [$section_name]."
            return 0
        fi
    else
        debug_log "ERROR" "Internal error: Unknown action type detected for choice '$choice' in section [$section_name]."
        # No generic message here either
        return 0
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
    local colors_2="magenta green"
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
            if echo "$line" | grep -q -E "^[a-z_]+[ ]"; then
                local color_name=$(echo "$line" | cut -d' ' -f1)
                local key=$(echo "$line" | cut -d' ' -f2)
                local cmd=$(echo "$line" | cut -d' ' -f3-)
                debug_log "DEBUG" "Color specified in line: color=$color_name, key=$key, cmd=$cmd"
            else
                local key=$(echo "$line" | cut -d' ' -f1)
                local cmd=$(echo "$line" | cut -d' ' -f2-)
                local color_name=$(get_auto_color "$menu_count" "$total_normal_items")
                debug_log "DEBUG" "No color specified, auto-assigned: color=$color_name, key=$key, cmd=$cmd"
            fi

            # 各ファイルに情報を保存
            echo "$key" >> "$menu_keys_file"
            echo "$cmd" >> "$menu_commands_file"
            echo "$color_name" >> "$menu_colors_file"

            # メッセージキーの変換処理
            local display_text=""
            local current_lang=""
            if [ -f "${CACHE_DIR}/message.ch" ]; then
                current_lang=$(cat "${CACHE_DIR}/message.ch")
            fi
            debug_log "DEBUG" "Using language code for menu display: $current_lang"
            debug_log "DEBUG" "Direct search for message key: $key"

            for msg_file in "${BASE_DIR}"/message_*.db; do
                if [ -f "$msg_file" ]; then
                    local msg_value=$(grep -F "$current_lang|$key=" "$msg_file" 2>/dev/null | cut -d'=' -f2-)
                    if [ -n "$msg_value" ]; then
                        display_text="$msg_value"
                        debug_log "DEBUG" "Found message in file: $msg_file"
                        break
                    fi
                fi
            done

            # 変換が見つからない場合はキーをそのまま使用
            if [ -z "$display_text" ]; then
                display_text="$key"
                debug_log "DEBUG" "No message found for key: $key, using key as display text"
            fi

            # ★ 修正点: 表示テキストを normalize_message で正規化する (存在確認なし)
            local normalized_display_text=$(normalize_message "$display_text" "$current_lang")
            debug_log "DEBUG" "Normalized display text: $normalized_display_text"

            # 表示テキストを保存（[数字] 形式） - 正規化後のテキストを使用
            printf "%s\n" "$(color "$color_name" "[${menu_count}] ${normalized_display_text}")" >> "$menu_displays_file" 2>/dev/null

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
        echo "white_underline" >> "$menu_colors_file"
    
        local remove_text=$(get_message "MENU_REMOVE")
        [ -z "$remove_text" ] && remove_text="削除"
        printf "%s\n" "$(color white_underline "[00] $remove_text")" >> "$menu_displays_file"
    
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
            if echo "$MENU_HISTORY" | grep -q "$MENU_HISTORY_SEPARATOR"; then
                history_count=$(($(echo "$MENU_HISTORY" | tr -cd "$MENU_HISTORY_SEPARATOR" | wc -c) + 1))
            else
                history_count=1
            fi
            debug_log "DEBUG" "Menu history levels: $history_count"
        fi
        
        echo "go_back_menu" >> "$menu_commands_file"
        debug_log "DEBUG" "Using go_back_menu for navigation with $history_count history levels"

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

# menu_ynオプションを処理する関数
process_menu_yn() {
    local cmd_str="$1"
    
    debug_log "DEBUG" "Processing menu_yn option if present"
    
    # menu_ynオプションがない場合はそのまま返す
    if ! echo "$cmd_str" | grep -q "menu_yn"; then
        debug_log "DEBUG" "No menu_yn option found, returning original command"
        echo "$cmd_str"
        return 0
    fi
    
    debug_log "DEBUG" "Found menu_yn option in command, requesting confirmation"
    
    # 既存のconfirm関数を使用して確認
    if ! confirm "MSG_CONFIRM_INSTALL"; then
        debug_log "DEBUG" "User declined confirmation"
        printf "%s\n" "$(color yellow "$(get_message "MSG_ACTION_CANCELLED")")"
        return 1
    fi
    
    # 確認OKの場合、コマンド文字列からmenu_ynオプションを削除
    local cleaned_cmd=$(echo "$cmd_str" | sed 's/menu_yn//g')
    debug_log "DEBUG" "User confirmed, returning cleaned command: $cleaned_cmd"
    
    echo "$cleaned_cmd"
    return 0
}

# Selector function - Revised loop structure (with added/modified debug logs) - FULL VERSION
selector() {
    local section_name="$1"
    local parent_display_text="$2" # Unused, kept for compatibility
    local skip_history="$3"        # 1 if history update should be skipped

    section_name="${section_name:-$MAIN_MENU}"
    debug_log "DEBUG" "Entering selector for section: [$section_name]"

    local main_menu="${MAIN_MENU}"

    # --- Main loop for the current menu section ---
    while true; do
        # --- Prepare and display menu at the start of each loop iteration ---
        printf "\n"
        CURRENT_MENU="$section_name"

        # History management (only if skip_history is not 1)
        if [ "$skip_history" != "1" ]; then
            if [ "$section_name" = "$main_menu" ]; then
                MENU_HISTORY="" # Clear history when entering main menu
                debug_log "DEBUG" "Cleared menu history for main menu"
            fi
            # Note: Actual history push (with color) happens in handle_user_selection on submenu selection
            debug_log "DEBUG" "Menu [$section_name] display loop. History push depends on user action."
        else
            debug_log "DEBUG" "Skipping potential history update due to skip_history=1 (likely from go_back_menu)"
            # Reset skip_history for the next iteration? No, go_back_menu needs it.
        fi
        # Set skip_history back to 0 for the next loop iteration, unless go_back_menu sets it again
        skip_history=0 # Reset for the next potential iteration

        local is_main_menu=0
        [ "$section_name" = "$main_menu" ] && is_main_menu=1

        # Initialize temporary files
        local menu_keys_file="${CACHE_DIR}/menu_keys.tmp"
        local menu_displays_file="${CACHE_DIR}/menu_displays.tmp"
        local menu_commands_file="${CACHE_DIR}/menu_commands.tmp"
        local menu_colors_file="${CACHE_DIR}/menu_colors.tmp"
        rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
        touch "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"

        # Process menu items from menu.db
        local menu_count=$(process_menu_items "$section_name" "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file")

        # Add special menu items (Back/Exit/Remove)
        local special_result=$(add_special_menu_items "$section_name" "$is_main_menu" "$menu_count" "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file")
        local special_items_count=$(echo "$special_result" | cut -d' ' -f1)
        menu_count=$(echo "$special_result" | cut -d' ' -f2) # Total count including special items

        debug_log "DEBUG" "Total items for section [$section_name]: $menu_count ($special_items_count special)"

        # Check if menu has items
        if [ $menu_count -eq 0 ]; then
            debug_log "ERROR" "No menu items found for section [$section_name]. Returning 1 from selector." # Modify log
            rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
            return 1
        fi

        # Display breadcrumbs
        display_breadcrumbs

        # Display menu items
        if [ -s "$menu_displays_file" ]; then
            cat "$menu_displays_file"
        else
            debug_log "ERROR" "Menu display file is empty for section [$section_name]. Returning 1 from selector." # Modify log
            rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
            return 1
        fi

        local menu_choices=$((menu_count - special_items_count))

        # --- Handle user input at the end of the loop iteration ---
        handle_user_selection "$section_name" "$is_main_menu" "$menu_count" "$menu_choices" \
            "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file" "$main_menu"

        local selection_status=$?
        # *** Modify/Add debug logs for status check ***
        debug_log "DEBUG" "handle_user_selection for [$section_name] returned status: $selection_status"

        # Clean up temporary files after handling selection
        rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"

        # If status is non-zero, return the status to exit this selector instance
        if [ $selection_status -ne 0 ]; then
            debug_log "DEBUG" "Selector for [$section_name] received non-zero status ($selection_status). Returning status $selection_status."
            return $selection_status
        fi

        # If status is 0, continue the loop to redisplay the current menu
        debug_log "DEBUG" "Selector for [$section_name] received zero status. Continuing loop (redisplaying menu)."
        # Implicitly continues to the next iteration

    done # End of while true loop
}

# メニュー履歴にエントリを追加する関数（完全修正版）
push_menu_history() {
    local menu_name="$1"    # メニューセクション名
    local menu_color="$2"   # 関連付ける色
    
    # 色情報が空の場合はデフォルト値を設定
    [ -z "$menu_color" ] && menu_color="white"
    
    debug_log "DEBUG" "Adding section to history with color: $menu_name ($menu_color)"
    
    # 最大深度を3に設定（メインメニュー含めると最大4階層）
    local max_history_depth=3
    
    # 重複チェック - 履歴の先頭が同じメニューなら追加しない
    if [ -n "$MENU_HISTORY" ]; then
        local first_item=$(echo "$MENU_HISTORY" | cut -d"$MENU_HISTORY_SEPARATOR" -f1)
        if [ "$first_item" = "$menu_name" ]; then
            debug_log "DEBUG" "Menu $menu_name already at top of history, skipping duplicate"
            return
        fi
    fi
    
    # 履歴の追加（セクション名と色情報のペア）
    if [ -z "$MENU_HISTORY" ]; then
        MENU_HISTORY="${menu_name}${MENU_HISTORY_SEPARATOR}${menu_color}"
    else
        MENU_HISTORY="${menu_name}${MENU_HISTORY_SEPARATOR}${menu_color}${MENU_HISTORY_SEPARATOR}${MENU_HISTORY}"
        
        # 最大深度を超える場合は切り詰め（メニューと色のペアで1階層）
        local pair_count=1
        if echo "$MENU_HISTORY" | grep -q "$MENU_HISTORY_SEPARATOR"; then
            local separator_count=$(echo "$MENU_HISTORY" | tr -cd "$MENU_HISTORY_SEPARATOR" | wc -c)
            pair_count=$(( (separator_count + 1) / 2 ))
            
            if [ $pair_count -gt $max_history_depth ]; then
                debug_log "DEBUG" "Truncating history to max depth: $max_history_depth"
                local items_to_keep=$((max_history_depth * 2 - 1))
                MENU_HISTORY=$(echo "$MENU_HISTORY" | cut -d"$MENU_HISTORY_SEPARATOR" -f1-"$items_to_keep")
            fi
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

# より効率的な履歴処理
get_previous_menu() {
  # 単一のシェルセッションで処理
  local prev=$(echo "$MENU_HISTORY" | sed -E 's/([^:]+:[^:]+:)?.*/\1/' | sed 's/:$//')
  echo "$prev" | cut -d':' -f1
}

# 階層を正しく戻る関数
go_back_menu() {
    debug_log "DEBUG" "Processing go_back_menu with extended history format"
    
    # 履歴が空の場合はメインメニューへ
    if [ -z "$MENU_HISTORY" ]; then
        debug_log "DEBUG" "History is empty, returning to main menu"
        return_menu
        return $?
    fi
    
    # 履歴に含まれるペア数を確認（メニューと色で1ペア）
    local pair_count=1
    if echo "$MENU_HISTORY" | grep -q "$MENU_HISTORY_SEPARATOR"; then
        local separator_count=$(echo "$MENU_HISTORY" | tr -cd "$MENU_HISTORY_SEPARATOR" | wc -c)
        pair_count=$(( (separator_count + 1) / 2 ))
    fi
    
    debug_log "DEBUG" "Current menu history: $MENU_HISTORY with $pair_count menu/color pairs"
    
    # 1ペアのみの場合はメインメニューへ
    if [ $pair_count -le 1 ]; then
        debug_log "DEBUG" "Only one menu/color pair in history, returning to main menu"
        MENU_HISTORY=""
        return_menu
        return $?
    fi
    
    # 現在のメニューと色を履歴から削除（最初のペア）
    # フォーマット: menu3:color3:menu2:color2:menu1:color1
    local new_history=""
    
    # 最初のペア（2項目）を削除
    if echo "$MENU_HISTORY" | grep -q "$MENU_HISTORY_SEPARATOR"; then
        new_history=$(echo "$MENU_HISTORY" | cut -d"$MENU_HISTORY_SEPARATOR" -f3-)
    else
        new_history=""
    fi
    
    # 一つ前のメニューを取得（新しい先頭項目）
    local prev_menu=""
    if [ -n "$new_history" ]; then
        prev_menu=$(echo "$new_history" | cut -d"$MENU_HISTORY_SEPARATOR" -f1)
    else
        prev_menu="$MAIN_MENU"
    fi
    
    debug_log "DEBUG" "Going back to previous menu: $prev_menu"
    
    # 前のメニューを表示
    MENU_HISTORY="$new_history"
    selector "$prev_menu" "" 1
    return $?
}

# 削除確認関数
remove_exit() {
    debug_log "DEBUG" "Starting remove_exit confirmation process"
    
    # 確認プロンプト表示
    if confirm "CONFIG_CONFIRM_DELETE"; then
        debug_log "DEBUG" "User confirmed deletion, proceeding with removal"
        printf "%s\n\n" "$(color green "$(get_message "CONFIG_DELETE_CONFIRMED")")"
        [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH"
        [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR" 
        exit 0
    else
        debug_log "DEBUG" "User canceled deletion, returning to menu"
        printf "%s\n" "$(color white "$(get_message "CONFIG_DELETE_CANCELED")")"
        
        # メインメニューに戻る処理
        local main_menu="${MAIN_MENU}"
        debug_log "DEBUG" "Returning to main menu after cancellation"
        
        # メインメニューを表示
        selector "$main_menu" "" 1
        return $?
    fi
}

# 標準終了関数
menu_exit() {
    printf "%s\n\n" "$(color green "$(get_message "CONFIG_EXIT_CONFIRMED")")"
    exit 0
}
