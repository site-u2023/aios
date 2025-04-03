#!/bin/sh

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-04-03
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 24.10.0)
# =========================================================

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="wget --no-check-certificate -q"
DEBUG_MODE="${DEBUG_MODE:-false}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# WAN/WAN6のインターフェース名とIPアドレスを取得
get_wan_info() {
    # 変数初期化
    local net_if=""
    local net_if6=""
    local ipv4_addr=""
    local ipv6_addr=""
    
    # デバッグログ出力
    debug_log "Getting WAN interfaces and addresses from OpenWrt"
    
    # OpenWrtのネットワークライブラリ確認
    if [ ! -f "/lib/functions/network.sh" ]; then
        debug_log "OpenWrt network libraries not found"
        return 1
    fi
    
    # ネットワークライブラリ読み込み
    debug_log "Loading OpenWrt network libraries"
    . /lib/functions/network.sh 2>/dev/null
    
    # ネットワークキャッシュクリア
    network_flush_cache
    
    # WANインターフェース取得
    network_find_wan net_if
    network_find_wan6 net_if6
    
    # IPv4アドレス取得
    if [ -n "$net_if" ]; then
        debug_log "Found WAN interface: $net_if"
        network_get_ipaddr ipv4_addr "$net_if"
        if [ -n "$ipv4_addr" ]; then
            debug_log "Found IPv4 address: $ipv4_addr"
        else
            debug_log "No IPv4 address found on interface $net_if"
        fi
    else
        debug_log "No WAN interface found"
    fi
    
    # IPv6アドレス取得
    if [ -n "$net_if6" ]; then
        debug_log "Found WAN6 interface: $net_if6"
        network_get_ipaddr6 ipv6_addr "$net_if6"
        if [ -n "$ipv6_addr" ]; then
            debug_log "Found IPv6 address: $ipv6_addr"
        else
            debug_log "No IPv6 address found on interface $net_if6"
        fi
    else
        debug_log "No WAN6 interface found"
    fi
    
    # 結果を返す
    echo "WAN_IF=\"$net_if\""
    echo "WAN_IF6=\"$net_if6\""
    echo "IPV4_ADDR=\"$ipv4_addr\""
    echo "IPV6_ADDR=\"$ipv6_addr\""
    
    return 0
}

# DS-LITE用のAFTRアドレスを検出
detect_aftr_address() {
    debug_log "Detecting AFTR address for DS-LITE"
    
    # dig/nslookupコマンドでAFTRの候補を調べる
    local aftr_candidates="mgw.transix.jp dgw.xpass.jp aft.v6connect.net"
    local aftr_result=""
    
    # digコマンドが使える場合
    if command -v dig >/dev/null 2>&1; then
        debug_log "Using dig command to resolve AFTR"
        for candidate in $aftr_candidates; do
            debug_log "Checking AFTR candidate: $candidate"
            if dig AAAA "$candidate" +short 2>/dev/null | grep -q ":" ; then
                aftr_result="$candidate"
                debug_log "AFTR found: $aftr_result"
                echo "$aftr_result"
                return 0
            fi
        done
    # nslookupコマンドが使える場合
    elif command -v nslookup >/dev/null 2>&1; then
        debug_log "Using nslookup command to resolve AFTR"
        for candidate in $aftr_candidates; do
            debug_log "Checking AFTR candidate: $candidate"
            if nslookup -type=AAAA "$candidate" 2>/dev/null | grep -q "has AAAA address" ; then
                aftr_result="$candidate"
                debug_log "AFTR found: $aftr_result"
                echo "$aftr_result"
                return 0
            fi
        done
    fi
    
    debug_log "No AFTR address detected"
    return 1
}

