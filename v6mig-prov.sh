#!/bin/sh
#===============================================================================
# IPv6マイグレーション標準プロビジョニング設定取得スクリプト
#
# このスクリプトは、IPv6マイグレーション標準プロビジョニング仕様に従い、
# DNS TXTレコードからプロビジョニングサーバのURLを取得するか、
# ISP固有のAPIからMAP-E設定情報を取得します。
#
# OpenWrt/ASHシェル対応 POSIX準拠スクリプト
#===============================================================================

# 設定変数
VERSION="2025.04.03-1"
WAN_IFACE="wan"                      # WANインターフェース名
VENDORID="acde48-v6pc_swg_hgw"       # ベンダーID
PRODUCT="V6MIG-ROUTER"               # 製品名
PRODUCT_VERSION="1_0"                # バージョン
DEBUG=1                              # デバッグ出力（1=有効, 0=無効）
TEMP_DIR="/tmp"                      # 一時ファイル用ディレクトリ
CACHE_DIR="/tmp/v6mig_cache"         # キャッシュディレクトリ
CACHE_VALID_TIME=3600                # キャッシュ有効時間（秒）
DNS_SERVERS="8.8.8.8 1.1.1.1 9.9.9.9" # 代替DNSサーバーリスト

# フレッツ系ISP APIキー (サンプル - 実際の値に置き換えてください)
OCN_API_KEY="sample_key"

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
        debug_log "Created cache directory: $CACHE_DIR"
    fi
}

# 設定のバックアップ作成
backup_config() {
    if [ -f "/etc/config/network" ]; then
        cp /etc/config/network /etc/config/network.v6mig.bak
        debug_log "Network configuration backed up"
    fi
}

# ネットワーク情報取得に必要なOpenWrtライブラリの読み込み
load_network_libs() {
    if [ -f "/lib/functions/network.sh" ]; then
        . /lib/functions/network.sh
        . /lib/functions.sh
        network_flush_cache
        debug_log "OpenWrt network libraries loaded"
        return 0
    else
        debug_log "OpenWrt network libraries not found"
        return 1
    fi
}

# ====== 必要なコマンドの確認 ======
check_commands() {
    for cmd in ip curl jq dig uci; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            print_error "$cmd コマンドが見つかりません。インストールしてください。"
            return 1
        fi
    done
    debug_log "All required commands are available"
    return 0
}

# ====== IPv6アドレスの取得 ======
get_ipv6_address() {
    local local_ipv6=""
    local net_if6=""
    
    debug_log "Attempting to get IPv6 address"
    
    # OpenWrtの関数を利用
    if load_network_libs; then
        network_find_wan6 net_if6
        network_get_ipaddr6 local_ipv6 "${net_if6}"
        
        if [ -n "$local_ipv6" ]; then
            debug_log "Retrieved IPv6 using OpenWrt network functions: $local_ipv6"
            echo "$local_ipv6"
            return 0
        else
            debug_log "Failed to get IPv6 from network functions, trying ip command"
        fi
    fi
    
    # 一般的な方法でグローバルIPv6アドレスを取得
    local_ipv6=$(ip -6 addr show dev "$WAN_IFACE" scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)
    
    if [ -n "$local_ipv6" ]; then
        debug_log "Retrieved IPv6 using ip command: $local_ipv6"
        echo "$local_ipv6"
        return 0
    fi
    
    print_error "グローバルIPv6アドレスを取得できませんでした"
    return 1
}

