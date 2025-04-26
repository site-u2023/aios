#!/bin/sh

SCRIPT_VERSION="2025.04.26-00-00" # Updated version

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-04-26
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 24.10.0)
#
# ⚠️ IMPORTANT NOTICE:
# OpenWrt OS exclusively uses **Almquist Shell (ash)** and
# is **NOT** compatible with Bourne-Again Shell (bash).
#
# 📢 POSIX Compliance Guidelines: (Guidelines remain the same)
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

# DEV_NULL and other basic constants might be defined in aios or another common script
# DEV_NULL="${DEV_NULL:-on}"
DEBUG_MODE="${DEBUG_MODE:-false}"

# 表示スタイル設定のデフォルト値 (These might be controlled globally by aios)
DISPLAY_MODE="${DISPLAY_MODE:-normal}" # 表示モード (normal/fancy/box/minimal)
COLOR_ENABLED="${COLOR_ENABLED:-1}"    # 色表示有効/無効
BOLD_ENABLED="${BOLD_ENABLED:-0}"     # 太字表示有効/無効
UNDERLINE_ENABLED="${UNDERLINE_ENABLED:-0}" # 下線表示有効/無効
BOX_ENABLED="${BOX_ENABLED:-0}"      # ボックス表示有効/無効

# --- Spinner related variables and functions REMOVED ---

# コマンドラインオプション処理関数 (aios側で制御される可能性あり)
# process_display_options() { ... } # This function might be removed if options are handled solely in aios

# 拡張カラーコードマップ関数
# @param $1: color (string) - Color name (e.g., "red", "red_underline", "black_on_white")
# @param $2: weight (string) - "bold" or "normal"
color_code_map() {
    local color="$1"
    local weight="$2"  # "bold" または "normal"
    local esc_seq=""   # Escape sequence accumulator

    # Check if color is enabled globally
    if [ "${COLOR_ENABLED:-1}" = "0" ]; then
        # If disabled, return reset sequence or empty based on color name
        [ "$color" = "reset" ] && printf "\033[0m" || printf ""
        return
    fi

    # Determine prefixes based on global settings and weight
    local style_prefix=""
    [ "$weight" = "bold" ] && style_prefix="1;"
    [ "${UNDERLINE_ENABLED:-0}" = "1" ] && ! echo "$color" | grep -q "_underline" && style_prefix="${style_prefix}4;"

    # Handle reset separately
    if [ "$color" = "reset" ]; then
        printf "\033[0m"
        return
    fi

    # Handle specific color formats
    case "$color" in
        # Basic colors
        "red") esc_seq="38;5;196" ;;
        "orange") esc_seq="38;5;208" ;;
        "yellow") esc_seq="38;5;226" ;;
        "green") esc_seq="38;5;46" ;;
        "cyan") esc_seq="38;5;51" ;;
        "blue") esc_seq="38;5;33" ;;
        "indigo") esc_seq="38;5;57" ;;
        "purple") esc_seq="38;5;129" ;;
        "magenta") esc_seq="38;5;201" ;;
        "white") esc_seq="37" ;;
        "black") esc_seq="30" ;;
        "gray") esc_seq="38;5;240" ;;

        # Underlined colors
        *_underline)
            local base_color=$(echo "$color" | sed 's/_underline//g')
            # Add underline code (4) if not already added by global setting
            echo "$style_prefix" | grep -q "4;" || style_prefix="${style_prefix}4;"
            # Recursively call for base color code (prevent infinite loop by checking _underline)
            if [ "$base_color" != "$color" ]; then
                 esc_seq=$(color_code_map "$base_color" "normal") # Get base color code without style
                 # Extract the numeric part of the base color code
                 esc_seq=$(echo "$esc_seq" | sed 's/\x1b\[//; s/m$//')
            else
                 esc_seq="37" # Fallback to white if extraction fails
            fi
            ;;

        # Background colors (fg_on_bg)
        *_on_*)
            local fg=$(echo "$color" | cut -d'_' -f1)
            local bg=$(echo "$color" | cut -d'_' -f3)
            local fg_code=$(color_code_map "$fg" "normal" | sed 's/\x1b\[//; s/m$//') # Get fg code numeric part
            local bg_code=""
            case "$bg" in # Map background name to code
                "black") bg_code="40" ;; "red") bg_code="48;5;196" ;; "orange") bg_code="48;5;208" ;;
                "yellow") bg_code="48;5;226" ;; "green") bg_code="48;5;46" ;; "cyan") bg_code="48;5;51" ;;
                "blue") bg_code="48;5;33" ;; "indigo") bg_code="48;5;57" ;; "purple") bg_code="48;5;129" ;;
                "magenta") bg_code="48;5;201" ;; "white") bg_code="47" ;; "gray") bg_code="48;5;240" ;;
                *) bg_code="40" ;; # Default background black
            esac
            esc_seq="${fg_code};${bg_code}"
            ;;

        # Fallback for fg_bg (treated as fg_on_bg with potential ambiguity)
        # Consider deprecating this format if fg_on_bg is preferred
        *_*)
            if ! echo "$color" | grep -q "_on_" && ! echo "$color" | grep -q "_underline"; then
                local fg=$(echo "$color" | cut -d'_' -f1)
                local bg=$(echo "$color" | cut -d'_' -f2) # Assume second part is background
                local fg_code=$(color_code_map "$fg" "normal" | sed 's/\x1b\[//; s/m$//')
                local bg_code=""
                case "$bg" in # Map background name to code
                    "black") bg_code="40" ;; "red") bg_code="48;5;196" ;; "orange") bg_code="48;5;208" ;;
                    "yellow") bg_code="48;5;226" ;; "green") bg_code="48;5;46" ;; "cyan") bg_code="48;5;51" ;;
                    "blue") bg_code="48;5;33" ;; "indigo") bg_code="48;5;57" ;; "purple") bg_code="48;5;129" ;;
                    "magenta") bg_code="48;5;201" ;; "white") bg_code="47" ;; "gray") bg_code="48;5;240" ;;
                    *) bg_code="40" ;; # Default background black
                esac
                esc_seq="${fg_code};${bg_code}"
            else
                # If it contains _on_ or _underline, it was handled above or is invalid
                esc_seq="37" # Default to white foreground
            fi
            ;;

        # Default: Unknown color name treated as white
        *) esc_seq="37" ;;
    esac

    # Combine style prefix and color code
    printf "\033[${style_prefix}%sm" "$esc_seq"
}


