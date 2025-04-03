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

# ローカルISPデータベースをダウンロードする関数
download_isp_database() {
    local db_url="${BASE_URL}/isp.db"
    local db_file="${BASE_DIR}/isp.db"
    local tmp_file
    local timeout_sec=30
    
    debug_log "DEBUG: Downloading ISP database from $db_url"
    
    # スピナー開始（利用可能な場合）
    if type start_spinner >/dev/null 2>&1; then
        start_spinner "$(color "blue" "$(get_message "MSG_DOWNLOADING_ISP_DB")")" "yellow"
    fi
    
    # 既存DBファイルのバックアップ（存在する場合）
    if [ -f "$db_file" ]; then
        mv "$db_file" "${db_file}.bak"
        debug_log "DEBUG: Backed up existing ISP database"
    fi
    
    # データベースのダウンロード
    tmp_file="$(mktemp -t ispdb.XXXXXX)"
    $BASE_WGET -O "$tmp_file" "$db_url" --timeout=$timeout_sec -T $timeout_sec 2>/dev/null
    
    # ダウンロード結果の確認
    if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        # 一時ファイルを移動
        mv "$tmp_file" "$db_file"
        
        # スピナー停止（利用可能な場合）
        if type stop_spinner >/dev/null 2>&1; then
            stop_spinner "$(get_message "MSG_ISP_DB_SUCCESS")" "success"
        fi
        
        debug_log "DEBUG: ISP database downloaded successfully"
        return 0
    else
        # 失敗した場合、バックアップから復元
        if [ -f "${db_file}.bak" ]; then
            mv "${db_file}.bak" "$db_file"
            debug_log "DEBUG: Restored ISP database from backup"
            
            # 復元メッセージ（オプション）
            if type update_spinner >/dev/null 2>&1; then
                update_spinner "$(get_message "MSG_ISP_DB_RESTORED")" "yellow"
            fi
        fi
        
        # 一時ファイル削除
        rm -f "$tmp_file" 2>/dev/null
        
        # スピナー停止（利用可能な場合）
        if type stop_spinner >/dev/null 2>&1; then
            stop_spinner "$(get_message "MSG_ISP_DB_FAILED")" "failed"
        fi
        
        debug_log "DEBUG: Failed to download ISP database"
        return 1
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