# ====== IPv6プレフィックスの取得 ======
get_ipv6_prefix() {
    local ipv6_addr="$1"
    local prefix_len=64  # デフォルト値
    
    if [ -z "$ipv6_addr" ]; then
        print_error "IPv6アドレスが指定されていません"
        return 1
    fi
    
    # プレフィックス長の取得（UICが利用可能な場合）
    if command -v uci > /dev/null 2>&1; then
        local uci_prefix_len=$(uci get network.wan6.ip6prefix 2>/dev/null | cut -d/ -f2)
        if [ -n "$uci_prefix_len" ]; then
            prefix_len="$uci_prefix_len"
            debug_log "Retrieved prefix length from UCI: $prefix_len"
        fi
    fi
    
    # プレフィックス部分の抽出
    local prefix_parts=$(echo "$ipv6_addr" | tr ':' ' ' | awk -v len="$prefix_len" '{
        full_parts = int(len / 16);
        remainder = len % 16;
        result = "";
        for (i = 1; i <= full_parts; i++) {
            if (i > 1) result = result ":";
            result = result $i;
        }
        if (remainder > 0) {
            mask = 2^(16-remainder) - 1;
            hex_val = "0x" $(full_parts+1);
            masked = and(hex_val, compl(mask));
            if (full_parts > 0) result = result ":";
            result = result sprintf("%x", masked);
        }
        print result;
    }')
    
    echo "${prefix_parts}::/${prefix_len}"
    debug_log "Extracted IPv6 prefix: ${prefix_parts}::/${prefix_len}"
    return 0
}

# ====== TXTレコードからプロビジョニング情報を取得 ======
get_provisioning_from_txt() {
    local txt_record=""
    local success=0
    local domain="4over6.info"
    
    debug_log "Attempting to retrieve TXT record from $domain"
    
    # システムDNSで試行
    txt_record=$(dig +short TXT "$domain" 2>/dev/null | sed -e 's/^"//' -e 's/"$//')
    
    if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
        debug_log "Found valid TXT record using system DNS: $txt_record"
        success=1
    else
        debug_log "No valid TXT record found with system DNS, trying alternative DNS servers"
        
        # 代替DNSサーバーで試行
        for dns in $DNS_SERVERS; do
            debug_log "Trying DNS server: $dns"
            txt_record=$(dig +short TXT "$domain" @"$dns" 2>/dev/null | sed -e 's/^"//' -e 's/"$//')
            
            if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
                debug_log "Found valid TXT record with DNS server $dns: $txt_record"
                success=1
                break
            fi
        done
        
        # 別のドメイン v6mig.transix.jp も試行
        if [ "$success" = "0" ]; then
            debug_log "Trying alternative domain: v6mig.transix.jp"
            txt_record=$(dig +short TXT v6mig.transix.jp 2>/dev/null | sed -e 's/^"//' -e 's/"$//')
            
            if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
                debug_log "Found valid TXT record from v6mig.transix.jp: $txt_record"
                success=1
            else
                for dns in $DNS_SERVERS; do
                    debug_log "Trying v6mig.transix.jp with DNS server: $dns"
                    txt_record=$(dig +short TXT v6mig.transix.jp @"$dns" 2>/dev/null | sed -e 's/^"//' -e 's/"$//')
                    
                    if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "url="; then
                        debug_log "Found valid TXT record from v6mig.transix.jp with DNS $dns: $txt_record"
                        success=1
                        break
                    fi
                done
            fi
        fi
    fi
    
    if [ "$success" = "1" ]; then
        echo "$txt_record"
        return 0
    fi
    
    debug_log "No valid TXT record found from any source"
    return 1
}

# ====== TXTレコードからURLを抽出 ======
extract_url_from_txt() {
    local txt_record="$1"
    local url=""
    
    debug_log "Extracting URL from TXT record: $txt_record"
    
    url=$(echo "$txt_record" | awk '{
        for (i=1; i<=NF; i++) {
            if ($i ~ /^url=/) {
                sub(/^url=/, "", $i);
                print $i;
                exit;
            }
        }
    }')
    
    if [ -n "$url" ]; then
        debug_log "Extracted URL: $url"
        echo "$url"
        return 0
    else
        debug_log "Failed to extract URL from TXT record"
        return 1
    fi
}

