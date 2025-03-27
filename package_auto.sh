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
BASE_WGET="wget --no-check-certificate -q -O"
# BASE_WGET="wget -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"

packages() {
    # === 基本システム・UI機能 ===
    install_package luci-i18n-base hidden            # 基本UI言語パック
    install_package luci-i18n-opkg hidden            # パッケージ管理UI言語パック
    install_package luci-i18n-firewall hidden        # ファイアウォールUI言語パック
    install_package ttyd hidden                      # ウェブターミナル
    install_package luci-app-ttyd hidden             # ターミナルUI
    install_package luci-i18n-ttyd hidden            # ターミナルUI言語パック
    install_package openssh-sftp-server hidden       # ファイル転送サーバー
    install_package luci-mod-dashboard hidden        # ダッシュボード
    install_package luci-i18n-dashboard hidden       # ダッシュボード言語パック
    install_package coreutils hidden                 # 基本コマンド群

    # === システムパフォーマンス管理 ===
    install_package irqbalance hidden                # CPU負荷分散

    # === ネットワーク管理 ===
    install_package luci-app-sqm hidden              # QoSスマートキューイング
    install_package luci-i18n-sqm hidden             # SQM言語パック
    install_package tc-mod-iptables hidden           # トラフィック制御IPテーブル
    install_package luci-app-qos hidden              # 基本的なQoS
    install_package luci-i18n-qos hidden             # QoS言語パック
    install_package luci-i18n-statistics hidden      # 統計情報
    install_package luci-i18n-nlbwmon hidden         # 帯域監視
    install_package wifischedule hidden              # WiFiスケジュール
    install_package luci-app-wifischedule hidden     # WiFiスケジュールUI
    install_package luci-i18n-wifischedule hidden    # WiFiスケジュール言語パック

    # === セキュリティツール ===
    install_package znc-mod-fail2ban hidden      # 不正アクセス防止
    install_package banip hidden                 # IPブロック
    
    # === テーマおよび見た目 ===
    install_package luci-theme-openwrt hidden        # 標準OpenWrtテーマ
    install_package luci-theme-material hidden       # マテリアルテーマ
    install_package luci-theme-openwrt-2020 hidden   # OpenWrt 2020テーマ

    # === システム更新 ===
    install_package attendedsysupgrade-common hidden       # システムアップグレード共通
    install_package luci-app-attendedsysupgrade hidden     # システムアップグレードUI
    install_package luci-i18n-attendedsysupgrade hidden    # システムアップグレード言語パック
    
    # === ユーティリティ ===
    install_package usleep hidden                     # スリープユーティリティ
    install_package git hidden                        # バージョン管理
    install_package git-http hidden                   # Git HTTP対応
    install_package ca-certificates hidden            # CA証明書

    # === システム監視 ===
    install_package htop hidden                    # インタラクティブプロセスビューア
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf hidden      # CPU性能監視
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-status hidden    # CPUステータス
    feed_package gSpotx2f packages-openwrt current luci-app-temp-status hidden   # 温度ステータス
    feed_package gSpotx2f packages-openwrt current luci-app-log-viewer hidden    # ログビューア

    # === ネットワーク診断ツール ===
    install_package mtr hidden                     # 高機能traceroute
    install_package nmap hidden                    # ネットワークスキャン
    install_package tcpdump hidden                 # パケットキャプチャ

    # === 追加機能（デフォルトで無効） ===
    feed_package gSpotx2f packages-openwrt current internet-detector hidden disabled    # インターネット検知
    feed_package_release lisaac luci-app-diskman hidden disabled                        # ディスク管理
    feed_package_release jerrykuku luci-theme-argon hidden disabled                     # Argonテーマ

    debug_log "DEBUG" "Standard packages installation process completed"
    return 0
}

