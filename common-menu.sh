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

# エラーハンドリング関数 - 一元化された処理 (エラー時、現在のメニューを再表示する修正版)
handle_menu_error() {
    local error_type="$1"    # エラータイプ (例: "command_failed")
    local section_name="$2"  # エラーが発生したメニュー名 (例: "MENU_INTERNET_DSLITE")
    # local previous_menu="$3" # 呼び出し元からの引数は使用せず
    local main_menu="$4"     # メインメニュー名 (例: "MENU_MAIN")
    local error_msg="$5"     # エラーメッセージキー (例: "MSG_ERROR_OCCURRED")

    # 1. ログレベルは DEBUG に (冗長な ERROR ログ抑制のため)
    debug_log "DEBUG" "$error_type in section [$section_name]"

    # 2. メッセージ表示条件 (MSG_ERROR_OCCURRED は表示しない)
    if [ -n "$error_msg" ] && [ "$error_msg" != "MSG_ERROR_OCCURRED" ]; then
         printf "%s\n" "$(color red "$(get_message "$error_msg")")"
    fi

    # 3. メニュー遷移ロジックの修正
    if [ "$section_name" = "$main_menu" ]; then
        # メインメニューでエラーが発生した場合は、メインメニューを再読み込み
        debug_log "DEBUG" "Main menu $error_type, reloading main menu"
        MENU_HISTORY="" # メインメニュー再読み込み時は履歴をクリア
        selector "$main_menu" "" 1
        return $?
    else
        # サブメニューでエラーが発生した場合は、**現在のメニューを再表示する**
        debug_log "DEBUG" "Error occurred in submenu, reloading current menu: $section_name"

        # ★重要★: 履歴スタックから現在の（失敗した）エントリを削除する必要があるか検討
        # selector を skip_history=1 で呼び出すため、通常は不要だが、
        # 念のため pop_menu_history を呼び出して整合性を保つ方が安全かもしれない。
        # ただし、pop_menu_history が意図しない動作をする可能性も考慮。
        # → 一旦 pop_menu_history は呼び出さずに試す。
        # local popped_menu=$(pop_menu_history)
        # debug_log "DEBUG" "Popped potentially incorrect history entry '$popped_menu' before reloading."

        # 現在のメニューを再表示 (skip_history=1 を指定して履歴の重複追加を防ぐ)
        selector "$section_name" "" 1
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
            
            # メッセージキーの変換処理の修正
            local display_text=""

            # メッセージファイルから言語設定を直接取得（キャッシュ優先）
            local current_lang=""
            if [ -f "${CACHE_DIR}/message.ch" ]; then
                current_lang=$(cat "${CACHE_DIR}/message.ch")
            fi

            debug_log "DEBUG" "Using language code for menu display: $current_lang"
            
            # メッセージファイルから直接検索（特殊文字対応）
            debug_log "DEBUG" "Direct search for message key: $key"
            
            for msg_file in "${BASE_DIR}"/message_*.db; do
                if [ -f "$msg_file" ]; then
                    # -Fオプションで特殊文字をリテラルとして扱う
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
            
            # 表示テキストを保存（[数字] 形式） - 数字と表示の間に空白を入れる
            printf "%s\n" "$(color "$color_name" "[${menu_count}] ${display_text}")" >> "$menu_displays_file" 2>/dev/null
            
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
    else
        # サブメニュー用のプロンプト（0, 10を含む）
        local selection_prompt=$(get_message "CONFIG_SUB_SELECT_PROMPT")
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
    
    # エラーメッセージを一度だけ取得して再利用
    local error_msg=$(get_message "CONFIG_ERROR_NOT_NUMBER")
    
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
                printf "%s\n" "$(color red "$error_msg")"
                return 0 # リトライが必要
            fi
            ;;
        "0")
            # [0]は常にRETURN（サブメニューのみ）(旧[9])
            if [ $is_main_menu -eq 0 ]; then
                real_choice=$((menu_count - 1))
                debug_log "DEBUG" "Special input [0] mapped to item: $real_choice"
            else
                printf "%s\n" "$(color red "$error_msg")"
                return 0 # リトライが必要
            fi
            ;;
        *)
            # 数値チェック
            if ! echo "$choice" | grep -q '^[0-9]\+$'; then
                printf "%s\n" "$(color red "$error_msg")"
                return 0 # リトライが必要
            fi
        
            # 選択範囲チェック（通常メニュー項目のみ）
            if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_choices" ]; then
                printf "%s\n" "$(color red "$error_msg")"
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

    # グローバル変数に選択された情報を保存
    SELECTED_MENU_KEY="$selected_key"
    SELECTED_MENU_COLOR="$selected_color"
    
    debug_log "DEBUG" "Selected key: $selected_key"
    debug_log "DEBUG" "Selected color: $selected_color"
    debug_log "DEBUG" "Original command: $selected_cmd"
    
    # コマンド実行 - セレクターコマンドの特別処理
    if echo "$selected_cmd" | grep -q "^selector "; then
        # セレクターコマンドの場合、サブメニューへ移動
        local next_menu=$(echo "$selected_cmd" | cut -d' ' -f2)
        debug_log "DEBUG" "Detected submenu navigation: $next_menu"
    
        # 選択した色とともにメニュー履歴に追加
        push_menu_history "$selected_key" "$selected_color"
    
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
    local parent_display_text="$2" # 未使用（後方互換性のため残す）
    local skip_history="$3"        # 履歴に追加しない場合は1
    
    # セクション名が指定されていない場合はメインメニューを使用
    section_name="${section_name:-$MAIN_MENU}"
    
    debug_log "DEBUG" "Starting menu selector with section: $section_name"

    printf "\n"
    
    # 現在のセクションを記録
    CURRENT_MENU="$section_name"

    # メインメニューに戻る場合はパンくずの色履歴をクリア
    if [ "$section_name" = "$MAIN_MENU" ] && [ "$skip_history" != "1" ]; then
        local breadcrumb_colors_file="${CACHE_DIR}/breadcrumb_colors.tmp"
        [ -f "$breadcrumb_colors_file" ] && > "$breadcrumb_colors_file"
        debug_log "DEBUG" "Reset breadcrumb colors for main menu"
    fi
    
    # 履歴管理（skipが指定されていない場合のみ）
    if [ "$skip_history" != "1" ]; then
        # メインメニューに戻る場合は履歴をクリア
        if [ "$section_name" = "$MAIN_MENU" ]; then
            MENU_HISTORY=""
            debug_log "DEBUG" "Cleared menu history for main menu"
        fi
            # セクション名を履歴に追加（色情報はhandle_user_selection内で追加）
            # ここでは色情報を追加しない - 二重登録防止のため
            debug_log "DEBUG" "Menu $section_name will be added to history when color is selected"
    else
        debug_log "DEBUG" "Skipping history update due to skip_history flag"
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
