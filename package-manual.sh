#!/bin/sh

SCRIPT_VERSION="2025.03.25-00-00"

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
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"

packages() {
    install_package luci-i18n-base yn hidden
    install_package luci-i18n-opkg yn hidden
    install_package luci-i18n-firewall yn hidden
    install_package ttyd yn hidden
    install_package luci-app-ttyd yn hidden
    install_package luci-i18n-ttyd yn hidden
    install_package openssh-sftp-server yn hidden
    install_package luci-mod-dashboard yn hidden
    install_package luci-i18n-dashboard yn hidden
    install_package coreutils yn hidden
    install_package irqbalance yn hidden
    install_package luci-app-sqm yn hidden
    install_package luci-i18n-sqm yn hidden
    install_package tc-mod-iptables yn hidden
    install_package luci-app-qos yn hidden
    install_package luci-i18n-qos yn hidden
    install_package luci-i18n-statistics yn hidden
    install_package luci-i18n-nlbwmon yn hidden
    install_package wifischedule yn hidden
    install_package luci-app-wifischedule yn hidden
    install_package luci-i18n-wifischedule yn hidden
    install_package luci-theme-openwrt yn hidden
    install_package luci-theme-material yn hidden
    install_package luci-theme-openwrt-2020 yn hidden
    install_package attendedsysupgrade-common yn hidden
    install_package luci-app-attendedsysupgrade yn hidden
    install_package luci-i18n-attendedsysupgrade yn hidden   
    install_package jq yn hidden

    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-status yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-temp-status yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-log-viewer yn hidden
    feed_package gSpotx2f packages-openwrt current luci-app-log yn hidden
    feed_package gSpotx2f packages-openwrt current internet-detector yn hidden disabled

    feed_package_release lisaac luci-app-diskman yn hidden disabled

    feed_package_release jerrykuku luci-theme-argon yn hidden disabled
}

packages_19() {
    install_package luci-i18n-base yn hidden
    install_package luci-i18n-opkg yn hidden
    install_package luci-i18n-firewall yn hidden
    install_package ttyd yn hidden
    install_package luci-app-ttyd yn hidden
    install_package luci-i18n-ttyd yn hidden
    install_package openssh-sftp-server yn hidden
    install_package luci-mod-dashboard yn hidden
    install_package luci-i18n-dashboard yn hidden
    install_package coreutils yn hidden
    install_package irqbalance yn hidden
    install_package luci-app-sqm yn hidden
    install_package luci-i18n-sqm yn hidden
    install_package tc-mod-iptables yn hidden
    install_package luci-app-qos yn hidden
    install_package luci-i18n-qos yn hidden
    install_package luci-i18n-statistics yn hidden
    install_package luci-i18n-nlbwmon yn hidden
    install_package wifischedule yn hidden
    install_package luci-app-wifischedule yn hidden
    install_package luci-i18n-wifischedule yn hidden
    install_package luci-theme-openwrt yn hidden
    install_package luci-theme-material yn hidden
    install_package luci-theme-openwrt-2020 yn hidden
    install_package attendedsysupgrade-common yn hidden
    install_package luci-app-attendedsysupgrade yn hidden
    install_package luci-i18n-attendedsysupgrade yn hidden   
    install_package jq yn hidden
}

packages_snaphot() {
    install_package luci yn hidden
    install_package luci-i18n-base yn hidden
    install_package luci-i18n-opkg yn hidden
    install_package luci-i18n-firewall yn hidden
    install_package ttyd yn hidden
    install_package luci-app-ttyd yn hidden
    install_package luci-i18n-ttyd yn hidden
    install_package openssh-sftp-server yn hidden
    install_package luci-mod-dashboard yn hidden
    install_package luci-i18n-dashboard yn hidden
    install_package coreutils yn hidden
    install_package irqbalance yn hidden
    install_package luci-app-sqm yn hidden
    install_package luci-i18n-sqm yn hidden
    install_package tc-mod-iptables yn hidden
    install_package luci-app-qos yn hidden
    install_package luci-i18n-qos yn hidden
    install_package luci-i18n-statistics yn hidden
    install_package luci-i18n-nlbwmon yn hidden
    install_package wifischedule yn hidden
    install_package luci-app-wifischedule yn hidden
    install_package luci-i18n-wifischedule yn hidden
    install_package luci-theme-openwrt yn hidden
    install_package luci-theme-material yn hidden
    install_package luci-theme-openwrt-2020 yn hidden
    install_package attendedsysupgrade-common yn hidden
    install_package luci-app-attendedsysupgrade yn hidden
    install_package luci-i18n-attendedsysupgrade yn hidden   
    install_package jq yn hidden
}

packages_usb() {
    install_package block-mount yn hidden 
    install_package kmod-usb-storage yn hidden 
    install_package kmod-usb-storage-uas yn hidden 
    install_package usbutils yn hidden 
    install_package gdisk yn hidden 
    install_package libblkid1 yn hidden 
    install_package kmod-usb-ledtrig-usb yn hidden port
    install_package luci-app-ledtrig-usbport yn hidden 
    install_package dosfstools yn hidden 
    install_package kmod-fs-vfat yn hidden 
    install_package e2fsprogs yn hidden 
    install_package kmod-fs-ext4 yn hidden 
    install_package f2fs-tools yn hidden 
    install_package kmod-fs-f2fs yn hidden 
    install_package exfat-fsck yn hidden 
    install_package kmod-fs-exfat yn hidden 
    install_package ntfs-3g yn hidden 
    install_package kmod-fs-ntfs3 yn hidden 
    install_package hfsfsck yn hidden 
    install_package kmod-fs-hfs yn hidden 
    install_package kmod-fs-hfsplus yn hidden 

    install_package hdparm yn hidden 
    install_package hd-idle yn hidden 
    install_package luci-app-hd-idle yn hidden 
    install_package luci-i18n-hd-idle yn hidden 
}

install_package_samba() {
    install_package luci-app-samba4 yn hidden 
    install_package luci-i18n-samba4-ja yn hidden 
    install_package wsdd2 yn hidden
}

install_package_list() {
    install_package list
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
main() {
    print_information
    # OSバージョンに基づいたパッケージインストール
    install_packages_by_version
    # USB関連パッケージのインストール
    install_usb_packages
}

# スクリプトの実行
# main "$@"
