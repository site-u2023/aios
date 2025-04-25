#!/bin/sh

SCRIPT_VERSION="2025.03.14-00-00"

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

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
DEBUG_MODE="${DEBUG_MODE:-false}"
# パス・ファイル関連
INTERPRETER="${INTERPRETER:-ash}"  # デフォルトインタープリタ
script_dir="$( cd "$(dirname "$0")" >/dev/null 2>&1 && pwd )"
script_path="${script_dir}/$(basename "$0")"
BIN_DIR="$script_dir"    # ディレクトリの絶対パス
BIN_PATH="$script_path"  # スクリプトファイルの絶対パス
BIN_FILE="$(basename "$0")" # スクリプトファイル名
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# 表示スタイル設定のデフォルト値
DISPLAY_MODE="normal"   # 表示モード (normal/fancy/box/minimal)
COLOR_ENABLED="1"       # 色表示有効/無効
BOLD_ENABLED="0"        # 太字表示有効/無効
UNDERLINE_ENABLED="0"   # 下線表示有効/無効
BOX_ENABLED="0"         # ボックス表示有効/無効

# スピナーデフォルト設定
SPINNER_DELAY="1" # デフォルトは秒単位
SPINNER_USLEEP_VALUE="1000000" # 1秒（マイクロ秒）
SPINNER_COLOR="white" # デフォルトのスピナー色
ANIMATION_ENABLED="1" # アニメーション有効/無効フラグ

# コマンドラインオプション処理関数
process_display_options() {
    debug_log "DEBUG" "Processing display options"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -d|--display)
                shift
                [ $# -gt 0 ] && DISPLAY_MODE="$1"
                debug_log "DEBUG" "Display mode set to: $DISPLAY_MODE"
                ;;
            -c|--color)
                shift
                if [ $# -gt 0 ]; then
                    case "$1" in
                        on|1|yes) COLOR_ENABLED="1" ;;
                        off|0|no) COLOR_ENABLED="0" ;;
                    esac
                    debug_log "DEBUG" "Color display set to: $COLOR_ENABLED"
                fi
                ;;
            -b|--bold)
                BOLD_ENABLED="1"
                debug_log "DEBUG" "Bold text enabled"
                ;;
            -u|--underline)
                UNDERLINE_ENABLED="1"
                debug_log "DEBUG" "Underlined text enabled"
                ;;
            --box)
                BOX_ENABLED="1"
                debug_log "DEBUG" "Box display enabled"
                ;;
            --plain)
                # すべての装飾を無効化
                COLOR_ENABLED="0"
                BOLD_ENABLED="0"
                UNDERLINE_ENABLED="0"
                BOX_ENABLED="0"
                DISPLAY_MODE="minimal"
                debug_log "DEBUG" "Plain mode enabled (all decorations disabled)"
                ;;
        esac
        shift
    done
}

