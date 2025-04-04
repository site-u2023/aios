#!/bin/sh

SCRIPT_VERSION="2025.04.04-00-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX準拠シェルスクリプト
# 🚀 最終更新日: 2025-03-14
#
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 互換性: OpenWrt >= 19.07 (24.10.0でテスト済み)
#
# ⚠️ 重要な注意事項:
# OpenWrtは**Almquistシェル(ash)**のみを使用し、
# **Bourne-Again Shell(bash)**とは互換性がありません。
#
# 📢 POSIX準拠ガイドライン:
# ✅ 条件には `[[` ではなく `[` を使用する
# ✅ バックティック ``command`` ではなく `$(command)` を使用する
# ✅ `let` の代わりに `$(( ))` を使用して算術演算を行う
# ✅ 関数は `function` キーワードなしで `func_name() {}` と定義する
# ✅ 連想配列は使用しない (`declare -A` はサポートされていない)
# ✅ ヒアストリングは使用しない (`<<<` はサポートされていない)
# ✅ `test` や `[[` で `-v` フラグを使用しない
# ✅ `${var:0:3}` のようなbash特有の文字列操作を避ける
# ✅ 配列はできるだけ避ける（インデックス配列でも問題が発生する可能性がある）
# ✅ `read -p` の代わりに `printf` の後に `read` を使用する
# ✅ フォーマットには `echo -e` ではなく `printf` を使用する
# ✅ プロセス置換 `<()` や `>()` を避ける
# ✅ 複雑なif/elifチェーンよりもcaseステートメントを優先する
# ✅ コマンドの存在確認には `which` や `type` ではなく `command -v` を使用する
# ✅ スクリプトをモジュール化し、小さな焦点を絞った関数を保持する
# ✅ 複雑なtrapの代わりに単純なエラー処理を使用する
# ✅ スクリプトはbashだけでなく、明示的にash/dashでテストする
#
# 🛠️ OpenWrt向けにシンプル、POSIX準拠、軽量に保つ！
### =========================================================

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

get_address() {
    # 変数初期化
    local ipv4_addr=""
    local ipv6_addr=""
    local ip_service=""
    local cloudflare="one.one.one.one/cdn-cgi/trace"
    local ifconfig="ifconfig.me/ip"
    local icanhazip="icanhazip.com"
    local timeout=5
    local ip_cache="$CACHE_DIR/ip_address.ch"
    
    # IPv4取得処理
    for iptype in "-4"; do
        debug_log "DEBUG" "Attempting to retrieve IPv4 address"
        
        for ip_service in "$cloudflare" "$ifconfig" "$icanhazip"; do
            if [ -z "$ipv4_addr" ]; then
                debug_log "DEBUG" "Trying service: $ip_service"
                
                if [ "$ip_service" = "$cloudflare" ]; then
                    ipv4_addr=$($BASE_WGET -$iptype -T "$timeout" -O- "https://$ip_service" 2>/dev/null | grep "ip=" | cut -d= -f2)
                else
                    ipv4_addr=$($BASE_WGET -$iptype -T "$timeout" -O- "https://$ip_service" 2>/dev/null)
                fi
                
                if [ -n "$ipv4_addr" ]; then
                    debug_log "DEBUG" "Successfully retrieved IPv4: $ipv4_addr"
                    break
                fi
            fi
        done
    done
    
    # IPv6取得処理
    for iptype in "-6"; do
        debug_log "DEBUG" "Attempting to retrieve IPv6 address"
        
        for ip_service in "$cloudflare" "$ifconfig" "$icanhazip"; do
            if [ -z "$ipv6_addr" ]; then
                debug_log "DEBUG" "Trying service: $ip_service"
                
                if [ "$ip_service" = "$cloudflare" ]; then
                    ipv6_addr=$($BASE_WGET -$iptype -T "$timeout" -O- "https://$ip_service" 2>/dev/null | grep "ip=" | cut -d= -f2)
                else
                    ipv6_addr=$($BASE_WGET -$iptype -T "$timeout" -O- "https://$ip_service" 2>/dev/null)
                fi
                
                if [ -n "$ipv6_addr" ]; then
                    debug_log "DEBUG" "Successfully retrieved IPv6: $ipv6_addr"
                    break
                fi
            fi
        done
    done
    
    # キャッシュファイルに結果を書き込み
    {
        echo "IPV4_ADDR=\"$ipv4_addr\""
        echo "IPV6_ADDR=\"$ipv6_addr\""
        echo "IP_UPDATE_TIME=\"$(date '+%Y-%m-%d %H:%M:%S')\""
    } > "$ip_cache"
    
    debug_log "DEBUG" "IP information saved to cache: $ip_cache"
    
    return 0
}

