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

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
DEBUG_MODE="${DEBUG_MODE:-false}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# ISP判定関数（OpenWrt用・POSIX準拠）
# 使用方法: . ./detect_isp.sh

# IPv6アドレスをOpenWrtの機能から取得
get_wan_ipv6_address() {
    debug_log "Retrieving IPv6 address from OpenWrt network functions"
    
    # OpenWrtのネットワークライブラリ読み込み
    if [ -f "/lib/functions/network.sh" ]; then
        debug_log "Loading OpenWrt network libraries"
        . /lib/functions.sh 2>/dev/null
        . /lib/functions/network.sh 2>/dev/null
        . /lib/netifd/netifd-proto.sh 2>/dev/null
        
        # キャッシュをクリア
        network_flush_cache
        
        # WAN6インターフェース検出
        local net_if6=""
        network_find_wan6 net_if6
        
        if [ -n "$net_if6" ]; then
            debug_log "Found WAN6 interface: $net_if6"
            
            # IPv6アドレスを取得
            local net_addr6=""
            network_get_ipaddr6 net_addr6 "$net_if6"
            
            if [ -n "$net_addr6" ]; then
                debug_log "Found IPv6 address: $net_addr6"
                echo "$net_addr6"
                return 0
            fi
            debug_log "No IPv6 address found on interface $net_if6"
        else
            debug_log "No WAN6 interface found"
        fi
    else
        debug_log "OpenWrt network libraries not found"
    fi
    
    # フォールバック: ip コマンド使用
    if command -v ip >/dev/null 2>&1; then
        debug_log "Trying ip command fallback for IPv6"
        local ipv6_addr
        ipv6_addr=$(ip -6 addr show scope global | grep inet6 | grep -v temporary | head -1 | awk '{print $2}' | cut -d/ -f1)
        
        if [ -n "$ipv6_addr" ]; then
            debug_log "Found global IPv6 via ip command: $ipv6_addr"
            echo "$ipv6_addr"
            return 0
        fi
    fi
    
    # 外部APIからIPv6取得を試行
    debug_log "Attempting to get IPv6 address from external API"
    local tmp_file
    tmp_file=$(mktemp -t ipv6.XXXXXX)
    
    $BASE_WGET -O "$tmp_file" "https://ipv6-test.com/api/myip.php?json" >/dev/null 2>&1
    
    if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        local ipv6_addr
        ipv6_addr=$(grep -o '"address":"[^"]*' "$tmp_file" | sed 's/"address":"//')
        rm -f "$tmp_file"
        
        if echo "$ipv6_addr" | grep -q ":"; then
            debug_log "Found IPv6 address from external API: $ipv6_addr"
            echo "$ipv6_addr"
            return 0
        fi
    else
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    debug_log "Failed to get IPv6 address from all sources"
    return 1
}

