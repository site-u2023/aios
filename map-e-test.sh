#!/bin/sh
# MAP-E 情報抽出ツール - OpenWrt向けPOSIX準拠版

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
    
    # 16進数表記
    hex1=$(printf "%04x" $dec1)
    hex2=$(printf "%04x" $dec2)
    hex3=$(printf "%04x" $dec3)
    hex4=$(printf "%04x" $dec4)
    
    echo "Debug: Extracted hextets: $hextet1:$hextet2:$hextet3:$hextet4"
    echo "Debug: Decimal values: $dec1 $dec2 $dec3 $dec4"
    echo "Debug: Hex values: $hex1 $hex2 $hex3 $hex4"
    
    # プレフィックス値を計算
    prefix31_dec=$(( (dec1 * 65536) + (dec2 & 65534) )) # 0xfffe = 65534
    prefix38_dec=$(( (dec1 * 16777216) + (dec2 * 256) + ((dec3 & 64512) >> 8) )) # 0xfc00 = 64512
    
    # 16進数に変換
    prefix31=$(printf "0x%x" $prefix31_dec)
    prefix38=$(printf "0x%x" $prefix38_dec)
    
    echo "Debug: Calculated prefix31=$prefix31, prefix38=$prefix38"
    
    # v6プラスの設定を想定
    ip6prefixlen=38
    psidlen=6
    offset=4
    
    # EA-bitsの長さを計算
    ealen=$(( 64 - ip6prefixlen ))
    ip4prefixlen=$(( 32 - (ealen - psidlen) ))
    
    echo "Debug: ip6prefixlen=$ip6prefixlen, psidlen=$psidlen, ealen=$ealen, ip4prefixlen=$ip4prefixlen"
    
    # PSIDの計算
    # PSIDはヘクステット4の上位6ビットに位置する
    psid=$(( (dec4 >> 8) & 0x3f ))
    
    echo "Debug: PSID=$psid (hex: $(printf "0x%x" $psid))"
    
    # EA-bits（Embedded Address bits）を抽出
    # EA-bitsはプレフィックス後の特定のビット
    # これは将来のIPv4アドレス計算に必要
    local ea_bits_raw=$(( ((dec3 & 0x03ff) << 6) | ((dec4 >> 10) & 0x3f) ))
    local ea_bits=$(printf "0x%x" $ea_bits_raw)
    
    echo "Debug: EA-bits raw=$ea_bits_raw (hex: $ea_bits)"
    
    # ビットパターンの詳細表示（デバッグ用）
    echo "Debug: Hextet3 binary: $(printf "%016d" $(echo "ibase=16;obase=2;${hex3^^}" | bc))"
    echo "Debug: Hextet4 binary: $(printf "%016d" $(echo "ibase=16;obase=2;${hex4^^}" | bc))"
    
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
    echo "  EA-bits: $ea_bits"
    echo "注意: IPv4アドレス計算にはISP固有のマッピングルールが必要です"
}

# 実行
echo "=== MAP-E情報抽出を実行します ==="
extract_map_e_info
echo "=== 抽出処理完了 ==="