# IPv6プレフィックスからISPを判定
detect_ipv6_provider() {
    local ipv6="$1"
    local provider="unknown"
    
    if [ -z "$ipv6" ]; then
        debug_log "No IPv6 address provided for provider detection"
        return 1
    fi
    
    # プレフィックスを抽出
    local prefix
    prefix=$(echo "$ipv6" | cut -d: -f1-2)
    debug_log "Extracted IPv6 prefix: $prefix"
    
    # 詳細なプレフィックス
    local long_prefix
    long_prefix=$(echo "$ipv6" | cut -d: -f1-3)
    debug_log "Extracted long IPv6 prefix: $long_prefix"
    
    # プレフィックスからプロバイダを判定
    case "$prefix" in
        # SoftBank（V6プラス）
        2404:7a)
            provider="mape_v6plus"
            debug_log "Detected SoftBank V6plus from IPv6 prefix"
            ;;
        # KDDI（IPv6オプション）
        2001:f9)
            provider="mape_ipv6option"
            debug_log "Detected KDDI IPv6option from IPv6 prefix"
            ;;
        # OCN
        2001:0c|2400:38)
            provider="mape_ocn"
            debug_log "Detected OCN MAP-E from IPv6 prefix"
            ;;
        # ビッグローブ BIGLOBE
        2001:26|2001:f6)
            provider="mape_biglobe"
            debug_log "Detected BIGLOBE from IPv6 prefix"
            ;;
        # NURO光
        240d:00)
            provider="mape_nuro"
            debug_log "Detected NURO from IPv6 prefix"
            ;;
        # JPNE NGN
        2404:92)
            provider="mape_jpne"
            debug_log "Detected JPNE from IPv6 prefix"
            ;;
        # So-net
        240b:10|240b:11|240b:12|240b:13)
            provider="mape_sonet"
            debug_log "Detected So-net from IPv6 prefix"
            ;;
        # NTT東日本/西日本（DS-Lite）- トランジックス系
        2404:8e)
            if echo "$long_prefix" | grep -q "2404:8e01"; then
                provider="dslite_east_transix"
                debug_log "Detected NTT East DS-Lite with transix"
            elif echo "$long_prefix" | grep -q "2404:8e00"; then
                provider="dslite_west_transix"
                debug_log "Detected NTT West DS-Lite with transix"
            else
                provider="dslite_transix"
                debug_log "Detected DS-Lite with transix (unknown region)"
            fi
            ;;
        # クロスパス系
        2404:92)
            provider="dslite_xpass"
            debug_log "Detected DS-Lite with xpass"
            ;;
        # v6コネクト系
        2404:01)
            provider="dslite_v6connect"
            debug_log "Detected DS-Lite with v6connect"
            ;;
        # @nifty
        2001:f7)
            provider="mape_nifty"
            debug_log "Detected @nifty from IPv6 prefix"
            ;;
        *)
            provider="unknown"
            debug_log "Unknown provider for prefix: $prefix"
            ;;
    esac
    
    # DS-LITEの場合はAFTRアドレスも検出
    if echo "$provider" | grep -q "dslite" && echo "$provider" | grep -qv "dslite_east\|dslite_west"; then
        local aftr_address
        aftr_address=$(detect_aftr_address)
        
        if [ -n "$aftr_address" ]; then
            debug_log "AFTR address detected: $aftr_address"
            
            if echo "$aftr_address" | grep -i "transix" >/dev/null 2>&1; then
                provider="dslite_transix"
                debug_log "Identified as transix DS-LITE from AFTR"
            elif echo "$aftr_address" | grep -i "xpass" >/dev/null 2>&1; then
                provider="dslite_xpass"
                debug_log "Identified as xpass DS-LITE from AFTR"
            elif echo "$aftr_address" | grep -i "v6connect" >/dev/null 2>&1; then
                provider="dslite_v6connect"
                debug_log "Identified as v6connect DS-LITE from AFTR"
            fi
        fi
    fi
    
    echo "$provider"
    return 0
}

