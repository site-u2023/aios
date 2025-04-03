#!/bin/sh
#===============================================================================
# IPv6マイグレーション標準プロビジョニングTXTレコード取得スクリプト
#
# このスクリプトは、IPv6マイグレーション標準プロビジョニング仕様に準拠した
# DNS TXTレコードの取得と解析を行います。
#
# OpenWrt/ASH対応 POSIX準拠スクリプト
#===============================================================================

# 設定変数
VERSION="2025.04.04-1"
WAN_IFACE="wan"                      # WANインターフェース名
TEMP_DIR="/tmp"                      # 一時ファイル用ディレクトリ
CACHE_DIR="/tmp/v6mig_cache"         # キャッシュディレクトリ
DIG_TIMEOUT=3                        # dig コマンドのタイムアウト（秒）
MAX_RETRIES=2                        # リトライ回数

# プロビジョニングドメイン（優先度順）
PROV_DOMAINS="4over6.info v6mig.transix.jp jpne.co eonet.ne.jp ipv4v6.flets-east.jp ipv4v6.flets-west.jp"

# 代替DNSサーバーリスト（優先度順）
DNS_SERVERS="8.8.8.8 1.1.1.1 9.9.9.9 208.67.222.222"

# 情報出力関数
print_info() {
    echo "$1"
}

# エラー出力関数
print_error() {
    echo "エラー: $1" >&2
}

# キャッシュディレクトリ作成
create_cache_dir() {
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR"
        debug_log "Created cache directory at $CACHE_DIR"
    fi
}

# ネットワークライブラリ読み込み
load_network_libs() {
    if [ -f "/lib/functions/network.sh" ]; then
        . /lib/functions/network.sh
        . /lib/functions.sh
        network_flush_cache
        debug_log "OpenWrt network libraries loaded successfully"
        return 0
    else
        debug_log "OpenWrt network libraries not found, using standard methods"
        return 1
    fi
}

# 必要コマンド確認
check_commands() {
    local missing=""
    local required_commands="ip dig"
    
    for cmd in $required_commands; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    
    if [ -n "$missing" ]; then
        print_error "以下のコマンドが見つかりません:$missing"
        return 1
    fi
    
    return 0
}

# IPv6アドレス取得
get_ipv6_address() {
    local local_ipv6=""
    local net_if6=""
    
    debug_log "Retrieving IPv6 address from interface $WAN_IFACE"
    
    # OpenWrtのネットワーク関数使用
    if load_network_libs; then
        network_find_wan6 net_if6
        network_get_ipaddr6 local_ipv6 "${net_if6}"
        
        if [ -n "$local_ipv6" ]; then
            debug_log "Successfully retrieved IPv6 using OpenWrt network functions"
            echo "$local_ipv6"
            return 0
        fi
    fi
    
    # 一般的な方法でIPv6取得
    local_ipv6=$(ip -6 addr show dev "$WAN_IFACE" scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)
    
    if [ -n "$local_ipv6" ]; then
        debug_log "Successfully retrieved IPv6 using ip command"
        echo "$local_ipv6"
        return 0
    fi
    
    print_error "グローバルIPv6アドレスを取得できませんでした"
    return 1
}

# DNS接続チェック
check_dns_connectivity() {
    local dns_server="$1"
    local test_domain="example.com"
    
    if [ -z "$dns_server" ]; then
        # システムのDNS
        if dig +short +timeout=2 +tries=1 $test_domain A >/dev/null 2>&1; then
            debug_log "System DNS appears to be working"
            return 0
        else
            debug_log "System DNS check failed"
            return 1
        fi
    else
        # 指定DNSサーバー
        if dig +short +timeout=2 +tries=1 $test_domain A @"$dns_server" >/dev/null 2>&1; then
            debug_log "DNS server $dns_server is responding"
            return 0
        else
            debug_log "DNS server $dns_server is not responding"
            return 1
        fi
    fi
}

