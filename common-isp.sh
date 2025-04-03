#!/bin/sh

SCRIPT_VERSION="2025.04.01-00-00"

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
BASE_WGET="wget --no-check-certificate -q"
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

# ロケーション情報取得用タイムアウト設定（秒）
LOCATION_API_TIMEOUT="${LOCATION_API_TIMEOUT:-3}"
# リトライ回数の設定
LOCATION_API_MAX_RETRIES="${LOCATION_API_MAX_RETRIES:-5}"

# 🔵　ISP情報　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

# ネットワーク接続状態を確認する関数
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
        # v4v6デュアルスタック - 両方成功
        echo "v4v6" > "${ip_check_file}"
        debug_log "DEBUG: Dual-stack (v4v6) connectivity detected"
    elif [ "$ret4" -eq 0 ]; then
        # IPv4のみ成功
        echo "v4" > "${ip_check_file}"
        debug_log "DEBUG: IPv4-only connectivity detected"
    elif [ "$ret6" -eq 0 ]; then
        # IPv6のみ成功
        echo "v6" > "${ip_check_file}"
        debug_log "DEBUG: IPv6-only connectivity detected"
    else
        # 両方失敗
        echo "" > "${ip_check_file}"
        debug_log "DEBUG: No network connectivity detected"
    fi
}

# 国コードとタイムゾーン情報を取得する関数
get_country_code() {
    # 変数宣言
    local ip_address=""
    local network_type=""
    local tmp_file=""
    local api_url=""
    local spinner_active=0
    local retry_count=0
    
    # API URLの定数化
    local API_IPV4="http://api.ipify.org"
    local API_IPV6="http://api64.ipify.org"
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
        debug_log "DEBUG: Network connectivity type detected: $network_type"
    else
        debug_log "DEBUG: Network connectivity information not available, running check"
        check_network_connectivity
        
        if [ -f "${CACHE_DIR}/network.ch" ]; then
            network_type=$(cat "${CACHE_DIR}/network.ch")
            debug_log "DEBUG: Network type after check: $network_type"
        else
            network_type="unknown"
            debug_log "DEBUG: Network type still unknown after check"
        fi
    fi
    
    # 接続がない場合は早期リターン
    if [ -z "$network_type" ]; then
        debug_log "DEBUG: No network connectivity, cannot proceed"
        if [ $spinner_active -eq 1 ]; then
            local fail_msg=$(get_message "MSG_LOCATION_RESULT" "status=network unavailable")
            stop_spinner "$fail_msg" "failed"
        fi
        return 1
    fi
    
    # スピナー開始
    local init_msg=$(get_message "MSG_QUERY_INFO" "type=IP address" "api=ipify.org" "network=$network_type")
    start_spinner "$(color "blue" "$init_msg")" "yellow"
    spinner_active=1
    debug_log "DEBUG: Starting IP and location detection process"
    
    # IPアドレスの取得（ネットワークタイプに応じて適切なAPIを選択）
    if [ "$network_type" = "v4" ] || [ "$network_type" = "v4v6" ]; then
        # IPv4を使用（デュアルスタックでも常にIPv4を優先）
        debug_log "DEBUG: Using IPv4 API (preferred for dual-stack or v4-only)"
        api_url="$API_IPV4"
    elif [ "$network_type" = "v6" ]; then
        # IPv6のみ
        debug_log "DEBUG: Using IPv6 API (v6-only environment)"
        api_url="$API_IPV6"
    else
        # 不明なタイプ - デフォルトでIPv4
        debug_log "DEBUG: Unknown network type, defaulting to IPv4 API"
        api_url="$API_IPV4"
    fi
    
    # 選択したAPIを使用してIPアドレスを取得（リトライロジック付き）
    debug_log "DEBUG: Querying IP address from $api_url"
    
    retry_count=0
    while [ $retry_count -lt $LOCATION_API_MAX_RETRIES ]; do
        tmp_file="$(mktemp -t location.XXXXXX)"
        $BASE_WGET -O "$tmp_file" "$api_url" -T $LOCATION_API_TIMEOUT 2>/dev/null
        wget_status=$?
        debug_log "DEBUG: wget exit code: $wget_status (attempt: $((retry_count+1))/$LOCATION_API_MAX_RETRIES)"
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            ip_address=$(cat "$tmp_file")
            rm -f "$tmp_file"
            debug_log "DEBUG: Retrieved IP address: $ip_address from $api_url"
            break
        else
            debug_log "DEBUG: IP address query failed for $api_url, retrying..."
            rm -f "$tmp_file" 2>/dev/null
            retry_count=$((retry_count + 1))
            sleep 1
        fi
    done
    
    # IPアドレスが取得できたかチェック
    if [ -z "$ip_address" ]; then
        debug_log "DEBUG: Failed to retrieve IP address after $LOCATION_API_MAX_RETRIES attempts"
        if [ $spinner_active -eq 1 ]; then
            local fail_msg=$(get_message "MSG_LOCATION_RESULT" "status=failed")
            stop_spinner "$fail_msg" "failed"
            spinner_active=0
        fi
        return 1
    fi
    
    # 国コードの取得（リトライロジック付き）
    local country_msg=$(get_message "MSG_QUERY_INFO" "type=country code" "api=ip-api.com" "network=$network_type")
    update_spinner "$(color "blue" "$country_msg")" "yellow"
    debug_log "DEBUG: Querying country code from ip-api.com for IP: $ip_address"
    
    retry_count=0
    while [ $retry_count -lt $LOCATION_API_MAX_RETRIES ]; do
        tmp_file="$(mktemp -t location.XXXXXX)"
        $BASE_WGET -O "$tmp_file" "${API_IPAPI}/${ip_address}" -T $LOCATION_API_TIMEOUT 2>/dev/null
        wget_status=$?
        debug_log "DEBUG: wget exit code for country query: $wget_status (attempt: $((retry_count+1))/$LOCATION_API_MAX_RETRIES)"
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            SELECT_COUNTRY=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
            debug_log "DEBUG: Retrieved country code: $SELECT_COUNTRY"
            rm -f "$tmp_file"
            break
        else
            debug_log "DEBUG: Country code query failed, retrying..."
            rm -f "$tmp_file" 2>/dev/null
            retry_count=$((retry_count + 1))
            sleep 1
        fi
    done
    
    # タイムゾーン情報の取得（リトライロジック付き）
    local tz_msg=$(get_message "MSG_QUERY_INFO" "type=timezone" "api=worldtimeapi.org" "network=$network_type")
    update_spinner "$(color "blue" "$tz_msg")" "yellow"
    debug_log "DEBUG: Querying timezone from worldtimeapi.org"
    
    retry_count=0
    while [ $retry_count -lt $LOCATION_API_MAX_RETRIES ]; do
        tmp_file="$(mktemp -t location.XXXXXX)"
        $BASE_WGET -O "$tmp_file" "$API_WORLDTIME" -T $LOCATION_API_TIMEOUT 2>/dev/null
        wget_status=$?
        debug_log "DEBUG: wget exit code for timezone query: $wget_status (attempt: $((retry_count+1))/$LOCATION_API_MAX_RETRIES)"
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            SELECT_ZONENAME=$(grep -o '"timezone":"[^"]*' "$tmp_file" | sed 's/"timezone":"//')
            SELECT_TIMEZONE=$(grep -o '"abbreviation":"[^"]*' "$tmp_file" | sed 's/"abbreviation":"//')
            local utc_offset=$(grep -o '"utc_offset":"[^"]*' "$tmp_file" | sed 's/"utc_offset":"//')
            
            debug_log "DEBUG: Retrieved timezone data: $SELECT_ZONENAME ($SELECT_TIMEZONE), UTC offset: $utc_offset"
            
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
                
                debug_log "DEBUG: Generated POSIX timezone: $SELECT_POSIX_TZ"
            fi
            rm -f "$tmp_file"
            break
        else
            debug_log "DEBUG: Timezone query failed, retrying..."
            rm -f "$tmp_file" 2>/dev/null
            retry_count=$((retry_count + 1))
            sleep 1
        fi
    done
    
    # 結果のチェックとスピナー停止
    if [ $spinner_active -eq 1 ]; then
        if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ]; then
            local success_msg=$(get_message "MSG_LOCATION_RESULT" "status=successfully")
            stop_spinner "$success_msg" "success"
            debug_log "DEBUG: Location information process completed successfully"
            return 0
        else
            local fail_msg=$(get_message "MSG_LOCATION_RESULT" "status=failed")
            stop_spinner "$fail_msg" "failed"
            debug_log "DEBUG: Location information process failed - incomplete data received"
            return 1
        fi
    else
        # スピナーがすでに停止している場合（エラー時）
        debug_log "DEBUG: Spinner already stopped before completion"
        return 1
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