# AS番号からISPを判定（IPv6で判別できない場合）
detect_as_provider() {
    local as_num="$1"
    local isp="$2"
    local org="$3"
    local region="$4"
    local city="$5"
    local provider="unknown"
    
    debug_log "Detecting provider from AS number and organization info"
    
    # AS番号による判定
    case "$as_num" in
        *AS4713*)
            # OCN (NTT Communications)
            provider="mape_ocn"
            debug_log "Detected OCN from AS number (AS4713)"
            ;;
        *AS17676*)
            # SoftBank
            provider="mape_v6plus"
            debug_log "Detected SoftBank from AS number (AS17676)"
            ;;
        *AS2516*)
            # KDDI
            provider="mape_ipv6option"
            debug_log "Detected KDDI from AS number (AS2516)"
            ;;
        *AS7521*)
            # NURO/So-net
            provider="mape_nuro"
            debug_log "Detected NURO/So-net from AS number (AS7521)"
            ;;
        *AS18126*)
            # Chubu Telecommunications
            provider="pppoe_ctc"
            debug_log "Detected CTC from AS number (AS18126)"
            ;;
        *AS2527*)
            # NTT East
            provider="dslite_east"
            debug_log "Detected NTT East from AS number (AS2527)"
            ;;
        *AS2914*)
            # NTT West
            provider="dslite_west"
            debug_log "Detected NTT West from AS number (AS2914)"
            ;;
        *AS17506*)
            # NIFTY
            provider="mape_nifty"
            debug_log "Detected @nifty from AS number (AS17506)"
            ;;
        *AS9824*|*AS9607*)
            # BIGLOBE
            provider="mape_biglobe"
            debug_log "Detected BIGLOBE from AS number (AS9824/AS9607)"
            ;;
        *AS9595*|*AS9591*)
            # So-net
            provider="mape_sonet"
            debug_log "Detected So-net from AS number (AS9595/AS9591)"
            ;;
        *)
            provider="unknown"
            ;;
    esac
    
    echo "$provider"
    return 0
}

# IPv6アドレスからISPを判定し、結果をisp.chに書き込む
detect_isp_type() {
    local ipv6_addr=""
    local ipv4_addr=""
    local wan_if=""
    local wan_if6=""
    local provider="unknown"
    local isp_file="${CACHE_DIR}/isp.ch"
    local aftr_address=""
    local is_dslite=0
    
    # スピナー表示開始
    if type start_spinner >/dev/null 2>&1; then
        if type get_message >/dev/null 2>&1; then
            start_spinner "$(get_message "MSG_PROVIDER_ISP_TYPE")" "yellow"
        else
            start_spinner "ISPの判別中..." "yellow"
        fi
    else
        if type get_message >/dev/null 2>&1; then
            echo "$(get_message "MSG_PROVIDER_ISP_TYPE")" >&2
        else
            echo "ISPの判別中..." >&2
        fi
    fi
    
    # WAN情報取得（インターフェースとIPアドレス）
    debug_log "Starting ISP detection process"
    
    # get_wan_info関数の結果を取得して変数に設定
    eval "$(get_wan_info)"
    ipv4_addr="$IPV4_ADDR"
    ipv6_addr="$IPV6_ADDR"
    wan_if="$WAN_IF"
    wan_if6="$WAN_IF6"
    
    # IPv6アドレスからプロバイダ判定
    if [ -n "$ipv6_addr" ]; then
        debug_log "IPv6 address detected: $ipv6_addr"
        
        # プレフィックスからプロバイダ判定
        provider=$(detect_ipv6_provider "$ipv6_addr")
        debug_log "Provider detection result from IPv6: $provider"
        
        # DS-LITEの場合はさらに詳細判定
        if echo "$provider" | grep -q "dslite"; then
            debug_log "DS-LITE detected, checking for AFTR"
            aftr_address=$(detect_aftr_address)
            
            if [ -n "$aftr_address" ]; then
                debug_log "AFTR address detected: $aftr_address"
                # AFTRからプロバイダの詳細判定
                if echo "$aftr_address" | grep -i "transix" >/dev/null 2>&1; then
                    provider="dslite_transix"
                    debug_log "Identified as transix DS-LITE"
                elif echo "$aftr_address" | grep -i "xpass" >/dev/null 2>&1; then
                    provider="dslite_xpass"
                    debug_log "Identified as xpass DS-LITE"
                elif echo "$aftr_address" | grep -i "v6connect" >/dev/null 2>&1; then
                    provider="dslite_v6connect"
                    debug_log "Identified as v6connect DS-LITE"
                fi
            fi
        fi
    else
        debug_log "No IPv6 address detected"
    fi
    
    # IPv4アドレスを使った補助判定（IPv6で判別できない場合）
    if [ "$provider" = "unknown" ] && [ -n "$ipv4_addr" ]; then
        debug_log "Using IPv4 address for supplementary detection"
        
        # プライベートIPv4アドレスでDS-LITE判定
        if echo "$ipv4_addr" | grep -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)'; then
            debug_log "Private IPv4 detected, likely DS-LITE"
            provider="dslite"
            is_dslite=1
        fi
    fi
    
    # 結果をファイルに書き込み
    mkdir -p "${CACHE_DIR}"
    echo "# ISP情報 $(date)" > "$isp_file"
    echo "CONNECTION_TYPE=\"$provider\"" >> "$isp_file"
    [ -n "$wan_if" ] && echo "WAN_INTERFACE=\"$wan_if\"" >> "$isp_file"
    [ -n "$wan_if6" ] && echo "WAN6_INTERFACE=\"$wan_if6\"" >> "$isp_file"
    [ -n "$ipv4_addr" ] && echo "IPV4_ADDRESS=\"$ipv4_addr\"" >> "$isp_file"
    [ -n "$ipv6_addr" ] && echo "IPV6_ADDRESS=\"$ipv6_addr\"" >> "$isp_file"
    [ -n "$aftr_address" ] && echo "AFTR_ADDRESS=\"$aftr_address\"" >> "$isp_file"
    [ "$is_dslite" = "1" ] && echo "IS_DSLITE=\"$is_dslite\"" >> "$isp_file"
    
    debug_log "ISP detection result saved to $isp_file"
    
    # スピナー停止と結果表示
    if type stop_spinner >/dev/null 2>&1; then
        if [ "$provider" != "unknown" ]; then
            if type get_message >/dev/null 2>&1; then
                stop_spinner "$(get_message "MSG_PROVIDER_INFO_SUCCESS")" "success"
            else
                stop_spinner "ISPを正常に判別しました" "success"
            fi
        else
            if type get_message >/dev/null 2>&1; then
                stop_spinner "$(get_message "MSG_PROVIDER_INFO_FAILED")" "warning"
            else
                stop_spinner "ISPの判別に失敗しました" "warning"
            fi
        fi
    fi
    
    # 結果表示
    display_isp_info "$provider"
    
    return 0
}

