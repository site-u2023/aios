#!/bin/sh

SCRIPT_VERSION="2025.04.08-00-01"

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

# API設定
API_TIMEOUT="${API_TIMEOUT:-5}"
API_MAX_RETRIES="${API_MAX_RETRIES:-5}"

# 🔵　デバイス　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

display_detected_device() {
    local network=$(cat "${CACHE_DIR}/network.ch")
    local architecture=$(cat "${CACHE_DIR}/architecture.ch")
    local osversion=$(cat "${CACHE_DIR}/osversion.ch")
    local package_manager=$(cat "${CACHE_DIR}/package_manager.ch")
    local usbdevice=$(cat "${CACHE_DIR}/usbdevice.ch")

    # ファイルが存在しない場合のみメッセージを表示
    if [ ! -f "${CACHE_DIR}/message.ch" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_INFO_DEVICE")")"
    fi
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_NETWORK" "info=$network")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_ARCHITECTURE" "info=$architecture")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_OSVERSION" "info=$osversion")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_PACKAGEMANAGER" "info=$package_manager")")"
    printf "%s\n" "$(color white "$(get_message "MSG_INFO_USBDEVICE" "info=$usbdevice")")"
    printf "\n"
}

# 🔴　デバイス　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　ISP　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

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

# ISP情報取得関数
get_isp_info() {
    # 変数宣言
    local ip_address=""
    local network_type=""
    local timeout_sec=$API_TIMEOUT
    local tmp_file=""
    local api_url=""
    local spinner_active=0
    local retry_count=0
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
            
            # キャッシュに保存（キャッシュタイムアウトが0でない場合）
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
    
    # IPアドレスの取得（リトライロジック追加）
    retry_count=0
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        debug_log "DEBUG: Querying IP address from $api_url (attempt $(($retry_count+1))/$API_MAX_RETRIES)"
        
        tmp_file="$(mktemp -t isp.XXXXXX)"
        $BASE_WGET -O "$tmp_file" "$api_url" -T $timeout_sec 2>/dev/null
        wget_status=$?
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            ip_address=$(cat "$tmp_file")
            rm -f "$tmp_file"
            debug_log "DEBUG: Retrieved IP address: $ip_address"
            break
        else
            debug_log "DEBUG: IP address query failed, retrying..."
            rm -f "$tmp_file" 2>/dev/null
            retry_count=$(($retry_count + 1))
            [ $retry_count -lt $API_MAX_RETRIES ] && sleep 1
        fi
    done
    
    # IPアドレスが取得できたかチェック
    if [ -z "$ip_address" ]; then
        debug_log "DEBUG: Failed to retrieve any IP address after $API_MAX_RETRIES attempts"
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
    
    # ISP情報の取得（リトライロジック追加）
    retry_count=0
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        debug_log "DEBUG: Querying ISP information for IP: $ip_address (attempt $(($retry_count+1))/$API_MAX_RETRIES)"
        
        tmp_file="$(mktemp -t isp.XXXXXX)"
        $BASE_WGET -O "$tmp_file" "http://ip-api.com/json/${ip_address}?fields=isp,as,org" -T $timeout_sec 2>/dev/null
        wget_status=$?
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # JSON解析
            ISP_NAME=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
            ISP_AS=$(grep -o '"as":"[^"]*' "$tmp_file" | sed 's/"as":"//')
            ISP_ORG=$(grep -o '"org":"[^"]*' "$tmp_file" | sed 's/"org":"//')
            
            debug_log "DEBUG: Retrieved ISP info - Name: $ISP_NAME, AS: $ISP_AS, Organization: $ISP_ORG"
            rm -f "$tmp_file"
            
            # 正常にデータが取得できたかチェック
            if [ -n "$ISP_NAME" ]; then
                # キャッシュに保存（キャッシュタイムアウトが0でない場合）
                if [ $cache_timeout -ne 0 ]; then
                    echo "$ISP_NAME" > "$cache_file"
                    echo "$ISP_AS" >> "$cache_file"
                    echo "$ISP_ORG" >> "$cache_file"
                    debug_log "DEBUG: Saved ISP information to cache"
                fi
                break
            else
                debug_log "DEBUG: ISP information retrieved but empty, retrying..."
                retry_count=$(($retry_count + 1))
                [ $retry_count -lt $API_MAX_RETRIES ] && sleep 1
            fi
        else
            debug_log "DEBUG: ISP information query failed, retrying..."
            rm -f "$tmp_file" 2>/dev/null
            retry_count=$(($retry_count + 1))
            [ $retry_count -lt $API_MAX_RETRIES ] && sleep 1
        fi
    done
    
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

# 🔴　ISP　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　ロケーション　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

# 検出した地域情報を表示する共通関数
display_detected_location() {
    local detection_source="$1"
    local detected_country="$2"
    local detected_zonename="$3"
    local detected_timezone="$4"
    local show_success_message="${5:-false}"
    
    debug_log "DEBUG" "Displaying location information from source: $detection_source"
    
    # 検出情報表示
    local msg_info=$(get_message "MSG_USE_DETECTED_INFORMATION")
    msg_info=$(echo "$msg_info" | sed "s/{info}/$detection_source/g")
    printf "%s\n" "$(color white "$msg_info")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_COUNTRY")")" "$(color white "$detected_country")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ZONENAME")")" "$(color white "$detected_zonename")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_TIMEZONE")")" "$(color white "$detected_timezone")"
    
    # 成功メッセージの表示（オプション）
    if [ "$show_success_message" = "true" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"
        printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
        printf "\n"
        EXTRA_SPACING_NEEDED="yes"
        debug_log "DEBUG" "Success messages displayed"
    fi
    
    debug_log "DEBUG" "Location information displayed successfully"
}

