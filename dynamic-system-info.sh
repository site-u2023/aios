#!/bin/sh

SCRIPT_VERSION="2025.03.14-01-01"

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

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="wget --no-check-certificate -q -O"
# BASE_WGET="wget -O"
DEBUG_MODE="${DEBUG_MODE:-false}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
ARCHITECTURE="${CACHE_DIR}/architecture.ch"
OSVERSION="${CACHE_DIR}/osversion.ch"
PACKAGE_MANAGER="${CACHE_DIR}/package_manager.ch"
PACKAGE_EXTENSION="${CACHE_DIR}/extension.ch"

# wget関連設定
BASE_WGET="wget --no-check-certificate -q -O" # 基本wgetコマンド

check_network_connectivity() {
    local ip_check_file="${CACHE_DIR}/network.ch"
    local ret4=1
    local ret6=1

    debug_log "DEBUG: Checking IPv4 connectivity"
    ping -c 1 -w 3 8.8.8.8 >/dev/null 2>&1
    ret4=$?

    debug_log "DEBUG: Checking IPv6 connectivity"
    ping6 -c 1 -w 3 2001:4860:4860::8888 >/dev/null 2>&1
    ret6=$?

    if [ "$ret4" -eq 0 ] && [ "$ret6" -eq 0 ]; then
        echo "v4v6" > "${ip_check_file}"
    elif [ "$ret4" -eq 0 ]; then
        echo "v4" > "${ip_check_file}"
    elif [ "$ret6" -eq 0 ]; then
        echo "v6" > "${ip_check_file}"
    else
        echo "" > "${ip_check_file}"
    fi
}

# キャッシュファイルの存在と有効性を確認する関数
check_location_cache() {
    local cache_language="${CACHE_DIR}/language.ch"
    local cache_luci="${CACHE_DIR}/luci.ch"
    local cache_timezone="${CACHE_DIR}/timezone.ch"
    local cache_zonename="${CACHE_DIR}/zonename.ch"
    local cache_message="${CACHE_DIR}/message.ch"
    
    debug_log "DEBUG" "Checking location cache files"
    
    # すべての必要なキャッシュファイルが存在するか確認
    if [ -f "$cache_language" ] && [ -f "$cache_luci" ] && [ -f "$cache_timezone" ] && [ -f "$cache_zonename" ] && [ -f "$cache_message" ]; then
        # すべてのファイルの内容が空でないか確認
        if [ -s "$cache_language" ] && [ -s "$cache_luci" ] && [ -s "$cache_timezone" ] && [ -s "$cache_zonename" ] && [ -s "$cache_message" ]; then
            debug_log "DEBUG" "Valid location cache files found"
            return 0  # キャッシュ有効
        else
            debug_log "DEBUG" "One or more cache files are empty"
        fi
    else
        debug_log "DEBUG" "One or more required cache files are missing"
    fi
    
    return 1  # キャッシュ無効または不完全
}

# 国コードとタイムゾーン情報を取得する関数
get_country_code() {
    # 変数宣言
    local ip_address=""
    local network_type=""
    local timeout_sec=15
    local tmp_file=""
    local spinner_pid=0
    local api_url=""
    
    # API URLの定数化
    local API_IPV4="https://api.ipify.org"
    local API_IPV6="https://api64.ipify.org"
    local API_WORLDTIME="http://worldtimeapi.org/api/ip"
    local API_IPAPI="http://ip-api.com/json"
    
    # グローバル変数の初期化
    SELECT_ZONE=""
    SELECT_ZONENAME=""
    SELECT_TIMEZONE=""
    SELECT_COUNTRY=""
    SELECT_POSIX_TZ=""
    
    # キャッシュディレクトリの確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"
    
    # ネットワーク接続状況の取得
    if [ -f "${CACHE_DIR}/network.ch" ]; then
        network_type=$(cat "${CACHE_DIR}/network.ch")
        debug_log "DEBUG" "Network connectivity type detected: $network_type"
    else
        debug_log "DEBUG" "Network connectivity information not available"
        network_type="v4"  # デフォルトでIPv4を試行
    fi
    
    # スピナー開始
    start_spinner
    spinner_pid=$!
    debug_log "DEBUG" "Starting IP and location detection process"
    
    # ネットワークタイプに応じてIPアドレス取得API選択
    if [ "$network_type" = "v6" ] || [ "$network_type" = "v4v6" ]; then
        # IPv6優先
        network_label="IPv6"
        api_url="$API_IPV6"
    else
        # IPv4
        network_label="IPv4"
        api_url="$API_IPV4"
    fi
    
    # IPアドレスの取得
    get_message "MSG_QUERY_INFO" "type=IP address" "api=ipify.org" "network=$network_label"
    debug_log "DEBUG" "Querying IP address from ipify.org via $network_label"
    
    tmp_file="$(mktemp -t location.XXXXXX)"
    $BASE_WGET "$tmp_file" "$api_url" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
    
    if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        ip_address=$(cat "$tmp_file")
        rm -f "$tmp_file"
        debug_log "DEBUG" "Retrieved IP address: $ip_address from ipify.org via $network_label"
    else
        debug_log "DEBUG" "IP address query failed via $network_label"
        rm -f "$tmp_file" 2>/dev/null
        
        # v4v6環境でネットワークを切り替え
        if [ "$network_type" = "v4v6" ]; then
            if [ "$network_label" = "IPv6" ]; then
                network_label="IPv4"
                api_url="$API_IPV4"
            else
                network_label="IPv6"
                api_url="$API_IPV6"
            fi
            
            get_message "MSG_QUERY_INFO" "type=IP address" "api=ipify.org" "network=$network_label"
            debug_log "DEBUG" "Trying alternative network: Querying IP address from ipify.org via $network_label"
            
            tmp_file="$(mktemp -t location.XXXXXX)"
            $BASE_WGET "$tmp_file" "$api_url" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
            
            if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
                ip_address=$(cat "$tmp_file")
                rm -f "$tmp_file"
                debug_log "DEBUG" "Retrieved IP address: $ip_address from ipify.org via $network_label"
            else
                debug_log "DEBUG" "IP address query failed with alternative network too"
                rm -f "$tmp_file" 2>/dev/null
            fi
        fi
    fi
    
    # IPアドレスが取得できたかチェック
    if [ -z "$ip_address" ]; then
        debug_log "DEBUG" "Failed to retrieve any IP address"
        stop_spinner "$spinner_pid"
        get_message "MSG_LOCATION_RESULT" "status=failed"
        return 1
    fi
    
    # 国コードの取得
    get_message "MSG_QUERY_INFO" "type=country code" "api=ip-api.com" "network=$network_label"
    debug_log "DEBUG" "Querying country code from ip-api.com via $network_label"
    
    tmp_file="$(mktemp -t location.XXXXXX)"
    $BASE_WGET "$tmp_file" "${API_IPAPI}/${ip_address}" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
    
    if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        SELECT_COUNTRY=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
        debug_log "DEBUG" "Retrieved country code: $SELECT_COUNTRY from ip-api.com via $network_label"
        rm -f "$tmp_file"
    else
        debug_log "DEBUG" "Country code query failed"
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    # タイムゾーン情報の取得
    get_message "MSG_QUERY_INFO" "type=timezone" "api=worldtimeapi.org" "network=$network_label"
    debug_log "DEBUG" "Querying timezone from worldtimeapi.org via $network_label"
    
    tmp_file="$(mktemp -t location.XXXXXX)"
    $BASE_WGET "$tmp_file" "$API_WORLDTIME" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
    
    if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        SELECT_ZONENAME=$(grep -o '"timezone":"[^"]*' "$tmp_file" | sed 's/"timezone":"//')
        SELECT_TIMEZONE=$(grep -o '"abbreviation":"[^"]*' "$tmp_file" | sed 's/"abbreviation":"//')
        local utc_offset=$(grep -o '"utc_offset":"[^"]*' "$tmp_file" | sed 's/"utc_offset":"//')
        
        debug_log "DEBUG" "Retrieved timezone data: $SELECT_ZONENAME ($SELECT_TIMEZONE), UTC offset: $utc_offset from worldtimeapi.org via $network_label"
        
        # POSIX形式のタイムゾーン文字列を生成
        if [ -n "$SELECT_TIMEZONE" ] && [ -n "$utc_offset" ]; then
            local offset_sign=$(echo "$utc_offset" | cut -c1)
            local offset_hours=$(echo "$utc_offset" | cut -c2-3 | sed 's/^0//')
            
            if [ "$offset_sign" = "+" ]; then
                # +9 -> -9（POSIXでは符号が反転）
                SELECT_POSIX_TZ="${SELECT_TIMEZONE}-${offset_hours}"
            else
                # -5 -> 5（POSIXではプラスの符号は省略）
                SELECT_POSIX_TZ="${SELECT_TIMEZONE}${offset_hours}"
            fi
            
            debug_log "DEBUG" "Generated POSIX timezone: $SELECT_POSIX_TZ"
        fi
        rm -f "$tmp_file"
    else
        debug_log "DEBUG" "Timezone query failed"
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    # スピナー停止と最終結果の表示
    stop_spinner "$spinner_pid"
    
    # 結果のチェック
    if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ]; then
        get_message "MSG_LOCATION_RESULT" "status=completed successfully"
        debug_log "DEBUG" "Location information process completed with status: success"
        return 0
    else
        get_message "MSG_LOCATION_RESULT" "status=failed"
        debug_log "DEBUG" "Location information process completed with status: failed"
        return 1
    fi
}

