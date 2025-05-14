#!/bin/sh
#===============================================================================
# NURO光 MAP-E設定スクリプト (POSIX準拠・aios連携版)
#
# 機能: NURO光向けMAP-E接続の自動設定と管理 (aios フレームワーク対応)
# バージョン: 2.1.3 (2025-04-21) # メッセージ処理を簡略化
# 元ソース: site-u2023/config-software/map-e-nuro.sh (Commit: 643a0a40)
#
# このスクリプトはPOSIX準拠でOpenWrtのash環境で動作します。
# aios の共通関数とメニューシステムを利用します。
#===============================================================================

SCRIPT_VERSION="2.1.3" # このスクリプトのバージョン

# --- aios 環境変数の確認 (aios から引き継がれる想定) ---
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# --- OpenWrt 標準ネットワークライブラリのロード (必須) ---
# aios 本体で必要な共通関数 (debug_log, get_message など) はロード済みと仮定
AIOS_NETWORK_LIB="/lib/functions/network.sh"
if [ -f "$AIOS_NETWORK_LIB" ]; then
    # shellcheck source=/dev/null
    . "$AIOS_NETWORK_LIB"
    # debug_log が利用可能と仮定してログ出力
    if command -v debug_log >/dev/null 2>&1; then
        debug_log "DEBUG" "Loaded OpenWrt network library: $AIOS_NETWORK_LIB"
    else
        echo "DEBUG: Loaded OpenWrt network library: $AIOS_NETWORK_LIB" >&2 # フォールバック
    fi
else
    echo "Error: OpenWrt network library not found: $AIOS_NETWORK_LIB" >&2
    # debug_log が利用可能ならログにも残す
    if command -v debug_log >/dev/null 2>&1; then
        debug_log "ERROR" "OpenWrt network library not found: $AIOS_NETWORK_LIB"
    fi
    # exit 1 # load されるスクリプト内での exit は避ける方が無難な場合がある
fi

# --- グローバル変数 (パターン判定で設定) ---
BR_ADDR=""
IPV6_PREFIX=""
IPV4_PREFIX=""

# --- 関数定義 ---

# IPv6アドレス正規化 (元ソースのロジックを踏襲, POSIX準拠)
# $1: 正規化するIPv6アドレス文字列
# Output: 正規化されたIPv6アドレス (8セクション、ゼロパディング、::展開済み)
# Returns: 0 on success, 1 on failure
normalize_ipv6() {
    local prefix="$1"
    local normalized=""
    local cn=0 # コロンの数

    # 入力チェック
    if [ -z "$prefix" ]; then
        # debug_log は利用可能と仮定
        debug_log "ERROR" "No IPv6 address provided to normalize_ipv6."
        printf "\033[31mError: No IPv6 address provided to normalize_ipv6.\033[0m\n" >&2
        return 1
    fi

    # プレフィックス長を除去 (念のため)
    prefix=$(echo "$prefix" | cut -d'/' -f1)

    debug_log "DEBUG" "Normalizing IPv6 (legacy logic): $prefix"

    # 1. 基本形式チェック (元ソース L13 相当)
    if ! echo "$prefix" | grep -q '[[:xdigit:]:]\{2,\}'; then
        debug_log "ERROR" "Invalid IPv6 format (basic check failed): $prefix"
        printf "\033[31mError: Invalid IPv6 format (basic check failed): %s\033[0m\n" "$prefix" >&2
        return 1
    fi

    # 2. コロン数カウント (元ソース L15)
    cn=$(echo "$prefix" | grep -o ':' | wc -l)

    # 3. コロン数範囲チェック (元ソース L16)
    if [ $cn -lt 2 ] || [ $cn -gt 7 ]; then
         debug_log "ERROR" "Invalid IPv6 format: colons ($cn) out of range 2-7 for $prefix"
         printf "\033[31mError: Invalid IPv6 format: colons (%d) out of range 2-7 for %s\033[0m\n" "$cn" "$prefix" >&2
         return 1
    fi

    # 4. sedによるゼロパディング等 (元ソース L17-24)
    #    区切り文字に '#' を使用して '/' との衝突を回避
    normalized=$(echo "$prefix" | sed -e 's#^:#0000:#' \
                                     -e 's#:$#:0000#' \
                                     -e 's#.*#:&:#e' \
                                     -e ':add0' \
                                     -e 's#:\([^:]\{1,3\}\):#:0\1:#' \
                                     -e 't add0' \
                                     -e 's#:\(.*\):#\1#')

    # 5. '::' 展開 (元ソース L25-29)
    if echo "$normalized" | grep -q '::'; then
        if [ $cn -gt 7 ]; then # このチェックは理論上不要だが元ソース互換
             debug_log "ERROR" "Internal error: Invalid IPv6 format with '::': colons ($cn) > 7 for $prefix"
             printf "\033[31mError: Internal error: Invalid IPv6 format with '::': colons (%d) > 7 for %s\033[0m\n" "$cn" "$prefix" >&2
             return 1
        fi
        local zeros_to_add=$((8 - cn))
        local zero_block_sed=""
        local i=1
        while [ $i -le $zeros_to_add ]; do
            zero_block_sed="${zero_block_sed}0000:"
            i=$((i + 1))
        done
        zero_block_sed=$(echo "$zero_block_sed" | sed 's/:$//') # 末尾コロン削除

        # sed で '::' を置換 (区切り文字に '#' を使用)
        normalized=$(echo "$normalized" | sed "s#::#:${zero_block_sed}:#")
        # 先頭・末尾のコロン削除
        normalized=$(echo "$normalized" | sed -e 's/^://' -e 's/:$//')
    else
        if [ $cn -ne 7 ]; then # '::' なしならコロンは7個のはず (元ソース L28)
            debug_log "ERROR" "Invalid IPv6 format without '::': colons ($cn) != 7 for $prefix"
            printf "\033[31mError: Invalid IPv6 format without '::': colons (%d) != 7 for %s\033[0m\n" "$cn" "$prefix" >&2
            return 1
        fi
    fi

    # 6. 最終形式チェック (8セクション、7コロン)
    local final_colons=$(echo "$normalized" | grep -o ':' | wc -l)
    local final_sections=$(echo "$normalized" | awk -F: '{print NF}')

    if [ "$final_colons" -ne 7 ] || [ "$final_sections" -ne 8 ]; then
         debug_log "ERROR" "IPv6 normalization failed final check (Expected 7 colons, 8 sections; Got $final_colons colons, $final_sections sections): $normalized"
         printf "\033[31mError: IPv6 normalization failed final check (Expected 7 colons, 8 sections; Got %d colons, %d sections): %s\033[0m\n" "$final_colons" "$final_sections" "$normalized" >&2
         return 1
    fi

    # 成功: 正規化されたアドレスを出力
    echo "$normalized"
    debug_log "DEBUG" "Normalized IPv6: $normalized"
    return 0
}