# 拡張カラーコードマップ関数
color_code_map() {
    local color="$1"
    local weight="$2"  # "bold" または "normal"
    
    # 太字プレフィックス
    local bold_prefix=""
    [ "$weight" = "bold" ] && bold_prefix="1;"
    
    # 下線プレフィックス（UNDERLINE_ENABLEDが設定されている場合）
    local underline_prefix=""
    if [ "$UNDERLINE_ENABLED" = "1" ] && ! echo "$color" | grep -q "_underline"; then
        underline_prefix="4;"
    fi
    
    case "$color" in
        # 基本色（9色+黒+グレー）
        "red") printf "\033[${underline_prefix}${bold_prefix}38;5;196m" ;;
        "orange") printf "\033[${underline_prefix}${bold_prefix}38;5;208m" ;;
        "yellow") printf "\033[${underline_prefix}${bold_prefix}38;5;226m" ;;
        "green") printf "\033[${underline_prefix}${bold_prefix}38;5;46m" ;;
        "cyan") printf "\033[${underline_prefix}${bold_prefix}38;5;51m" ;;
        "blue") printf "\033[${underline_prefix}${bold_prefix}38;5;33m" ;;
        "indigo") printf "\033[${underline_prefix}${bold_prefix}38;5;57m" ;;
        "purple") printf "\033[${underline_prefix}${bold_prefix}38;5;129m" ;;
        "magenta") printf "\033[${underline_prefix}${bold_prefix}38;5;201m" ;;
        "white") printf "\033[${underline_prefix}${bold_prefix}37m" ;;  # 白色
        "black") printf "\033[${underline_prefix}${bold_prefix}30m" ;;  # 黒色
        "gray") printf "\033[${underline_prefix}${bold_prefix}38;5;240m" ;;  # グレー色追加
        
        # 下線付き
        *"_underline")
            local base_color=$(echo "$color" | sed 's/_underline//g')
            case "$base_color" in
                "red") printf "\033[4;${bold_prefix}38;5;196m" ;;
                "orange") printf "\033[4;${bold_prefix}38;5;208m" ;;
                "yellow") printf "\033[4;${bold_prefix}38;5;226m" ;;
                "green") printf "\033[4;${bold_prefix}38;5;46m" ;;
                "cyan") printf "\033[4;${bold_prefix}38;5;51m" ;;
                "blue") printf "\033[4;${bold_prefix}38;5;33m" ;;
                "indigo") printf "\033[4;${bold_prefix}38;5;57m" ;;
                "purple") printf "\033[4;${bold_prefix}38;5;129m" ;;
                "magenta") printf "\033[4;${bold_prefix}38;5;201m" ;;
                "white") printf "\033[4;${bold_prefix}37m" ;;  # 白色下線
                "black") printf "\033[4;${bold_prefix}30m" ;;  # 黒色下線
                "gray") printf "\033[4;${bold_prefix}38;5;240m" ;;  # グレー色下線追加
                *) printf "\033[4;${bold_prefix}37m" ;;  # デフォルト
            esac
            ;;
            
        # 背景色付き（black_on_white など）
        *"_on_"*)
            local fg=$(echo "$color" | cut -d'_' -f1)
            local bg=$(echo "$color" | cut -d'_' -f3)
            
            # 前景色コード
            local fg_code=""
            case "$fg" in
                "black") fg_code="30" ;;
                "red") fg_code="38;5;196" ;;
                "orange") fg_code="38;5;208" ;;
                "yellow") fg_code="38;5;226" ;;
                "green") fg_code="38;5;46" ;;
                "cyan") fg_code="38;5;51" ;;
                "blue") fg_code="38;5;33" ;;
                "indigo") fg_code="38;5;57" ;;
                "purple") fg_code="38;5;129" ;;
                "magenta") fg_code="38;5;201" ;;
                "white") fg_code="37" ;;
                "gray") fg_code="38;5;240" ;;  # グレー色追加
                *) fg_code="37" ;;  # デフォルトは白
            esac
            
            # 背景色コード
            local bg_code=""
            case "$bg" in
                "black") bg_code="40" ;;
                "red") bg_code="48;5;196" ;;
                "orange") bg_code="48;5;208" ;;
                "yellow") bg_code="48;5;226" ;;
                "green") bg_code="48;5;46" ;;
                "cyan") bg_code="48;5;51" ;;
                "blue") bg_code="48;5;33" ;;
                "indigo") bg_code="48;5;57" ;;
                "purple") bg_code="48;5;129" ;;
                "magenta") bg_code="48;5;201" ;;
                "white") bg_code="47" ;;
                "gray") bg_code="48;5;240" ;;  # グレー背景色追加
                *) bg_code="40" ;;  # デフォルトは黒
            esac
            
            printf "\033[${underline_prefix}${bold_prefix}${fg_code};${bg_code}m"
            ;;
            
        # 反転表示（white_black など）
        *"_"*)
            if echo "$color" | grep -q -v "_on_" && echo "$color" | grep -q -v "_underline"; then
                local fg=$(echo "$color" | cut -d'_' -f1)
                local bg=$(echo "$color" | cut -d'_' -f2)
                
                # fg/bgの組み合わせで反転表示
                local fg_code=""
                case "$fg" in
                    "black") fg_code="30" ;;
                    "red") fg_code="38;5;196" ;;
                    "orange") fg_code="38;5;208" ;;
                    "yellow") fg_code="38;5;226" ;;
                    "green") fg_code="38;5;46" ;;
                    "cyan") fg_code="38;5;51" ;;
                    "blue") fg_code="38;5;33" ;;
                    "indigo") fg_code="38;5;57" ;;
                    "purple") fg_code="38;5;129" ;;
                    "magenta") fg_code="38;5;201" ;;
                    "white") fg_code="37" ;;
                    "gray") fg_code="38;5;240" ;;  # グレー色追加
                    *) fg_code="37" ;;  # デフォルトは白
                esac
                
                local bg_code=""
                case "$bg" in
                    "black") bg_code="40" ;;
                    "red") bg_code="48;5;196" ;;
                    "orange") bg_code="48;5;208" ;;
                    "yellow") bg_code="48;5;226" ;;
                    "green") bg_code="48;5;46" ;;
                    "cyan") bg_code="48;5;51" ;;
                    "blue") bg_code="48;5;33" ;;
                    "indigo") bg_code="48;5;57" ;;
                    "purple") bg_code="48;5;129" ;;
                    "magenta") bg_code="48;5;201" ;;
                    "white") bg_code="47" ;;
                    "gray") bg_code="48;5;240" ;;  # グレー背景色追加
                    *) bg_code="40" ;;  # デフォルトは黒
                esac
                
                printf "\033[${underline_prefix}${bold_prefix}${fg_code};${bg_code}m"
            else
                # マッチしなかった場合はデフォルト
                printf "\033[${underline_prefix}${bold_prefix}37m"
            fi
            ;;
            
        # リセット
        "reset") printf "\033[0m" ;;
        
        # デフォルト
        *) printf "\033[${underline_prefix}${bold_prefix}37m" ;;
    esac
}