detect_mape_from_cache() {
    local ip_cache="$CACHE_DIR/ip_address.ch"
    local provider_cache="$CACHE_DIR/mape_provider.ch"
    local ipv6_addr=""
    local provider="unknown"
    
    # キャッシュが存在しなければアドレス取得を実行
    if [ ! -f "$ip_cache" ]; then
        debug_log "DEBUG" "No IP address cache found. Running get_address()"
        get_address
    fi
    
    # キャッシュからIPv6アドレスを読み込み
    if [ -f "$ip_cache" ]; then
        # シェルスクリプトから変数を読み込む
        . "$ip_cache"
        ipv6_addr="$IPV6_ADDR"
        
        if [ -n "$ipv6_addr" ]; then
            debug_log "DEBUG" "Found IPv6 address in cache: $ipv6_addr"
            provider=$(detect_mape_provider "$ipv6_addr")
            
            # プロバイダー情報をキャッシュに保存（MAP-Eのみ）
            if [ "$provider" != "unknown" ]; then
                {
                    echo "MAPE_PROVIDER=\"$provider\""
                    echo "MAPE_UPDATE_TIME=\"$(date '+%Y-%m-%d %H:%M:%S')\""
                } > "$provider_cache"
                
                debug_log "DEBUG" "MAP-E provider information saved to cache: $provider_cache"
            else
                debug_log "DEBUG" "No MAP-E provider detected for this IPv6 address"
            fi
        else
            debug_log "DEBUG" "No IPv6 address found in cache"
        fi
    else
        debug_log "DEBUG" "Failed to read IP address cache"
    fi
    
    echo "$provider"
    return 0
}

detect_mape_provider() {
    local ipv6="$1"
    local provider="unknown"
    
    if [ -z "$ipv6" ]; then
        debug_log "DEBUG" "No IPv6 address provided for MAP-E provider detection"
        return 1
    fi
    
    # プレフィックスの抽出（短い形式）
    local prefix
    prefix=$(echo "$ipv6" | sed -E 's/([0-9a-f]+:[0-9a-f]+).*/\1/i')
    debug_log "DEBUG" "Extracted IPv6 prefix: $prefix"
    
    # MAP-Eプロバイダー判定（MAP-E技術を使用しているプロバイダーのみ）
    case "$prefix" in
        # SoftBank（V6プラス）- MAP-E
        "2404:7a")
            provider="mape_v6plus"
            debug_log "DEBUG" "Detected SoftBank V6plus (MAP-E) from prefix"
            ;;
        # KDDI（IPv6オプション）- MAP-E
        "2001:f9")
            provider="mape_ipv6option"
            debug_log "DEBUG" "Detected KDDI IPv6option (MAP-E) from prefix"
            ;;
        # OCN - MAP-E
        "2001:0c"|"2400:38")
            provider="mape_ocn"
            debug_log "DEBUG" "Detected OCN MAP-E from prefix"
            ;;
        # BIGLOBE - MAP-E
        "2001:26"|"2001:f6")
            provider="mape_biglobe"
            debug_log "DEBUG" "Detected BIGLOBE MAP-E from prefix"
            ;;
        # NURO光 - MAP-E
        "240d:00")
            provider="mape_nuro"
            debug_log "DEBUG" "Detected NURO MAP-E from prefix"
            ;;
        # JPNE NGN - MAP-E
        "2404:92")
            provider="mape_jpne"
            debug_log "DEBUG" "Detected JPNE MAP-E from prefix"
            ;;
        # So-net - MAP-E
        "240b:10"|"240b:11"|"240b:12"|"240b:13")
            provider="mape_sonet"
            debug_log "DEBUG" "Detected So-net MAP-E from prefix"
            ;;
        # @nifty - MAP-E
        "2001:f7")
            provider="mape_nifty"
            debug_log "DEBUG" "Detected @nifty MAP-E from prefix"
            ;;
        *)
            provider="unknown"
            debug_log "DEBUG" "No MAP-E provider detected for prefix: $prefix"
            ;;
    esac
    
    echo "$provider"
    return 0
}

