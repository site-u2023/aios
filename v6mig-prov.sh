#!/bin/ash
#===============================================================================
# MAP-E 自動接続スクリプト
#
# このスクリプトは、IPv6マイグレーション標準プロビジョニング仕様に従い、
# DNS TXT レコードからプロビジョニングサーバの URL を取得し、
# プロビジョニングサーバへ GET リクエストを送信して MAP-E のパラメータを取得、
# さらにローカル IPv6 アドレスと MAP-E ルールからクライアント用 IPv4 アドレスを
# 計算し、MAP-E トンネルインターフェース (mape0) を設定するサンプルです。
#
# ※必要に応じて設定変数等を変更してください。
#===============================================================================

#----- 設定変数 -----
WAN_IFACE="wan"                      # WAN インターフェース名（グローバルIPv6取得対象）
VENDORID="acde48-v6pc_swg_hgw"         # ベンダーID（例：ベンダーOUI＋任意文字列）
PRODUCT="V6MIG-ROUTER"               # 製品名（ASCII 半角英数字、ハイフン、アンダースコア 32文字以内）
VERSION="1_0"                        # ファームウェアバージョン（数字とアンダースコア、例：1_0）
PSID=0x35                           # MAP-E 用 PSID（必要に応じて設定、ここでは例として 0x00）
DNS_SERVER=""                        # カスタムDNSサーバー（空欄の場合はシステムのデフォルトを使用）

#----- 必要なコマンドの存在チェック -----
for cmd in ip curl jq dig python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "エラー: 必要なコマンド '$cmd' が見つかりません。インストールしてください。" >&2
    exit 1
  fi
done

#----- 1. ローカル IPv6 アドレスの取得 -----
LOCAL_IPV6=$(ip -6 addr show dev "$WAN_IFACE" scope global | awk '/inet6/ {print $2}' | awk -F'/' '{print $1}' | head -n1)
if [ -z "$LOCAL_IPV6" ]; then
  echo "エラー: WAN インターフェース ($WAN_IFACE) のグローバルIPv6アドレスが取得できません。" >&2
  exit 1
fi
echo "Obtained local IPv6 address: $LOCAL_IPV6"

#----- 2. プロビジョニングサーバの TXT レコード取得 -----
# プロビジョニングサーバ発見用 FQDN: 4over6.info
DIG_CMD="dig +short TXT 4over6.info"
if [ -n "$DNS_SERVER" ]; then
  DIG_CMD="$DIG_CMD @$DNS_SERVER"
fi
TXT_RECORD=$($DIG_CMD | sed -e 's/^"//' -e 's/"$//')
if [ -z "$TXT_RECORD" ]; then
  echo "エラー: 4over6.info の TXT レコードが取得できませんでした。" >&2
  exit 1
fi
echo "Obtained TXT record: $TXT_RECORD"

#----- 3. TXT レコードからプロビジョニングサーバ URL を抽出 -----
# TXT レコード例: v=v6mig-1 url=https://vne.example.jp/rule.cgi t=b
if ! echo "$TXT_RECORD" | grep -q "url="; then
  echo "エラー: TXTレコードにURLが含まれていません。レコード形式: $TXT_RECORD" >&2
  echo "正しいTXTレコードの例: v=v6mig-1 url=https://example.jp/rule.cgi t=b" >&2
  echo "異なるDNSサーバーを試すには DNS_SERVER 変数を設定してください。" >&2
  echo "ISPの正しいプロビジョニングサーバーに関する情報を確認してください。" >&2
  exit 1
fi

PROV_URL=$(echo "$TXT_RECORD" | awk '{for(i=1;i<=NF;i++){ if($i ~ /^url=/){split($i,a,"="); print a[2]}}}')
if [ -z "$PROV_URL" ]; then
  echo "エラー: プロビジョニングサーバの URL が TXT レコードから抽出できませんでした。" >&2
  exit 1
fi
echo "Provisioning server URL: $PROV_URL"

#----- 4. プロビジョニングサーバへ GET リクエスト送信 -----
# capability パラメータに "map_e" を指定（他の技術と併用する場合はカンマ区切りで指定可）
PROV_RESPONSE=$(curl -s "$PROV_URL/config?vendorid=$VENDORID&product=$PRODUCT&version=$VERSION&capability=map_e")
if [ -z "$PROV_RESPONSE" ]; then
  echo "エラー: プロビジョニングサーバからの応答が得られませんでした。" >&2
  exit 1
fi
echo "プロビジョニングサーバからの応答:"
echo "$PROV_RESPONSE"

#----- 5. JSON から MAP-E パラメータを抽出 -----
# 例として、最初の MAP-E ルールを利用する
MAPE_JSON=$(echo "$PROV_RESPONSE" | jq -r '.map_e')
if [ "$MAPE_JSON" = "null" ]; then
  echo "エラー: プロビジョニング応答に map_e パラメータが含まれていません。" >&2
  exit 1