# 国コードとタイムゾーン情報を一括取得する関数（スピナー実装版）
OK2_get_country_code() {
    # 変数宣言
    local ip_v4=""
    local ip_v6=""
    local select_ip=""
    local select_ip_ver=""
    local utc_offset=""
    local offset_sign=""
    local offset_hours=""
    local worldtime_ip=""
    local timeout_sec=15
    local network_type=""
    local tmp_file=""
    
    # API URLの定数化
    local API_IPV4="https://api.ipify.org"
    local API_IPV6="https://api64.ipify.org"
    local API_WORLDTIME="http://worldtimeapi.org/api/ip"
    local API_IPAPI="http://ip-api.com/json"
    local API_IPINFO="https://ipinfo.io"
    
    # グローバル変数の初期化
    SELECT_ZONE=""
    SELECT_ZONENAME=""
    SELECT_TIMEZONE=""
    SELECT_COUNTRY=""
    SELECT_POSIX_TZ=""
    
    # キャッシュディレクトリの確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"
    
    # ネットワーク接続状況の確認
    if [ -f "${CACHE_DIR}/network.ch" ]; then
        network_type=$(cat "${CACHE_DIR}/network.ch")
        debug_log "DEBUG: Network connectivity type detected: $network_type"
    else
        debug_log "DEBUG: Network connectivity information not available, checking now"
        check_network_connectivity
        if [ -f "${CACHE_DIR}/network.ch" ]; then
            network_type=$(cat "${CACHE_DIR}/network.ch")
            debug_log "DEBUG: Network connectivity checked and type is: $network_type"
        else
            network_type=""
            debug_log "DEBUG: Failed to detect network connectivity type"
        fi
    fi
    
    # スピナー開始 - 地域情報取得開始
    start_spinner "$(color blue "$(get_message "MSG_RETRIEVING_INFO")")" "dot" "blue"
    debug_log "DEBUG: Starting location info retrieval process"
    
    # ネットワーク状況に応じたIPアドレス取得
    if [ "$network_type" = "v4" ] || [ "$network_type" = "v4v6" ]; then
        # IPv4アドレスの取得を試行
        stop_spinner
        start_spinner "$(color blue "$(get_message "MSG_API_ACCESS" "api=$API_IPV4" "network=IPv4")")" "dot" "blue"
        debug_log "DEBUG: Attempting to retrieve IPv4 address"
        
        # BASE_WGETを使用
        tmp_file="${CACHE_DIR}/ipv4_$$.tmp"
        $BASE_WGET "$tmp_file" "$API_IPV4" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            ip_v4=$(cat "$tmp_file")
            rm -f "$tmp_file"
        fi
        
        if [ -n "$ip_v4" ]; then
            stop_spinner "$(color green "$(get_message "MSG_RETRIEVED" "api=$API_IPV4" "network=IPv4")")" "success"
            debug_log "DEBUG: IPv4 address retrieved: $ip_v4"
            
            # WorldTimeAPIからタイムゾーン情報を取得
            start_spinner "$(color blue "$(get_message "MSG_API_ACCESS" "api=$API_WORLDTIME" "network=IPv4")")" "dot" "blue"
            debug_log "DEBUG: Trying WorldTimeAPI with IPv4 address"
            
            # BASE_WGETを使用
            tmp_file="${CACHE_DIR}/worldtime_$$.tmp"
            $BASE_WGET "$tmp_file" "$API_WORLDTIME" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
            if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
                SELECT_ZONE=$(cat "$tmp_file")
                rm -f "$tmp_file"
            fi
            
            if [ -n "$SELECT_ZONE" ]; then
                select_ip="$ip_v4"
                select_ip_ver="IPv4"
                stop_spinner "$(color green "$(get_message "MSG_RETRIEVED" "api=$API_WORLDTIME" "network=IPv4")")" "success"
                debug_log "DEBUG: WorldTimeAPI responded successfully using IPv4"
            else
                stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                debug_log "DEBUG: WorldTimeAPI failed with IPv4, response is empty"
            fi
        else
            stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
            debug_log "DEBUG: Failed to retrieve IPv4 address"
        fi
    fi
    
    # IPv4で取得できなかった場合やデータが不完全な場合はIPv6を試す
    if { [ -z "$SELECT_ZONE" ] || ! echo "$SELECT_ZONE" | grep -q '"timezone"' || ! echo "$SELECT_ZONE" | grep -q '"abbreviation"' || ! echo "$SELECT_ZONE" | grep -q '"utc_offset"'; } && { [ "$network_type" = "v6" ] || [ "$network_type" = "v4v6" ]; }; then
        debug_log "DEBUG: Trying WorldTimeAPI with IPv6 address"
        
        # IPv6アドレスの取得を試行
        if [ -z "$ip_v6" ]; then
            start_spinner "$(color blue "$(get_message "MSG_API_ACCESS" "api=$API_IPV6" "network=IPv6")")" "dot" "blue"
            debug_log "DEBUG: Attempting to retrieve IPv6 address"
            
            # BASE_WGETを使用
            tmp_file="${CACHE_DIR}/ipv6_$$.tmp"
            $BASE_WGET "$tmp_file" "$API_IPV6" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
            if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
                ip_v6=$(cat "$tmp_file")
                rm -f "$tmp_file"
            fi
            
            if [ -n "$ip_v6" ]; then
                stop_spinner "$(color green "$(get_message "MSG_RETRIEVED" "api=$API_IPV6" "network=IPv6")")" "success"
                debug_log "DEBUG: IPv6 address retrieved: $ip_v6"
            else
                stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                debug_log "DEBUG: Failed to retrieve IPv6 address"
            fi
        fi
        
        if [ -n "$ip_v6" ]; then
            start_spinner "$(color blue "$(get_message "MSG_API_ACCESS" "api=$API_WORLDTIME" "network=IPv6")")" "dot" "blue"
            debug_log "DEBUG: Querying WorldTimeAPI with IPv6"
            
            # BASE_WGETを使用
            tmp_file="${CACHE_DIR}/worldtime_v6_$$.tmp"
            $BASE_WGET "$tmp_file" "$API_WORLDTIME" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
            if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
                SELECT_ZONE=$(cat "$tmp_file")
                rm -f "$tmp_file"
            fi
            
            if [ -n "$SELECT_ZONE" ]; then
                select_ip="$ip_v6"
                select_ip_ver="IPv6"
                stop_spinner "$(color green "$(get_message "MSG_RETRIEVED" "api=$API_WORLDTIME" "network=IPv6")")" "success"
                debug_log "DEBUG: WorldTimeAPI responded successfully using IPv6"
            else
                stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                debug_log "DEBUG: WorldTimeAPI also failed with IPv6"
            fi
        fi
    fi
    
    # WorldTimeAPIからのデータを処理
    if [ -n "$SELECT_ZONE" ]; then
        # タイムゾーン情報を抽出
        SELECT_ZONENAME=$(echo "$SELECT_ZONE" | grep -o '"timezone":"[^"]*' | awk -F'"' '{print $4}')
        SELECT_TIMEZONE=$(echo "$SELECT_ZONE" | grep -o '"abbreviation":"[^"]*' | awk -F'"' '{print $4}')
        utc_offset=$(echo "$SELECT_ZONE" | grep -o '"utc_offset":"[^"]*' | awk -F'"' '{print $4}')
        worldtime_ip=$(echo "$SELECT_ZONE" | grep -o '"client_ip":"[^"]*' | awk -F'"' '{print $4}')
        
        debug_log "DEBUG: Data extracted from WorldTimeAPI - ZoneName: $SELECT_ZONENAME, TZ: $SELECT_TIMEZONE, Offset: $utc_offset, IP: $worldtime_ip"
        
        # すべての時間情報が揃っているか確認
        if [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$utc_offset" ]; then
            # POSIX形式のタイムゾーン文字列を生成（例：JST-9）
            offset_sign=$(echo "$utc_offset" | cut -c1)
            offset_hours=$(echo "$utc_offset" | cut -c2-3 | sed 's/^0//')
            
            if [ "$offset_sign" = "+" ]; then
                # +9 -> -9（POSIXでは符号が反転）
                SELECT_POSIX_TZ="${SELECT_TIMEZONE}-${offset_hours}"
            else
                # -5 -> 5（POSIXではプラスの符号は省略）
                SELECT_POSIX_TZ="${SELECT_TIMEZONE}${offset_hours}"
            fi
            
            debug_log "DEBUG: Generated POSIX timezone: $SELECT_POSIX_TZ"
        else
            debug_log "DEBUG: WorldTimeAPI response incomplete, missing required timezone data"
        fi
        
        # WorldTimeAPIから得たIPを使ってIP-APIから国コードを取得
        if [ -n "$worldtime_ip" ]; then
            start_spinner "$(color blue "$(get_message "MSG_API_ACCESS" "api=$API_IPAPI" "network=$select_ip_ver")")" "dot" "blue"
            debug_log "DEBUG: Using WorldTimeAPI-provided IP for country code lookup"
            
            # BASE_WGETを使用
            tmp_file="${CACHE_DIR}/country_$$.tmp"
            $BASE_WGET "$tmp_file" "${API_IPAPI}/${worldtime_ip}" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
            if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
                local country_data=$(cat "$tmp_file")
                rm -f "$tmp_file"
                
                if [ -n "$country_data" ]; then
                    SELECT_COUNTRY=$(echo "$country_data" | grep -o '"countryCode":"[^"]*' | awk -F'"' '{print $4}')
                    if [ -n "$SELECT_COUNTRY" ]; then
                        stop_spinner "$(color green "$(get_message "MSG_RETRIEVED" "api=$API_IPAPI" "network=$select_ip_ver")")" "success"
                        debug_log "DEBUG: Country code retrieved using WorldTimeAPI IP: $SELECT_COUNTRY"
                    else
                        stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                        debug_log "DEBUG: Failed to get country code using WorldTimeAPI IP"
                    fi
                else
                    stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                    debug_log "DEBUG: IP-API request returned empty response"
                fi
            else
                stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                debug_log "DEBUG: IP-API request failed"
            fi
        fi
    else
        debug_log "DEBUG: Failed to get any valid response from WorldTimeAPI"
    fi
    
    # WorldTimeAPIからIPが取得できなかった場合やIP-APIが失敗した場合のフォールバック
    if [ -z "$SELECT_COUNTRY" ]; then
        debug_log "DEBUG: Using fallback method for country code"
        
        # 使用可能なIP（IPv4優先）をIP-APIに渡す
        local fallback_ip="$ip_v6"
        local fallback_network="IPv6"
        if [ -n "$ip_v4" ]; then
            fallback_ip="$ip_v4"
            fallback_network="IPv4"
        fi
        
        if [ -n "$fallback_ip" ]; then
            start_spinner "$(color blue "$(get_message "MSG_API_ACCESS" "api=$API_IPAPI" "network=$fallback_network")")" "dot" "blue"
            debug_log "DEBUG: Querying IP-API directly with local IP: $fallback_ip"
            
            # BASE_WGETを使用
            tmp_file="${CACHE_DIR}/country_fallback_$$.tmp"
            $BASE_WGET "$tmp_file" "${API_IPAPI}/${fallback_ip}" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
            if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
                local fallback_data=$(cat "$tmp_file")
                rm -f "$tmp_file"
                
                if [ -n "$fallback_data" ]; then
                    SELECT_COUNTRY=$(echo "$fallback_data" | grep -o '"countryCode":"[^"]*' | awk -F'"' '{print $4}')
                    if [ -n "$SELECT_COUNTRY" ]; then
                        stop_spinner "$(color green "$(get_message "MSG_RETRIEVED" "api=$API_IPAPI" "network=$fallback_network")")" "success"
                        debug_log "DEBUG: Country code retrieved using direct IP query: $SELECT_COUNTRY"
                    else
                        stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                        debug_log "DEBUG: Failed to get country code using direct IP query"
                        
                        # ipinfo.ioをさらにフォールバックとして使用
                        start_spinner "$(color blue "$(get_message "MSG_API_ACCESS" "api=$API_IPINFO" "network=$fallback_network")")" "dot" "blue"
                        debug_log "DEBUG: Trying ipinfo.io as last resort"
                        
                        # BASE_WGETを使用
                        tmp_file="${CACHE_DIR}/ipinfo_$$.tmp"
                        $BASE_WGET "$tmp_file" "${API_IPINFO}/${fallback_ip}/json" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
                        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
                            local ipinfo_data=$(cat "$tmp_file")
                            rm -f "$tmp_file"
                            
                            if [ -n "$ipinfo_data" ]; then
                                SELECT_COUNTRY=$(echo "$ipinfo_data" | grep -o '"country"[ ]*:[ ]*"[^"]*' | awk -F'"' '{print $4}')
                                if [ -n "$SELECT_COUNTRY" ]; then
                                    stop_spinner "$(color green "$(get_message "MSG_RETRIEVED" "api=$API_IPINFO" "network=$fallback_network")")" "success"
                                    debug_log "DEBUG: Country code retrieved from ipinfo.io: $SELECT_COUNTRY"
                                else
                                    stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                                    debug_log "DEBUG: Failed to get country code from ipinfo.io"
                                fi
                            else
                                stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                                debug_log "DEBUG: ipinfo.io request returned empty response"
                            fi
                        else
                            stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                            debug_log "DEBUG: ipinfo.io request failed"
                        fi
                    fi
                else
                    stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                    debug_log "DEBUG: IP-API fallback request returned empty response"
                fi
            else
                stop_spinner "$(color red "$(get_message "MSG_NOT_RETRIEVED")")" "error"
                debug_log "DEBUG: IP-API fallback request failed"
            fi
        fi
    fi
    
    # 一時ファイルのクリーンアップ（念のため）
    rm -f "${CACHE_DIR}/*_$$.tmp" 2>/dev/null
    
    # 結果表示の前にスピナーを停止
    stop_spinner
    
    # 結果の表示
    if [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$SELECT_COUNTRY" ]; then
        echo "$(color green "$(get_message "MSG_INFO_RETRIEVED")")"
        debug_log "DEBUG: Successfully retrieved all required information"
        return 0
    else
        echo "$(color red "$(get_message "MSG_RETRIEVAL_FAILED")")"
        debug_log "DEBUG: Failed to retrieve all required information"
        return 1
    fi
}

# 国コードとタイムゾーン情報を一括取得する関数（ネットワーク接続状況を考慮した改良版）
OK_get_country_code() {
    # ローカル変数の宣言
    local ip_v4=""
    local ip_v6=""
    local select_ip=""
    local select_ip_ver=""
    local utc_offset=""
    local offset_sign=""
    local offset_hours=""
    local worldtime_ip=""
    local timeout_sec=15
    local network_type=""
    
    # グローバル変数の初期化
    SELECT_ZONE=""
    SELECT_ZONENAME=""
    SELECT_TIMEZONE=""
    SELECT_COUNTRY=""
    SELECT_POSIX_TZ=""
    
    # キャッシュディレクトリの確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"
    
    # ネットワーク接続状況の確認
    if [ -f "${CACHE_DIR}/network.ch" ]; then
        network_type=$(cat "${CACHE_DIR}/network.ch")
        debug_log "DEBUG: Network connectivity type detected: $network_type"
    else
        debug_log "DEBUG: Network connectivity information not available, checking now"
        check_network_connectivity
        if [ -f "${CACHE_DIR}/network.ch" ]; then
            network_type=$(cat "${CACHE_DIR}/network.ch")
            debug_log "DEBUG: Network connectivity checked and type is: $network_type"
        else
            network_type=""
            debug_log "DEBUG: Failed to detect network connectivity type"
        fi
    fi
    
    # ネットワーク状況に応じたIPアドレス取得
    if [ "$network_type" = "v4" ] || [ "$network_type" = "v4v6" ]; then
        # IPv4アドレスの取得を試行
        debug_log "DEBUG: Attempting to retrieve IPv4 address"
        ip_v4=$(wget --timeout=$timeout_sec -T $timeout_sec -qO- https://api.ipify.org 2>/dev/null || echo "")
        
        if [ -n "$ip_v4" ]; then
            debug_log "DEBUG: IPv4 address retrieved: $ip_v4"
            
            # WorldTimeAPIからタイムゾーン情報を取得
            debug_log "DEBUG: Trying WorldTimeAPI with IPv4 address"
            SELECT_ZONE=$(wget --timeout=$timeout_sec -T $timeout_sec -qO- "http://worldtimeapi.org/api/ip" 2>/dev/null || echo "")
            
            if [ -n "$SELECT_ZONE" ]; then
                select_ip="$ip_v4"
                select_ip_ver="IPv4"
                debug_log "DEBUG: WorldTimeAPI responded successfully using IPv4"
            else
                debug_log "DEBUG: WorldTimeAPI failed with IPv4, response is empty"
            fi
        else
            debug_log "DEBUG: Failed to retrieve IPv4 address"
        fi
    fi
    
    # IPv4で取得できなかった場合やデータが不完全な場合はIPv6を試す
    if { [ -z "$SELECT_ZONE" ] || ! echo "$SELECT_ZONE" | grep -q '"timezone"' || ! echo "$SELECT_ZONE" | grep -q '"abbreviation"' || ! echo "$SELECT_ZONE" | grep -q '"utc_offset"'; } && { [ "$network_type" = "v6" ] || [ "$network_type" = "v4v6" ]; }; then
        debug_log "DEBUG: Trying WorldTimeAPI with IPv6 address"
        
        # IPv6アドレスの取得を試行
        if [ -z "$ip_v6" ]; then
            debug_log "DEBUG: Attempting to retrieve IPv6 address"
            ip_v6=$(wget --timeout=$timeout_sec -T $timeout_sec -qO- https://api64.ipify.org 2>/dev/null || echo "")
        fi
        
        if [ -n "$ip_v6" ]; then
            debug_log "DEBUG: IPv6 address retrieved: $ip_v6"
            
            SELECT_ZONE=$(wget --timeout=$timeout_sec -T $timeout_sec -qO- "http://worldtimeapi.org/api/ip" 2>/dev/null || echo "")
            
            if [ -n "$SELECT_ZONE" ]; then
                select_ip="$ip_v6"
                select_ip_ver="IPv6"
                debug_log "DEBUG: WorldTimeAPI responded successfully using IPv6"
            else
                debug_log "DEBUG: WorldTimeAPI also failed with IPv6"
            fi
        else
            debug_log "DEBUG: Failed to retrieve IPv6 address"
        fi
    fi
    
    # WorldTimeAPIからのデータを処理
    if [ -n "$SELECT_ZONE" ]; then
        # タイムゾーン情報を抽出
        SELECT_ZONENAME=$(echo "$SELECT_ZONE" | grep -o '"timezone":"[^"]*' | awk -F'"' '{print $4}')
        SELECT_TIMEZONE=$(echo "$SELECT_ZONE" | grep -o '"abbreviation":"[^"]*' | awk -F'"' '{print $4}')
        utc_offset=$(echo "$SELECT_ZONE" | grep -o '"utc_offset":"[^"]*' | awk -F'"' '{print $4}')
        worldtime_ip=$(echo "$SELECT_ZONE" | grep -o '"client_ip":"[^"]*' | awk -F'"' '{print $4}')
        
        debug_log "DEBUG: Data extracted from WorldTimeAPI - ZoneName: $SELECT_ZONENAME, TZ: $SELECT_TIMEZONE, Offset: $utc_offset, IP: $worldtime_ip"
        
        # すべての時間情報が揃っているか確認
        if [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$utc_offset" ]; then
            # POSIX形式のタイムゾーン文字列を生成（例：JST-9）
            offset_sign=$(echo "$utc_offset" | cut -c1)
            offset_hours=$(echo "$utc_offset" | cut -c2-3 | sed 's/^0//')
            
            if [ "$offset_sign" = "+" ]; then
                # +9 -> -9（POSIXでは符号が反転）
                SELECT_POSIX_TZ="${SELECT_TIMEZONE}-${offset_hours}"
            else
                # -5 -> 5（POSIXではプラスの符号は省略）
                SELECT_POSIX_TZ="${SELECT_TIMEZONE}${offset_hours}"
            fi
            
            debug_log "DEBUG: Generated POSIX timezone: $SELECT_POSIX_TZ"
        else
            debug_log "DEBUG: WorldTimeAPI response incomplete, missing required timezone data"
        fi
        
        # WorldTimeAPIから得たIPを使ってIP-APIから国コードを取得
        if [ -n "$worldtime_ip" ]; then
            debug_log "DEBUG: Using WorldTimeAPI-provided IP for country code lookup"
            local country_data=$(wget --timeout=$timeout_sec -T $timeout_sec -qO- "http://ip-api.com/json/$worldtime_ip" 2>/dev/null || echo "")
            
            if [ -n "$country_data" ]; then
                SELECT_COUNTRY=$(echo "$country_data" | grep -o '"countryCode":"[^"]*' | awk -F'"' '{print $4}')
                if [ -n "$SELECT_COUNTRY" ]; then
                    debug_log "DEBUG: Country code retrieved using WorldTimeAPI IP: $SELECT_COUNTRY"
                else
                    debug_log "DEBUG: Failed to get country code using WorldTimeAPI IP"
                fi
            else
                debug_log "DEBUG: IP-API request returned empty response"
            fi
        fi
    else
        debug_log "DEBUG: Failed to get any valid response from WorldTimeAPI"
    fi
    
    # WorldTimeAPIからIPが取得できなかった場合やIP-APIが失敗した場合のフォールバック
    if [ -z "$SELECT_COUNTRY" ]; then
        debug_log "DEBUG: Using fallback method for country code"
        
        # 使用可能なIP（IPv4優先）をIP-APIに渡す
        local fallback_ip="$ip_v6"
        if [ -n "$ip_v4" ]; then
            fallback_ip="$ip_v4"
        fi
        
        if [ -n "$fallback_ip" ]; then
            debug_log "DEBUG: Querying IP-API directly with local IP: $fallback_ip"
            local fallback_data=$(wget --timeout=$timeout_sec -T $timeout_sec -qO- "http://ip-api.com/json/$fallback_ip" 2>/dev/null || echo "")
            
            if [ -n "$fallback_data" ]; then
                SELECT_COUNTRY=$(echo "$fallback_data" | grep -o '"countryCode":"[^"]*' | awk -F'"' '{print $4}')
                if [ -n "$SELECT_COUNTRY" ]; then
                    debug_log "DEBUG: Country code retrieved using direct IP query: $SELECT_COUNTRY"
                else
                    debug_log "DEBUG: Failed to get country code using direct IP query"
                    
                    # ipinfo.ioをさらにフォールバックとして使用
                    debug_log "DEBUG: Trying ipinfo.io as last resort"
                    local ipinfo_data=$(wget --timeout=$timeout_sec -T $timeout_sec -qO- "https://ipinfo.io/$fallback_ip/json" 2>/dev/null || echo "")
                    
                    if [ -n "$ipinfo_data" ]; then
                        SELECT_COUNTRY=$(echo "$ipinfo_data" | grep -o '"country"[ ]*:[ ]*"[^"]*' | awk -F'"' '{print $4}')
                        if [ -n "$SELECT_COUNTRY" ]; then
                            debug_log "DEBUG: Country code retrieved from ipinfo.io: $SELECT_COUNTRY"
                        else
                            debug_log "DEBUG: Failed to get country code from ipinfo.io"
                        fi
                    else
                        debug_log "DEBUG: ipinfo.io request returned empty response"
                    fi
                fi
            else
                debug_log "DEBUG: IP-API fallback request returned empty response"
            fi
        fi
    fi
    
    # 結果の確認
    if [ -z "$SELECT_ZONENAME" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_COUNTRY" ]; then
        debug_log "DEBUG: Failed to retrieve all required information"
        return 1
    else
        debug_log "DEBUG: Successfully retrieved all required information"
        return 0
    fi
}

# IPアドレスから地域情報を取得しキャッシュファイルに保存する関数
process_location_info() {
    local skip_retrieval=0
    
    # パラメータ処理（オプション）
    if [ "$1" = "use_cached" ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$SELECT_ZONENAME" ]; then
        skip_retrieval=1
        debug_log "DEBUG: Using already retrieved location information"
    fi
    
    # 必要な場合のみget_country_code関数を呼び出し
    if [ $skip_retrieval -eq 0 ]; then
        debug_log "DEBUG: Starting IP-based location information retrieval"
        get_country_code || {
            debug_log "ERROR: get_country_code failed to retrieve location information"
            return 1
        }
    fi
    
    debug_log "DEBUG: Processing location data - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME, Timezone: $SELECT_TIMEZONE"

    # キャッシュファイルのパス定義
    local tmp_country="${CACHE_DIR}/ip_country.tmp"
    local tmp_zone="${CACHE_DIR}/ip_zone.tmp"
    local tmp_timezone="${CACHE_DIR}/ip_timezone.tmp"
    local tmp_zonename="${CACHE_DIR}/ip_zonename.tmp"
    
    # 3つの重要情報が揃っているか確認
    if [ -z "$SELECT_COUNTRY" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_ZONENAME" ]; then
        debug_log "ERROR: Incomplete location data - required information missing"
        # 既存のファイルを削除してクリーンな状態を確保
        rm -f "$tmp_country" "$tmp_zone" "$tmp_timezone" "$tmp_zonename" 2>/dev/null
        return 1
    fi
    
    debug_log "DEBUG: All required location data available, saving to cache files"
    
    # 国コードをキャッシュに保存
    echo "$SELECT_COUNTRY" > "$tmp_country"
    debug_log "DEBUG: Country code saved to cache: $SELECT_COUNTRY"
    
    # 生のゾーン情報（JSON形式）をキャッシュに保存
    if [ -n "$SELECT_ZONE" ]; then
        echo "$SELECT_ZONE" > "$tmp_zone"
        debug_log "DEBUG: Zone data saved to cache (JSON format)"
    fi
    
    # ゾーンネームをキャッシュに保存（例：Asia/Tokyo）
    echo "$SELECT_ZONENAME" > "$tmp_zonename"
    debug_log "DEBUG: Zone name saved to cache: $SELECT_ZONENAME"
    
    # POSIXタイムゾーン文字列を保存（get_country_code()で生成済み）
    if [ -n "$SELECT_POSIX_TZ" ]; then
        echo "$SELECT_POSIX_TZ" > "$tmp_timezone"
        debug_log "DEBUG: Using pre-generated POSIX timezone: $SELECT_POSIX_TZ"
    else
        # 万が一SELECT_POSIX_TZが設定されていない場合の保険
        local posix_tz="$SELECT_TIMEZONE"
        local temp_offset=""
        
        if [ -n "$SELECT_ZONE" ]; then
            temp_offset=$(echo "$SELECT_ZONE" | grep -o '"utc_offset":"[^"]*' | awk -F'"' '{print $4}')
            
            if [ -n "$temp_offset" ]; then
                debug_log "DEBUG: Found UTC offset in zone data: $temp_offset"
                # +09:00のような形式からPOSIX形式（-9）に変換
                local temp_sign=$(echo "$temp_offset" | cut -c1)
                local temp_hours=$(echo "$temp_offset" | cut -c2-3 | sed 's/^0//')
                
                if [ "$temp_sign" = "+" ]; then
                    # +9 -> -9（POSIXでは符号が反転）
                    posix_tz="${SELECT_TIMEZONE}-${temp_hours}"
                else
                    # -5 -> 5（POSIXではプラスの符号は省略）
                    posix_tz="${SELECT_TIMEZONE}${temp_hours}"
                fi
                
                debug_log "DEBUG: Generated POSIX timezone as fallback: $posix_tz"
            fi
        fi
        
        echo "$posix_tz" > "$tmp_timezone"
        debug_log "DEBUG: Timezone saved to cache in POSIX format: $posix_tz"
    fi
    
    debug_log "DEBUG: Location information cache process completed successfully"
    return 0
}

# 📌 デバイスアーキテクチャの取得
# 戻り値: アーキテクチャ文字列 (例: "mips_24kc", "arm_cortex-a7", "x86_64")
get_device_architecture() {
    local arch=""
    local target=""
    
    # OpenWrtから詳細なアーキテクチャ情報を取得
    if [ -f "/etc/openwrt_release" ]; then
        target=$(grep "DISTRIB_TARGET" /etc/openwrt_release | cut -d "'" -f 2)
        arch=$(grep "DISTRIB_ARCH" /etc/openwrt_release | cut -d "'" -f 2)
    fi
    echo "$target $arch"
}

# 📌 OSタイプとバージョンの取得
# 戻り値: OSタイプとバージョン文字列 (例: "OpenWrt 24.10.0", "Alpine 3.18.0")
get_os_info() {
    local os_type=""
    local os_version=""
    
    # OpenWrtのチェック
    if [ -f "/etc/openwrt_release" ]; then
        os_type="OpenWrt"
        os_version=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2)
    fi
    
    echo "$os_type $os_version"
}

# 📌 パッケージマネージャーの検出
# 戻り値: パッケージマネージャー情報 (例: "opkg", "apk")
get_package_manager() {
    if command -v opkg >/dev/null 2>&1; then
        echo "opkg"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
} 

# 📌 利用可能な言語パッケージの取得
# 戻り値: "language_code:language_name"形式の利用可能な言語パッケージのリスト
# 📌 LuCIで利用可能な言語パッケージを検出し、luci.chに保存する関数
get_available_language_packages() {
    local pkg_manager=""
    local lang_packages=""
    local tmp_file="${CACHE_DIR}/lang_packages.tmp"
    local package_cache="${CACHE_DIR}/package_list.ch"
    local luci_cache="${CACHE_DIR}/luci.ch"
    local country_cache="${CACHE_DIR}/country.ch"
    local default_lang="en"
    
    debug_log "DEBUG" "Running get_available_language_packages() to detect LuCI languages"
    
    # パッケージマネージャーの検出
    pkg_manager=$(get_package_manager)
    debug_log "DEBUG" "Using package manager: $pkg_manager"
    
    # package_list.chが存在しない場合はupdate_package_list()を呼び出す
    if [ ! -f "$package_cache" ]; then
        debug_log "DEBUG" "Package list cache not found, calling update_package_list()"
        
        # common-package.shが読み込まれているか確認
        if type update_package_list >/dev/null 2>&1; then
            update_package_list
            debug_log "DEBUG" "Package list updated successfully"
        else
            debug_log "ERROR" "update_package_list() function not available"
        fi
    fi
    
    # package_list.chが存在するか再確認
    if [ ! -f "$package_cache" ]; then
        debug_log "ERROR" "Package list cache still not available after update attempt"
        # デフォルト言語をluci.chに設定
        echo "$default_lang" > "$luci_cache"
        debug_log "DEBUG" "Default language '$default_lang' written to luci.ch"
        return 1
    fi
    
    # LuCI言語パッケージを一時ファイルに格納
    if [ "$pkg_manager" = "opkg" ]; then
        debug_log "DEBUG" "Extracting LuCI language packages from package_list.ch"
        grep "luci-i18n-base-" "$package_cache" > "$tmp_file" || touch "$tmp_file"
        
        # 言語コードを抽出
        lang_packages=$(sed -n 's/luci-i18n-base-\([a-z][a-z]\(-[a-z][a-z]\)\?\) .*/\1/p' "$tmp_file" | sort -u)
        debug_log "DEBUG" "Available LuCI languages: $lang_packages"
    else
        debug_log "ERROR" "Unsupported package manager: $pkg_manager"
        touch "$tmp_file"
    fi
    
    # country.chからLuCI言語コード（$4）を取得
    local preferred_lang=""
    if [ -f "$country_cache" ]; then
        preferred_lang=$(awk '{print $4}' "$country_cache")
        debug_log "DEBUG" "Preferred language from country.ch: $preferred_lang"
    else
        debug_log "WARNING" "Country cache not found, using default language"
    fi
    
    # LuCI言語の決定ロジック
    local selected_lang="$default_lang"  # デフォルトは英語
    
    if [ -n "$preferred_lang" ]; then
        if [ "$preferred_lang" = "xx" ]; then
            # xxの場合はそのまま使用
            selected_lang="xx"
            debug_log "DEBUG" "Using special language code: xx (no localization)"
        elif echo "$lang_packages" | grep -q "^$preferred_lang$"; then
            # country.chの言語コードがパッケージリストに存在する場合
            selected_lang="$preferred_lang"
            debug_log "DEBUG" "Using preferred language: $selected_lang"
        else
            debug_log "DEBUG" "Preferred language not available, using default: $default_lang"
        fi
    fi
    
    # luci.chに書き込み
    echo "$selected_lang" > "$luci_cache"
    debug_log "DEBUG" "Selected LuCI language '$selected_lang' written to luci.ch"
    
    # 一時ファイル削除
    rm -f "$tmp_file"
    
    # 利用可能な言語リストを返す
    echo "$lang_packages"
    return 0
}

# タイムゾーン情報を取得（例: JST-9）
get_timezone_info() {
    local timezone=""

    # UCI（OpenWrt）設定から直接取得
    if command -v uci >/dev/null 2>&1; then
        timezone="$(uci get system.@system[0].timezone 2>/dev/null)"
    fi

    echo "$timezone"
}

# ゾーン名を取得（例: Asia/Tokyo）
get_zonename_info() {
    local zonename=""

    # UCI（OpenWrt）から取得
    if command -v uci >/dev/null 2>&1; then
        zonename="$(uci get system.@system[0].zonename 2>/dev/null)"
    fi

    echo "$zonename"
}

# USBデバイス検出
# USBデバイス検出関数
get_usb_devices() {
    # キャッシュファイルパスの設定
    USB_DEVICE="${CACHE_DIR}/usbdevice.ch"
    
    # USBデバイスの存在確認
    if [ -d "/sys/bus/usb/devices" ] && ls /sys/bus/usb/devices/[0-9]*-[0-9]*/idVendor >/dev/null 2>&1; then
        # USBデバイスが存在する場合
        debug_log "DEBUG" "USB device detected"
        echo "detected" > "${CACHE_DIR}/usbdevice.ch"
    else
        # USBデバイスが存在しない場合
        debug_log "DEBUG" "No USB devices detected"
        echo "not_detected" > "${CACHE_DIR}/usbdevice.ch"
    fi
}

# 📌 デバイスの国情報の取得
# 戻り値: システム設定とデータベースに基づく組み合わせた国情報
# 戻り値: システム設定とデータベースに基づく2文字の国コード
# 戻り値: システム設定から推定される2文字の国コード（JP、USなど）
get_country_info() {
    local current_lang=""
    local current_timezone=""
    local country_code=""
    local country_db="${BASE_DIR}/country.db"
    
    # 現在のシステム言語を取得
    if command -v uci >/dev/null 2>&1; then
        current_lang=$(uci get luci.main.lang 2>/dev/null)
    fi
    
    # 現在のタイムゾーンを取得
    current_timezone=$(get_timezone_info)
    
    # country.dbが存在する場合、情報を照合
    if [ -f "$country_db" ] && [ -n "$current_lang" ]; then
        # まず言語コードで照合（5列目の国コードを取得）
        country_code=$(awk -v lang="$current_lang" '$4 == lang {print $5; exit}' "$country_db")
        
        # 言語で一致しない場合、タイムゾーンで照合（同じく5列目）
        if [ -z "$country_code" ] && [ -n "$current_timezone" ]; then
            country_code=$(awk -v tz="$current_timezone" '$0 ~ tz {print $5; exit}' "$country_db")
        fi
        
        # 値が取得できた場合は返す
        if [ -n "$country_code" ]; then
            [ "$DEBUG_MODE" = "true" ] && printf "DEBUG: Found country code from database: %s\n" "$country_code" >&2
            echo "$country_code"
            return 0
        fi
    fi
    
    # 一致が見つからないか、country.dbがない場合は空を返す
    [ "$DEBUG_MODE" = "true" ] && printf "DEBUG: No country code found in database\n" >&2
    echo ""
    return 1
}

# デバイス情報キャッシュを初期化・保存する関数
init_device_cache() {
   
    # アーキテクチャ情報の保存
    if [ ! -f "${CACHE_DIR}/architecture.ch" ]; then
        local arch
        arch=$(uname -m)
        echo "$arch" > "${CACHE_DIR}/architecture.ch"
        debug_log "DEBUG" "Created architecture cache: $arch"
    fi

    # OSバージョン情報の保存
    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        local version=""
        # OpenWrtバージョン取得
        if [ -f "/etc/openwrt_release" ]; then
            # ファイルからバージョン抽出
            version=$(grep -E "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2)
            echo "$version" > "${CACHE_DIR}/osversion.ch"
            debug_log "DEBUG" "Created OS version cache: $version"
        else
            echo "unknown" > "${CACHE_DIR}/osversion.ch"
            echo "WARN: Could not determine OS version"
        fi
    fi
 
    return 0
}

# パッケージマネージャー情報を検出・保存する関数
detect_and_save_package_manager() {
    if [ ! -f "${CACHE_DIR}/package_manager.ch" ]; then
        if command -v opkg >/dev/null 2>&1; then
            echo "opkg" > "${CACHE_DIR}/package_manager.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            PACKAGE_MANAGER="opkg"  # グローバル変数を設定
            debug_log "DEBUG" "Detected and saved package manager: opkg"
        elif command -v apk >/dev/null 2>&1; then
            echo "apk" > "${CACHE_DIR}/package_manager.ch"
            echo "apk" > "${CACHE_DIR}/extension.ch"
            PACKAGE_MANAGER="apk"  # グローバル変数を設定
            debug_log "DEBUG" "Detected and saved package manager: apk" 
        else
            # デフォルトとしてopkgを使用
            echo "opkg" > "${CACHE_DIR}/package_manager.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            PACKAGE_MANAGER="opkg"  # グローバル変数を設定
            debug_log "WARN" "No package manager detected, using opkg as default"
        fi
    else
        # すでにファイルが存在する場合は、グローバル変数を設定
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/package_manager.ch")
        debug_log "DEBUG" "Loaded package manager from cache: $PACKAGE_MANAGER"
    fi
}

# 端末の表示能力を検出する関数
detect_terminal_capability() {
    # 環境変数による明示的指定を最優先
    if [ -n "$AIOS_BANNER_STYLE" ]; then
        debug_log "DEBUG" "Using environment override: AIOS_BANNER_STYLE=$AIOS_BANNER_STYLE"
        echo "$AIOS_BANNER_STYLE"
        return 0
    fi
    
    # キャッシュが存在する場合はそれを使用
    if [ -f "$CACHE_DIR/banner_style.ch" ]; then
        CACHED_STYLE=$(cat "$CACHE_DIR/banner_style.ch")
        debug_log "DEBUG" "Using cached banner style: $CACHED_STYLE"
        echo "$CACHED_STYLE"
        return 0
    fi
    
    # デフォルトスタイル（安全なASCII）
    STYLE="ascii"
    
    # ロケールの確認
    LOCALE_CHECK=""
    if [ -n "$LC_ALL" ]; then
        LOCALE_CHECK="$LC_ALL"
    elif [ -n "$LANG" ]; then
        LOCALE_CHECK="$LANG"
    fi
    
    debug_log "DEBUG" "Checking locale: $LOCALE_CHECK"
    
    # UTF-8検出
    if echo "$LOCALE_CHECK" | grep -i "utf-\?8" >/dev/null 2>&1; then
        debug_log "DEBUG" "UTF-8 locale detected"
        STYLE="unicode"
    else
        debug_log "DEBUG" "Non-UTF-8 locale or unset locale"
    fi
    
    # ターミナル種別の確認
    if [ -n "$TERM" ]; then
        debug_log "DEBUG" "Checking terminal type: $TERM"
        case "$TERM" in
            *-256color|xterm*|rxvt*|screen*)
                STYLE="unicode"
                debug_log "DEBUG" "Advanced terminal detected"
                ;;
            dumb|vt100|linux)
                STYLE="ascii"
                debug_log "DEBUG" "Basic terminal detected"
                ;;
        esac
    fi
    
    # OpenWrt固有の検出
    if [ -f "/etc/openwrt_release" ]; then
        debug_log "DEBUG" "OpenWrt environment detected"
        # OpenWrtでの追加チェック（必要に応じて）
    fi
    
    # スタイルをキャッシュに保存（ディレクトリが存在する場合）
    if [ -d "$CACHE_DIR" ]; then
        echo "$STYLE" > "$CACHE_DIR/banner_style.ch"
        debug_log "DEBUG" "Banner style saved to cache: $STYLE"
    fi
    
    debug_log "DEBUG" "Selected banner style: $STYLE"
    echo "$STYLE"
}

# 📌 デバッグヘルパー関数
debug_info() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "===== SYSTEM DEBUG INFO ====="
        echo "Architecture: $(get_device_architecture)"
        echo "OS: $(get_os_info)"
        echo "Package Manager: $(get_package_manager)"
        echo "Current Zonename: $(get_zonename_info)"
        echo "Current Timezone: $(get_timezone_info)"
        echo "==========================="
    fi
}

# メイン処理
dynamic_system_info_main() {
    check_network_connectivity
    init_device_cache
    get_usb_devices
    detect_and_save_package_manager
}

# スクリプトの実行
dynamic_system_info_main "$@"
