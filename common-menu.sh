#!/bin/sh

COMMON_VERSION="2025.03.18-01-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-02-21
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
### 📌 AI Assistance Request: POSIX-Compliant Debugging Guide
### 
### When debugging or fixing errors in this POSIX shell script:
### 
### 1️⃣ Create a minimal reproducible test case (avoid bash features)
### 2️⃣ Test with ash/dash explicitly: dash ./test.sh
### 3️⃣ Use portable debugging methods: echo, printf, or set -x
### 4️⃣ Validate fixes against all POSIX compliance guidelines
### 5️⃣ Ensure the solution works in resource-constrained OpenWrt
### 
### ⚠️ IMPORTANT:
### - Avoid suggesting bash-specific solutions
### - Always test fixes with ash/dash before implementation
### - Prefer simple solutions over complex ones
### - Do not modify production code without test verification
### 
### 🛠️ Keep debugging simple, focused, and POSIX-compliant!
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

# メニューセレクター関数 - POSIX準拠版
selector() {
    # グローバル変数でメニュー階層を管理
    local previous_menu="$CURRENT_MENU"
    CURRENT_MENU="$1"
    
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
    debug_log "DEBUG" "Previous menu was: $previous_menu"
    
    # メインメニュー名を取得
    local main_menu="${MAIN_MENU:-openwrt-config}"
    
    # メニューDBの存在確認
    if [ ! -f "${BASE_DIR}/menu.db" ]; then
        debug_log "ERROR" "Menu database not found at ${BASE_DIR}/menu.db"
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
        return 1
    fi
    
    debug_log "DEBUG" "Menu DB path: ${BASE_DIR}/menu.db"
    
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
        printf "%s\n" "$(color red "No menu items found in section [$section_name]")"
        
        # エラー時に前のメニューに戻る
        if [ "$section_name" = "$main_menu" ]; then
            # メインメニューの場合は再表示（ループ）
            debug_log "INFO" "Main menu error, reloading main menu"
            selector "$main_menu"
            return $?
        else
            # サブメニューの場合は前のメニューに戻る
            debug_log "INFO" "Returning to previous menu: $previous_menu"
            selector "$previous_menu"
            return $?
        fi
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
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
        
        # エラー時に前のメニューに戻る
        if [ "$section_name" = "$main_menu" ]; then
            debug_log "INFO" "Main menu error, reloading main menu"
            selector "$main_menu"
            return $?
        else
            debug_log "INFO" "Returning to previous menu: $previous_menu"
            selector "$previous_menu"
            return $?
        fi
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
        
        # エラー時に前のメニューに戻る
        if [ "$section_name" = "$main_menu" ]; then
            debug_log "INFO" "Main menu error, reloading main menu"
            selector "$main_menu"
            return $?
        else
            debug_log "INFO" "Returning to previous menu: $previous_menu"
            selector "$previous_menu"
            return $?
        fi
    fi
    
    # 入力の正規化（利用可能な場合のみ）
    if command -v normalize_input >/dev/null 2>&1; then
        choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    fi
    debug_log "DEBUG" "User input: $choice"
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        printf "\n%s\n" "$(color red "$(get_message "CONFIG_ERROR_NOT_NUMBER")")"
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
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
        
        # エラー時に前のメニューに戻る
        if [ "$section_name" = "$main_menu" ]; then
            debug_log "INFO" "Main menu error, reloading main menu"
            selector "$main_menu"
            return $?
        else
            debug_log "INFO" "Returning to previous menu: $previous_menu"
            selector "$previous_menu"
            return $?
        fi
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
    
    # コマンド実行エラー時、前のメニューに戻る
    if [ $cmd_status -ne 0 ]; then
        debug_log "ERROR" "Command failed with status $cmd_status"
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
        sleep 2
        
        if [ "$section_name" = "$main_menu" ]; then
            debug_log "INFO" "Main menu command error, reloading main menu"
            selector "$main_menu"
            return $?
        else 
            debug_log "INFO" "Command error, returning to previous menu: $previous_menu"
            selector "$previous_menu"
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
    local main_menu="${MAIN_MENU:-openwrt-config}"
    
    debug_log "DEBUG" "Returning to main menu: $main_menu"
    printf "%s\n" "$(color blue "$(get_message "CONFIG_RETURN_TO_MAIN")")"
    sleep 1
    
    # メインメニューに戻る
    selector "$main_menu"
    return $?
}

# 削除確認関数
remove_exit() {
    debug_log "DEBUG" "Starting remove_exit using confirm function"
    
    # 確認関数を使用
    if confirm "CONFIG_CONFIRM_DELETE"; then
        debug_log "DEBUG" "User confirmed deletion, proceeding with removal"
        printf "%s\n" "$(color green "$(get_message "CONFIG_DELETE_CONFIRMED")")"
        [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH"
        [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
        exit 0
    else
        debug_log "DEBUG" "User canceled deletion, returning to menu"
        printf "%s\n" "$(color blue "$(get_message "CONFIG_DELETE_CANCELED")")"
        return 0
    fi
}

# 標準終了関数
menu_exit() {
    printf "%s\n" "$(color green "$(get_message "CONFIG_EXIT_CONFIRMED")")"
    sleep 1
    exit 0
}