# WAN6インターフェースからIPv6プレフィックスを取得
# Output: 取得したIPv6プレフィックス文字列 (プレフィックス長なし)
# Returns: 0 on success, 1 on failure
get_ipv6_prefix_from_wan6() {
    local ipv6_pfx=""
    local net_if6=""

    # debug_log は利用可能と仮定
    debug_log "DEBUG" "Attempting to retrieve IPv6 prefix from WAN6 interface..."
    network_flush_cache # キャッシュをクリア

    # WAN6インターフェースを探す
    network_find_wan6 net_if6
    if [ -z "$net_if6" ]; then
        # 見つからない場合、デフォルト 'wan6' を試す
        net_if6="wan6"
        debug_log "DEBUG" "network_find_wan6 failed, trying default interface: $net_if6"
        # デフォルトインターフェースが存在するか確認
        if ! ip link show "$net_if6" > /dev/null 2>&1; then
             debug_log "ERROR" "WAN6 interface not found and default '$net_if6' does not exist."
             # エラーメッセージは呼び出し元で get_message を使う
             # printf "\033[31mError: WAN6 interface not found and default '%s' does not exist.\033[0m\n" "$net_if6" >&2
             return 1
        fi
    fi
    debug_log "DEBUG" "Using interface '$net_if6' to get IPv6 prefix."

    # network_get_prefix6 でプレフィックスを取得
    network_get_prefix6 ipv6_pfx "$net_if6"

    if [ -z "$ipv6_pfx" ]; then
        debug_log "ERROR" "Failed to get IPv6 prefix using network_get_prefix6 for interface '$net_if6'."
        # エラーメッセージは呼び出し元で get_message を使う
        # printf "\033[31mError: Failed to get IPv6 prefix using network_get_prefix6 for interface '%s'.\033[0m\n" "$net_if6" >&2
        return 1
    fi

    # プレフィックス長部分を除去 (例: "/64")
    ipv6_pfx=$(echo "$ipv6_pfx" | cut -d'/' -f1)

    if [ -z "$ipv6_pfx" ]; then
        # このケースは通常発生しないはずだが念のため
        debug_log "ERROR" "Failed to extract IPv6 prefix after stripping length."
        # エラーメッセージは呼び出し元で get_message を使う
        # printf "\033[31mError: Failed to extract IPv6 prefix after stripping length.\033[0m\n" >&2
        return 1
    fi

    # 成功: プレフィックスを出力
    echo "$ipv6_pfx"
    debug_log "DEBUG" "Successfully retrieved IPv6 prefix: $ipv6_pfx"
    return 0
}

