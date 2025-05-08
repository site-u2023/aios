#!/bin/sh

SCRIPT_VERSION="2025.05.08-02-00"

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

# Dependencies assumed to be defined elsewhere in the script:
# debug_log() - Assumed to be a global function like: debug_log "LEVEL" "message"
# CACHE_DIR   - Assumed to be a global variable (e.g., "/tmp/aios/cache")
# TMP_DIR     - Assumed to be a global variable (e.g., "/tmp")

get_installed_packages_apk() {
    debug_log "DEBUG" "Function called: get_installed_packages_apk"

    # --- Start: APK Default Package Extraction Logic (Based on V16) ---
    
    # --- APK Helper Function: apk_fetch_file (V16 compatible) ---
    apk_fetch_file() {
        local _url_orig="$1"
        local _output_file="$2"
        local _cache_bust_param
        local _url_with_cb
        local _ret_code
        local _wget_base_cmd="wget -qO" # Base wget command

        _cache_bust_param="_cb=$(date +%s)"
        _url_with_cb="${_url_orig}?${_cache_bust_param}"
        
        debug_log "DEBUG" "APK: Downloading ${_url_with_cb} to ${_output_file}"
        # V16に合わせて --no-check-certificate を明示
        if $_wget_base_cmd "$_output_file" --timeout=30 --no-check-certificate "$_url_with_cb"; then 
            if [ ! -s "$_output_file" ]; then
                debug_log "DEBUG" "APK: Downloaded file ${_output_file} is empty. URL: ${_url_with_cb}" # Changed ERROR to DEBUG as per rule
                return 1
            fi
            return 0
        else
            _ret_code=$?
            debug_log "DEBUG" "APK: wget failed for ${_url_with_cb} (exit code: ${_ret_code})" # Changed ERROR to DEBUG
            return 1
        fi
    }

    # --- APK Helper Function: apk_extract_makefile_block (V16 compatible) ---
    apk_extract_makefile_block() {
        local _file_path="$1"
        local _var_name_raw="$2"
        local _operator_raw="$3"
        local _var_name_for_regex
        local _operator_for_regex
        local _full_regex
    
        _var_name_for_regex=$(echo "$_var_name_raw" | sed 's/\./\\./g') 
        _operator_for_regex=""
        if [ "$_operator_raw" = "+=" ]; then _operator_for_regex='\\+[[:space:]]*=';
        elif [ "$_operator_raw" = ":=" ]; then _operator_for_regex=':[[:space:]]*=';
        elif [ "$_operator_raw" = "?=" ]; then _operator_for_regex='\\?[[:space:]]*='; 
        else _operator_for_regex=$(echo "$_operator_raw" | sed 's/[+?*.:\[\]^${}\\|=()]/\\&/g'); fi
    
        _full_regex="^[[:space:]]*${_var_name_for_regex}[[:space:]]*${_operator_for_regex}"
    
        awk -v pattern="${_full_regex}" \
        'BEGIN{state=0}
         {
            if (state == 0) {
                if ($0 ~ pattern) {
                    state = 1;
                    current_line = $0;
                    sub(/[[:space:]]*#.*$/, "", current_line); 
                    print current_line;
                    if (!(current_line ~ /\\$/)) { 
                        state = 0;
                    }
                }
            } else { 
                current_line = $0;
                sub(/[[:space:]]*#.*$/, "", current_line); 
                print current_line;
                if (!(current_line ~ /\\$/)) { 
                    state = 0;
                }
            }
         }' "$_file_path"
    }

    # --- APK Helper Function: apk_parse_packages_from_extracted_block (V16 compatible) ---
    apk_parse_packages_from_extracted_block() {
        local _block_text="$1"
        local _var_to_strip_orig="$2" 
        local _op_to_strip="$3"  
        local _first_line_processed=0 # Matched V16
        local _line 
        local _processed_line 
        local _processed_line_final 
        local _var_esc_awk 
        local _op_esc_awk 
        local _var_re_str_for_awk 

        if [ -z "$_block_text" ]; then return; fi
    
        echo "$_block_text" | while IFS= read -r _line || [ -n "$_line" ]; do
            _processed_line="$_line"
    
            _var_esc_awk=$(echo "$_var_to_strip_orig" | sed 's/\./\\./g')
            _op_esc_awk=""
            if [ "$_op_to_strip" = "+=" ]; then _op_esc_awk='\\+[[:space:]]*=';
            elif [ "$_op_to_strip" = ":=" ]; then _op_esc_awk=':[[:space:]]*=';
            elif [ "$_op_to_strip" = "?=" ]; then _op_esc_awk='\\?[[:space:]]*=';
            else _op_esc_awk=$(echo "$_op_to_strip" | sed 's/[+?*.:\[\]^${}\\|=()]/\\&/g'); fi
            _var_re_str_for_awk="^[[:space:]]*${_var_esc_awk}[[:space:]]*${_op_esc_awk}[[:space:]]*"
    
            # Renamed awk internal variable to avoid conflict with shell's _first_line_processed
            _processed_line=$(echo "$_processed_line" | awk \
                -v var_re_str="$_var_re_str_for_awk" \
                -v var_to_filter_exact="$_var_to_strip_orig" \
                -v op_to_filter_exact="$_op_to_strip" \
                -v is_first_line_in_awk="$_first_line_processed" \
                '{
                    sub(/[[:space:]]*#.*$/, "");
                    if (is_first_line_in_awk == 0) { # Use the awk variable here
                        sub(var_re_str, ""); 
                    }
                    while (match($0, /\$\([^)]*\)/)) {
                        $0 = substr($0, 1, RSTART-1) substr($0, RSTART+RLENGTH);
                    }
                    gsub(/^[[:space:]]+|[[:space:]]+$/, ""); 
                    if (NF > 0) {
                        for (i=1; i<=NF; i++) {
                            current_field = $i;
                            if (current_field == var_to_filter_exact) continue;
                            current_op_no_space_for_awk = op_to_filter_exact; 
                            gsub(/[[:space:]]/, "", current_op_no_space_for_awk);
                            current_field_no_space_for_awk = current_field; 
                            gsub(/[[:space:]]/, "", current_field_no_space_for_awk);
                            if (current_op_no_space_for_awk != "" && current_field_no_space_for_awk == current_op_no_space_for_awk) continue;
                            if (current_field != "" && current_field != "\\" && current_field !~ /^(\(|\))$/ && current_field !~ /^(=|\+=|:=|\?=)$/ && current_field !~ /^\$\(/ ) {
                                print current_field;
                            }
                        }
                    }
                }')
            
            if [ "$_first_line_processed" -eq 0 ]; then # Shell variable update
                _first_line_processed=1
            fi
            
            _processed_line_final=$(echo "$_processed_line" | sed 's/\\[[:space:]]*$//' | sed '/^$/d')
    
            if [ -n "$_processed_line_final" ]; then
                echo "$_processed_line_final"
            fi
        done
    }

    # --- APK Temporary files and directory setup (V16 compatible names where possible) ---
    local apk_tmp_dir
    local apk_tmp_dir_basename # V16: tmp_dir_basename
    local apk_pkg_list_target_mk_basic_tmp # V16: pkg_list_target_mk_basic_tmp
    local apk_pkg_list_target_mk_router_additions_tmp # V16: pkg_list_target_mk_router_additions_tmp
    local apk_pkg_list_target_mk_direct_tmp # V16: pkg_list_target_mk_direct_tmp
    local apk_pkg_list_target_specific_tmp # V16: pkg_list_target_specific_tmp
    local apk_pkg_list_device_specific_tmp # V16: pkg_list_device_specific_tmp
    local apk_final_extracted_list_sorted_tmp # V16: final_extracted_list_sorted_tmp
    local apk_combined_list_for_processing_tmp # New name for clarity, V16 used combined_list_for_processing_tmp
    local apk_f 

    if command -v mktemp >/dev/null; then
        apk_tmp_dir=$(mktemp -d -p "${TMP_DIR:-/tmp}" "apk_pkg_extract.XXXXXX") || { # V16 used "pkg_extract.XXXXXX"
            debug_log "DEBUG" "APK: Failed to create temp dir using mktemp for default package extraction."
            return 1
        }
    else
        apk_tmp_dir_basename="apk_pkg_extract_$$_$(date +%s)" # V16 used "pkg_extract_..."
        apk_tmp_dir="${TMP_DIR:-/tmp}/${apk_tmp_dir_basename}"
        mkdir -p "$apk_tmp_dir" || {
            debug_log "DEBUG" "APK: Failed to create temp dir ${apk_tmp_dir} for default package extraction."
            return 1
        }
    fi
    debug_log "DEBUG" "APK: Temporary directory for default package extraction: $apk_tmp_dir"

    apk_pkg_list_target_mk_basic_tmp="${apk_tmp_dir}/pkg_target_mk_basic.txt"
    apk_pkg_list_target_mk_router_additions_tmp="${apk_tmp_dir}/pkg_target_mk_router_additions.txt"
    apk_pkg_list_target_mk_direct_tmp="${apk_tmp_dir}/pkg_target_mk_direct.txt"
    apk_pkg_list_target_specific_tmp="${apk_tmp_dir}/pkg_target_specific.txt"
    apk_pkg_list_device_specific_tmp="${apk_tmp_dir}/pkg_device_specific.txt"
    apk_final_extracted_list_sorted_tmp="${apk_tmp_dir}/final_extracted_sorted.txt" 
    apk_combined_list_for_processing_tmp="${apk_tmp_dir}/combined_for_processing.txt" # Matched V16 name

    for apk_f in "$apk_pkg_list_target_mk_basic_tmp" "$apk_pkg_list_target_mk_router_additions_tmp" \
                  "$apk_pkg_list_target_mk_direct_tmp" "$apk_pkg_list_target_specific_tmp" \
                  "$apk_pkg_list_device_specific_tmp" "$apk_final_extracted_list_sorted_tmp" \
                  "$apk_combined_list_for_processing_tmp"; do
        true > "$apk_f"
    done

    # --- APK Configuration (V16 compatible names where possible) ---
    local apk_device_profile_name # V16: DEVICE_PROFILE_NAME (global)
    local apk_assumed_device_type="router" # V16: ASSUMED_DEVICE_TYPE (global)
    local apk_distrib_target="" # V16: distrib_target (global)
    local apk_distrib_release="" # V16: distrib_release (global)
    local apk_openwrt_git_branch="main" # V16: openwrt_git_branch (global)
    local apk_target_base # V16: target_base (global)
    local apk_image_target_suffix # V16: image_target_suffix (global)
    
    local apk_target_mk_file # V16: target_mk_file
    local apk_target_mk_url
    local apk_basic_block_content
    local apk_basic_block_content_fallback
    local apk_router_additions_block_content
    local apk_direct_block_content
    local apk_target_specific_mk_file # V16: target_specific_mk_file
    local apk_target_specific_mk_url
    local apk_ts_block_content
    local apk_device_specific_mk_file # V16: device_specific_mk_file
    local apk_device_profile_block_tmp # V16: device_profile_block_tmp
    local apk_device_specific_mk_url
    local apk_device_pkgs_block_content
    local apk_list_file # V16: list_file

    # Get DEVICE_PROFILE_NAME (V16 logic, adapted)
    if [ -f "/etc/board.json" ] && command -v jsonfilter > /dev/null; then
        local _apk_board_name_raw # V16: board_name_raw
        _apk_board_name_raw=$(jsonfilter -e '@.model.id' < /etc/board.json 2>/dev/null)
        # V16 logic for sanitization (no comma replacement)
        apk_device_profile_name=$(echo "$_apk_board_name_raw" | sed 's/\//_/g' | tr '[:upper:]' '[:lower:]')
        if [ -z "$apk_device_profile_name" ]; then
            debug_log "DEBUG" "APK: Could not determine DEVICE_PROFILE_NAME from /etc/board.json, using default 'radxa_zero_3w'."
            apk_device_profile_name="radxa_zero_3w" 
        else
            debug_log "DEBUG" "APK: Using DEVICE_PROFILE_NAME='$apk_device_profile_name' (V16 sanitized) from /etc/board.json"
        fi
    else
        debug_log "DEBUG" "APK: /etc/board.json or jsonfilter not found, using default DEVICE_PROFILE_NAME='radxa_zero_3w'."
        apk_device_profile_name="radxa_zero_3w" 
    fi

    # Read release information (V16 logic, adapted)
    if [ -f "/etc/openwrt_release" ]; then
        # Source in a subshell to avoid polluting current shell's global variables for DISTRIB_*
        apk_distrib_target=$(. /etc/openwrt_release >/dev/null 2>&1; echo "$DISTRIB_TARGET")
        apk_distrib_release=$(. /etc/openwrt_release >/dev/null 2>&1; echo "$DISTRIB_RELEASE")
        # Fallback parsing if sourcing fails to set them (e.g. strict modes prevent it)
        if [ -z "$apk_distrib_target" ]; then apk_distrib_target=$(grep '^DISTRIB_TARGET=' "/etc/openwrt_release" 2>/dev/null | cut -d "'" -f 2); fi
        if [ -z "$apk_distrib_release" ]; then apk_distrib_release=$(grep '^DISTRIB_RELEASE=' "/etc/openwrt_release" 2>/dev/null | cut -d "'" -f 2); fi
        debug_log "DEBUG" "APK: Read from /etc/openwrt_release: DISTRIB_TARGET='$apk_distrib_target', DISTRIB_RELEASE='$apk_distrib_release'"
    else
        debug_log "DEBUG" "APK: /etc/openwrt_release not found. Using default branch 'main' and target 'rockchip/armv8'."
        apk_distrib_target="rockchip/armv8"
        # apk_distrib_release remains empty, apk_openwrt_git_branch remains "main"
    fi

    # Determine OpenWrt Git branch (V16 logic, adapted)
    if echo "$apk_distrib_release" | grep -q "SNAPSHOT"; then
        apk_openwrt_git_branch="main"
    elif echo "$apk_distrib_release" | grep -Eq '^[0-9]+\.[0-9]+'; then
        local _apk_major_minor_version # V16: major_minor_version
        _apk_major_minor_version=$(echo "$apk_distrib_release" | awk -F'.' '{print $1"."$2}')
        apk_openwrt_git_branch="openwrt-$_apk_major_minor_version"
    else
        debug_log "DEBUG" "APK: DISTRIB_RELEASE ('$apk_distrib_release') is not SNAPSHOT or a recognized version, using git branch 'main'."
        apk_openwrt_git_branch="main"
    fi
    debug_log "DEBUG" "APK: Using OpenWrt Git branch: $apk_openwrt_git_branch"

    # Split DISTRIB_TARGET (V16 logic, adapted)
    apk_target_base=$(echo "$apk_distrib_target" | cut -d'/' -f1)
    apk_image_target_suffix=$(echo "$apk_distrib_target" | cut -d'/' -f2)

    if [ -z "$apk_target_base" ] || [ -z "$apk_image_target_suffix" ] || [ "$apk_target_base" = "$apk_distrib_target" ]; then
        debug_log "DEBUG" "APK: Could not reliably determine target_base/image_target_suffix from DISTRIB_TARGET: '$apk_distrib_target'."
        if [ "$apk_distrib_target" = "rockchip/armv8" ]; then # V16 fallback condition
            debug_log "DEBUG" "APK: Falling back to target_base='rockchip', image_target_suffix='armv8'."
            apk_target_base="rockchip"
            apk_image_target_suffix="armv8"
        else
            debug_log "DEBUG" "APK: Critical - Cannot proceed without valid target paths. Exiting default package extraction part."
            rm -rf "$apk_tmp_dir" 
            return 1 
        fi
    fi
    debug_log "DEBUG" "APK: Using target paths: target_base='$apk_target_base', image_target_suffix='$apk_image_target_suffix'"

    # --- APK Tier 1: Global/Basic packages (V16 logic, adapted) ---
    debug_log "DEBUG" "APK: --- Tier 1: Processing include/target.mk ---"
    apk_target_mk_file="${apk_tmp_dir}/target.mk.download"
    apk_target_mk_url="https://raw.githubusercontent.com/openwrt/openwrt/${apk_openwrt_git_branch}/include/target.mk"
    if apk_fetch_file "$apk_target_mk_url" "$apk_target_mk_file"; then
        apk_basic_block_content=$(apk_extract_makefile_block "$apk_target_mk_file" "DEFAULT_PACKAGES.basic" ":=")
        if [ -n "$apk_basic_block_content" ]; then
            apk_parse_packages_from_extracted_block "$apk_basic_block_content" "DEFAULT_PACKAGES.basic" ":=" > "$apk_pkg_list_target_mk_basic_tmp"
        fi
        if [ ! -s "$apk_pkg_list_target_mk_basic_tmp" ]; then 
            apk_basic_block_content_fallback=$(apk_extract_makefile_block "$apk_target_mk_file" "DEFAULT_PACKAGES" ":=")
            if [ -n "$apk_basic_block_content_fallback" ]; then
                 apk_parse_packages_from_extracted_block "$apk_basic_block_content_fallback" "DEFAULT_PACKAGES" ":=" > "$apk_pkg_list_target_mk_basic_tmp"
            fi
        fi
        # V16 logs counts, adapting to debug_log
        if [ -s "$apk_pkg_list_target_mk_basic_tmp" ]; then debug_log "DEBUG" "APK: Parsed basic packages (Tier 1a) count: $(wc -l < "$apk_pkg_list_target_mk_basic_tmp")"; else debug_log "DEBUG" "APK: Basic packages list (Tier 1a) is empty."; fi


        apk_router_additions_block_content=$(apk_extract_makefile_block "$apk_target_mk_file" "DEFAULT_PACKAGES.${apk_assumed_device_type}" ":=")
        if [ -n "$apk_router_additions_block_content" ]; then
            apk_parse_packages_from_extracted_block "$apk_router_additions_block_content" "DEFAULT_PACKAGES.${apk_assumed_device_type}" ":=" > "$apk_pkg_list_target_mk_router_additions_tmp"
        fi
        if [ -s "$apk_pkg_list_target_mk_router_additions_tmp" ]; then debug_log "DEBUG" "APK: Parsed ${apk_assumed_device_type} specific additions (Tier 1b) count: $(wc -l < "$apk_pkg_list_target_mk_router_additions_tmp")"; else debug_log "DEBUG" "APK: Could not extract or parse block for DEFAULT_PACKAGES.${apk_assumed_device_type} (additions)."; fi

        apk_direct_block_content=$(apk_extract_makefile_block "$apk_target_mk_file" "DEFAULT_PACKAGES" "+=")
        if [ -n "$apk_direct_block_content" ]; then
            apk_parse_packages_from_extracted_block "$apk_direct_block_content" "DEFAULT_PACKAGES" "+=" > "$apk_pkg_list_target_mk_direct_tmp"
        fi
        if [ -s "$apk_pkg_list_target_mk_direct_tmp" ]; then debug_log "DEBUG" "APK: Parsed direct additions (Tier 1c) count: $(wc -l < "$apk_pkg_list_target_mk_direct_tmp")"; else debug_log "DEBUG" "APK: Could not extract or parse block for direct DEFAULT_PACKAGES += (Tier 1c)."; fi
    else
        debug_log "DEBUG" "APK: Failed to process include/target.mk. Skipping Tier 1."
    fi

    # --- APK Tier 2: Target-specific packages (V16 logic, adapted) ---
    debug_log "DEBUG" "APK: --- Tier 2: Processing target/linux/$apk_target_base/Makefile ---"
    apk_target_specific_mk_file="${apk_tmp_dir}/target_${apk_target_base}.mk.download"
    apk_target_specific_mk_url="https://raw.githubusercontent.com/openwrt/openwrt/${apk_openwrt_git_branch}/target/linux/${apk_target_base}/Makefile"
    if [ -n "$apk_target_base" ]; then 
        if apk_fetch_file "$apk_target_specific_mk_url" "$apk_target_specific_mk_file"; then
            apk_ts_block_content=$(apk_extract_makefile_block "$apk_target_specific_mk_file" "DEFAULT_PACKAGES" "+=")
            if [ -n "$apk_ts_block_content" ]; then
                apk_parse_packages_from_extracted_block "$apk_ts_block_content" "DEFAULT_PACKAGES" "+=" > "$apk_pkg_list_target_specific_tmp"
            fi
            if [ -s "$apk_pkg_list_target_specific_tmp" ]; then debug_log "DEBUG" "APK: Parsed target-specific additions (Tier 2) count: $(wc -l < "$apk_pkg_list_target_specific_tmp")"; else debug_log "DEBUG" "APK: Could not extract or parse block for target-specific DEFAULT_PACKAGES += (Tier 2)."; fi
        else
            debug_log "DEBUG" "APK: Failed to download or process target/linux/$apk_target_base/Makefile. Skipping Tier 2."
        fi
    else
        debug_log "DEBUG" "APK: target_base is empty. Skipping Tier 2."
    fi

    # --- APK Tier 3: Device-specific packages (V16 logic, adapted) ---
    debug_log "DEBUG" "APK: --- Tier 3: Processing target/linux/$apk_target_base/image/$apk_image_target_suffix.mk for device $apk_device_profile_name ---"
    apk_device_specific_mk_file="${apk_tmp_dir}/image_${apk_image_target_suffix}.mk.download"
    apk_device_profile_block_tmp="${apk_tmp_dir}/device_profile_block.txt"
    apk_device_specific_mk_url="https://raw.githubusercontent.com/openwrt/openwrt/${apk_openwrt_git_branch}/target/linux/${apk_target_base}/image/${apk_image_target_suffix}.mk"
    if [ -n "$apk_target_base" ] && [ -n "$apk_image_target_suffix" ]; then 
        if apk_fetch_file "$apk_device_specific_mk_url" "$apk_device_specific_mk_file"; then
            # V16 awk command for device profile block
            awk -v profile="Device/${apk_device_profile_name}" \
                'BEGIN{found=0} $2==profile && $1=="define"{found=1} found{print} /^[[:space:]]*endef[[:space:]]*$/&&found{found=0}' \
                "$apk_device_specific_mk_file" > "$apk_device_profile_block_tmp"

            if [ -s "$apk_device_profile_block_tmp" ]; then
                apk_device_pkgs_block_content=$(apk_extract_makefile_block "$apk_device_profile_block_tmp" "DEVICE_PACKAGES" ":=")
                if [ -z "$apk_device_pkgs_block_content" ]; then 
                     apk_device_pkgs_block_content=$(apk_extract_makefile_block "$apk_device_profile_block_tmp" "DEVICE_PACKAGES" "+=")
                fi

                if [ -n "$apk_device_pkgs_block_content" ]; then
                    apk_parse_packages_from_extracted_block "$apk_device_pkgs_block_content" "DEVICE_PACKAGES" ":=" > "$apk_pkg_list_device_specific_tmp"
                    if [ ! -s "$apk_pkg_list_device_specific_tmp" ]; then
                         apk_parse_packages_from_extracted_block "$apk_device_pkgs_block_content" "DEVICE_PACKAGES" "+=" > "$apk_pkg_list_device_specific_tmp"
                    fi
                fi
                if [ -s "$apk_pkg_list_device_specific_tmp" ]; then debug_log "DEBUG" "APK: Parsed device-specific packages (Tier 3) count: $(wc -l < "$apk_pkg_list_device_specific_tmp")"; else debug_log "DEBUG" "APK: Could not parse DEVICE_PACKAGES for $apk_device_profile_name."; fi
            else
                debug_log "DEBUG" "APK: Could not extract 'define Device/$apk_device_profile_name' block from $(basename "$apk_device_specific_mk_file")."
            fi
        else
            debug_log "DEBUG" "APK: Failed to download or process image specific Makefile for Tier 3."
        fi
    else
        debug_log "DEBUG" "APK: target_base or image_target_suffix is empty. Skipping Tier 3."
    fi

    # --- APK Combine all package lists (V16 logic, adapted) ---
    debug_log "DEBUG" "APK: --- Combining all package lists ---"
    # V16 ensures combined_list_for_processing_tmp is empty initially
    true > "$apk_combined_list_for_processing_tmp" 
    for apk_list_file in "$apk_pkg_list_target_mk_basic_tmp" "$apk_pkg_list_target_mk_router_additions_tmp" \
                     "$apk_pkg_list_target_mk_direct_tmp" "$apk_pkg_list_target_specific_tmp" \
                     "$apk_pkg_list_device_specific_tmp"; do
        if [ -s "$apk_list_file" ]; then 
            cat "$apk_list_file" >> "$apk_combined_list_for_processing_tmp"
        fi
    done

    debug_log "DEBUG" "APK: Finalizing extracted list of default packages."
    if [ -s "$apk_combined_list_for_processing_tmp" ]; then
        sort -u "$apk_combined_list_for_processing_tmp" | sed '/^$/d' > "$apk_final_extracted_list_sorted_tmp"
        # V16 prints the list here, adapting to a debug log
        debug_log "DEBUG" "APK: Default package list generated into '$apk_final_extracted_list_sorted_tmp'. Count: $(wc -l < "$apk_final_extracted_list_sorted_tmp")"
    else
        debug_log "DEBUG" "APK: No packages found or extracted from Makefiles. Default list will be empty."
        true > "$apk_final_extracted_list_sorted_tmp" # Create empty file for consistency (as in V16)
    fi
    # --- End: APK Default Package Extraction Logic ---


    # --- Start: Diff Logic (Comparing with /etc/apk/world) ---
    local diff_apk_world_list_file 
    local diff_default_pkgs_list_file 
    local diff_tmp_dir_base 

    if [ -n "$CACHE_DIR" ] && mkdir -p "$CACHE_DIR" 2>/dev/null && [ -w "$CACHE_DIR" ]; then
        diff_tmp_dir_base="$CACHE_DIR"
    else
        diff_tmp_dir_base="${TMP_DIR:-/tmp}" 
        debug_log "DEBUG" "CACHE_DIR ('$CACHE_DIR') is not usable for apk_world temp. Using '$diff_tmp_dir_base'."
    fi
    diff_apk_world_list_file="${diff_tmp_dir_base}/.apk_world_list_for_diff.tmp"
    
    diff_default_pkgs_list_file="$apk_final_extracted_list_sorted_tmp" # This is the output from V16 logic


    debug_log "DEBUG" "Diff: Reading /etc/apk/world for comparison..."
    if [ -f "/etc/apk/world" ] && [ -s "/etc/apk/world" ]; then
        sort "/etc/apk/world" > "$diff_apk_world_list_file"
        debug_log "DEBUG" "Diff: /etc/apk/world content sorted into '$diff_apk_world_list_file'."
    else
        debug_log "DEBUG" "Diff: /etc/apk/world not found or is empty."
        true > "$diff_apk_world_list_file" 
    fi

    if [ ! -s "$diff_apk_world_list_file" ] && [ ! -s "$diff_default_pkgs_list_file" ]; then
        printf "\nINFO: /etc/apk/world is empty AND no default packages were extracted. No comparison possible.\n" # User-facing info
        rm -f "$diff_apk_world_list_file" 
        rm -rf "$apk_tmp_dir" 
        return 0
    fi
    
    # --- Perform and Print Diff ---
    # User-facing headers, not using message keys as per instruction
    printf "\n--- Package Differences ---\n"

    printf "\nPackages ONLY in /etc/apk/world (User Installed/Explicitly Kept):\n"
    local diff_only_in_apk_world
    if [ -s "$diff_apk_world_list_file" ]; then 
        diff_only_in_apk_world=$(grep -vxFf "$diff_default_pkgs_list_file" "$diff_apk_world_list_file")
    else
        diff_only_in_apk_world=""
    fi

    if [ -n "$diff_only_in_apk_world" ]; then
        echo "$diff_only_in_apk_world"
    else
        printf "(None)\n"
    fi

    printf "\nPackages ONLY in Default OpenWrt Source List (Potentially Missing from /etc/apk/world):\n"
    local diff_only_in_defaults
    if [ -s "$diff_default_pkgs_list_file" ]; then 
        diff_only_in_defaults=$(grep -vxFf "$diff_apk_world_list_file" "$diff_default_pkgs_list_file")
    else
        diff_only_in_defaults=""
    fi
    
    if [ -n "$diff_only_in_defaults" ]; then
        echo "$diff_only_in_defaults"
    else
        printf "(None)\n"
    fi
    
    # Cleanup
    rm -f "$diff_apk_world_list_file" 
    rm -rf "$apk_tmp_dir" 
    debug_log "DEBUG" "Cleaned up temporary files for APK extraction and diff."
    
    debug_log "DEBUG" "Package difference check finished." # Changed INFO to DEBUG
    return 0
}

# インストール後のパッケージリストを表示 (入口関数)
check_install_list() {
    printf "\n%s\n" "$(color blue "$(get_message "MSG_PACKAGES_INSTALLED_AFTER_FLASHING")")"

    local cached_package_manager=""

    if [ -f "${CACHE_DIR}/package_manager.ch" ]; then
        cached_package_manager=$(cat "${CACHE_DIR}/package_manager.ch")
        debug_log "DEBUG" "Package manager read from cache: $cached_package_manager"
    else
        debug_log "DEBUG" "Package manager cache file (${CACHE_DIR}/package_manager.ch) not found. This might lead to an error."
        # return 1 # ここで即時リターンするかは要件によるが、今回は後続に任せる
    fi

    if [ "$cached_package_manager" = "opkg" ]; then
        debug_log "DEBUG" "Using opkg (from cache) to list user-installed packages (post-flash)."
        get_installed_packages_opkg
    elif [ "$cached_package_manager" = "apk" ]; then
        debug_log "DEBUG" "Using apk (from cache) to list explicitly installed packages."
        get_installed_packages_apk
    else
        debug_log "DEBUG" "Unknown or invalid package manager in cache: '$cached_package_manager'. Cannot list user-installed packages."
        return 1 # 不明な場合はエラー
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