# AFTRアドレスを検出（DS-LITE用）
detect_aftr_address() {
    debug_log "Detecting AFTR address for DS-LITE"
    local aftr_address=""
    
    # システムログからの検出
    if [ -f "/var/log/messages" ]; then
        aftr_address=$(grep -i "AFTR" /var/log/messages | tail -1 | grep -o '[a-zA-Z0-9\.\-]*\.jp')
        if [ -n "$aftr_address" ]; then
            debug_log "Found AFTR address in system logs: $aftr_address"
            echo "$aftr_address"
            return 0
        fi
    fi
    
    # UCI設定からの検出（OpenWrt）
    if command -v uci >/dev/null 2>&1; then
        # 全てのWAN6設定を検索
        config_list=$(uci show network | grep aftr_v4_addr 2>/dev/null)
        if [ -n "$config_list" ]; then
            aftr_address=$(echo "$config_list" | head -1 | cut -d= -f2 | tr -d "'" 2>/dev/null)
            if [ -n "$aftr_address" ]; then
                debug_log "Found AFTR address in UCI config: $aftr_address"
                echo "$aftr_address"
                return 0
            fi
        fi
    fi
    
    debug_log "No AFTR address found"
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
            # ISP名/組織名による判定
            if echo "$isp $org" | grep -i "OCN\|Open Computer Network\|NTT Communications" >/dev/null 2>&1; then
                provider="mape_ocn"
                debug_log "Detected OCN from organization name"
            elif echo "$isp $org" | grep -i "SoftBank\|Yahoo\|BBIX\|ソフトバンク" >/dev/null 2>&1; then
                provider="mape_v6plus"
                debug_log "Detected SoftBank from organization name"
            elif echo "$isp $org" | grep -i "KDDI\|au\|ケーディーディーアイ" >/dev/null 2>&1; then
                provider="mape_ipv6option"
                debug_log "Detected KDDI from organization name"
            elif echo "$isp $org" | grep -i "NURO\|Sony\|So-net\|ソニー\|ソネット" >/dev/null 2>&1; then
                provider="mape_nuro"
                debug_log "Detected NURO/So-net from organization name"
            elif echo "$isp $org" | grep -i "BIGLOBE\|ビッグローブ" >/dev/null 2>&1; then
                provider="mape_biglobe"
                debug_log "Detected BIGLOBE from organization name"
            elif echo "$isp $org" | grep -i "nifty\|ニフティ\|@nifty" >/dev/null 2>&1; then
                provider="mape_nifty"
                debug_log "Detected @nifty from organization name"
            elif echo "$isp $org" | grep -i "Chubu Telecommunications\|CTC\|中部テレコミュニケーション" >/dev/null 2>&1; then
                provider="pppoe_ctc"
                debug_log "Detected CTC from organization name"
            elif echo "$isp $org" | grep -i "NTT East\|NTT東日本" >/dev/null 2>&1; then
                provider="dslite_east"
                debug_log "Detected NTT East from organization name"
            elif echo "$isp $org" | grep -i "NTT West\|NTT西日本" >/dev/null 2>&1; then
                provider="dslite_west"
                debug_log "Detected NTT West from organization name"
            elif echo "$isp $org" | grep -i "NTT\|FLETS\|フレッツ" >/dev/null 2>&1; then
                # 地域情報から東西判別
                if [ -n "$region" ] && [ -n "$city" ]; then
                    debug_log "Trying to determine NTT region from location data: $region, $city"
                    
                    # 東日本エリア
                    if echo "$region $city" | grep -i "Tokyo\|Kanagawa\|Saitama\|Chiba\|Ibaraki\|Tochigi\|Gunma\|Yamanashi\|Nagano\|Niigata\|Hokkaido\|Aomori\|Iwate\|Miyagi\|Akita\|Yamagata\|Fukushima" >/dev/null 2>&1; then
                        provider="dslite_east"
                        debug_log "Estimated NTT East from geographic location"
                    # 西日本エリア
                    elif echo "$region $city" | grep -i "Osaka\|Kyoto\|Hyogo\|Nara\|Shiga\|Wakayama\|Mie\|Aichi\|Gifu\|Shizuoka\|Toyama\|Ishikawa\|Fukui\|Tottori\|Shimane\|Okayama\|Hiroshima\|Yamaguchi\|Tokushima\|Kagawa\|Ehime\|Kochi\|Fukuoka\|Saga\|Nagasaki\|Kumamoto\|Oita\|Miyazaki\|Kagoshima\|Okinawa" >/dev/null 2>&1; then
                        provider="dslite_west"
                        debug_log "Estimated NTT West from geographic location"
                    else
                        provider="dslite"
                        debug_log "Generic NTT/FLETS service detected, but region unknown"
                    fi
                else
                    provider="dslite"
                    debug_log "Generic NTT/FLETS service detected"
                fi
            fi
            ;;
    esac
    
    echo "$provider"
    return 0
}

