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

        # IPv4アドレスの計算
    ipv4=$(generate_ipv4_from_prefix "$prefix38" "$psid")
    if [ $? -eq 0 ]; then
        echo "変換結果:"
        echo "  IPv4アドレス: $ipv4"
    else
        echo "注意: このプレフィックス($prefix38)とPSID($psid)の組み合わせに対応するIPv4アドレスが見つかりませんでした。"
        echo "      ISP固有のマッピングルールを確認してください。"
    fi
}

# プレフィックスとPSIDからIPv4アドレスを生成する関数
generate_ipv4_from_prefix() {
    local prefix="$1"
    local psid="$2"
    
    echo "# Debug: Generating IPv4 address from prefix:$prefix, PSID:$psid"
    
    # prefix38からIPv4アドレスの前半部分を生成
    case "$prefix" in
        "0x2400415180")
            echo "# Debug: Found matching prefix for 0x2400415180"
            local base_ip="153.187.0"
            echo "${base_ip}.${psid}"
            return 0
            ;;
        "0x2400405000")
            echo "# Debug: Found matching prefix for 0x2400405000"
            local base_ip="153.240.0"
            echo "${base_ip}.${psid}"
            return 0
            ;;
        "0x2400405080")
            echo "# Debug: Found matching prefix for 0x2400405080"
            local base_ip="153.242.0"
            echo "${base_ip}.${psid}"
            return 0
            ;;
        # 必要に応じて他のプレフィックスを追加
        *)
            # 環境変数からの取得を試みる
            local var_name="ruleprefix38_20_${prefix}"
            local ip_base=$(eval echo \$${var_name})
            
            if [ -n "$ip_base" ]; then
                echo "# Debug: Found base IP in environment variable: $ip_base"
                local formatted_ip=$(echo "$ip_base" | tr ',' '.')
                echo "${formatted_ip}.${psid}"
                return 0
            fi
            
            echo "# Debug: No mapping found for prefix $prefix"
            return 1
            ;;
    esac
}

# 実行
echo "=== MAP-E情報抽出を実行します ==="
extract_map_e_info
echo "=== 抽出処理完了 ==="
