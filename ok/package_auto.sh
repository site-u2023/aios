#!/bin/sh

SCRIPT_VERSION="2025.03.27-01-00"

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
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"

# OSバージョンに基づいて適切なパッケージインストール関数を選択する
detect_and_run_installer() {
    local install_type="$1"  # ミニマム/標準/フル
    
    # OSバージョンファイルの確認
    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        debug_log "DEBUG" "OS version file not found, using standard version functions"
        # バージョンファイルがない場合は標準バージョンとして扱う
        case "$install_type" in
            minimal)
                install_minimal_standard
                ;;
            standard)
                install_standard_standard
                ;;
            full)
                install_full_standard
                ;;
            *)
                debug_log "ERROR" "Unknown installation type: $install_type"
                return 1
                ;;
        esac
        return 0
    fi

    # OSバージョンの読み込み
    local os_version
    os_version=$(cat "${CACHE_DIR}/osversion.ch")
    
    debug_log "DEBUG" "Detected OS version: $os_version"

    # バージョンとインストールタイプに基づいて関数を呼び出し
    if echo "$os_version" | grep -q "^19\."; then
        # 19.x系の場合
        debug_log "DEBUG" "Using OpenWrt 19.x series installer functions"
        case "$install_type" in
            minimal)
                install_minimal_19
                ;;
            standard)
                install_standard_19
                ;;
            full)
                install_full_19
                ;;
            *)
                debug_log "ERROR" "Unknown installation type: $install_type"
                return 1
                ;;
        esac
    elif echo "$os_version" | grep -qi "snapshot"; then
        # SNAPSHOTの場合（大文字小文字を区別しない）
        debug_log "DEBUG" "Using OpenWrt SNAPSHOT installer functions"
        case "$install_type" in
            minimal)
                install_minimal_snapshot
                ;;
            standard)
                install_standard_snapshot
                ;;
            full)
                install_full_snapshot
                ;;
            *)
                debug_log "ERROR" "Unknown installation type: $install_type"
                return 1
                ;;
        esac
    else
        # その他の通常バージョン
        debug_log "DEBUG" "Using standard version installer functions"
        case "$install_type" in
            minimal)
                install_minimal_standard
                ;;
            standard)
                install_standard_standard
                ;;
            full)
                install_full_standard
                ;;
            *)
                debug_log "ERROR" "Unknown installation type: $install_type"
                return 1
                ;;
        esac
    fi
    
    return 0
}

#
# 標準バージョン（最新リリース）向けの関数群
#

# 標準バージョン用ミニマムインストール
install_minimal_standard() {
    debug_log "DEBUG" "Installing minimal packages for standard OpenWrt"
    
    # === 基本システム・UI機能（最小限） ===
    install_package luci-i18n-base desc:"基本UI言語パック" hidden
    install_package luci-i18n-firewall desc:"ファイアウォールUI言語パック" hidden
    install_package ttyd desc:"ウェブターミナル" hidden
    install_package openssh-sftp-server desc:"ファイル転送サーバー" hidden
    install_package coreutils desc:"基本コマンド群" hidden
    
    # === ネットワーク管理（最小限） ===
    install_package luci-app-sqm desc:"QoSスマートキューイング" hidden
    
    # === テーマ（最小限） ===
    install_package luci-theme-openwrt desc:"標準OpenWrtテーマ" hidden
    
    check_and_install_usb
    
    debug_log "DEBUG" "Minimal standard installation completed"
    return 0
}

