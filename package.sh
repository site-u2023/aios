#!/bin/sh

SCRIPT_VERSION="2025.05.08-01-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-28
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
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"

packages() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color black_white "$header_text")"
    }

    # === 基本システム機能 ===
    print_section_header "PKG_SECTION_BASIC"
    install_package luci-i18n-base yn hidden
    install_package ttyd yn hidden disabled
    install_package openssh-sftp-server yn hidden
    install_package coreutils yn hidden
    #install_package bash yn hidden
    
    # === システム管理 ===
    print_section_header "PKG_SECTION_SYSADMIN"
    install_package irqbalance yn hidden
    install_package luci-mod-dashboard yn hidden
    
    # === ネットワーク管理 ===
    print_section_header "PKG_SECTION_NETWORK"
    install_package luci-app-sqm yn hidden
    install_package luci-app-qos yn hidden
    install_package luci-i18n-statistics yn hidden
    install_package luci-i18n-nlbwmon yn hidden
    install_package wifischedule yn hidden

    # === セキュリティツール ===
    print_section_header "PKG_SECTION_SECURITY"
    install_package znc-mod-fail2ban yn hidden
    install_package banip yn hidden

    # === システム監視 ===
    print_section_header "PKG_SECTION_MONITORING"
    install_package htop yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf yn hidden "desc=CPU performance information and management for LuCI"
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-status yn hidden "desc=CPU utilization info for the LuCI status page"
    feed_package gSpotx2f packages-openwrt current luci-app-temp-status yn hidden "desc=Temperature sensors data for the LuCI status page"
    feed_package gSpotx2f packages-openwrt current internet-detector yn hidden disabled "desc=Internet-detector is an application for checking the availability of the Internet. Performs periodic connections to a known public host and determines the actual Internet"
    feed_package gSpotx2f packages-openwrt current luci-app-log-viewer yn hidden "desc=Advanced syslog and kernel log (tail, search, etc) for LuCI"

    # === ネットワーク診断ツール ===
    print_section_header "PKG_SECTION_NETWORK_DIAG"
    install_package mtr yn hidden
    install_package nmap yn hidden
    install_package tcpdump yn hidden
    
    # === テーマおよび見た目 ===
    print_section_header "PKG_SECTION_THEME"
    install_package luci-theme-openwrt yn hidden
    feed_package_release jerrykuku luci-theme-argon yn hidden disabled "desc=Argon is a clean and tidy OpenWrt LuCI theme that allows users to customize their login interface with images or videos. It also supports automatic and manual switching between light and dark modes."

    # === ユーティリティ ===
    print_section_header "PKG_SECTION_UTILITY"
    install_package attendedsysupgrade-common yn hidden
    feed_package_release lisaac luci-app-diskman yn hidden disabled "desc=A Simple Disk Manager for LuCI, support disk partition and format, support raid / btrfs-raid / btrfs-snapshot"

    # === 追加機能（デフォルトで無効） ===
    #print_section_header "PKG_SECTION_ADDITION"
    
    debug_log "DEBUG" "Standard packages installation process completed"
    return 0
}

packages_19() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color black_white "$header_text")"
    }

    # === 基本システム機能 ===
    print_section_header "PKG_SECTION_BASIC"
    install_package wget yn hidden
    install_package luci-i18n-base yn hidden
    install_package ttyd yn hidden disabled
    install_package openssh-sftp-server yn hidden
    install_package coreutils yn hidden
    
    # === システム管理 ===
    print_section_header "PKG_SECTION_SYSADMIN"
    install_package irqbalance yn hidden
    install_package luci-i18n-dashboard yn hidden
    
    # === ネットワーク管理 ===
    print_section_header "PKG_SECTION_NETWORK"
    #install_package luci-app-sqm yn hidden
    install_package luci-app-qos yn hidden
    install_package luci-i18n-statistics yn hidden
    install_package luci-i18n-nlbwmon yn hidden
    install_package wifischedule yn hidden

    # === セキュリティツール ===
    print_section_header "PKG_SECTION_SECURITY"
    install_package znc-mod-fail2ban yn hidden
    install_package banip yn hidden
    
    # === システム監視 (19.07特有版) ===
    print_section_header "PKG_SECTION_MONITORING"
    install_package htop yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf yn hidden "desc=CPU performance information and management for LuCI"
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-cpu-status-mini yn hidden "desc=CPU utilization info for the LuCI status page"
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-log yn hidden "desc=Advanced syslog and kernel log (tail, search, etc) for LuCI"
    
    # === ネットワーク診断ツール ===
    print_section_header "PKG_SECTION_NETWORK_DIAG"
    install_package mtr yn hidden
    install_package nmap yn hidden
    install_package tcpdump yn hidden

    # === テーマおよび見た目 ===
    print_section_header "PKG_SECTION_THEME"
    install_package luci-theme-openwrt yn hidden
    
    # === ユーティリティ ===
    print_section_header "PKG_SECTION_UTILITY"
    install_package attendedsysupgrade-common yn hidden
    feed_package_release lisaac luci-app-diskman yn hidden disabled "desc=A Simple Disk Manager for LuCI, support disk partition and format, support raid / btrfs-raid / btrfs-snapshot"
    
    # === 追加機能（デフォルトで無効） ===
    #print_section_header "PKG_SECTION_ADDITION"
    
    debug_log "DEBUG" "19.07 specific packages installation process completed"
    return 0
}

