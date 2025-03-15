#!/bin/sh

SCRIPT_VERSION="2025.03.15-00-00"

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

# ダウンロード用データ - ループ問題修正
menu_download() {
        download "internet-config.sh" "chmod" "run"
        download "system-config.sh" "chmod" "run"
        download "package-install.sh" "chmod" "run"
        download "adblocker-dns.sh" "chmod" "run"
        download "accesspoint-setup.sh" "chmod" "run"
        download "other-utilities.sh" "chmod" "run"
        echo "exit" "" ""
        echo "remove" "" ""
}

# セレクター関数（メニュー表示と選択処理）
selector() {
    local menu_title="$1"
    local menu_count=0
    local choice=""
    local i=0
    local script_name=$(basename "$0" .sh)
    
    # カラーリスト
    local color_list="red blue green magenta cyan yellow white white_black"
    
    # 一時ファイル
    local temp_file="${CACHE_DIR}/menu_selector_output.tmp"
    local filtered_file="${CACHE_DIR}/menu_filtered.tmp"
    
    # ディレクトリ存在確認
    [ ! -d "${CACHE_DIR}" ] && mkdir -p "${CACHE_DIR}"
    
    # メニューアイテムをキャプチャ
    menyu_selector > "$temp_file" 2>/dev/null
    
    # デバッグ行をフィルタリング
    grep -v "^DEBUG:" "$temp_file" > "$filtered_file" 2>/dev/null || cp "$temp_file" "$filtered_file"
    menu_count=$(wc -l < "$filtered_file")
    
    echo "DEBUG: Menu items count: $menu_count" >&2
    
    # ヘッダー表示
    local header_text="$(get_message "CONFIG_HEADER")"
    header_text=$(echo "$header_text" | sed "s/{0}/$script_name/g" 2>/dev/null || echo "$header_text")
    header_text=$(echo "$header_text" | sed "s/{1}/$SCRIPT_VERSION/g" 2>/dev/null || echo "$header_text")
    printf "%s\n" "$header_text"
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    if [ -n "$menu_title" ]; then
        local title_text="$(get_message "CONFIG_SECTION_TITLE")"
        title_text=$(echo "$title_text" | sed "s/{0}/$menu_title/g" 2>/dev/null || echo "$title_text")
        printf "%s\n" "$title_text"
    fi
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    # 番号付きでメニュー項目を表示
    i=1
    while IFS= read -r line; do
        # デバッグ行をスキップ
        if echo "$line" | grep -q "^DEBUG:"; then
            continue
        fi
        
        # 色を決定
        local current_color=""
        current_color=$(echo "$color_list" | cut -d' ' -f$i 2>/dev/null)
        [ -z "$current_color" ] && current_color="white"
        
        # 番号と項目を表示
        printf " %s %s\n" "$(color "$current_color" "[${i}]:")" "$line"
        i=$((i + 1))
    done < "$filtered_file"
    
    # 一時ファイル削除
    rm -f "$temp_file" "$filtered_file"
    
    # 選択プロンプト
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    local prompt_text="$(get_message "CONFIG_SELECT_PROMPT")"
    prompt_text=$(echo "$prompt_text" | sed "s/{0}/$menu_count/g" 2>/dev/null || echo "$prompt_text")
    printf "%s " "$prompt_text"
    
    # ユーザー入力を読み取り
    read -r raw_choice
    echo "DEBUG: User input: $raw_choice" >&2
    
    # 入力値を正規化
    choice=$(normalize_input "$raw_choice")
    echo "DEBUG: Normalized choice: $choice" >&2
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        echo "DEBUG: Invalid input (not a number)" >&2
        printf "%s\n" "$(get_message "CONFIG_ERROR_NOT_NUMBER")"
        sleep 2
        return 0
    fi
    
    # 範囲チェック
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        echo "DEBUG: Input out of range: $choice (valid: 1-$menu_count)" >&2
        local error_text="$(get_message "CONFIG_ERROR_INVALID_NUMBER")"
        error_text=$(echo "$error_text" | sed "s/{0}/$menu_count/g" 2>/dev/null || echo "$error_text")
        printf "%s\n" "$error_text"
        sleep 2
        return 0
    fi
    
    # 選択アクションを実行
    echo "DEBUG: Processing menu selection: $choice" >&2
    execute_menu_action "$choice"
    
    return $?
}

# メニューアクション実行関数
execute_menu_action() {
    local choice="$1"
    local temp_file="${CACHE_DIR}/menu_commands.tmp"
    local command_line=""
    
    echo "DEBUG: Executing action for choice: $choice" >&2
    
    # メニューコマンドを取得
    menu_download > "$temp_file" 2>/dev/null
    
    # 行数取得と範囲チェック
    local lines=$(wc -l < "$temp_file")
    echo "DEBUG: Menu has $lines commands" >&2
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$lines" ]; then
        echo "DEBUG: Choice out of range: $choice (valid: 1-$lines)" >&2
        printf "%s\n" "$(get_message "CONFIG_ERROR_INVALID_NUMBER")"
        rm -f "$temp_file"
        return 0
    fi
    
    # コマンド行を取得
    command_line=$(sed -n "${choice}p" "$temp_file")
    rm -f "$temp_file"
    
    echo "DEBUG: Selected command: $command_line" >&2
    
    # 空コマンドチェック
    if [ -z "$command_line" ];then
        echo "DEBUG: Empty command selected" >&2
        return 0
    fi
    
    # 特殊コマンド処理: exit
    if [ "$command_line" = "exit" ] || [ "$command_line" = "exit  " ]; then
        printf "%s\n" "$(get_message "CONFIG_EXIT_CONFIRMED")"
        sleep 1
        return 255
    fi
    
    # 特殊コマンド処理: remove
    if [ "$command_line" = "remove" ] || [ "$command_line" = "remove  " ]; then
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
    echo "DEBUG: Executing command: $command_line" >&2
    ( eval "$command_line" )
    local status=$?
    echo "DEBUG: Command execution finished with status: $status" >&2
    
    return $status
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
