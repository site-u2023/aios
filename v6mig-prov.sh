#!/bin/sh
#===============================================================================
# IPv6マイグレーション標準プロビジョニング対応スクリプト
#
# 機能: DNS TXTレコードからプロビジョニングサーバのURL情報を取得し、
#       MAP-E設定パラメータを自動的に構成します
#
# POSIX準拠 OpenWrt対応
#===============================================================================

# 設定変数
VERSION="2025.04.04-2"
WAN_IFACE="wan"                      # WANインターフェース名
TEMP_DIR="/tmp"                      # 一時ファイル用ディレクトリ
CACHE_DIR="/tmp/v6mig_cache"         # キャッシュディレクトリ
DIG_TIMEOUT=3                        # dig コマンドのタイムアウト（秒）
MAX_RETRIES=2                        # リトライ回数
SIMULATION_MODE=1                    # 1=設定表示のみ、0=設定を実際に適用
PROV_DOMAINS="4over6.info v6mig.transix.jp jpne.co ipv4v6.flets-east.jp ipv4v6.flets-west.jp"
DNS_SERVERS="8.8.8.8 1.1.1.1 9.9.9.9 208.67.222.222"

# キャッシュディレクトリ作成
create_cache_dir() {
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR"
        debug_log "Created cache directory at $CACHE_DIR"
    fi
}

# 必要コマンド確認
check_commands() {
    local missing=""
    
    for cmd in ip dig curl; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    
    if [ -n "$missing" ]; then
        echo "エラー: 以下のコマンドが見つかりません:$missing"
        echo "これらのパッケージをインストールしてください。"
        return 1
    fi
    
    # jqはあると便利だが、必須ではない
    if ! command -v jq > /dev/null 2>&1; then
        debug_log "jq command not found, will use basic text processing"
    fi
    
    return 0
}

# ネットワークライブラリ読み込み
load_network_libs() {
    if [ -f "/lib/functions/network.sh" ]; then
        . /lib/functions/network.sh
        . /lib/functions.sh
        network_flush_cache
        debug_log "OpenWrt network libraries loaded"
        return 0
    fi
    
    debug_log "OpenWrt network libraries not found"
    return 1
}

# IPv6アドレス取得
get_ipv6_address() {
    local local_ipv6=""
    local net_if6=""
    
    debug_log "Retrieving IPv6 address from interface $WAN_IFACE"
    
    # OpenWrtのネットワーク関数を使用
    if load_network_libs; then
        network_find_wan6 net_if6
        network_get_ipaddr6 local_ipv6 "${net_if6}"
        
        if [ -n "$local_ipv6" ]; then
            debug_log "IPv6 address retrieved via network functions: $local_ipv6"
            echo "$local_ipv6"
            return 0
        fi
    fi
    
    # 代替方法でIPv6取得
    local_ipv6=$(ip -6 addr show dev "$WAN_IFACE" scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)
    
    if [ -n "$local_ipv6" ]; then
        debug_log "IPv6 address retrieved via ip command: $local_ipv6"
        echo "$local_ipv6"
        return 0
    fi
    
    echo "エラー: IPv6アドレスを取得できませんでした"
    return 1
}

# TXTレコード取得（複数のDNSサーバーとドメインを試行）
get_txt_record() {
    local domain=""
    local dns=""
    local txt_record=""
    local tmp_file="$TEMP_DIR/txt_record_$$.tmp"
    
    debug_log "Searching for provisioning TXT record"
    
    for domain in $PROV_DOMAINS; do
        debug_log "Trying domain: $domain"
        
        # システムDNSで試行
        dig +short +timeout=$DIG_TIMEOUT +tries=$MAX_RETRIES TXT "$domain" > "$tmp_file" 2>/dev/null
        
        if [ -s "$tmp_file" ]; then
            txt_record=$(head -1 "$tmp_file" | sed -e 's/^"//' -e 's/"$//')
            
            if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
                debug_log "Valid TXT record found using system DNS: $txt_record"
                rm -f "$tmp_file" 2>/dev/null
                echo "$txt_record"
                return 0
            fi
            
            debug_log "TXT record found but missing url parameter: $txt_record"
        fi
        
        # 代替DNSサーバーを試行
        for dns in $DNS_SERVERS; do
            debug_log "Trying DNS server $dns for domain $domain"
            
            dig +short +timeout=$DIG_TIMEOUT +tries=$MAX_RETRIES TXT "$domain" @"$dns" > "$tmp_file" 2>/dev/null
            
            if [ -s "$tmp_file" ]; then
                txt_record=$(head -1 "$tmp_file" | sed -e 's/^"//' -e 's/"$//')
                
                if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
                    debug_log "Valid TXT record found using DNS $dns: $txt_record"
                    rm -f "$tmp_file" 2>/dev/null
                    echo "$txt_record"
                    return 0
                fi
                
                debug_log "TXT record found but missing url parameter: $txt_record"
            fi
        done
    done
    
    rm -f "$tmp_file" 2>/dev/null
    debug_log "No valid TXT records found"
    return 1
}

