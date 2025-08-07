#!/bin/sh

# uci-defaults MAP-E Auto Setup for OpenWrt (Modular Version)
# Place this file in firmware at: /etc/uci-defaults/99-mape-setup

# Beware! This script will be in /rom/etc/uci-defaults/ as part of the image.
# Uncomment lines to apply:
#
# ROOT_PASSWORD="your_password"
# LAN_IP_ADDRESS="192.168.1.1"
# WLAN_NAME="MyOpenWrt"
# WLAN_PASSWORD="12345678"
#
# PPPOE_USERNAME="your_isp_username"
# PPPOE_PASSWORD="your_isp_password"

API_URL="https://mape-auto.site-u.workers.dev/"
WAN_DEF="wan"
WAN6_NAME="wanmap6"
WANMAP_NAME="wanmap"

# Global variables for device configuration (uncomment to use)
# ROOT_PASSWORD=""
# LAN_IP_ADDRESS=""
# WLAN_NAME=""
# WLAN_PASSWORD=""
# PPPOE_USERNAME=""
# PPPOE_PASSWORD=""

# Global variables for API response data
API_RESPONSE=""
BR=""
EALEN=""
IPV4_PREFIX=""
IPV4_PREFIXLEN=""
IPV6_PREFIX=""
IPV6_PREFIXLEN=""
PSID_OFFSET=""
COUNTRY=""
TIMEZONE=""
OS_VERSION=""

# Function 1: OpenWrtネットワークAPIでIPv6アドレス取得を待機
wait_for_ipv6() {
    local timeout=60
    local count=0
    local ipv6_addr=""
    
    logger -t mape-setup "Waiting for IPv6 address..."
    
    # ネットワーク関数をロード
    . /lib/functions.sh
    . /lib/functions/network.sh
    
    while [ $count -lt $timeout ]; do
        network_flush_cache
        network_find_wan6 wan6_iface
        
        if [ -n "$wan6_iface" ]; then
            # IPv6アドレスまたはプレフィックスを取得
            if network_get_ipaddr6 ipv6_addr "$wan6_iface" && [ -n "$ipv6_addr" ]; then
                logger -t mape-setup "IPv6 address obtained: $ipv6_addr"
                return 0
            elif network_get_prefix6 ipv6_addr "$wan6_iface" && [ -n "$ipv6_addr" ]; then
                logger -t mape-setup "IPv6 prefix obtained: $ipv6_addr"
                return 0
            fi
        fi
        
        sleep 2
        count=$((count + 2))
    done
    
    logger -t mape-setup "IPv6 address not available after ${timeout}s"
    return 1
}

# Function 2: Cloudflareワーカーから情報取得
fetch_cloudflare_info() {
    logger -t mape-setup "Fetching configuration from Cloudflare Worker..."
    
    # APIから設定情報を取得
    API_RESPONSE=$(wget -6 -q -O - --timeout=30 "$API_URL" 2>/dev/null)

    if [ -z "$API_RESPONSE" ]; then
        logger -t mape-setup "Failed to fetch API response"
        return 1
    fi

    # MAP-Eルールが見つかったかチェック
    local rule_exists=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule' 2>/dev/null)
    if [ -z "$rule_exists" ] || [ "$rule_exists" = "null" ]; then
        logger -t mape-setup "No MAP-E rule found for this IPv6 address"
        return 1
    fi

    # API レスポンスから値を抽出
    BR=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule.brIpv6Address' 2>/dev/null)
    EALEN=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule.eaBitLength' 2>/dev/null)
    IPV4_PREFIX=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule.ipv4Prefix' 2>/dev/null)
    IPV4_PREFIXLEN=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule.ipv4PrefixLength' 2>/dev/null)
    IPV6_PREFIX=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule.ipv6Prefix' 2>/dev/null)
    IPV6_PREFIXLEN=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule.ipv6PrefixLength' 2>/dev/null)
    PSID_OFFSET=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule.psIdOffset' 2>/dev/null)

    # 地域情報も取得
    COUNTRY=$(echo "$API_RESPONSE" | jsonfilter -e '@.country' 2>/dev/null)
    TIMEZONE=$(echo "$API_RESPONSE" | jsonfilter -e '@.timezone' 2>/dev/null)

    # 必須パラメータのチェック
    if [ -z "$BR" ] || [ -z "$EALEN" ] || [ -z "$IPV4_PREFIX" ] || [ -z "$IPV4_PREFIXLEN" ] || [ -z "$IPV6_PREFIX" ] || [ -z "$IPV6_PREFIXLEN" ] || [ -z "$PSID_OFFSET" ]; then
        logger -t mape-setup "Missing required MAP-E parameters"
        return 1
    fi

    logger -t mape-setup "Configuration fetched successfully (BR: $BR, Country: $COUNTRY, TZ: $TIMEZONE)"
    return 0
}