packages_snaphot() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color black_white "$header_text")"
    }

    # === 基本システム機能 ===
    print_section_header "PKG_SECTION_BASIC"
    install_package luci yn hidden
    install_package luci-i18n-base yn hidden
    install_package ttyd yn hidden disabled
    install_package openssh-sftp-server yn hidden
    install_package coreutils yn hidden
    
    # === システム管理 ===
    print_section_header "PKG_SECTION_SYSADMIN"
    install_package irqbalance yn hidden
    install_package luci-mod-dashboard yn hidden
    
    # === ネットワーク管理 ===
    print_section_header "PKG_SECTION_NETWORK"
    install_package luci-app-sqm yn hidden
    install_package luci-app-qos yn hidden
    install_package luci-i18n-statistics yn hidden
    install_package luci-i18n-nlbwmon yn hidden
    install_package wifischedule yn hidden

    # === システム監視 ===
    print_section_header "PKG_SECTION_MONITORING"
    install_package htop yn hidden
    
    # === セキュリティツール ===
    print_section_header "PKG_SECTION_SECURITY"
    install_package znc-mod-fail2ban yn hidden
    install_package banip yn hidden

    # === ネットワーク診断ツール ===
    print_section_header "PKG_SECTION_NETWORK_DIAG"
    install_package mtr yn hidden
    install_package nmap yn hidden
    install_package tcpdump yn hidden
    
    # === テーマおよび見た目 ===
    print_section_header "PKG_SECTION_THEME"
    install_package luci-theme-openwrt yn hidden
    
    # === ユーティリティ ===
    print_section_header "PKG_SECTION_UTILITY"
    install_package attendedsysupgrade-common yn hidden
    
    debug_log "DEBUG" "SNAPSHOT specific packages installation process completed"
    return 0
}

packages_usb() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color black_white "$header_text")"
    }

    # === USBストレージ ===
    print_section_header "PKG_SECTION_USB"
    install_package kmod-usb-storage yn hidden
    install_package dosfstools yn hidden
    install_package e2fsprogs yn hidden
    install_package f2fs-tools yn hidden
    install_package exfat-fsck yn hidden
    install_package ntfs-3g yn hidden
    install_package hfsfsck yn hidden
    install_package hdparm yn hidden
    
    debug_log "DEBUG" "USB and storage related packages installation process completed"
    return 0
}

package_samba() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color black_white "$header_text")"
    }

    # === ファイル共有 ===
    print_section_header "PKG_SECTION_SAMBA"
    install_package luci-app-samba4 yn hidden
    
    debug_log "DEBUG" "Samba file sharing packages installation process completed"
    return 0
}

# OSバージョンに基づいて適切なパッケージ関数を実行する
install_packages_version() {
    # OSバージョンファイルの確認
    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        debug_log "DEBUG" "OS version file not found, using default package function"
        packages
        
        return 0
    fi

    # OSバージョンの読み込み
    local os_version
    os_version=$(cat "${CACHE_DIR}/osversion.ch")
    
    debug_log "DEBUG" "Detected OS version: $os_version"

    # バージョンに基づいて関数を呼び出し
    case "$os_version" in
        19.*)
            # バージョン19系の場合
            debug_log "DEBUG" "Installing packages for OpenWrt 19.x series"
            packages_19
            ;;
        *[Ss][Nn][Aa][Pp][Ss][Hh][Oo][Tt]*)
            # スナップショットバージョンの場合（大文字小文字を区別しない）
            debug_log "DEBUG" "Installing packages for OpenWrt SNAPSHOT"
            packages_snaphot
            ;;
        *)
            # その他の通常バージョン
            debug_log "DEBUG" "Installing standard packages"
            packages
            ;;
    esac

    return 0
}

# USBデバイスを検出し、必要なパッケージをインストールする関数
install_usb_packages() {
    # USBデバイスのキャッシュファイルを確認
    if [ ! -f "${CACHE_DIR}/usbdevice.ch" ]; then
        debug_log "DEBUG" "USB device cache file not found, skipping USB detection"
        return 0
    fi
    
    # USBデバイスが検出されているか確認
    if [ "$(cat "${CACHE_DIR}/usbdevice.ch")" = "detected" ]; then
        debug_log "DEBUG" "USB device detected, installing USB packages"
        packages_usb
    else
        debug_log "DEBUG" "No USB device detected, skipping USB packages"
    fi
    
    return 0
}

# 元の check_install_list 関数を入口関数として利用
# パッケージマネージャに応じて処理を分岐する

# グローバル変数（またはスクリプトの早い段階で設定される変数）の想定
# CACHE_DIR="/tmp/my_cache" # 例: キャッシュディレクトリ
# PACKAGE_MANAGER="" # スクリプトの初期化段階で設定される想定

# ログ出力関数のプレースホルダー (実際のログ関数に置き換えてください)
debug_log() {
    _level="$1"
    _message="$2"
    # 実際のログ記録処理 (例: printf "[%s] %s\n" "$_level" "$_message" >&2)
    printf "[%s] %s\n" "$_level" "$_message"
}

# メッセージ取得関数のプレースホルダー (実際のメッセージ取得関数に置き換えてください)
get_message() {
    _key="$1"
    # 実際のメッセージ取得処理 (例: echo "$_key")
    echo "$_key"
}

# 色付け関数のプレースホルダー (実際のカラーリング関数に置き換えてください)
color() {
    _color_name="$1"
    _text="$2"
    # 実際のカラーリング処理 (例: echo "$_text")
    echo "$_text"
}

