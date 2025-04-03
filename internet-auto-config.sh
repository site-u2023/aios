#!/bin/sh

SCRIPT_VERSION="2025.04.01-00-00"

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

detect_aftr_address() {
    echo "DEBUG: Detecting AFTR address for DS-LITE"
    
    # dig/nslookupコマンドでAFTRの候補を調べる
    local aftr_candidates="mgw.transix.jp dgw.xpass.jp aft.v6connect.net"
    local aftr_result=""
    
    # digコマンドが使える場合
    if command -v dig >/dev/null 2>&1; then
        echo "DEBUG: Using dig command to resolve AFTR"
        for candidate in $aftr_candidates; do
            echo "DEBUG: Checking AFTR candidate: $candidate"
            if dig AAAA "$candidate" +short 2>/dev/null | grep -q ":" ; then
                aftr_result="$candidate"
                echo "DEBUG: AFTR found: $aftr_result"
                echo "$aftr_result"
                return 0
            fi
        done
    # nslookupコマンドが使える場合
    elif command -v nslookup >/dev/null 2>&1; then
        echo "DEBUG: Using nslookup command to resolve AFTR"
        for candidate in $aftr_candidates; do
            echo "DEBUG: Checking AFTR candidate: $candidate"
            if nslookup -type=AAAA "$candidate" 2>/dev/null | grep -q "has AAAA address" ; then
                aftr_result="$candidate"
                echo "DEBUG: AFTR found: $aftr_result"
                echo "$aftr_result"
                return 0
            fi
        done
    fi
    
    # DIG/NSLOOKUPでAFTRが見つからない場合、他の方法でチェック
    local ping_result
    if command -v ping6 >/dev/null 2>&1; then
        echo "DEBUG: Testing AFTR connectivity with ping6"
        for candidate in $aftr_candidates; do
            echo "DEBUG: Pinging AFTR candidate: $candidate"
            if ping6 -c 1 "$candidate" >/dev/null 2>&1; then
                aftr_result="$candidate"
                echo "DEBUG: AFTR reachable with ping6: $aftr_result"
                echo "$aftr_result"
                return 0
            fi
        done
    fi
    
    echo "DEBUG: No AFTR address detected"
    return 1
}

detect_ipv6_provider() {
    local ipv6="$1"
    local provider="unknown"
    
    if [ -z "$ipv6" ]; then
        echo "DEBUG: No IPv6 address provided for provider detection"
        return 1
    fi
    
    # プレフィックスのより厳密な抽出
    local prefix
    prefix=$(echo "$ipv6" | sed -E 's/([0-9a-f]+:[0-9a-f]+).*/\1/i')
    echo "DEBUG: Extracted IPv6 prefix: $prefix"
    
    # 詳細なプレフィックス
    local long_prefix
    long_prefix=$(echo "$ipv6" | sed -E 's/([0-9a-f]+:[0-9a-f]+:[0-9a-f]+).*/\1/i')
    echo "DEBUG: Extracted long IPv6 prefix: $long_prefix"
    
    # プロバイダー判定の優先順位を明確に
    case "$long_prefix" in
        # NTT東日本（DS-Lite - トランジックス）
        "2404:8e01:"*)
            provider="dslite_east_transix"
            echo "DEBUG: Detected NTT East DS-Lite with transix from long prefix"
            ;;
        # NTT西日本（DS-Lite - トランジックス）
        "2404:8e00:"*)
            provider="dslite_west_transix"
            echo "DEBUG: Detected NTT West DS-Lite with transix from long prefix"
            ;;
        *)
            # 短いプレフィックスで判定
            case "$prefix" in
                # SoftBank（V6プラス）
                "2404:7a")
                    provider="mape_v6plus"
                    echo "DEBUG: Detected SoftBank V6plus from IPv6 prefix"
                    ;;
                # KDDI（IPv6オプション）
                "2001:f9")
                    provider="mape_ipv6option"
                    echo "DEBUG: Detected KDDI IPv6option from IPv6 prefix"
                    ;;
                # OCN
                "2001:0c"|"2400:38")
                    provider="mape_ocn"
                    echo "DEBUG: Detected OCN MAP-E from IPv6 prefix"
                    ;;
                # ビッグローブ BIGLOBE
                "2001:26"|"2001:f6")
                    provider="mape_biglobe"
                    echo "DEBUG: Detected BIGLOBE from IPv6 prefix"
                    ;;
                # NURO光
                "240d:00")
                    provider="mape_nuro"
                    echo "DEBUG: Detected NURO from IPv6 prefix"
                    ;;
                # JPNE NGN - これを先に判定
                "2404:92")
                    provider="mape_jpne"
                    echo "DEBUG: Detected JPNE from IPv6 prefix"
                    ;;
                # So-net
                "240b:10"|"240b:11"|"240b:12"|"240b:13")
                    provider="mape_sonet"
                    echo "DEBUG: Detected So-net from IPv6 prefix"
                    ;;
                # NTT東日本/西日本（DS-Lite）- トランジックス系
                "2404:8e")
                    provider="dslite_transix"
                    echo "DEBUG: Detected DS-Lite with transix (unknown region)"
                    ;;
                # v6コネクト系
                "2404:01")
                    provider="dslite_v6connect"
                    echo "DEBUG: Detected DS-Lite with v6connect"
                    ;;
                # @nifty
                "2001:f7")
                    provider="mape_nifty"
                    echo "DEBUG: Detected @nifty from IPv6 prefix"
                    ;;
                *)
                    provider="unknown"
                    echo "DEBUG: Unknown provider for prefix: $prefix"
                    ;;
            esac
            ;;
    esac
    
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