# NURO光MAP-Eパターンの判定 (元ソース L205-L278 相当)
# $1: 正規化されたIPv6アドレス
# Globals: BR_ADDR, IPV6_PREFIX, IPV4_PREFIX を設定
# Returns: 0 on match, 1 on no match
detect_nuro_pattern() {
    local normalized_ipv6="$1"
    local nuro_prefix=""

    if [ -z "$normalized_ipv6" ]; then
        debug_log "ERROR" "No normalized IPv6 address provided to detect_nuro_pattern."
        printf "\033[31mError: No normalized IPv6 address provided to detect_nuro_pattern.\033[0m\n" >&2
        return 1
    fi

    # IPv6プレフィックスの最初の3セクションを取得してNUROパターン比較用の形式に整形
    nuro_prefix=$(echo "$normalized_ipv6" | cut -d':' -f1-3)
    local section3=$(echo "$nuro_prefix" | cut -d':' -f3)
    local simplified_section3=$(echo "$section3" | sed 's/^0*//; s/0*$//')
    [ -z "$simplified_section3" ] && simplified_section3="0"
    nuro_prefix=$(echo "$nuro_prefix" | cut -d':' -f1-2):${simplified_section3}
    debug_log "DEBUG" "NURO prefix for pattern matching: $nuro_prefix (from $normalized_ipv6)"

    # グローバル変数を初期化
    BR_ADDR=""
    IPV6_PREFIX=""
    IPV4_PREFIX=""

    # パターンマッチング (元ソースの case 文に相当、ハードコード)
    case "$nuro_prefix" in
        "240d:f:0") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:0000"; IPV4_PREFIX="219.104.128.0"; debug_log "DEBUG" "Matched NURO pattern 0";;
        "240d:f:1") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:1000"; IPV4_PREFIX="219.104.144.0"; debug_log "DEBUG" "Matched NURO pattern 1";;
        "240d:f:2") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:2000"; IPV4_PREFIX="219.104.160.0"; debug_log "DEBUG" "Matched NURO pattern 2";;
        "240d:f:3") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:3000"; IPV4_PREFIX="219.104.176.0"; debug_log "DEBUG" "Matched NURO pattern 3";;
        "240d:f:4") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:4000"; IPV4_PREFIX="219.104.192.0"; debug_log "DEBUG" "Matched NURO pattern 4";;
        "240d:f:5") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:5000"; IPV4_PREFIX="219.104.208.0"; debug_log "DEBUG" "Matched NURO pattern 5";;
        "240d:f:6") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:6000"; IPV4_PREFIX="219.104.224.0"; debug_log "DEBUG" "Matched NURO pattern 6";;
        "240d:f:7") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:7000"; IPV4_PREFIX="219.104.240.0"; debug_log "DEBUG" "Matched NURO pattern 7";;
        "240d:f:8") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:8000"; IPV4_PREFIX="219.105.0.0"; debug_log "DEBUG" "Matched NURO pattern 8";;
        "240d:f:9") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:9000"; IPV4_PREFIX="219.105.16.0"; debug_log "DEBUG" "Matched NURO pattern 9";;
        "240d:f:a") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:a000"; IPV4_PREFIX="219.105.32.0"; debug_log "DEBUG" "Matched NURO pattern a";;
        "240d:f:b") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:b000"; IPV4_PREFIX="219.105.48.0"; debug_log "DEBUG" "Matched NURO pattern b";;
        "240d:f:c") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:c000"; IPV4_PREFIX="219.105.64.0"; debug_log "DEBUG" "Matched NURO pattern c";;
        "240d:f:d") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:d000"; IPV4_PREFIX="219.105.80.0"; debug_log "DEBUG" "Matched NURO pattern d";;
        "240d:f:e") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:e000"; IPV4_PREFIX="219.105.96.0"; debug_log "DEBUG" "Matched NURO pattern e";;
        "240d:f:f") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:000f:f000"; IPV4_PREFIX="219.105.112.0"; debug_log "DEBUG" "Matched NURO pattern f";;
        "240d:10:0") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:0010:0000"; IPV4_PREFIX="219.105.128.0"; debug_log "DEBUG" "Matched NURO pattern 10_0";;
        "240d:10:1") BR_ADDR="2001:3b8:200:ff9::1"; IPV6_PREFIX="240d:0010:1000"; IPV4_PREFIX="219.105.144.0"; debug_log "DEBUG" "Matched NURO pattern 10_1";;
        *)
            debug_log "WARN" "Unknown NURO IPv6 prefix pattern: $nuro_prefix"
            printf "\033[31mError: This IPv6 address does not match known NURO patterns: %s.\033[0m\n" "$nuro_prefix" >&2
            return 1
            ;;
    esac

    # 正常終了
    return 0
}