# opkgでフラッシュ後にユーザーがインストールしたパッケージを取得する関数
get_installed_packages_opkg() {
    debug_log "DEBUG" "Function called: get_installed_packages_opkg"
    if [ ! -f "/usr/lib/opkg/status" ] || [ ! -s "/usr/lib/opkg/status" ]; then
        debug_log "ERROR" "/usr/lib/opkg/status not found or is empty."
        return 1
    fi

    # opkg statusファイルから、最も古いインストール時刻（通常はフラッシュ時刻）を取得
    # awkスクリプトの堅牢性向上のため、OLDESTの初期化をBEGINブロックで行う
    local flash_time
    flash_time="$(awk '
    BEGIN { OLDEST = "" }
    $1 == "Installed-Time:" {
        current_time = $2;
        # 数字であるか簡単なチェック (より厳密なチェックも可能)
        if (current_time ~ /^[0-9]+$/) {
            if (OLDEST == "" || current_time < OLDEST) {
                OLDEST = current_time;
            }
        }
    }
    END {
        if (OLDEST != "") {
            print OLDEST;
        } else {
            # OLDEST が見つからなかった場合のフォールバックまたはエラー処理
            # ここでは空文字列を出力し、呼び出し元で対処する想定
            # print "Error:CouldNotDetermineFlashTime"; # 代替案
        }
    }
    ' /usr/lib/opkg/status)"

    if [ -z "$flash_time" ]; then
        debug_log "ERROR" "Could not determine the flash installation time from opkg status."
        return 1
    fi
    debug_log "DEBUG" "Determined flash time (opkg oldest install time): $flash_time"

    # opkg statusファイルから、フラッシュ時刻以降にユーザーによってインストールされたパッケージを抽出
    awk -v ft="$flash_time" '
    BEGIN { pkg = ""; usr = "" }
    $1 == "Package:" { pkg = $2 }
    $1 == "Status:" {
        # "Status: install user installed" のような形式を想定
        # $3 が "user" で $4 が "installed" であることを確認
        if ($3 == "user" && $4 == "installed") {
            usr = 1
        } else {
            usr = "" # 他のステータスならリセット
        }
    }
    $1 == "Installed-Time:" && $2 ~ /^[0-9]+$/ { # Installed-Timeが数字であることを確認
        if (usr == 1 && $2 != ft) {
            print pkg
        }
        # Reset for next package block
        pkg = ""; usr = "";
    }
    ' /usr/lib/opkg/status | sort
}

# Helper function to fetch a file using wget
# This function is part of the v16 logic and is a dependency for
# generate_default_package_list_from_source.
# It should be defined before generate_default_package_list_from_source.
fetch_file() {
    local _url_orig="$1"         # The original URL to fetch
    local _output_file="$2"      # The file path to save the downloaded content
    local _cache_bust_param    # Cache-busting parameter
    local _url_with_cb         # URL with cache-busting parameter
    local ret_code             # Stores the return code of wget

    _cache_bust_param="_cb=$(date +%s)" # Simple cache buster using current timestamp
    _url_with_cb="${_url_orig}?${_cache_bust_param}"

    # debug_log "DEBUG" "Downloading $_url_with_cb to $_output_file" # Verbose logging
    # ユーザー指示: OpenWrtデフォルトパッケージのみ利用 (wget)
    # ユーザー指示: 元ソース状態厳守 (wgetオプション)
    if ${BASE_WGET:-wget --no-check-certificate -q} -O "$_output_file" --timeout=30 "$_url_with_cb"; then
        if [ ! -s "$_output_file" ]; then # Check if the downloaded file is empty
            debug_log "ERROR" "Downloaded file '$_output_file' is empty. URL: '$_url_with_cb'"
            return 1 # Failure
        fi
        # debug_log "DEBUG" "Successfully downloaded '$_url_orig'." # Verbose logging
        return 0 # Success
    else
        ret_code=$?
        debug_log "ERROR" "wget failed for '$_url_with_cb' (exit code: $ret_code)"
        return $ret_code # Failure, return wget's exit code
    fi
}

