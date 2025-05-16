#!/bin/sh

SCRIPT_VERSION="2025.05.16-00-00"

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

# set_wifi_ssid_password: Wi-Fi の SSID とパスワードを設定する
set_wifi_ssid_password() {
    local devices wifi_country_code
    local devices_to_enable=""

    # country.ch から国コードを取得
    wifi_country_code=$("${CACHE_DIR}/language.ch" 2>/dev/null)
    
    if [ -z "$wifi_country_code" ]; then
        echo "$(color red "$(get_message "MSG_ERROR_NO_COUNTRY_CODE")")"
        return 1
    fi

    devices=$(uci show wireless | grep 'wifi-device' | cut -d'=' -f1 | cut -d'.' -f2 | sort -u)

    if [ -z "$devices" ]; then
        echo "$(color red "$(get_message "MSG_NO_WIFI_DEVICES")")"
        return 1
    fi

    for device in $devices; do
        configure_wifi_device "$device" "$wifi_country_code" || continue
        devices_to_enable="$devices_to_enable $device"
    done

    if ! uci commit wireless; then
        echo "$(color red "$(get_message "MSG_COMMIT_FAILED_WIFI")")"
        return 1
    fi

    /etc/init.d/network reload

    for device in $devices_to_enable; do
        echo "$(color green "$(get_message "MSG_WIFI_SETTINGS_UPDATED" "device=$device")")"
    done
}

# WiFiデバイス個別設定
configure_wifi_device() {
    local device="$1"
    local wifi_country_code="$2"
    local band htmode ssid password enable_band confirm iface_num iface

    # バンド情報の取得
    band=$(uci get wireless."$device".band 2>/dev/null)
    htmode=$(uci get wireless."$device".htmode 2>/dev/null)
    
    # バンドの種類を判定
    local band_type
    case "$band" in
        "2g"|"2G") band_type="2.4GHz" ;;
        "5g"|"5G") band_type="5GHz" ;;
        "6g"|"6G") band_type="6GHz" ;;
        *) band_type="$band" ;;
    esac

    # デバイスの情報表示
    echo "$(color green "$(get_message "MSG_WIFI_DEVICE_BAND" "device=$device" "band=$band_type")")"
    echo "$(color yellow "$(get_message "MSG_ENABLE_BAND" "device=$device" "band=$band_type")")"
    read enable_band

    [ "$enable_band" = "y" ] || return 0

    # インターフェース名の生成
    iface_num=$(echo "$device" | grep -o '[0-9]*')
    iface="aios${iface_num}"

    # デフォルトSSIDの生成
    local default_ssid="aios_${band_type}"

    # SSID設定
    while true; do
        echo "$(color yellow "$(get_message "MSG_ENTER_SSID")") [${default_ssid}]: "
        read ssid
        # デフォルトSSIDの使用
        [ -z "$ssid" ] && ssid="$default_ssid"
        [ -n "$ssid" ] && break
        echo "$(color red "$(get_message "MSG_ERROR_EMPTY_SSID")")"
    done

# パスワード設定
while true; do
    echo "$(color yellow "$(get_message "MSG_ENTER_WIFI_PASSWORD")")"
    read password
    echo
    [ ${#password} -ge 8 ] && break
    echo "$(color red "$(get_message "MSG_PASSWORD_TOO_SHORT")")"
done

    # HTモード設定の最適化
    case "$band" in
        "2g"|"2G")
            [ -z "$htmode" ] && htmode="HT20"
            ;;
        "5g"|"5G")
            [ -z "$htmode" ] && htmode="VHT80"
            ;;
        "6g"|"6G")
            [ -z "$htmode" ] && htmode="HE80"
            ;;
    esac

    # 設定確認
    while true; do
        echo "$(color yellow "$(get_message "MSG_WIFI_CONFIG_PREVIEW")")"
        echo "$(color green "$(get_message "MSG_WIFI_BAND_INFO" "band=$band_type")")"
        echo "$(color green "$(get_message "MSG_WIFI_HTMODE_INFO" "mode=$htmode")")"
        echo "$(color green "$(get_message "MSG_CONFIRM_WIFI_SETTINGS" "ssid=$ssid" "password=$password")")"
        read confirm
        case "$confirm" in
            y) break ;;
            n) echo "$(color yellow "$(get_message "MSG_REENTER_INFO")")"
               return 1 ;;
            *) echo "$(color red "$(get_message "MSG_INVALID_YN")")" ;;
        esac
    done

    # WiFi設定の適用
    setup_wifi_interface "$device" "$iface" "$ssid" "$password" "$wifi_country_code" "$htmode"
}