# 検出した地域情報を表示する共通関数
display_detected_isp() {
    local detection_isp="$1"
    local detected_isp="$2"
    local detected_as="$3"
    local detected_org="$4"
    local show_success_message="${5:-false}"
    
    debug_log "DEBUG" "Displaying ISP information from source: $detection_isp"
    
    # 検出情報表示
    local msg_info=$(get_message "MSG_USE_DETECTED_ISP_INFORMATION" "info=$detection_isp")
    printf "%s\n" "$(color white "$msg_info")"
    
    # ISP情報の詳細表示
    if [ -n "$detected_isp" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ISP")")" "$(color white "$detected_isp")"
    fi
    
    if [ -n "$detected_as" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_ISP_AS")")" "$(color white "$detected_as")"
    fi
    
    if [ -n "$detected_org" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_ISP_ORG")")" "$(color white "$detected_org")"
    fi
    
    # 成功メッセージの表示（オプション）
    if [ "$show_success_message" = "true" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_ISP_SUCCESS")")"
        EXTRA_SPACING_NEEDED="yes"
        debug_log "DEBUG" "Success messages displayed"
    fi

    printf "\n"
    
    debug_log "DEBUG" "ISP information displayed successfully"
}

# ISP情報取得関数
get_isp_info() {
    # 変数宣言
    local ip_address=""
    local network_type=""
    local timeout_sec=10
    local tmp_file=""
    local api_url=""
    local spinner_active=0
    local cache_file="${CACHE_DIR}/isp_info.ch"
    local cache_timeout=86400  # キャッシュ有効期間（24時間）
    local use_local_db=0  # ローカルDB使用フラグ
    local show_result="${1:-true}"  # 結果表示フラグ（デフォルトはtrue）
    
    # パラメータ処理
    while [ $# -gt 0 ]; do
        case "$1" in
            --local|-l)
                use_local_db=1
                debug_log "DEBUG: Using local database mode"
                ;;
            --cache-timeout=*)
                cache_timeout="${1#*=}"
                debug_log "DEBUG: Custom cache timeout: $cache_timeout seconds"
                ;;
            --no-cache)
                cache_timeout=0
                debug_log "DEBUG: Cache disabled"
                ;;
            --no-display)
                show_result="false"
                debug_log "DEBUG: Result display disabled"
                ;;
        esac
        shift
    done
    
    # グローバル変数の初期化
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    
    # キャッシュディレクトリの確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"
    
    # キャッシュチェック（キャッシュタイムアウトが0でない場合）
    if [ $cache_timeout -ne 0 ] && [ -f "$cache_file" ]; then
        local cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || date +%s)
        local current_time=$(date +%s)
        local cache_age=$(($current_time - $cache_time))
        
        if [ $cache_age -lt $cache_timeout ]; then
            debug_log "DEBUG: Using cached ISP information ($cache_age seconds old)"
            # キャッシュから情報読み込み
            if [ -s "$cache_file" ]; then
                ISP_NAME=$(sed -n '1p' "$cache_file")
                ISP_AS=$(sed -n '2p' "$cache_file")
                ISP_ORG=$(sed -n '3p' "$cache_file")
                
                if [ -n "$ISP_NAME" ]; then
                    debug_log "DEBUG: Loaded from cache - ISP: $ISP_NAME, AS: $ISP_AS"
                    
                    # キャッシュからの結果表示（オプション）
                    if [ "$show_result" = "true" ] && type display_detected_isp >/dev/null 2>&1; then
                        display_detected_isp "Cache" "$ISP_NAME" "$ISP_AS" "$ISP_ORG" "false"
                    fi
                    
                    return 0
                fi
            fi
            debug_log "DEBUG: Cache file invalid or empty"
        else
            debug_log "DEBUG: Cache expired ($cache_age seconds old)"
        fi
    fi
    
    # ローカルDBモードの処理
    if [ $use_local_db -eq 1 ]; then
        if [ -f "${BASE_DIR}/isp.db" ]; then
            debug_log "DEBUG: Processing with local database"
            # 実際のローカルDB処理はここに実装 (ローカルIPとISPマッピング)
            
            # 仮実装：ローカルIPからISP情報を取得できたとする
            ISP_NAME="Local ISP Database"
            ISP_AS="AS12345"
            ISP_ORG="Example Local Organization"
            
            # キャッシュに保存
            if [ $cache_timeout -ne 0 ]; then
                echo "$ISP_NAME" > "$cache_file"
                echo "$ISP_AS" >> "$cache_file"
                echo "$ISP_ORG" >> "$cache_file"
                debug_log "DEBUG: Saved local DB results to cache"
            fi
            
            # ローカルDBからの結果表示（オプション）
            if [ "$show_result" = "true" ] && type display_detected_isp >/dev/null 2>&1; then
                display_detected_isp "Local DB" "$ISP_NAME" "$ISP_AS" "$ISP_ORG" "false"
            fi
            
            return 0
        else
            debug_log "DEBUG: Local database not found, falling back to online API"
        fi
    fi
    
    # ネットワーク接続状況の取得
    if [ -f "${CACHE_DIR}/network.ch" ]; then
        network_type=$(cat "${CACHE_DIR}/network.ch")
        debug_log "DEBUG: Network connectivity type detected: $network_type"
    else
        debug_log "DEBUG: Network connectivity information not available, checking..."
        check_network_connectivity
        if [ -f "${CACHE_DIR}/network.ch" ]; then
            network_type=$(cat "${CACHE_DIR}/network.ch")
        else
            network_type="v4"  # デフォルトでIPv4を試行
        fi
    fi
    
    # スピナー開始（初期メッセージ）
    if type start_spinner >/dev/null 2>&1; then
        start_spinner "$(color "blue" "$(get_message "MSG_FETCHING_ISP_INFO")")" "yellow"
        spinner_active=1
        debug_log "DEBUG: Starting ISP detection process"
    fi
    
    # IPアドレスの取得（ネットワークタイプに応じて適切なAPIを選択）
    if [ "$network_type" = "v4" ] || [ "$network_type" = "v4v6" ]; then
        # IPv4優先
        api_url="https://api.ipify.org"
    elif [ "$network_type" = "v6" ]; then
        # IPv6のみ
        api_url="https://api64.ipify.org"
    else
        # デフォルト
        api_url="https://api.ipify.org"
    fi
    
    # IPアドレスの取得
    debug_log "DEBUG: Querying IP address from $api_url"
    
    tmp_file="$(mktemp -t isp.XXXXXX)"
    $BASE_WGET -O "$tmp_file" "$api_url" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
    
    if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        ip_address=$(cat "$tmp_file")
        rm -f "$tmp_file"
        debug_log "DEBUG: Retrieved IP address: $ip_address"
    else
        debug_log "DEBUG: IP address query failed"
        rm -f "$tmp_file" 2>/dev/null
        
        # IPv6にフォールバック試行（IPv4が失敗した場合）
        if [ "$network_type" = "v4v6" ]; then
            api_url="https://api64.ipify.org"
            debug_log "DEBUG: Trying IPv6 fallback"
            
            tmp_file="$(mktemp -t isp.XXXXXX)"
            $BASE_WGET -O "$tmp_file" "$api_url" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
            
            if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
                ip_address=$(cat "$tmp_file")
                rm -f "$tmp_file"
                debug_log "DEBUG: Retrieved IP address (IPv6): $ip_address"
            else
                debug_log "DEBUG: IPv6 address query also failed"
                rm -f "$tmp_file" 2>/dev/null
            fi
        fi
    fi
    
    # IPアドレスが取得できたかチェック
    if [ -z "$ip_address" ]; then
        debug_log "DEBUG: Failed to retrieve any IP address"
        if [ $spinner_active -eq 1 ] && type stop_spinner >/dev/null 2>&1; then
            stop_spinner "$(get_message "MSG_ISP_INFO_FAILED")" "failed"
            spinner_active=0
        fi
        return 1
    fi
    
    # スピナー更新（APIクエリ中）
    if [ $spinner_active -eq 1 ] && type update_spinner >/dev/null 2>&1; then
        update_spinner "$(color "blue" "$(get_message "MSG_FETCHING_ISP_INFO")")" "yellow"
    fi
    
    # ISP情報の取得
    debug_log "DEBUG: Querying ISP information for IP: $ip_address"
    
    tmp_file="$(mktemp -t isp.XXXXXX)"
    $BASE_WGET -O "$tmp_file" "http://ip-api.com/json/${ip_address}?fields=isp,as,org" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
    
    if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        # JSON解析
        ISP_NAME=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
        ISP_AS=$(grep -o '"as":"[^"]*' "$tmp_file" | sed 's/"as":"//')
        ISP_ORG=$(grep -o '"org":"[^"]*' "$tmp_file" | sed 's/"org":"//')
        
        debug_log "DEBUG: Retrieved ISP info - Name: $ISP_NAME, AS: $ISP_AS, Organization: $ISP_ORG"
        rm -f "$tmp_file"
        
        # キャッシュに保存（キャッシュタイムアウトが0でない場合）
        if [ $cache_timeout -ne 0 ]; then
            echo "$ISP_NAME" > "$cache_file"
            echo "$ISP_AS" >> "$cache_file"
            echo "$ISP_ORG" >> "$cache_file"
            debug_log "DEBUG: Saved ISP information to cache"
        fi
    else
        debug_log "DEBUG: ISP information query failed"
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    # 結果のチェックとスピナー停止
    if [ $spinner_active -eq 1 ] && type stop_spinner >/dev/null 2>&1; then
        if [ -n "$ISP_NAME" ]; then
            stop_spinner "$(get_message "MSG_ISP_INFO_SUCCESS")" "success"
            debug_log "DEBUG: ISP information process completed with status: success"
        else
            stop_spinner "$(get_message "MSG_ISP_INFO_FAILED")" "failed"
            debug_log "DEBUG: ISP information process completed with status: failed"
        fi
    fi
    
    # 成功した場合、結果表示
    if [ -n "$ISP_NAME" ]; then
        if [ "$show_result" = "true" ] && type display_detected_isp >/dev/null 2>&1; then
            display_detected_isp "Online API" "$ISP_NAME" "$ISP_AS" "$ISP_ORG" "false"
        fi
        return 0
    else
        return 1
    fi
}

