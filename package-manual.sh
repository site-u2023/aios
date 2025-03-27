#!/bin/sh

SCRIPT_VERSION="2025.03.27-00-01"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-27
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
BASE_WGET="wget --no-check-certificate -q -O"
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
        printf "\n%s\n" "$(color blue "$header_text")"
    }

    # === 基本システム機能 ===
    print_section_header "PKG_SECTION_BASIC"
    install_package luci-i18n-base desc:"UI Language Pack" yn hidden
    install_package ttyd desc:"Web Terminal" yn hidden
    install_package openssh-sftp-server desc:"Secure File Transfer" yn hidden
    install_package coreutils desc:"Core Utilities" yn hidden
    
    # === システム管理 ===
    print_section_header "PKG_SECTION_SYSADMIN"
    install_package irqbalance desc:"CPU Load Balancing" yn hidden
    install_package luci-mod-dashboard desc:"System Dashboard" yn hidden
    feed_package_release lisaac luci-app-diskman desc:"Disk Management" yn hidden disabled
    
    # === ネットワーク管理 ===
    print_section_header "PKG_SECTION_NETWORK"
    install_package luci-app-sqm desc:"Smart Queue Management QoS" yn hidden
    install_package luci-app-qos desc:"Basic QoS Control" yn hidden
    install_package luci-i18n-statistics desc:"System Statistics" yn hidden
    install_package luci-i18n-nlbwmon desc:"Bandwidth Monitoring" yn hidden
    install_package wifischedule desc:"WiFi Scheduling" yn hidden

    # === セキュリティツール ===
    print_section_header "PKG_SECTION_SECURITY"
    install_package znc-mod-fail2ban desc:"Protection Against Login Attacks" yn hidden
    install_package banip desc:"IP Blocking Utility" yn hidden

    # === システム監視 ===
    print_section_header "PKG_SECTION_MONITORING"
    install_package htop desc:"Interactive Process Viewer" yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf desc:"CPU Performance Monitor" yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-status desc:"CPU Status Monitor" yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-temp-status desc:"Temperature Monitor" yn hidden
    feed_package gSpotx2f packages-openwrt current internet-detector desc:"Internet Connection Monitor" yn hidden disabled
    feed_package gSpotx2f packages-openwrt current luci-app-log-viewer desc:"System Log Viewer" yn hidden

    # === ネットワーク診断ツール ===
    print_section_header "PKG_SECTION_NETWORK_DIAG"
    install_package mtr desc:"Advanced Traceroute Tool" yn hidden
    install_package nmap desc:"Network Scanner" yn hidden
    install_package tcpdump desc:"Packet Capture Tool" yn hidden
    
    # === テーマおよび見た目 ===
    print_section_header "PKG_SECTION_THEME"
    install_package luci-theme-openwrt desc:"OpenWrt Standard Theme" yn hidden
    feed_package_release jerrykuku luci-theme-argon desc:"Argon Modern Theme" yn hidden disabled

    # === ユーティリティ ===
    print_section_header "PKG_SECTION_UTILITY"
    install_package attendedsysupgrade-common desc:"System Upgrade Utility" yn hidden
    install_package usleep desc:"Microsleep Utility" yn hidden
    install_package git desc:"Version Control System" yn hidden
    
    debug_log "DEBUG" "Standard packages installation process completed"
    return 0
}

packages_19() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color blue "$header_text")"
    }

    # === 基本システム機能 ===
    print_section_header "PKG_SECTION_BASIC"
    install_package wget desc:"Download Utility (Required for 19.07)" yn hidden
    install_package luci-i18n-base desc:"UI Language Pack" yn hidden
    install_package ttyd desc:"Web Terminal" yn hidden
    install_package openssh-sftp-server desc:"Secure File Transfer" yn hidden
    install_package coreutils desc:"Core Utilities" yn hidden
    
    # === システム管理 ===
    print_section_header "PKG_SECTION_SYSADMIN"
    install_package irqbalance desc:"CPU Load Balancing" yn hidden
    install_package luci-i18n-dashboard desc:"System Dashboard (19.07 Version)" yn hidden
    
    # === ネットワーク管理 ===
    print_section_header "PKG_SECTION_NETWORK"
    install_package luci-app-sqm desc:"Smart Queue Management QoS" yn hidden
    install_package luci-app-qos desc:"Basic QoS Control" yn hidden
    install_package luci-i18n-statistics desc:"System Statistics" yn hidden
    install_package luci-i18n-nlbwmon desc:"Bandwidth Monitoring" yn hidden
    install_package wifischedule desc:"WiFi Scheduling" yn hidden

    # === セキュリティツール ===
    print_section_header "PKG_SECTION_SECURITY"
    install_package znc-mod-fail2ban desc:"Protection Against Login Attacks" yn hidden
    install_package banip desc:"IP Blocking Utility" yn hidden
    
    # === システム監視 (19.07特有版) ===
    print_section_header "PKG_SECTION_MONITORING"
    install_package htop desc:"Interactive Process Viewer" yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf desc:"CPU Performance Monitor" yn hidden
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-cpu-status-mini desc:"CPU Status Monitor (19.07)" yn hidden
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-log desc:"Log Viewer (19.07)" yn hidden

    # === ネットワーク診断ツール ===
    print_section_header "PKG_SECTION_NETWORK_DIAG"
    install_package mtr desc:"Advanced Traceroute Tool" yn hidden
    install_package nmap desc:"Network Scanner" yn hidden
    install_package tcpdump desc:"Packet Capture Tool" yn hidden

    # === テーマおよび見た目 ===
    print_section_header "PKG_SECTION_THEME"
    install_package luci-theme-openwrt desc:"OpenWrt Standard Theme" yn hidden
    
    # === ユーティリティ ===
    print_section_header "PKG_SECTION_UTILITY"
    install_package attendedsysupgrade-common desc:"System Upgrade Utility" yn hidden
    install_package usleep desc:"Microsleep Utility" yn hidden
    install_package git desc:"Version Control System" yn hidden
    
    # === 追加機能（デフォルトで無効） ===
    print_section_header "PKG_SECTION_ADDITION"
    feed_package_release lisaac luci-app-diskman desc:"Disk Management" yn hidden disabled
    
    debug_log "DEBUG" "19.07 specific packages installation process completed"
    return 0
}