# MAP-E設定適用関数 (NURO光) (元ソース _func_NURO 相当)
# Globals: BR_ADDR, IPV6_PREFIX, IPV4_PREFIX を使用
# Returns: 0 on success, 1 on failure
setup_nuro_mape() {
    local WANMAP='wanmap' # UCIセクション名 (元ソース踏襲)
    local ZONE_NO='1'     # WANファイアウォールゾーン番号 (元ソース踏襲)
    # エラー/警告メッセージ用プレフィックス (ハードコード)
    local error_prefix="\033[31mError: "
    local warning_prefix="\033[33mWarning: "
    local reset_color="\033[0m"
    local msg_prefix="" # confirm/reboot メッセージ用

    # debug_log, color, get_message は利用可能と仮定
    printf "%s\n" "$(color blue "Applying NURO MAP-E settings...")" # ハードコード
    debug_log "INFO" "Applying NURO MAP-E settings..."

    # 必須グローバル変数のチェック
    if [ -z "$BR_ADDR" ] || [ -z "$IPV6_PREFIX" ] || [ -z "$IPV4_PREFIX" ]; then
        debug_log "ERROR" "Required NURO parameters (BR_ADDR, IPV6_PREFIX, IPV4_PREFIX) are not set. Run pattern detection first."
        printf "%sRequired NURO parameters (BR_ADDR, IPV6_PREFIX, IPV4_PREFIX) are not set. Run pattern detection first.%s\n" "$error_prefix" "$reset_color" >&2
        return 1
    fi

    # mapパッケージのインストール確認
    # install_package は aios の関数と仮定
    if ! install_package map silent; then
        debug_log "ERROR" "Failed to install 'map' package."
        printf "%sFailed to install 'map' package.%s\n" "$error_prefix" "$reset_color" >&2
        return 1
    fi
    debug_log "DEBUG" "'map' package installed or already present."

    # 設定のバックアップ作成
    debug_log "DEBUG" "Backing up configuration files..."
    cp /etc/config/network /etc/config/network.nuro.bak 2>/dev/null && debug_log "DEBUG" "network backup created." || debug_log "WARN" "Failed to backup network config."
    cp /etc/config/dhcp /etc/config/dhcp.nuro.bak 2>/dev/null && debug_log "DEBUG" "dhcp backup created." || debug_log "WARN" "Failed to backup dhcp config."
    cp /etc/config/firewall /etc/config/firewall.nuro.bak 2>/dev/null && debug_log "DEBUG" "firewall backup created." || debug_log "WARN" "Failed to backup firewall config."

    # --- UCI 設定 (個別コマンド形式 - ベタ書き) ---
    debug_log "DEBUG" "Applying NURO MAP-E configuration using individual UCI commands"

    # DHCP LAN (元ソース尊重)
    uci set dhcp.lan.ra='relay'
    uci set dhcp.lan.dhcpv6='server'
    uci set dhcp.lan.ndp='relay'
    uci set dhcp.lan.force='1'

    # WAN (元ソース尊重)
    uci set network.wan.auto='1'

    # DHCP WAN6 (共通設定)
    uci set dhcp.wan6=dhcp
    uci set dhcp.wan6.master='1'
    uci set dhcp.wan6.ra='relay'
    uci set dhcp.wan6.dhcpv6='relay'
    uci set dhcp.wan6.ndp='relay'

    # WANMAP (共通設定)
    uci set network.${WANMAP}=interface
    uci set network.${WANMAP}.proto='map'
    uci set network.${WANMAP}.maptype='map-e'
    uci set network.${WANMAP}.peeraddr="${BR_ADDR}"
    uci set network.${WANMAP}.ipaddr="${IPV4_PREFIX}" # 元ソース尊重
    uci set network.${WANMAP}.ip4prefixlen='20'
    uci set network.${WANMAP}.ip6prefix="${IPV6_PREFIX}::"
    uci set network.${WANMAP}.ip6prefixlen='36'
    uci set network.${WANMAP}.ealen='20'
    uci set network.${WANMAP}.psidlen='8'
    uci set network.${WANMAP}.offset='4'
    uci set network.${WANMAP}.mtu='1452'
    uci set network.${WANMAP}.encaplimit='ignore'

    # OSバージョン固有設定 (internet-map-e.sh のロジックを使用, 設定値はNURO用)
    local osversion=""
    if [ -f "${CACHE_DIR}/osversion.ch" ]; then
        osversion=$(cat "${CACHE_DIR}/osversion.ch")
        debug_log "DEBUG" "Detected OS Version from cache: $osversion"
    else
        debug_log "WARN" "OS version cache file not found. Applying default settings (assuming non-19)."
        osversion="unknown" # 不明な場合、19以外として扱う
    fi

    if [ "$osversion" = "19" ]; then
        # OpenWrt 19
        debug_log "DEBUG" "Applying OpenWrt 19 specific setting: add_list network.${WANMAP}.tunlink='wan6'"
        # 既に追加されていないか確認してから追加
        local current_tunlinks
        current_tunlinks=$(uci -q get network.${WANMAP}.tunlink 2>/dev/null)
        if ! echo " $current_tunlinks " | grep -q " wan6 "; then
             uci add_list network.${WANMAP}.tunlink='wan6'
        else
             debug_log "DEBUG" "tunlink 'wan6' already exists for network.${WANMAP}. Skipping add_list."
        fi
    else
        # OpenWrt 19 以外 (または不明): NURO用設定
        debug_log "DEBUG" "Applying OpenWrt non-19 specific UCI settings."
        uci set dhcp.wan6.ignore='1'
        uci set network.${WANMAP}.legacymap='1'
        uci set network.${WANMAP}.tunlink='wan6'
    fi

    # ファイアウォール設定 (個別 UCI コマンド, 元ソース尊重)
    debug_log "DEBUG" "Configuring firewall zone $ZONE_NO..."
    local current_fw_networks
    current_fw_networks=$(uci -q get firewall.@zone["$ZONE_NO"].network 2>/dev/null)
    # 'wan' を削除
    if echo " $current_fw_networks " | grep -q " wan "; then
        debug_log "DEBUG" "Removing 'wan' from firewall zone $ZONE_NO network list."
        uci del_list firewall.@zone["$ZONE_NO"].network='wan'
    fi
    # '${WANMAP}' を追加 (存在しない場合のみ)
    if ! echo " $current_fw_networks " | grep -q " $WANMAP "; then
        debug_log "DEBUG" "Adding '$WANMAP' to firewall zone $ZONE_NO network list."
        uci add_list firewall.@zone["$ZONE_NO"].network="$WANMAP"
    fi

    # DNS設定 (個別 UCI コマンド, 元ソース尊重)
    debug_log "DEBUG" "Applying DNS settings..."
    # 既存のリスト/オプションを削除
    uci -q delete dhcp.lan.dns
    uci -q delete dhcp.lan.dhcp_option

    # IPv4 DNS
    uci add_list network.lan.dns='118.238.201.33'
    uci add_list network.lan.dns='152.165.245.17'
    uci add_list dhcp.lan.dhcp_option='6,1.1.1.1,8.8.8.8'
    uci add_list dhcp.lan.dhcp_option='6,1.0.0.1,8.8.4.4'

    # IPv6 DNS
    uci add_list network.lan.dns='240d:0010:0004:0005::33'
    uci add_list network.lan.dns='240d:12:4:1b01:152:165:245:17'
    uci add_list dhcp.lan.dns='2606:4700:4700::1111'
    uci add_list dhcp.lan.dns='2001:4860:4860::8888'
    uci add_list dhcp.lan.dns='2606:4700:4700::1001'
    uci add_list dhcp.lan.dns='2001:4860:4860::8844'

    # 最後にコミット (元ソースと同じ)
    debug_log "DEBUG" "Committing all UCI changes..."
    uci commit
    local uci_commit_status=$?
    if [ $uci_commit_status -ne 0 ]; then
        debug_log "ERROR" "UCI commit failed with status $uci_commit_status."
        printf "%sUCI commit failed.%s\n" "$error_prefix" "$reset_color" >&2
        # 失敗した場合も続行する（元ソースにはエラーチェックがない）
    fi

    # --- 完了メッセージと情報表示 (一部ハードコード化) ---
    printf "\n%s\n" "$(color green "$(get_message "MSG_NURO_APPLY_SUCCESS")")" # 設定完了＆再起動要求
    printf "%s\n" "$(color cyan "Applied MAP-E Parameters:")" # ハードコード
    printf "  Border Relay (BR): %s\n" "$BR_ADDR" # ハードコード
    printf "  IPv6 Prefix (Rule): %s::/36\n" "$IPV6_PREFIX" # ハードコード
    printf "  IPv4 Prefix (Rule): %s/20\n" "$IPV4_PREFIX" # ハードコード
    printf "  EA-bits length: 20\n" # ハードコード
    printf "  PSID length: 8\n" # ハードコード
    printf "  PSID offset: 4\n" # ハードコード
    printf "  MTU: 1452\n" # ハードコード
    printf "\n"

    # --- 再起動確認 (confirm の引数をハードコード化) ---
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi

    local confirm_reboot=1
    # confirm は aios の関数と仮定 (質問文はハードコード)
    confirm "Do you want to reboot now? {ynr}" # ハードコード
    confirm_reboot=$?

    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%sRebooting the device...\n" "$msg_prefix" # ハードコード
        # reboot は aios の関数と仮定
        reboot # 即時再起動
        exit 0 # reboot が失敗した場合に備えて exit
    elif [ $confirm_reboot -eq 2 ]; then # Return
         printf "%sReturning to menu.\n" "$msg_prefix" # ハードコード
         return 0 # メニューに戻る (成功扱い)
    else # No
        printf "%sSettings applied. Please reboot the device later.\n" "$msg_prefix" # ハードコード
        return 0 # メニューに戻る (成功扱い)
    fi
}

