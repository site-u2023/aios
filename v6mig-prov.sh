#!/bin/sh
#===============================================================================
# IPv6マイグレーション標準プロビジョニング仕様に基づくMAP-E設定取得スクリプト
#
# このスクリプトは、DNS TXTレコードからプロビジョニングサーバのURLを取得し、
# そのサーバにアクセスしてMAP-Eの設定パラメータを取得します。
# POSIX準拠で実装されており、OpenWrt環境で動作します。
#===============================================================================

#----- 設定変数 -----
WAN_IFACE="wan"                      # WANインターフェース名
VENDORID="acde48-v6pc_swg_hgw"       # ベンダーID
PRODUCT="V6MIG-ROUTER"               # 製品名
VERSION="1_0"                        # バージョン
DNS_SERVERS="8.8.8.8 1.1.1.1"        # 代替DNSサーバーリスト（スペース区切り）
PROV_DOMAIN="4over6.info"            # プロビジョニングサーバ発見用ドメイン

# INFOメッセージ出力関数
info() {
  echo "INFO: $1" >&2
}

# エラー出力関数
error() {
  echo "エラー: $1" >&2
}

# 必要なコマンドの存在確認
for cmd in ip curl jq dig; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    error "$cmd コマンドが見つかりません。インストールしてください。"
    exit 1
  fi
done

info "Checking required commands: OK"

#----- 1. IPv6アドレスの取得 -----
get_ipv6_address() {
  info "Attempting to get IPv6 address from interface $WAN_IFACE"
  
  # OpenWrtの関数を利用
  if [ -f "/lib/functions/network.sh" ]; then
    . /lib/functions/network.sh
    . /lib/functions.sh
    network_flush_cache
    network_find_wan6 NET_IF6
    network_get_ipaddr6 NET_ADDR6 "${NET_IF6}"
    LOCAL_IPV6="$NET_ADDR6"
    info "Using OpenWrt network functions: $LOCAL_IPV6"
  else
    # 一般的な方法でグローバルIPv6アドレスを取得
    LOCAL_IPV6=$(ip -6 addr show dev "$WAN_IFACE" scope global | awk '/inet6/ {print $2}' | awk -F'/' '{print $1}' | head -n1)
    info "Using ip command: $LOCAL_IPV6"
  fi

  if [ -z "$LOCAL_IPV6" ]; then
    error "インターフェース $WAN_IFACE からIPv6アドレスを取得できませんでした"
    return 1
  fi
  
  echo "$LOCAL_IPV6"
  return 0
}

#----- 2. TXTレコード取得 -----
get_txt_record() {
  info "Retrieving TXT record from $PROV_DOMAIN"
  local txt_record=""
  local success=0
  
  # システムデフォルトのDNSサーバーでまず試行
  txt_record=$(dig +short TXT "$PROV_DOMAIN" | sed -e 's/^"//' -e 's/"$//')
  if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "v=v6mig"; then
    success=1
    info "Found valid TXT record using system DNS"
  else
    # 代替DNSサーバーを試行
    for dns in $DNS_SERVERS; do
      info "Trying alternate DNS server: $dns"
      txt_record=$(dig +short TXT "$PROV_DOMAIN" @"$dns" | sed -e 's/^"//' -e 's/"$//')
      if [ -n "$txt_record" ] && echo "$txt_record" | grep -q "v=v6mig"; then
        success=1
        info "Found valid TXT record using DNS server $dns"
        break
      fi
    done
  fi
  
  if [ "$success" = "0" ]; then
    if [ -n "$txt_record" ]; then
      error "取得したTXTレコードが正しい形式ではありません: $txt_record"
      error "期待される形式: v=v6mig-1 url=https://example.jp/rule.cgi t=b"
    else
      error "$PROV_DOMAIN からTXTレコードを取得できませんでした"
      error "お使いのISPがIPv6マイグレーション標準プロビジョニングに対応していない可能性があります"
    fi
    return 1
  fi
  
  echo "$txt_record"
  return 0
}

#----- 3. URLの抽出 -----
extract_url() {
  local txt_record="$1"
  info "Extracting URL from TXT record: $txt_record"
  
  # TXTレコードからURLを抽出
  if ! echo "$txt_record" | grep -q "url="; then
    error "TXTレコードにURLが含まれていません: $txt_record"
    error "正しい形式: v=v6mig-1 url=https://example.jp/rule.cgi t=b"
    return 1
  fi
  
  local url=$(echo "$txt_record" | awk '{for(i=1;i<=NF;i++){ if($i ~ /^url=/){split($i,a,"="); print a[2]}}}')
  
  if [ -z "$url" ]; then
    error "TXTレコードからURLを抽出できませんでした"
    return 1
  fi
  
  echo "$url"
  return 0
}