# WiFiインターフェース設定
setup_wifi_interface() {
    local device="$1" iface="$2" ssid="$3" password="$4" country="$5" htmode="$6"

    uci set wireless."$iface"="wifi-iface"
    uci set wireless."$iface".device="$device"
    uci set wireless."$iface".mode='ap'
    uci set wireless."$iface".ssid="$ssid"
    uci set wireless."$iface".key="$password"
    uci set wireless."$iface".encryption='sae-mixed'
    uci set wireless."$iface".network='lan'
    uci set wireless."$device".country="$country"
    [ -n "$htmode" ] && uci set wireless."$device".htmode="$htmode"
    uci -q delete wireless."$device".disabled
}

# set_device: システム全体の設定
set_device() {
    configure_ssh
    configure_system
    configure_network
    configure_dns

    echo "$(color yellow "$(get_message "MSG_PRESS_KEY_REBOOT")")"
    read
    reboot
}

# システム基本設定
configure_system() {
    local description notes zonename timezone
    description=$(cat /etc/openwrt_version) || description="Unknown"
    notes=$(date) || notes="No date"
    
    zonename=$(cat "${CACHE_DIR}/zonename.ch" 2>/dev/null || echo "Unknown")
    timezone=$(cat "${CACHE_DIR}/timezone.ch" 2>/dev/null || echo "UTC")

    echo "$(color yellow "$(get_message "MSG_APPLYING_ZONENAME" "zone=$zonename")")"
    echo "$(color yellow "$(get_message "MSG_APPLYING_TIMEZONE" "timezone=$timezone")")"

    apply_system_settings "$description" "$notes" "$zonename" "$timezone"
    configure_ntp
}

# システム設定の適用
apply_system_settings() {
    local description="$1" notes="$2" zonename="$3" timezone="$4"

    uci set system.@system[0]=system
    uci set system.@system[0].description="$description"
    uci set system.@system[0].zonename="$zonename"
    uci set system.@system[0].timezone="$timezone"
    uci set system.@system[0].conloglevel='6'
    uci set system.@system[0].cronloglevel='9'
    uci set system.@system[0].notes="$notes"
    uci commit system

    /etc/init.d/system reload
}

# ネットワーク設定
configure_network() {
    # ファイアウォール設定
    uci set firewall.@defaults[0].flow_offloading='1'
    
    # Mediatek検出とハードウェアオフロード設定
    if grep -q 'mediatek' /etc/openwrt_release; then
        uci set firewall.@defaults[0].flow_offloading_hw='1'
    fi
    
    uci commit firewall

    # パケットステアリング設定
    uci set network.globals.packet_steering='1'
    uci commit network
}

# DNS設定
configure_dns() {
    # 既存のDNS設定をクリア
    uci -q delete dhcp.lan.dhcp_option
    uci -q delete dhcp.lan.dns

    # IPv4 DNS設定
    uci add_list dhcp.lan.dhcp_option="6,1.1.1.1,8.8.8.8"
    uci add_list dhcp.lan.dhcp_option="6,1.0.0.1,8.8.4.4"

    # IPv6 DNS設定
    uci add_list dhcp.lan.dns="2606:4700:4700::1111"
    uci add_list dhcp.lan.dns="2001:4860:4860::8888"
    uci add_list dhcp.lan.dns="2606:4700:4700::1001"
    uci add_list dhcp.lan.dns="2001:4860:4860::8844"

    # その他のDHCP設定
    uci set dhcp.@dnsmasq[0].cachesize='2000'
    uci set dhcp.lan.leasetime='24h'
    uci commit dhcp
}

# メイン処理
wifi_main() {
    #information
    #set_device_name_password
    #set_wifi_ssid_password
    #set_device
    packages
}

# スクリプトの実行
wifi_main "$@"