# ISP情報表示（シンプル版）
display_isp_info() {
    local provider="$1"
    local display_name=""
   
    # 情報ソースを表示
    printf "%s\n" "$(color white "$(get_message "MSG_ISP_INFO_SOURCE" "source=IPv6プレフィックス検出")")"
    
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
    
    # 接続タイプを表示
    printf "%s\n" "$(color white "$(get_message "MSG_ISP_TYPE") $display_name")"
}

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
        start_spinner "$(color blue "$(get_message "MSG_PROVIDER_ISP_TYPE")")" "yellow"
    else
        printf "%s\n" "$(get_message "MSG_PROVIDER_ISP_TYPE")" >&2
    fi
    
    # WAN情報取得（インターフェースとIPアドレス）
    echo "DEBUG: Starting ISP detection process"
    
    # get_wan_info関数の結果を取得して変数に設定
    eval "$(get_wan_info)"
    ipv4_addr="$IPV4_ADDR"
    ipv6_addr="$IPV6_ADDR"
    wan_if="$WAN_IF"
    wan_if6="$WAN_IF6"
    
    echo "DEBUG: Interface detection - WAN: $wan_if, WAN6: $wan_if6"
    echo "DEBUG: Address detection - IPv4: $ipv4_addr, IPv6: $ipv6_addr"
    
    # IPv6アドレスからプロバイダ判定
    if [ -n "$ipv6_addr" ]; then
        echo "DEBUG: IPv6 address detected: $ipv6_addr"
        
        # プレフィックスからプロバイダ判定
        provider=$(detect_ipv6_provider "$ipv6_addr")
        echo "DEBUG: Provider detection result from IPv6: $provider"
        
        # DS-LITEの場合はさらに詳細判定
        if echo "$provider" | grep -q "dslite"; then
            echo "DEBUG: DS-LITE detected, checking for AFTR"
            aftr_address=$(detect_aftr_address)
            
            if [ -n "$aftr_address" ]; then
                echo "DEBUG: AFTR address detected: $aftr_address"
                # AFTRからプロバイダの詳細判定
                if echo "$aftr_address" | grep -i "transix" >/dev/null 2>&1; then
                    provider="dslite_transix"
                    echo "DEBUG: Identified as transix DS-LITE"
                elif echo "$aftr_address" | grep -i "xpass" >/dev/null 2>&1; then
                    provider="dslite_xpass"
                    echo "DEBUG: Identified as xpass DS-LITE"
                elif echo "$aftr_address" | grep -i "v6connect" >/dev/null 2>&1; then
                    provider="dslite_v6connect"
                    echo "DEBUG: Identified as v6connect DS-LITE"
                fi
            fi
        fi
    else
        echo "DEBUG: No IPv6 address detected"
    fi
    
    # IPv4アドレスを使った補助判定（IPv6で判別できない場合）
    if [ "$provider" = "unknown" ] && [ -n "$ipv4_addr" ]; then
        echo "DEBUG: Using IPv4 address for supplementary detection: $ipv4_addr"
        
        # プライベートIPv4アドレスでDS-LITE判定
        if echo "$ipv4_addr" | grep -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)'; then
            echo "DEBUG: Private IPv4 detected, likely DS-LITE"
            provider="dslite"
            is_dslite=1
            
            # AFTR検出を試みる
            aftr_address=$(detect_aftr_address)
            if [ -n "$aftr_address" ]; then
                echo "DEBUG: AFTR address detected from IPv4 path: $aftr_address"
                
                # AFTRからプロバイダの詳細判定
                if echo "$aftr_address" | grep -i "transix" >/dev/null 2>&1; then
                    provider="dslite_transix"
                    echo "DEBUG: Identified as transix DS-LITE from IPv4 path"
                elif echo "$aftr_address" | grep -i "xpass" >/dev/null 2>&1; then
                    provider="dslite_xpass"
                    echo "DEBUG: Identified as xpass DS-LITE from IPv4 path"
                elif echo "$aftr_address" | grep -i "v6connect" >/dev/null 2>&1; then
                    provider="dslite_v6connect"
                    echo "DEBUG: Identified as v6connect DS-LITE from IPv4 path"
                fi
            fi
        else
            echo "DEBUG: Public IPv4 detected, checking other indicators"
            
            # 公開IPv4アドレスを持っている場合の追加チェック
            # ここに追加のチェックロジックを入れることも可能
        fi
    fi
    
    # 結果をファイルに書き込み
    mkdir -p "${CACHE_DIR}"
    printf "# ISP情報 %s\n" "$(date)" > "$isp_file"
    printf "CONNECTION_TYPE=\"%s\"\n" "$provider" >> "$isp_file"
    [ -n "$wan_if" ] && printf "WAN_INTERFACE=\"%s\"\n" "$wan_if" >> "$isp_file"
    [ -n "$wan_if6" ] && printf "WAN6_INTERFACE=\"%s\"\n" "$wan_if6" >> "$isp_file"
    [ -n "$ipv4_addr" ] && printf "IPV4_ADDRESS=\"%s\"\n" "$ipv4_addr" >> "$isp_file"
    [ -n "$ipv6_addr" ] && printf "IPV6_ADDRESS=\"%s\"\n" "$ipv6_addr" >> "$isp_file"
    [ -n "$aftr_address" ] && printf "AFTR_ADDRESS=\"%s\"\n" "$aftr_address" >> "$isp_file"
    [ "$is_dslite" = "1" ] && printf "IS_DSLITE=\"%s\"\n" "$is_dslite" >> "$isp_file"
    
    echo "DEBUG: ISP detection result saved to $isp_file with provider=$provider"
    
    # スピナー停止と結果表示
    if type stop_spinner >/dev/null 2>&1; then
        if [ "$provider" != "unknown" ]; then
            stop_spinner "$(color green "$(get_message "MSG_PROVIDER_INFO_SUCCESS")")" "success"
        else
            stop_spinner "$(color yellow "$(get_message "MSG_PROVIDER_INFO_FAILED")")" "warning"
        fi
    fi
    
    # 結果表示
    display_isp_info "$provider"
    
    return 0
}

# メイン処理実行
detect_isp_type "$@"