# 🔴　ISP情報　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　ISP判定　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

# ISP判定関数（OpenWrt用・POSIX準拠）
# 使用方法: . ./detect_isp.sh

# IPv6アドレスをOpenWrtの機能から取得
get_wan_ipv6_address() {
    debug_log "Retrieving IPv6 address from OpenWrt network functions"
    
    # OpenWrtのネットワークライブラリ読み込み
    if [ -f "/lib/functions/network.sh" ]; then
        debug_log "Loading OpenWrt network libraries"
        . /lib/functions.sh 2>/dev/null
        . /lib/functions/network.sh 2>/dev/null
        . /lib/netifd/netifd-proto.sh 2>/dev/null
        
        # キャッシュをクリア
        network_flush_cache
        
        # WAN6インターフェース検出
        local net_if6=""
        network_find_wan6 net_if6
        
        if [ -n "$net_if6" ]; then
            debug_log "Found WAN6 interface: $net_if6"
            
            # IPv6アドレスを取得
            local net_addr6=""
            network_get_ipaddr6 net_addr6 "$net_if6"
            
            if [ -n "$net_addr6" ]; then
                debug_log "Found IPv6 address: $net_addr6"
                echo "$net_addr6"
                return 0
            fi
            debug_log "No IPv6 address found on interface $net_if6"
        else
            debug_log "No WAN6 interface found"
        fi
    else
        debug_log "OpenWrt network libraries not found"
    fi
    
    # フォールバック: ip コマンド使用
    if command -v ip >/dev/null 2>&1; then
        debug_log "Trying ip command fallback for IPv6"
        local ipv6_addr
        ipv6_addr=$(ip -6 addr show scope global | grep inet6 | grep -v temporary | head -1 | awk '{print $2}' | cut -d/ -f1)
        
        if [ -n "$ipv6_addr" ]; then
            debug_log "Found global IPv6 via ip command: $ipv6_addr"
            echo "$ipv6_addr"
            return 0
        fi
    fi
    
    # 外部APIからIPv6取得を試行
    debug_log "Attempting to get IPv6 address from external API"
    local tmp_file
    tmp_file=$(mktemp -t ipv6.XXXXXX)
    
    $BASE_WGET -O "$tmp_file" "https://ipv6-test.com/api/myip.php?json" >/dev/null 2>&1
    
    if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        local ipv6_addr
        ipv6_addr=$(grep -o '"address":"[^"]*' "$tmp_file" | sed 's/"address":"//')
        rm -f "$tmp_file"
        
        if echo "$ipv6_addr" | grep -q ":"; then
            debug_log "Found IPv6 address from external API: $ipv6_addr"
            echo "$ipv6_addr"
            return 0
        fi
    else
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    debug_log "Failed to get IPv6 address from all sources"
    return 1
}