packages_19() {
    # === 基本システム・UI機能 ===
    install_package wget hidden                      # 基本ダウンローダー(19.07必須)
    install_package luci-i18n-base hidden            # 基本UI言語パック
    install_package luci-i18n-opkg hidden            # パッケージ管理UI言語パック
    install_package luci-i18n-firewall hidden        # ファイアウォールUI言語パック
    install_package ttyd hidden                      # ウェブターミナル
    install_package luci-app-ttyd hidden             # ターミナルUI
    install_package luci-i18n-ttyd hidden            # ターミナルUI言語パック
    install_package openssh-sftp-server hidden       # ファイル転送サーバー
    install_package luci-i18n-dashboard hidden       # ダッシュボード言語パック(19.07互換)
    install_package coreutils hidden                 # 基本コマンド群

    # === システムパフォーマンス管理 ===
    install_package irqbalance hidden                # CPU負荷分散

    # === ネットワーク管理 ===
    install_package luci-app-sqm hidden              # QoSスマートキューイング
    install_package luci-i18n-sqm hidden             # SQM言語パック
    install_package tc-mod-iptables hidden           # トラフィック制御IPテーブル
    install_package luci-app-qos hidden              # 基本的なQoS
    install_package luci-i18n-qos hidden             # QoS言語パック
    install_package luci-i18n-statistics hidden      # 統計情報
    install_package luci-i18n-nlbwmon hidden         # 帯域監視
    install_package wifischedule hidden              # WiFiスケジュール
    install_package luci-app-wifischedule hidden     # WiFiスケジュールUI
    install_package luci-i18n-wifischedule hidden    # WiFiスケジュール言語パック

    install_package znc-mod-fail2ban hidden      # 不正アクセス防止
    install_package banip hidden                 # IPブロック
    
    # === テーマおよび見た目 ===
    install_package luci-theme-openwrt hidden        # 標準OpenWrtテーマ
    install_package luci-theme-material hidden       # マテリアルテーマ
    install_package luci-theme-openwrt-2020 hidden   # OpenWrt 2020テーマ

    # === システム更新 ===
    install_package attendedsysupgrade-common hidden       # システムアップグレード共通
    install_package luci-app-attendedsysupgrade hidden     # システムアップグレードUI
    install_package luci-i18n-attendedsysupgrade hidden    # システムアップグレード言語パック

    # === ユーティリティ ===
    install_package usleep hidden                     # スリープユーティリティ
    install_package git hidden                        # バージョン管理
    install_package git-http hidden                   # Git HTTP対応
    install_package ca-certificates hidden            # CA証明書

    # === システム監視 (19.07特有版) ===
    install_package htop hidden                    # インタラクティブプロセスビューア
    feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf hidden      # CPU性能監視
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-cpu-status-mini hidden # CPU状態(19.07用)
    feed_package gSpotx2f packages-openwrt 19.07 luci-app-log hidden             # ログビューア(19.07用)

    # === ネットワーク診断ツール ===
    install_package mtr hidden                     # 高機能traceroute
    install_package nmap hidden                    # ネットワークスキャン
    install_package tcpdump hidden                 # パケットキャプチャ
    
    # === 追加機能（デフォルトで無効） ===
    feed_package_release lisaac luci-app-diskman hidden disabled                 # ディスク管理
    # feed_package_release jerrykuku luci-theme-argon hidden disabled              # Argonテーマ
    
    debug_log "DEBUG" "19.07 specific packages installation process completed"
    return 0
}

