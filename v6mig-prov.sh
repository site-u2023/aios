#!/bin/sh
#===============================================================================
# IPv6マイグレーション標準プロビジョニング設定取得スクリプト
#
# このスクリプトは、IPv6マイグレーション標準プロビジョニング仕様に従い
# DNS TXTレコードからプロビジョニングサーバのURLを取得し、
# MAP-E設定パラメータを自動的に取得します。
#
# OpenWrt/ASHシェル対応 POSIX準拠スクリプト
#===============================================================================

# 設定変数
VERSION="2025.04.03-3"
WAN_IFACE="wan"                      # WANインターフェース名
VENDORID="acde48-v6pc_swg_hgw"       # ベンダーID
PRODUCT="V6MIG-ROUTER"               # 製品名
PRODUCT_VERSION="1_0"                # バージョン
DEBUG=1                              # デバッグ出力（1=有効, 0=無効）
SIMULATION_MODE=1                    # シミュレーションモード（1=設定変更なし, 0=設定適用）
TEMP_DIR="/tmp"                      # 一時ファイル用ディレクトリ
CACHE_DIR="/tmp/v6mig_cache"         # キャッシュディレクトリ
DNS_SERVERS="8.8.8.8 1.1.1.1 9.9.9.9" # 代替DNSサーバーリスト
PROV_DOMAINS="4over6.info v6mig.transix.jp" # プロビジョニングドメイン

# デバッグログ関数
debug_log() {
    [ "$DEBUG" = "1" ] && echo "INFO: $1" >&2
}

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
    local required_commands="ip curl dig"
    
    for cmd in $required_commands; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    
    # jqはあれば便利だが必須ではない
    if ! command -v jq > /dev/null 2>&1; then
        debug_log "jq command not found, will use simple text processing instead"
    fi
    
    if [ -n "$missing" ]; then
        print_error "以下のコマンドが見つかりません:$missing"
        print_error "これらのパッケージをインストールしてください"
        return 1
    fi
    
    debug_log "All required commands are available"
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
            debug_log "Retrieved IPv6 using OpenWrt network functions: $local_ipv6"
            echo "$local_ipv6"
            return 0
        fi
    fi
    
    # 一般的な方法でIPv6取得
    local_ipv6=$(ip -6 addr show dev "$WAN_IFACE" scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)
    
    if [ -n "$local_ipv6" ]; then
        debug_log "Retrieved IPv6 using ip command: $local_ipv6"
        echo "$local_ipv6"
        return 0
    fi
    
    print_error "グローバルIPv6アドレスを取得できませんでした"
    return 1
}

# TXTレコード取得処理
get_txt_record() {
    local domain=""
    local dns=""
    local txt_record=""
    
    debug_log "Attempting to retrieve provisioning TXT record"
    
    # 各ドメインとDNSサーバーの組み合わせを試行
    for domain in $PROV_DOMAINS; do
        # システムのDNSで試行
        debug_log "Trying system DNS for domain: $domain"
        txt_record=$(dig +short TXT "$domain" 2>/dev/null | sed -e 's/^"//' -e 's/"$//')
        
        if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
            debug_log "Valid TXT record found using system DNS: $txt_record"
            echo "$txt_record"
            return 0
        fi
        
        # 代替DNSサーバーで試行
        for dns in $DNS_SERVERS; do
            debug_log "Trying DNS server $dns for domain: $domain"
            txt_record=$(dig +short TXT "$domain" @"$dns" 2>/dev/null | sed -e 's/^"//' -e 's/"$//')
            
            if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
                debug_log "Valid TXT record found using DNS $dns: $txt_record"
                echo "$txt_record"
                return 0
            fi
        done
    done
    
    debug_log "No valid TXT record found from any source"
    return 1
}

# TXTレコードからURL抽出
extract_url() {
    local txt_record="$1"
    local url=""
    
    debug_log "Extracting URL from TXT record: $txt_record"
    
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
        debug_log "Extracted URL: $url"
        echo "$url"
        return 0
    fi
    
    debug_log "Failed to extract URL from TXT record"
    return 1
}