# AFTRアドレスを検出（DS-LITE用）
detect_aftr_address() {
    debug_log "Detecting AFTR address for DS-LITE"
    local aftr_address=""
    
    # システムログからの検出
    if [ -f "/var/log/messages" ]; then
        aftr_address=$(grep -i "AFTR" /var/log/messages | tail -1 | grep -o '[a-zA-Z0-9\.\-]*\.jp')
        if [ -n "$aftr_address" ]; then
            debug_log "Found AFTR address in system logs: $aftr_address"
            echo "$aftr_address"
            return 0
        fi
    fi
    
    # UCI設定からの検出（OpenWrt）
    if command -v uci >/dev/null 2>&1; then
        # 全てのWAN6設定を検索
        config_list=$(uci show network | grep aftr_v4_addr 2>/dev/null)
        if [ -n "$config_list" ]; then
            aftr_address=$(echo "$config_list" | head -1 | cut -d= -f2 | tr -d "'" 2>/dev/null)
            if [ -n "$aftr_address" ]; then
                debug_log "Found AFTR address in UCI config: $aftr_address"
                echo "$aftr_address"
                return 0
            fi
        fi
    fi
    
    debug_log "No AFTR address found"
    return 1
}

# IPv6プレフィックスからISPを判定
detect_ipv6_provider() {
    local ipv6="$1"
    local provider="unknown"
    
    if [ -z "$ipv6" ]; then
        debug_log "No IPv6 address provided for provider detection"
        return 1
    fi
    
    # プレフィックスを抽出
    local prefix
    prefix=$(echo "$ipv6" | cut -d: -f1-2)
    debug_log "Extracted IPv6 prefix: $prefix"
    
    # 詳細なプレフィックス
    local long_prefix
    long_prefix=$(echo "$ipv6" | cut -d: -f1-3)
    debug_log "Extracted long IPv6 prefix: $long_prefix"
    
    # プレフィックスからプロバイダを判定
    case "$prefix" in
        # SoftBank（V6プラス）
        2404:7a)
            provider="mape_v6plus"
            debug_log "Detected SoftBank V6plus from IPv6 prefix"
            ;;
        # KDDI（IPv6オプション）
        2001:f9)
            provider="mape_ipv6option"
            debug_log "Detected KDDI IPv6option from IPv6 prefix"
            ;;
        # OCN
        2001:0c|2400:38)
            provider="mape_ocn"
            debug_log "Detected OCN MAP-E from IPv6 prefix"
            ;;
        # ビッグローブ BIGLOBE
        2001:26|2001:f6)
            provider="mape_biglobe"
            debug_log "Detected BIGLOBE from IPv6 prefix"
            ;;
        # NURO光
        240d:00)
            provider="mape_nuro"
            debug_log "Detected NURO from IPv6 prefix"
            ;;
        # JPNE NGN
        2404:92)
            provider="mape_jpne"
            debug_log "Detected JPNE from IPv6 prefix"
            ;;
        # So-net
        240b:10|240b:11|240b:12|240b:13)
            provider="mape_sonet"
            debug_log "Detected So-net from IPv6 prefix"
            ;;
        # NTT東日本/西日本（DS-Lite）- トランジックス系
        2404:8e)
            if echo "$long_prefix" | grep -q "2404:8e01"; then
                provider="dslite_east_transix"
                debug_log "Detected NTT East DS-Lite with transix"
            elif echo "$long_prefix" | grep -q "2404:8e00"; then
                provider="dslite_west_transix"
                debug_log "Detected NTT West DS-Lite with transix"
            else
                provider="dslite_transix"
                debug_log "Detected DS-Lite with transix (unknown region)"
            fi
            ;;
        # クロスパス系
        2404:92)
            provider="dslite_xpass"
            debug_log "Detected DS-Lite with xpass"
            ;;
        # v6コネクト系
        2404:01)
            provider="dslite_v6connect"
            debug_log "Detected DS-Lite with v6connect"
            ;;
        # @nifty
        2001:f7)
            provider="mape_nifty"
            debug_log "Detected @nifty from IPv6 prefix"
            ;;
        *)
            provider="unknown"
            debug_log "Unknown provider for prefix: $prefix"
            ;;
    esac
    
    # DS-LITEの場合はAFTRアドレスも検出
    if echo "$provider" | grep -q "dslite" && echo "$provider" | grep -qv "dslite_east\|dslite_west"; then
        local aftr_address
        aftr_address=$(detect_aftr_address)
        
        if [ -n "$aftr_address" ]; then
            debug_log "AFTR address detected: $aftr_address"
            
            if echo "$aftr_address" | grep -i "transix" >/dev/null 2>&1; then
                provider="dslite_transix"
                debug_log "Identified as transix DS-LITE from AFTR"
            elif echo "$aftr_address" | grep -i "xpass" >/dev/null 2>&1; then
                provider="dslite_xpass"
                debug_log "Identified as xpass DS-LITE from AFTR"
            elif echo "$aftr_address" | grep -i "v6connect" >/dev/null 2>&1; then
                provider="dslite_v6connect"
                debug_log "Identified as v6connect DS-LITE from AFTR"
            fi
        fi
    fi
    
    echo "$provider"
    return 0
}

