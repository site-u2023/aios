#!/bin/sh

SCRIPT_VERSION="2025.03.14-00-00"

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