# ====== プロビジョニングサーバへのリクエスト ======
request_provisioning() {
    local url="$1"
    local ipv6_addr="$2"
    local response_file="$TEMP_DIR/v6mig_resp_$$.json"
    local max_retries=3
    local retry=0
    
    debug_log "Requesting provisioning data from server: $url"
    
    while [ $retry -lt $max_retries ]; do
        # リクエストパラメータの構築
        local params="vendorid=$VENDORID&product=$PRODUCT&version=$PRODUCT_VERSION&capability=map_e"
        if [ -n "$ipv6_addr" ]; then
            params="$params&ipv6addr=$ipv6_addr"
        fi
        
        debug_log "Request URL: $url/config?$params (attempt $(($retry + 1))/$max_retries)"
        
        # サーバーへリクエスト送信
        curl -s -m 10 -A "V6MIG-Client/$VERSION" "$url/config?$params" -o "$response_file" 2>/dev/null
        
        if [ -f "$response_file" ] && [ -s "$response_file" ]; then
            # JSONの検証
            if jq . "$response_file" >/dev/null 2>&1; then
                debug_log "Received valid JSON response"
                cat "$response_file"
                rm -f "$response_file"
                return 0
            else
                debug_log "Response is not valid JSON, retrying..."
            fi
        else
            debug_log "Empty or no response, retrying..."
        fi
        
        retry=$((retry + 1))
        sleep 2
    done
    
    rm -f "$response_file" 2>/dev/null
    print_error "プロビジョニングサーバからの応答が取得できませんでした"
    return 1
}

# ====== OCN用MAP-E設定取得API ======
get_ocn_mape_config() {
    local ipv6_prefix="$1"
    local response_file="$TEMP_DIR/ocn_resp_$$.json"
    
    if [ -z "$ipv6_prefix" ]; then
        print_error "IPv6プレフィックスが指定されていません"
        return 1
    fi
    
    # プレフィックス情報を抽出
    local prefix_addr=$(echo "$ipv6_prefix" | cut -d/ -f1)
    local prefix_len=$(echo "$ipv6_prefix" | cut -d/ -f2)
    
    debug_log "Requesting OCN MAP-E configuration for prefix: $prefix_addr/$prefix_len"
    
    # OCN APIへのリクエスト（APIキーが必要）
    local api_url="https://rule.map.ocn.ad.jp/?ipv6Prefix=$prefix_addr&ipv6PrefixLength=$prefix_len&code=$OCN_API_KEY"
    
    curl -s -m 10 -A "V6MIG-Client/$VERSION" "$api_url" -o "$response_file" 2>/dev/null
    
    if [ -f "$response_file" ] && [ -s "$response_file" ]; then
        # OCN APIのレスポンス検証
        if grep -q "IPv4Address" "$response_file"; then
            debug_log "Received valid OCN MAP-E configuration"
            
            # OCNの応答をv6migプロビジョニング互換の形式に変換
            local ipv4_addr=$(grep IPv4Address "$response_file" | awk '{print $2}' | tr -d '"')
            local ipv4_prefix=$(grep IPv4PrefixLength "$response_file" | awk '{print $2}' | tr -d '",')
            local ipv6_rule=$(grep IPv6RulePrefix "$response_file" | awk '{print $2}' | tr -d '"')
            local br_addr=$(grep BRIPv6Address "$response_file" | awk '{print $2}' | tr -d '"')
            local psid=$(grep Psid "$response_file" | awk '{print $2}' | tr -d '",')
            local psid_len=$(grep PsidLen "$response_file" | awk '{print $2}' | tr -d '",')
            local psid_offset=$(grep PsidOffset "$response_file" | awk '{print $2}' | tr -d '",')
            
            # 標準形式のJSON作成
            {
                echo "{"
                echo "  \"map_e\": {"
                echo "    \"br\": \"$br_addr\","
                echo "    \"rules\": ["
                echo "      {"
                echo "        \"ipv4\": \"$ipv4_addr/$ipv4_prefix\","
                echo "        \"ipv6\": \"$ipv6_rule\","
                echo "        \"ea_length\": $((32 - $ipv4_prefix + $psid_len)),"
                echo "        \"psid_offset\": $psid_offset,"
                echo "        \"psid_len\": $psid_len"
                echo "      }"
                echo "    ]"
                echo "  }"
                echo "}"
            } > "$TEMP_DIR/ocn_converted_$$.json"
            
            cat "$TEMP_DIR/ocn_converted_$$.json"
            rm -f "$response_file" "$TEMP_DIR/ocn_converted_$$.json" 2>/dev/null
            return 0
        else
            debug_log "OCN response does not contain required MAP-E fields"
        fi
    else
        debug_log "Empty or no response from OCN API"
    fi
    
    rm -f "$response_file" 2>/dev/null
    return 1
}