# TXTレコードの取得（詳細出力）
get_txt_records_verbose() {
    local domain=""
    local dns=""
    local tmp_file="$TEMP_DIR/txt_records_$$.txt"
    local found_records=0
    local result=1
    
    print_info "プロビジョニングTXTレコードの検索:"
    print_info "----------------------------------------"
    
    # まずDNSの動作確認
    print_info "DNS接続確認中..."
    if check_dns_connectivity ""; then
        print_info "システムDNSは正常に動作しています"
    else
        print_info "システムDNSに問題があります。代替DNSを使用します"
    fi
    
    # 各ドメインとDNSサーバーの組み合わせを試行
    for domain in $PROV_DOMAINS; do
        print_info "\nドメイン $domain を確認中:"
        
        # システムのDNSで試行
        print_info "  システムDNSで検索..."
        dig +short +timeout=$DIG_TIMEOUT +tries=$MAX_RETRIES TXT "$domain" > "$tmp_file" 2>/dev/null
        
        if [ -s "$tmp_file" ]; then
            txt_content=$(cat "$tmp_file" | sed -e 's/^"//' -e 's/"$//')
            print_info "  ✓ レコード発見! (システムDNS)"
            print_info "    内容: $txt_content"
            
            if echo "$txt_content" | grep -q "url="; then
                print_info "    ✓ 有効なプロビジョニングTXTレコード"
                result=0
            else
                print_info "    ✗ URLパラメータが含まれていません"
            fi
            
            found_records=$((found_records + 1))
        else
            print_info "  ✗ システムDNSでは見つかりませんでした"
            
            # 代替DNSサーバーで試行
            for dns in $DNS_SERVERS; do
                print_info "  代替DNS $dns で検索..."
                dig +short +timeout=$DIG_TIMEOUT +tries=$MAX_RETRIES TXT "$domain" @"$dns" > "$tmp_file" 2>/dev/null
                
                if [ -s "$tmp_file" ]; then
                    txt_content=$(cat "$tmp_file" | sed -e 's/^"//' -e 's/"$//')
                    print_info "  ✓ レコード発見! (DNS: $dns)"
                    print_info "    内容: $txt_content"
                    
                    if echo "$txt_content" | grep -q "url="; then
                        print_info "    ✓ 有効なプロビジョニングTXTレコード"
                        result=0
                    else
                        print_info "    ✗ URLパラメータが含まれていません"
                    fi
                    
                    found_records=$((found_records + 1))
                    break
                else
                    print_info "  ✗ DNS $dns でも見つかりませんでした"
                fi
            done
        fi
    done
    
    print_info "\n----------------------------------------"
    
    # 結果サマリー
    if [ $found_records -gt 0 ]; then
        print_info "合計 $found_records 件のTXTレコードが見つかりました"
    else
        print_info "TXTレコードは見つかりませんでした"
    fi
    
    # 一時ファイル削除
    rm -f "$tmp_file" 2>/dev/null
    
    return $result
}

# TXTレコード取得処理（単一レコード取得）
get_txt_record() {
    local domain=""
    local dns=""
    local txt_record=""
    local found=0
    
    debug_log "Attempting to retrieve valid provisioning TXT record"
    
    # 各ドメインとDNSサーバーの組み合わせを試行
    for domain in $PROV_DOMAINS; do
        # システムのDNSで試行
        debug_log "Trying system DNS for domain: $domain"
        txt_record=$(dig +short +timeout=$DIG_TIMEOUT +tries=$MAX_RETRIES TXT "$domain" 2>/dev/null | head -1 | sed -e 's/^"//' -e 's/"$//')
        
        if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
            debug_log "Found valid TXT record with system DNS"
            echo "$txt_record"
            return 0
        elif [ -n "$txt_record" ]; then
            debug_log "Found TXT record but no URL parameter: $txt_record"
        fi
        
        # 代替DNSサーバーで試行
        for dns in $DNS_SERVERS; do
            debug_log "Trying DNS $dns for domain: $domain"
            txt_record=$(dig +short +timeout=$DIG_TIMEOUT +tries=$MAX_RETRIES TXT "$domain" @"$dns" 2>/dev/null | head -1 | sed -e 's/^"//' -e 's/"$//')
            
            if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
                debug_log "Found valid TXT record with DNS $dns"
                echo "$txt_record"
                return 0
            elif [ -n "$txt_record" ]; then
                debug_log "Found TXT record but no URL parameter: $txt_record"
            fi
        done
    done
    
    debug_log "No valid TXT records found"
    return 1
}

# TXTレコードからURL抽出
extract_url() {
    local txt_record="$1"
    local url=""
    
    debug_log "Extracting URL from TXT record: $txt_record"
    
    # url=パターンの検索
    url=$(echo "$txt_record" | awk '{
        for (i=1; i<=NF; i++) {
            if ($i ~ /^url=/) {
                gsub(/^url=/, "", $i);
                print $i;
                exit;
            }
        }
    }')
    
    if [ -n "$url" ]; then
        debug_log "URL found: $url"
        echo "$url"
        return 0
    fi
    
    debug_log "No URL found in TXT record"
    return 1
}

# TXTレコードを解析してプロビジョニング情報を表示
analyze_txt_record() {
    local txt_record="$1"
    
    if [ -z "$txt_record" ]; then
        print_error "解析するTXTレコードがありません"
        return 1
    fi
    
    print_info "\n■ TXTレコード解析結果"
    print_info "レコード内容: $txt_record"
    
    # バージョン情報
    local version=$(echo "$txt_record" | awk '{
        for (i=1; i<=NF; i++) {
            if ($i ~ /^v=/) {
                gsub(/^v=/, "", $i);
                print $i;
                exit;
            }
        }
    }')
    
    if [ -n "$version" ]; then
        print_info "バージョン: $version"
    else
        print_info "バージョン: 未指定"
    fi
    
    # URL情報
    local url=$(extract_url "$txt_record")
    if [ -n "$url" ]; then
        print_info "プロビジョニングURL: $url"
    else
        print_info "プロビジョニングURL: 見つかりません"
    fi
    
    # プロトコルタイプ
    local type=$(echo "$txt_record" | awk '{
        for (i=1; i<=NF; i++) {
            if ($i ~ /^t=/) {
                gsub(/^t=/, "", $i);
                print $i;
                exit;
            }
        }
    }')
    
    if [ -n "$type" ]; then
        case "$type" in
            b) print_info "プロトコルタイプ: b (基本認証)" ;;
            d) print_info "プロトコルタイプ: d (ダイジェスト認証)" ;;
            n) print_info "プロトコルタイプ: n (認証なし)" ;;
            *) print_info "プロトコルタイプ: $type (不明)" ;;
        esac
    else
        print_info "プロトコルタイプ: 未指定"
    fi
    
    return 0
}