# AS番号からISPを判定（IPv6で判別できない場合）
detect_as_provider() {
    local as_num="$1"
    local isp="$2"
    local org="$3"
    local region="$4"
    local city="$5"
    local provider="unknown"
    
    debug_log "Detecting provider from AS number and organization info"
    
    # AS番号による判定
    case "$as_num" in
        *AS4713*)
            # OCN (NTT Communications)
            provider="mape_ocn"
            debug_log "Detected OCN from AS number (AS4713)"
            ;;
        *AS17676*)
            # SoftBank
            provider="mape_v6plus"
            debug_log "Detected SoftBank from AS number (AS17676)"
            ;;
        *AS2516*)
            # KDDI
            provider="mape_ipv6option"
            debug_log "Detected KDDI from AS number (AS2516)"
            ;;
        *AS7521*)
            # NURO/So-net
            provider="mape_nuro"
            debug_log "Detected NURO/So-net from AS number (AS7521)"
            ;;
        *AS18126*)
            # Chubu Telecommunications
            provider="pppoe_ctc"
            debug_log "Detected CTC from AS number (AS18126)"
            ;;
        *AS2527*)
            # NTT East
            provider="dslite_east"
            debug_log "Detected NTT East from AS number (AS2527)"
            ;;
        *AS2914*)
            # NTT West
            provider="dslite_west"
            debug_log "Detected NTT West from AS number (AS2914)"
            ;;
        *AS17506*)
            # NIFTY
            provider="mape_nifty"
            debug_log "Detected @nifty from AS number (AS17506)"
            ;;
        *AS9824*|*AS9607*)
            # BIGLOBE
            provider="mape_biglobe"
            debug_log "Detected BIGLOBE from AS number (AS9824/AS9607)"
            ;;
        *AS9595*|*AS9591*)
            # So-net
            provider="mape_sonet"
            debug_log "Detected So-net from AS number (AS9595/AS9591)"
            ;;
        *)
            # ISP名/組織名による判定
            if echo "$isp $org" | grep -i "OCN\|Open Computer Network\|NTT Communications" >/dev/null 2>&1; then
                provider="mape_ocn"
                debug_log "Detected OCN from organization name"
            elif echo "$isp $org" | grep -i "SoftBank\|Yahoo\|BBIX\|ソフトバンク" >/dev/null 2>&1; then
                provider="mape_v6plus"
                debug_log "Detected SoftBank from organization name"
            elif echo "$isp $org" | grep -i "KDDI\|au\|ケーディーディーアイ" >/dev/null 2>&1; then
                provider="mape_ipv6option"
                debug_log "Detected KDDI from organization name"
            elif echo "$isp $org" | grep -i "NURO\|Sony\|So-net\|ソニー\|ソネット" >/dev/null 2>&1; then
                provider="mape_nuro"
                debug_log "Detected NURO/So-net from organization name"
            elif echo "$isp $org" | grep -i "BIGLOBE\|ビッグローブ" >/dev/null 2>&1; then
                provider="mape_biglobe"
                debug_log "Detected BIGLOBE from organization name"
            elif echo "$isp $org" | grep -i "nifty\|ニフティ\|@nifty" >/dev/null 2>&1; then
                provider="mape_nifty"
                debug_log "Detected @nifty from organization name"
            elif echo "$isp $org" | grep -i "Chubu Telecommunications\|CTC\|中部テレコミュニケーション" >/dev/null 2>&1; then
                provider="pppoe_ctc"
                debug_log "Detected CTC from organization name"
            elif echo "$isp $org" | grep -i "NTT East\|NTT東日本" >/dev/null 2>&1; then
                provider="dslite_east"
                debug_log "Detected NTT East from organization name"
            elif echo "$isp $org" | grep -i "NTT West\|NTT西日本" >/dev/null 2>&1; then
                provider="dslite_west"
                debug_log "Detected NTT West from organization name"
            elif echo "$isp $org" | grep -i "NTT\|FLETS\|フレッツ" >/dev/null 2>&1; then
                # 地域情報から東西判別
                if [ -n "$region" ] && [ -n "$city" ]; then
                    debug_log "Trying to determine NTT region from location data: $region, $city"
                    
                    # 東日本エリア
                    if echo "$region $city" | grep -i "Tokyo\|Kanagawa\|Saitama\|Chiba\|Ibaraki\|Tochigi\|Gunma\|Yamanashi\|Nagano\|Niigata\|Hokkaido\|Aomori\|Iwate\|Miyagi\|Akita\|Yamagata\|Fukushima" >/dev/null 2>&1; then
                        provider="dslite_east"
                        debug_log "Estimated NTT East from geographic location"
                    # 西日本エリア
                    elif echo "$region $city" | grep -i "Osaka\|Kyoto\|Hyogo\|Nara\|Shiga\|Wakayama\|Mie\|Aichi\|Gifu\|Shizuoka\|Toyama\|Ishikawa\|Fukui\|Tottori\|Shimane\|Okayama\|Hiroshima\|Yamaguchi\|Tokushima\|Kagawa\|Ehime\|Kochi\|Fukuoka\|Saga\|Nagasaki\|Kumamoto\|Oita\|Miyazaki\|Kagoshima\|Okinawa" >/dev/null 2>&1; then
                        provider="dslite_west"
                        debug_log "Estimated NTT West from geographic location"
                    else
                        provider="dslite"
                        debug_log "Generic NTT/FLETS service detected, but region unknown"
                    fi
                else
                    provider="dslite"
                    debug_log "Generic NTT/FLETS service detected"
                fi
            fi
            ;;
    esac
    
    echo "$provider"
    return 0
}

