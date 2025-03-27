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

# USBデバイスを検出し、必要なパッケージをインストールする関数
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
        packages_usb
    else
        debug_log "DEBUG" "No USB device detected, skipping USB packages"
    fi
    
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

install_minimal_packages() {
    debug_log "DEBUG" "Installing minimal essential packages"
    
    # === 基本システム・UI機能（最小限） ===
    install_package luci-i18n-base hidden            # 基本UI言語パック
    install_package luci-i18n-firewall hidden        # ファイアウォールUI言語パック
    install_package ttyd hidden                      # ウェブターミナル
    install_package openssh-sftp-server hidden       # ファイル転送サーバー
    install_package coreutils hidden                 # 基本コマンド群

    # === ネットワーク管理（最小限） ===
    install_package luci-app-sqm hidden              # QoSスマートキューイング
    
    # === テーマ（最小限） ===
    install_package luci-theme-openwrt hidden        # 標準OpenWrtテーマ
    
    debug_log "DEBUG" "Minimal package installation completed"
    return 0
}

install_full_packages() {
    debug_log "DEBUG" "Installing full package set"
    
    # 標準パッケージをインストール
    install_packages_by_version
    
    # 追加のパッケージ（通常は無効なもの）をインストールして有効化
    install_additional_packages
    
    debug_log "DEBUG" "Full package installation completed"
    return 0
}

install_additional_packages() {
    debug_log "DEBUG" "Installing and enabling additional packages"
    
    # === 追加機能（通常は無効だが、フルインストールでは有効化） ===
    feed_package gSpotx2f packages-openwrt current internet-detector hidden       # インターネット検知（有効化）
    feed_package_release lisaac luci-app-diskman hidden                           # ディスク管理（有効化）
    feed_package_release jerrykuku luci-theme-argon hidden                        # Argonテーマ（有効化）
    
    debug_log "DEBUG" "Additional package installation completed"
    return 0
}

package_auto_install() {
    local install_type="$1"
    
    # インストール開始メッセージ
    printf "\n%s\n" "$(color blue "$(get_message "MSG_INSTALLING_PACKAGES")")"
    
    # タイプ別のインストール処理
    case "$install_type" in
        standard)
            # 標準インストール
            debug_log "DEBUG" "Proceeding with standard installation"
            install_packages_by_version
            check_and_install_usb
            ;;
        minimal)
            # 必須（最小）インストール
            debug_log "DEBUG" "Proceeding with minimal installation"
            install_minimal_packages
            check_and_install_usb
            ;;
        full)
            # フル（全部）インストール
            debug_log "DEBUG" "Proceeding with full installation"
            install_full_packages
            check_and_install_usb
            install_package_samba
            ;;
    esac
    
    # インストール完了メッセージ
    printf "\n%s\n" "$(color green "$(get_message "MSG_INSTALL_COMPLETED")")"
    
    return 0
}

# メイン処理
package_auto_main() {
    local install_type=""
    print_information
    
    # インストールタイプの選択
    printf "%s\n" "$(color white "$(get_message "MSG_PACKAGE_AUTO_SELECT")")"
    printf "[1] %s\n" "$(color white "$(get_message "MSG_PACKAGE_STANDARD")")"
    printf "[2] %s\n" "$(color yellow "$(get_message "MSG_PACKAGE_MINIMAL")")"
    printf "[3] %s\n" "$(color green "$(get_message "MSG_PACKAGE_FULL")")"
    printf "[0] %s\n" "$(color red "$(get_message "MSG_PACKAGE_SKIP")")"
    
    # ユーザー入力の取得
    printf "%s " "$(color white "$(get_message "MSG_SELECT_NUMBER")")"
    read -r selection
    
    # 入力を正規化
    selection=$(normalize_input "$selection")
    
    case "$selection" in
        1|"")  # デフォルト選択
            debug_log "DEBUG" "User selected standard installation"
            install_type="standard"
            ;;
        2)
            debug_log "DEBUG" "User selected minimal installation"
            install_type="minimal"
            ;;
        3)
            debug_log "DEBUG" "User selected full installation"
            install_type="full"
            ;;
        0|[Nn])
            debug_log "DEBUG" "User skipped package installation"
            printf "%s\n" "$(color yellow "$(get_message "MSG_PACKAGE_AUTO_SKIPPED")")"
            return 0
            ;;
        *)
            debug_log "DEBUG" "Invalid selection, defaulting to standard installation"
            install_type="standard"
            ;;
    esac
    
    # 選択に基づいてインストールを実行
    package_auto_install "$install_type"
    
    return 0
}

# スクリプトの実行
# package_auto_main "$@"