# 拡張カラー表示関数
color() {
    # 色表示が無効の場合はプレーンテキストを返す
    if [ "$COLOR_ENABLED" = "0" ]; then
        shift
        echo "$*"
        return
    fi
    
    local color_name="$1"
    local param=""
    local text=""
    
    # オプションの解析
    if [ "$2" = "-b" ]; then
        param="bold"
        shift 2
        text="$*"
    elif [ "$2" = "-u" ]; then
        param="underline"
        shift 2
        text="$*"
    else
        shift
        text="$*"
    fi
    
    # 表示モードに基づく処理
    case "$DISPLAY_MODE" in
        box)
            if [ "$BOX_ENABLED" = "1" ]; then
                display_boxed_text "$color_name" "$text" "$param"
                return
            fi
            ;;
        fancy)
            # fancyモードでは下線や太字を自動適用
            if [ "$param" != "underline" ] && [ "$UNDERLINE_ENABLED" = "1" ]; then
                color_name="${color_name}_underline"
            fi
            if [ "$param" != "bold" ]; then
                param="bold"  # fancyモードでは自動的に太字適用
            fi
            ;;
    esac
    
    # パラメータに基づいて重みを設定
    local weight="normal"
    if [ "$param" = "bold" ] || [ "$BOLD_ENABLED" = "1" ]; then
        weight="bold"
    fi
    
    # 下線パラメータの処理
    if [ "$param" = "underline" ] && ! echo "$color_name" | grep -q "_underline"; then
        color_name="${color_name}_underline"
    fi
    
    # 色コードを取得して表示
    local color_code=$(color_code_map "$color_name" "$weight")
    printf "%b%s%b" "$color_code" "$text" "$(color_code_map reset normal)"
}