detect_dslite_from_cache() {
    local ip_cache="$CACHE_DIR/ip_address.ch"
    local provider_cache="$CACHE_DIR/dslite_provider.ch"
    local ipv6_addr=""
    local provider="unknown"
    
    # キャッシュが存在しなければアドレス取得を実行
    if [ ! -f "$ip_cache" ]; then
        debug_log "DEBUG" "No IP address cache found. Running get_address()"
        get_address
    fi
    
    # キャッシュからIPv6アドレスを読み込み
    if [ -f "$ip_cache" ]; then
        # シェルスクリプトから変数を読み込む
        . "$ip_cache"
        ipv6_addr="$IPV6_ADDR"
        
        if [ -n "$ipv6_addr" ]; then
            debug_log "DEBUG" "Found IPv6 address in cache: $ipv6_addr"
            provider=$(detect_dslite_provider "$ipv6_addr")
            
            # プロバイダー情報をキャッシュに保存（DS-Liteのみ）
            if [ "$provider" != "unknown" ]; then
                {
                    echo "DSLITE_PROVIDER=\"$provider\""
                    echo "DSLITE_UPDATE_TIME=\"$(date '+%Y-%m-%d %H:%M:%S')\""
                } > "$provider_cache"
                
                debug_log "DEBUG" "DS-Lite provider information saved to cache: $provider_cache"
            else
                debug_log "DEBUG" "No DS-Lite provider detected for this IPv6 address"
            fi
        else
            debug_log "DEBUG" "No IPv6 address found in cache"
        fi
    else
        debug_log "DEBUG" "Failed to read IP address cache"
    fi
    
    echo "$provider"
    return 0
}

detect_dslite_provider() {
    local ipv6="$1"
    local provider="unknown"
    
    if [ -z "$ipv6" ]; then
        debug_log "DEBUG" "No IPv6 address provided for DS-Lite provider detection"
        return 1
    fi
    
    # プレフィックスの抽出（短い形式と詳細形式）
    local prefix
    prefix=$(echo "$ipv6" | sed -E 's/([0-9a-f]+:[0-9a-f]+).*/\1/i')
    debug_log "DEBUG" "Extracted IPv6 prefix: $prefix"
    
    # より詳細なプレフィックス（東西判定用）
    local long_prefix
    long_prefix=$(echo "$ipv6" | sed -E 's/([0-9a-f]+:[0-9a-f]+:[0-9a-f]+).*/\1/i')
    debug_log "DEBUG" "Extracted long IPv6 prefix: $long_prefix"
    
    # DS-Liteプロバイダ判定（Transix、Xpass、v6connectの3種類×東西の計6種類）
    case "$long_prefix" in
        # NTT東日本（トランジックス）
        "2404:8e01:"*)
            provider="dslite_east_transix"
            debug_log "DEBUG" "Detected NTT East DS-Lite with Transix"
            ;;
        # NTT西日本（トランジックス）
        "2404:8e00:"*)
            provider="dslite_west_transix"
            debug_log "DEBUG" "Detected NTT West DS-Lite with Transix"
            ;;
        # v6コネクト東日本
        "2404:0100:"*)
            provider="dslite_east_v6connect"
            debug_log "DEBUG" "Detected NTT East DS-Lite with v6connect"
            ;;
        # v6コネクト西日本
        "2404:0101:"*)
            provider="dslite_west_v6connect"
            debug_log "DEBUG" "Detected NTT West DS-Lite with v6connect"
            ;;
        # Xpass東日本
        "2409:10:"*)
            provider="dslite_east_xpass"
            debug_log "DEBUG" "Detected NTT East DS-Lite with Xpass"
            ;;
        # Xpass西日本
        "2409:11:"*)
            provider="dslite_west_xpass"
            debug_log "DEBUG" "Detected NTT West DS-Lite with Xpass"
            ;;
        *)
            # より短いプレフィックスで判定（東西不明な場合）
            case "$prefix" in
                # トランジックス系（東西不明）
                "2404:8e")
                    provider="dslite_transix"
                    debug_log "DEBUG" "Detected DS-Lite with Transix (region unknown)"
                    ;;
                # v6コネクト系（東西不明）
                "2404:01")
                    provider="dslite_v6connect"
                    debug_log "DEBUG" "Detected DS-Lite with v6connect (region unknown)"
                    ;;
                # Xpass系（東西不明）
                "2409:10"|"2409:11")
                    provider="dslite_xpass"
                    debug_log "DEBUG" "Detected DS-Lite with Xpass (region unknown)"
                    ;;
                # その他のプレフィックスは未知のDS-Liteとして扱う
                *)
                    provider="unknown"
                    debug_log "DEBUG" "No DS-Lite provider detected for prefix: $prefix"
                    ;;
            esac
            ;;
    esac
    
    echo "$provider"
    return 0
}

