#!/bin/sh
#===============================================================================
# IPv6マイグレーション標準プロビジョニング TXTレコード取得スクリプト
#
# このスクリプトは、IPv6マイグレーション標準プロビジョニング仕様に従い
# DNS TXTレコードを取得し、その内容を解析してISP情報を表示します。
#
# OpenWrt/ASHシェル対応 POSIX準拠スクリプト
#===============================================================================

# 設定変数
VERSION="2025.04.04-1"
WAN_IFACE="wan"                      # WANインターフェース名
TEMP_DIR="/tmp"                      # 一時ファイル用ディレクトリ
CACHE_DIR="/tmp/v6mig_cache"         # キャッシュディレクトリ

# プロビジョニングドメイン（優先度順）
PROV_DOMAINS="4over6.info v6mig.transix.jp jpne.co eonet.ne.jp ipv6-literal.net"
# 代替DNSサーバーリスト（優先度順）
DNS_SERVERS="8.8.8.8 1.1.1.1 9.9.9.9 208.67.222.222"

# エラー出力関数
print_error() {
    echo "エラー: $1" >&2
}

# 情報出力関数
print_info() {
    echo "$1"
}

# キャッシュディレクトリ作成
create_cache_dir() {
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR"
        debug_log "Cache directory created"
    fi
}

# ネットワークライブラリ読み込み
load_network_libs() {
    if [ -f "/lib/functions/network.sh" ]; then
        . /lib/functions/network.sh
        . /lib/functions.sh
        network_flush_cache
        debug_log "Network libraries loaded"
        return 0
    else
        debug_log "Network libraries not found"
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
        print_error "必要なコマンドが見つかりません:$missing"
        print_error "必要なパッケージをインストールしてください"
        return 1
    fi
    
    debug_log "Required commands available"
    return 0
}

# IPv6アドレス取得
get_ipv6_address() {
    local local_ipv6=""
    local net_if6=""
    
    debug_log "Retrieving IPv6 address"
    
    # OpenWrtのネットワーク関数使用
    if load_network_libs; then
        network_find_wan6 net_if6
        network_get_ipaddr6 local_ipv6 "${net_if6}"
        
        if [ -n "$local_ipv6" ]; then
            debug_log "Using OpenWrt network functions"
            echo "$local_ipv6"
            return 0
        fi
    fi
    
    # 一般的な方法でIPv6取得
    local_ipv6=$(ip -6 addr show dev "$WAN_IFACE" scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)
    
    if [ -n "$local_ipv6" ]; then
        debug_log "Using ip command"
        echo "$local_ipv6"
        return 0
    fi
    
    print_error "グローバルIPv6アドレスを取得できませんでした"
    return 1
}

# TXTレコード取得処理（詳細表示版）
get_txt_records_verbose() {
    local domain=""
    local dns=""
    local tmp_file="$TEMP_DIR/txt_records_$$.txt"
    local found_records=0
    
    print_info "プロビジョニングTXTレコードの検索中..."
    print_info "---------------------------------------"
    
    # 各ドメインとDNSサーバーの組み合わせを試行
    for domain in $PROV_DOMAINS; do
        print_info "ドメイン $domain を確認中:"
        
        # システムのDNSで試行
        print_info "  システムDNSを使用..."
        dig +short TXT "$domain" > "$tmp_file" 2>/dev/null
        
        if [ -s "$tmp_file" ]; then
            print_info "  レコード発見! (システムDNS)"
            print_info "  内容: $(cat "$tmp_file" | sed -e 's/^"//' -e 's/"$//')"
            found_records=$((found_records + 1))
        else
            print_info "  システムDNSで見つかりませんでした"
            
            # 代替DNSサーバーで試行
            for dns in $DNS_SERVERS; do
                print_info "  代替DNS $dns を使用..."
                dig +short TXT "$domain" @"$dns" > "$tmp_file" 2>/dev/null
                
                if [ -s "$tmp_file" ]; then
                    print_info "  レコード発見! (DNS: $dns)"
                    print_info "  内容: $(cat "$tmp_file" | sed -e 's/^"//' -e 's/"$//')"
                    found_records=$((found_records + 1))
                    break
                else
                    print_info "  代替DNS $dns でも見つかりませんでした"
                fi
            done
        fi
        print_info "---------------------------------------"
    done
    
    # 見つかったレコードの総数を表示
    if [ $found_records -gt 0 ]; then
        print_info "合計 $found_records 件のTXTレコードが見つかりました"
    else
        print_info "TXTレコードは見つかりませんでした"
    fi
    
    # 一時ファイル削除
    rm -f "$tmp_file" 2>/dev/null
    
    return 0
}

# TXTレコード取得処理（単一レコード取得）
get_txt_record() {
    local domain=""
    local dns=""
    local txt_record=""
    
    debug_log "Attempting to retrieve TXT records"
    
    # 各ドメインとDNSサーバーの組み合わせを試行
    for domain in $PROV_DOMAINS; do
        # システムのDNSで試行
        debug_log "Trying system DNS for domain: $domain"
        txt_record=$(dig +short TXT "$domain" 2>/dev/null | head -1 | sed -e 's/^"//' -e 's/"$//')
        
        if [ -n "$txt_record" ]; then
            debug_log "Found TXT record using system DNS"
            echo "$txt_record"
            return 0
        fi
        
        # 代替DNSサーバーで試行
        for dns in $DNS_SERVERS; do
            debug_log "Trying DNS $dns for domain: $domain"
            txt_record=$(dig +short TXT "$domain" @"$dns" 2>/dev/null | head -1 | sed -e 's/^"//' -e 's/"$//')
            
            if [ -n "$txt_record" ]; then
                debug_log "Found TXT record using DNS $dns"
                echo "$txt_record"
                return 0
            fi
        done
    done
    
    debug_log "No TXT records found"
    return 1
}