# Helper function to extract a multi-line Makefile variable block.
# This function is part of the v16 logic and is a dependency for
# generate_default_package_list_from_source.
# It should be defined before generate_default_package_list_from_source.
extract_makefile_block() {
    local _file_path="$1"        # Path to the Makefile
    local _var_name_raw="$2"     # Raw variable name (e.g., "DEFAULT_PACKAGES.basic")
    local _operator_raw="$3"     # Raw operator (e.g., ":=", "+=")
    local _var_name_for_regex  # Variable name escaped for regex
    local _operator_for_regex  # Operator escaped for regex
    local _full_regex          # Full regex to find the start of the block
    
    # Escape dots in variable name for regex (e.g., "DEFAULT_PACKAGES.basic" -> "DEFAULT_PACKAGES\.basic")
    _var_name_for_regex=$(echo "$_var_name_raw" | sed 's/\./\\./g')
    
    # Prepare operator for regex, allowing optional spaces around operator characters
    # This logic is from v16 and should be robust.
    _operator_for_regex=""
    if [ "$_operator_raw" = "+=" ]; then _operator_for_regex='\\+[[:space:]]*=';
    elif [ "$_operator_raw" = ":=" ]; then _operator_for_regex=':[[:space:]]*=';
    elif [ "$_operator_raw" = "?=" ]; then _operator_for_regex='\\?[[:space:]]*='; # ? needs shell escape for \? then regex escape for \?
    else
        # Generic escape for other potential operators, though less common for package lists
        _operator_for_regex=$(echo "$_operator_raw" | sed 's/[+?*.:\[\]^${}\\|=()]/\\&/g')
    fi
    
    # Construct the full regex pattern to find the start of the block
    # Looks for: optional_spaces VAR optional_spaces OP
    _full_regex="^[[:space:]]*${_var_name_for_regex}[[:space:]]*${_operator_for_regex}"

    # AWK script to find and print the block:
    # state 0: searching for the start of the block
    # state 1: in the block, printing lines until one does not end with '\' (line continuation)
    awk -v pattern="${_full_regex}" '
    BEGIN {
        state = 0; # 0 = searching_for_start, 1 = in_block
    }
    {
        if (state == 0) {
            if ($0 ~ pattern) { # If current line matches the start pattern
                state = 1;
                current_line = $0;
                # Remove EOL comments (anything after #) before printing
                sub(/[[:space:]]*#.*$/, "", current_line);
                print current_line;
                # If this starting line does not end with a backslash, the block ends here
                if (!(current_line ~ /\\$/)) {
                    state = 0; # Reset state, block was a single line
                }
            }
        } else { # state == 1 (already in_block)
            current_line = $0;
            sub(/[[:space:]]*#.*$/, "", current_line); # Remove EOL comments
            print current_line;
            # If this continuation line does not end with a backslash, the block ends here
            if (!(current_line ~ /\\$/)) {
                state = 0; # Reset state
            }
        }
     }' "$_file_path"
}

# Helper function to parse packages from an already extracted Makefile block.
# This function is part of the v16 logic and is a dependency for
# generate_default_package_list_from_source.
# It should be defined before generate_default_package_list_from_source.
parse_packages_from_extracted_block() {
    local _block_text="$1"          # The multi-line block text from extract_makefile_block
    local _var_to_strip_orig="$2"   # Original variable name to strip (e.g., "DEFAULT_PACKAGES.basic")
    local _op_to_strip="$3"         # Original operator to strip (e.g., ":=")
    local _first_line_processed=0   # Flag to track if the first line of the block has been processed

    if [ -z "$_block_text" ]; then
        return # Nothing to parse
    fi

    # Process the block text line by line using a while loop
    echo "$_block_text" | while IFS= read -r _line || [ -n "$_line" ]; do # POSIX compliant read loop
        local _processed_line # Stores the line after processing
        _processed_line="$_line"

        # Prepare awk-safe versions of the variable and operator for regex stripping
        local _var_esc_awk # Variable escaped for awk regex
        _var_esc_awk=$(echo "$_var_to_strip_orig" | sed 's/\./\\./g')
        local _op_esc_awk # Operator escaped for awk regex
        if [ "$_op_to_strip" = "+=" ]; then _op_esc_awk='\\+[[:space:]]*=';
        elif [ "$_op_to_strip" = ":=" ]; then _op_esc_awk=':[[:space:]]*=';
        elif [ "$_op_to_strip" = "?=" ]; then _op_esc_awk='\\?[[:space:]]*=';
        else _op_esc_awk=$(echo "$_op_to_strip" | sed 's/[+?*.:\[\]^${}\\|=()]/\\&/g'); fi
        
        # Regex to match "VAR OP " at the beginning of the first line
        local _var_re_str_for_awk="^[[:space:]]*${_var_esc_awk}[[:space:]]*${_op_esc_awk}[[:space:]]*"

        # AWK script to clean up the line and extract package names
        _processed_line=$(echo "$_processed_line" | awk \
            -v var_re_str="$_var_re_str_for_awk" \
            -v var_to_filter_exact="$_var_to_strip_orig" \
            -v op_to_filter_exact="$_op_to_strip" \
            -v is_first_line_for_awk="$_first_line_processed" \
            '{
                # Remove EOL comments first from the whole line (robustly handles spaces before #)
                sub(/[[:space:]]*#.*$/, "");

                # On the first line of the block, remove the "VAR OP " part
                if (is_first_line_for_awk == 0) { 
                    sub(var_re_str, ""); 
                }
                
                # Remove all Makefile $(...) variable expansions iteratively
                while (match($0, /\$\([^)]*\)/)) {
                    $0 = substr($0, 1, RSTART-1) substr($0, RSTART+RLENGTH);
                }

                # Trim leading/trailing whitespace from the processed line
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); 

                # Iterate over fields (package names) and print valid ones
                if (NF > 0) { # If there are any fields left
                    for (i=1; i<=NF; i++) {
                        current_field = $i;
                        
                        # Filter out the variable name itself or the operator if they appear as fields
                        if (current_field == var_to_filter_exact) continue;
                        
                        # Prepare operator for exact match filtering (remove spaces for comparison if needed)
                        # This handles cases like " + = " being passed as op_to_filter_exact
                        current_op_no_space_for_awk = op_to_filter_exact; 
                        gsub(/[[:space:]]/, "", current_op_no_space_for_awk);
                        current_field_no_space_for_awk = current_field; 
                        gsub(/[[:space:]]/, "", current_field_no_space_for_awk);
                        if (current_op_no_space_for_awk != "" && current_field_no_space_for_awk == current_op_no_space_for_awk) continue;

                        # Filter out common makefile elements that are not package names
                        if (current_field != "" && \
                            current_field != "\\" && \
                            current_field !~ /^(\(|\))$/ && \
                            current_field !~ /^(=|\+=|:=|\?=)$/ && \
                            current_field !~ /^\$\(/ ) { # Also filter incomplete $(vars
                            print current_field;
                        }
                    }
                }
            }')
        
        # Mark first line as processed for subsequent iterations (if block is multi-line)
        if [ "$_first_line_processed" -eq 0 ]; then
            _first_line_processed=1
        fi
        
        # Final cleanup: remove trailing backslash (line continuation) and any resulting empty lines
        local _processed_line_final
        _processed_line_final=$(echo "$_processed_line" | sed 's/\\[[:space:]]*$//' | sed '/^$/d')

        if [ -n "$_processed_line_final" ]; then
            echo "$_processed_line_final"
        fi
    done
}

# Dependencies assumed to be defined elsewhere in the script:
# fetch_file()
# extract_makefile_block()
# parse_packages_from_extracted_block()
# debug_log()
# color()
# get_message()
# CACHE_DIR (variable)
# TMP_DIR (variable, for mktemp fallback)

# ヘルパー関数: OpenWrtソースからデフォルトパッケージリストを生成し、指定ファイルに出力
# (v16スクリプトの主要ロジックをベースとする)
generate_default_package_list_from_source() {
    local output_file_path="$1"
    if [ -z "$output_file_path" ]; then
        debug_log "ERROR" "Output file path not provided to generate_default_package_list_from_source."
        return 1
    fi

    local _tmp_dir_generate # Function-local temporary directory variable
    if command -v mktemp >/dev/null; then
        _tmp_dir_generate=$(mktemp -d -p "${TMP_DIR:-/tmp}" "pkg_generate_defaults.XXXXXX") || {
            debug_log "ERROR" "Failed to create temp dir for default package generation."
            return 1
        }
    else
        local _tmp_dir_basename_generate
        _tmp_dir_basename_generate="pkg_generate_defaults_$$_$(date +%s)"
        _tmp_dir_generate="${TMP_DIR:-/tmp}/${_tmp_dir_basename_generate}"
        mkdir -p "$_tmp_dir_generate" || {
            debug_log "ERROR" "Failed to create temp dir %s for default package generation." "$_tmp_dir_generate"
            return 1
        }
    fi
    debug_log "DEBUG" "Temporary directory for default package generation: $_tmp_dir_generate"

    # Define local file paths within the temporary directory
    local gen_pkg_list_target_mk_basic_tmp="${_tmp_dir_generate}/pkg_target_mk_basic.txt"
    local gen_pkg_list_target_mk_router_additions_tmp="${_tmp_dir_generate}/pkg_target_mk_router_additions.txt"
    local gen_pkg_list_target_mk_direct_tmp="${_tmp_dir_generate}/pkg_target_mk_direct.txt"
    local gen_pkg_list_target_specific_tmp="${_tmp_dir_generate}/pkg_target_specific.txt"
    local gen_pkg_list_device_specific_tmp="${_tmp_dir_generate}/pkg_device_specific.txt"
    local gen_combined_list_for_processing_tmp="${_tmp_dir_generate}/combined_for_processing.txt"
    # Output will be written directly to $output_file_path after processing

    # --- Configuration (mirrors v16 logic) ---
    local gen_device_profile_name_val 
    local gen_assumed_device_type_val="router"

    if [ -f "/etc/board.json" ] && command -v jsonfilter > /dev/null; then
        local gen_board_name_raw_val
        gen_board_name_raw_val=$(jsonfilter -e '@.model.id' < /etc/board.json 2>/dev/null)
        gen_device_profile_name_val=$(echo "$gen_board_name_raw_val" | sed 's/\//_/g' | tr '[:upper:]' '[:lower:]')
        if [ -z "$gen_device_profile_name_val" ]; then
            gen_device_profile_name_val="radxa_zero-3w"
        fi
    else
        gen_device_profile_name_val="radxa_zero-3w"
    fi
    debug_log "INFO" "Using device_profile_name='$gen_device_profile_name_val' for default pkg list generation."

    local gen_distrib_target_val=""
    local gen_distrib_release_val=""
    local gen_openwrt_git_branch_val="main"

    if [ -f "/etc/openwrt_release" ]; then
        gen_distrib_target_val=$(. /etc/openwrt_release >/dev/null 2>&1; echo "$DISTRIB_TARGET")
        gen_distrib_release_val=$(. /etc/openwrt_release >/dev/null 2>&1; echo "$DISTRIB_RELEASE")
        if [ -z "$gen_distrib_target_val" ]; then 
             gen_distrib_target_val=$(grep '^DISTRIB_TARGET=' "/etc/openwrt_release" 2>/dev/null | cut -d "'" -f 2)
             gen_distrib_release_val=$(grep '^DISTRIB_RELEASE=' "/etc/openwrt_release" 2>/dev/null | cut -d "'" -f 2)
        fi
    else
        gen_distrib_target_val="rockchip/armv8"
    fi

    if echo "$gen_distrib_release_val" | grep -q "SNAPSHOT"; then
        gen_openwrt_git_branch_val="main"
    elif echo "$gen_distrib_release_val" | grep -Eq '^[0-9]+\.[0-9]+'; then
        local gen_major_minor_version_val
        gen_major_minor_version_val=$(echo "$gen_distrib_release_val" | awk -F'.' '{print $1"."$2}')
        gen_openwrt_git_branch_val="openwrt-${gen_major_minor_version_val}"
    else
        gen_openwrt_git_branch_val="main"
    fi
    debug_log "INFO" "Using OpenWrt Git branch: $gen_openwrt_git_branch_val for default pkg list generation."

    local gen_target_base_val
    local gen_image_target_suffix_val
    gen_target_base_val=$(echo "$gen_distrib_target_val" | cut -d'/' -f1)
    gen_image_target_suffix_val=$(echo "$gen_distrib_target_val" | cut -d'/' -f2)

    if [ -z "$gen_target_base_val" ] || [ -z "$gen_image_target_suffix_val" ] || [ "$gen_target_base_val" = "$gen_distrib_target_val" ]; then
        if [ "$gen_distrib_target_val" = "rockchip/armv8" ]; then
            gen_target_base_val="rockchip"
            gen_image_target_suffix_val="armv8"
        else
            debug_log "ERROR" "Cannot proceed with default package generation without valid target paths."
            rm -rf "$_tmp_dir_generate"
            return 1
        fi
    fi
    debug_log "INFO" "Using target paths for default pkg list generation: base='$gen_target_base_val', suffix='$gen_image_target_suffix_val'"

    for f_gen in "$gen_pkg_list_target_mk_basic_tmp" "$gen_pkg_list_target_mk_router_additions_tmp" "$gen_pkg_list_target_mk_direct_tmp" \
             "$gen_pkg_list_target_specific_tmp" "$gen_pkg_list_device_specific_tmp" "$gen_combined_list_for_processing_tmp"; do
        true > "$f_gen"
    done
    true > "$output_file_path" # Ensure output file is initially empty

    local gen_success_flag=0 

    # Tier 1 (generation)
    local gen_target_mk_file_val="${_tmp_dir_generate}/target.mk.download"
    local gen_target_mk_url_val="https://raw.githubusercontent.com/openwrt/openwrt/${gen_openwrt_git_branch_val}/include/target.mk"
    if fetch_file "$gen_target_mk_url_val" "$gen_target_mk_file_val"; then
        local gen_basic_block_content_val
        gen_basic_block_content_val=$(extract_makefile_block "$gen_target_mk_file_val" "DEFAULT_PACKAGES.basic" ":=")
        if [ -n "$gen_basic_block_content_val" ]; then parse_packages_from_extracted_block "$gen_basic_block_content_val" "DEFAULT_PACKAGES.basic" ":=" > "$gen_pkg_list_target_mk_basic_tmp"; fi
        if [ ! -s "$gen_pkg_list_target_mk_basic_tmp" ]; then
            local gen_basic_block_content_fallback_val
            gen_basic_block_content_fallback_val=$(extract_makefile_block "$gen_target_mk_file_val" "DEFAULT_PACKAGES" ":=")
            if [ -n "$gen_basic_block_content_fallback_val" ]; then parse_packages_from_extracted_block "$gen_basic_block_content_fallback_val" "DEFAULT_PACKAGES" ":=" > "$gen_pkg_list_target_mk_basic_tmp"; fi
        fi
        local gen_router_additions_block_content_val
        gen_router_additions_block_content_val=$(extract_makefile_block "$gen_target_mk_file_val" "DEFAULT_PACKAGES.${gen_assumed_device_type_val}" ":=")
        if [ -n "$gen_router_additions_block_content_val" ]; then parse_packages_from_extracted_block "$gen_router_additions_block_content_val" "DEFAULT_PACKAGES.${gen_assumed_device_type_val}" ":=" > "$gen_pkg_list_target_mk_router_additions_tmp"; fi
        local gen_direct_block_content_val
        gen_direct_block_content_val=$(extract_makefile_block "$gen_target_mk_file_val" "DEFAULT_PACKAGES" "+=")
        if [ -n "$gen_direct_block_content_val" ]; then parse_packages_from_extracted_block "$gen_direct_block_content_val" "DEFAULT_PACKAGES" "+=" > "$gen_pkg_list_target_mk_direct_tmp"; fi
    else
        debug_log "ERROR" "Failed to process include/target.mk for default pkg list generation. Tier 1 skipped."
        gen_success_flag=1 
    fi

    # Tier 2 (generation)
    if [ "$gen_success_flag" -eq 0 ] && [ -n "$gen_target_base_val" ]; then
        local gen_target_specific_mk_file_val="${_tmp_dir_generate}/target_${gen_target_base_val}.mk.download"
        local gen_target_specific_mk_url_val="https://raw.githubusercontent.com/openwrt/openwrt/${gen_openwrt_git_branch_val}/target/linux/${gen_target_base_val}/Makefile"
        if fetch_file "$gen_target_specific_mk_url_val" "$gen_target_specific_mk_file_val"; then
            local gen_ts_block_content_val
            gen_ts_block_content_val=$(extract_makefile_block "$gen_target_specific_mk_file_val" "DEFAULT_PACKAGES" "+=")
            if [ -n "$gen_ts_block_content_val" ]; then parse_packages_from_extracted_block "$gen_ts_block_content_val" "DEFAULT_PACKAGES" "+=" > "$gen_pkg_list_target_specific_tmp"; fi
        else
            debug_log "WARNING" "Failed to process target/linux/$gen_target_base_val/Makefile for default pkg list generation. Tier 2 might be incomplete."
        fi
    elif [ -z "$gen_target_base_val" ]; then
         debug_log "WARNING" "target_base is empty. Skipping Tier 2 for default pkg list generation."
    fi

    # Tier 3 (generation)
    if [ "$gen_success_flag" -eq 0 ] && [ -n "$gen_target_base_val" ] && [ -n "$gen_image_target_suffix_val" ]; then
        local gen_device_specific_mk_file_val="${_tmp_dir_generate}/image_${gen_image_target_suffix_val}.mk.download"
        local gen_device_profile_block_tmp_val="${_tmp_dir_generate}/device_profile_block.txt"
        local gen_device_specific_mk_url_val="https://raw.githubusercontent.com/openwrt/openwrt/${gen_openwrt_git_branch_val}/target/linux/${gen_target_base_val}/image/${gen_image_target_suffix_val}.mk"
        if fetch_file "$gen_device_specific_mk_url_val" "$gen_device_specific_mk_file_val"; then
            awk -v profile="Device/${gen_device_profile_name_val}" \
                'BEGIN{found=0} $2==profile && $1=="define"{found=1} found{print} /^[[:space:]]*endef[[:space:]]*$/&&found{found=0}' \
                "$gen_device_specific_mk_file_val" > "$gen_device_profile_block_tmp_val"
            if [ -s "$gen_device_profile_block_tmp_val" ]; then
                local gen_device_pkgs_block_content_val
                gen_device_pkgs_block_content_val=$(extract_makefile_block "$gen_device_profile_block_tmp_val" "DEVICE_PACKAGES" ":=")
                if [ -z "$gen_device_pkgs_block_content_val" ]; then gen_device_pkgs_block_content_val=$(extract_makefile_block "$gen_device_profile_block_tmp_val" "DEVICE_PACKAGES" "+="); fi
                if [ -n "$gen_device_pkgs_block_content_val" ]; then
                    parse_packages_from_extracted_block "$gen_device_pkgs_block_content_val" "DEVICE_PACKAGES" ":=" > "$gen_pkg_list_device_specific_tmp"
                    if [ ! -s "$gen_pkg_list_device_specific_tmp" ]; then parse_packages_from_extracted_block "$gen_device_pkgs_block_content_val" "DEVICE_PACKAGES" "+=" > "$gen_pkg_list_device_specific_tmp"; fi
                fi
            else
                 debug_log "WARNING" "Could not extract 'define Device/$gen_device_profile_name_val' block for default pkg list generation."
            fi
        else
            debug_log "WARNING" "Failed to process image specific Makefile for Tier 3 for default pkg list generation."
        fi
    elif [ -z "$gen_target_base_val" ] || [ -z "$gen_image_target_suffix_val" ]; then
        debug_log "WARNING" "target_base or image_target_suffix is empty. Skipping Tier 3 for default pkg list generation."
    fi

    # Combine (generation)
    true > "$gen_combined_list_for_processing_tmp"
    for list_file_gen in "$gen_pkg_list_target_mk_basic_tmp" "$gen_pkg_list_target_mk_router_additions_tmp" "$gen_pkg_list_target_mk_direct_tmp" \
                     "$gen_pkg_list_target_specific_tmp" "$gen_pkg_list_device_specific_tmp"; do
        if [ -s "$list_file_gen" ]; then cat "$list_file_gen" >> "$gen_combined_list_for_processing_tmp"; fi
    done

    if [ -s "$gen_combined_list_for_processing_tmp" ]; then
        sort -u "$gen_combined_list_for_processing_tmp" | sed '/^$/d' > "$output_file_path" # Output to the specified file
        debug_log "INFO" "Default package list successfully generated into $output_file_path."
    else
        debug_log "WARNING" "No default packages could be extracted from source. Output file $output_file_path will be empty."
        true > "$output_file_path" # Ensure output file is at least an empty file
    fi
    
    rm -rf "$_tmp_dir_generate" # Cleanup generation temp dir
    return "$gen_success_flag"
}


# メイン関数: apkで明示的にインストールされたパッケージを取得し、デフォルトと比較
get_installed_packages_apk() {
    debug_log "DEBUG" "Function called: get_installed_packages_apk"
    
    local apk_world_list_file_val 
    local default_pkgs_list_file_val 

    # Ensure CACHE_DIR is defined and accessible for temporary diff files
    if [ -z "$CACHE_DIR" ] || ! mkdir -p "$CACHE_DIR" 2>/dev/null || [ ! -w "$CACHE_DIR" ]; then # Try to create CACHE_DIR if it doesn't exist
        debug_log "WARNING" "CACHE_DIR ('$CACHE_DIR') is not usable. Using /tmp for temporary diff files."
        local tmp_diff_dir="/tmp"
        apk_world_list_file_val="${tmp_diff_dir}/.apk_world_list_diff.tmp"
        default_pkgs_list_file_val="${tmp_diff_dir}/.default_pkgs_list_diff.tmp"
    else
        apk_world_list_file_val="${CACHE_DIR}/.apk_world_list_diff.tmp"
        default_pkgs_list_file_val="${CACHE_DIR}/.default_pkgs_list_diff.tmp"
    fi
    
    # 1. /etc/apk/world からリスト取得 (リストA)
    if [ -f "/etc/apk/world" ] && [ -s "/etc/apk/world" ]; then
        debug_log "INFO" "Reading /etc/apk/world..."
        sort "/etc/apk/world" > "$apk_world_list_file_val"
    else
        debug_log "INFO" "/etc/apk/world not found or is empty."
        true > "$apk_world_list_file_val" 
    fi

    # 2. ソースからデフォルトパッケージリストを生成し、ファイルに保存 (リストB)
    printf "\n%s\n" "$(color cyan "$(get_message "MSG_FETCHING_DEFAULT_PACKAGES_FROM_SOURCE")")"
    if generate_default_package_list_from_source "$default_pkgs_list_file_val"; then
        debug_log "INFO" "Default package list from source has been generated into $default_pkgs_list_file_val."
    else
        debug_log "ERROR" "Failed to generate default package list from source. Comparison will be incomplete."
        # Ensure the file exists and is empty if generation failed critically
        if [ ! -f "$default_pkgs_list_file_val" ]; then 
             true > "$default_pkgs_list_file_val"
        elif [ ! -s "$default_pkgs_list_file_val" ]; then # If it exists but is empty due to no pkgs found
             debug_log "INFO" "Default package list from source was empty."
        fi
    fi

    if [ ! -s "$apk_world_list_file_val" ] && [ ! -s "$default_pkgs_list_file_val" ]; then
        printf "%s\n" "$(color yellow "$(get_message "MSG_APK_WORLD_AND_DEFAULTS_EMPTY")")"
        rm -f "$apk_world_list_file_val" "$default_pkgs_list_file_val" 
        return 0
    fi
    
    # 3. 差分表示
    printf "\n%s\n" "$(color green "$(get_message "MSG_PACKAGE_COMPARISON_TITLE")")"

    printf "\n%s\n" "$(color yellow "$(get_message "MSG_PACKAGES_ONLY_IN_APK_WORLD_DESC")")"
    local only_in_apk_world_val
    if [ -s "$apk_world_list_file_val" ]; then 
        only_in_apk_world_val=$(grep -vxFf "$default_pkgs_list_file_val" "$apk_world_list_file_val")
    else
        only_in_apk_world_val=""
    fi

    if [ -n "$only_in_apk_world_val" ]; then
        echo "$only_in_apk_world_val"
    else
        printf "%s\n" "$(get_message "MSG_NONE")"
    fi

    printf "\n%s\n" "$(color yellow "$(get_message "MSG_PACKAGES_ONLY_IN_DEFAULTS_DESC")")"
    local only_in_defaults_val
    if [ -s "$default_pkgs_list_file_val" ]; then 
        only_in_defaults_val=$(grep -vxFf "$apk_world_list_file_val" "$default_pkgs_list_file_val")
    else
        only_in_defaults_val=""
    fi
    
    if [ -n "$only_in_defaults_val" ]; then
        echo "$only_in_defaults_val"
    else
        printf "%s\n" "$(get_message "MSG_NONE")"
    fi
    
    # Cleanup diff temp files
    rm -f "$apk_world_list_file_val" "$default_pkgs_list_file_val" 
    return 0
}

# インストール後のパッケージリストを表示 (入口関数)
check_install_list() {
    printf "\n%s\n" "$(color blue "$(get_message "MSG_PACKAGES_INSTALLED_AFTER_FLASHING")")"

    # パッケージマネージャの種類を確認 (キャッシュまたは動的検出)
    # この例では、PACKAGE_MANAGER変数が事前に設定されていることを期待
    if [ -z "$PACKAGE_MANAGER" ]; then
        if [ -f "${CACHE_DIR}/package_manager.ch" ]; then
            PACKAGE_MANAGER=$(cat "${CACHE_DIR}/package_manager.ch")
            debug_log "DEBUG" "Package manager read from cache: $PACKAGE_MANAGER"
        elif command -v opkg >/dev/null 2>&1; then
            PACKAGE_MANAGER="opkg"
            debug_log "DEBUG" "Detected opkg package manager."
        elif command -v apk >/dev/null 2>&1; then
            PACKAGE_MANAGER="apk"
            debug_log "DEBUG" "Detected apk package manager."
        else
            debug_log "ERROR" "Could not determine package manager."
            PACKAGE_MANAGER="unknown" # or handle error appropriately
        fi
        # 必要であれば、検出結果をキャッシュに保存
        # echo "$PACKAGE_MANAGER" > "${CACHE_DIR}/package_manager.ch"
    fi


    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        debug_log "INFO" "Using opkg to list user-installed packages (post-flash)."
        get_installed_packages_opkg
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        debug_log "INFO" "Using apk to list explicitly installed packages."
        get_installed_packages_apk
    else
        debug_log "ERROR" "Unknown or undetermined package manager: '$PACKAGE_MANAGER'. Cannot list user-installed packages."
        return 1 # Indicate an error or issue
    fi

    return 0 
}

# メイン処理
package_main() {
    debug_log "DEBUG" "package_main called. PACKAGE_INSTALL_MODE is currently: '$PACKAGE_INSTALL_MODE'"

    if [ "$PACKAGE_INSTALL_MODE" = "auto" ]; then
        # common-country.sh の confirm 関数を使用する
        # メッセージキーは適切なものを get_message で取得するか、直接指定
        # 例: "MSG_CONFIRM_AUTO_INSTALL_ALL" のようなキーを messages.db に定義
        # ここでは仮のメッセージキーを使用
        if ! confirm "MSG_PACKAGE_INSTALL_AUTO" "yn"; then
            debug_log "DEBUG" "User cancelled automatic package installation."
            printf "%s\n" "$(get_message "MSG_PACKAGE_INSTALL_CANCELLED")" # キャンセルメッセージ
            return 1 # 中断して終了
        fi
        debug_log "DEBUG" "User confirmed automatic package installation."
    fi
    
    # OSバージョンに基づいたパッケージインストール
    install_packages_version
    
    # USB関連パッケージのインストール
    install_usb_packages

    # 自動インストール成功時のメッセージ (オプション)
    if [ "$PACKAGE_INSTALL_MODE" = "auto" ]; then
        printf "%s\n" "$(get_message "MSG_PACKAGE_INSTALL_COMPLETED")" # 完了メッセージ
    fi
    return 0 # 正常終了
}

# スクリプトの実行
# package_main "$@"
