#!/bin/sh

SCRIPT_VERSION="2025.04.03-00-00"

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
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
DEBUG_MODE="${DEBUG_MODE:-false}"
BIN_PATH=$(readlink -f "$0")
BIN_DIR="$(dirname "$BIN_PATH")"
BIN_FILE="$(basename "$BIN_PATH")"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# ネットワークライブラリの読み込み
nuro_load_network_libs() {
    if [ -f "/lib/functions/network.sh" ]; then
        . /lib/functions/network.sh
        network_flush_cache
        debug_log "DEBUG" "OpenWrt network libraries loaded"
        return 0
    else
        debug_log "DEBUG" "OpenWrt network libraries not found"
        return 1
    fi
}

# OpenWrtバージョンの取得
nuro_get_openwrt_version() {
    local version=""
    
    if [ -f "$CACHE_DIR/osversion.ch" ]; then
        version=$(cat "$CACHE_DIR/osversion.ch")
        debug_log "DEBUG" "OpenWrt version from cache: $version"
    elif [ -f "/etc/openwrt_release" ]; then
        version=$(grep -E "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2)
        debug_log "DEBUG" "Retrieved OpenWrt version: $version"
    else
        version="unknown"
        debug_log "DEBUG" "Unable to determine OpenWrt version"
    fi
    
    # メジャーバージョンのみを抽出（例: 21.02 → 21）
    echo "$version" | cut -d '.' -f 1
}

# IPv6アドレスの取得
nuro_get_ipv6_address() {
    local ipv6_addr=""
    local net_if6=""
    
    # OpenWrtのネットワーク関数を使用
    if nuro_load_network_libs; then
        network_find_wan6 net_if6
        if [ -n "$net_if6" ]; then
            network_get_ipaddr6 ipv6_addr "$net_if6"
            if [ -n "$ipv6_addr" ]; then
                debug_log "DEBUG" "Found IPv6 using OpenWrt network functions: $ipv6_addr"
                echo "$ipv6_addr"
                return 0
            fi
        fi
    fi
    
    # 代替方法でIPv6アドレス取得
    ipv6_addr=$(ip -6 addr show scope global | grep inet6 | head -n1 | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$ipv6_addr" ]; then
        debug_log "DEBUG" "Found IPv6 using ip command: $ipv6_addr"
        echo "$ipv6_addr"
        return 0
    fi
    
    printf "%s\n" "$(color red "IPv6アドレスを取得できませんでした")" >&2
    return 1
}

# NUROのIPv6アドレスか確認
nuro_is_ipv6_nuro() {
    local ipv6="$1"
    local ipv6_prefix_pattern="240b:10:[0-9a-f:]"
    
    if echo "$ipv6" | grep -q "^$ipv6_prefix_pattern"; then
        debug_log "DEBUG" "IPv6 address matches NURO pattern"
        return 0
    else
        debug_log "DEBUG" "IPv6 address does not match NURO pattern"
        return 1
    fi
}

# IPv6プレフィックスを取得（NURO向け）
nuro_get_ipv6_prefix() {
    local ipv6_addr="$1"
    local ipv6_prefix_length="40"  # NURO特有のプレフィックス長
    
    debug_log "DEBUG" "Extracting NURO IPv6 prefix from: $ipv6_addr"
    
    if [ -z "$ipv6_addr" ]; then
        printf "%s\n" "$(color red "IPv6アドレスが指定されていません")" >&2
        return 1
    fi
    
    # NUROのIPv6アドレスかチェック
    if ! nuro_is_ipv6_nuro "$ipv6_addr"; then
        printf "%s\n" "$(color red "このIPv6アドレスはNURO光のものではありません (240b:10で始まりません)")" >&2
        return 1
    fi
    
    # プレフィックス部分の取得（NURO特有の処理）
    # NUROは240b:10::/32から始まり、その後に顧客識別子が続く
    local prefix
    prefix=$(echo "$ipv6_addr" | awk -F: '{print $1":"$2":"$3}')
    
    if [ -n "$prefix" ]; then
        local full_prefix="${prefix}::/40"
        debug_log "DEBUG" "Extracted NURO IPv6 prefix: $full_prefix"
        echo "$full_prefix"
        return 0
    fi
    
    printf "%s\n" "$(color red "IPv6プレフィックスの抽出に失敗しました")" >&2
    return 1
}

# NURO MAP-E設定を適用
nuro_apply_mape_config() {
    local ipv6_prefix="$1"
    local major_version="$2"
    
    # NURO MAP-E固定パラメータ（ローカル変数）
    local br_address="2404:9200:225:100::64"  # NURO光のBRアドレス
    local ipv4_prefix="106.72.0.0/16"         # NURO光のIPv4プレフィックス
    local ea_length="12"                      # NURO特有のEA-bit長
    local psid_offset="4"                     # PSIDオフセット
    local psid_len="8"                        # NURO特有のPSID長（8ビット）
    local ipv6_prefix_length="40"             # NURO特有のIPv6プレフィックス長
    local wan_iface="wan"
    local wan6_iface="wan6"
    local mape_iface="mape"

    local ipv6_prefix_clean=$(echo "$ipv6_prefix" | sed 's/\/.*$//')
    local ipv4_prefix_len=$(echo "$ipv4_prefix" | cut -d/ -f2)
    
    printf "%s\n" "$(color green "NURO光 MAP-E設定をOpenWrt $major_version向けに適用します...")"
    
    # 設定のバックアップ作成
    cp /etc/config/network /etc/config/network.nuro.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.nuro.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.nuro.bak 2>/dev/null
    
    # WAN設定
    uci set network.wan.auto='0'
    
    # MAP-E設定
    uci set network.${mape_iface}=interface
    uci set network.${mape_iface}.proto='map'
    uci set network.${mape_iface}.maptype='map-e'
    uci set network.${mape_iface}.peeraddr="$br_address"
    uci set network.${mape_iface}.ipaddr="${ipv4_prefix%/*}"
    uci set network.${mape_iface}.ip4prefixlen="$ipv4_prefix_len"
    uci set network.${mape_iface}.ip6prefix="$ipv6_prefix_clean"
    uci set network.${mape_iface}.ip6prefixlen="$ipv6_prefix_length"
    uci set network.${mape_iface}.ealen="$ea_length"
    uci set network.${mape_iface}.psidlen="$psid_len"
    uci set network.${mape_iface}.offset="$psid_offset"
    uci set network.${mape_iface}.tunlink="$wan6_iface"
    uci set network.${mape_iface}.mtu='1460'
    uci set network.${mape_iface}.encaplimit='ignore'
    
    # OpenWrtバージョン固有の設定
    if [ "$major_version" -ge 21 ] || [ "$major_version" = "SN" ]; then
        debug_log "DEBUG" "Setting OpenWrt $major_version specific options"
        uci set network.${mape_iface}.legacymap='1'
        uci set dhcp.wan6.interface='wan6'
        uci set dhcp.wan6.ignore='1'
    elif [ "$major_version" = "19" ]; then
        debug_log "DEBUG" "Setting OpenWrt 19 specific options"
        uci add_list network.${mape_iface}.tunlink='wan6'
    fi
    
    # DHCP設定
    uci set dhcp.wan6=dhcp
    uci set dhcp.wan6.master='1'
    uci set dhcp.wan6.ra='relay'
    uci set dhcp.wan6.dhcpv6='relay'
    uci set dhcp.wan6.ndp='relay'
    
    # ファイアウォール設定
    uci del_list firewall.@zone[1].network='wan' 2>/dev/null
    uci add_list firewall.@zone[1].network="$mape_iface"
    
    # 設定の保存と適用
    uci commit network
    uci commit firewall
    uci commit dhcp
    
    printf "%s\n" "$(color green "NURO光 MAP-E設定を適用しました")"
    printf "%s: %s\n" "$(color cyan "IPv6プレフィックス")" "$ipv6_prefix"
    printf "%s: %s\n" "$(color cyan "ブリッジルータアドレス")" "$br_address"
    printf "%s: %s\n" "$(color cyan "IPv4プレフィックス")" "$ipv4_prefix"
    printf "%s\n" "$(color yellow "設定を有効にするためシステムを再起動します...")"
    
    # 3秒待ってから再起動
    sleep 3
    reboot
    
    return 0
}

# メイン処理
Internet_nuro_main() {
    printf "%s\n" "$(color blue "NURO光 MAP-E設定スクリプト v${SCRIPT_VERSION}")"
    printf "%s\n" "$(color blue "========================================")"
    
    # IPv6アドレスの取得
    printf "%s\n" "$(color green "IPv6アドレスを取得中...")"
    local ipv6_addr
    ipv6_addr=$(nuro_get_ipv6_address)
    if [ $? -ne 0 ] || [ -z "$ipv6_addr" ]; then
        printf "%s\n" "$(color red "エラー: IPv6アドレスの取得に失敗しました")"
        exit 1
    fi
    printf "%s: %s\n" "$(color cyan "IPv6アドレス")" "$ipv6_addr"
    
    # NUROのIPv6アドレスか確認
    if ! nuro_is_ipv6_nuro "$ipv6_addr"; then
        printf "%s\n" "$(color red "エラー: このIPv6アドレスはNURO光のものではないようです")"
        exit 1
    fi
    printf "%s\n" "$(color green "NURO光の回線を確認しました")"
    
    # IPv6プレフィックスの取得
    printf "%s\n" "$(color green "IPv6プレフィックスを取得中...")"
    local ipv6_prefix
    ipv6_prefix=$(nuro_get_ipv6_prefix "$ipv6_addr")
    if [ $? -ne 0 ] || [ -z "$ipv6_prefix" ]; then
        printf "%s\n" "$(color red "エラー: IPv6プレフィックスの取得に失敗しました")"
        exit 1
    fi
    printf "%s: %s\n" "$(color cyan "IPv6プレフィックス")" "$ipv6_prefix"
    
    # OpenWrtバージョンの取得
    local major_version
    major_version=$(nuro_get_openwrt_version)
    printf "%s: %s\n" "$(color cyan "OpenWrtバージョン")" "$major_version"
    
    # MAP-E設定の適用
    nuro_apply_mape_config "$ipv6_prefix" "$major_version"
    
    return 0
}

# スクリプト実行
Internet_nuro_main "$@"