# ISP情報を取得してISPタイプを判定
detect_isp_type() {
    local cache_file="${CACHE_DIR}/isp.ch"
    local cache_timeout=86400  # キャッシュ有効期間（24時間）
    local provider="unknown"
    local show_result=1
    local use_cache=1
    local force_update=0
    
    # パラメータ処理
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-cache)
                use_cache=0
                debug_log "Cache disabled"
                ;;
            --force-update)
                force_update=1
                debug_log "Forcing update of ISP information"
                ;;
            --silent)
                show_result=0
                debug_log "Silent mode enabled"
                ;;
        esac
        shift
    done
    
    # キャッシュディレクトリ確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"
    
    # キャッシュチェック
    if [ $use_cache -eq 1 ] && [ $force_update -eq 0 ] && [ -f "$cache_file" ]; then
        local cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || date +%s)
        local current_time=$(date +%s)
        local cache_age=$(($current_time - $cache_time))
        
        if [ $cache_age -lt $cache_timeout ]; then
            debug_log "Using cached ISP information ($cache_age seconds old)"
            provider=$(grep CONNECTION_TYPE "$cache_file" | cut -d= -f2 | tr -d '"')
            
            if [ -n "$provider" ] && [ "$provider" != "unknown" ]; then
                if [ $show_result -eq 1 ]; then
                    display_isp_info "$provider" "cached"
                fi
                return 0
            fi
            debug_log "Invalid or incomplete cache data"
        else
            debug_log "Cache expired ($cache_age seconds old)"
        fi
    fi
    
    # スピナー表示開始
    if [ $show_result -eq 1 ]; then
        start_spinner "$(color "blue" "$(get_message "MSG_DETECTING_ISP_TYPE")")" "yellow"
    fi
    
    # IPv6アドレス取得
    local ipv6_addr
    ipv6_addr=$(get_wan_ipv6_address)
    local has_ipv6=0
    
    if [ -n "$ipv6_addr" ]; then
        has_ipv6=1
        debug_log "IPv6 address detected: $ipv6_addr"
        provider=$(detect_ipv6_provider "$ipv6_addr")
        debug_log "Provider detection from IPv6 result: $provider"
    else
        debug_log "No IPv6 address detected"
    fi
    
    # IPv6で判定できなかった場合はAPIから情報取得
    if [ "$provider" = "unknown" ] || [ -z "$provider" ]; then
        debug_log "IPv6 detection failed, trying ISP API"
        
        # API情報取得
        local tmp_file
        tmp_file=$(mktemp -t isp.XXXXXX)
        
        $BASE_WGET -O "$tmp_file" "http://ip-api.com/json?fields=isp,as,org,country,countryCode,regionName,city" >/dev/null 2>&1
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # JSONデータを抽出
            local isp=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
            local as_num=$(grep -o '"as":"[^"]*' "$tmp_file" | sed 's/"as":"//')
            local org=$(grep -o '"org":"[^"]*' "$tmp_file" | sed 's/"org":"//')
            local country=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
            local region=$(grep -o '"regionName":"[^"]*' "$tmp_file" | sed 's/"regionName":"//')
            local city=$(grep -o '"city":"[^"]*' "$tmp_file" | sed 's/"city":"//')
            
            debug_log "Retrieved ISP info - Name: $isp, AS: $as_num, Org: $org, Country: $country"
            
            # 日本の場合のみ詳細判定を行う
            if [ "$country" = "JP" ]; then
                provider=$(detect_as_provider "$as_num" "$isp" "$org" "$region" "$city")
                debug_log "Provider detection from AS number: $provider"
            else
                provider="overseas"
                debug_log "Non-Japanese ISP detected: $country"
            fi
            
            # キャッシュファイル作成
            echo "# ISP情報 $(date)" > "$cache_file"
            echo "ISP_NAME=\"$isp\"" >> "$cache_file"
            echo "ISP_AS=\"$as_num\"" >> "$cache_file"
            echo "ISP_ORG=\"$org\"" >> "$cache_file"
            echo "ISP_COUNTRY=\"$country\"" >> "$cache_file"
            echo "CONNECTION_TYPE=\"$provider\"" >> "$cache_file"
            echo "HAS_IPV6=\"$has_ipv6\"" >> "$cache_file"
            [ -n "$ipv6_addr" ] && echo "IPV6_ADDRESS=\"$ipv6_addr\"" >> "$cache_file"
        else
            debug_log "Failed to retrieve ISP information from API"
            rm -f "$tmp_file" 2>/dev/null
        fi
        
        rm -f "$tmp_file" 2>/dev/null
    else
        # IPv6で判定できた場合はより詳細な情報をAPIから取得してキャッシュに保存
        debug_log "IPv6 detection successful, getting additional ISP info"
        
        local tmp_file
        tmp_file=$(mktemp -t isp.XXXXXX)
        
        $BASE_WGET -O "$tmp_file" "http://ip-api.com/json?fields=isp,as,org,country,countryCode" >/dev/null 2>&1
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            local isp=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
            local as_num=$(grep -o '"as":"[^"]*' "$tmp_file" | sed 's/"as":"//')
            local org=$(grep -o '"org":"[^"]*' "$tmp_file" | sed 's/"org":"//')
            local country=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
            
            debug_log "Retrieved additional ISP info - Name: $isp, AS: $as_num, Org: $org"
            
            # キャッシュファイル作成
            echo "# ISP情報 $(date)" > "$cache_file"
            echo "ISP_NAME=\"$isp\"" >> "$cache_file"
            echo "ISP_AS=\"$as_num\"" >> "$cache_file"
            echo "ISP_ORG=\"$org\"" >> "$cache_file"
            echo "ISP_COUNTRY=\"$country\"" >> "$cache_file"
            echo "CONNECTION_TYPE=\"$provider\"" >> "$cache_file"
            echo "HAS_IPV6=\"$has_ipv6\"" >> "$cache_file"
            echo "IPV6_ADDRESS=\"$ipv6_addr\"" >> "$cache_file"
        else
            debug_log "Failed to retrieve additional ISP information"
            rm -f "$tmp_file" 2>/dev/null
            
            # 最低限の情報でキャッシュ保存
            echo "# ISP情報 $(date)" > "$cache_file"
            echo "CONNECTION_TYPE=\"$provider\"" >> "$cache_file"
            echo "HAS_IPV6=\"$has_ipv6\"" >> "$cache_file"
            echo "IPV6_ADDRESS=\"$ipv6_addr\"" >> "$cache_file"
        fi
        
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    # 結果表示
    if [ $show_result -eq 1 ]; then
        stop_spinner "$(get_message "MSG_ISP_INFO_SUCCESS")" "success"
        display_isp_info "$provider" "detected"
    fi
    
    debug_log "ISP detection completed with result: $provider"
    return 0
}

