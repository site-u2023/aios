#!/bin/sh

SCRIPT_VERSION="2025.03.17-09-12"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-17
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

# デフォルトの設定値
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
DEBUG_MODE="${DEBUG_MODE:-false}"

# メニューセレクタースクリプト
# メニューDBからメニュー項目を読み込み、ユーザーに選択を促し、選択したコマンドを実行する

# メニューセレクター関数
selector() {
    local section_name="${1:-openwrt-config}"
    local menu_keys_file="${CACHE_DIR}/menu_keys.tmp"
    local menu_displays_file="${CACHE_DIR}/menu_displays.tmp"
    local menu_commands_file="${CACHE_DIR}/menu_commands.tmp"
    local colors="red blue green magenta cyan yellow white white_black"
    local menu_count=0
    
    debug_log "DEBUG" "Starting menu selector with section: $section_name"
    
    # メニューDBの存在確認
    if [ ! -f "${BASE_DIR}/menu.db" ]; then
        debug_log "ERROR" "Menu database not found at ${BASE_DIR}/menu.db"
        printf "%s\n" "$(color red "メニューデータベースが見つかりません")"
        return 1
    fi
    
    # キャッシュディレクトリの存在確認
    if [ ! -d "$CACHE_DIR" ]; then
        debug_log "DEBUG" "Creating cache directory: $CACHE_DIR"
        mkdir -p "$CACHE_DIR" || {
            debug_log "ERROR" "Failed to create cache directory: $CACHE_DIR"
            printf "%s\n" "$(color red "キャッシュディレクトリを作成できません")"
            return 1
        }
    }
    
    # キャッシュファイルの初期化
    : > "$menu_keys_file"
    : > "$menu_displays_file"
    : > "$menu_commands_file"
    
    # セクション検索
    debug_log "DEBUG" "Searching for section [$section_name] in menu.db"
    local in_section=0
    
    # ファイルを1行ずつ処理
    while IFS= read -r line; do
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
            # キーとコマンドを分離して保存
            local key=$(echo "$line" | cut -d' ' -f1)
            local cmd=$(echo "$line" | cut -d' ' -f2-)
            
            # 各ファイルに情報を保存
            echo "$key" >> "$menu_keys_file"
            
            # メニュー項目番号とメッセージキー
            menu_count=$((menu_count+1))
            
            # 色の選択
            local color_index=$(( (menu_count % 8) + 1 ))
            local color_name=$(echo "$colors" | cut -d' ' -f$color_index)
            [ -z "$color_name" ] && color_name="white"
            
            # 表示テキストとコマンドを保存
            printf "%s\n" "$(color "$color_name" "$menu_count: $(get_message "$key")")" >> "$menu_displays_file"
            printf "%s\n" "$cmd" >> "$menu_commands_file"
            
            debug_log "DEBUG" "Added menu item $menu_count: [$key] -> [$cmd]"
        fi
    done < "${BASE_DIR}/menu.db"
    
    # メニュー項目の確認
    if [ $menu_count -eq 0 ]; then
        debug_log "ERROR" "No menu items found in section [$section_name]"
        printf "%s\n" "$(color red "セクション[$section_name]にメニュー項目がありません")"
        return 1
    fi
    
    # メニューヘッダー表示
    printf "\n%s\n" "$(color white_black "===============================")"
    printf "%s\n" "$(color white_black "          メインメニュー         ")"
    printf "%s\n" "$(color white_black "===============================")"
    printf "\n"
    
    # メニュー表示
    cat "$menu_displays_file"
    printf "\n"
    
    # 選択プロンプト
    printf "%s " "$(color green "数字を入力して選択してください (1-$menu_count):")"
    
    # ユーザー入力
    local choice=""
    read -r choice
    choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    debug_log "DEBUG" "User input: $choice"
    
    # 数値チェック
    if ! echo "$choice" | grep -q '^[0-9][0-9]*$'; then
        printf "\n%s\n" "$(color red "有効な数字を入力してください")"
        sleep 2
        return 0
    fi
    
    # 選択範囲チェック
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        printf "\n%s\n" "$(color red "選択は1～${menu_count}の範囲で入力してください")"
        sleep 2
        return 0
    fi
    
    # 選択されたキーとコマンドを取得
    local selected_key=$(sed -n "${choice}p" "$menu_keys_file")
    local selected_cmd=$(sed -n "${choice}p" "$menu_commands_file")
    
    debug_log "DEBUG" "Selected key: $selected_key"
    debug_log "DEBUG" "Executing command: $selected_cmd"
    
    printf "\n%s\n\n" "$(color blue "$(get_message "$selected_key")を実行します...")"
    sleep 1
    
    # コマンド実行
    eval "$selected_cmd"
    local cmd_status=$?
    
    debug_log "DEBUG" "Command execution finished with status: $cmd_status"
    
    # 一時ファイル削除
    rm -f "$menu_keys_file" "$menu_displays_file" "$menu_commands_file"
    
    # コマンド終了後に少し待機
    if [ $cmd_status -ne 0 ]; then
        printf "\n%s\n" "$(color yellow "コマンドは終了しましたが、エラーが発生した可能性があります")"
        sleep 2
    fi
    
    return $cmd_status
}

# 終了関数
menu_exit() {
    printf "%s\n" "$(color green "スクリプトを終了します")"
    sleep 1
    exit 0
}

# 削除終了関数
remove_exit() {
    printf "%s\n" "$(color yellow "警告: スクリプトと関連ディレクトリを削除しようとしています")"
    
    printf "%s " "$(color cyan "本当に削除してよろしいですか？ (y/n):")"
    local choice=""
    read -r choice
    choice=$(normalize_input "$choice" 2>/dev/null || echo "$choice")
    
    case "$choice" in
        [Yy]|[Yy][Ee][Ss])
            printf "%s\n" "$(color green "スクリプトと関連ディレクトリを削除します")"
            [ -f "$0" ] && rm -f "$0"
            [ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"
            exit 0
            ;;
        *)
            printf "%s\n" "$(color blue "削除をキャンセルしました")"
            return 0
            ;;
    esac
}

# メインループ関数
main_menu_loop() {
    local section_name="${1:-openwrt-config}"
    
    while true; do
        selector "$section_name"
        
        # Ctrlキー操作などによる異常終了を防ぐ
        if [ $? -eq 130 ]; then
            printf "\n%s\n" "$(color yellow "メニューに戻ります...")"
            sleep 1
        fi
    done
}

# メイン関数
main() {
    # デバッグモードでmenu.dbの内容を確認
    if [ "$DEBUG_MODE" = "true" ]; then
        if [ -f "${BASE_DIR}/menu.db" ]; then
            debug_log "DEBUG" "Menu DB exists at ${BASE_DIR}/menu.db"
            debug_log "DEBUG" "First 10 lines of menu.db:"
            head -n 10 "${BASE_DIR}/menu.db" | while IFS= read -r line; do
                debug_log "DEBUG" "menu.db> $line"
            done
        else
            debug_log "ERROR" "Menu DB not found at ${BASE_DIR}/menu.db"
        fi
    fi
    
    # 引数があれば指定セクションを表示
    if [ $# -gt 0 ]; then
        main_menu_loop "$1"
        return $?
    fi
    
    # 引数がなければデフォルトセクションを表示
    main_menu_loop "openwrt-config"
}

# スクリプト自体が直接実行された場合のみ、mainを実行
if [ "$(basename "$0")" = "menu-selector.sh" ]; then
    main "$@"
fi