# 設定復元関数 (元ソース _func_RECOVERY 相当, menu.db 指定の関数名)
# Returns: 0 on success, 1 on failure
restore_mape_nuro_settings() {
    local msg_prefix=""
    # エラー/警告メッセージ用プレフィックス (ハードコード)
    local error_prefix="\033[31mError: "
    local warning_prefix="\033[33mWarning: "
    local reset_color="\033[0m"

    # debug_log, color, get_message は利用可能と仮定
    printf "%s\n" "$(color blue "Restoring previous settings from NURO backup...")" # ハードコード
    debug_log "INFO" "Attempting to restore configuration from NURO backups..."

    local network_bak="/etc/config/network.nuro.bak"
    local dhcp_bak="/etc/config/dhcp.nuro.bak"
    local firewall_bak="/etc/config/firewall.nuro.bak"
    local restore_failed=0

    # バックアップファイルの存在確認
    if [ ! -f "$network_bak" ] && [ ! -f "$dhcp_bak" ] && [ ! -f "$firewall_bak" ]; then
        debug_log "ERROR" "Backup files (.nuro.bak) not found. Cannot restore."
        printf "%sBackup files (.nuro.bak) not found. Cannot restore.%s\n" "$error_prefix" "$reset_color" >&2 # ハードコード
        return 1 # 失敗としてメニュー終了
    fi

    # 各ファイルを復元
    if [ -f "$network_bak" ]; then
        if cp "$network_bak" /etc/config/network; then
            debug_log "DEBUG" "Restored /etc/config/network from $network_bak"
        else
            debug_log "WARN" "Failed to restore /etc/config/network."
            printf "%sFailed to restore /etc/config/network.%s\n" "$warning_prefix" "$reset_color" >&2
            restore_failed=1
        fi
    fi
    if [ -f "$dhcp_bak" ]; then
        if cp "$dhcp_bak" /etc/config/dhcp; then
            debug_log "DEBUG" "Restored /etc/config/dhcp from $dhcp_bak"
        else
            debug_log "WARN" "Failed to restore /etc/config/dhcp."
            printf "%sFailed to restore /etc/config/dhcp.%s\n" "$warning_prefix" "$reset_color" >&2
            restore_failed=1
        fi
    fi
    if [ -f "$firewall_bak" ]; then
        if cp "$firewall_bak" /etc/config/firewall; then
            debug_log "DEBUG" "Restored /etc/config/firewall from $firewall_bak"
        else
            debug_log "WARN" "Failed to restore /etc/config/firewall."
            printf "%sFailed to restore /etc/config/firewall.%s\n" "$warning_prefix" "$reset_color" >&2
            restore_failed=1
        fi
    fi

    if [ $restore_failed -eq 0 ]; then
        printf "%s\n" "$(color green "Previous settings restored successfully.")" # ハードコード
    else
        printf "%s\n" "$(color yellow "Previous settings partially restored. Check logs for details.")" # ハードコード
    fi

    # --- 再起動確認 (confirm の引数をハードコード化) ---
    printf "\nReboot is required to apply the settings.\n" # ハードコード
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi

    local confirm_reboot=1
    confirm "Do you want to reboot now? {ynr}" # ハードコード
    confirm_reboot=$?

    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%sRebooting the device...\n" "$msg_prefix" # ハードコード
        reboot
        exit 0
    elif [ $confirm_reboot -eq 2 ]; then # Return
         printf "%sReturning to menu.\n" "$msg_prefix" # ハードコード
         return 0 # メニューに戻る
    else # No
        printf "%sSettings restored. Please reboot the device later.\n" "$msg_prefix" # ハードコード
        return 0 # メニューに戻る
    fi
}