# ISP情報表示（シンプル版）- メッセージキーを使用するように修正
display_isp_info() {
    local provider="$1"
    local display_name=""

    echo "========= ISP判定結果 ========="
    
    # メッセージキーを使用（実装があれば）
    if type get_message >/dev/null 2>&1; then
        echo "$(get_message "MSG_ISP_INFO_SOURCE" "source=IPv6プレフィックス検出")"
    else
        echo "情報ソース: IPv6プレフィックス検出"
    fi
    
    # プロバイダ名の日本語表示
    case "$provider" in
        mape_ocn)           display_name="MAP-E OCN" ;;
        mape_v6plus)        display_name="SoftBank V6プラス" ;;
        mape_ipv6option)    display_name="KDDI IPv6オプション" ;;
        mape_nuro)          display_name="NURO光 MAP-E" ;;
        mape_biglobe)       display_name="BIGLOBE IPv6" ;;
        mape_jpne)          display_name="JPNE IPv6" ;;
        mape_sonet)         display_name="So-net IPv6" ;;
        mape_nifty)         display_name="@nifty IPv6" ;;
        dslite_east_transix) display_name="NTT東日本 DS-Lite (transix)" ;;
        dslite_west_transix) display_name="NTT西日本 DS-Lite (transix)" ;;
        dslite_transix)     display_name="DS-Lite (transix)" ;;
        dslite_xpass)       display_name="DS-Lite (xpass)" ;;
        dslite_v6connect)   display_name="DS-Lite (v6connect)" ;;
        dslite_east)        display_name="NTT東日本 DS-Lite" ;;
        dslite_west)        display_name="NTT西日本 DS-Lite" ;;
        dslite*)            display_name="DS-LITE" ;;
        pppoe_ctc)          display_name="中部テレコム PPPoE" ;;
        pppoe_iij)          display_name="IIJ PPPoE" ;;
        overseas)           display_name="海外ISP" ;;
        *)                  display_name="不明" ;;
    esac
    
    # メッセージキーを使用（実装があれば）
    if type get_message >/dev/null 2>&1; then
        echo "$(get_message "MSG_ISP_TYPE" "type=$display_name")"
    else
        echo "接続タイプ: $display_name"
    fi
    
    echo "==============================="
}

# メイン処理実行
if [ "${0##*/}" = "detect_isp.sh" ]; then
    detect_isp_type "$@"
fi
