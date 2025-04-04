#!/bin/sh

SCRIPT_VERSION="2025.04.04-12-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX準拠シェルスクリプト
# 🚀 最終更新日: 2025-04-04
#
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 互換性: OpenWrt >= 19.07 (24.10.0でテスト済み)
#
# ⚠️ 重要な注意事項:
# OpenWrtは**Almquistシェル(ash)**のみを使用し、
# **Bourne-Again Shell(bash)**とは互換性がありません。
# =========================================================

# OpenWrt関数をロード
. /lib/functions.sh
. /lib/functions/network.sh
. /lib/netifd/netifd-proto.sh

# IPv6プレフィックスを取得
network_flush_cache
network_find_wan6 NET_IF6
network_get_ipaddr6 NET_ADDR6 "${NET_IF6}"
new_ip6_prefix=${NET_ADDR6}

echo "Debug: Working with IPv6 prefix: $new_ip6_prefix"

# プレフィックスとPSIDからIPv4アドレスを生成する関数
generate_ipv4_from_prefix38() {
    local prefix="$1"
    local psid="$2"
    
    echo "Debug: Generating IPv4 address from prefix38:$prefix, PSID:$psid"
    
    # ruleprefix38_20 のマッピングチェック (OCTET.OCTET.OCTET.PSID)
    case "$prefix" in
        "0x2400415180")
            echo "Debug: Found matching in ruleprefix38_20 for 0x2400415180 = 153,187,0"
            echo "153.187.0.$psid"
            return 0
            ;;
        "0x2400405000")
            echo "Debug: Found matching in ruleprefix38_20 for 0x2400405000 = 153,240,0"
            echo "153.240.0.$psid"
            return 0
            ;;
        "0x2400405080")
            echo "Debug: Found matching in ruleprefix38_20 for 0x2400405080 = 153,242,0"
            echo "153.242.0.$psid"
            return 0
            ;;
        *)
            echo "Debug: No direct mapping found for prefix $prefix"
            return 1
            ;;
    esac
}

# IPv6プレフィックスからMAP-E関連情報を抽出する関数
extract_map_e_info() {
    local ip6_prefix_tmp hextet1 hextet2 hextet3 hextet4
    local dec1 dec2 dec3 dec4 prefix31 prefix38
    local ip6prefixlen psidlen ealen ip4prefixlen offset
    
    # ::を:0::に変換してフォーマットを統一
    ip6_prefix_tmp=$(echo ${new_ip6_prefix} | sed 's/::/:0::/g')
    
    # 各16ビット（ヘクステット）を抽出
    hextet1=$(echo "$ip6_prefix_tmp" | cut -d':' -f1)
    hextet2=$(echo "$ip6_prefix_tmp" | cut -d':' -f2)
    hextet3=$(echo "$ip6_prefix_tmp" | cut -d':' -f3)
    hextet4=$(echo "$ip6_prefix_tmp" | cut -d':' -f4)
    
    # 空の場合は0を設定
    [ -z "$hextet1" ] && hextet1=0
    [ -z "$hextet2" ] && hextet2=0
    [ -z "$hextet3" ] && hextet3=0
    [ -z "$hextet4" ] && hextet4=0
    
    # 10進数に変換
    dec1=$(printf "%d" "0x$hextet1" 2>/dev/null || echo 0)
    dec2=$(printf "%d" "0x$hextet2" 2>/dev/null || echo 0)
    dec3=$(printf "%d" "0x$hextet3" 2>/dev/null || echo 0)
    dec4=$(printf "%d" "0x$hextet4" 2>/dev/null || echo 0)
    
    echo "Debug: Extracted hextets: $hextet1:$hextet2:$hextet3:$hextet4"
    echo "Debug: Decimal values: $dec1 $dec2 $dec3 $dec4"
    
    # プレフィックス値を計算
    prefix31_dec=$(( (dec1 * 65536) + (dec2 & 65534) )) # 0xfffe = 65534
    prefix38_dec=$(( (dec1 * 16777216) + (dec2 * 256) + ((dec3 & 64512) >> 8) )) # 0xfc00 = 64512
    
    # 16進数に変換
    prefix31=$(printf "0x%x" $prefix31_dec)
    prefix38=$(printf "0x%x" $prefix38_dec)
    
    echo "Debug: Calculated prefix31=$prefix31, prefix38=$prefix38"
    
    # ISP設定に基づくパラメータ値を設定（元のmap-e.shに基づく）
    ip6prefixlen=38
    psidlen=6
    offset=4
    ealen=$(( 64 - ip6prefixlen ))
    ip4prefixlen=$(( 32 - (ealen - psidlen) ))
    
    echo "Debug: ip6prefixlen=$ip6prefixlen, psidlen=$psidlen, ealen=$ealen, ip4prefixlen=$ip4prefixlen"
    
    # PSIDの計算（元のmap-e.shに基づく）
    # PSIDはヘクステット4の上位6ビット（38bitプレフィックスを持つISP）
    psid=$(( (dec4 >> 8) & 0x3f ))
    
    echo "Debug: PSID=$psid (hex: $(printf "0x%x" $psid))"
    
    # 結果表示
    echo "プレフィックス情報:"
    echo "  IPv6プレフィックス: $new_ip6_prefix"
    echo "  プレフィックス31: $prefix31"
    echo "  プレフィックス38: $prefix38"
    echo "MAP-E設定情報:"
    echo "  プレフィックス長: $ip6prefixlen"
    echo "  PSIDビット長: $psidlen"
    echo "  EA-bitsビット長: $ealen"
    echo "  オフセット: $offset"
    echo "抽出情報:"
    echo "  PSID値: $psid"
    
    # 元のmap-e.shのルールに基づいてIPv4アドレスを計算
    if [ "$prefix38" = "0x2400415180" ]; then
        # 元のスクリプトのruleprefix38_20配列のエントリに基づく処理
        # [0x2400415180]=153,187,0 のエントリに基づき、PSIDを第4オクテットとする
        ipv4="153.187.0.$psid"
        echo "変換結果:"
        echo "  IPv4アドレス: $ipv4"
        
        # 利用可能なポート範囲の計算
        max_port_blocks=$(( 1 << offset ))
        ports_per_block=$(( 1 << (16 - offset - psidlen) ))
        echo "ポート情報:"
        echo "  利用可能なポート数: $(( ports_per_block * (max_port_blocks - 1) ))"
        port_start=$(( psid << (16 - offset - psidlen) ))
        echo "  基本ポート開始値: $port_start"
    else
        echo "注意: このプレフィックス($prefix38)はマッピングに登録されていません。"
        echo "      ISPの提供する情報を確認してください。"
        
        # 設定済みのプレフィックスからの探索を試みる
        ipv4=$(generate_ipv4_from_prefix38 "$prefix38" "$psid")
        if [ $? -eq 0 ]; then
            echo "変換結果:"
            echo "  IPv4アドレス: $ipv4"
        fi
    fi
}

# 実行
echo "=== MAP-E情報抽出を実行します ==="
extract_map_e_info
echo "=== 抽出処理完了 ==="