# 標準バージョン用標準インストール
install_standard_standard() {
    debug_log "DEBUG" "Installing standard packages for standard OpenWrt"
    
    # まずミニマムパッケージをインストール
    install_minimal_standard
    
    # === 基本システム・UI機能（追加） ===
    install_package luci-i18n-opkg desc:"パッケージ管理UI言語パック" hidden
    install_package luci-app-ttyd desc:"ターミナルUI" hidden
    install_package luci-i18n-ttyd desc:"ターミナルUI言語パック" hidden
    install_package luci-mod-dashboard desc:"ダッシュボード" hidden
    install_package luci-i18n-dashboard desc:"ダッシュボード言語パック" hidden

    # === システムパフォーマンス管理 ===
    install_package irqbalance desc:"CPU負荷分散" hidden

    # === ネットワーク管理（追加） ===
    install_package luci-i18n-sqm desc:"SQM言語パック" hidden
    install_package tc-mod-iptables desc:"トラフィック制御IPテーブル" hidden
    install_package luci-app-qos desc:"基本的なQoS" hidden
    install_package luci-i18n-qos desc:"QoS言語パック" hidden
    install_package luci-i18n-statistics desc:"統計情報" hidden
    install_package luci-i18n-nlbwmon desc:"帯域監視" hidden
    install_package wifischedule desc:"WiFiスケジュール" hidden
    install_package luci-app-wifischedule desc:"WiFiスケジュールUI" hidden
    install_package luci-i18n-wifischedule desc:"WiFiスケジュール言語パック" hidden

    # === セキュリティツール ===
    install_package znc-mod-fail2ban desc:"不正アクセス防止" hidden
    install_package banip desc:"IPブロック" hidden
    
    # === テーマおよび見た目（追加） ===
    install_package luci-theme-material desc:"マテリアルテーマ" hidden
    install_package luci-theme-openwrt-2020 desc:"OpenWrt 2020テーマ" hidden

    # === システム更新 ===
    install_package attendedsysupgrade-common desc:"システムアップグレード共通" hidden
    install_package luci-app-attendedsysupgrade desc:"システムアップグレードUI" hidden
    install_package luci-i18n-attendedsysupgrade desc:"システムアップグレード言語パック" hidden
    
    # === ユーティリティ ===
    install_package usleep desc:"スリープユーティリティ" hidden
    install_package git desc:"バージョン管理" hidden
    install_package git-http desc:"Git HTTP対応" hidden
    install_package ca-certificates desc:"CA証明書" hidden

    # === システム監視 ===
    install_package htop desc:"インタラクティブプロセスビューア" hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf desc:"CPU性能監視" hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-status desc:"CPUステータス" hidden
    feed_package gSpotx2f packages-openwrt current luci-app-temp-status desc:"温度ステータス" hidden
    feed_package gSpotx2f packages-openwrt current luci-app-log-viewer desc:"ログビューア" hidden

    # === ネットワーク診断ツール ===
    install_package mtr desc:"高機能traceroute" hidden
    install_package nmap desc:"ネットワークスキャン" hidden
    install_package tcpdump desc:"パケットキャプチャ" hidden

    # === 追加機能（デフォルトで無効） ===
    feed_package gSpotx2f packages-openwrt current internet-detector desc:"インターネット検知" hidden disabled
    feed_package_release lisaac luci-app-diskman desc:"ディスク管理" hidden disabled
    feed_package_release jerrykuku luci-theme-argon desc:"Argonテーマ" hidden disabled
    
    debug_log "DEBUG" "Standard installation for standard OpenWrt completed"
    return 0
}

# 標準バージョン用フルインストール
install_full_standard() {
    debug_log "DEBUG" "Installing full package set for standard OpenWrt"
    
    # 標準インストールを実行
    install_standard_standard
    
    # === 追加機能（有効化） ===
    feed_package gSpotx2f packages-openwrt current internet-detector desc:"インターネット検知" hidden
    feed_package_release lisaac luci-app-diskman desc:"ディスク管理" hidden
    feed_package_release jerrykuku luci-theme-argon desc:"Argonテーマ" hidden
    
    # === Sambaファイル共有 ===
    install_package luci-app-samba4 desc:"Sambaファイル共有" hidden
    install_package luci-i18n-samba4-ja desc:"Samba日本語UI" hidden
    install_package wsdd2 desc:"Windows検出サービス" hidden
    
    debug_log "DEBUG" "Full installation for standard OpenWrt completed"
    return 0
}

#
# 19.07向けの関数群
#

# 19.07用ミニマムインストール
install_minimal_19() {
    debug_log "DEBUG" "Installing minimal packages for OpenWrt 19.07"
    
    # === 基本システム・UI機能（最小限） ===
    install_package wget desc:"基本ダウンローダー(19.07必須)" hidden
    install_package luci-i18n-base desc:"基本UI言語パック" hidden
    install_package luci-i18n-firewall desc:"ファイアウォールUI言語パック" hidden
    install_package ttyd desc:"ウェブターミナル" hidden
    install_package openssh-sftp-server desc:"ファイル転送サーバー" hidden
    install_package coreutils desc:"基本コマンド群" hidden
    
    # === ネットワーク管理（最小限） ===
    install_package luci-app-sqm desc:"QoSスマートキューイング" hidden
    
    # === テーマ（最小限） ===
    install_package luci-theme-openwrt desc:"標準OpenWrtテーマ" hidden
    
    check_and_install_usb
    
    debug_log "DEBUG" "Minimal installation for OpenWrt 19.07 completed"
    return 0
}

