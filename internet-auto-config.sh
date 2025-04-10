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
    local result=""
    local cloudflare="one.one.one.one/cdn-cgi/trace"
    local ifconfig="ifconfig.me/ip"
    local icanhazip="icanhazip.com"
    local timeout=5
    local ip_cache="$CACHE_DIR/ip_address.ch"
    
    debug_log "DEBUG" "Starting IP address detection"
    
    # IPv4取得処理 - Cloudflare
    debug_log "DEBUG" "Testing IPv4 via Cloudflare"
    result=$($BASE_WGET -4 -T "$timeout" -O- "https://$cloudflare" 2>/dev/null)
    if [ -n "$result" ]; then
        ipv4_addr=$(echo "$result" | grep "ip=" | cut -d= -f2)
        debug_log "DEBUG" "Cloudflare IPv4 result: $ipv4_addr"
    fi
    
    # IPv4取得処理 - icanhazip
    if [ -z "$ipv4_addr" ]; then
        debug_log "DEBUG" "Testing IPv4 via icanhazip"
        ipv4_addr=$($BASE_WGET -4 -T "$timeout" -O- "https://$icanhazip" 2>/dev/null)
        debug_log "DEBUG" "icanhazip IPv4 result: $ipv4_addr"
    fi
    
    # IPv4取得処理 - ifconfig.me
    if [ -z "$ipv4_addr" ]; then
        debug_log "DEBUG" "Testing IPv4 via ifconfig.me"
        ipv4_addr=$($BASE_WGET -4 -T "$timeout" -O- "https://$ifconfig" 2>/dev/null)
        debug_log "DEBUG" "ifconfig.me IPv4 result: $ipv4_addr"
    fi
    
    # IPv6取得処理 - Cloudflare
    debug_log "DEBUG" "Testing IPv6 via Cloudflare"
    result=$($BASE_WGET -6 -T "$timeout" -O- "https://$cloudflare" 2>/dev/null)
    if [ -n "$result" ]; then
        ipv6_addr=$(echo "$result" | grep "ip=" | cut -d= -f2)
        debug_log "DEBUG" "Cloudflare IPv6 result: $ipv6_addr"
    fi
    
    # IPv6取得処理 - icanhazip
    if [ -z "$ipv6_addr" ]; then
        debug_log "DEBUG" "Testing IPv6 via icanhazip"
        ipv6_addr=$($BASE_WGET -6 -T "$timeout" -O- "https://$icanhazip" 2>/dev/null)
        debug_log "DEBUG" "icanhazip IPv6 result: $ipv6_addr"
    fi
    
    # IPv6取得処理 - ifconfig.me
    if [ -z "$ipv6_addr" ]; then
        debug_log "DEBUG" "Testing IPv6 via ifconfig.me"
        ipv6_addr=$($BASE_WGET -6 -T "$timeout" -O- "https://$ifconfig" 2>/dev/null)
        debug_log "DEBUG" "ifconfig.me IPv6 result: $ipv6_addr"
    fi
    
    # 結果のクリーニング
    if [ -n "$ipv4_addr" ]; then
        ipv4_addr=$(echo "$ipv4_addr" | tr -d '\r\n')
        debug_log "DEBUG" "Cleaned IPv4 address: $ipv4_addr"
    fi
    
    if [ -n "$ipv6_addr" ]; then
        ipv6_addr=$(echo "$ipv6_addr" | tr -d '\r\n')
        debug_log "DEBUG" "Cleaned IPv6 address: $ipv6_addr"
    fi
    
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