# プロビジョニングサーバーへのリクエスト
get_provisioning_data() {
    local url="$1"
    local ipv6_addr="$2"
    local response_file="$TEMP_DIR/v6mig_resp_$$.json"
    local retry=0
    local max_retries=3
    
    debug_log "Requesting data from provisioning server: $url"
    
    while [ $retry -lt $max_retries ]; do
        # リクエストパラメータ構築
        local params="vendorid=$VENDORID&product=$PRODUCT&version=$PRODUCT_VERSION&capability=map_e"
        if [ -n "$ipv6_addr" ]; then
            params="$params&ipv6addr=$ipv6_addr"
        fi
        
        debug_log "Request URL: $url/config?$params (attempt: $((retry+1))/$max_retries)"
        
        # リクエスト送信
        curl -s -m 10 -A "V6MigClient/$VERSION" "$url/config?$params" -o "$response_file" 2>/dev/null
        
        if [ -f "$response_file" ] && [ -s "$response_file" ]; then
            # レスポンスがJSONか確認
            if command -v jq > /dev/null 2>&1 && jq . "$response_file" >/dev/null 2>&1; then
                debug_log "Received valid JSON response"
                cat "$response_file"
                rm -f "$response_file" 2>/dev/null
                return 0
            elif grep -q '{"map_e":' "$response_file"; then
                debug_log "Response appears to be JSON (without using jq)"
                cat "$response_file"
                rm -f "$response_file" 2>/dev/null
                return 0
            else
                debug_log "Response is not valid JSON, retrying..."
            fi
        else
            debug_log "Empty or no response received, retrying..."
        fi
        
        retry=$((retry + 1))
        sleep 2
    done
    
    rm -f "$response_file" 2>/dev/null
    debug_log "Failed to get valid response from provisioning server"
    return 1
}

# プロビジョニング応答からMAP-Eパラメータを抽出
extract_mape_params() {
    local response="$1"
    local params_file="$CACHE_DIR/mape_params.cache"
    
    debug_log "Extracting MAP-E parameters from response"
    
    # 一時ファイル作成
    local tmp_file="$TEMP_DIR/mape_json_$$.tmp"
    echo "$response" > "$tmp_file"
    
    # JSON解析（jqがあれば使用）
    if command -v jq > /dev/null 2>&1; then
        local br=$(jq -r '.map_e.br' "$tmp_file")
        local rule_ipv6=$(jq -r '.map_e.rules[0].ipv6' "$tmp_file")
        local rule_ipv4=$(jq -r '.map_e.rules[0].ipv4' "$tmp_file")
        local ea_length=$(jq -r '.map_e.rules[0].ea_length' "$tmp_file")
        local psid_offset=$(jq -r '.map_e.rules[0].psid_offset' "$tmp_file")
        local psid_len=$(jq -r '.map_e.rules[0].psid_len // 0' "$tmp_file")
    else
        # jqがない場合は基本的なテキスト処理
        local br=$(grep -o '"br":"[^"]*"' "$tmp_file" | cut -d'"' -f4)
        local rule_ipv6=$(grep -o '"ipv6":"[^"]*"' "$tmp_file" | cut -d'"' -f4)
        local rule_ipv4=$(grep -o '"ipv4":"[^"]*"' "$tmp_file" | cut -d'"' -f4)
        local ea_length=$(grep -o '"ea_length":[0-9]*' "$tmp_file" | cut -d':' -f2)
        local psid_offset=$(grep -o '"psid_offset":[0-9]*' "$tmp_file" | cut -d':' -f2)
        local psid_len=$(grep -o '"psid_len":[0-9]*' "$tmp_file" | cut -d':' -f2)
        
        # PSID長が見つからない場合のデフォルト
        if [ -z "$psid_len" ]; then
            psid_len="0"
        fi
    fi
    
    rm -f "$tmp_file" 2>/dev/null
    
    # パラメータ検証
    if [ -z "$br" ] || [ -z "$rule_ipv6" ] || [ -z "$rule_ipv4" ] || [ -z "$ea_length" ] || [ -z "$psid_offset" ]; then
        debug_log "Missing required MAP-E parameters"
        print_error "必要なMAP-Eパラメータが欠けています"
        return 1
    fi
    
    # 結果表示
    print_info "■ MAP-E設定パラメータ"
    print_info "  BRアドレス: $br"
    print_info "  IPv6プレフィックス: $rule_ipv6"
    print_info "  IPv4プレフィックス: $rule_ipv4"
    print_info "  EAビット長: $ea_length"
    print_info "  PSIDオフセット: $psid_offset"
    print_info "  PSID長: $psid_len"
    
    # パラメータをキャッシュに保存
    mkdir -p "$CACHE_DIR"
    {
        echo "$br"
        echo "$rule_ipv6"
        echo "$rule_ipv4"
        echo "$ea_length"
        echo "$psid_offset"
        echo "$psid_len"
    } > "$params_file"
    
    debug_log "MAP-E parameters saved to cache"
    return 0
}