# 19.07用標準インストール
install_standard_19() {
    debug_log "DEBUG" "Installing standard packages for OpenWrt 19.07"
    
    # まずミニマムパッケージをインストール
    install_minimal_19
    
    # === 基本システム・UI機能（追加） ===
    install_package luci-i18n-opkg desc:"パッケージ管理UI言語パック" hidden
    install_package luci-app-ttyd desc:"ターミナルUI" hidden
    install_package luci-i18n-ttyd desc:"ターミナルUI言語パック" hidden
    install_package luci-i18n-dashboard desc:"ダッシュボード言語パック(19.07互換)" hidden

    # === システムパフォーマンス管理 ===
    install_package irqbalance desc:"CPU負荷分散" hidden

    # === ネットワーク管理（追加） ===
    install_package luci-i18n-sqm desc:"SQM言語パック" hidden
    install_package tc-mod-iptables desc:"トラフィック制御IPテーブル" hidden
    install_package luci-app-qos desc:"基本的なQoS" hidden
    install_package luci-i18n-qos desc:"QoS言語パック" hidden
    install_package luci-i18n-statistics desc:"統計情報" hidden
    install_package luci-i18n-nlbwmon desc:"帯域監視" hidden
    install_package wifischedule desc:"WiFiスケジュール" hidden
    install_package luci-app-wifischedule desc:"WiFiスケジュールUI" hidden
    install_package luci-i18n-wifischedule desc:"WiFiスケジュール言語パック" hidden

    # === セキュリティツール ===
    install_package znc-mod-fail2ban desc:"不正アクセス防止" hidden
    install_package banip desc:"IPブロック" hidden
    
    # === テーマおよび見た目（追加） ===
    install_package luci-theme-material desc:"マテリアルテーマ" hidden
    install_package luci-theme-openwrt-2020 desc:"OpenWrt 2020テーマ" hidden

    # === システム更新 ===
    install_package attendedsysupgrade-common desc:"システムアップグレード共通" hidden
    install_package luci-app-attendedsysupgrade desc:"システムアップグレードUI" hidden
    install_package luci-i18n-attendedsysupgrade desc:"システムアップグレード言語パック" hidden

    # === ユーティリティ ===
    install_package usleep desc:"スリープユーティリティ" hidden
    install_package git desc:"バージョン管理" hidden
    install_package git-http desc:"Git HTTP対応" hidden
    install_package ca-certificates desc:"CA証明書" hidden

    # === システム監視 (19.07特有版) ===
    install_package htop desc:"インタラクティブプロセスビューア" hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf desc:"CPU性能監視" hidden
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-cpu-status-mini desc:"CPU状態(19.07用)" hidden
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-log desc:"ログビューア(19.07用)" hidden

    # === ネットワーク診断ツール ===
    install_package mtr desc:"高機能traceroute" hidden
    install_package nmap desc:"ネットワークスキャン" hidden
    install_package tcpdump desc:"パケットキャプチャ" hidden
    
    # === 追加機能（デフォルトで無効） ===
    feed_package_release lisaac luci-app-diskman desc:"ディスク管理" hidden disabled
    
    debug_log "DEBUG" "Standard installation for OpenWrt 19.07 completed"
    return 0
}

# 19.07用フルインストール
install_full_19() {
    debug_log "DEBUG" "Installing full package set for OpenWrt 19.07"
    
    # 標準インストールを実行
    install_standard_19
    
    # === 追加機能（有効化） ===
    feed_package_release lisaac luci-app-diskman desc:"ディスク管理" hidden
    
    # === Sambaファイル共有 ===
    install_package luci-app-samba4 desc:"Sambaファイル共有" hidden
    install_package luci-i18n-samba4-ja desc:"Samba日本語UI" hidden
    install_package wsdd2 desc:"Windows検出サービス" hidden
    
    debug_log "DEBUG" "Full installation for OpenWrt 19.07 completed"
    return 0
}