# 日本の主要MAP-E接続を正確に検出する関数
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
    
    # 正確なMAP-E対応ISP判定
    case "$prefix" in
        # === OCNバーチャルConnect系（MAP-E） - NTT Com ===
        "2404:7a")
            provider="mape_ocn_virtual"
            debug_log "DEBUG" "Detected OCN Virtual Connect MAP-E"
            ;;
            
        # === V6プラス系（MAP-E） - JPIX ===
        # SoftBank系
        "240b:10"|"240b:11"|"240b:12"|"240b:13"|"240b:250"|"240b:251"|"240b:252"|"240b:253")
            provider="mape_v6plus_softbank"
            debug_log "DEBUG" "Detected V6plus/SoftBank MAP-E"
            ;;
            
        # So-net系
        "240b:10"|"240b:11"|"240b:12"|"240b:13")
            provider="mape_v6plus_sonet"
            debug_log "DEBUG" "Detected V6plus/So-net MAP-E"
            ;;
            
        # @nifty系
        "2001:f7")
            provider="mape_v6plus_nifty"
            debug_log "DEBUG" "Detected V6plus/@nifty MAP-E"
            ;;
            
        # GMOとくとくBB系
        "2400:09")
            provider="mape_v6plus_gmobb"
            debug_log "DEBUG" "Detected V6plus/GMO TokuToku BB MAP-E"
            ;;
            
        # DMM光系
        "2400:2c")
            provider="mape_v6plus_dmm"
            debug_log "DEBUG" "Detected V6plus/DMM MAP-E"
            ;;
            
        # Tigers-net系
        "2404:5200")
            provider="mape_v6plus_tigers"
            debug_log "DEBUG" "Detected V6plus/Tigers-net MAP-E"
            ;;
            
        # === その他の主要MAP-E接続 ===
        # KDDI IPv6オプション
        "2001:f9")
            provider="mape_ipv6option_kddi"
            debug_log "DEBUG" "Detected KDDI IPv6option MAP-E"
            ;;
            
        # BIGLOBEのIPv6オプション
        "2001:26"|"2001:f6")
            provider="mape_ipv6option_biglobe"
            debug_log "DEBUG" "Detected BIGLOBE IPv6option MAP-E"
            ;;
            
        # NURO光
        "240d:00")
            provider="mape_nuro"
            debug_log "DEBUG" "Detected NURO MAP-E"
            ;;
            
        # IIJmio（フレッツ系・MAP-E）
        "2400:41")
            provider="mape_iijmio"
            debug_log "DEBUG" "Detected IIJmio MAP-E"
            ;;
            
        # ぷらら光（フレッツ系・MAP-E）
        "2400:31")
            provider="mape_plala"
            debug_log "DEBUG" "Detected Plala MAP-E"
            ;;
            
        # hi-ho光（フレッツ系・MAP-E）
        "2001:378")
            provider="mape_hiho"
            debug_log "DEBUG" "Detected hi-ho MAP-E"
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

detect_pppoe_from_cache() {
    local ip_cache="$CACHE_DIR/ip_address.ch"
    local provider_cache="$CACHE_DIR/pppoe_provider.ch"
    local ipv4_addr=""
    local provider="unknown"
    
    # キャッシュが存在しなければアドレス取得を実行
    if [ ! -f "$ip_cache" ]; then
        debug_log "DEBUG" "No IP address cache found. Running get_address()"
        get_address
    fi
    
    # キャッシュからIPv4アドレスを読み込み
    if [ -f "$ip_cache" ]; then
        # シェルスクリプトから変数を読み込む
        . "$ip_cache"
        ipv4_addr="$IPV4_ADDR"
        
        if [ -n "$ipv4_addr" ]; then
            debug_log "DEBUG" "Found IPv4 address in cache: $ipv4_addr"
            provider=$(detect_pppoe_provider "$ipv4_addr")
            
            # プロバイダー情報をキャッシュに保存
            if [ "$provider" != "unknown" ]; then
                {
                    echo "PPPOE_PROVIDER=\"$provider\""
                    echo "PPPOE_UPDATE_TIME=\"$(date '+%Y-%m-%d %H:%M:%S')\""
                } > "$provider_cache"
                
                debug_log "DEBUG" "PPPoE provider information saved to cache: $provider_cache"
            else
                debug_log "DEBUG" "No specific PPPoE provider detected for this IPv4 address"
            fi
        else
            debug_log "DEBUG" "No IPv4 address found in cache"
        fi
    else
        debug_log "DEBUG" "Failed to read IP address cache"
    fi
    
    echo "$provider"
    return 0
}

