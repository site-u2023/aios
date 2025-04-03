#!/bin/sh
#===============================================================================
# NTT東日本 NGN/MAP-E設定スクリプト
#
# このスクリプトは、NTT東日本のフレッツ光回線でMAP-E接続を
# 自動的に構成します。IPv6マイグレーション標準プロビジョニングが
# 利用できない環境で使用します。
#
# POSIX準拠 OpenWrt対応
#===============================================================================

# 設定変数
VERSION="2025.04.04-1"
WAN_IFACE="wan"                # WANインターフェース名
WAN6_IFACE="wan6"              # WAN6インターフェース名
TEMP_DIR="/tmp"                # 一時ファイル用ディレクトリ
CACHE_DIR="/tmp/ngn_cache"     # キャッシュディレクトリ
SIMULATION_MODE=1              # 1=設定表示のみ、0=設定を実際に適用

# NTT東日本 NGN/MAP-E固定パラメータ
BR_ADDRESS="2404:8e01::1"       # ボーダルータIPv6アドレス
IPV4_PREFIX="192.0.0.0/29"      # IPv4プレフィックス
IPV6_PREFIX="2001:0db8::/48"    # IPv6プレフィックス（ユーザーのプレフィックスに置き換え）
EA_LENGTH="15"                  # EAビット長
PSID_OFFSET="4"                 # PSIDオフセット
PSID_LENGTH="3"                 # PSID長

# デバッグログ関数（英語）
debug_log() {
    [ -n "$DEBUG" ] && echo "DEBUG: $1" >&2
}

# 情報出力関数（日本語）
print_info() {
    echo "$1"
}

# エラー出力関数（日本語）
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
    local required_commands="ip uci"
    
    for cmd in $required_commands; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    
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

# IPv6プレフィックスの取得
get_ipv6_prefix() {
    local ipv6_addr="$1"
    local prefix_len=48  # NGNのユーザープレフィックス長
    
    debug_log "Extracting IPv6 prefix from $ipv6_addr with length $prefix_len"
    
    if [ -z "$ipv6_addr" ]; then
        print_error "IPv6アドレスが指定されていません"
        return 1
    fi
    
    # プレフィックス部分の抽出
    local prefix=$(echo "$ipv6_addr" | cut -d: -f1-3)
    
    if [ -n "$prefix" ]; then
        echo "$prefix::/$prefix_len"
        debug_log "Extracted prefix: $prefix::/$prefix_len"
        return 0
    fi
    
    print_error "IPv6プレフィックスの抽出に失敗しました"
    return 1
}

# ISP情報の確認
check_isp() {
    local ipv6_addr="$1"
    
    if [ -z "$ipv6_addr" ]; then
        print_error "IPv6アドレスが指定されていません"
        return 1
    fi
    
    # NTT東日本のプレフィックスチェック
    if echo "$ipv6_addr" | grep -q "^2400:41"; then
        print_info "NTT東日本のIPv6アドレスを検出しました"
        echo "ntt_east"
        return 0
    fi
    
    # NTT西日本のプレフィックスチェック
    if echo "$ipv6_addr" | grep -q "^2400:85"; then
        print_info "NTT西日本のIPv6アドレスを検出しました"
        print_error "このスクリプトはNTT東日本向けです。NTT西日本用に調整が必要です。"
        echo "ntt_west"
        return 1
    fi
    
    # その他のISP
    print_error "このIPv6アドレスはNTT東日本のものではありません"
    echo "unknown"
    return 1
}

# NGN/MAP-Eパラメータの設定
setup_mape_params() {
    local ipv6_prefix="$1"
    local params_file="$CACHE_DIR/mape_params.cache"
    
    debug_log "Setting up MAP-E parameters for NGN"
    
    if [ -z "$ipv6_prefix" ]; then
        print_error "IPv6プレフィックスが指定されていません"
        return 1
    fi
    
    # キャッシュディレクトリ作成
    mkdir -p "$CACHE_DIR"
    
    # パラメータをキャッシュに保存
    {
        echo "$BR_ADDRESS"
        echo "$ipv6_prefix"
        echo "$IPV4_PREFIX"
        echo "$EA_LENGTH"
        echo "$PSID_OFFSET"
        echo "$PSID_LENGTH"
    } > "$params_file"
    
    debug_log "MAP-E parameters saved to cache"
    
    # 結果表示
    print_info "■ NGN/MAP-E設定パラメータ"
    print_info "  ブリッジルータ(BR): $BR_ADDRESS"
    print_info "  IPv6プレフィックス: $ipv6_prefix"
    print_info "  IPv4プレフィックス: $IPV4_PREFIX"
    print_info "  EAビット長: $EA_LENGTH"
    print_info "  PSIDオフセット: $PSID_OFFSET"
    print_info "  PSID長: $PSID_LENGTH"
    
    return 0
}

