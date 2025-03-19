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
# 形式: "menu_name:display_text:menu_name:display_text:..."
MENU_HISTORY=""

# メニュー階層の現在位置（カレントメニュー）
CURRENT_MENU=""

# メニュー履歴にエントリを追加する関数
push_menu_history() {
    local menu_name="$1"    # メニュー名/セクション名
    local display_text="$2" # 表示テキスト（メッセージ）
    
    debug_log "DEBUG" "Adding to menu history: $menu_name ($display_text)"
    
    # 履歴が空の場合は直接設定、そうでなければ先頭に追加
    if [ -z "$MENU_HISTORY" ]; then
        MENU_HISTORY="${menu_name}:${display_text}"
    else
        MENU_HISTORY="${menu_name}:${display_text}:${MENU_HISTORY}"
    fi
    
    debug_log "DEBUG" "Current menu history: $MENU_HISTORY"
}

# メニュー履歴から最新のエントリを取得して履歴から削除する関数
pop_menu_history() {
    debug_log "DEBUG" "Popping from menu history"
    
    # 履歴が空の場合、メインメニューを返す
    if [ -z "$MENU_HISTORY" ]; then
        debug_log "DEBUG" "History empty, returning main menu"
        echo "$MAIN_MENU"
        return
    fi
    
    # 最初の区切り文字までを取得（フィールド1）
    local first_entry=$(echo "$MENU_HISTORY" | cut -d':' -f1)
    
    # 残りの履歴を更新
    if echo "$MENU_HISTORY" | grep -q ':'; then
        # 最初の2つのエントリ（メニュー名とその表示テキスト）を削除
        MENU_HISTORY=$(echo "$MENU_HISTORY" | cut -d':' -f3-)
    else
        # 唯一のエントリだった場合は履歴をクリア
        MENU_HISTORY=""
    fi
    
    debug_log "DEBUG" "Popped entry: $first_entry, Remaining history: $MENU_HISTORY"
    
    # メニュー名を返す
    echo "$first_entry"
}

# パンくずリスト表示関数（revに依存しないバージョン）
display_breadcrumbs() {
    debug_log "DEBUG" "Displaying breadcrumbs from history: $MENU_HISTORY"
    
    # 履歴が空の場合は何も表示しない
    if [ -z "$MENU_HISTORY" ]; then
        debug_log "DEBUG" "No history to display breadcrumbs"
        return
    fi
    
    # メインメニューのパンくず（常に最初に表示）
    local main_menu_text=$(get_message "MAIN_MENU_NAME")
    [ -z "$main_menu_text" ] && main_menu_text="メインメニュー" # デフォルト値
    
    # パンくずの初期値はメインメニュー
    local breadcrumb="$(color cyan "$main_menu_text")"
    local separator=" > "
    
    # 履歴文字列をIFSで分割して処理
    local old_ifs="$IFS"
    IFS=':'
    
    # 履歴文字列を一時ファイルに保存
    local temp_history_file="${CACHE_DIR}/history.tmp"
    echo "$MENU_HISTORY" > "$temp_history_file"
    
    # 履歴を項目ごとに分割して処理
    local item_count=0
    local items=""
    
    # 履歴アイテムをカウント
    item_count=$(awk -F: '{print NF}' "$temp_history_file")
    debug_log "DEBUG" "History has $item_count items"
    
    # 履歴項目を逆順で処理するため、リストを構築
    local i=1
    local pairs=""
    
    while [ "$i" -le "$item_count" ]; do
        # 奇数インデックスはメニュー名、偶数インデックスは表示テキスト
        if [ "$((i % 2))" -eq "1" ] && [ "$i" -lt "$item_count" ]; then
            local menu_name=$(cut -d':' -f"$i" "$temp_history_file")
            local display_text=$(cut -d':' -f"$((i+1))" "$temp_history_file")
            
            # メインメニューはスキップ（既に表示済み）
            if [ "$menu_name" != "$MAIN_MENU" ]; then
                # 表示テキストがある場合のみ追加
                if [ -n "$display_text" ]; then
                    # パンくずに追加
                    breadcrumb="${breadcrumb}${separator}$(color cyan "$display_text")"
                    debug_log "DEBUG" "Added breadcrumb: $display_text"
                fi
            fi
        fi
        i=$((i+2)) # ペアでスキップ
    done
    
    # 一時ファイルを削除
    rm -f "$temp_history_file"
    
    # 元のIFSを復元
    IFS="$old_ifs"
    
    # パンくずリストを表示
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

# 色の自動割り当て関数
get_auto_color() {
    local position="$1"
    local total_items="$2"
    
    debug_log "DEBUG" "Auto-assigning color for position $position of $total_items items"
    
    # 色の自動割り当てロジック
    case "$total_items" in
        6)
            case "$position" in
                1) echo "magenta" ;;
                2) echo "blue" ;;
                3) echo "cyan" ;;
                4) echo "green" ;;
                5) echo "yellow" ;;
                6) echo "red" ;;
                *) echo "white" ;; # フォールバック
            esac
            ;;
        5)
            case "$position" in
                1) echo "blue" ;;
                2) echo "cyan" ;;
                3) echo "green" ;;
                4) echo "yellow" ;;
                5) echo "red" ;;
                *) echo "white" ;; # フォールバック
            esac
            ;;
        4)
            case "$position" in
                1) echo "cyan" ;;
                2) echo "green" ;;
                3) echo "yellow" ;;
                4) echo "red" ;;
                *) echo "white" ;; # フォールバック
            esac
            ;;
        3)
            case "$position" in
                1) echo "green" ;;
                2) echo "yellow" ;;
                3) echo "red" ;;
                *) echo "white" ;; # フォールバック
            esac
            ;;
        2)
            case "$position" in
                1) echo "green" ;;
                2) echo "red" ;;
                *) echo "white" ;; # フォールバック
            esac
            ;;
        1)
            echo "green"
            ;;
        *)
            echo "white" # フォールバック色
            ;;
    esac
}