detect_pppoe_provider() {
    local ipv4="$1"
    local provider="unknown"
    
    if [ -z "$ipv4" ]; then
        debug_log "DEBUG" "No IPv4 address provided for PPPoE ISP detection"
        return 1
    fi
    
    # IPv4アドレス範囲によるISP判定
    # 先頭オクテットによる大まかな分類
    local first_octet
    first_octet=$(echo "$ipv4" | cut -d. -f1)
    
    debug_log "DEBUG" "Analyzing IPv4 address: $ipv4 (first octet: $first_octet)"
    
    # まず大まかなIPv4範囲で判定
    case "$first_octet" in
        60)
            # J:COMなどケーブルTV系
            case "$ipv4" in
                60.33.*|60.34.*|60.112.*|60.116.*)
                    provider="pppoe_jcom"
                    debug_log "DEBUG" "Detected J:COM cable PPPoE connection"
                    ;;
                60.236.*|60.237.*)
                    provider="pppoe_cnci"
                    debug_log "DEBUG" "Detected CNCI cable PPPoE connection"
                    ;;
                *)
                    provider="pppoe_cable"
                    debug_log "DEBUG" "Detected generic cable TV PPPoE connection"
                    ;;
            esac
            ;;
        61)
            # 電力系ISP
            case "$ipv4" in
                61.7.*|61.8.*)
                    provider="pppoe_tepco"
                    debug_log "DEBUG" "Detected TEPCO (Tokyo Electric) PPPoE connection"
                    ;;
                61.119.*|61.120.*)
                    provider="pppoe_energy"
                    debug_log "DEBUG" "Detected energy company PPPoE connection"
                    ;;
                *)
                    provider="pppoe_power_company"
                    debug_log "DEBUG" "Detected power company ISP PPPoE connection"
                    ;;
            esac
            ;;
        101)
            # KDDI系
            provider="pppoe_kddi"
            debug_log "DEBUG" "Detected KDDI PPPoE connection"
            ;;
        111)
            # KDDI系(auひかり)
            provider="pppoe_au_hikari"
            debug_log "DEBUG" "Detected au Hikari PPPoE connection"
            ;;
        114|119)
            # NTT系
            provider="pppoe_ntt"
            debug_log "DEBUG" "Detected NTT PPPoE connection"
            ;;
        118)
            # BBIQ(九州電力系)
            provider="pppoe_bbiq"
            debug_log "DEBUG" "Detected BBIQ (Kyushu Electric) PPPoE connection"
            ;;
        183)
            # 中部テレコム/コミュファ関連
            case "$ipv4" in
                183.177.*)
                    provider="pppoe_commufa"
                    debug_log "DEBUG" "Detected Commufa (CTC) PPPoE connection"
                    ;;
                *)
                    provider="pppoe_ctc"
                    debug_log "DEBUG" "Detected CTC PPPoE connection"
                    ;;
            esac
            ;;
        202)
            # IIJ/ASAHIネット
            case "$ipv4" in
                202.232.*)
                    provider="pppoe_iij"
                    debug_log "DEBUG" "Detected IIJ PPPoE connection"
                    ;;
                202.222.*)
                    provider="pppoe_asahi"
                    debug_log "DEBUG" "Detected Asahi-net PPPoE connection"
                    ;;
            esac
            ;;
        203)
            # ケーブルTV/地域系
            case "$ipv4" in
                203.139.*)
                    provider="pppoe_cable_media"
                    debug_log "DEBUG" "Detected cable TV media PPPoE connection"
                    ;;
                203.141.*)
                    provider="pppoe_zaq"
                    debug_log "DEBUG" "Detected ZAQ cable PPPoE connection"
                    ;;
            esac
            ;;
        210)
            # OCN
            provider="pppoe_ocn"
            debug_log "DEBUG" "Detected OCN PPPoE connection"
            ;;
        218)
            # 東北電力/コミュファ
            case "$ipv4" in
                218.222.*)
                    provider="pppoe_commufa" 
                    debug_log "DEBUG" "Detected Commufa PPPoE connection"
                    ;;
                218.30.*|218.31.*)
                    provider="pppoe_tohoku_electric"
                    debug_log "DEBUG" "Detected Tohoku Electric PPPoE connection"
                    ;;
            esac
            ;;
        219)
            # BIGLOBE
            provider="pppoe_biglobe"
            debug_log "DEBUG" "Detected BIGLOBE PPPoE connection"
            ;;
        220)
            # So-net
            provider="pppoe_sonet"
            debug_log "DEBUG" "Detected So-net PPPoE connection"
            ;;
        *)
            provider="unknown"
            debug_log "DEBUG" "Unknown ISP for IPv4 address range"
            ;;
    esac
    
    echo "$provider"
    return 0
}