# ISP推定関数
guess_isp() {
    local ipv6_addr="$1"
    
    if [ -z "$ipv6_addr" ]; then
        print_info "ISP推定: IPv6アドレスが利用できません"
        return 1
    fi
    
    print_info "\n■ ISP推定結果"
    
    # IPv6アドレスプレフィックスからの推定
    local prefix=$(echo "$ipv6_addr" | cut -d: -f1-2)
    local prefix3=$(echo "$ipv6_addr" | cut -d: -f1-3)
    
    case "$prefix" in
        2400:*)
            case "$prefix3" in
                2400:4150:*|2400:4151:*|2400:4152:*)
                    print_info "推定ISP: NTT東日本 (フレッツ光系)"
                    print_info "MAP-E利用: 可能性あり"
                    print_info "推奨設定方式: NGN/MAP-E"
                    ;;
                2400:8500:*|2400:8501:*|2400:8502:*)
                    print_info "推定ISP: NTT西日本 (フレッツ光系)"
                    print_info "MAP-E利用: 可能性あり"
                    print_info "推奨設定方式: NGN/MAP-E"
                    ;;
                2400:9800:*|2400:9801:*)
                    print_info "推定ISP: KDDI (au ひかり)"
                    print_info "MAP-E利用: 可能性あり"
                    ;;
                *)
                    print_info "推定ISP: 不明 ($prefix)"
                    ;;
            esac
            ;;
        2001:*)
            case "$prefix3" in
                2001:358:*)
                    print_info "推定ISP: JPNE/IPoE対応事業者"
                    print_info "MAP-E利用: 可能性あり"
                    ;;
                2001:260:*)
                    print_info "推定ISP: OCN"
                    print_info "MAP-E利用: 可能性あり"
                    print_info "推奨設定方式: OCN MAP-E"
                    ;;
                *)
                    print_info "推定ISP: 不明 ($prefix)"
                    ;;
            esac
            ;;
        *)
            print_info "推定ISP: 不明 ($prefix)"
            ;;
    esac
    
    return 0
}

# メイン処理
main() {
    print_info "=== IPv6マイグレーションプロビジョニングTXTレコード取得 v$VERSION ==="
    
    # 初期化と必須コマンド確認
    create_cache_dir
    check_commands || exit 1
    
    # IPv6アドレスの取得
    print_info "\n■ IPv6アドレスの取得"
    local ipv6_addr=$(get_ipv6_address)
    if [ $? -ne 0 ]; then
        print_error "IPv6アドレスの取得に失敗しました"
    else
        print_info "IPv6アドレス: $ipv6_addr"
    fi
    
    # ISP推定
    if [ -n "$ipv6_addr" ]; then
        guess_isp "$ipv6_addr"
    fi
    
    # TXTレコードの詳細検索
    print_info "\n■ TXTレコード検索"
    get_txt_records_verbose
    
    # TXTレコード取得（解析用）
    local txt_record=$(get_txt_record)
    if [ $? -eq 0 ] && [ -n "$txt_record" ]; then
        analyze_txt_record "$txt_record"
        
        # URL抽出
        local url=$(extract_url "$txt_record")
        if [ -n "$url" ]; then
            print_info "\n■ プロビジョニングサーバーURL"
            print_info "URL: $url"
            print_info "このURLにアクセスしてMAP-E設定情報を取得できます"
        fi
    else
        print_info "\n■ プロビジョニングの代替手段"
        print_info "標準プロビジョニングのTXTレコードが見つかりませんでした。"
        print_info "お使いのISPは標準以外の方法でMAP-E設定を提供している可能性があります。"
        
        if echo "$ipv6_addr" | grep -q "^2400:41"; then
            print_info "\nNTT東日本の場合は、以下を試してください："
            print_info "* フレッツ・v6オプション契約の確認"
            print_info "* NGNインターフェース（MAP-E）の設定"
        elif echo "$ipv6_addr" | grep -q "^2400:85"; then
            print_info "\nNTT西日本の場合は、以下を試してください："
            print_info "* フレッツ・v6オプション契約の確認"
            print_info "* NGNインターフェース（MAP-E）の設定"
        elif echo "$ipv6_addr" | grep -q "^2001:260"; then
            print_info "\nOCNの場合は、以下を試してください："
            print_info "* OCN専用のMAP-E APIを使用"
        fi
    fi
    
    print_info "\n処理が完了しました"
    return 0
}

# スクリプト実行
main "$@"