# TXTレコードからURLを抽出
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
        debug_log "URL extracted: $url"
        echo "$url"
        return 0
    fi
    
    debug_log "Failed to extract URL from TXT record"
    return 1
}

# プロビジョニングサーバーからMAP-E設定データを取得
get_provisioning_data() {
    local url="$1"
    local ipv6_addr="$2"
    local vendorid="acde48-v6pc_swg_hgw"  # ベンダーID
    local product="V6MIG-ROUTER"          # 製品名
    local version="1_0"                    # 製品バージョン
    local response_file="$TEMP_DIR/prov_response_$$.json"
    local retry=0
    local max_retries=3
    
    debug_log "Requesting data from provisioning server: $url"
    
    # リクエストパラメータの構築
    local params="vendorid=$vendorid&product=$product&version=$version&capability=map_e"
    if [ -n "$ipv6_addr" ]; then
        params="$params&ipv6addr=$ipv6_addr"
    fi
    
    while [ $retry -lt $max_retries ]; do
        echo "プロビジョニングサーバーに接続しています (試行 $((retry+1))/$max_retries)..."
        debug_log "Request URL: $url/config?$params"
        
        curl -s -m 10 -A "V6MigClient/$VERSION" "$url/config?$params" -o "$response_file" 2>/dev/null
        
        if [ -f "$response_file" ] && [ -s "$response_file" ]; then
            # JSONレスポンス検証
            if command -v jq > /dev/null 2>&1 && jq . "$response_file" >/dev/null 2>&1; then
                debug_log "Received valid JSON response"
                cat "$response_file"
                rm -f "$response_file" 2>/dev/null
                return 0
            elif grep -q '{"map_e":' "$response_file"; then
                debug_log "Response appears to contain map_e data"
                cat "$response_file"
                rm -f "$response_file" 2>/dev/null
                return 0
            fi
            
            debug_log "Response is not valid map_e JSON, retrying..."
        else
            debug_log "Empty or no response received, retrying..."
        fi
        
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            sleep 2
        fi
    done
    
    rm -f "$response_file" 2>/dev/null
    echo "エラー: プロビジョニングサーバーからの応答を取得できませんでした"
    return 1
}

# JSON応答からMAP-Eパラメータを抽出
extract_mape_params() {
    local json_response="$1"
    local params_file="$CACHE_DIR/mape_params.cache"
    
    debug_log "Extracting MAP-E parameters from response"
    
    # 一時ファイル作成
    local tmp_file="$TEMP_DIR/mape_json_$$.tmp"
    echo "$json_response" > "$tmp_file"
    
    # JSONパラメータ抽出
    local br=""
    local rule_ipv6=""
    local rule_ipv4=""
    local ea_length=""
    local psid_offset=""
    local psid_len=""
    
    if command -v jq > /dev/null 2>&1; then
        # jq使用
        br=$(jq -r '.map_e.br' "$tmp_file" 2>/dev/null)
        rule_ipv6=$(jq -r '.map_e.rules[0].ipv6' "$tmp_file" 2>/dev/null)
        rule_ipv4=$(jq -r '.map_e.rules[0].ipv4' "$tmp_file" 2>/dev/null)
        ea_length=$(jq -r '.map_e.rules[0].ea_length' "$tmp_file" 2>/dev/null)
        psid_offset=$(jq -r '.map_e.rules[0].psid_offset' "$tmp_file" 2>/dev/null)
        psid_len=$(jq -r '.map_e.rules[0].psid_len // 0' "$tmp_file" 2>/dev/null)
    else
        # grep/sed/awk使用
        br=$(grep -o '"br":"[^"]*"' "$tmp_file" | sed 's/"br":"//;s/"$//')
        rule_ipv6=$(grep -o '"ipv6":"[^"]*"' "$tmp_file" | sed 's/"ipv6":"//;s/"$//')
        rule_ipv4=$(grep -o '"ipv4":"[^"]*"' "$tmp_file" | sed 's/"ipv4":"//;s/"$//')
        ea_length=$(grep -o '"ea_length":[0-9]*' "$tmp_file" | sed 's/"ea_length"://')
        psid_offset=$(grep -o '"psid_offset":[0-9]*' "$tmp_file" | sed 's/"psid_offset"://')
        psid_len=$(grep -o '"psid_len":[0-9]*' "$tmp_file" | sed 's/"psid_len"://')
        
        # psid_lenが見つからない場合のデフォルト値
        if [ -z "$psid_len" ]; then
            psid_len="0"
        fi
    fi
    
    rm -f "$tmp_file" 2>/dev/null
    
    # 必須パラメータの検証
    if [ -z "$br" ] || [ "$br" = "null" ] || \
       [ -z "$rule_ipv6" ] || [ "$rule_ipv6" = "null" ] || \
       [ -z "$rule_ipv4" ] || [ "$rule_ipv4" = "null" ] || \
       [ -z "$ea_length" ] || [ "$ea_length" = "null" ] || \
       [ -z "$psid_offset" ] || [ "$psid_offset" = "null" ]; then
        debug_log "Missing required MAP-E parameters"
        echo "エラー: 必要なMAP-Eパラメータが欠けています"
        return 1
    fi
    
    # キャッシュに保存
    mkdir -p "$CACHE_DIR"
    {
        echo "$br"
        echo "$rule_ipv6"
        echo "$rule_ipv4"
        echo "$ea_length"
        echo "$psid_offset"
        echo "$psid_len"
    } > "$params_file"
    
    # 結果表示
    echo "■ MAP-E設定パラメータ"
    echo "  ブリッジアドレス: $br"
    echo "  IPv6プレフィックス: $rule_ipv6"
    echo "  IPv4プレフィックス: $rule_ipv4"
    echo "  EA長: $ea_length"
    echo "  PSIDオフセット: $psid_offset"
    echo "  PSID長: $psid_len"
    
    debug_log "MAP-E parameters extracted and saved to cache"
    return 0
}