# ISP情報を取得してISPタイプを判定
detect_isp_type() {
    local cache_file="${CACHE_DIR}/isp.ch"
    local cache_timeout=86400  # キャッシュ有効期間（24時間）
    local provider="unknown"
    local show_result=1
    local use_cache=1
    local force_update=0
    
    # パラメータ処理
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-cache)
                use_cache=0
                debug_log "Cache disabled"
                ;;
            --force-update)
                force_update=1
                debug_log "Forcing update of ISP information"
                ;;
            --silent)
                show_result=0
                debug_log "Silent mode enabled"
                ;;
        esac
        shift
    done
    
    # キャッシュディレクトリ確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"
    
    # キャッシュチェック
    if [ $use_cache -eq 1 ] && [ $force_update -eq 0 ] && [ -f "$cache_file" ]; then
        local cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || date +%s)
        local current_time=$(date +%s)
        local cache_age=$(($current_time - $cache_time))
        
        if [ $cache_age -lt $cache_timeout ]; then
            debug_log "Using cached ISP information ($cache_age seconds old)"
            provider=$(grep CONNECTION_TYPE "$cache_file" | cut -d= -f2 | tr -d '"')
            
            if [ -n "$provider" ] && [ "$provider" != "unknown" ]; then
                if [ $show_result -eq 1 ]; then
                    display_isp_info "$provider" "cached"
                fi
                return 0
            fi
            debug_log "Invalid or incomplete cache data"
        else
            debug_log "Cache expired ($cache_age seconds old)"
        fi
    fi
    
    # スピナー表示開始
    if [ $show_result -eq 1 ]; then
        start_spinner "$(color "blue" "$(get_message "MSG_DETECTING_ISP_TYPE")")" "yellow"
    fi
    
    # IPv6アドレス取得
    local ipv6_addr
    ipv6_addr=$(get_wan_ipv6_address)
    local has_ipv6=0
    
    if [ -n "$ipv6_addr" ]; then
        has_ipv6=1
        debug_log "IPv6 address detected: $ipv6_addr"
        provider=$(detect_ipv6_provider "$ipv6_addr")
        debug_log "Provider detection from IPv6 result: $provider"
    else
        debug_log "No IPv6 address detected"
    fi
    
    # IPv6で判定できなかった場合はAPIから情報取得
    if [ "$provider" = "unknown" ] || [ -z "$provider" ]; then
        debug_log "IPv6 detection failed, trying ISP API"
        
        # API情報取得
        local tmp_file
        tmp_file=$(mktemp -t isp.XXXXXX)
        
        $BASE_WGET -O "$tmp_file" "http://ip-api.com/json?fields=isp,as,org,country,countryCode,regionName,city" >/dev/null 2>&1
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # JSONデータを抽出
            local isp=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
            local as_num=$(grep -o '"as":"[^"]*' "$tmp_file" | sed 's/"as":"//')
            local org=$(grep -o '"org":"[^"]*' "$tmp_file" | sed 's/"org":"//')
            local country=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
            local region=$(grep -o '"regionName":"[^"]*' "$tmp_file" | sed 's/"regionName":"//')
            local city=$(grep -o '"city":"[^"]*' "$tmp_file" | sed 's/"city":"//')
            
            debug_log "Retrieved ISP info - Name: $isp, AS: $as_num, Org: $org, Country: $country"
            
            # 日本の場合のみ詳細判定を行う
            if [ "$country" = "JP" ]; then
                provider=$(detect_as_provider "$as_num" "$isp" "$org" "$region" "$city")
                debug_log "Provider detection from AS number: $provider"
            else
                provider="overseas"
                debug_log "Non-Japanese ISP detected: $country"
            fi
            
            # キャッシュファイル作成
            echo "# ISP情報 $(date)" > "$cache_file"
            echo "ISP_NAME=\"$isp\"" >> "$cache_file"
            echo "ISP_AS=\"$as_num\"" >> "$cache_file"
            echo "ISP_ORG=\"$org\"" >> "$cache_file"
            echo "ISP_COUNTRY=\"$country\"" >> "$cache_file"
            echo "CONNECTION_TYPE=\"$provider\"" >> "$cache_file"
            echo "HAS_IPV6=\"$has_ipv6\"" >> "$cache_file"
            [ -n "$ipv6_addr" ] && echo "IPV6_ADDRESS=\"$ipv6_addr\"" >> "$cache_file"
        else
            debug_log "Failed to retrieve ISP information from API"
            rm -f "$tmp_file" 2>/dev/null
        fi
        
        rm -f "$tmp_file" 2>/dev/null
    else
        # IPv6で判定できた場合はより詳細な情報をAPIから取得してキャッシュに保存
        debug_log "IPv6 detection successful, getting additional ISP info"
        
        local tmp_file
        tmp_file=$(mktemp -t isp.XXXXXX)
        
        $BASE_WGET -O "$tmp_file" "http://ip-api.com/json?fields=isp,as,org,country,countryCode" >/dev/null 2>&1
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            local isp=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
            local as_num=$(grep -o '"as":"[^"]*' "$tmp_file" | sed 's/"as":"//')
            local org=$(grep -o '"org":"[^"]*' "$tmp_file" | sed 's/"org":"//')
            local country=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
            
            debug_log "Retrieved additional ISP info - Name: $isp, AS: $as_num, Org: $org"
            
            # キャッシュファイル作成
            echo "# ISP情報 $(date)" > "$cache_file"
            echo "ISP_NAME=\"$isp\"" >> "$cache_file"
            echo "ISP_AS=\"$as_num\"" >> "$cache_file"
            echo "ISP_ORG=\"$org\"" >> "$cache_file"
            echo "ISP_COUNTRY=\"$country\"" >> "$cache_file"
            echo "CONNECTION_TYPE=\"$provider\"" >> "$cache_file"
            echo "HAS_IPV6=\"$has_ipv6\"" >> "$cache_file"
            echo "IPV6_ADDRESS=\"$ipv6_addr\"" >> "$cache_file"
        else
            debug_log "Failed to retrieve additional ISP information"
            rm -f "$tmp_file" 2>/dev/null
            
            # 最低限の情報でキャッシュ保存
            echo "# ISP情報 $(date)" > "$cache_file"
            echo "CONNECTION_TYPE=\"$provider\"" >> "$cache_file"
            echo "HAS_IPV6=\"$has_ipv6\"" >> "$cache_file"
            echo "IPV6_ADDRESS=\"$ipv6_addr\"" >> "$cache_file"
        fi
        
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    # 結果表示
    if [ $show_result -eq 1 ]; then
        stop_spinner "$(get_message "MSG_ISP_INFO_SUCCESS")" "success"
        display_isp_info "$provider" "detected"
    fi
    
    debug_log "ISP detection completed with result: $provider"
    return 0
}