detect_mobile_from_cache() {
    local ip_cache="$CACHE_DIR/ip_address.ch"
    local provider_cache="$CACHE_DIR/mobile_provider.ch"
    local ipv4_addr=""
    local provider="unknown"
    
    # キャッシュが存在しなければアドレス取得を実行
    if [ ! -f "$ip_cache" ]; then
        debug_log "DEBUG" "No IP address cache found. Running get_address()"
        get_address
    fi
    
    # キャッシュからIPv4アドレスを読み込み
    if [ -f "$ip_cache" ]; then
        # シェルスクリプトから変数を読み込む
        . "$ip_cache"
        ipv4_addr="$IPV4_ADDR"
        
        if [ -n "$ipv4_addr" ]; then
            debug_log "DEBUG" "Found IPv4 address in cache: $ipv4_addr"
            provider=$(detect_mobile_provider "$ipv4_addr")
            
            # プロバイダー情報をキャッシュに保存（モバイルキャリアのみ）
            if [ "$provider" != "unknown" ]; then
                {
                    echo "MOBILE_PROVIDER=\"$provider\""
                    echo "MOBILE_UPDATE_TIME=\"$(date '+%Y-%m-%d %H:%M:%S')\""
                } > "$provider_cache"
                
                debug_log "DEBUG" "Mobile carrier information saved to cache: $provider_cache"
            else
                debug_log "DEBUG" "No mobile carrier detected for this IPv4 address"
            fi
        else
            debug_log "DEBUG" "No IPv4 address found in cache"
        fi
    else
        debug_log "DEBUG" "Failed to read IP address cache"
    fi
    
    echo "$provider"
    return 0
}

detect_mobile_provider() {
    local ipv4="$1"
    local provider="unknown"
    
    if [ -z "$ipv4" ]; then
        debug_log "DEBUG" "No IPv4 address provided for mobile carrier detection"
        return 1
    fi
    
    # IPv4アドレス範囲によるモバイルキャリア判定
    debug_log "DEBUG" "Analyzing IPv4 address for mobile carrier: $ipv4"
    
    # モバイル通信事業者のIPアドレス範囲での判定
    case "$ipv4" in
        # NTTドコモ (docomo)
        1.66.*|1.72.*|1.79.*|110.163.*|110.164.*)
            provider="mobile_docomo"
            debug_log "DEBUG" "Detected NTT docomo mobile connection"
            ;;
        # KDDI (au)
        106.128.*|106.129.*|106.130.*|106.131.*|106.132.*|106.133.*)
            provider="mobile_au"
            debug_log "DEBUG" "Detected KDDI (au) mobile connection"
            ;;
        # ソフトバンク (SoftBank)
        126.78.*|126.79.*|126.80.*|126.81.*|126.82.*|126.83.*|126.84.*|126.85.*|126.86.*|126.87.*|126.88.*|126.89.*)
            provider="mobile_softbank"
            debug_log "DEBUG" "Detected SoftBank mobile connection"
            ;;
        # 楽天モバイル (Rakuten)
        133.106.*|133.107.*|133.108.*|133.109.*)
            provider="mobile_rakuten"
            debug_log "DEBUG" "Detected Rakuten mobile connection"
            ;;
        # ahamo (ドコモサブブランド)
        1.73.*|1.74.*|1.75.*|1.76.*|1.77.*)
            provider="mobile_ahamo"
            debug_log "DEBUG" "Detected ahamo (docomo sub-brand) mobile connection"
            ;;
        # UQモバイル (KDDIサブブランド)
        106.134.*|106.135.*|106.136.*|106.137.*|106.138.*|106.139.*)
            provider="mobile_uq"
            debug_log "DEBUG" "Detected UQ mobile (KDDI sub-brand) connection"
            ;;
        # Y!mobile (ソフトバンクサブブランド)
        126.90.*|126.91.*|126.92.*|126.93.*|126.94.*|126.95.*)
            provider="mobile_ymobile"
            debug_log "DEBUG" "Detected Y!mobile (SoftBank sub-brand) connection"
            ;;
        # その他のモバイル通信と思われるIP範囲
        10.*)
            # プライベートIPを使う可能性が高いモバイル回線
            provider="mobile_generic"
            debug_log "DEBUG" "Detected generic mobile connection (private IP range)"
            ;;
        *)
            provider="unknown"
            debug_log "DEBUG" "No mobile carrier detected for this IPv4 address range"
            ;;
    esac
    
    echo "$provider"
    return 0
}

