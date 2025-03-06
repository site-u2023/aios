#!/bin/sh

SCRIPT_VERSION="2025.03.06-00-00"

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
# ✅ Use `$(command)` instead of backticks `` `command` ``
# ✅ Use `$(( ))` for arithmetic instead of `let`
# ✅ Define functions as `func_name() {}` (no `function` keyword)
# ✅ No associative arrays (`declare -A` is NOT supported)
# ✅ No here-strings (`<<<` is NOT supported)
# ✅ No `-v` flag in `test` or `[[`
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
# =========================================================
### =========================================================
### 📌 AI Assistance Request: Bug Fixing Procedure
### 
### When debugging or fixing errors in this script, follow these steps:
### 
### 1️⃣ Create a minimal test script to identify the bug.
### 2️⃣ Execute the test and verify the reproducibility of the error.
### 3️⃣ Fix the error and re-run the test to confirm the solution.
### 4️⃣ Apply the corrected code to the production environment.
### 
### ⚠️ DO NOT modify the main script without first confirming the fix 
###     through a dedicated test script.
### 
### 🛠️ Keep the debugging process structured, efficient, and reliable.
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
BUILD_DIR="${BUILD_DIR:-$BASE_DIR/build}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BUILD_DIR" "$FEED_DIR"
#########################################################################
# 本スクリプトは、デバイスの初期設定を行うためのスクリプトです。
# 主な処理内容は以下の通りです：
#  1. 国・ゾーン情報スクリプトのダウンロード
#  2. common-functions.sh のダウンロードと読み込み
#  3. 共通初期化処理 (check_common、country_zone、information) による情報表示
#  4. デバイス名・パスワードの設定 (set_device_name_password)
#  5. Wi-Fi SSID・パスワードの設定 (set_wifi_ssid_password)
#  6. システム全体の設定 (set_device)
#########################################################################
#########################################################################
# information: country_zone で取得済みのゾーン情報を元にシステム情報を表示する
#########################################################################
information() {
    local country_name="$ZONENAME"
    local display_name="$DISPLAYNAME"
    local language_code="$LANGUAGE"
    local country_code="$COUNTRYCODE"

    # メッセージDBからメッセージを取得して表示
    echo -e "$(get_msg "MSG_INFO_COUNTRY" "name=$country_name")"
    echo -e "$(get_msg "MSG_INFO_DISPLAY" "name=$display_name")"
    echo -e "$(get_msg "MSG_INFO_LANG_CODE" "code=$language_code")"
    echo -e "$(get_msg "MSG_INFO_COUNTRY_CODE" "code=$country_code")"
}
#########################################################################
# set_device_name_password: デバイス名とパスワードの設定を行う
# ユーザーから入力を受け、確認後、ubus および uci で更新する
#########################################################################
set_device_name_password() {
    local device_name password confirmation

    echo "$(get_msg "MSG_ENTER_DEVICE_NAME")"
    read device_name
    
    echo -n "$(get_msg "MSG_ENTER_NEW_PASSWORD")"
    read -s password
    echo

    # 設定内容の表示
    echo "Device Name: $device_name"
    echo "Password: $password"
    
    echo -n "$(get_msg "MSG_CONFIRM_DEVICE_SETTINGS")"
    read confirmation
    
    if [ "$confirmation" != "y" ]; then
        echo "$(get_msg "MSG_UPDATE_CANCELLED")"
        return 1
    fi

    echo "Updating password and device name..."
    ubus call luci setPassword "{ \"username\": \"root\", \"password\": \"$password\" }" || {
        echo "$(get_msg "MSG_UPDATE_FAILED_PASSWORD")"
        return 1
    }

    uci set system.@system[0].hostname="$device_name" || {
        echo "$(get_msg "MSG_UPDATE_FAILED_DEVICE")"
        return 1
    }

    uci commit system || {
        echo "$(get_msg "MSG_UPDATE_FAILED_COMMIT")"
        return 1
    }

    echo "$(get_msg "MSG_UPDATE_SUCCESS")"
}

