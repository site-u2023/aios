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

# 表示スタイル設定のデフォルト値
DISPLAY_MODE="normal"   # 表示モード (normal/fancy/box/minimal)
COLOR_ENABLED="1"       # 色表示有効/無効
BOLD_ENABLED="0"        # 太字表示有効/無効
UNDERLINE_ENABLED="0"   # 下線表示有効/無効
BOX_ENABLED="0"         # ボックス表示有効/無効
ANIMATION_ENABLED="1"   # アニメーション有効/無効

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

# 設定保存関数
save_display_settings() {
    local config_file="${BASE_DIR:-/tmp/aios}/display_settings.conf"
    
    debug_log "DEBUG" "Saving display settings to: $config_file"
    
    # ディレクトリが存在しない場合は作成
    [ -d "${BASE_DIR:-/tmp/aios}" ] || mkdir -p "${BASE_DIR:-/tmp/aios}"
    
    # 設定ファイルを作成
    cat > "$config_file" << EOF
# 表示設定ファイル
# 更新日時: $(date)
DISPLAY_MODE=$DISPLAY_MODE
COLOR_ENABLED=$COLOR_ENABLED
BOLD_ENABLED=$BOLD_ENABLED
UNDERLINE_ENABLED=$UNDERLINE_ENABLED
BOX_ENABLED=$BOX_ENABLED
ANIMATION_ENABLED=$ANIMATION_ENABLED
EOF

    debug_log "DEBUG" "Display settings saved successfully"
}

# 設定読み込み関数
load_display_settings() {
    local config_file="${BASE_DIR:-/tmp/aios}/display_settings.conf"
    
    debug_log "DEBUG" "Loading display settings from: $config_file"
    
    # 設定ファイルが存在する場合のみ読み込み
    if [ -f "$config_file" ]; then
        while IFS="=" read -r key value; do
            # コメント行と空行をスキップ
            case "$key" in
                \#*|"") continue ;;
            esac
            
            # 空白を削除
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # 設定を適用
            case "$key" in
                DISPLAY_MODE) DISPLAY_MODE="$value" ;;
                COLOR_ENABLED) COLOR_ENABLED="$value" ;;
                BOLD_ENABLED) BOLD_ENABLED="$value" ;;
                UNDERLINE_ENABLED) UNDERLINE_ENABLED="$value" ;;
                BOX_ENABLED) BOX_ENABLED="$value" ;;
                ANIMATION_ENABLED) ANIMATION_ENABLED="$value" ;;
            esac
        done < "$config_file"
        
        debug_log "DEBUG" "Display settings loaded successfully"
    else
        debug_log "DEBUG" "No display settings file found, using defaults"
    fi
}

# アニメーション関数
animation() {
    local anim_type="spinner"  # デフォルトはスピナー
    local delay="1"       # デフォルトは1秒
    local count="1"            # デフォルトは1回
    local cursor_hide="1"      # デフォルトはカーソル非表示
    local param_found=""       # パラメータが見つかったかのフラグ
    
    # オプション処理（POSIX準拠）
    while [ $# -gt 0 ]; do
        case "$1" in
            -t|--type)
                shift
                [ -n "$1" ] && anim_type="$1"
                ;;
            -d|--delay)
                shift
                [ -n "$1" ] && delay="$1"
                ;;
            -c|--count)
                shift
                [ -n "$1" ] && count="$1"
                ;;
            -s|--show-cursor)
                cursor_hide="0"
                ;;
            *)
                # 最初の位置引数はタイプ
                if [ -z "$param_found" ]; then
                    anim_type="$1"
                    param_found="1"
                fi
                ;;
        esac
        shift
    done
    
    debug_log "DEBUG" "Running animation with type: $anim_type, delay: $delay, count: $count"
    
    # カーソル非表示（設定されている場合）
    [ "$cursor_hide" = "1" ] && printf "\033[?25l"
    
    local c=0
    while [ $c -lt $count ]; do
        case "$anim_type" in
            spinner)
                # スピナーアニメーション - 1サイクル分の文字
                printf "-"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b\\"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b|"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b/"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b"
                ;;
                
            dot)
                # ドットアニメーション
                printf "."
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "."
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "."
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b\b\b   \b\b\b"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                ;;
                
            bar)
                # バーアニメーション
                printf "["
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b="
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b>"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b]"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b \b"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                ;;
                
            pulse)
                # パルスアニメーション
                printf "□"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b■"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b□"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                ;;
                
            *)
                # カスタムアニメーション
                printf "%s" "$anim_type"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                printf "\b \b"
                if command -v usleep >/dev/null 2>&1; then
                    usleep "$delay"
                else
                    sleep "$((delay / 1000000))"
                fi
                ;;
        esac
        
        c=$((c + 1))
    done
    
    # カーソル表示（設定されている場合）
    [ "$cursor_hide" = "1" ] && printf "\033[?25h"
    
    debug_log "DEBUG" "Animation completed successfully"
}