# ISP情報の表示
display_isp_info() {
    local provider="$1"
    local source="$2"
    
    printf "%s\n" "$(color blue "========= ISP接続判定結果 =========")"
    
    if [ "$source" = "cached" ]; then
        printf "%s\n" "$(get_message "MSG_ISP_INFO_SOURCE" "source=キャッシュ")"
    else
        printf "%s\n" "$(get_message "MSG_ISP_INFO_SOURCE" "source=検出")"
    fi
    
    printf "%s %s\n\n" "$(get_message "MSG_ISP_TYPE")" "$(color cyan "$provider")"
    
    case "$provider" in
        mape_ocn)
            printf "%s\n" "$(color white "【 OCN IPv6 (MAP-E)接続 】")"
            printf "%s\n" "$(color white "NTT Communicationsが提供するOCN IPv6サービスです。")"
            printf "%s\n" "$(color white "IPv4 over IPv6のMAP-E方式を採用しています。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_v6plus)
            printf "%s\n" "$(color white "【 SoftBank V6プラス接続 】")"
            printf "%s\n" "$(color white "SoftBankが提供するIPv6接続サービスです。")"
            printf "%s\n" "$(color white "MAP-E方式でIPv4 over IPv6通信を行います。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_ipv6option)
            printf "%s\n" "$(color white "【 KDDI IPv6オプション接続 】")"
            printf "%s\n" "$(color white "KDDIが提供するMAP-E方式のIPv6接続サービスです。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_nuro)
            printf "%s\n" "$(color white "【 NURO光 MAP-E接続 】")"
            printf "%s\n" "$(color white "So-netが提供するNURO光のMAP-E接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_biglobe)
            printf "%s\n" "$(color white "【 BIGLOBE IPv6接続 】")"
            printf "%s\n" "$(color white "BIGLOBEが提供するMAP-E方式のIPv6接続サービスです。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_jpne)
            printf "%s\n" "$(color white "【 JPNE IPv6接続 】")"
            printf "%s\n" "$(color white "日本ネットワークイネイブラーが提供するMAP-E接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_sonet)
            printf "%s\n" "$(color white "【 So-net IPv6接続 】")"
            printf "%s\n" "$(color white "So-netが提供するMAP-E方式のIPv6接続サービスです。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        mape_nifty)
            printf "%s\n" "$(color white "【 @nifty IPv6接続 】")"
            printf "%s\n" "$(color white "@niftyが提供するMAP-E方式のIPv6接続サービスです。")"
            printf "%s\n" "$(color yellow "設定ポイント: MTU値は1460に設定します。")"
            ;;
        dslite_east_transix)
            printf "%s\n" "$(color white "【 NTT東日本 DS-Lite接続 (transix) 】")"
            printf "%s\n" "$(color white "NTT東日本が提供するIPv6 IPoE + DS-Lite接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・ホスト名: mgw.transix.jp")"
            printf "%s\n" "$(color yellow "・IPv6アドレス: 2404:8e01::feed:100")"
            printf "%s\n" "$(color yellow "MTU値は1500のままで構いません。")"
            ;;
        dslite_west_transix)
            printf "%s\n" "$(color white "【 NTT西日本 DS-Lite接続 (transix) 】")"
            printf "%s\n" "$(color white "NTT西日本が提供するIPv6 IPoE + DS-Lite接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・ホスト名: mgw.transix.jp")"
            printf "%s\n" "$(color yellow "・IPv6アドレス: 2404:8e00::feed:100")"
            printf "%s\n" "$(color yellow "MTU値は1500のままで構いません。")"
            ;;
        dslite_transix)
            printf "%s\n" "$(color white "【 DS-Lite接続 (transix) 】")"
            printf "%s\n" "$(color white "IPv6 IPoE + DS-Lite接続（トランジックス）です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・東日本の場合: mgw.transix.jp (2404:8e01::feed:100)")"
            printf "%s\n" "$(color yellow "・西日本の場合: mgw.transix.jp (2404:8e00::feed:100)")"
            printf "%s\n" "$(color yellow "お住まいの地域により設定が異なります。")"
            ;;
        dslite_xpass)
            printf "%s\n" "$(color white "【 DS-Lite接続 (xpass) 】")"
            printf "%s\n" "$(color white "IPv6 IPoE + DS-Lite接続（クロスパス）です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・ホスト名: dgw.xpass.jp")"
            printf "%s\n" "$(color yellow "MTU値は1500のままで構いません。")"
            ;;
        dslite_v6connect)
            printf "%s\n" "$(color white "【 DS-Lite接続 (v6connect) 】")"
            printf "%s\n" "$(color white "IPv6 IPoE + DS-Lite接続（V6コネクト）です。")"
            printf "%s\n" "$(color yellow "設定ポイント: AFTRホスト設定")"
            printf "%s\n" "$(color yellow "・ホスト名: aft.v6connect.net")"
            printf "%s\n" "$(color yellow "MTU値は1500のままで構いません。")"
            ;;
        dslite_east)
            printf "%s\n" "$(color white "【 NTT東日本 DS-Lite接続 】")"
            printf "%s\n" "$(color white "NTT東日本が提供するIPv6 IPoE + DS-Lite接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: 主要なAFTRは次のいずれかです。")"
            printf "%s\n" "$(color yellow "・トランジックス: mgw.transix.jp (2404:8e01::feed:100)")"
            printf "%s\n" "$(color yellow "・クロスパス: dgw.xpass.jp")"
            printf "%s\n" "$(color yellow "・V6コネクト: aft.v6connect.net")"
            printf "%s\n" "$(color yellow "ご利用のプロバイダにより対応するAFTRが異なります。")"
            ;;
        dslite_west)
            printf "%s\n" "$(color white "【 NTT西日本 DS-Lite接続 】")"
            printf "%s\n" "$(color white "NTT西日本が提供するIPv6 IPoE + DS-Lite接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: 主要なAFTRは次のいずれかです。")"
            printf "%s\n" "$(color yellow "・トランジックス: mgw.transix.jp (2404:8e00::feed:100)")"
            printf "%s\n" "$(color yellow "・クロスパス: dgw.xpass.jp")"
            printf "%s\n" "$(color yellow "・V6コネクト: aft.v6connect.net")"
            printf "%s\n" "$(color yellow "ご利用のプロバイダにより対応するAFTRが異なります。")"
            ;;
        dslite*)
            printf "%s\n" "$(color white "【 DS-LITE接続 】")"
            printf "%s\n" "$(color white "DS-LITE方式を使用したIPv4 over IPv6接続です。")"
            printf "%s\n" "$(color white "東西の判定ができませんでした。")"
            printf "%s\n" "$(color yellow "設定ポイント: 主要なAFTRは次のいずれかです。")"
            printf "%s\n" "$(color yellow "・トランジックス: mgw.transix.jp")"
            printf "%s\n" "$(color yellow "  東日本: 2404:8e01::feed:100")"
            printf "%s\n" "$(color yellow "  西日本: 2404:8e00::feed:100")"
            printf "%s\n" "$(color yellow "・クロスパス: dgw.xpass.jp")"
            printf "%s\n" "$(color yellow "・V6コネクト: aft.v6connect.net")"
            ;;
        pppoe_ctc)
            printf "%s\n" "$(color white "【 中部テレコム PPPoE接続 】")"
            printf "%s\n" "$(color white "中部テレコミュニケーション株式会社が提供するPPPoE接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: 標準的なPPPoE設定で問題ありません。")"
            ;;
        pppoe_iij)
            printf "%s\n" "$(color white "【 IIJ PPPoE接続 】")"
            printf "%s\n" "$(color white "IIJが提供するPPPoE接続です。")"
            printf "%s\n" "$(color yellow "設定ポイント: 標準的なPPPoE設定で問題ありません。")"
            ;;
        overseas)
            printf "%s\n" "$(color white "【 海外ISP接続 】")"
            printf "%s\n" "$(color white "日本国外のISPが検出されました。")"
            printf "%s\n" "$(color white "日本のISP判定には対応していません。")"
            ;;
        *)
            printf "%s\n" "$(color white "【 不明な接続タイプ 】")"
            printf "%s\n" "$(color white "接続タイプを特定できませんでした。")"
            printf "%s\n" "$(color white "IPv6プレフィックスやAS情報から判断できません。")"
            printf "%s\n" "$(color yellow "ご契約のインターネットプロバイダに確認してください。")"
            ;;
    esac
    
    printf "\n%s\n" "$(color blue "====================================")"
    
    # キャッシュファイルの場所を表示
    printf "%s %s\n\n" "$(get_message "MSG_ISP_CACHE_PATH")" "$(color "green" "${CACHE_DIR}/isp.ch")"
}

# 単体実行時の処理
if [ "$(basename "$0")" = "detect_isp.sh" ]; then
    detect_isp_type "$@"
fi

# 🔴　IS判定　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------