#########################################################################
# set_wifi_ssid_password: Wi-Fi の SSID とパスワードを設定する
# 各 Wi-Fi デバイスごとにユーザー入力を受け、uci コマンドで更新する
#########################################################################
set_wifi_ssid_password() {
    local device iface iface_num ssid password enable_band band htmode devices
    local wifi_country_code=$(echo "$ZONENAME" | awk '{print $4}')
    
    devices=$(uci show wireless | grep 'wifi-device' | cut -d'=' -f1 | cut -d'.' -f2 | sort -u)
    if [ -z "$devices" ]; then
        echo "$(get_msg "MSG_NO_WIFI_DEVICES")"
        exit 1
    fi

    for device in $devices; do
        band=$(uci get wireless."$device".band 2>/dev/null)
        htmode=$(uci get wireless."$device".htmode 2>/dev/null)

        echo "$(get_msg "MSG_WIFI_DEVICE_BAND" "device=$device" "band=$band")"
        echo -n "$(get_msg "MSG_ENABLE_BAND" "device=$device" "band=$band")"
        read enable_band
        if [ "$enable_band" != "y" ]; then
            continue
        fi

        iface_num=$(echo "$device" | grep -o '[0-9]*')
        iface="aios${iface_num}"

        echo -n "$(get_msg "MSG_ENTER_SSID")"
        read ssid
        while true; do
            echo -n "$(get_msg "MSG_ENTER_WIFI_PASSWORD")"
            read -s password
            echo
            if [ "${#password}" -ge 8 ]; then
                break
            else
                echo "$(get_msg "MSG_PASSWORD_TOO_SHORT")"
            fi
        done

        while true; do
            echo "$(get_msg "MSG_CONFIRM_WIFI_SETTINGS" "ssid=$ssid" "password=$password")"
            read confirm
            if [ "$confirm" = "y" ]; then
                break
            elif [ "$confirm" = "n" ]; then
                echo "$(get_msg "MSG_REENTER_INFO")"
                break
            else
                echo "$(get_msg "MSG_INVALID_YN")"
            fi
        done

        # WiFi設定の適用
        uci set wireless."$iface"="wifi-iface"
        uci set wireless."$iface".device="${device:-aios}"
        uci set wireless."$iface".mode='ap'
        uci set wireless."$iface".ssid="${ssid:-openwrt}"
        uci set wireless."$iface".key="${password:-password}"
        uci set wireless."$iface".encryption="${encryption:-sae-mixed}"
        uci set wireless."$iface".network='lan'
        uci set wireless."$device".country="$wifi_country_code"
        uci -q delete wireless."$device".disabled

        devices_to_enable="$devices_to_enable $device"
    done

    uci commit wireless
    /etc/init.d/network reload

    for device in $devices_to_enable; do
        echo "$(get_msg "MSG_WIFI_SETTINGS_UPDATED" "device=$device")"
    done
}
#########################################################################
# set_device: デバイス全体の設定を行い、最終的にリブートを実行する
#  ※ SSH ドロップベア設定、システム設定、NTP サーバ設定、ファイアウォール・パケットスティアリング、
#     カスタム DNS 設定などを uci コマンドで行う。
#########################################################################
set_device() {
    # SSH アクセス用のインターフェース設定
    uci set dropbear.@dropbear[0].Interface='lan'
    uci commit dropbear

    # システム基本設定
    local DESCRIPTION NOTES _zonename _timezone
    DESCRIPTION=$(cat /etc/openwrt_version) || DESCRIPTION="Unknown"
    NOTES=$(date) || NOTES="No date"
    # ZONENAME, TIMEZONE は country_zone で取得済み、TIMEZONE は select_timezone で選択
    _zonename=$(echo "$ZONENAME" | awk '{print $1}' 2>/dev/null || echo "Unknown")
    _timezone="${TIMEZONE:-UTC}"

    echo "Applying zonename settings: $_zonename"
    echo "Applying timezone settings: $_timezone"

    uci set system.@system[0]=system
    #uсi set system.@system[0].hostname=${HOSTNAME}  # 必要に応じてコメント解除
    uci set system.@system[0].description="${DESCRIPTION}"
    uci set system.@system[0].zonename="$_zonename"
    uci set system.@system[0].timezone="$_timezone"
    uci set system.@system[0].conloglevel='6'
    uci set system.@system[0].cronloglevel='9'
    # NTP サーバ設定
    uci set system.ntp.enable_server='1'
    uci set system.ntp.use_dhcp='0'
    uci set system.ntp.interface='lan'
    uci delete system.ntp.server
    uci add_list system.ntp.server='0.pool.ntp.org'
    uci add_list system.ntp.server='1.pool.ntp.org'
    uci add_list system.ntp.server='2.pool.ntp.org'
    uci add_list system.ntp.server='3.pool.ntp.org'
    uci commit system
    /etc/init.d/system reload
    /etc/init.d/sysntpd restart
    # ノート設定
    uci set system.@system[0].notes="${NOTES}"
    uci commit system
    /etc/init.d/system reload

    # ソフトウェアフローオフロード
    uci set firewall.@defaults[0].flow_offloading='1'
    uci commit firewall

    # ハードウェアフローオフロード（mediatek 判定）
    local Hardware_flow_offload
    Hardware_flow_offload=$(grep 'mediatek' /etc/openwrt_release)
    if [ "${Hardware_flow_offload:16:8}" = "mediatek" ]; then
        uci set firewall.@defaults[0].flow_offloading_hw='1'
        uci commit firewall
    fi

    # パケットステアリング
    uci set network.globals.packet_steering='1'
    uci commit network

    # カスタム DNS 設定
    uci -q delete dhcp.lan.dhcp_option
    uci -q delete dhcp.lan.dns
    # IPV4 DNS
    uci add_list dhcp.lan.dhcp_option="6,1.1.1.1,8.8.8.8"
    uci add_list dhcp.lan.dhcp_option="6,1.0.0.1,8.8.4.4"
    # IPV6 DNS
    uci add_list dhcp.lan.dns="2606:4700:4700::1111"
    uci add_list dhcp.lan.dns="2001:4860:4860::8888"
    uci add_list dhcp.lan.dns="2606:4700:4700::1001"
    uci add_list dhcp.lan.dns="2001:4860:4860::8844"
    uci set dhcp.@dnsmasq[0].cachesize='2000'
    uci set dhcp.lan.leasetime='24h'
    uci commit dhcp

    # ネットワークサービスの再起動
    #/etc/init.d/dnsmasq restart
    #/etc/init.d/odhcpd restart

    # 再起動確認メッセージ
    read -p "$(get_msg "MSG_PRESS_KEY_REBOOT")"
    reboot
}

#########################################################################
# メイン処理の開始
#########################################################################
download_country_zone
download_and_execute_common
check_common "$INPUT_LANG"

# 国選択プロセスの実行（新規実装の関数）
process_country_selection

# 国・言語・ゾーン情報の表示
information

# タイムゾーンの選択（common-functions.sh の関数を利用）
select_timezone "$SELECTED_COUNTRY"

# デバイス設定（必要に応じてコメントアウト解除）
#set_device_name_password
#set_wifi_ssid_password
#set_device
