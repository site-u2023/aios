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

install_package_list() {
    install_package list
}

packages_usb() {
    install_package block-mount
    install_package kmod-usb-storage
    install_package kmod-usb-storage-uas
    install_package usbutils
    install_package gdisk
    install_package libblkid1
    install_package kmod-usb-ledtrig-usbport
    install_package luci-app-ledtrig-usbport
    install_package dosfstools
    install_package kmod-fs-vfat
    install_package e2fsprogs
    install_package kmod-fs-ext4
    install_package f2fs-tools
    install_package kmod-fs-f2fs
    install_package exfat-fsck
    install_package kmod-fs-exfat
    install_package ntfs-3g
    install_package kmod-fs-ntfs3
    install_package hfsfsck
    install_package kmod-fs-hfs
    install_package kmod-fs-hfsplus

    install_package hdparm
    install_package hd-idle
    install_package luci-app-hd-idle
    install_package luci-i18n-hd-idle
    
    install_package luci-app-samba4
    install_package luci-i18n-samba4-ja
    install_package wsdd2
}

# メイン処理
main() {

}

# スクリプトの実行
main "$@"