# メニューセレクター関数
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
    local menu_count=0
    
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    touch "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    
    # まず、セクション内の通常項目数をカウント（特殊項目を除く）
    local total_normal_items=0
    local in_section=0
    
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
    
    # 特殊メニュー項目の追加
    local special_items_count=0
    
    # メインメニューの場合は [0]と[00]を追加
    if [ $is_main_menu -eq 1 ]; then
        # [0] EXIT - 終了
        menu_count=$((menu_count+1))
        special_items_count=$((special_items_count+1))
        echo "MENU_EXIT" >> "$menu_keys_file"
        echo "menu_exit" >> "$menu_commands_file"
        echo "white" >> "$menu_colors_file"
        
        local exit_text=$(get_message "MENU_EXIT")
        [ -z "$exit_text" ] && exit_text="終了"
        printf "%s\n" "$(color white "[0] $exit_text")" >> "$menu_displays_file"
        
        debug_log "DEBUG" "Added special EXIT item [0] to main menu"
        
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
        # サブメニューの場合は [9]と[0]を追加
        # [9] RETURN - 戻る
        menu_count=$((menu_count+1))
        special_items_count=$((special_items_count+1))
        echo "MENU_RETURN" >> "$menu_keys_file"
        echo "return_menu" >> "$menu_commands_file"
        echo "white" >> "$menu_colors_file"
        
        local return_text=$(get_message "MENU_RETURN")
        [ -z "$return_text" ] && return_text="戻る"
        printf "%s\n" "$(color white "[9] $return_text")" >> "$menu_displays_file"
        
        debug_log "DEBUG" "Added special RETURN item [9] to sub-menu"
        
        # [0] EXIT - 終了
        menu_count=$((menu_count+1))
        special_items_count=$((special_items_count+1))
        echo "MENU_EXIT" >> "$menu_keys_file"
        echo "menu_exit" >> "$menu_commands_file"
        echo "white" >> "$menu_colors_file"
        
        local exit_text=$(get_message "MENU_EXIT")
        [ -z "$exit_text" ] && exit_text="終了"
        printf "%s\n" "$(color white "[0] $exit_text")" >> "$menu_displays_file"
        
        debug_log "DEBUG" "Added special EXIT item [0] to sub-menu"
    fi
    
    debug_log "DEBUG" "Added $special_items_count special menu items"
    debug_log "DEBUG" "Total menu items: $menu_count"
    
    # メニュー項目の確認
    if [ $menu_count -eq 0 ]; then
        # エラーハンドラーを呼び出し
        handle_menu_error "no_items" "$section_name" "" "$main_menu" ""
        return $?
    fi
    
    # タイトルヘッダーを表示
    local menu_title_template=$(get_message "MENU_TITLE")
    local menu_title=$(echo "$menu_title_template" | sed "s/{0}/$section_name/g")

    printf "%s\n" "----------------------------------------------"
    printf "%s\n" "$(color white "$menu_title")"
    printf "%s\n" "----------------------------------------------"
    
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
    
    # 選択プロンプト表示
    local selection_prompt=$(get_message "CONFIG_SELECT_PROMPT")
    # {0}をメニュー数で置換（特殊項目は含めない）
    local menu_choices=$((menu_count - special_items_count))
    selection_prompt=$(echo "$selection_prompt" | sed "s/{0}/$menu_choices/g")
    printf "%s" "$(color blue "$selection_prompt")"
    
    # ユーザー入力
    local choice=""
    if ! read -r choice; then
        # エラーハンドラーを呼び出し
        handle_menu_error "read_input" "$section_name" "" "$main_menu" "MSG_ERROR_OCCURRED"
        return $?
    fi
    
    # 入力の正規化（利用可能な場合のみ）
    if command -v normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    debug_log "DEBUG" "User input: $choice"
    
    # 特殊入力の処理
    local real_choice=""
    case "$choice" in
        "0")
            # [0]は常にEXIT
            if [ $is_main_menu -eq 1 ]; then
                real_choice=$((menu_count - 2 + 1)) # メインメニューの場合
            else
                real_choice=$menu_count # サブメニューの場合
            fi
            debug_log "DEBUG" "Special input [0] mapped to item: $real_choice"
            ;;
        "00")
            # [00]は常にREMOVE（メインメニューのみ）
            if [ $is_main_menu -eq 1 ]; then
                real_choice=$menu_count
                debug_log "DEBUG" "Special input [00] mapped to item: $real_choice"
            else
                printf "\n%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_NUMBER")")"
                sleep 2
                selector "$section_name" "" 1
                return $?
            fi
            ;;
        "9")
            # [9]は常にRETURN（サブメニューのみ）
            if [ $is_main_menu -eq 0 ]; then
                real_choice=$((menu_count - 1))
                debug_log "DEBUG" "Special input [9] mapped to item: $real_choice"
            else
                printf "\n%s\n" "$(color red "$(get_message "CONFIG_ERROR_INVALID_NUMBER")")"
                sleep 2
                selector "$section_name" "" 1
                return $?
            fi
            ;;
        *)
            # 数値チェック
            if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
                printf "\n%s\n" "$(color red "$(get_message "CONFIG_ERROR_NOT_NUMBER")")"
                sleep 2
                # 同じメニューを再表示
                selector "$section_name" "" 1
                return $?
            fi
            
            # 選択範囲チェック（通常メニュー項目のみ）
            if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_choices" ]; then
                local error_msg=$(get_message "CONFIG_ERROR_INVALID_NUMBER")
                error_msg=$(echo "$error_msg" | sed "s/PLACEHOLDER/$menu_choices/g")
                printf "\n%s\n" "$(color red "$error_msg")"
                sleep 2
                # 同じメニューを再表示
                selector "$section_name" "" 1
                return $?
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
        return $?
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
            return $?
        fi
    fi
    
    # 一時ファイル削除
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file" "$menu_colors_file"
    
    return $cmd_status
}

# メインメニューに戻る関数
return_menu() {
    # グローバル変数MAIN_MENUからメインメニュー名を取得
    local main_menu="${MAIN_MENU}"
    
    debug_log "DEBUG" "Returning to main menu: $main_menu"
    
    # 履歴をクリア（メインメニューに直接戻るため）
    MENU_HISTORY=""
    debug_log "DEBUG" "Cleared menu history for main menu return"
    
    sleep 1
    
    # メインメニューに戻る
    selector "$main_menu" "" 0
    return $?
}

# 前のメニューに戻る関数
go_back_menu() {
    debug_log "DEBUG" "Going back to previous menu"
    
    # 履歴から前のメニューを取得
    local prev_menu=$(pop_menu_history)
    
    # 履歴が空の場合はメインメニューに戻る
    if [ -z "$prev_menu" ]; then
        debug_log "DEBUG" "No previous menu found, returning to main menu"
        return_menu
        return $?
    fi
    
    debug_log "DEBUG" "Going back to menu: $prev_menu"
    sleep 1
    
    # 前のメニューを表示
    selector "$prev_menu" "" 1
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
        printf "%s\n" "$(color blue "$(get_message "CONFIG_DELETE_CANCELED")")"
        
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