# ボックス表示関数
display_boxed_text() {
    local color_name="$1"
    local text="$2"
    local param="$3"
    local width=$((${#text} + 4))
    
    # 太字判定
    local weight="normal"
    if [ "$param" = "bold" ] || [ "$BOLD_ENABLED" = "1" ]; then
        weight="bold"
    fi
    
    # 色コードを取得
    local color_code=$(color_code_map "$color_name" "$weight")
    local reset_code=$(color_code_map reset normal)
    
    # 上の罫線
    printf "%b┌" "$color_code"
    local i=1
    while [ $i -lt $((width-1)) ]; do
        printf "─"
        i=$((i + 1))
    done
    printf "┐%b\n" "$reset_code"
    
    # テキスト行
    printf "%b│ %s │%b\n" "$color_code" "$text" "$reset_code"
    
    # 下の罫線
    printf "%b└" "$color_code"
    i=1
    while [ $i -lt $((width-1)) ]; do
        printf "─"
        i=$((i + 1))
    done
    printf "┘%b\n" "$reset_code"
}

# 装飾メニューヘッダー表示関数
fancy_header() {
    local title="$1"
    local color_name="${2:-blue}"
    
    case "$DISPLAY_MODE" in
        box)
            if [ "$BOX_ENABLED" = "1" ]; then
                display_boxed_text "$color_name" "$title" "bold"
                return
            fi
            ;;
        fancy)
            printf "\n%s\n" "$(color "$color_name" -b "$title")"
            printf "%s\n\n" "$(color "$color_name" "$(repeat_char "=" ${#title})")"
            return
            ;;
        minimal)
            printf "\n%s\n\n" "$(color "$color_name" "$title")"
            return
            ;;
        *)
            # 通常表示
            printf "\n%s\n" "$(color "$color_name" -b "$title")"
            printf "%s\n\n" "$(color "$color_name" "$(repeat_char "-" ${#title})")"
            ;;
    esac
}

# 文字繰り返し関数
repeat_char() {
    local char="$1"
    local count="$2"
    local result=""
    local i=0
    
    while [ $i -lt $count ]; do
        result="${result}${char}"
        i=$((i + 1))
    done
    
    echo "$result"
}

# スピナー開始関数
start_spinner() {
    local message="$1"
    local spinner_color="${2:-$SPINNER_COLOR}"
    local anim_type="${3:-figure}" 
    
    # グローバル変数を設定
    SPINNER_MESSAGE="$message"
    SPINNER_TYPE="$anim_type"
    SPINNER_COLOR="$spinner_color"
    
    if [ "$ANIMATION_ENABLED" -eq "0" ]; then
        debug_log "DEBUG: Animation disabled, showing static message"
        return
    fi

    if command -v usleep >/dev/null 2>&1; then
        SPINNER_USLEEP_VALUE="300000"  # 300000マイクロ秒 = 0.3秒
        SPINNER_DELAY="300000"         # アニメーションディレイ値
        debug_log "DEBUG: Using fast animation mode (0.3s) with usleep"
    else
        SPINNER_DELAY="1"              # アニメーションディレイ値（秒）
        debug_log "DEBUG: Using standard animation mode (1s)"
    fi

    # カーソル非表示
    printf "\033[?25l"

    # アニメーションタイプに応じた文字セット
    case "$anim_type" in
        spinner)
            SPINNER_CHARS="- \\ | /"
            ;;
        dot)
            SPINNER_CHARS=". .. ... .... ....."
            ;;
        bar)
            SPINNER_CHARS="[=] => ->"
            ;;
        figure)
            SPINNER_CHARS="0 1 2 3 4 5 6 7 8 9"
            ;;
        pulse)
            # 環境依存
            SPINNER_CHARS="◯ ◎"
            ;;
        emoji)
            # 環境依存
            SPINNER_CHARS="💩 👺 😀 👽 😈 💀"
            ;;
        moon)
            # 環境依存
            SPINNER_CHARS="🌑 🌘 🌗 🌖 🌝 🌔 🌓 🌒"
            # SPINNER_CHARS="🌕 🌖 🌗 🌘 🌑 🌒 🌓 🌔"
            ;;
        bloc)
            # 環境依存
            SPINNER_CHARS="⢿ ⣻ ⣽ ⣾ ⣷ ⣯ ⣟ ⡿"
            ;;
        *)
            SPINNER_CHARS="- \\ | /"
            ;;
    esac

    debug_log "DEBUG: Starting spinner with message: $message, type: $anim_type, delay: $SPINNER_DELAY"

    # 直前のスピナープロセスがまだ実行中の場合は停止
    if [ -n "$SPINNER_PID" ]; then
        ps | grep -v grep | grep -q "$SPINNER_PID" 2>/dev/null
        if [ $? -eq 0 ]; then
            debug_log "DEBUG: Stopping previous spinner process PID: $SPINNER_PID"
            kill "$SPINNER_PID" >/dev/null 2>&1
            wait "$SPINNER_PID" 2>/dev/null || true
        fi
    fi

    # メッセージファイルの設定
    SPINNER_MSG_FILE="${CACHE_DIR}/spinner_msg_$$.tmp"
    mkdir -p "${CACHE_DIR}" 2>/dev/null
    printf "%s" "$message" > "$SPINNER_MSG_FILE"
    debug_log "DEBUG: Created spinner message file: $SPINNER_MSG_FILE"

    # バックグラウンドでスピナーを実行
    (
        i=0
        local curr_msg="$message"
        
        while true; do
            # ファイルから新しいメッセージを読み取る
            if [ -f "$SPINNER_MSG_FILE" ]; then
                new_msg=$(cat "$SPINNER_MSG_FILE" 2>/dev/null)
                if [ -n "$new_msg" ] && [ "$new_msg" != "$curr_msg" ]; then
                    curr_msg="$new_msg"
                fi
            fi
            
            for char in $SPINNER_CHARS; do
                printf "\r\033[K%s %s" "$curr_msg" "$(color "$SPINNER_COLOR" "$char")"

                if command -v usleep >/dev/null 2>&1; then
                    usleep "$SPINNER_USLEEP_VALUE"  # マイクロ秒単位のディレイ
                else
                    sleep "$SPINNER_DELAY"  # 秒単位のディレイ
                fi
                
                # アニメーションサイクル中のメッセージ更新チェック
                if [ -f "$SPINNER_MSG_FILE" ]; then
                    new_msg=$(cat "$SPINNER_MSG_FILE" 2>/dev/null)
                    if [ -n "$new_msg" ] && [ "$new_msg" != "$curr_msg" ]; then
                        curr_msg="$new_msg"
                        break  # 新しいメッセージがあれば次のサイクルへ
                    fi
                fi
            done
        done
    ) &
    SPINNER_PID=$!
    debug_log "DEBUG: Spinner started with PID: $SPINNER_PID"
}