# スピナー開始関数
start_spinner() {
    local message="$1"
    local anim_type="${2:-spinner}"
    local spinner_color="${3:-green}"
    
    SPINNER_MESSAGE="$message"
    SPINNER_TYPE="$anim_type"
    SPINNER_COLOR="$spinner_color"
    
    # usleepの有無をチェックしてディレイを設定
    if command -v usleep >/dev/null 2>&1; then
        SPINNER_USLEEP_VALUE=200000  # 200000マイクロ秒 = 0.2秒
        SPINNER_DELAY="200000"       # animation関数用のディレイ値（マイクロ秒）
        debug_log "DEBUG" "Using fast animation mode (0.2s) with usleep"
    else
        SPINNER_DELAY="1"            # animation関数用のディレイ値（整数秒）
        debug_log "DEBUG" "Using standard animation mode (1s)"
    fi
    
    # カーソル非表示
    printf "\033[?25l"
    
    debug_log "DEBUG" "Starting spinner with message: $message, type: $anim_type, delay: $SPINNER_DELAY"

    # バックグラウンドでループ実行
    (
        while true; do
            # 行をクリアしてメッセージ表示
            printf "\r\033[K📡 %s " "$(color "$SPINNER_COLOR" "$SPINNER_MESSAGE")"
            
            # animation関数を呼び出し
            animation -t "$SPINNER_TYPE" -d "$SPINNER_DELAY" -c 1 -s
            
            # ディレイ
            if command -v usleep >/dev/null 2>&1; then
                usleep "$SPINNER_USLEEP_VALUE"  # マイクロ秒単位のディレイ
            else
                sleep "$SPINNER_DELAY"          # 秒単位のディレイ
            fi
        done
    ) &
    
    SPINNER_PID=$!
    debug_log "DEBUG" "Spinner started with PID: $SPINNER_PID"
}

# スピナー停止関数
stop_spinner() {
    local message="$1"
    local status="${2:-success}"

    debug_log "DEBUG" "Stopping spinner with message: $message, status: $status"

    # プロセスが存在するか確認
    if [ -n "$SPINNER_PID" ]; then
        # プロセスが実際に存在するか確認
        ps | grep -v grep | grep -q "$SPINNER_PID" 2>/dev/null
        if [ $? -eq 0 ]; then
            debug_log "DEBUG" "Process found, killing PID: $SPINNER_PID"
            kill "$SPINNER_PID" >/dev/null 2>&1
            wait "$SPINNER_PID" 2>/dev/null || true
            printf "\r\033[K"  # 行をクリア
            
            # 成功/失敗に応じたメッセージカラー
            if [ "$status" = "success" ]; then
                printf "%s\n" "$(color green "$message")"
            else
                printf "%s\n" "$(color yellow "$message")"
            fi
        else
            debug_log "DEBUG" "Process not found for PID: $SPINNER_PID"
        fi
    fi
    
    # カーソル表示
    printf "\033[?25h"
}

# **スピナー開始関数**
XX_start_spinner() {
    local message="$1"
    SPINNER_MESSAGE="$message"  # 停止時のメッセージ保持
    #spinner_chars='| / - \\'
    spinner_chars="-\\|/"
    i=0

    # カーソル非表示
    printf "\033[?25l"

    while true; do
        # POSIX 準拠の方法でインデックスを計算し、1文字抽出
        local index=$(( i % 4 ))
        local char_pos=$(( index + 1 ))
        local spinner_char=$(expr substr "$spinner_chars" "$char_pos" 1)
        printf "\r📡 %s %s" "$(color yellow "$SPINNER_MESSAGE")" "$spinner_char"
        
        if command -v usleep >/dev/null 2>&1; then
            usleep 200000
        else
            sleep 1
        fi
        i=$(( i + 1 ))
    done &
    SPINNER_PID=$!
}