# ISP情報の表示
display_isp_info() {
    local provider="$1"
    local source="$2"
    
    printf "%s\n" "$(color blue "========= ISP接続判定結果 =========")"
    
    if [ "$source" = "cached" ]; then
        printf "%s\n" "$(get_message "MSG_ISP_INFO_SOURCE" "source=キャッシュ")"
    else
        printf "%s\n" "$(get_message "MSG_ISP_INFO_SOURCE" "source=検出")"
    fi
    
    printf "%s %s\n\n" "$(get_message "MSG_ISP_TYPE")" "$(color cyan "$provider")"
    
    case "$provider" in
        mape_ocn)
            printf "%s\n" "$(color white "【 OCN IPv6 (MAP-E)接続 】")"
            printf "%s\n" "$(color white "NTT Communicationsが提供するOCN IPv6サービスです。")"
            printf "%s\n" "$(color white "IPv4 over IPv6のMAP-E方式を採用しています。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_v6plus)
            printf "%s\n" "$(color white "【 SoftBank V6プラス接続 】")"
            printf "%s\n" "$(color white "SoftBankが提供するIPv6接続サービスです。")"
            printf "%s\n" "$(color white "MAP-E方式でIPv4 over IPv6通信を行います。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_ipv6option)
            printf "%s\n" "$(color white "【 KDDI IPv6オプション接続 】")"
            printf "%s\n" "$(color white "KDDIが提供するMAP-E方式のIPv6接続サービスです。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_nuro)
            printf "%s\n" "$(color white "【 NURO光 MAP-E接続 】")"
            printf "%s\n" "$(color white "So-netが提供するNURO光のMAP-E接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_biglobe)
            printf "%s\n" "$(color white "【 BIGLOBE IPv6接続 】")"
            printf "%s\n" "$(color white "BIGLOBEが提供するMAP-E方式のIPv6接続サービスです。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_jpne)
            printf "%s\n" "$(color white "【 JPNE IPv6接続 】")"
            printf "%s\n" "$(color white "日本ネットワークイネイブラーが提供するMAP-E接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_sonet)
            printf "%s\n" "$(color white "【 So-net IPv6接続 】")"
            printf "%s\n" "$(color white "So-netが提供するMAP-E方式のIPv6接続サービスです。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_nifty)
            printf "%s\n" "$(color white "【 @nifty IPv6接続 】")"
            printf "%s\n" "$(color white "@niftyが提供するMAP-E方式のIPv6接続サービスです。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        dslite_east_transix)
            printf "%s\n" "$(color white "【 NTT東日本 DS-Lite接続 (transix) 】")"
            printf "%s\n" "$(color white "NTT東日本が提供するIPv6 IPoE + DS-Lite接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・ホスト名: mgw.transix.jp")"
            printf "%s\n" "$(color yellow "・IPv6アドレス: 2404:8e01::feed:100")"
            printf "%s\n" "$(color yellow "MTU値は1500のままで構いません。")"
            ;;
        dslite_west_transix)
            printf "%s\n" "$(color white "【 NTT西日本 DS-Lite接続 (transix) 】")"
            printf "%s\n" "$(color white "NTT西日本が提供するIPv6 IPoE + DS-Lite接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・ホスト名: mgw.transix.jp")"
            printf "%s\n" "$(color yellow "・IPv6アドレス: 2404:8e00::feed:100")"
            printf "%s\n" "$(color yellow "MTU値は1500のままで構いません。")"
            ;;
        dslite_transix)
            printf "%s\n" "$(color white "【 DS-Lite接続 (transix) 】")"
            printf "%s\n" "$(color white "IPv6 IPoE + DS-Lite接続（トランジックス）です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・東日本の場合: mgw.transix.jp (2404:8e01::feed:100)")"
            printf "%s\n" "$(color yellow "・西日本の場合: mgw.transix.jp (2404:8e00::feed:100)")"
            printf "%s\n" "$(color yellow "お住まいの地域により設定が異なります。")"
            ;;
        dslite_xpass)
            printf "%s\n" "$(color white "【 DS-Lite接続 (xpass) 】")"
            printf "%s\n" "$(color white "IPv6 IPoE + DS-Lite接続（クロスパス）です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・ホスト名: dgw.xpass.jp")"
            printf "%s\n" "$(color yellow "MTU値は1500のままで構いません。")"
            ;;
        dslite_v6connect)
            printf "%s\n" "$(color white "【 DS-Lite接続 (v6connect) 】")"
            printf "%s\n" "$(color white "IPv6 IPoE + DS-Lite接続（V6コネクト）です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・ホスト名: aft.v6connect.net")"
            printf "%s\n" "$(color yellow "MTU値は1500のままで構いません。")"
            ;;
        dslite_east)
            printf "%s\n" "$(color white "【 NTT東日本 DS-Lite接続 】")"
            printf "%s\n" "$(color white "NTT東日本が提供するIPv6 IPoE + DS-Lite接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: 主要なAFTRは次のいずれかです。")"
            printf "%s\n" "$(color yellow "・トランジックス: mgw.transix.jp (2404:8e01::feed:100)")"
            printf "%s\n" "$(color yellow "・クロスパス: dgw.xpass.jp")"
            printf "%s\n" "$(color yellow "・V6コネクト: aft.v6connect.net")"
            printf "%s\n" "$(color yellow "ご利用のプロバイダにより対応するAFTRが異なります。")"
            ;;
        dslite_west)
            printf "%s\n" "$(color white "【 NTT西日本 DS-Lite接続 】")"
            printf "%s\n" "$(color white "NTT西日本が提供するIPv6 IPoE + DS-Lite接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: 主要なAFTRは次のいずれかです。")"
            printf "%s\n" "$(color yellow "・トランジックス: mgw.transix.jp (2404:8e00::feed:100)")"
            printf "%s\n" "$(color yellow "・クロスパス: dgw.xpass.jp")"
            printf "%s\n" "$(color yellow "・V6コネクト: aft.v6connect.net")"
            printf "%s\n" "$(color yellow "ご利用のプロバイダにより対応するAFTRが異なります。")"
            ;;
        dslite*)
            printf "%s\n" "$(color white "【 DS-LITE接続 】")"
            printf "%s\n" "$(color white "DS-LITE方式を使用したIPv4 over IPv6接続です。")"
            printf "%s\n" "$(color white "東西の判定ができませんでした。")"
            printf "%s\n" "$(color yellow "設定ポイント: 主要なAFTRは次のいずれかです。")"
            printf "%s\n" "$(color yellow "・トランジックス: mgw.transix.jp")"
            printf "%s\n" "$(color yellow "  東日本: 2404:8e01::feed:100")"
            printf "%s\n" "$(color yellow "  西日本: 2404:8e00::feed:100")"
            printf "%s\n" "$(color yellow "・クロスパス: dgw.xpass.jp")"
            printf "%s\n" "$(color yellow "・V6コネクト: aft.v6connect.net")"
            ;;
        pppoe_ctc)
            printf "%s\n" "$(color white "【 中部テレコム PPPoE接続 】")"
            printf "%s\n" "$(color white "中部テレコミュニケーション株式会社が提供するPPPoE接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: 標準的なPPPoE設定で問題ありません。")"
            ;;
        pppoe_iij)
            printf "%s\n" "$(color white "【 IIJ PPPoE接続 】")"
            printf "%s\n" "$(color white "IIJが提供するPPPoE接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: 標準的なPPPoE設定で問題ありません。")"
            ;;
        overseas)
            printf "%s\n" "$(color white "【 海外ISP接続 】")"
            printf "%s\n" "$(color white "日本国外のISPが検出されました。")"
            printf "%s\n" "$(color white "日本のISP判定には対応していません。")"
            ;;
        *)
            printf "%s\n" "$(color white "【 不明な接続タイプ 】")"
            printf "%s\n" "$(color white "接続タイプを特定できませんでした。")"
            printf "%s\n" "$(color white "IPv6プレフィックスやAS情報から判断できません。")"
            printf "%s\n" "$(color yellow "ご契約のインターネットプロバイダに確認してください。")"
            ;;
    esac
    
    printf "\n%s\n" "$(color blue "====================================")"
    
    # キャッシュファイルの場所を表示
    printf "%s %s\n\n" "$(get_message "MSG_ISP_CACHE_PATH")" "$(color "green" "${CACHE_DIR}/isp.ch")"
}

detect_isp_type "$@"