packages_snaphot() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color blue "$header_text")"
    }

    # === 基本システム機能 ===
    print_section_header "PKG_SECTION_BASIC"
    install_package luci desc:"LuCI Web Interface (SNAPSHOT)" yn hidden
    install_package luci-i18n-base desc:"UI Language Pack" yn hidden
    install_package ttyd desc:"Web Terminal" yn hidden
    install_package openssh-sftp-server desc:"Secure File Transfer" yn hidden
    install_package coreutils desc:"Core Utilities" yn hidden
    
    # === システム管理 ===
    print_section_header "PKG_SECTION_SYSADMIN"
    install_package irqbalance desc:"CPU Load Balancing" yn hidden
    install_package luci-mod-dashboard desc:"System Dashboard" yn hidden
    
    # === ネットワーク管理 ===
    print_section_header "PKG_SECTION_NETWORK"
    install_package luci-app-sqm desc:"Smart Queue Management QoS" yn hidden
    install_package luci-app-qos desc:"Basic QoS Control" yn hidden
    install_package luci-i18n-statistics desc:"System Statistics" yn hidden
    install_package luci-i18n-nlbwmon desc:"Bandwidth Monitoring" yn hidden
    install_package wifischedule desc:"WiFi Scheduling" yn hidden

    # === システム監視 ===
    print_section_header "PKG_SECTION_MONITORING"
    install_package htop desc:"Interactive Process Viewer" yn hidden
    
    # === セキュリティツール ===
    print_section_header "PKG_SECTION_SECURITY"
    install_package znc-mod-fail2ban desc:"Protection Against Login Attacks" yn hidden
    install_package banip desc:"IP Blocking Utility" yn hidden

    # === ネットワーク診断ツール ===
    print_section_header "PKG_SECTION_NETWORK_DIAG"
    install_package mtr desc:"Advanced Traceroute Tool" yn hidden
    install_package nmap desc:"Network Scanner" yn hidden
    install_package tcpdump desc:"Packet Capture Tool" yn hidden
    
    # === テーマおよび見た目 ===
    print_section_header "PKG_SECTION_THEME"
    install_package luci-theme-openwrt desc:"OpenWrt Standard Theme" yn hidden
    
    # === ユーティリティ ===
    print_section_header "PKG_SECTION_UTILITY"
    install_package attendedsysupgrade-common desc:"System Upgrade Utility" yn hidden
    install_package usleep desc:"Microsleep Utility" yn hidden
    install_package git desc:"Version Control System" yn hidden
    
    debug_log "DEBUG" "SNAPSHOT specific packages installation process completed"
    return 0
}

packages_usb() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color blue "$header_text")"
    }

    # === USBストレージ ===
    print_section_header "PKG_SECTION_USB"
    install_package kmod-usb-storage desc:"USB Storage Driver" yn hidden
    install_package dosfstools desc:"FAT/FAT32 Filesystem Support" yn hidden
    install_package e2fsprogs desc:"Ext2/3/4 Filesystem Support" yn hidden
    install_package f2fs-tools desc:"F2FS Filesystem Support" yn hidden
    install_package exfat-fsck desc:"exFAT Filesystem Support" yn hidden
    install_package ntfs-3g desc:"NTFS Filesystem Support" yn hidden
    install_package hfsfsck desc:"HFS Filesystem Support" yn hidden
    install_package hdparm desc:"Hard Disk Parameters Tool" yn hidden
    
    debug_log "DEBUG" "USB and storage related packages installation process completed"
    return 0
}

package_samba() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color blue "$header_text")"
    }

    # === ファイル共有 ===
    print_section_header "PKG_SECTION_SAMBA"
    install_package luci-app-samba4 desc:"Windows File Sharing" yn hidden
    
    debug_log "DEBUG" "Samba file sharing packages installation process completed"
    return 0
}

package_list() {
    check_install_list
    
    return 0
}

# OSバージョンに基づいて適切なパッケージ関数を実行する
install_packages_by_version() {
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

# メイン処理
# メイン処理
main() {
    print_information
    
    # パッケージインストールの確認
    if confirm "MSG_CONFIRM_INSTALL_PACKAGES"; then
        debug_log "DEBUG" "User confirmed package installation, proceeding"
        
        # OSバージョンに基づいたパッケージインストール
        install_packages_by_version
        
        # USB関連パッケージのインストール
        install_usb_packages
    else
        debug_log "DEBUG" "User declined package installation, skipping"
        # ユーザーが拒否した場合は何もせずに終了
    fi
}

# スクリプトの実行
# main "$@"
