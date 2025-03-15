#!/bin/sh

SCRIPT_VERSION="2025.03.15-00-00"

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

# メニュー表示用データ
menyu_selector() (
printf "%s\n" "$(color red "$(get_message "MENU_INTERNET")")"
printf "%s\n" "$(color blue "$(get_message "MENU_SYSTEM")")"
printf "%s\n" "$(color green "$(get_message "MENU_PACKAGES")")"
printf "%s\n" "$(color magenta "$(get_message "MENU_ADBLOCKER")")"
printf "%s\n" "$(color cyan "$(get_message "MENU_ACCESSPOINT")")"
printf "%s\n" "$(color yellow "$(get_message "MENU_OTHERS")")"
printf "%s\n" "$(color white "$(get_message "MENU_EXIT")")"
printf "%s\n" "$(color white_black "$(get_message "MENU_REMOVE")")"
)

# ダウンロード用データ
menu_download() (
download "internet-config.sh" "chmod" "load"
download "system-config.sh" "chmod" "load"
download "package-install.sh" "chmod" "load"
download "adblocker-dns.sh" "chmod" "load"
download "accesspoint-setup.sh" "chmod" "load"
download "other-utilities.sh" "chmod" "load"
"exit" "" ""
"remove" "" ""
)

# メニューセレクター関数（メニュー表示と選択処理）
selector() {
    local menu_title="$1"
    local menu_count=0
    local choice=""
    local i=0
    local item_color=""
    local script_name=$(basename "$0" .sh)
    
    # カラーコードの配列
    local color_list="red blue green magenta cyan yellow white white_black"
    
    # メニューデータを取得して一時保存
    local menu_data=""
    local temp_file="${CACHE_DIR}/menu_selector_output.tmp"
    
    # メニューアイテムをキャプチャ
    menyu_selector > "$temp_file" 2>/dev/null
    menu_count=$(wc -l < "$temp_file")
    
    # 画面クリア処理をデバッグ変数で制御
    if [ "$DEBUG_MODE" != "true" ]; then
        clear
    fi
    
    # プレースホルダーの置換を確実に行うため、直接変数を代入
    local header_text="$(get_message "CONFIG_HEADER")"
    header_text=$(printf "%s" "$header_text" | sed "s/{0}/$script_name/g" | sed "s/{1}/$SCRIPT_VERSION/g")
    printf "%s\n" "$header_text"
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    if [ -n "$menu_title" ]; then
        local title_text="$(get_message "CONFIG_SECTION_TITLE")"
        title_text=$(printf "%s" "$title_text" | sed "s/{0}/$menu_title/g")
        printf "%s\n" "$title_text"
    fi
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # 番号付きでメニュー項目を表示
    i=1
    while IFS= read -r line; do
        # 色を決定（iに基づく）
        local current_color=$(printf "%s" "$color_list" | cut -d' ' -f$i 2>/dev/null)
        [ -z "$current_color" ] && current_color="white"
        
        # 色付きの番号と項目を表示
        printf " %s %s\n" "$(color "$current_color" "[${i}]:")" "$line"
        i=$((i + 1))
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    # 選択プロンプト
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # プレースホルダーの置換を確実に行う
    local prompt_text="$(get_message "CONFIG_SELECT_PROMPT")"
    prompt_text=$(printf "%s" "$prompt_text" | sed "s/{0}/$menu_count/g")
    printf "%s " "$prompt_text"
    
    read -r choice
    
    # 入力値を正規化
    choice=$(normalize_input "$choice")
    
    # 入力値チェック
    if ! printf "%s" "$choice" | grep -q '^[0-9]\+$'; then
        printf "%s\n" "$(get_message "CONFIG_ERROR_NOT_NUMBER")"
        sleep 2
        return 0
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        local error_text="$(get_message "CONFIG_ERROR_INVALID_NUMBER")"
        error_text=$(printf "%s" "$error_text" | sed "s/{0}/$menu_count/g")
        printf "%s\n" "$error_text"
        sleep 2
        return 0
    fi
    
    # 選択アクションの実行
    execute_menu_action "$choice"
    
    return $?
}

# 選択メニュー実行関数
execute_menu_action() {
    local choice="$1"
    local temp_file="${CACHE_DIR}/menu_download_commands.tmp"
    local command_line=""
    
    # メニューコマンドを取得
    menu_download > "$temp_file" 2>/dev/null
    command_line=$(sed -n "${choice}p" "$temp_file")
    rm -f "$temp_file"
    
    # exit処理（スクリプト終了）
    if [ "$command_line" = "\"exit\" \"\" \"\"" ]; then
        printf "%s\n" "$(get_message "CONFIG_EXIT_CONFIRMED")"
        sleep 1
        return 255
    fi
    
    # remove処理（スクリプトとディレクトリ削除）
    if [ "$command_line" = "\"remove\" \"\" \"\"" ]; then
        if confirm "$(get_message "CONFIG_CONFIRM_DELETE")"; then
            printf "%s\n" "$(get_message "CONFIG_DELETE_CONFIRMED")"
            sleep 1
            
            # スクリプト自身とBASE_DIRを削除
            [ -f "$0" ] && rm -f "$0"
            [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
            
            return 255
        else
            printf "%s\n" "$(get_message "CONFIG_DELETE_CANCELED")"
            sleep 2
            return 0
        fi
    fi
    
    # 通常コマンド実行
    eval "$command_line"
    
    return $?
}

# メイン関数
main() {
    local ret=0
        
    # メインループ
    while true; do
        selector "$(get_message "MENU_TITLE")"
        ret=$?
        
        if [ "$ret" -eq 255 ]; then
            break
        fi
    done
}

# スクリプト実行
main "$@"
