#!/bin/sh

SCRIPT_VERSION="2025.05.08-06-00"

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

check_install_list() {
    # Helper function to fetch remote content (v16: fetch_file logic)
    fetch_content() {
        local _url_orig="$1"; local _output_file="$2"; local _cache_bust_param="_cb=$(date +%s%N)"; local _url_with_cb="${_url_orig}?${_cache_bust_param}"
        if wget -qO "$_output_file" --timeout=30 --no-check-certificate "$_url_with_cb"; then
            if [ ! -s "$_output_file" ]; then debug_log "DEBUG" "ERROR: Downloaded file %s is empty. URL: %s" "$_output_file" "$_url_with_cb"; return 1; fi
            return 0
        else local ret_code=$?; debug_log "DEBUG" "ERROR: wget failed for %s (exit code: %s)" "$_url_with_cb" "$ret_code"; return 1; fi
    }

    # Helper function to extract a variable block from a Makefile (v16: extract_makefile_block logic)
    extract_makefile_var() {
        local _file_path="$1"; local _var_name_raw="$2"; local _operator_raw="$3"
        local _var_name_for_regex=$(echo "$_var_name_raw" | sed 's/\./\\./g')
        local _operator_for_regex=""
        if [ "$_operator_raw" = "+=" ]; then _operator_for_regex='\\+[[:space:]]*=';
        elif [ "$_operator_raw" = ":=" ]; then _operator_for_regex=':[[:space:]]*=';
        elif [ "$_operator_raw" = "?=" ]; then _operator_for_regex='\\?[[:space:]]*=';
        else _operator_for_regex=$(echo "$_operator_raw" | sed 's/[+?*.:\[\]^${}\\|=()]/\\&/g'); fi
        local _full_regex="^[[:space:]]*${_var_name_for_regex}[[:space:]]*${_operator_for_regex}"
        awk -v pattern="${_full_regex}" \
        'BEGIN{state=0}{if(state==0){if($0~pattern){state=1;current_line=$0;sub(/[[:space:]]*#.*$/,"",current_line);print current_line;if(!(current_line~/\\$/)){state=0}}}else{current_line=$0;sub(/[[:space:]]*#.*$/,"",current_line);print current_line;if(!(current_line~/\\$/)){state=0}}}' \
        "$_file_path"
    }

    # Helper function to parse package names from an extracted Makefile variable block (v16: parse_packages_from_extracted_block logic)
    parse_pkgs_from_var_block() {
        local _block_text="$1"
        local _var_to_strip_orig="$2" 
        local _op_to_strip="$3"
        local _first_line_processed=0
        local _line 
        local _processed_line 
        local _var_esc_awk 
        local _op_esc_awk 
        local _var_re_str_for_awk 
        local _processed_line_final 

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

            _processed_line=$(echo "$_processed_line" | awk \
                -v var_re_str="$_var_re_str_for_awk" \
                -v var_to_filter_exact="$_var_to_strip_orig" \
                -v op_to_filter_exact="$_op_to_strip" \
                -v first_line="$_first_line_processed" \
                '{
                    sub(/[[:space:]]*#.*$/, "");
                    if (first_line == 0) { 
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
                            if (current_field == op_to_filter_exact) continue; 
                            if (current_field != "" && current_field != "\\" && current_field !~ /^(\(|\))$/ && current_field !~ /^(=|\+=|:=|\?=)$/) {
                                print current_field;
                            }
                        }
                    }
                }')
            
            if [ "$_first_line_processed" -eq 0 ]; then
                _first_line_processed=1
            fi
            
            _processed_line_final=$(echo "$_processed_line" | sed 's/\\[[:space:]]*$//' | sed '/^$/d')

            if [ -n "$_processed_line_final" ]; then
                echo "$_processed_line_final"
            fi
        done
    }

    printf "\n%s\n" "$(color blue "$(get_message "MSG_PACKAGES_INSTALLED_AFTER_FLASHING")")"
    debug_log "DEBUG" "Function called: check_install_list (using v16 logic for parsing)"

    local pkg_extract_tmp_dir; local pkg_extract_tmp_dir_basename
    local default_pkgs_tier1a_tmp; local default_pkgs_tier1b_tmp; local default_pkgs_tier1c_tmp
    local default_pkgs_tier2_tmp; local default_pkgs_tier3_tmp
    local default_pkgs_from_source_sorted_tmp; local default_pkgs_combined_tmp; local tmp_f

    if command -v mktemp >/dev/null; then
        pkg_extract_tmp_dir=$(mktemp -d -p "${TMP_DIR:-/tmp}" "pkg_extract.XXXXXX")
    else
        pkg_extract_tmp_dir_basename="pkg_extract_$$_$(date +%s%N)"
        pkg_extract_tmp_dir="${TMP_DIR:-/tmp}/${pkg_extract_tmp_dir_basename}"
        mkdir -p "$pkg_extract_tmp_dir"
    fi
    if [ ! -d "$pkg_extract_tmp_dir" ]; then
         debug_log "DEBUG" "CRITICAL - Failed to create temp dir for default package extraction."
         return 1
    fi
    debug_log "DEBUG" "Temporary directory for default package extraction: $pkg_extract_tmp_dir"

    default_pkgs_tier1a_tmp="${pkg_extract_tmp_dir}/pkg_target_mk_basic.txt"
    default_pkgs_tier1b_tmp="${pkg_extract_tmp_dir}/pkg_target_mk_router_additions.txt"
    default_pkgs_tier1c_tmp="${pkg_extract_tmp_dir}/pkg_target_mk_direct.txt"
    default_pkgs_tier2_tmp="${pkg_extract_tmp_dir}/pkg_target_specific.txt"
    default_pkgs_tier3_tmp="${pkg_extract_tmp_dir}/pkg_device_specific.txt"
    default_pkgs_combined_tmp="${pkg_extract_tmp_dir}/combined_for_processing.txt"
    default_pkgs_from_source_sorted_tmp="${pkg_extract_tmp_dir}/final_extracted_sorted.txt"

    for tmp_f in "$default_pkgs_tier1a_tmp" "$default_pkgs_tier1b_tmp" "$default_pkgs_tier1c_tmp" \
                  "$default_pkgs_tier2_tmp" "$default_pkgs_tier3_tmp" \
                  "$default_pkgs_from_source_sorted_tmp" "$default_pkgs_combined_tmp"; do
        true > "$tmp_f"
    done

    local raw_device_profile_name=""
    local device_profile_name="" 
    local assumed_device_type="router" 
    local distrib_target="" 
    local distrib_release="" 
    local openwrt_git_branch="main" 
    local target_base=""
    local image_target_suffix=""
    
    debug_log "DEBUG" "Attempting to determine device profile name dynamically."
    if [ -f "/tmp/sysinfo/board_name" ] && [ -s "/tmp/sysinfo/board_name" ]; then
        raw_device_profile_name=$(cat "/tmp/sysinfo/board_name")
        debug_log "DEBUG" "Raw board_name from /tmp/sysinfo/board_name: '${raw_device_profile_name}'"
        if [ -n "$raw_device_profile_name" ]; then
            device_profile_name=$(echo "$raw_device_profile_name" | sed 's/,/_/g')
            debug_log "DEBUG" "Processed DEVICE_PROFILE_NAME: '${device_profile_name}' (commas to underscores)"
        else
            debug_log "DEBUG" "CRITICAL - /tmp/sysinfo/board_name exists but is empty. Cannot determine device profile."
            rm -rf "$pkg_extract_tmp_dir"; return 1
        fi
    else
        debug_log "DEBUG" "CRITICAL - /tmp/sysinfo/board_name not found or empty. Cannot determine device profile."
        rm -rf "$pkg_extract_tmp_dir"; return 1
    fi
    
    if [ -f "/etc/openwrt_release" ]; then
        distrib_release=$(grep '^DISTRIB_RELEASE=' "/etc/openwrt_release" 2>/dev/null | cut -d "'" -f 2)
        distrib_target=$(grep '^DISTRIB_TARGET=' "/etc/openwrt_release" 2>/dev/null | cut -d "'" -f 2)
        if [ -z "$distrib_release" ] || [ -z "$distrib_target" ]; then
            debug_log "DEBUG" "CRITICAL - Could not read DISTRIB_RELEASE or DISTRIB_TARGET from /etc/openwrt_release."
            rm -rf "$pkg_extract_tmp_dir"; return 1
        fi
        debug_log "DEBUG" "Read from /etc/openwrt_release: DISTRIB_TARGET='$distrib_target', DISTRIB_RELEASE='$distrib_release'"
    else
        debug_log "DEBUG" "CRITICAL - /etc/openwrt_release not found. Cannot determine target and release."
        rm -rf "$pkg_extract_tmp_dir"; return 1
    fi

    if echo "$distrib_release" | grep -q "SNAPSHOT"; then openwrt_git_branch="main";
    elif echo "$distrib_release" | grep -Eq '^[0-9]+\.[0-9]+'; then
        local major_minor_version=$(echo "$distrib_release" | awk -F'.' '{print $1"."$2}'); openwrt_git_branch="openwrt-${major_minor_version}"
    else
        debug_log "DEBUG" "CRITICAL - DISTRIB_RELEASE ('$distrib_release') has an unrecognized format. Cannot determine git branch."
        rm -rf "$pkg_extract_tmp_dir"; return 1
    fi
    debug_log "DEBUG" "Using OpenWrt Git branch: $openwrt_git_branch"

    target_base=$(echo "$distrib_target" | cut -d'/' -f1); image_target_suffix=$(echo "$distrib_target" | cut -d'/' -f2)
    if [ -z "$target_base" ] || [ -z "$image_target_suffix" ] || [ "$target_base" = "$distrib_target" ]; then
        debug_log "DEBUG" "CRITICAL - Could not reliably determine target_base/image_target_suffix from DISTRIB_TARGET: '$distrib_target'."
        rm -rf "$pkg_extract_tmp_dir"; return 1
    fi
    debug_log "DEBUG" "Using target paths: target_base='$target_base', image_target_suffix='$image_target_suffix'"

    debug_log "DEBUG" "--- Tier 1: Processing include/target.mk ---"
    local target_mk_file="${pkg_extract_tmp_dir}/target.mk.download" 
    local target_mk_url="https://raw.githubusercontent.com/openwrt/openwrt/${openwrt_git_branch}/include/target.mk"
    if fetch_content "$target_mk_url" "$target_mk_file"; then 
        debug_log "DEBUG" "Extracting DEFAULT_PACKAGES.basic from %s" "$target_mk_file"
        local basic_block_content=$(extract_makefile_var "$target_mk_file" "DEFAULT_PACKAGES.basic" ":=") 
        if [ -n "$basic_block_content" ]; then parse_pkgs_from_var_block "$basic_block_content" "DEFAULT_PACKAGES.basic" ":=" > "$default_pkgs_tier1a_tmp"; fi 
        if [ ! -s "$default_pkgs_tier1a_tmp" ]; then
            debug_log "DEBUG" "DEFAULT_PACKAGES.basic was empty/not found. Fallback: Trying DEFAULT_PACKAGES :="
            local basic_block_content_fallback=$(extract_makefile_var "$target_mk_file" "DEFAULT_PACKAGES" ":=")
            if [ -n "$basic_block_content_fallback" ]; then parse_pkgs_from_var_block "$basic_block_content_fallback" "DEFAULT_PACKAGES" ":=" > "$default_pkgs_tier1a_tmp"; fi
        fi
        if [ -s "$default_pkgs_tier1a_tmp" ]; then debug_log "DEBUG" "Parsed basic packages (Tier 1a) count: $(wc -l < "$default_pkgs_tier1a_tmp")"; else debug_log "DEBUG" "Basic packages list (Tier 1a) is empty."; fi

        debug_log "DEBUG" "Extracting DEFAULT_PACKAGES.%s (additions) from %s" "$assumed_device_type" "$target_mk_file"
        local router_additions_block_content=$(extract_makefile_var "$target_mk_file" "DEFAULT_PACKAGES.${assumed_device_type}" ":=")
        if [ -n "$router_additions_block_content" ]; then parse_pkgs_from_var_block "$router_additions_block_content" "DEFAULT_PACKAGES.${assumed_device_type}" ":=" > "$default_pkgs_tier1b_tmp"; fi
        if [ -s "$default_pkgs_tier1b_tmp" ]; then debug_log "DEBUG" "Parsed %s specific additions (Tier 1b) count: $(wc -l < "$default_pkgs_tier1b_tmp")" "$assumed_device_type"; else debug_log "DEBUG" "Could not extract block for DEFAULT_PACKAGES.%s (additions)." "$assumed_device_type"; fi

        debug_log "DEBUG" "Extracting direct DEFAULT_PACKAGES += from %s" "$target_mk_file"
        local direct_block_content=$(extract_makefile_var "$target_mk_file" "DEFAULT_PACKAGES" "+=")
        if [ -n "$direct_block_content" ]; then parse_pkgs_from_var_block "$direct_block_content" "DEFAULT_PACKAGES" "+=" > "$default_pkgs_tier1c_tmp"; fi
        if [ -s "$default_pkgs_tier1c_tmp" ]; then debug_log "DEBUG" "Parsed direct additions (Tier 1c) count: $(wc -l < "$default_pkgs_tier1c_tmp")"; else debug_log "DEBUG" "Could not extract or parse block for direct DEFAULT_PACKAGES += (Tier 1c)."; fi
    else debug_log "DEBUG" "CRITICAL - Failed to process include/target.mk. Skipping Tier 1."; fi

    debug_log "DEBUG" "--- Tier 2: Processing target/linux/%s/Makefile ---" "$target_base"
    local target_specific_mk_file="${pkg_extract_tmp_dir}/target_${target_base}.mk.download" 
    local target_specific_mk_url="https://raw.githubusercontent.com/openwrt/openwrt/${openwrt_git_branch}/target/linux/${target_base}/Makefile"
    if [ -n "$target_base" ]; then
        if fetch_content "$target_specific_mk_url" "$target_specific_mk_file"; then
            debug_log "DEBUG" "Extracting DEFAULT_PACKAGES += from %s (Tier 2)" "$target_specific_mk_file"
            local ts_block_content=$(extract_makefile_var "$target_specific_mk_file" "DEFAULT_PACKAGES" "+=")
            if [ -n "$ts_block_content" ]; then parse_pkgs_from_var_block "$ts_block_content" "DEFAULT_PACKAGES" "+=" > "$default_pkgs_tier2_tmp"; fi
            if [ -s "$default_pkgs_tier2_tmp" ]; then debug_log "DEBUG" "Parsed target-specific additions (Tier 2) count: $(wc -l < "$default_pkgs_tier2_tmp")"; else debug_log "DEBUG" "Could not extract or parse block for target-specific DEFAULT_PACKAGES += (Tier 2)."; fi
        else debug_log "DEBUG" "CRITICAL - Failed to process target/linux/%s/Makefile. Skipping Tier 2." "$target_base"; fi
    else debug_log "DEBUG" "CRITICAL - target_base is empty. Skipping Tier 2."; fi

    debug_log "DEBUG" "--- Tier 3: Processing target/linux/%s/image/%s.mk for device %s ---" "$target_base" "$image_target_suffix" "$device_profile_name"
    local device_specific_mk_file="${pkg_extract_tmp_dir}/image_${image_target_suffix}.mk.download" 
    local device_profile_block_tmp="${pkg_extract_tmp_dir}/device_profile_block.txt" 
    local device_specific_mk_url="https://raw.githubusercontent.com/openwrt/openwrt/${openwrt_git_branch}/target/linux/${target_base}/image/${image_target_suffix}.mk"
    if [ -n "$target_base" ] && [ -n "$image_target_suffix" ] && [ -n "$device_profile_name" ]; then 
        if fetch_content "$device_specific_mk_url" "$device_specific_mk_file"; then
            debug_log "DEBUG" "Extracting 'define Device/%s' block..." "$device_profile_name"
            awk -v profile_name_awk="$device_profile_name" \
                'BEGIN{found=0; profile_regex = "^define[[:space:]]+Device/" profile_name_awk "[[:space:]]*$"}
                 $0 ~ profile_regex {found=1}
                 found {print}
                 /^[[:space:]]*endef[[:space:]]*$/ && found {found=0}' \
                "$device_specific_mk_file" > "$device_profile_block_tmp"
            
            if [ -s "$device_profile_block_tmp" ]; then
                local device_pkgs_block_content=$(extract_makefile_var "$device_profile_block_tmp" "DEVICE_PACKAGES" ":=")
                if [ -z "$device_pkgs_block_content" ]; then device_pkgs_block_content=$(extract_makefile_var "$device_profile_block_tmp" "DEVICE_PACKAGES" "+="); fi
                
                if [ -n "$device_pkgs_block_content" ]; then
                    parse_pkgs_from_var_block "$device_pkgs_block_content" "DEVICE_PACKAGES" ":=" > "$default_pkgs_tier3_tmp"
                    if [ ! -s "$default_pkgs_tier3_tmp" ]; then parse_pkgs_from_var_block "$device_pkgs_block_content" "DEVICE_PACKAGES" "+=" > "$default_pkgs_tier3_tmp"; fi
                fi
                if [ -s "$default_pkgs_tier3_tmp" ]; then debug_log "DEBUG" "Parsed device-specific packages (Tier 3) count: $(wc -l < "$default_pkgs_tier3_tmp")"; else debug_log "DEBUG" "Could not parse DEVICE_PACKAGES for %s." "$device_profile_name"; fi
            else debug_log "DEBUG" "Could not extract 'define Device/%s' block." "$device_profile_name"; fi
        else debug_log "DEBUG" "CRITICAL - Failed to process image specific Makefile for Tier 3."; fi
    else debug_log "DEBUG" "CRITICAL - target_base, image_target_suffix or device_profile_name is empty. Skipping Tier 3."; fi

    debug_log "DEBUG" "--- Combining all package lists ---"
    for list_file in "$default_pkgs_tier1a_tmp" "$default_pkgs_tier1b_tmp" "$default_pkgs_tier1c_tmp" \
                     "$default_pkgs_tier2_tmp" "$default_pkgs_tier3_tmp"; do
        if [ -s "$list_file" ]; then cat "$list_file" >> "$default_pkgs_combined_tmp"; fi
    done

    debug_log "DEBUG" "Final extracted and sorted list of default packages:" 
    if [ -s "$default_pkgs_combined_tmp" ]; then
        sort -u "$default_pkgs_combined_tmp" | sed '/^$/d' > "$default_pkgs_from_source_sorted_tmp"; 
        debug_log "DEBUG" "Default package list generated. Count: $(wc -l < "$default_pkgs_from_source_sorted_tmp")"
    else 
        debug_log "DEBUG" "No packages found or extracted from Makefiles. Default list will be empty." 
        true > "$default_pkgs_from_source_sorted_tmp"; 
    fi

    local installed_pkgs_list_tmp 
    local source_of_installed_pkgs_msg="" 

    local tmp_dir_base 
    if [ -n "$CACHE_DIR" ] && mkdir -p "$CACHE_DIR" 2>/dev/null && [ -w "$CACHE_DIR" ]; then
        tmp_dir_base="$CACHE_DIR"
    else
        tmp_dir_base="${TMP_DIR:-/tmp}" 
    fi
    installed_pkgs_list_tmp="${tmp_dir_base}/.current_installed_pkgs.tmp"
    
    debug_log "DEBUG" "Determining installed packages based on PACKAGE_MANAGER global variable: '$PACKAGE_MANAGER'"
    if [ -z "$PACKAGE_MANAGER" ]; then
        debug_log "DEBUG" "CRITICAL - Global variable PACKAGE_MANAGER is not set. Run detect_and_save_package_manager first."
        rm -rf "$pkg_extract_tmp_dir"
        return 1
    fi

    if [ "$PACKAGE_MANAGER" = "apk" ]; then
        debug_log "DEBUG" "APK package manager detected via PACKAGE_MANAGER. Reading /etc/apk/world."
        source_of_installed_pkgs_msg="/etc/apk/world"
        if [ -f "/etc/apk/world" ] && [ -s "/etc/apk/world" ]; then
            sort "/etc/apk/world" > "$installed_pkgs_list_tmp"
        else
            debug_log "DEBUG" "/etc/apk/world not found or is empty."
            true > "$installed_pkgs_list_tmp" 
        fi
    elif [ "$PACKAGE_MANAGER" = "opkg" ]; then
        debug_log "DEBUG" "OPKG package manager detected via PACKAGE_MANAGER. Running 'opkg list-installed'."
        source_of_installed_pkgs_msg="'opkg list-installed'"
        opkg list-installed | awk '{print $1}' | sort > "$installed_pkgs_list_tmp"
        if [ ! -s "$installed_pkgs_list_tmp" ]; then
             debug_log "DEBUG" "'opkg list-installed' yielded no packages or awk failed."
        fi
    else
        debug_log "DEBUG" "CRITICAL - Unknown PACKAGE_MANAGER type: '$PACKAGE_MANAGER'. Cannot get installed packages."
        rm -rf "$pkg_extract_tmp_dir" "$installed_pkgs_list_tmp"
        return 1
    fi
    debug_log "DEBUG" "Installed packages list stored in '$installed_pkgs_list_tmp'."
    
    local pkgs_only_in_installed_list
    if [ -s "$installed_pkgs_list_tmp" ]; then 
        pkgs_only_in_installed_list=$(grep -vxFf "$default_pkgs_from_source_sorted_tmp" "$installed_pkgs_list_tmp")
    else
        pkgs_only_in_installed_list=""
    fi
    if [ -n "$pkgs_only_in_installed_list" ]; then echo "$pkgs_only_in_installed_list"; else printf "(None)\n"; fi

    local pkgs_only_in_default_source_list
    if [ -s "$default_pkgs_from_source_sorted_tmp" ]; then 
        pkgs_only_in_default_source_list=$(grep -vxFf "$installed_pkgs_list_tmp" "$default_pkgs_from_source_sorted_tmp")
    else
        pkgs_only_in_default_source_list=""
    fi
    if [ -n "$pkgs_only_in_default_source_list" ]; then echo "$pkgs_only_in_default_source_list"; else printf "(None)\n"; fi
    
    rm -f "$installed_pkgs_list_tmp"; rm -rf "$pkg_extract_tmp_dir" 
    debug_log "DEBUG" "Cleaned up temporary files."
    debug_log "DEBUG" "Package difference check finished."
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