# マルチセッション対応パッチ適用関数 (元ソース _func_NICHIBAN 相当)
# Returns: 0 on success, 1 on failure
setup_multisession_patch() {
    local map_sh_path="/lib/netifd/proto/map.sh"
    local map_sh_bak="${map_sh_path}.old"
    local patch_url_base="https://raw.githubusercontent.com/site-u2023/map-e/main"
    local patch_url=""
    local msg_prefix=""
    # Error/Warning prefixes (hardcoded English)
    local error_prefix="\033[31mError: "
    local warning_prefix="\033[33mWarning: "
    local reset_color="\033[0m"

    # debug_log, color, get_message は利用可能と仮定
    printf "%s\n" "$(color blue "Applying multi-session patch (map.sh)...")" # ハードコード
    debug_log "INFO" "Applying multi-session patch (map.sh)..."

    # 元ファイルのバックアップ
    if [ -f "$map_sh_path" ]; then
        if cp "$map_sh_path" "$map_sh_bak"; then
            debug_log "DEBUG" "Backed up $map_sh_path to $map_sh_bak"
        else
            debug_log "WARN" "Failed to backup original $map_sh_path."
            printf "%sFailed to backup original %s.%s\n" "$warning_prefix" "$map_sh_path" "$reset_color" >&2
            # Continue but warn
        fi
    else
        debug_log "WARN" "Original $map_sh_path not found. Cannot create backup."
        printf "%sOriginal %s not found. Cannot create backup.%s\n" "$warning_prefix" "$map_sh_path" "$reset_color" >&2
        # Continue but warn
    fi

    # Get OpenWrt version (using cached value - internet-map-e.sh logic)
    local osversion=""
    if [ -f "${CACHE_DIR}/osversion.ch" ]; then
        osversion=$(cat "${CACHE_DIR}/osversion.ch")
        debug_log "DEBUG" "Detected OS Version from cache for patch: $osversion"
    else
         # osversion.ch がない場合、エラーとして処理を中断
         debug_log "ERROR" "OS version cache file (${CACHE_DIR}/osversion.ch) not found. Cannot determine correct patch URL."
         printf "%sOS version cache file not found. Cannot determine correct patch URL.%s\n" "$error_prefix" "$reset_color" >&2
         return 1 # Fail and exit menu
    fi

    # Select patch URL based on version (using requested if/else logic)
    if [ "$osversion" = "19" ]; then
        patch_url="${patch_url_base}/map19.sh.new"
        debug_log "DEBUG" "Selected patch URL for OpenWrt 19."
    else
        # Version 19以外 (または osversion.ch が空だった場合もこちら)
        patch_url="${patch_url_base}/map.sh.new"
        debug_log "DEBUG" "Selected patch URL for OpenWrt non-19 (or unknown)."
    fi
    debug_log "DEBUG" "Using patch URL: $patch_url"

    # Download patch file using aios wget options
    # WGET_IPV_OPT is assumed to be set by aios main script
    # wget は aios の関数と仮定
    if ! wget -q --no-check-certificate ${WGET_IPV_OPT:-} -O "$map_sh_path" "$patch_url" 2>/dev/null; then
        debug_log "ERROR" "Failed to download multi-session patch script from $patch_url."
        printf "%sFailed to download multi-session patch.%s\n" "$error_prefix" "$reset_color" >&2 # ハードコード
        # Try restoring from backup if download failed
        if [ -f "$map_sh_bak" ]; then
             cp "$map_sh_bak" "$map_sh_path" 2>/dev/null
             debug_log "DEBUG" "Restored original map.sh due to download failure."
        fi
        return 1 # Fail and exit menu
    fi

    # Success message
    printf "%s\n" "$(color green "Multi-session patch applied successfully.")" # ハードコード

    # --- Reboot confirmation (confirm の引数をハードコード化) ---
    printf "\nReboot is required to apply the settings.\n" # ハードコード
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi

    local confirm_reboot=1
    confirm "Do you want to reboot now? {ynr}" # ハードコード
    confirm_reboot=$?

    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%sRebooting the device...\n" "$msg_prefix" # ハードコード
        reboot
        exit 0
    elif [ $confirm_reboot -eq 2 ]; then # Return
         printf "%sReturning to menu.\n" "$msg_prefix" # ハードコード
         return 0 # Return to menu
    else # No
        printf "%sPatch applied. Please reboot the device later.\n" "$msg_prefix" # ハードコード
        return 0 # Return to menu
    fi
}