# **スピナー停止関数**
XX_stop_spinner() {
    local message="$1"

    if [ -n "$SPINNER_PID" ] && ps | grep -q " $SPINNER_PID "; then
        kill "$SPINNER_PID" >/dev/null 2>&1
        printf "\r\033[K"  # 行をクリア
        printf "%s\n" "$(color green "$message")"
    else
        printf "\r\033[K"
        printf "%s\n" "$(color red "$message")"
    fi
    unset SPINNER_PID

    # カーソル表示
    printf "\033[?25h"
}

# 表示設定メニュー
display_settings_menu() {
    local exit_menu=0
    
    while [ $exit_menu -eq 0 ]; do
        clear
        
        fancy_header "表示設定" "blue"
        
        # 現在の設定を表示
        printf "%s\n" "$(color blue "[1]") $(color white "表示モード: $(color yellow "$DISPLAY_MODE")")"
        printf "%s\n" "$(color blue "[2]") $(color white "カラー表示: $([ "$COLOR_ENABLED" = "1" ] && color green "有効" || color red "無効")")"
        printf "%s\n" "$(color blue "[3]") $(color white "太字表示: $([ "$BOLD_ENABLED" = "1" ] && color green "有効" || color red "無効")")"
        printf "%s\n" "$(color blue "[4]") $(color white "下線表示: $([ "$UNDERLINE_ENABLED" = "1" ] && color green "有効" || color red "無効")")"
        printf "%s\n" "$(color blue "[5]") $(color white "ボックス表示: $([ "$BOX_ENABLED" = "1" ] && color green "有効" || color red "無効")")"
        printf "%s\n" "$(color blue "[6]") $(color white "アニメーション: $([ "$ANIMATION_ENABLED" = "1" ] && color green "有効" || color red "無効")")"
        printf "%s\n" "$(color blue "[7]") $(color white "設定を保存")"
        printf "%s\n" "$(color blue "[0]") $(color white "戻る")"
        printf "\n"
        
        # プロンプト表示
        printf "%s " "$(color green "番号を選択してください (0-7):")"
        read -r choice
        
        case "$choice" in
            1)
                # 表示モード変更
                clear
                printf "\n%s\n" "$(color blue "表示モードを選択:")"
                printf "%s\n" "$(color white "1. normal (標準表示)")"
                printf "%s\n" "$(color white "2. fancy (装飾表示)")"
                printf "%s\n" "$(color white "3. box (ボックス表示)")"
                printf "%s\n" "$(color white "4. minimal (最小限表示)")"
                printf "%s " "$(color green "番号を選択してください (1-4):")"
                
                read -r mode_choice
                case "$mode_choice" in
                    1) DISPLAY_MODE="normal" ;;
                    2) DISPLAY_MODE="fancy" ;;
                    3) DISPLAY_MODE="box" ;;
                    4) DISPLAY_MODE="minimal" ;;
                    *) printf "%s\n" "$(color red "無効な選択です")" ;;
                esac
                debug_log "DEBUG" "Display mode changed to: $DISPLAY_MODE"
                sleep 1
                ;;
                
            2)
                # カラー表示切り替え
                COLOR_ENABLED=$([ "$COLOR_ENABLED" = "1" ] && echo "0" || echo "1")
                debug_log "DEBUG" "Color display toggled to: $COLOR_ENABLED"
                ;;
                
            3)
                # 太字表示切り替え
                BOLD_ENABLED=$([ "$BOLD_ENABLED" = "1" ] && echo "0" || echo "1")
                debug_log "DEBUG" "Bold text toggled to: $BOLD_ENABLED"
                ;;
                
            4)
                # 下線表示切り替え
                UNDERLINE_ENABLED=$([ "$UNDERLINE_ENABLED" = "1" ] && echo "0" || echo "1")
                debug_log "DEBUG" "Underline text toggled to: $UNDERLINE_ENABLED"
                ;;
                
            5)
                # ボックス表示切り替え
                BOX_ENABLED=$([ "$BOX_ENABLED" = "1" ] && echo "0" || echo "1")
                debug_log "DEBUG" "Box display toggled to: $BOX_ENABLED"
                ;;
                
            6)
                # アニメーション切り替え
                ANIMATION_ENABLED=$([ "$ANIMATION_ENABLED" = "1" ] && echo "0" || echo "1")
                debug_log "DEBUG" "Animation toggled to: $ANIMATION_ENABLED"
                ;;
                
            7)
                # 設定保存
                save_display_settings
                printf "%s\n" "$(color green "設定を保存しました")"
                sleep 1
                ;;
                
            0)
                # 終了
                exit_menu=1
                ;;
                
            *)
                printf "%s\n" "$(color red "無効な選択です")"
                sleep 1
                ;;
        esac
    done
}