#----- 4. プロビジョニングサーバへのリクエスト -----
request_provisioning() {
  local url="$1"
  local local_ipv6="$2"
  info "Sending request to provisioning server: $url"
  
  # User-Agentとタイムアウトを設定してリクエスト送信
  local response=$(curl -s -m 10 -A "V6MIG-Client/$VERSION" \
    "$url/config?vendorid=$VENDORID&product=$PRODUCT&version=$VERSION&capability=map_e&ipv6addr=$local_ipv6")
  
  if [ -z "$response" ]; then
    error "プロビジョニングサーバからの応答がありませんでした"
    return 1
  fi
  
  # 応答がJSONかどうか確認
  if ! echo "$response" | jq . >/dev/null 2>&1; then
    error "プロビジョニングサーバからの応答がJSON形式ではありません"
    error "応答内容: $response"
    return 1
  fi
  
  echo "$response"
  return 0
}

#----- 5. MAP-Eパラメータの抽出 -----
extract_mape_params() {
  local response="$1"
  local ipv6="$2"
  info "Extracting MAP-E parameters from response"
  
  # JSONからMAP-Eパラメータを抽出
  local mape_json=$(echo "$response" | jq -r '.map_e')
  
  if [ "$mape_json" = "null" ]; then
    error "応答にMAP-Eパラメータが含まれていません"
    return 1
  fi
  
  # 各パラメータの抽出
  local br=$(echo "$mape_json" | jq -r '.br')
  local rule_ipv6=$(echo "$mape_json" | jq -r '.rules[0].ipv6')
  local rule_ipv4=$(echo "$mape_json" | jq -r '.rules[0].ipv4')
  local ea_len=$(echo "$mape_json" | jq -r '.rules[0].ea_length')
  local psid_offset=$(echo "$mape_json" | jq -r '.rules[0].psid_offset')
  local psid_len=$(echo "$mape_json" | jq -r '.rules[0].psid_len // 0')
  
  # 必須パラメータの確認
  if [ -z "$br" ] || [ "$br" = "null" ] || [ -z "$rule_ipv6" ] || [ "$rule_ipv6" = "null" ] || \
     [ -z "$rule_ipv4" ] || [ "$rule_ipv4" = "null" ] || [ -z "$ea_len" ] || [ "$ea_len" = "null" ] || \
     [ -z "$psid_offset" ] || [ "$psid_offset" = "null" ]; then
    error "必須のMAP-Eパラメータが欠けています"
    return 1
  fi
  
  # PSID自動計算（ローカルIPv6アドレスとルールから）
  local psid=""
  if [ -n "$ipv6" ]; then
    info "Calculating PSID from IPv6 address and rules"
    # ここでPSIDの計算ロジックを実装（例示のみ）
    # 実際の計算は複雑なので、プロビジョニングサーバからの値を優先する
  fi
  
  echo "BR: $br"
  echo "IPv6プレフィックス: $rule_ipv6"
  echo "IPv4プレフィックス: $rule_ipv4"
  echo "EA長: $ea_len"
  echo "PSIDオフセット: $psid_offset"
  echo "PSID長: $psid_len"
  if [ -n "$psid" ]; then
    echo "PSID: $psid（計算値）"
  fi
  
  return 0
}

#----- メイン処理 -----
main() {
  echo "=== IPv6マイグレーション標準プロビジョニング設定取得 ==="
  
  # 1. IPv6アドレス取得
  local local_ipv6=$(get_ipv6_address)
  if [ $? -ne 0 ]; then
    exit 1
  fi
  echo "グローバルIPv6アドレス: $local_ipv6"
  
  # 2. TXTレコード取得
  local txt_record=$(get_txt_record)
  if [ $? -ne 0 ]; then
    echo "TXTレコード取得に失敗しました。"
    echo "お使いのISPがIPv6マイグレーション標準プロビジョニングに対応していない可能性があります。"
    echo "手動でのMAP-E設定が必要かもしれません。"
    exit 1
  fi
  echo "TXTレコード: $txt_record"
  
  # 3. URLの抽出
  local prov_url=$(extract_url "$txt_record")
  if [ $? -ne 0 ]; then
    exit 1
  fi
  echo "プロビジョニングサーバURL: $prov_url"
  
  # 4. プロビジョニングサーバへのリクエスト
  local response=$(request_provisioning "$prov_url" "$local_ipv6")
  if [ $? -ne 0 ]; then
    exit 1
  fi
  echo "プロビジョニングサーバからの応答を受信しました"
  
  # 5. MAP-Eパラメータの抽出と表示
  echo "=== MAP-E設定パラメータ ==="
  extract_mape_params "$response" "$local_ipv6"
  
  echo ""
  echo "このスクリプトはMAP-E設定情報の取得のみを行い、実際の設定は変更していません。"
  echo "実際に設定を行うには、このスクリプトを拡張するか、手動で設定を行ってください。"
}

# メイン処理の実行
main