# ====== ISPを自動検出 ======
detect_isp() {
    local cache_file="$CACHE_DIR/isp_info.cache"
    local cache_age=0
    local current_time=0
    
    # キャッシュがあれば使用
    if [ -f "$cache_file" ]; then
        current_time=$(date +%s)
        local cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || date +%s)
        cache_age=$((current_time - cache_time))
        
        if [ $cache_age -lt $CACHE_VALID_TIME ]; then
            debug_log "Using cached ISP information (age: ${cache_age}s)"
            cat "$cache_file"
            return 0
        else
            debug_log "ISP cache expired (age: ${cache_age}s)"
        fi
    fi
    
    # dynamic-system-info.shのget_isp_info関数が利用可能かチェック
    if type get_isp_info >/dev/null 2>&1; then
        debug_log "Using get_isp_info from dynamic-system-info.sh"
        get_isp_info --no-display
        
        if [ -n "$ISP_NAME" ]; then
            debug_log "ISP detected: $ISP_NAME"
            echo "$ISP_NAME" > "$cache_file"
            echo "$ISP_NAME"
            return 0
        fi
    fi
    
    # 独自にISP検出を試行
    debug_log "Attempting manual ISP detection"
    local tmp_file="$TEMP_DIR/isp_detect_$$.json"
    local ip_address=$(curl -s https://api.ipify.org)
    
    if [ -n "$ip_address" ]; then
        curl -s "http://ip-api.com/json/${ip_address}?fields=isp,as,org" -o "$tmp_file"
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            local isp_name=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
            
            if [ -n "$isp_name" ]; then
                debug_log "ISP detected manually: $isp_name"
                echo "$isp_name" > "$cache_file"
                echo "$isp_name"
                rm -f "$tmp_file"
                return 0
            fi
        fi
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    debug_log "Failed to detect ISP"
    return 1
}