# 国コードとタイムゾーン情報を取得する関数

# worldtimeapi.orgからタイムゾーン情報を取得する関数
get_timezone_worldtime() {
    local tmp_file="$1"      # 一時ファイルパス
    local network_type="$2"  # ネットワークタイプ
    local api_url="$3"       # API URL（第3引数で受け取る）
    
    local retry_count=0
    local success=0
    
    # スピナー更新メッセージ
    local tz_msg=$(get_message "MSG_QUERY_INFO" "type=timezone" "api=worldtimeapi.org" "network=$network_type")
    update_spinner "$(color "blue" "$tz_msg")" "yellow"
    
    debug_log "DEBUG" "Querying timezone from worldtimeapi.org"
    
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        $BASE_WGET -O "$tmp_file" "$api_url" -T $API_TIMEOUT 2>/dev/null
        local wget_status=$?
        debug_log "DEBUG" "wget exit code: $wget_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # JSONデータからタイムゾーン情報を抽出
            SELECT_ZONENAME=$(grep -o '"timezone":"[^"]*' "$tmp_file" | sed 's/"timezone":"//')
            SELECT_TIMEZONE=$(grep -o '"abbreviation":"[^"]*' "$tmp_file" | sed 's/"abbreviation":"//')
            local utc_offset=$(grep -o '"utc_offset":"[^"]*' "$tmp_file" | sed 's/"utc_offset":"//')
            
            # データが正常に取得できたか確認
            if [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ]; then
                debug_log "DEBUG" "Retrieved timezone from worldtimeapi.org: $SELECT_ZONENAME ($SELECT_TIMEZONE)"
                
                # POSIX形式のタイムゾーン文字列を生成
                if [ -n "$utc_offset" ]; then
                    local offset_sign=$(echo "$utc_offset" | cut -c1)
                    local offset_hours=$(echo "$utc_offset" | cut -c2-3 | sed 's/^0//')
                    
                    if [ "$offset_sign" = "+" ]; then
                        SELECT_POSIX_TZ="${SELECT_TIMEZONE}-${offset_hours}"
                    else
                        SELECT_POSIX_TZ="${SELECT_TIMEZONE}${offset_hours}"
                    fi
                    
                    debug_log "DEBUG" "Generated POSIX timezone: $SELECT_POSIX_TZ"
                fi
                
                success=1
                break
            else
                debug_log "DEBUG" "Incomplete timezone data from worldtimeapi.org"
            fi
        fi
        
        debug_log "DEBUG" "worldtimeapi.org query attempt $((retry_count+1)) failed"
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $API_MAX_RETRIES ] && sleep 1
    done
    
    # 成功した場合は0を、失敗した場合は1を返す（シェルの慣習に合わせる）
    if [ $success -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

# ipinfo.ioからタイムゾーン情報を取得する関数
get_timezone_ipinfo() {
    local tmp_file="$1"      # 一時ファイルパス
    local network_type="$2"  # ネットワークタイプ
    local api_name="$3"      # API名（ログ用）
    
    local retry_count=0
    local success=0
    
    # スピナー更新メッセージ
    local tz_msg=$(get_message "MSG_QUERY_INFO" "type=timezone" "api=ipinfo.io" "network=$network_type")
    update_spinner "$(color "blue" "$tz_msg")" "yellow"
    
    debug_log "DEBUG" "Querying timezone from ipinfo.io"
    
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        $BASE_WGET -O "$tmp_file" "$api_name" -T $API_TIMEOUT 2>/dev/null
        local wget_status=$?
        debug_log "DEBUG" "wget exit code: $wget_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # JSONデータからタイムゾーン情報を抽出
            local ipinfo_timezone=$(grep -o '"timezone":"[^"]*' "$tmp_file" | sed 's/"timezone":"//')
            
            # タイムゾーン情報が取得できたか確認
            if [ -n "$ipinfo_timezone" ]; then
                # タイムゾーン情報を設定
                SELECT_ZONENAME="$ipinfo_timezone"
                debug_log "DEBUG" "Retrieved timezone from ipinfo.io: $SELECT_ZONENAME"
                
                # タイムゾーン略称を生成（例：Asia/Tokyo → TOK）
                SELECT_TIMEZONE=$(echo "$SELECT_ZONENAME" | awk -F'/' '{print $NF}' | cut -c1-3 | tr '[:lower:]' '[:upper:]')
                debug_log "DEBUG" "Generated timezone abbreviation: $SELECT_TIMEZONE"
                
                success=1
                break
            else
                debug_log "DEBUG" "No timezone data from ipinfo.io response"
            fi
        fi
        
        debug_log "DEBUG" "ipinfo.io query attempt $((retry_count+1)) failed"
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $API_MAX_RETRIES ] && sleep 1
    done
    
    # 成功した場合は0を、失敗した場合は1を返す
    if [ $success -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

# 国コード・タイムゾーン情報を取得する関数
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
    local API_IPINFO="http://ipinfo.io"
    
    # パラメータ（タイムゾーンAPIの種類）
    # "http://worldtimeapi.org/api/ip" または "http://ipinfo.io"
    local timezone_api="${1:-$API_IPINFO}"
    
    # タイムゾーンAPIと関数のマッピング
    local tz_func=""
    case "$timezone_api" in
        "$API_WORLDTIME")
            tz_func="get_timezone_worldtime"
            ;;
        "$API_IPINFO")
            tz_func="get_timezone_ipinfo"
            ;;
    esac
    
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
        debug_log "DEBUG" "Network connectivity information not available, running check"
        check_network_connectivity
        
        if [ -f "${CACHE_DIR}/network.ch" ]; then
            network_type=$(cat "${CACHE_DIR}/network.ch")
            debug_log "DEBUG" "Network type after check: $network_type"
        else
            network_type="unknown"
            debug_log "DEBUG" "Network type still unknown after check"
        fi
    fi
    
    # 接続がない場合は早期リターン
    if [ -z "$network_type" ]; then
        debug_log "DEBUG" "No network connectivity, cannot proceed"
        return 1
    fi
    
    # スピナー開始
    local init_msg=$(get_message "MSG_QUERY_INFO" "type=IP address" "api=ipify.org" "network=$network_type")
    start_spinner "$(color "blue" "$init_msg")" "yellow"
    spinner_active=1
    debug_log "DEBUG" "Starting IP and location detection process"
    
    # IPアドレスの取得（ネットワークタイプに応じて適切なAPIを選択）
    if [ "$network_type" = "v4" ] || [ "$network_type" = "v4v6" ]; then
        # IPv4を使用（デュアルスタックでも常にIPv4を優先）
        debug_log "DEBUG" "Using IPv4 API (preferred for dual-stack or v4-only)"
        api_url="$API_IP_V4"
    elif [ "$network_type" = "v6" ]; then
        # IPv6のみ
        debug_log "DEBUG" "Using IPv6 API (v6-only environment)"
        api_url="$API_IP_V6"
    else
        # 不明なタイプ - デフォルトでIPv4
        debug_log "DEBUG" "Unknown network type, defaulting to IPv4 API"
        api_url="$API_IP_V4"
    fi
    
    # 選択したAPIを使用してIPアドレスを取得（リトライロジック付き）
    debug_log "DEBUG" "Querying IP address from $api_url"
    
    retry_count=0
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        tmp_file="$(mktemp -t isp.XXXXXX)"
        $BASE_WGET -O "$tmp_file" "$api_url" -T $API_TIMEOUT 2>/dev/null
        wget_status=$?
        debug_log "DEBUG" "wget exit code: $wget_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            ip_address=$(cat "$tmp_file")
            rm -f "$tmp_file"
            debug_log "DEBUG" "Retrieved IP address: $ip_address"
            break
        else
            debug_log "DEBUG" "IP address query failed, retrying..."
            rm -f "$tmp_file" 2>/dev/null
            retry_count=$((retry_count + 1))
            sleep 1
        fi
    done
    
    # IPアドレスが取得できたかチェック
    if [ -z "$ip_address" ]; then
        debug_log "DEBUG" "Failed to retrieve IP address after $API_MAX_RETRIES attempts"
        if [ $spinner_active -eq 1 ]; then
            local fail_msg=$(get_message "MSG_LOCATION_RESULT" "status=failed")
            stop_spinner "$fail_msg" "failed"
            spinner_active=0
        fi
        return 1
    fi
    
    # 国コードの取得（ip-api.comから）
    local country_msg=$(get_message "MSG_QUERY_INFO" "type=country code" "api=ip-api.com" "network=$network_type")
    update_spinner "$(color "blue" "$country_msg")" "yellow"
    debug_log "DEBUG" "Querying country code from ip-api.com for IP: $ip_address"
    
    retry_count=0
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        tmp_file="$(mktemp -t location.XXXXXX)"
        # URLの構築方法を修正
        debug_log "DEBUG" "Using API URL: ${API_LOCATION}/${ip_address}"
        $BASE_WGET -O "$tmp_file" "${API_LOCATION}/${ip_address}" -T $API_TIMEOUT 2>/dev/null
        wget_status=$?
        debug_log "DEBUG" "wget exit code for country query: $wget_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"
        
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            SELECT_COUNTRY=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
            debug_log "DEBUG" "Retrieved country code: $SELECT_COUNTRY"
            rm -f "$tmp_file"
            break
        else
            debug_log "DEBUG" "Country code query failed, retrying..."
            rm -f "$tmp_file" 2>/dev/null
            retry_count=$((retry_count + 1))
            sleep 1
        fi
    done
    
    # タイムゾーン情報の取得（マッピングした関数を使用）
    tmp_file="$(mktemp -t timezone.XXXXXX)"
    debug_log "DEBUG" "Calling timezone function: $tz_func for API: $timezone_api"
    
    # 動的に関数を呼び出し
    $tz_func "$tmp_file" "$network_type" "$timezone_api"
    local tz_success=$?
    
    # 一時ファイルの削除
    rm -f "$tmp_file" 2>/dev/null
    
    # 結果のチェックとスピナー停止
    if [ $spinner_active -eq 1 ]; then
        if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ]; then
            local success_msg=$(get_message "MSG_LOCATION_RESULT" "status=success")
            stop_spinner "$success_msg" "success"
            debug_log "DEBUG" "Location information retrieved successfully"
            return 0
        else
            local fail_msg=$(get_message "MSG_LOCATION_RESULT" "status=failed")
            stop_spinner "$fail_msg" "failed"
            debug_log "DEBUG" "Location information process failed - incomplete data received"
            return 1
        fi
    fi
    
    return 1
}

# 🔴　ロケーション　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------