#
# SNAPSHOT向けの関数群
#

# SNAPSHOT用ミニマムインストール
install_minimal_snapshot() {
    debug_log "DEBUG" "Installing minimal packages for OpenWrt SNAPSHOT"
    
    # === まずLuCIをインストール ===
    install_package luci desc:"LuCIウェブインターフェース(SNAPSHOT用)" hidden
    
    # === 基本システム・UI機能（最小限） ===
    install_package luci-i18n-base desc:"基本UI言語パック" hidden
    install_package luci-i18n-firewall desc:"ファイアウォールUI言語パック" hidden
    install_package ttyd desc:"ウェブターミナル" hidden
    install_package openssh-sftp-server desc:"ファイル転送サーバー" hidden
    install_package coreutils desc:"基本コマンド群" hidden
    
    # === ネットワーク管理（最小限） ===
    install_package luci-app-sqm desc:"QoSスマートキューイング" hidden
    
    # === テーマ（最小限） ===
    install_package luci-theme-openwrt desc:"標準OpenWrtテーマ" hidden
    
    check_and_install_usb
    
    debug_log "DEBUG" "Minimal installation for OpenWrt SNAPSHOT completed"
    return 0
}

# SNAPSHOT用標準インストール
install_standard_snapshot() {
    debug_log "DEBUG" "Installing standard packages for OpenWrt SNAPSHOT"
    
    # まずミニマムパッケージをインストール
    install_minimal_snapshot
    
    # === 基本システム・UI機能（追加） ===
    install_package luci-i18n-opkg desc:"パッケージ管理UI言語パック" hidden
    install_package luci-app-ttyd desc:"ターミナルUI" hidden
    install_package luci-i18n-ttyd desc:"ターミナルUI言語パック" hidden
    install_package luci-mod-dashboard desc:"ダッシュボード" hidden
    install_package luci-i18n-dashboard desc:"ダッシュボード言語パック" hidden

    # === システムパフォーマンス管理 ===
    install_package irqbalance desc:"CPU負荷分散" hidden

    # === ネットワーク管理（追加） ===
    install_package luci-i18n-sqm desc:"SQM言語パック" hidden
    install_package tc-mod-iptables desc:"トラフィック制御IPテーブル" hidden
    install_package luci-app-qos desc:"基本的なQoS" hidden
    install_package luci-i18n-qos desc:"QoS言語パック" hidden
    install_package luci-i18n-statistics desc:"統計情報" hidden
    install_package luci-i18n-nlbwmon desc:"帯域監視" hidden
    install_package wifischedule desc:"WiFiスケジュール" hidden
    install_package luci-app-wifischedule desc:"WiFiスケジュールUI" hidden
    install_package luci-i18n-wifischedule desc:"WiFiスケジュール言語パック" hidden

    # === セキュリティツール ===
    install_package znc-mod-fail2ban desc:"不正アクセス防止" hidden
    install_package banip desc:"IPブロック" hidden
    
    # === テーマおよび見た目（追加） ===
    install_package luci-theme-material desc:"マテリアルテーマ" hidden
    install_package luci-theme-openwrt-2020 desc:"OpenWrt 2020テーマ" hidden

    # === システム更新 ===
    install_package attendedsysupgrade-common desc:"システムアップグレード共通" hidden
    install_package luci-app-attendedsysupgrade desc:"システムアップグレードUI" hidden
    install_package luci-i18n-attendedsysupgrade desc:"システムアップグレード言語パック" hidden
    
    # === ユーティリティ ===
    install_package usleep desc:"スリープユーティリティ" hidden
    install_package git desc:"バージョン管理" hidden
    install_package git-http desc:"Git HTTP対応" hidden
    install_package ca-certificates desc:"CA証明書" hidden

    # === システム監視 ===
    install_package htop desc:"インタラクティブプロセスビューア" hidden

    # === ネットワーク診断ツール ===
    install_package mtr desc:"高機能traceroute" hidden
    install_package nmap desc:"ネットワークスキャン" hidden
    install_package tcpdump desc:"パケットキャプチャ" hidden
    
    debug_log "DEBUG" "Standard installation for OpenWrt SNAPSHOT completed"
    return 0
}