# 拡張カラー表示関数
# @param $1: color_name (string) - e.g., "red", "green_underline", "white_on_blue"
# @param $2...: text (string) - Text to display
color() {
    # 色表示が無効の場合はプレーンテキストを返す
    if [ "${COLOR_ENABLED:-1}" = "0" ]; then
        shift
        # POSIX準拠: echo "$*" は引数間のスペースを保持しない場合があるため、printfを使用
        printf "%s\n" "$*"
        return
    fi

    local color_name="$1"
    local param=""
    shift # Shift color_name

    # Check for optional parameter (-b for bold, -u for underline)
    case "$1" in
        -b) param="bold"; shift ;;
        -u) param="underline"; shift ;;
    esac

    # Remaining arguments are the text
    local text="$*"

    # Determine weight based on param and global BOLD_ENABLED
    local weight="normal"
    if [ "$param" = "bold" ] || [ "${BOLD_ENABLED:-0}" = "1" ]; then
        weight="bold"
    fi

    # Handle underline param or global UNDERLINE_ENABLED
    # Add _underline suffix if needed, avoiding double addition
    if { [ "$param" = "underline" ] || [ "${UNDERLINE_ENABLED:-0}" = "1" ]; } && ! echo "$color_name" | grep -q "_underline"; then
        color_name="${color_name}_underline"
    fi

    # DISPLAY_MODE specific adjustments (e.g., box, fancy)
    case "${DISPLAY_MODE:-normal}" in
        box)
            if [ "${BOX_ENABLED:-0}" = "1" ]; then
                display_boxed_text "$color_name" "$text" "$param" # Pass param for potential bolding inside box
                return # Box function handles output
            fi
            ;;
        fancy)
            # Fancy mode implies bold unless explicitly normal (though param handling above covers -b)
            [ "$weight" = "normal" ] && weight="bold" # Ensure bold for fancy
            ;;
        # minimal or normal: No special adjustments here, rely on param and global flags
    esac

    # Get color codes
    local color_code=$(color_code_map "$color_name" "$weight")
    local reset_code=$(color_code_map "reset" "normal")

    # Output the colored text using printf %b to handle potential escapes in text if needed
    # Using %s for text is safer if text shouldn't be interpreted
    printf "%b%s%b\n" "$color_code" "$text" "$reset_code"
}

