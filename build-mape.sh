#!/bin/sh

# uci-defaults MAP-E Auto Setup for OpenWrt
# Place this file in firmware at: /etc/uci-defaults/99-mape-setup

API_URL="https://mape-auto.site-u.workers.dev/"
WAN_DEF="wan"
WAN6_NAME="wanmap6"
WANMAP_NAME="wanmap"

# OpenWrtネットワークAPIでIPv6アドレス取得を待機
wait_for_ipv6() {
    local timeout=60
    local count=0
    local ipv6_addr=""
    
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
    
    return 1
}

# IPv6接続が利用可能になるまで待機
if ! wait_for_ipv6; then
    logger -t mape-setup "IPv6 address not available, skipping MAP-E setup"
    exit 0
fi

# APIから設定情報を取得
API_RESPONSE=$(wget -6 -q -O - --timeout=30 "$API_URL" 2>/dev/null)

if [ -z "$API_RESPONSE" ]; then
    logger -t mape-setup "Failed to fetch MAP-E configuration from API"
    exit 0
fi

# MAP-Eルールが見つかったかチェック
RULE_EXISTS=$(echo "$API_RESPONSE" | jsonfilter -e '@.rule' 2>/dev/null)
if [ -z "$RULE_EXISTS" ] || [ "$RULE_EXISTS" = "null" ]; then
    logger -t mape-setup "No MAP-E rule found for this IPv6 address"
    exit 0
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
    exit 0
fi

# OpenWrtバージョンを取得
OS_VERSION=""
if [ -f "/etc/openwrt_release" ]; then
    OS_VERSION=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d"'" -f2 2>/dev/null)
fi

# 国コード設定関数
set_country_code() {
    local device="$1"
    uci set wireless.${device}.country="$COUNTRY" >/dev/null 2>&1
}

logger -t mape-setup "Configuring MAP-E (OpenWrt: $OS_VERSION, BR: $BR, Country: $COUNTRY, TZ: $TIMEZONE)"

# システム設定（タイムゾーン）
if [ -n "$TIMEZONE" ]; then
    uci set system.@system[0].timezone="$TIMEZONE" >/dev/null 2>&1
    logger -t mape-setup "Set timezone to $TIMEZONE"
fi

# ワイヤレス設定（国コード）
if [ -n "$COUNTRY" ]; then
    # 全ての無線デバイスに国コードを設定
    . /lib/functions.sh
    config_load wireless
    config_foreach set_country_code wifi-device
    logger -t mape-setup "Set country code to $COUNTRY"
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

# 設定をコミット
uci commit system >/dev/null 2>&1
uci commit wireless >/dev/null 2>&1
uci commit network
uci commit dhcp  
uci commit firewall

logger -t mape-setup "MAP-E configuration completed successfully (Country: $COUNTRY, Timezone: $TIMEZONE)"

exit 0