# MAP-E設定コマンドの表示（シミュレーションモード）
show_mape_config() {
    local params_file="$CACHE_DIR/mape_params.cache"
    
    if [ ! -f "$params_file" ]; then
        echo "エラー: MAP-Eパラメータが見つかりません"
        return 1
    fi
    
    # パラメータの読み取り
    local br=$(sed -n '1p' "$params_file")
    local rule_ipv6=$(sed -n '2p' "$params_file")
    local rule_ipv4=$(sed -n '3p' "$params_file")
    local ea_length=$(sed -n '4p' "$params_file")
    local psid_offset=$(sed -n '5p' "$params_file")
    local psid_len=$(sed -n '6p' "$params_file")
    
    # プレフィックス長の抽出
    local ipv4_prefix_len=$(echo "$rule_ipv4" | cut -d/ -f2)
    local ipv6_prefix_len=$(echo "$rule_ipv6" | cut -d/ -f2)
    
    echo ""
    echo "■ MAP-E設定コマンド"
    echo "  以下のコマンドでMAP-E設定が適用されます："
    echo ""
    echo "  # WAN無効化"
    echo "  uci set network.wan.auto='0'"
    echo ""
    echo "  # MAP-Eインターフェース設定"
    echo "  uci set network.mape=interface"
    echo "  uci set network.mape.proto='map'"
    echo "  uci set network.mape.maptype='map-e'"
    echo "  uci set network.mape.peeraddr='$br'"
    echo "  uci set network.mape.ipaddr='${rule_ipv4%/*}'"
    echo "  uci set network.mape.ip4prefixlen='$ipv4_prefix_len'"
    echo "  uci set network.mape.ip6prefix='${rule_ipv6%/*}'"
    echo "  uci set network.mape.ip6prefixlen='$ipv6_prefix_len'"
    echo "  uci set network.mape.ealen='$ea_length'"
    echo "  uci set network.mape.psidlen='$psid_len'"
    echo "  uci set network.mape.offset='$psid_offset'"
    echo "  uci set network.mape.tunlink='wan6'"
    echo "  uci set network.mape.mtu='1460'"
    echo "  uci set network.mape.encaplimit='ignore'"
    echo ""
    echo "  # ファイアウォール設定"
    echo "  uci del_list firewall.@zone[1].network='wan'"
    echo "  uci add_list firewall.@zone[1].network='mape'"
    echo ""
    echo "  # 設定反映"
    echo "  uci commit"
    echo "  /etc/init.d/network restart"
    echo ""
    
    return 0
}