# スピナー停止関数
stop_spinner() {
    local message="$1"
    local status="${2:-success}"

    if [ "$ANIMATION_ENABLED" -eq "0" ]; then
        # アニメーション無効時はメッセージがあれば表示 (改行あり)
        if [ -n "$message" ]; then
            printf "%s\n" "$message"
        fi
        return
    fi

    debug_log "DEBUG: Stopping spinner with message: $message, status: $status"

    # メッセージファイルを削除
    if [ -f "$SPINNER_MSG_FILE" ]; then
        rm -f "$SPINNER_MSG_FILE" 2>/dev/null
        debug_log "DEBUG: Removed spinner message file: $SPINNER_MSG_FILE"
    fi

    # プロセスが存在するか確認
    if [ -n "$SPINNER_PID" ]; then
        # プロセスが実際に存在するか確認
        ps | grep -v grep | grep -q "$SPINNER_PID" 2>/dev/null
        if [ $? -eq 0 ]; then
            debug_log "DEBUG: Process found, killing PID: $SPINNER_PID"
            kill "$SPINNER_PID" >/dev/null 2>&1
            wait "$SPINNER_PID" 2>/dev/null || true
            unset SPINNER_PID
            printf "\r\033[K"  # 行をクリア

            # ▼▼▼ 変更点 ▼▼▼
            # メッセージが空でない場合のみ表示 (改行あり)
            if [ -n "$message" ]; then
                # 成功/失敗に応じたメッセージカラー
                if [ "$status" = "success" ]; then
                    printf "%s\n" "$(color green "$message")"
                else
                    printf "%s\n" "$(color yellow "$message")"
                fi
            fi
            # ▲▲▲ 変更点 ▲▲▲
        else
            debug_log "DEBUG: Process not found for PID: $SPINNER_PID"
            unset SPINNER_PID
            # プロセスが見つからなくても、メッセージがあれば表示 (改行あり)
            if [ -n "$message" ]; then
                 if [ "$status" = "success" ]; then
                     printf "%s\n" "$(color green "$message")"
                 else
                     printf "%s\n" "$(color yellow "$message")"
                 fi
            fi
        fi
    # SPINNER_PID がない場合でも、メッセージがあれば表示 (改行あり)
    elif [ -n "$message" ]; then
        if [ "$status" = "success" ]; then
            printf "%s\n" "$(color green "$message")"
        else
            printf "%s\n" "$(color yellow "$message")"
        fi
    fi

    # カーソル表示
    printf "\033[?25h"
}

# スピナーメッセージ更新関数
update_spinner() {
    local message="$1"
    local spinner_color="${2:-$SPINNER_COLOR}"
    
    if [ "$ANIMATION_ENABLED" -eq "0" ]; then
        debug_log "DEBUG: Animation disabled, not updating spinner message"
        return
    fi
    
    # メッセージと色を更新
    SPINNER_MESSAGE="$message"
    
    # 色が指定されている場合のみ更新
    if [ -n "$spinner_color" ]; then
        SPINNER_COLOR="$spinner_color"
    fi
    
    # メッセージファイルを更新
    if [ -f "$SPINNER_MSG_FILE" ]; then
        printf "%s" "$message" > "$SPINNER_MSG_FILE"
        debug_log "DEBUG: Updated spinner message file with: $message"
    else
        debug_log "DEBUG: Spinner message file not found: $SPINNER_MSG_FILE"
    fi
}