# ISP情報表示（拡張版）
display_isp_info() {
    local provider="$1"
    local display_name=""
   
    # 情報ソースを表示
    printf "%s\n" "$(color white "$(get_message "MSG_ISP_INFO_SOURCE" "source=IPv6プレフィックス検出")")"
    
    debug_log "DEBUG" "Mapping provider ID to display name: $provider"
    
    # プロバイダ名の日本語表示（拡張版）
    case "$provider" in
        # MAP-E系サービス
        mape_ocn)           display_name="MAP-E OCN" ;;
        mape_v6plus)        display_name="SoftBank V6プラス" ;;
        mape_ipv6option)    display_name="KDDI IPv6オプション" ;;
        mape_nuro)          display_name="NURO光 MAP-E" ;;
        mape_biglobe)       display_name="BIGLOBE IPv6" ;;
        mape_jpne)          display_name="JPNE IPv6" ;;
        mape_sonet)         display_name="So-net IPv6" ;;
        mape_nifty)         display_name="@nifty IPv6" ;;
        
        # DS-Lite系サービス（東西区分あり）
        dslite_east_transix) display_name="NTT東日本 DS-Lite (Transix)" ;;
        dslite_west_transix) display_name="NTT西日本 DS-Lite (Transix)" ;;
        dslite_east_xpass)   display_name="NTT東日本 DS-Lite (Xpass)" ;;
        dslite_west_xpass)   display_name="NTT西日本 DS-Lite (Xpass)" ;;
        dslite_east_v6connect) display_name="NTT東日本 DS-Lite (v6connect)" ;;
        dslite_west_v6connect) display_name="NTT西日本 DS-Lite (v6connect)" ;;
        
        # DS-Lite系サービス（東西区分なし）
        dslite_transix)     display_name="DS-Lite (Transix)" ;;
        dslite_xpass)       display_name="DS-Lite (Xpass)" ;;
        dslite_v6connect)   display_name="DS-Lite (v6connect)" ;;
        
        # その他のDS-Lite
        dslite_east)        display_name="NTT東日本 DS-Lite" ;;
        dslite_west)        display_name="NTT西日本 DS-Lite" ;;
        dslite*)            display_name="DS-Lite" ;;
        
        # PPPoE系サービス
        pppoe_ctc)          display_name="中部テレコム PPPoE" ;;
        pppoe_iij)          display_name="IIJ PPPoE" ;;
        
        # 海外ISP
        overseas)           display_name="海外ISP" ;;
        
        # 不明なプロバイダ
        *)                  display_name="不明なISP" ;;
    esac
    
    debug_log "DEBUG" "Mapped to display name: $display_name"
    
    # 接続タイプを表示
    printf "%s\n" "$(color white "$(get_message "MSG_ISP_TYPE") $display_name")"
}

detect_isp_type() {
    local ip_cache="$CACHE_DIR/ip_address.ch"
    local ipv4_addr=""
    local ipv6_addr=""
    local provider="unknown"
    
    # キャッシュが存在しなければアドレス取得を実行
    if [ ! -f "$ip_cache" ]; then
        debug_log "DEBUG" "No IP address cache found. Retrieving addresses"
        get_address
    fi
    
    # キャッシュからIPアドレスを読み込み
    if [ -f "$ip_cache" ]; then
        # シェルスクリプトから変数を読み込む
        . "$ip_cache"
        ipv4_addr="$IPV4_ADDR"
        ipv6_addr="$IPV6_ADDR"
        
        debug_log "DEBUG" "Retrieved IPv4=$ipv4_addr IPv6=$ipv6_addr from cache"
    else
        debug_log "DEBUG" "Failed to read IP address cache"
        return 1
    fi
    
    # IPv6アドレスがある場合はプロバイダ判定を試みる
    if [ -n "$ipv6_addr" ]; then
        # MAP-E判定を優先
        provider=$(detect_mape_provider "$ipv6_addr")
        
        # MAP-Eでない場合はDS-Liteを試す
        if [ "$provider" = "unknown" ]; then
            provider=$(detect_dslite_provider "$ipv6_addr")
        fi
        
        # 海外ISP判定（日本以外のIPアドレスか確認）
        if [ "$provider" = "unknown" ] && [ -n "$ipv4_addr" ]; then
            # IPアドレス国判定関数が実装されていると仮定
            is_japan=$(detect_ip_country "$ipv4_addr")
            if [ "$is_japan" = "false" ]; then
                provider="overseas"
                debug_log "DEBUG" "Detected overseas ISP based on IP geolocation"
            fi
        fi
    fi
    
    echo "$provider"
    return 0
}

# メイン処理実行
detect_isp_type "$@"
