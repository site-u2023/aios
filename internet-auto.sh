#!/bin/sh

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-04-03
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
# ✅ Use $(command) instead of backticks `` `command` ``
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

# 基本定数
CACHE_DIR="${CACHE_DIR:-/tmp/aios/cache}"
LOG_DIR="${LOG_DIR:-/tmp/aios/logs}"
ISP_FILE="${CACHE_DIR}/isp.ch"
ISP=""

# プロバイダの自動判定関数
detect_provider() {
    local ipv6_prefix="$1"
    local provider="UNKNOWN"
    
    case "$ipv6_prefix" in
        # OCNバーチャルコネクト・V6プラス・IPv6オプションを上位に配置
        2404:7a10:*)
            provider="mape_virtual_connect_east"
            ;;
        2404:7a11:*)
            provider="mape_v6plus_east"
            ;;
        2404:7a12:*)
            provider="mape_ipv6_option_east"
            ;;
        # その他のプロバイダ
        240d:000f:*)
            provider="mape_nuro"
            ;;
        2404:9200:*)
            provider="mape_jpne"
            ;;
        2400:380:*)
            provider="mape_ocn"
            ;;
        # 新しいIPレンジを追加
        2404:7a80:*)
            provider="mape_biglobe_east"
            ;;
        2404:7a84:*)
            provider="mape_biglobe_west"
            ;;
        *)
            provider="unknown_provider"
            ;;
    esac
    
    echo "$provider"
}

# DS-Liteプロバイダ判定関数
detect_dslite_provider() {
    local domain="$1"
    local provider="UNKNOWN"
    
    case "$domain" in
        gw.transix.jp)
            provider="dslite_transix"
            ;;
        dgw.xpass.jp)
            provider="dslite_xpass"
            ;;
        dslite.v6connect.net)
            provider="dslite_v6connect"
            ;;
        *)
            provider="unknown_provider"
            ;;
    esac
    
    echo "$provider"
}

# IPv6プレフィックスの取得関数
get_ipv6_prefix() {
    local net_if6=""
    local net_pfx6=""
    
    . /lib/functions/network.sh
    network_flush_cache
    network_find_wan6 net_if6
    network_get_prefix6 net_pfx6 "$net_if6"
    
    echo "$net_pfx6"
}

# DS-Lite用AAAAレコード取得関数
get_AAAA_record() {
    local domain="$1"
    nslookup -type=AAAA "$domain" | grep "Address:" | awk 'NR==2 {print $2}'
}

# DS-Lite東日本と西日本の判別関数
detect_dslite_region() {
    local east_domain="2404:8e00::feed:100"
    local west_domain="2404:8e01::feed:100"
    local provider="UNKNOWN"
    
    if ping6 -c 1 -w 2 "$east_domain" > /dev/null 2>&1; then
        provider="east"
    elif ping6 -c 1 -w 2 "$west_domain" > /dev/null 2>&1; then
        provider="west"
    fi
    
    echo "$provider"
}

# メイン処理
internet_auto_main() {
    debug_log "DEBUG" "Starting provider detection process"
    
    local ipv6_prefix=$(get_ipv6_prefix)
    local dslite_domain=""
    local dslite_provider=""
    local region=""
    
    if [ -z "$ipv6_prefix" ];then
        debug_log "ERROR" "Failed to obtain IPv6 prefix"
        echo "unknown_provider" > "$ISP_FILE"
        return 1
    fi
    
    ISP=$(detect_provider "$ipv6_prefix")
    
    if [ "$ISP" = "unknown_provider" ]; then
        dslite_domain=$(get_AAAA_record "gw.transix.jp")
        if [ -n "$dslite_domain" ];then
            dslite_provider=$(detect_dslite_provider "gw.transix.jp")
            region=$(detect_dslite_region)
            if [ "$region" = "east" ];then
                dslite_provider="dslite_transix_east"
            elif [ "$region" = "west" ];then
                dslite_provider="dslite_transix_west"
            fi
        else
            dslite_domain=$(get_AAAA_record "dgw.xpass.jp")
            if [ -n "$dslite_domain" ];then
                dslite_provider=$(detect_dslite_provider "dgw.xpass.jp")
            else
                dslite_domain=$(get_AAAA_record "dslite.v6connect.net")
                if [ -n "$dslite_domain" ];then
                    dslite_provider=$(detect_dslite_provider "dslite.v6connect.net")
                fi
            fi
        fi
        
        if [ -n "$dslite_provider" ]; then
            ISP="$dslite_provider"
        fi
    fi
    
    debug_log "INFO" "ISP detected: $ISP"
    
    # 判定結果をファイルに書き出す
    echo "$ISP" > "$ISP_FILE"
    
    return 0
}

# スクリプト実行
internet_auto_main "$@"