# マルチセッション対応パッチ復元関数 (元ソース _func_NICHIBAN_RECOVERY 相当)
# Returns: 0 on success, 1 on failure
restore_multisession_patch() {
    local map_sh_path="/lib/netifd/proto/map.sh"
    local map_sh_bak="${map_sh_path}.old"
    local msg_prefix=""
    # Error/Warning prefixes (hardcoded English)
    local error_prefix="\033[31mError: "
    local warning_prefix="\033[33mWarning: "
    local reset_color="\033[0m"

    # debug_log, color, get_message は利用可能と仮定
    printf "%s\n" "$(color blue "Restoring original map.sh from backup...")" # ハードコード
    debug_log "INFO" "Restoring original map.sh from backup..."

    # Check if backup file exists
    if [ ! -f "$map_sh_bak" ]; then
        debug_log "ERROR" "Backup file ($map_sh_bak) not found. Cannot restore."
        printf "%sBackup file (map.sh.old) not found. Cannot restore.%s\n" "$error_prefix" "$reset_color" >&2 # ハードコード
        return 1 # Fail and exit menu
    fi

    # Restore from backup
    if cp "$map_sh_bak" "$map_sh_path"; then
        printf "%s\n" "$(color green "Original map.sh restored successfully.")" # ハードコード
        debug_log "DEBUG" "Restored $map_sh_path from $map_sh_bak"
    else
        debug_log "ERROR" "Failed to restore $map_sh_path from backup $map_sh_bak."
        printf "%sFailed to restore %s from backup.%s\n" "$error_prefix" "$map_sh_path" "$reset_color" >&2
        return 1 # Fail and exit menu
    fi

    # --- Reboot confirmation (confirm の引数をハードコード化) ---
    printf "\nReboot is required to apply the settings.\n" # ハードコード
    if command -v color >/dev/null 2>&1; then msg_prefix=$(color blue "- "); fi

    local confirm_reboot=1
    confirm "Do you want to reboot now? {ynr}" # ハードコード
    confirm_reboot=$?

    if [ $confirm_reboot -eq 0 ]; then # Yes
        printf "%sRebooting the device...\n" "$msg_prefix" # ハードコード
        reboot
        exit 0
    elif [ $confirm_reboot -eq 2 ]; then # Return
         printf "%sReturning to menu.\n" "$msg_prefix" # ハードコード
         return 0 # Return to menu
    else # No
        printf "%sOriginal map.sh restored. Please reboot the device later.\n" "$msg_prefix" # ハードコード
        return 0 # Return to menu
    fi
}