# SNAPSHOT用フルインストール
install_full_snapshot() {
    debug_log "DEBUG" "Installing full package set for OpenWrt SNAPSHOT"
    
    # 標準インストールを実行
    install_standard_snapshot
    
    # === 追加機能（有効化） ===
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf desc:"CPU性能監視" hidden
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-status desc:"CPUステータス" hidden
    feed_package gSpotx2f packages-openwrt current luci-app-temp-status desc:"温度ステータス" hidden
    feed_package gSpotx2f packages-openwrt current luci-app-log-viewer desc:"ログビューア" hidden
    feed_package gSpotx2f packages-openwrt current internet-detector desc:"インターネット検知" hidden
    feed_package_release lisaac luci-app-diskman desc:"ディスク管理" hidden
    feed_package_release jerrykuku luci-theme-argon desc:"Argonテーマ" hidden
    
    # === Sambaファイル共有 ===
    install_package luci-app-samba4 desc:"Sambaファイル共有" hidden
    install_package luci-i18n-samba4-ja desc:"Samba日本語UI" hidden
    install_package wsdd2 desc:"Windows検出サービス" hidden
    
    debug_log "DEBUG" "Full installation for OpenWrt SNAPSHOT completed"
    return 0
}

# USBパッケージインストール関数
check_and_install_usb() {
    debug_log "DEBUG" "Checking for USB devices"
    
    # USBデバイスのキャッシュファイルを確認
    if [ ! -f "${CACHE_DIR}/usbdevice.ch" ]; then
        debug_log "DEBUG" "USB device cache file not found, skipping USB detection"
        return 0
    fi
    
    # USBデバイスが検出されているか確認
    if [ "$(cat "${CACHE_DIR}/usbdevice.ch")" = "detected" ]; then
        debug_log "DEBUG" "USB device detected, installing USB packages"
        
        # === 基本USB機能 ===
        install_package block-mount desc:"ブロックデバイスマウント" hidden
        install_package kmod-usb-storage desc:"USBストレージ基本カーネルモジュール" hidden
        install_package kmod-usb-storage-uas desc:"USB高速プロトコル対応" hidden
        install_package usbutils desc:"USBユーティリティ" hidden
        install_package gdisk desc:"GPTパーティション管理" hidden
        install_package libblkid1 desc:"ブロックデバイスID" hidden
        install_package kmod-usb-ledtrig-usb desc:"USB LED表示トリガー" hidden port
        install_package luci-app-ledtrig-usbport desc:"USB LED設定UI" hidden

        # === ファイルシステムサポート ===
        install_package dosfstools desc:"FAT ファイルシステムツール" hidden
        install_package kmod-fs-vfat desc:"FAT カーネルモジュール" hidden
        install_package e2fsprogs desc:"EXT ファイルシステムツール" hidden
        install_package kmod-fs-ext4 desc:"EXT4 カーネルモジュール" hidden
        install_package f2fs-tools desc:"F2FS ファイルシステムツール" hidden
        install_package kmod-fs-f2fs desc:"F2FS カーネルモジュール" hidden
        install_package exfat-fsck desc:"exFAT ファイルシステムチェック" hidden
        install_package kmod-fs-exfat desc:"exFAT カーネルモジュール" hidden
        install_package ntfs-3g desc:"NTFS ファイルシステムツール" hidden
        install_package kmod-fs-ntfs3 desc:"NTFS カーネルモジュール" hidden
        install_package hfsfsck desc:"HFS ファイルシステムチェック" hidden
        install_package kmod-fs-hfs desc:"HFS カーネルモジュール" hidden
        install_package kmod-fs-hfsplus desc:"HFS+ カーネルモジュール" hidden

        # === ディスク管理 ===
        install_package hdparm desc:"ハードディスク設定ツール" hidden
        install_package hd-idle desc:"HDDアイドル制御" hidden
        install_package luci-app-hd-idle desc:"HDDアイドルUI" hidden
        install_package luci-i18n-hd-idle desc:"HDDアイドルUI言語パック" hidden
        
        debug_log "DEBUG" "USB packages installed successfully"
    else
        debug_log "DEBUG" "No USB device detected, skipping USB packages"
    fi
    
    return 0
}

# パッケージリスト表示関数
package_list() {
    check_install_list
    return 0
}