fi

BR_IPV6=$(echo "$MAPE_JSON" | jq -r '.br')
RULE_IPV6=$(echo "$MAPE_JSON" | jq -r '.rules[0].ipv6')
RULE_IPV4=$(echo "$MAPE_JSON" | jq -r '.rules[0].ipv4')
EA_LENGTH=$(echo "$MAPE_JSON" | jq -r '.rules[0].ea_length')
PSID_OFFSET=$(echo "$MAPE_JSON" | jq -r '.rules[0].psid_offset')

echo "取得した MAP-E パラメータ:"
echo "  BR のIPv6アドレス: $BR_IPV6"
echo "  MAP-E ルール (IPv6プレフィックス): $RULE_IPV6"
echo "  MAP-E ルール (IPv4プレフィックス): $RULE_IPV4"
echo "  EA ビット長: $EA_LENGTH"
echo "  PSID オフセット: $PSID_OFFSET"
echo "  設定済み PSID: $PSID"

#----- 6. MAP-E クライアント用 IPv4 アドレスの計算 -----
# RULE_IPV6, RULE_IPV4 はそれぞれ CIDR 表記 (例: 2001:db8:1:2000::/52, 203.0.113.0/24)
RULE_IPV6_PREFIX=$(echo "$RULE_IPV6" | awk -F'/' '{print $1}')
RULE_IPV6_PLEN=$(echo "$RULE_IPV6" | awk -F'/' '{print $2}')
RULE_IPV4_NET=$(echo "$RULE_IPV4" | awk -F'/' '{print $1}')
RULE_IPV4_PLEN=$(echo "$RULE_IPV4" | awk -F'/' '{print $2}')

# Python を利用して MAP-E アルゴリズムに基づく IPv4 アドレスを計算
COMPUTED_IPV4=$(python3 - <<EOF
import ipaddress, sys

try:
    local_ipv6 = ipaddress.IPv6Address("$LOCAL_IPV6")
    rule_ipv6_net = ipaddress.IPv6Network("$RULE_IPV6", strict=False)
    rule_ipv4_net = ipaddress.IPv4Network("$RULE_IPV4", strict=False)
    ea_length = int("$EA_LENGTH")
    psid_offset = int("$PSID_OFFSET")
    # ユーザー設定の PSID (16進数または整数)
    try:
        psid = int("$PSID", 0)
    except:
        psid = 0

    # ローカル IPv6 アドレスがルールの IPv6 ネットワーク内にあるか確認
    if local_ipv6 not in rule_ipv6_net:
        sys.exit("Calculation error: Local IPv6 address {} is not within the IPv6 prefix of the rule {}.".format(local_ipv6, rule_ipv6_net))
    # ルールの IPv6 ネットワークのプレフィックス長から EA ビットを抽出
    shift = 128 - rule_ipv6_net.prefixlen - ea_length
    ea_mask = (1 << ea_length) - 1
    ea_bits = (int(local_ipv6) >> shift) & ea_mask

    # MAP-E の計算式:
    # クライアントIPv4アドレス = ルールの IPv4ネットワークアドレス + (ea_bits << psid_offset) + psid
    computed_ipv4_int = int(rule_ipv4_net.network_address) + (ea_bits << psid_offset) + psid
    computed_ipv4 = ipaddress.IPv4Address(computed_ipv4_int)
    print(str(computed_ipv4))
except Exception as e:
    sys.exit("Calculation error: " + str(e))
EOF
)

if [ -z "$COMPUTED_IPV4" ]; then
  echo "エラー: MAP-E クライアント用 IPv4 アドレスの計算に失敗しました。" >&2
  exit 1
fi

echo "Calculated MAP-E client IPv4 address: $COMPUTED_IPV4"

#----- 7. MAP-E トンネルインターフェースの設定 -----
# ※ここでは mape0 というトンネルインターフェースを作成する例を示す
echo "MAP-E トンネルインターフェース (mape0) を設定中..."
ip tunnel add mape0 mode mape local "$LOCAL_IPV6" remote "$BR_IPV6" || { echo "エラー: トンネルインターフェースの作成に失敗しました。"; exit 1; }
ip addr add "$COMPUTED_IPV4"/"$RULE_IPV4_PLEN" dev mape0 || { echo "エラー: トンネルインターフェースへの IPv4 アドレス設定に失敗しました。"; exit 1; }
ip link set mape0 up || { echo "エラー: トンネルインターフェースの有効化に失敗しました。"; exit 1; }
echo "MAP-E トンネルインターフェース mape0 が有効になりました。"

#----- 完了 -----
echo "MAP-E への自動接続処理が正常に完了しました。"
exit 0