# ====== MAP-Eパラメータを抽出 ======
extract_mape_params() {
    local response="$1"
    
    if [ -z "$response" ]; then
        print_error "プロビジョニング応答が空です"
        return 1
    fi
    
    debug_log "Extracting MAP-E parameters"
    
    # 一時ファイルに保存してjqで処理
    local tmp_file="$TEMP_DIR/mape_json_$$.json"
    echo "$response" > "$tmp_file"
    
    # JSONからMAP-Eパラメータを抽出
    local mape_json=$(jq -r '.map_e' "$tmp_file")
    
    if [ "$mape_json" = "null" ] || [ -z "$mape_json" ]; then
        print_error "応答にMAP-Eパラメータが含まれていません"
        rm -f "$tmp_file"
        return 1
    fi
    
    # 各パラメータの抽出
    local br=$(jq -r '.map_e.br' "$tmp_file")
    local rule_ipv6=$(jq -r '.map_e.rules[0].ipv6' "$tmp_file")
    local rule_ipv4=$(jq -r '.map_e.rules[0].ipv4' "$tmp_file")
    local ea_length=$(jq -r '.map_e.rules[0].ea_length' "$tmp_file")
    local psid_offset=$(jq -r '.map_e.rules[0].psid_offset' "$tmp_file")
    local psid_len=$(jq -r '.map_e.rules[0].psid_len // "未指定"' "$tmp_file")
    
    # クリーンアップ
    rm -f "$tmp_file"
    
    # パラメータチェック
    if [ "$br" = "null" ] || [ -z "$br" ] || \
       [ "$rule_ipv6" = "null" ] || [ -z "$rule_ipv6" ] || \
       [ "$rule_ipv4" = "null" ] || [ -z "$rule_ipv4" ] || \
       [ "$ea_length" = "null" ] || [ -z "$ea_length" ] || \
       [ "$psid_offset" = "null" ] || [ -z "$psid_offset" ]; then
        print_error "必要なMAP-Eパラメータが欠けています"
        return 1
    fi
    
    # 結果表示
    print_info "■ MAP-E設定パラメータ"
    print_info "  BR IPv6アドレス: $br"
    print_info "  IPv6プレフィックス: $rule_ipv6"
    print_info "  IPv4プレフィックス: $rule_ipv4"
    print_info "  EAビット長: $ea_length"
    print_info "  PSIDオフセット: $psid_offset"
    print_info "  PSID長: $psid_len"
    
    # パラメータをキャッシュに保存
    {
        echo "$br"
        echo "$rule_ipv6"
        echo "$rule_ipv4"
        echo "$ea_length"
        echo "$psid_offset"
        echo "$psid_len"
    } > "$CACHE_DIR/mape_params.cache"
    
    return 0
}

# ====== MAP-E設定の適用（シミュレーションモード） ======
apply_mape_config_simulation() {
    local params_file="$CACHE_DIR/mape_params.cache"
    
    if [ ! -f "$params_file" ]; then
        print_error "MAP-Eパラメータファイルが見つかりません"
        return 1
    fi
    
    # パラメータの読み込み
    local br=$(sed -n '1p' "$params_file")
    local rule_ipv6=$(sed -n '2p' "$params_file")
    local rule_ipv4=$(sed -n '3p' "$params_file")
    local ea_length=$(sed -n '4p' "$params_file")
    local psid_offset=$(sed -n '5p' "$params_file")
    local psid_len=$(sed -n '6p' "$params_file")
    
    # IPv4 CIDR形式からプレフィックス長を抽出
    local ipv4_prefix_len=$(echo "$rule_ipv4" | cut -d/ -f2)
    
    print_info "■ MAP-E設定（シミュレーション）"
    print_info "  MAP-E インターフェース設定:"
    print_info "    config interface 'mape'"
    print_info "      option proto 'map'"
    print_info "      option maptype 'map-e'"
    print_info "      option peeraddr '$br'"
    print_info "      option ipaddr '${rule_ipv4%/*}'"
    print_info "      option ip4prefixlen '$ipv4_prefix_len'"
    print_info "      option ip6prefix '${rule_ipv6%/*}'"
    print_info "      option ip6prefixlen '${rule_ipv6#*/}'"
    print_info "      option ealen '$ea_length'"
    print_info "      option psidlen '$psid_len'"
    print_info "      option offset '$psid_offset'"
    print_info "      option tunlink 'wan6'"
    print_info "      option mtu '1460'"
    print_info "      option ttl '64'"
    print_info "      option encaplimit 'ignore'"
    
    return 0
}