# 利用可能ポート確認関数 (元ソース _func_NICHIBAN_PORT 相当)
# Returns: 0 (always returns to menu)
check_multisession_ports() {
    local rules_file="/tmp/map-wanmap.rules"
    local port_info=""
    local msg_prefix=""
    # Error/Warning prefixes (hardcoded English)
    local error_prefix="\033[31mError: "
    # local warning_prefix="\033[33mWarning: " # 未使用
    local reset_color="\033[0m"

    # debug_log, color, get_message は利用可能と仮定
    debug_log "DEBUG" "Checking available ports from $rules_file..."

    # Check if rules file exists
    if [ ! -f "$rules_file" ]; then
        debug_log "WARN" "MAP-E rules file ($rules_file) not found. Apply MAP-E settings first."
        printf "%sMAP-E rules file not found. Apply MAP-E settings first.%s\n" "$error_prefix" "$reset_color" >&2 # ハードコード
        # Prompt user to press Enter to return to menu
        printf "\nPress Enter to return to the menu..." # ハードコード
        read -r _ # Discard input
        return 0 # Return to menu
    fi

    # Extract port information
    port_info=$(cat "$rules_file" | grep 'PORTSETS' 2>/dev/null)

    printf "\n%s\n" "$(color cyan "Available MAP-E Ports:")" # ハードコード
    if [ -n "$port_info" ]; then
        # Port info found, display it
        printf "%s\n" "$port_info" # 変数を直接表示
        debug_log "DEBUG" "Port information found: $port_info"
    else
        # Port info not found in the file
        printf "%s\n" "$(color yellow "No port information (PORTSETS) found in the rules file.")" # ハードコード
        debug_log "DEBUG" "No PORTSETS line found in $rules_file"
    fi

    # Prompt user to press Enter to return to menu
    printf "\nPress Enter to return to the menu..." # ハードコード
    read -r _ # Discard input
    return 0 # Always return to menu
}

# --- メイン処理関数 (ロード時に末尾から呼ばれる) ---
nuro_mape_main() {
    # debug_log, color, get_message は利用可能と仮定
    debug_log "INFO" "Executing nuro_mape_main function (called from script end)..."

    # ローカル変数を定義 (POSIX準拠のため、関数内でlocal宣言)
    local ipv6_raw=""
    local ipv6_normalized=""
    # BR_ADDR, IPV6_PREFIX, IPV4_PREFIX は detect_nuro_pattern でグローバル変数として設定される

    # 1. Get IPv6 address
    printf "%s\n" "$(color blue "Getting IPv6 prefix from WAN interface...")" # ハードコード
    ipv6_raw=$(get_ipv6_prefix_from_wan6)
    if [ $? -ne 0 ] || [ -z "$ipv6_raw" ]; then
        debug_log "ERROR" "Failed to retrieve IPv6 address. Aborting nuro_mape_main."
        printf "%s%s%s\n" "$(color red "$(get_message "MSG_NURO_GET_IPV6_FAIL")")" >&2 # get_message 使用
        return 1 # 関数からエラー終了
    fi

    # 2. Normalize IPv6 address
    ipv6_normalized=$(normalize_ipv6 "$ipv6_raw")
    if [ $? -ne 0 ] || [ -z "$ipv6_normalized" ]; then
        debug_log "ERROR" "Failed to normalize IPv6 address: $ipv6_raw. Aborting nuro_mape_main."
        printf "\033[31mError: Failed to normalize IPv6 address.\033[0m\n" >&2 # ハードコード
        return 1 # 関数からエラー終了
    fi
    printf "Detected IPv6 Address: %s\n" "$ipv6_normalized" # ハードコード

    # 3. Detect NURO pattern
    printf "%s\n" "$(color blue "Detecting NURO MAP-E pattern...")" # ハードコード
    if ! detect_nuro_pattern "$ipv6_normalized"; then
        # エラーメッセージは detect_nuro_pattern 内で表示済み
        debug_log "ERROR" "This IPv6 address does not match known NURO patterns: $ipv6_normalized. Aborting nuro_mape_main."
        # printf "%s%s%s\n" "$(color red "This IPv6 address does not match known NURO patterns.")" >&2 # ハードコード
        return 1 # 関数からエラー終了
    fi
    printf "%s\n" "$(color green "NURO MAP-E pattern detected successfully.")" # ハードコード
    printf "  BR: %s, IPv6: %s::/36, IPv4: %s/20\n" "$BR_ADDR" "$IPV6_PREFIX" "$IPV4_PREFIX" # Simple display (ハードコード)

    # 4. Apply settings (calls setup_nuro_mape)
    # setup_nuro_mape は内部で reboot/return 0 を処理する
    setup_nuro_mape
    # setup_nuro_mape の戻り値に関わらず、nuro_mape_main としては正常終了扱いとする
    # (エラーは setup_nuro_mape 内で表示される)
    return 0
}

# --- スクリプト末尾でメイン関数を呼び出す ---
nuro_mape_main