# TXTレコードからURL抽出
extract_url() {
    local txt_record="$1"
    local url=""
    
    debug_log "Parsing TXT record: $txt_record"
    
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
    print_info "レコード: $txt_record"
    
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
        print_info "バージョン: 不明"
    fi
    
    # URL情報
    local url=$(extract_url "$txt_record")
    if [ -n "$url" ]; then
        print_info "プロビジョニングURL: $url"
    else
        print_info "プロビジョニングURL: 情報なし"
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
        print_info "プロトコルタイプ: 情報なし"
    fi
    
    # 追加情報
    local other_info=$(echo "$txt_record" | awk '{
        for (i=1; i<=NF; i++) {
            if ($i !~ /^(v=|url=|t=)/) {
                print $i;
            }
        }
    }')
    
    if [ -n "$other_info" ]; then
        print_info "その他の情報: $other_info"
    fi
    
    return 0
}

# ISP推定関数
guess_isp() {
    local ipv6_addr="$1"
    local txt_record="$2"
    
    # IPv6アドレスプレフィックスからの推定
    local prefix=""
    if [ -n "$ipv6_addr" ]; then
        prefix=$(echo "$ipv6_addr" | cut -d: -f1-2)
        
        case "$prefix" in
            2400:*)
                case "$(echo "$ipv6_addr" | cut -d: -f1-3)" in
                    2400:4150:*|2400:4151:*|2400:4152:*)
                        print_info "IPv6プレフィックスからの推定ISP: NTT東日本 (フレッツ光系)"
                        ;;
                    2400:8500:*|2400:8501:*|2400:8502:*)
                        print_info "IPv6プレフィックスからの推定ISP: NTT西日本 (フレッツ光系)"
                        ;;
                    2400:9800:*|2400:9801:*)
                        print_info "IPv6プレフィックスからの推定ISP: KDDI (au ひかり)"
                        ;;
                    *)
                        print_info "IPv6プレフィックスからの推定ISP: 不明 ($prefix)"
                        ;;
                esac
                ;;
            2001:*)
                case "$(echo "$ipv6_addr" | cut -d: -f1-3)" in
                    2001:358:*)
                        print_info "IPv6プレフィックスからの推定ISP: JPNE"
                        ;;
                    2001:260:*)
                        print_info "IPv6プレフィックスからの推定ISP: OCN"
                        ;;
                    *)
                        print_info "IPv6プレフィックスからの推定ISP: 不明 ($prefix)"
                        ;;
                esac
                ;;
            *)
                print_info "IPv6プレフィックスからの推定ISP: 不明 ($prefix)"
                ;;
        esac
    fi
    
    # TXTレコードのURLからの推定
    if [ -n "$txt_record" ]; then
        local url=$(extract_url "$txt_record")
        if [ -n "$url" ]; then
            case "$url" in
                *ocn*|*ntt*) 
                    print_info "プロビジョニングURLからの推定ISP: OCN/NTT"
                    ;;
                *jpne*)
                    print_info "プロビジョニングURLからの推定ISP: JPNE"
                    ;;
                *kddi*|*au*)
                    print_info "プロビジョニングURLからの推定ISP: KDDI"
                    ;;
                *eonet*)
                    print_info "プロビジョニングURLからの推定ISP: eo光"
                    ;;
                *so-net*)
                    print_info "プロビジョニングURLからの推定ISP: So-net"
                    ;;
                *)
                    print_info "プロビジョニングURLからの推定ISP: 不明 (URL: $url)"
                    ;;
            esac
        fi
    fi
    
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
    ipv6_addr=$(get_ipv6_address)
    if [ $? -ne 0 ]; then
        print_error "IPv6アドレスの取得に失敗しました"
    else
        print_info "IPv6アドレス: $ipv6_addr"
    fi
    
    # TXTレコードの詳細検索
    get_txt_records_verbose
    
    # TXTレコード取得（解析用）
    print_info "\n■ プロビジョニングTXTレコードの解析"
    txt_record=$(get_txt_record)
    if [ $? -eq 0 ] && [ -n "$txt_record" ]; then
        analyze_txt_record "$txt_record"
    else
        print_info "解析可能なTXTレコードは見つかりませんでした"
    fi
    
    # ISP推定
    print_info "\n■ ISP推定結果"
    guess_isp "$ipv6_addr" "$txt_record"
    
    # 結果まとめ
    print_info "\n■ まとめ"
    if [ -n "$txt_record" ]; then
        print_info "IPv6マイグレーション標準プロビジョニング対応のISPである可能性があります"
    else
        print_info "標準プロビジョニングのTXTレコードは見つかりませんでした"
        print_info "お使いのISPは独自の方法でMAP-Eを設定している可能性があります"
    fi
    
    print_info "\n処理が完了しました"
    return 0
}

# スクリプト実行
main "$@"