# ====== メイン処理 ======
main() {
    local ipv6_addr=""
    local ipv6_prefix=""
    local txt_record=""
    local prov_url=""
    local prov_response=""
    local isp_name=""
    
    # 初期設定
    create_cache_dir
    backup_config
    
    # 必要なコマンドの確認
    print_info "IPv6マイグレーション標準プロビジョニング設定取得ツール (v$VERSION)"
    print_info "OpenWrt MAP-E 自動設定"
    print_info "----------------------------------------"
    
    check_commands || exit 1
    
    # IPv6アドレスの取得
    print_info "IPv6アドレス取得中..."
    ipv6_addr=$(get_ipv6_address)
    if [ -z "$ipv6_addr" ]; then
        print_error "IPv6アドレスを取得できないため処理を中断します"
        exit 1
    fi
    print_info "グローバルIPv6アドレス: $ipv6_addr"
    
    # IPv6プレフィックスの取得
    print_info "IPv6プレフィックス取得中..."
    ipv6_prefix=$(get_ipv6_prefix "$ipv6_addr")
    print_info "IPv6プレフィックス: $ipv6_prefix"
    
    # ISP検出
    print_info "ISPの自動検出を試行中..."
    isp_name=$(detect_isp)
    if [ -n "$isp_name" ]; then
        print_info "検出されたISP: $isp_name"
    else
        print_info "ISPの自動検出に失敗しました。一般的な方法でプロビジョニングを試みます"
    fi
    
    # プロビジョニングの流れ決定
    local provisioning_method="standard"
    case "$isp_name" in
        *OCN*|*ocn*|*NTT*|*ntt*)
            provisioning_method="ocn"
            print_info "OCN向けのプロビジョニング方法を使用します"
            ;;
        *IIJ*|*iij*|*interlink*|*INTERLINK*)
            provisioning_method="iij"
            print_info "IIJ向けのプロビジョニング方法を使用します"
            ;;
        *JPNE*|*jpne*|*Japan*Net*|*JAPAN*NET*)
            provisioning_method="jpne"
            print_info "JPNE向けのプロビジョニング方法を使用します"
            ;;
        *)
            print_info "標準プロビジョニング方法を使用します"
            ;;
    esac
    
    # プロビジョニングサーバ情報の取得
    if [ "$provisioning_method" = "standard" ]; then
        print_info "DNSのTXTレコードからプロビジョニングサーバ情報を取得中..."
        txt_record=$(get_provisioning_from_txt)
        
        if [ -n "$txt_record" ]; then
            print_info "取得したTXTレコード: $txt_record"
            
            prov_url=$(extract_url_from_txt "$txt_record")
            if [ -n "$prov_url" ]; then
                print_info "プロビジョニングサーバURL: $prov_url"
                
                print_info "プロビジョニングサーバに接続中..."
                prov_response=$(request_provisioning "$prov_url" "$ipv6_addr")
                
                if [ -n "$prov_response" ]; then
                    print_info "プロビジョニング情報を取得しました"
                    extract_mape_params "$prov_response"
                    apply_mape_config_simulation
                else
                    provisioning_method="fallback"
                    print_info "プロビジョニングサーバからの応答がないため、代替方法を試みます"
                fi
            else
                provisioning_method="fallback"
                print_info "TXTレコードからURLを抽出できなかったため、代替方法を試みます"
            fi
        else
            provisioning_method="fallback"
            print_info "有効なTXTレコードが取得できなかったため、代替方法を試みます"
        fi
    fi
    
    # OCN向け処理
    if [ "$provisioning_method" = "ocn" ] || [ "$provisioning_method" = "fallback" ]; then
        print_info "OCN MAP-E API による設定取得を試行中..."
        prov_response=$(get_ocn_mape_config "$ipv6_prefix")
        
        if [ -n "$prov_response" ]; then
            print_info "OCN APIからMAP-E設定を取得しました"
            extract_mape_params "$prov_response"
            apply_mape_config_simulation
        else
            print_info "OCN APIからの情報取得に失敗しました"
            print_error "利用可能なプロビジョニング方法がありません"
        fi
    fi
    
    # 終了メッセージ
    print_info ""
    print_info "このスクリプトはMAP-E設定情報の表示のみを行いました。"
    print_info "実際の設定変更は行っていません。"
    print_info ""
    print_info "設定を適用するには、スクリプトを拡張するか手動で設定を行ってください。"
    
    return 0
}

# スクリプト実行
main "$@"