display_isp_info() {
    local provider="$1"
    local display_name=""
   
    # 情報ソースを表示
    printf "%s\n" "$(color white "$(get_message "MSG_ISP_INFO_SOURCE" "s=IPアドレス検出")")"
    
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
        pppoe_commufa)      display_name="コミュファ光 PPPoE" ;;
        pppoe_iij)          display_name="IIJ PPPoE" ;;
        pppoe_ocn)          display_name="OCN PPPoE" ;;
        pppoe_biglobe)      display_name="BIGLOBE PPPoE" ;;
        pppoe_sonet)        display_name="So-net PPPoE" ;;
        pppoe_asahi)        display_name="ASAHIネット PPPoE" ;;
        pppoe_ntt)          display_name="フレッツ光 PPPoE" ;;
        pppoe_au_hikari)    display_name="auひかり PPPoE" ;;
        pppoe_kddi)         display_name="KDDI PPPoE" ;;
        pppoe_bbiq)         display_name="BBIQ PPPoE" ;;
        pppoe_tepco)        display_name="TEPCO PPPoE" ;;
        pppoe_power_company) display_name="電力系 PPPoE" ;;
        pppoe_jcom)         display_name="J:COM PPPoE" ;;
        pppoe_cable)        display_name="ケーブルTV PPPoE" ;;
        pppoe_zaq)          display_name="ZAQ PPPoE" ;;
        pppoe_tohoku_electric) display_name="東北電力 PPPoE" ;;
        pppoe_*)            display_name="一般 PPPoE" ;;
        
        # モバイル通信
        mobile_docomo)      display_name="NTTドコモ モバイル" ;;
        mobile_au)          display_name="au（KDDI）モバイル" ;;
        mobile_softbank)    display_name="ソフトバンク モバイル" ;;
        mobile_rakuten)     display_name="楽天モバイル" ;;
        mobile_ahamo)       display_name="ahamo（ドコモ系）" ;;
        mobile_uq)          display_name="UQモバイル（KDDI系）" ;;
        mobile_ymobile)     display_name="ワイモバイル（SB系）" ;;
        mobile_generic)     display_name="モバイル通信" ;;
        mobile_*)           display_name="モバイル通信" ;;
        
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
    
    # 検出順序： MAP-E → DS-Lite → PPPoE → モバイル
    
    # 1. MAP-E検出（IPv6アドレスが必要）
    if [ -n "$ipv6_addr" ]; then
        debug_log "DEBUG" "Checking for MAP-E provider"
        provider=$(detect_mape_provider "$ipv6_addr")
        debug_log "DEBUG" "MAP-E detection result: $provider"
    else
        debug_log "DEBUG" "No IPv6 address, skipping MAP-E detection"
    fi
    
    # 2. MAP-Eで検出できなかった場合、DS-Lite検出（IPv6アドレスが必要）
    if [ "$provider" = "unknown" ] && [ -n "$ipv6_addr" ]; then
        debug_log "DEBUG" "Checking for DS-Lite provider"
        provider=$(detect_dslite_provider "$ipv6_addr")
        debug_log "DEBUG" "DS-Lite detection result: $provider"
    fi
    
    # 3. PPPoE検出（IPv4アドレスが必要）
    if [ "$provider" = "unknown" ] && [ -n "$ipv4_addr" ]; then
        debug_log "DEBUG" "Checking for PPPoE provider"
        provider=$(detect_pppoe_provider "$ipv4_addr")
        debug_log "DEBUG" "PPPoE detection result: $provider"
    fi
    
    # 4. モバイル検出（IPv4アドレスが必要）
    if [ "$provider" = "unknown" ] && [ -n "$ipv4_addr" ]; then
        debug_log "DEBUG" "Checking for mobile carrier"
        provider=$(detect_mobile_provider "$ipv4_addr")
        debug_log "DEBUG" "Mobile carrier detection result: $provider"
    fi
    
    # 5. 海外ISP判定（オプション）
    if [ "$provider" = "unknown" ] && [ -n "$ipv4_addr" ]; then
        # IPアドレス国判定関数がある場合の処理
        if command -v detect_ip_country >/dev/null 2>&1; then
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
