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
DNS_SERVER=""                        # DNSサーバー（空の場合はデフォルト使用）
DEBUG=1                              # デバッグ出力（1=有効, 0=無効）

# デバッグ情報出力関数
debug() {
  [ "$DEBUG" = "1" ] && echo "DEBUG: $1" >&2
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

debug "Checking required commands: OK"

#----- 1. IPv6アドレスの取得 -----
get_ipv6_address() {
  debug "Attempting to get IPv6 address from interface $WAN_IFACE"
  
  # OpenWrtの関数を利用
  if [ -f "/lib/functions/network.sh" ]; then
    . /lib/functions/network.sh
    . /lib/functions.sh
    network_flush_cache
    network_find_wan6 NET_IF6
    network_get_ipaddr6 NET_ADDR6 "${NET_IF6}"
    LOCAL_IPV6="$NET_ADDR6"
    debug "Using OpenWrt network functions: $LOCAL_IPV6"
  else
    # 一般的な方法でグローバルIPv6アドレスを取得
    LOCAL_IPV6=$(ip -6 addr show dev "$WAN_IFACE" scope global | awk '/inet6/ {print $2}' | awk -F'/' '{print $1}' | head -n1)
    debug "Using ip command: $LOCAL_IPV6"
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
  debug "Retrieving TXT record from 4over6.info"
  local dig_cmd="dig +short TXT 4over6.info"
  
  # カスタムDNSサーバーの指定
  if [ -n "$DNS_SERVER" ]; then
    dig_cmd="$dig_cmd @$DNS_SERVER"
    debug "Using custom DNS server: $DNS_SERVER"
  fi
  
  # TXTレコードの取得と引用符の除去
  local txt_record=$(eval "$dig_cmd" | sed -e 's/^"//' -e 's/"$//')
  
  if [ -z "$txt_record" ]; then
    error "4over6.info からTXTレコードを取得できませんでした"
    return 1
  fi
  
  echo "$txt_record"
  return 0
}

#----- 3. URLの抽出 -----
extract_url() {
  local txt_record="$1"
  debug "Extracting URL from TXT record: $txt_record"
  
  # TXTレコードからURLを抽出
  if ! echo "$txt_record" | grep -q "url="; then
    error "TXTレコードにURLが含まれていません: $txt_record"
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
  debug "Sending request to provisioning server: $url"
  
  # プロビジョニングサーバへGETリクエスト送信
  local response=$(curl -s "$url/config?vendorid=$VENDORID&product=$PRODUCT&version=$VERSION&capability=map_e&ipv6addr=$local_ipv6")
  
  if [ -z "$response" ]; then
    error "プロビジョニングサーバからの応答がありませんでした"
    return 1
  fi
  
  echo "$response"
  return 0
}

#----- 5. MAP-Eパラメータの抽出 -----
extract_mape_params() {
  local response="$1"
  debug "Extracting MAP-E parameters from response"
  
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
  if [ -z "$br" ] || [ -z "$rule_ipv6" ] || [ -z "$rule_ipv4" ] || [ -z "$ea_len" ] || [ -z "$psid_offset" ]; then
    error "必須のMAP-Eパラメータが欠けています"
    return 1
  fi
  
  # PSID計算（必要ならローカルIPv6アドレスから計算可能）
  local ipv6="$2"
  local psid="不明（手動設定が必要です）"
  
  echo "BR: $br"
  echo "IPv6プレフィックス: $rule_ipv6"
  echo "IPv4プレフィックス: $rule_ipv4"
  echo "EA長: $ea_len"
  echo "PSIDオフセット: $psid_offset"
  echo "PSID長: $psid_len"
  echo "PSID: $psid"
  
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
  echo "プロビジョニングサーバからの応答:"
  echo "$response" | jq '.'
  
  # 5. MAP-Eパラメータの抽出
  echo "=== MAP-E設定パラメータ ==="
  extract_mape_params "$response" "$local_ipv6"
  
  echo "このスクリプトはMAP-E設定情報の取得のみを行い、実際の設定は変更していません。"
}

# メイン処理の実行
main
