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

# パッケージのインストール (オプション)
packages() {
    # パッケージのインストール
    #install_package luci yn hidden
    install_package ttyd yn hidden
    install_package luci-app-ttyd yn hidden
    install_package luci-i18n-ttyd yn hidden
    install_package openssh-sftp-server yn hidden
    install_package luci-mod-dashboard yn hidden
    #install_package coreutils yn hidden
    install_package irqbalance yn hidden
    install_package jq yn hidden

    #feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf yn hidden
    #feed_package gSpotx2f packages-openwrt current luci-app-cpu-status yn hidden
    #feed_package gSpotx2f packages-openwrt current luci-app-temp-status yn hidden
    #feed_package gSpotx2f packages-openwrt current luci-app-log-viewer yn hidden
    #feed_package gSpotx2f packages-openwrt current luci-app-log yn hidden
    #feed_package gSpotx2f packages-openwrt current internet-detector yn hidden disabled

    #feed_package_release lisaac luci-app-diskman yn hidden disabled

    #feed_package_release jerrykuku luci-theme-argon yn hidden disabled
    
    # install_package list
}

# メイン処理
main() {
    #information
    #set_device_name_password
    #set_wifi_ssid_password
    #set_device
    packages
}

# スクリプトの実行
main "$@"