# シミュレーションモードでMAP-E設定を表示
show_mape_config() {
    local params_file="$CACHE_DIR/mape_params.cache"
    
    if [ ! -f "$params_file" ]; then
        print_error "MAP-Eパラメータが見つかりません"
        return 1
    fi
    
    # パラメータの読み込み
    local br=$(sed -n '1p' "$params_file")
    local rule_ipv6=$(sed -n '2p' "$params_file")
    local rule_ipv4=$(sed -n '3p' "$params_file")
    local ea_length=$(sed -n '4p' "$params_file")
    local psid_offset=$(sed -n '5p' "$params_file")
    local psid_len=$(sed -n '6p' "$params_file")
    
    # IPv4 CIDRからプレフィックス長を抽出
    local ipv4_prefix_len=$(echo "$rule_ipv4" | cut -d/ -f2)
    local ipv6_prefix_len=$(echo "$rule_ipv6" | cut -d/ -f2)
    
    print_info ""
    print_info "■ MAP-E設定コマンド（シミュレーション）"
    print_info "  以下のコマンドを実行するとMAP-E設定が適用されます："
    print_info ""
    print_info "  # WAN 無効化"
    print_info "  uci set network.wan.auto='0'"
    print_info ""
    print_info "  # MAP-E インターフェース設定"
    print_info "  uci set network.mape=interface"
    print_info "  uci set network.mape.proto='map'"
    print_info "  uci set network.mape.maptype='map-e'"
    print_info "  uci set network.mape.peeraddr='$br'"
    print_info "  uci set network.mape.ipaddr='${rule_ipv4%/*}'"
    print_info "  uci set network.mape.ip4prefixlen='$ipv4_prefix_len'"
    print_info "  uci set network.mape.ip6prefix='${rule_ipv6%/*}'"
    print_info "  uci set network.mape.ip6prefixlen='$ipv6_prefix_len'"
    print_info "  uci set network.mape.ealen='$ea_length'"
    print_info "  uci set network.mape.psidlen='$psid_len'"
    print_info "  uci set network.mape.offset='$psid_offset'"
    print_info "  uci set network.mape.tunlink='wan6'"
    print_info "  uci set network.mape.mtu='1460'"
    print_info "  uci set network.mape.encaplimit='ignore'"
    print_info ""
    print_info "  # ファイアウォール設定"
    print_info "  uci del_list firewall.@zone[1].network='wan'"
    print_info "  uci add_list firewall.@zone[1].network='mape'"
    print_info ""
    print_info "  # 設定の適用"
    print_info "  uci commit"
    print_info "  /etc/init.d/network restart"
    
    return 0
}

# 実際にMAP-E設定を適用する関数
apply_mape_config() {
    local params_file="$CACHE_DIR/mape_params.cache"
    
    if [ ! -f "$params_file" ]; then
        print_error "MAP-Eパラメータが見つかりません"
        return 1
    fi
    
    # パラメータの読み込み
    local br=$(sed -n '1p' "$params_file")
    local rule_ipv6=$(sed -n '2p' "$params_file")
    local rule_ipv4=$(sed -n '3p' "$params_file")
    local ea_length=$(sed -n '4p' "$params_file")
    local psid_offset=$(sed -n '5p' "$params_file")
    local psid_len=$(sed -n '6p' "$params_file")
    
    # IPv4 CIDRからプレフィックス長を抽出
    local ipv4_prefix_len=$(echo "$rule_ipv4" | cut -d/ -f2)
    local ipv6_prefix_len=$(echo "$rule_ipv6" | cut -d/ -f2)
    
    print_info "MAP-E設定を適用しています..."
    
    # 設定のバックアップ作成
    cp /etc/config/network /etc/config/network.mape.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.mape.bak 2>/dev/null
    
    # UCI設定コマンド
    if ! command -v uci > /dev/null 2>&1; then
        print_error "UCI コマンドが見つかりません。設定を適用できません。"
        return 1
    fi
    
    # WAN無効化
    uci set network.wan.auto='0'
    
    # MAP-E設定
    uci set network.mape=interface
    uci set network.mape.proto='map'
    uci set network.mape.maptype='map-e'
    uci set network.mape.peeraddr="$br"
    uci set network.mape.ipaddr="${rule_ipv4%/*}"
    uci set network.mape.ip4prefixlen="$ipv4_prefix_len"
    uci set network.mape.ip6prefix="${rule_ipv6%/*}"
    uci set network.mape.ip6prefixlen="$ipv6_prefix_len"
    uci set network.mape.ealen="$ea_length"
    uci set network.mape.psidlen="$psid_len"
    uci set network.mape.offset="$psid_offset"
    uci set network.mape.tunlink='wan6'
    uci set network.mape.mtu='1460'
    uci set network.mape.encaplimit='ignore'
    
    # OpenWrtバージョン固有の設定
    if [ -f "/etc/openwrt_release" ]; then
        local openwrt_version=$(grep -E "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2 | cut -c 1-2)
        debug_log "OpenWrt version detected: $openwrt_version"
        
        case "$openwrt_version" in
            "24"|"23"|"22"|"21"|"SN")
                debug_log "Setting modern OpenWrt specific options"
                uci set network.mape.legacymap='1'
                ;;
            "19")
                debug_log "Setting OpenWrt 19 specific options"
                # OpenWrt 19には特に追加設定なし
                ;;
        esac
    fi
    
    # ファイアウォール設定
    local wan_zone=1  # 通常、WAN/WANゾーンは1だが、念のためチェック
    local zone_count=$(uci show firewall | grep -c "firewall.@zone\[")
    
    for i in $(seq 0 $((zone_count - 1))); do
        local zone_name=$(uci get firewall.@zone[$i].name 2>/dev/null)
        if [ "$zone_name" = "wan" ]; then
            wan_zone=$i
            break
        fi
    done
    
    uci del_list firewall.@zone["$wan_zone"].network='wan'
    uci add_list firewall.@zone["$wan_zone"].network='mape'
    
    # DHCP設定の調整
    if [ -f "/etc/config/dhcp" ]; then
        # DHCPの設定があれば調整
        uci set dhcp.lan.ra='relay'
        uci set dhcp.lan.dhcpv6='relay'
        uci set dhcp.lan.ndp='relay'
    fi
    
    # 設定の適用
    uci commit network
    uci commit firewall
    uci commit dhcp
    
    print_info "MAP-E設定が適用されました。ネットワークを再起動しています..."
    
    # ネットワーク再起動
    if [ -f "/etc/init.d/network" ]; then
        /etc/init.d/network restart
    else
        print_error "ネットワーク再起動スクリプトが見つかりません"
        return 1
    fi
    
    print_info "MAP-E設定の適用が完了しました"
    return 0
}