# Function 3: タイムゾーン＆国コード設定
set_timezone_country() {
    logger -t mape-setup "Setting timezone and country..."
    
    # システム設定（タイムゾーン）
    if [ -n "$TIMEZONE" ]; then
        uci set system.@system[0].timezone="$TIMEZONE" >/dev/null 2>&1
        logger -t mape-setup "Set timezone to $TIMEZONE"
    fi

    return 0
}

# Function 4: Wi-Fi設定（国コード）
set_wifi_config() {
    logger -t mape-setup "Setting WiFi configuration..."
    
    # 国コード設定関数
    set_country_code() {
        local device="$1"
        uci set wireless.${device}.country="$COUNTRY" >/dev/null 2>&1
    }

    # ワイヤレス設定（国コード）
    if [ -n "$COUNTRY" ]; then
        # 全ての無線デバイスに国コードを設定
        . /lib/functions.sh
        config_load wireless
        config_foreach set_country_code wifi-device
        logger -t mape-setup "Set country code to $COUNTRY"
    fi

    return 0
}

# Function 5: MAP-E設定
set_mape_config() {
    logger -t mape-setup "Configuring MAP-E..."
    
    # OpenWrtバージョンを取得
    if [ -f "/etc/openwrt_release" ]; then
        OS_VERSION=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d"'" -f2 2>/dev/null)
    fi

    # 既存のWAN/WAN6を無効化
    uci set network.wan.disabled='1' >/dev/null 2>&1
    uci set network.wan.auto='0' >/dev/null 2>&1
    uci set network.wan6.disabled='1' >/dev/null 2>&1
    uci set network.wan6.auto='0' >/dev/null 2>&1

    # WAN6インターフェース設定（DHCPv6）
    uci delete network.${WAN6_NAME} >/dev/null 2>&1
    uci set network.${WAN6_NAME}=interface
    uci set network.${WAN6_NAME}.proto='dhcpv6'
    uci set network.${WAN6_NAME}.device="${WAN_DEF}"
    uci set network.${WAN6_NAME}.reqaddress='try'
    uci set network.${WAN6_NAME}.reqprefix='auto'

    # MAP-Eインターフェース設定
    uci delete network.${WANMAP_NAME} >/dev/null 2>&1
    uci set network.${WANMAP_NAME}=interface
    uci set network.${WANMAP_NAME}.proto='map'
    uci set network.${WANMAP_NAME}.maptype='map-e'
    uci set network.${WANMAP_NAME}.peeraddr="${BR}"
    uci set network.${WANMAP_NAME}.ipaddr="${IPV4_PREFIX}"
    uci set network.${WANMAP_NAME}.ip4prefixlen="${IPV4_PREFIXLEN}"
    uci set network.${WANMAP_NAME}.ip6prefix="${IPV6_PREFIX}"
    uci set network.${WANMAP_NAME}.ip6prefixlen="${IPV6_PREFIXLEN}"
    uci set network.${WANMAP_NAME}.ealen="${EALEN}"
    uci set network.${WANMAP_NAME}.offset="${PSID_OFFSET}"
    uci set network.${WANMAP_NAME}.mtu='1460'
    uci set network.${WANMAP_NAME}.encaplimit='ignore'

    # OpenWrt バージョン別設定
    if echo "$OS_VERSION" | grep -q "^19"; then
        uci delete network.${WANMAP_NAME}.legacymap >/dev/null 2>&1
        uci delete network.${WANMAP_NAME}.tunlink >/dev/null 2>&1
        uci add_list network.${WANMAP_NAME}.tunlink="${WAN6_NAME}"
    else
        uci set network.${WANMAP_NAME}.legacymap='1'
        uci set network.${WANMAP_NAME}.tunlink="${WAN6_NAME}"
    fi

    # DHCP設定
    uci delete dhcp.${WAN6_NAME} >/dev/null 2>&1
    uci set dhcp.${WAN6_NAME}=dhcp
    uci set dhcp.${WAN6_NAME}.interface="${WAN6_NAME}"
    uci set dhcp.${WAN6_NAME}.master='1'
    uci set dhcp.${WAN6_NAME}.ra='relay'
    uci set dhcp.${WAN6_NAME}.dhcpv6='relay'
    uci set dhcp.${WAN6_NAME}.ndp='relay'

    # OpenWrt 21.02+のみでignore設定
    if ! echo "$OS_VERSION" | grep -q "^19"; then
        uci set dhcp.${WAN6_NAME}.ignore='1'
    fi

    # LANでIPv6リレー有効化
    uci set dhcp.lan.ra='relay' >/dev/null 2>&1
    uci set dhcp.lan.dhcpv6='relay' >/dev/null 2>&1
    uci set dhcp.lan.ndp='relay' >/dev/null 2>&1
    uci set dhcp.lan.force='1' >/dev/null 2>&1

    # ファイアウォール設定
    uci add_list firewall.@zone[1].network="${WANMAP_NAME}" >/dev/null 2>&1
    uci add_list firewall.@zone[1].network="${WAN6_NAME}" >/dev/null 2>&1
    uci set firewall.@zone[1].masq='1' >/dev/null 2>&1
    uci set firewall.@zone[1].mtu_fix='1' >/dev/null 2>&1

    logger -t mape-setup "MAP-E configuration completed (OpenWrt: $OS_VERSION)"
    return 0
}