packages_snaphot() {
    # === 基本システム・UI機能 ===
    install_package luci hidden                      # 基本LuCIパッケージ(SNAPSHOT用)
    install_package luci-i18n-base hidden            # 基本UI言語パック
    install_package luci-i18n-opkg hidden            # パッケージ管理UI言語パック
    install_package luci-i18n-firewall hidden        # ファイアウォールUI言語パック
    install_package ttyd hidden                      # ウェブターミナル
    install_package luci-app-ttyd hidden             # ターミナルUI
    install_package luci-i18n-ttyd hidden            # ターミナルUI言語パック
    install_package openssh-sftp-server hidden       # ファイル転送サーバー
    install_package luci-mod-dashboard hidden        # ダッシュボード
    install_package luci-i18n-dashboard hidden       # ダッシュボード言語パック
    install_package coreutils hidden                 # 基本コマンド群

    # === システムパフォーマンス管理 ===
    install_package irqbalance hidden                # CPU負荷分散

    # === ネットワーク管理 ===
    install_package luci-app-sqm hidden              # QoSスマートキューイング
    install_package luci-i18n-sqm hidden             # SQM言語パック
    install_package tc-mod-iptables hidden           # トラフィック制御IPテーブル
    install_package luci-app-qos hidden              # 基本的なQoS
    install_package luci-i18n-qos hidden             # QoS言語パック
    install_package luci-i18n-statistics hidden      # 統計情報
    install_package luci-i18n-nlbwmon hidden         # 帯域監視
    install_package wifischedule hidden              # WiFiスケジュール
    install_package luci-app-wifischedule hidden     # WiFiスケジュールUI
    install_package luci-i18n-wifischedule hidden    # WiFiスケジュール言語パック

    install_package znc-mod-fail2ban hidden      # 不正アクセス防止
    install_package banip hidden                 # IPブロック
    
    # === テーマおよび見た目 ===
    install_package luci-theme-openwrt hidden        # 標準OpenWrtテーマ
    install_package luci-theme-material hidden       # マテリアルテーマ
    install_package luci-theme-openwrt-2020 hidden   # OpenWrt 2020テーマ

    # === システム更新 ===
    install_package attendedsysupgrade-common hidden       # システムアップグレード共通
    install_package luci-app-attendedsysupgrade hidden     # システムアップグレードUI
    install_package luci-i18n-attendedsysupgrade hidden    # システムアップグレード言語パック

    # === システム監視 ===
    install_package htop hidden                    # インタラクティブプロセスビューア

    # === ネットワーク診断ツール ===
    install_package mtr hidden                     # 高機能traceroute
    install_package nmap hidden                    # ネットワークスキャン
    install_package tcpdump hidden                 # パケットキャプチャ
    
    # === ユーティリティ ===
    install_package usleep hidden                     # スリープユーティリティ
    install_package git hidden                        # バージョン管理
    install_package git-http hidden                   # Git HTTP対応
    install_package ca-certificates hidden            # CA証明書

    debug_log "DEBUG" "SNAPSHOT specific packages installation process completed"
    return 0
}

packages_usb() {
    # === 基本USB機能 ===
    install_package block-mount hidden               # ブロックデバイスマウント
    install_package kmod-usb-storage hidden          # USBストレージ基本カーネルモジュール
    install_package kmod-usb-storage-uas hidden      # USB高速プロトコル対応
    install_package usbutils hidden                  # USBユーティリティ
    install_package gdisk hidden                     # GPTパーティション管理
    install_package libblkid1 hidden                 # ブロックデバイスID
    install_package kmod-usb-ledtrig-usb hidden port # USB LED表示トリガー
    install_package luci-app-ledtrig-usbport hidden  # USB LED設定UI

    # === ファイルシステムサポート ===
    install_package dosfstools hidden                # FAT ファイルシステムツール
    install_package kmod-fs-vfat hidden              # FAT カーネルモジュール
    install_package e2fsprogs hidden                 # EXT ファイルシステムツール
    install_package kmod-fs-ext4 hidden              # EXT4 カーネルモジュール
    install_package f2fs-tools hidden                # F2FS ファイルシステムツール
    install_package kmod-fs-f2fs hidden              # F2FS カーネルモジュール
    install_package exfat-fsck hidden                # exFAT ファイルシステムチェック
    install_package kmod-fs-exfat hidden             # exFAT カーネルモジュール
    install_package ntfs-3g hidden                   # NTFS ファイルシステムツール
    install_package kmod-fs-ntfs3 hidden             # NTFS カーネルモジュール
    install_package hfsfsck hidden                   # HFS ファイルシステムチェック
    install_package kmod-fs-hfs hidden               # HFS カーネルモジュール
    install_package kmod-fs-hfsplus hidden           # HFS+ カーネルモジュール

    # === ディスク管理 ===
    install_package hdparm hidden                    # ハードディスク設定ツール
    install_package hd-idle hidden                   # HDDアイドル制御
    install_package luci-app-hd-idle hidden          # HDDアイドルUI
    install_package luci-i18n-hd-idle hidden         # HDDアイドルUI言語パック

    debug_log "DEBUG" "USB and storage related packages installation process completed"
    return 0
}

package_samba() {
    # === ファイル共有 ===
    install_package luci-app-samba4 hidden           # Sambaファイル共有
    install_package luci-i18n-samba4-ja hidden       # Samba日本語UI
    install_package wsdd2 hidden                     # Windows検出サービス

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
main() {
    print_information
    # OSバージョンに基づいたパッケージインストール
    install_packages_by_version
    # USB関連パッケージのインストール
    install_usb_packages
}

# スクリプトの実行
# main "$@"