# メイン処理
main() {
    local ipv6_addr=""
    local txt_record=""
    local prov_url=""
    local prov_response=""
    local success=0
    
    print_info "=== IPv6マイグレーションプロビジョニング設定取得 v$VERSION ==="
    
    # 初期化と必須コマンド確認
    create_cache_dir
    check_commands || exit 1
    
    # IPv6アドレスの取得
    print_info "IPv6アドレスを取得中..."
    ipv6_addr=$(get_ipv6_address)
    if [ $? -ne 0 ]; then
        print_error "IPv6アドレスの取得に失敗しました"
        exit 1
    fi
    print_info "IPv6アドレス: $ipv6_addr"
    
    # TXTレコードの取得
    print_info "プロビジョニングサーバ情報を探索中..."
    txt_record=$(get_txt_record)
    if [ $? -eq 0 ]; then
        print_info "TXTレコード: $txt_record"
        
        # URLの抽出
        prov_url=$(extract_url "$txt_record")
        if [ $? -eq 0 ]; then
            print_info "プロビジョニングサーバURL: $prov_url"
            
            # プロビジョニングサーバからデータ取得
            print_info "設定情報を取得中..."
            prov_response=$(get_provisioning_data "$prov_url" "$ipv6_addr")
            if [ $? -eq 0 ]; then
                print_info "設定情報の取得に成功しました"
                
                # MAP-Eパラメータの抽出
                extract_mape_params "$prov_response"
                if [ $? -eq 0 ]; then
                    success=1
                fi
            else
                print_error "プロビジョニングサーバからの情報取得に失敗しました"
            fi
        else
            print_error "TXTレコードからURLを抽出できませんでした"
        fi
    else
        print_error "プロビジョニングTXTレコードが見つかりませんでした"
        print_info "お使いのISPがIPv6マイグレーション標準プロビジョニングに対応していない可能性があります"
    fi
    
    # 設定の表示または適用
    if [ $success -eq 1 ]; then
        if [ "$SIMULATION_MODE" = "1" ]; then
            show_mape_config
            print_info ""
            print_info "このスクリプトは設定のシミュレーションのみ行いました。"
            print_info "実際に設定を適用するには、以下のコマンドを実行してください："
            print_info ""
            print_info "  SIMULATION_MODE=0 $0"
        else
            apply_mape_config
        fi
    else
        print_info ""
        print_info "MAP-E設定情報の取得に失敗しました。以下をご確認ください："
        print_info "  1. IPv6接続が正常に機能していること"
        print_info "  2. お使いのISPがIPv6マイグレーション標準プロビジョニングに対応していること"
        print_info "  3. DNSサーバーが正常に機能していること"
    fi
    
    return 0
}

# スクリプト実行
main "$@"