# ボックス表示関数
# @param $1: color_name
# @param $2: text
# @param $3: param ("bold", "underline", or empty)
display_boxed_text() {
    local color_name="$1"
    local text="$2"
    local param="$3"
    local text_len=$(printf "%s" "$text" | wc -c) # Get byte count for width calculation
    local width=$((text_len + 4))

    # Determine weight
    local weight="normal"
    if [ "$param" = "bold" ] || [ "${BOLD_ENABLED:-0}" = "1" ]; then
        weight="bold"
    fi

    # Handle underline (add suffix if needed)
    if { [ "$param" = "underline" ] || [ "${UNDERLINE_ENABLED:-0}" = "1" ]; } && ! echo "$color_name" | grep -q "_underline"; then
        color_name="${color_name}_underline"
    fi

    # Get color codes
    local color_code=$(color_code_map "$color_name" "$weight")
    local reset_code=$(color_code_map reset normal)

    # Draw box using POSIX utilities
    local border_line=$(printf "%${width}s" "" | tr ' ' '-') # Create line of dashes
    local top_border="┌${border_line%??}┐" # Replace last two dashes
    local bottom_border="└${border_line%??}┘"

    printf "%b%s%b\n" "$color_code" "$top_border" "$reset_code"
    printf "%b│ %s │%b\n" "$color_code" "$text" "$reset_code" # Add spaces around text
    printf "%b%s%b\n" "$color_code" "$bottom_border" "$reset_code"
}

# 装飾メニューヘッダー表示関数 (Remains the same logic, uses updated color/display_boxed_text)
# @param $1: title
# @param $2: color_name (optional, default: blue)
fancy_header() {
    local title="$1"
    local color_name="${2:-blue}"
    local title_len=$(printf "%s" "$title" | wc -c)

    case "${DISPLAY_MODE:-normal}" in
        box)
            if [ "${BOX_ENABLED:-0}" = "1" ]; then
                display_boxed_text "$color_name" "$title" "bold" # Use bold param for box
                return
            fi
            # Fall through if box not enabled
            ;& # POSIX equivalent for fallthrough is not direct, simulate by repeating default logic
        fancy)
            printf "\n%s\n" "$(color "$color_name" -b "$title")" # Use -b for bold
            printf "%s\n\n" "$(color "$color_name" "$(repeat_char "=" "$title_len")")"
            return
            ;;
        minimal)
            printf "\n%s\n\n" "$(color "$color_name" "$title")" # No bold, no underline
            return
            ;;
        *) # Default 'normal' mode
            printf "\n%s\n" "$(color "$color_name" -b "$title")" # Use -b for bold
            printf "%s\n\n" "$(color "$color_name" "$(repeat_char "-" "$title_len")")"
            ;;
    esac
}

# 文字繰り返し関数 (POSIX compliant)
# @param $1: char
# @param $2: count
repeat_char() {
    local char="$1"
    local count="$2"
    local result=""
    local i=0

    # Handle non-numeric or zero count
    if ! [ "$count" -gt 0 ] 2>/dev/null; then
        printf ""
        return
    fi

    while [ $i -lt $count ]; do
        result="${result}${char}"
        i=$((i + 1))
    done

    printf "%s" "$result" # Use printf without newline
}