# MAP-E設定の実際の適用
apply_mape_config() {
    local params_file="$CACHE_DIR/mape_params.cache"
    
    if [ ! -f "$params_file" ]; then
        echo "エラー: MAP-Eパラメータが見つかりません"
        return 1
    fi
    
    # パラメータの読み取り
    local br=$(sed -n '1p' "$params_file")
    local rule_ipv6=$(sed -n '2p' "$params_file")
    local rule_ipv4=$(sed -n '3p' "$params_file")
    local ea_length=$(sed -n '4p' "$params_file")
    local psid_offset=$(sed -n '5p' "$params_file")
    local psid_len=$(sed -n '6p' "$params_file")
    
    # プレフィックス長の抽出
    local ipv4_prefix_len=$(echo "$rule_ipv4" | cut -d/ -f2)
    local ipv6_prefix_len=$(echo "$rule_ipv6" | cut -d/ -f2)
    
    echo "MAP-E設定を適用しています..."
    
    # UCI設定が利用可能か確認
    if ! command -v uci > /dev/null 2>&1; then
        echo "エラー: uciコマンドが見つかりません。OpenWrt環境で実行してください。"
        return 1
    fi
    
    # 設定のバックアップ作成
    cp /etc/config/network /etc/config/network.mape.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.mape.bak 2>/dev/null
    
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
    
    # OpenWrtバージョンに応じた設定
    if [ -f "/etc/openwrt_release" ]; then
        local version=$(grep -E "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2 | cut -c 1-2)
        debug_log "Detected OpenWrt version: $version"
        
        case "$version" in
            "SN"|"24"|"23"|"22"|"21")
                debug_log "Setting modern OpenWrt specific options"
                uci set network.mape.legacymap='1'
                ;;
        esac
    fi
    
    # ファイアウォール設定
    local wan_zone=1
    uci del_list firewall.@zone[$wan_zone].network='wan'
    uci add_list firewall.@zone[$wan_zone].network='mape'
    
    # 設定の適用
    uci commit network
    uci commit firewall
    
    echo "MAP-E設定が適用されました。ネットワークを再起動しています..."
    /etc/init.d/network restart
    
    return 0
}

# ISP推定関数
guess_isp() {
    local ipv6_addr="$1"
    
    if [ -z "$ipv6_addr" ]; then
        return 1
    fi
    
    # IPv6プレフィックスの取得
    local prefix=$(echo "$ipv6_addr" | cut -d: -f1-2)
    
    debug_log "Analyzing IPv6 prefix: $prefix"
    
    case "$prefix" in
        2400:41*)
            echo "推定ISP: NTT東日本 (フレッツ光系)"
            ;;
        2400:85*)
            echo "推定ISP: NTT西日本 (フレッツ光系)"
            ;;
        2001:260*)
            echo "推定ISP: OCN"
            ;;
        2001:358*)
            echo "推定ISP: JPNE/IPoEサービス"
            ;;
        *)
            echo "推定ISP: 不明 ($prefix)"
            ;;
    esac
    
    return 0
}

# メイン処理
main() {
    echo "=== IPv6マイグレーション標準プロビジョニング設定取得 v$VERSION ==="
    
    # 初期化と必須コマンド確認
    create_cache_dir
    if ! check_commands; then
        return 1
    fi
    
    # IPv6アドレスの取得
    echo "IPv6アドレスを取得中..."
    local ipv6_addr=$(get_ipv6_address)
    if [ $? -ne 0 ]; then
        echo "エラー: IPv6アドレスを取得できませんでした"
        return 1
    fi
    echo "IPv6アドレス: $ipv6_addr"
    
    # ISP推定
    local isp_info=$(guess_isp "$ipv6_addr")
    if [ -n "$isp_info" ]; then
        echo "$isp_info"
    fi
    
    # TXTレコードの取得
    echo "プロビジョニングサーバ情報を探索中..."
    local txt_record=$(get_txt_record)
    if [ $? -ne 0 ] || [ -z "$txt_record" ]; then
        echo "エラー: プロビジョニングTXTレコードが見つかりませんでした"
        echo "お使いのISPがIPv6マイグレーション標準プロビジョニングに対応していない可能性があります"
        return 1
    fi
    
    echo "TXTレコード: $txt_record"
    
    # URLの抽出
    local prov_url=$(extract_url "$txt_record")
    if [ $? -ne 0 ] || [ -z "$prov_url" ]; then
        echo "エラー: TXTレコードからURLを抽出できませんでした"
        return 1
    fi
    
    echo "プロビジョニングサーバURL: $prov_url"
    
    # プロビジョニングサーバからデータ取得
    local json_response=$(get_provisioning_data "$prov_url" "$ipv6_addr")
    if [ $? -ne 0 ] || [ -z "$json_response" ]; then
        echo "エラー: プロビジョニングサーバからの応答の取得に失敗しました"
        return 1
    fi
    
    # MAP-Eパラメータの抽出
    extract_mape_params "$json_response"
    if [ $? -ne 0 ]; then
        echo "エラー: MAP-Eパラメータの抽出に失敗しました"
        return 1
    fi
    
    # 設定の表示または適用
    if [ "$SIMULATION_MODE" -eq 1 ]; then
        show_mape_config
        echo ""
        echo "注意: これはシミュレーションモードです。実際に設定を適用するには："
        echo "SIMULATION_MODE=0 $0"
    else
        apply_mape_config
    fi
    
    return 0
}

# スクリプト実行
main "$@"