# Function 6: PPPoE設定
set_pppoe_config() {
    logger -t mape-setup "Setting PPPoE configuration..."
    
    # PPPoE設定（公式フォーマットに準拠）
    if [ -n "$PPPOE_USERNAME" ] && [ -n "$PPPOE_PASSWORD" ]; then
        logger -t mape-setup "Configuring PPPoE with username: $PPPOE_USERNAME"
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$PPPOE_USERNAME"
        uci set network.wan.password="$PPPOE_PASSWORD"
        
        # WAN6も無効化（PPPoE使用時）
        uci set network.wan6.disabled='1' >/dev/null 2>&1
        uci set network.wan6.auto='0' >/dev/null 2>&1
        
        # MAP-E関連インターフェースを削除（競合回避）
        uci delete network.${WAN6_NAME} >/dev/null 2>&1
        uci delete network.${WANMAP_NAME} >/dev/null 2>&1
        uci delete dhcp.${WAN6_NAME} >/dev/null 2>&1
        
        logger -t mape-setup "PPPoE configuration completed"
    else
        logger -t mape-setup "PPPoE username or password not set, skipping PPPoE configuration"
    fi
    
    return 0
}

# Function 7: デバイス基本設定（パスワード、IP、Wi-Fi名）
set_device_basic_config() {
    logger -t mape-setup "Setting device basic configuration..."
    
    # ログ出力設定（公式フォーマットに準拠）
    exec >/tmp/setup.log 2>&1
    
    # rootパスワード設定
    if [ -n "$ROOT_PASSWORD" ]; then
        logger -t mape-setup "Setting root password"
        (echo "$ROOT_PASSWORD"; sleep 1; echo "$ROOT_PASSWORD") | passwd > /dev/null
    fi
    
    # LAN IPアドレス設定
    if [ -n "$LAN_IP_ADDRESS" ]; then
        logger -t mape-setup "Setting LAN IP address to $LAN_IP_ADDRESS"
        uci set network.lan.ipaddr="$LAN_IP_ADDRESS"
    fi
    
    # WLAN設定（SSID & パスワード）
    if [ -n "$WLAN_NAME" ] && [ -n "$WLAN_PASSWORD" ] && [ ${#WLAN_PASSWORD} -ge 8 ]; then
        logger -t mape-setup "Setting WLAN: $WLAN_NAME"
        uci set wireless.@wifi-device[0].disabled='0'
        uci set wireless.@wifi-iface[0].disabled='0'
        uci set wireless.@wifi-iface[0].encryption='psk2'
        uci set wireless.@wifi-iface[0].ssid="$WLAN_NAME"
        uci set wireless.@wifi-iface[0].key="$WLAN_PASSWORD"
    fi
    
    return 0
}
openwrt_main() {
    logger -t mape-setup "Starting OpenWrt auto configuration..."
    
    # 1. IPv6接続が利用可能になるまで待機
    if ! wait_for_ipv6; then
        logger -t mape-setup "IPv6 address not available, skipping MAP-E setup"
        exit 0
    fi

    # 2. Cloudflareワーカーから情報取得
    if ! fetch_cloudflare_info; then
        logger -t mape-setup "Failed to fetch configuration, skipping setup"
        exit 0
    fi

    # 3. タイムゾーン＆国コード設定
    set_timezone_country

    # 4. Wi-Fi設定
    set_wifi_config

    # 5. MAP-E設定
    set_mape_config

    # 6. 設定をコミット
    uci commit system >/dev/null 2>&1
    uci commit wireless >/dev/null 2>&1
    uci commit network
    uci commit dhcp  
    uci commit firewall

    logger -t mape-setup "OpenWrt auto configuration completed successfully (Country: $COUNTRY, Timezone: $TIMEZONE)"
    echo "All done!"
    return 0
}

# Function 9: PPPoE専用メイン実行関数
openwrt_pppoe_main() {
    logger -t mape-setup "Starting OpenWrt PPPoE configuration..."
    
    # PPPoEの場合はIPv6待機不要、直接設定開始
    
    # 1. デバイス基本設定
    set_device_basic_config
    
    # 2. PPPoE設定
    set_pppoe_config
    
    # 3. 設定をコミット
    uci commit system >/dev/null 2>&1
    uci commit wireless >/dev/null 2>&1
    uci commit network
    uci commit dhcp  
    uci commit firewall

    logger -t mape-setup "OpenWrt PPPoE configuration completed successfully"
    echo "All done!"
    return 0
}

# Execute main function (choose one)
# For MAP-E auto setup:
openwrt_main

# For PPPoE setup (uncomment this and comment out openwrt_main):
# openwrt_pppoe_main

exit 0