# MAP-E設定コマンドの表示（シミュレーションモード）
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
    
    # プレフィックス長の抽出
    local ipv4_prefix_len=$(echo "$rule_ipv4" | cut -d/ -f2)
    local ipv6_prefix_len=$(echo "$rule_ipv6" | cut -d/ -f2)
    
    print_info ""
    print_info "■ NTT東日本 NGN/MAP-E設定コマンド"
    print_info "  以下のコマンドでMAP-E設定が適用されます："
    print_info ""
    print_info "  # WAN無効化"
    print_info "  uci set network.wan.auto='0'"
    print_info ""
    print_info "  # MAP-Eインターフェース設定"
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
    print_info "  # 設定反映"
    print_info "  uci commit"
    print_info "  /etc/init.d/network restart"
    print_info ""
    
    return 0
}

# MAP-E設定の実際の適用
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
    
    # プレフィックス長の抽出
    local ipv4_prefix_len=$(echo "$rule_ipv4" | cut -d/ -f2)
    local ipv6_prefix_len=$(echo "$rule_ipv6" | cut -d/ -f2)
    
    print_info "NGN/MAP-E設定を適用しています..."
    
    # UCI設定が利用可能か確認
    if ! command -v uci > /dev/null 2>&1; then
        print_error "uciコマンドが見つかりません。OpenWrt環境で実行してください。"
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
    
    # OpenWrtバージョン固有の設定
    if [ -f "/etc/openwrt_release" ]; then
        local version=$(grep -E "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2 | cut -c 1-2)
        debug_log "Detected OpenWrt version: $version"
        
        case "$version" in
            "24"|"23"|"22"|"21")
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
    
    print_info "MAP-E設定が適用されました。ネットワークを再起動しています..."
    
    # ネットワーク再起動
    /etc/init.d/network restart
    
    return 0
}

# メイン処理
main() {
    print_info "=== NTT東日本 NGN/MAP-E設定スクリプト v$VERSION ==="
    
    # 初期化と必須コマンド確認
    create_cache_dir
    check_commands || exit 1
    
    # IPv6アドレスの取得
    print_info "\n■ IPv6アドレスの取得"
    local ipv6_addr=$(get_ipv6_address)
    if [ $? -ne 0 ]; then
        print_error "IPv6アドレスの取得に失敗しました"
        exit 1
    fi
    print_info "IPv6アドレス: $ipv6_addr"
    
    # ISP確認
    print_info "\n■ ISP確認"
    local isp_type=$(check_isp "$ipv6_addr")
    if [ "$isp_type" != "ntt_east" ]; then
        print_error "このスクリプトはNTT東日本のフレッツ光回線専用です"
        exit 1
    fi
    
    # IPv6プレフィックスの取得
    print_info "\n■ IPv6プレフィックスの取得"
    local ipv6_prefix=$(get_ipv6_prefix "$ipv6_addr")
    if [ $? -ne 0 ]; then
        print_error "IPv6プレフィックスの取得に失敗しました"
        exit 1
    fi
    print_info "IPv6プレフィックス: $ipv6_prefix"
    
    # MAP-Eパラメータ設定
    print_info "\n■ NGN/MAP-Eパラメータの設定"
    setup_mape_params "$ipv6_prefix"
    if [ $? -ne 0 ]; then
        print_error "MAP-Eパラメータの設定に失敗しました"
        exit 1
    fi
    
    # 設定の表示または適用
    if [ "$SIMULATION_MODE" -eq 1 ]; then
        show_mape_config
        print_info ""
        print_info "注意: これはシミュレーションモードです。実際に設定を適用するには："
        print_info "SIMULATION_MODE=0 $0"
    else
        apply_mape_config
    fi
    
    return 0
}

# スクリプト実行
main "$@"
