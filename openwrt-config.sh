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
menu_download() (
download "internet-config.sh" "chmod" "run"
download "system-config.sh" "chmod" "run"
download "package-install.sh" "chmod" "run"
download "adblocker-dns.sh" "chmod" "run"
download "accesspoint-setup.sh" "chmod" "run"
download "other-utilities.sh" "chmod" "run"
echo "exit" "" ""
echo "remove" "" ""
)

safe_sed_replace() {
    local text="$1"
    local pattern="$2"
    local replacement="$3"
    
    # パターンが空の場合は置換せず元の文字列を返す
    if [ -z "$pattern" ]; then
        debug_log "Empty pattern detected in sed operation. Skipping."
        echo "$text"
        return 0
    fi
    
    # 特殊文字のエスケープ
    local esc_pattern=$(echo "$pattern" | sed 's/[\/&]/\\&/g')
    local esc_replacement=$(echo "$replacement" | sed 's/[\/&]/\\&/g')
    
    # 置換実行
    echo "$text" | sed "s/$esc_pattern/$esc_replacement/g" 2>/dev/null || echo "$text"
}

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
    
    # ディレクトリ存在確認
    [ ! -d "${CACHE_DIR}" ] && mkdir -p "${CACHE_DIR}"
    
    # メニューアイテムをキャプチャ
    menyu_selector > "$temp_file" 2>/dev/null
    menu_count=$(wc -l < "$temp_file")
    
    # 画面クリア処理をデバッグ変数で制御
    if [ "$DEBUG_MODE" != "true" ]; then
        clear
    fi
    
    # プレースホルダーの置換を確実に行うため、safe_sed_replace関数を使用
    local header_text="$(get_message "CONFIG_HEADER")"
    header_text=$(safe_sed_replace "$header_text" "{0}" "$script_name")
    header_text=$(safe_sed_replace "$header_text" "{1}" "$SCRIPT_VERSION")
    printf "%s\n" "$header_text"
    
    printf "%s\n" "$(get_message "CONFIG_SEPARATOR")"
    
    if [ -n "$menu_title" ]; then
        local title_text="$(get_message "CONFIG_SECTION_TITLE")"
        title_text=$(safe_sed_replace "$title_text" "{0}" "$menu_title")
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
    prompt_text=$(safe_sed_replace "$prompt_text" "{0}" "$menu_count")
    printf "%s " "$prompt_text"
    
    read -r choice
    debug_log "User selected: $choice"
    
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
        error_text=$(safe_sed_replace "$error_text" "{0}" "$menu_count")
        printf "%s\n" "$error_text"
        sleep 2
        return 0
    fi
    
    # 選択アクションの実行
    debug_log "Processing menu selection: $choice"
    execute_menu_action "$choice"
    
    return $?
}

# 選択メニュー実行関数 - ループ対策で修正
execute_menu_action() {
    local choice="$1"
    local temp_file="${CACHE_DIR}/menu_download_commands.tmp"
    local command_line=""
    
    # ディレクトリ存在確認
    [ ! -d "${CACHE_DIR}" ] && mkdir -p "${CACHE_DIR}"
    
    # メニューコマンドを取得
    menu_download > "$temp_file" 2>/dev/null
    command_line=$(sed -n "${choice}p" "$temp_file" 2>/dev/null || echo "")
    debug_log "Selected command: $command_line"
    rm -f "$temp_file"
    
    # コマンド行が空の場合
    if [ -z "$command_line" ]; then
        debug_log "Empty command line selected"
        return 0
    fi
    
    # exit処理（スクリプト終了）
    if [ "$command_line" = "exit  " ]; then
        printf "%s\n" "$(get_message "CONFIG_EXIT_CONFIRMED")"
        sleep 1
        return 255
    fi
    
    # remove処理（スクリプトとディレクトリ削除）
    if [ "$command_line" = "remove  " ]; then
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
    
    # 通常コマンド実行（run モードでサブシェルで実行してループ防止）
    debug_log "Executing command: $command_line"
    (eval "$command_line")
    
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
