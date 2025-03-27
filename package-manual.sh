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
    # === 基本システム機能 ===
    install_package luci-i18n-base yn hidden        # 基本UI言語パック
    install_package ttyd yn hidden                  # ウェブターミナル
    install_package openssh-sftp-server yn hidden   # ファイル転送
    install_package coreutils yn hidden             # 基本コマンド群
    
    # === システム管理 ===
    install_package irqbalance yn hidden            # CPU負荷分散
    install_package luci-mod-dashboard yn hidden    # ダッシュボード
    
    # === ネットワーク管理 ===
    install_package luci-app-sqm yn hidden          # QoSスマートキューイング
    install_package luci-app-qos yn hidden          # 基本的なQoS
    install_package luci-i18n-statistics yn hidden  # 統計情報
    install_package luci-i18n-nlbwmon yn hidden     # 帯域監視
    install_package wifischedule yn hidden          # WiFiスケジュール

    # === セキュリティツール ===
    install_package fail2ban yn hidden                # 不正アクセス防止
    install_package banip yn hidden                   # IPブロック
    install_package https-dns-proxy yn hidden         # DNS over HTTPS

    # === システム監視 ===
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf yn hidden      # CPU性能
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-status yn hidden    # CPUステータス
    feed_package gSpotx2f packages-openwrt current luci-app-temp-status yn hidden   # 温度ステータス
    feed_package gSpotx2f packages-openwrt current luci-app-log-viewer yn hidden    # ログビューア
    
    # === テーマおよび見た目 ===
    install_package luci-theme-openwrt yn hidden    # 標準テーマ
    
    # === ユーティリティ ===
    install_package attendedsysupgrade-common yn hidden  # システムアップグレード
    install_package usleep yn hidden                # スリープユーティリティ
    install_package git yn hidden                   # バージョン管理
    
    # === 追加機能（デフォルトで無効） ===
    feed_package gSpotx2f packages-openwrt current internet-detector yn hidden disabled     # インターネット検知
    feed_package_release lisaac luci-app-diskman yn hidden disabled                         # ディスク管理
    feed_package_release jerrykuku luci-theme-argon yn hidden disabled                      # Argonテーマ
    
    debug_log "DEBUG" "Standard packages installation process completed"
    return 0
}

packages_19() {
    # === 基本システム機能 ===
    install_package wget yn hidden                  # 基本ダウンローダー(19.07必須)
    install_package luci-i18n-base yn hidden        # 基本UI言語パック
    install_package ttyd yn hidden                  # ウェブターミナル
    install_package openssh-sftp-server yn hidden   # ファイル転送
    install_package coreutils yn hidden             # 基本コマンド群
    
    # === システム管理 ===
    install_package irqbalance yn hidden            # CPU負荷分散
    install_package luci-i18n-dashboard yn hidden   # ダッシュボード(19.07版)
    
    # === ネットワーク管理 ===
    install_package luci-app-sqm yn hidden          # QoSスマートキューイング
    install_package luci-app-qos yn hidden          # 基本的なQoS
    install_package luci-i18n-statistics yn hidden  # 統計情報
    install_package luci-i18n-nlbwmon yn hidden     # 帯域監視
    install_package wifischedule yn hidden          # WiFiスケジュール

        # === セキュリティツール ===
    install_package fail2ban yn hidden                # 不正アクセス防止
    install_package banip yn hidden                   # IPブロック
    install_package https-dns-proxy yn hidden         # DNS over HTTPS
    
    # === テーマおよび見た目 ===
    install_package luci-theme-openwrt yn hidden    # 標準テーマ
    
    # === システム監視 (19.07特有版) ===
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf yn hidden     # CPU性能
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-cpu-status-mini yn hidden # CPU状態(19.07用)
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-log yn hidden            # ログビューア(19.07用)
    
    # === ユーティリティ ===
    install_package attendedsysupgrade-common yn hidden  # システムアップグレード
    install_package usleep yn hidden                # スリープユーティリティ
    install_package git yn hidden                   # バージョン管理
    
    # === 追加機能（デフォルトで無効） ===
    feed_package_release lisaac luci-app-diskman yn hidden disabled    # ディスク管理
    
    # feed_package_release jerrykuku luci-theme-argon yn hidden disabled # Argonテーマ
    
    debug_log "DEBUG" "19.07 specific packages installation process completed"
    return 0
}

packages_snaphot() {
    # === 基本システム機能 ===
    install_package luci yn hidden                  # 基本LuCIパッケージ(SNAPSHOT用)
    install_package luci-i18n-base yn hidden        # 基本UI言語パック
    install_package ttyd yn hidden                  # ウェブターミナル
    install_package openssh-sftp-server yn hidden   # ファイル転送
    install_package coreutils yn hidden             # 基本コマンド群
    
    # === システム管理 ===
    install_package irqbalance yn hidden            # CPU負荷分散
    install_package luci-mod-dashboard yn hidden    # ダッシュボード
    
    # === ネットワーク管理 ===
    install_package luci-app-sqm yn hidden          # QoSスマートキューイング
    install_package luci-app-qos yn hidden          # 基本的なQoS
    install_package luci-i18n-statistics yn hidden  # 統計情報
    install_package luci-i18n-nlbwmon yn hidden     # 帯域監視
    install_package wifischedule yn hidden          # WiFiスケジュール

        # === セキュリティツール ===
    install_package fail2ban yn hidden                # 不正アクセス防止
    install_package banip yn hidden                   # IPブロック
    install_package https-dns-proxy yn hidden         # DNS over HTTPS
    
    # === テーマおよび見た目 ===
    install_package luci-theme-openwrt yn hidden    # 標準テーマ
    
    # === ユーティリティ ===
    install_package attendedsysupgrade-common yn hidden  # システムアップグレード
    install_package usleep yn hidden                # スリープユーティリティ
    install_package git yn hidden                   # バージョン管理
    
    debug_log "DEBUG" "SNAPSHOT specific packages installation process completed"
    return 0
}

packages_usb() {
    install_package kmod-usb-storage yn hidden 
    install_package dosfstools yn hidden 
    install_package e2fsprogs yn hidden 
    install_package f2fs-tools yn hidden 
    install_package exfat-fsck yn hidden 
    install_package ntfs-3g yn hidden 
    install_package hfsfsck yn hidden 
    install_package hdparm yn hidden 
    
    return 0
}

package_samba() {
    install_package luci-app-samba4 yn hidden 
    
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
main() {
    print_information
    # OSバージョンに基づいたパッケージインストール
    install_packages_by_version
    # USB関連パッケージのインストール
    install_usb_packages
}

# スクリプトの実行
# main "$@"
