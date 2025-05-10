#!/bin/sh

SCRIPT_VERSION="2025.05.10-00-00"

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

# API定数
API_TIMEOUT="${API_TIMEOUT:-5}"
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"
API_MAX_REDIRECTS="${API_MAX_REDIRECTS:-2}"
TIMEZONE_API_SOURCE=""
USER_AGENT="aios-script/${SCRIPT_VERSION:-unknown}"
API_PROVIDERS="get_country_cloudflare get_country_ipapi get_country_ipinfo"

SELECT_REGION_NAME=""

# NTP pool自動設定＆同期関数
setup_ntp() {
    # キャッシュから国コード取得
    local country_code=""
    if [ -f "${CACHE_DIR}/language.ch" ]; then
        country_code=$(cat "${CACHE_DIR}/language.ch" | tr '[:upper:]' '[:lower:]')
    elif [ -f "${CACHE_DIR}/country.ch" ]; then
        # country.chの5列目が国コード（JP,US等）
        country_code=$(awk '{ print tolower($5) }' "${CACHE_DIR}/country.ch" | head -n 1)
    fi

    # キャッシュが無い場合・空の場合は何もしない
    if [ -z "$country_code" ]; then
        debug_log "DEBUG" "setup_ntp: No country code found in cache. Skipping NTP setup."
        return 0
    fi

    # 既存のNTPサーバ設定を取得
    local ntp_servers_current=""
    ntp_servers_current=$(uci get system.@system[0].ntpserver 2>/dev/null)

    # デフォルト値が「0.openwrt.pool.ntp.org」のみなら上書き可
    if [ "$ntp_servers_current" != "0.openwrt.pool.ntp.org" ]; then
        debug_log "DEBUG" "setup_ntp: NTP servers already customized. Skipping overwrite."
        return 0
    fi

    # 国コードからNTP pool名を生成
    local ntp_test_host="0.${country_code}.pool.ntp.org"
    local ntp_servers="0.${country_code}.pool.ntp.org 1.${country_code}.pool.ntp.org 2.${country_code}.pool.ntp.org 3.${country_code}.pool.ntp.org"

    # 生成したNTP poolが疎通可能か確認（pingで2秒以内に応答必須）
    if ping -c 1 -w 2 "$ntp_test_host" >/dev/null 2>&1; then
        debug_log "DEBUG" "setup_ntp: $ntp_test_host is reachable. Setting NTP servers."
        # NTPサーバを4つ全てセット
        uci set system.@system[0].ntpserver="$ntp_servers"
        uci commit system
        # 即時時刻同期（失敗時もエラー出さず終了）
        ntpd -n -q -p "$ntp_test_host" >/dev/null 2>&1
    else
        debug_log "DEBUG" "setup_ntp: $ntp_test_host is NOT reachable. Keeping default NTP config."
        # 何も変更しない
        return 0
    fi

    return 0
}

# APIリクエストを実行する関数（リダイレクト、タイムアウト、リトライ対応）
make_api_request() {
    # パラメータ
    local url="$1"
    local tmp_file="$2"
    local timeout="${3:-$API_TIMEOUT}"
    local debug_tag="${4:-API}"
    local user_agent="$5"

    # UAが空の場合のデフォルト設定
    if [ -z "$user_agent" ]; then
        user_agent="$USER_AGENT"
    fi

    # wgetの機能検出
    local wget_capability=$(detect_wget_capabilities)
    local used_url="$url"
    local status=0

    debug_log "DEBUG" "[$debug_tag] Making API request to: $url"
    debug_log "DEBUG" "[$debug_tag] Using User-Agent: $user_agent"

    # 最適なwget実行
    case "$wget_capability" in
        "full")
            debug_log "DEBUG" "[$debug_tag] Using full wget with redirect support"
            wget --no-check-certificate -q -L --max-redirect="${API_MAX_REDIRECTS:-2}" \
                 -U "$user_agent" \
                 -O "$tmp_file" "$used_url" -T "$timeout" 2>/dev/null
            status=$?
            ;;
        "https_only"|"basic")
            used_url=$(echo "$url" | sed 's|^http:|https:|')
            debug_log "DEBUG" "[$debug_tag] Using BusyBox wget, forcing HTTPS URL: $used_url"
            wget --no-check-certificate -q -U "$user_agent" \
                 -O "$tmp_file" "$used_url" -T "$timeout" 2>/dev/null
            status=$?
            ;;
    esac

    if [ $status -eq 0 ] && [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        debug_log "DEBUG" "[$debug_tag] API request successful"
        return 0
    else
        debug_log "DEBUG" "[$debug_tag] API request failed with status: $status"
        return $status
    fi
}

get_country_ipapi() {
    local tmp_file="$1"
    local network_type="$2"
    local api_name="$3" # Optional API URL override

    local retry_count=0
    local success=0
    local api_domain=""
    local wget_options="" # wget options based on network_type
    local wget_exit_code=0

    # --- v4/v6 制御ロジック開始 ---
    # APIエンドポイント設定 (引数があれば優先、なければデフォルト)
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://ipapi.co/json"
    fi

    # API URLからドメイン名を抽出 (表示用)
    api_domain=$(echo "$api_url" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$api_url" # フォールバック
    debug_log "DEBUG" "get_country_ipapi: Using API domain: $api_domain"

    # ネットワークタイプに基づいてwgetオプションを設定
    case "$network_type" in
        "v4") wget_options="-4" ;;
        "v6") wget_options="-6" ;;
        "v4v6") wget_options="-4" ;; # 初期値 -4
        *) wget_options="" ;;
    esac
    debug_log "DEBUG" "get_country_ipapi: Initial wget options: ${wget_options}"
    # --- v4/v6 制御ロジックここまで ---

    debug_log "DEBUG" "get_country_ipapi: Querying country and timezone from $api_domain"

    # --- make_api_request の代わりに直接 wget を実行するループ ---
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        debug_log "DEBUG" "get_country_ipapi: Attempt (Try $((retry_count + 1))/${API_MAX_RETRIES}) options: '${wget_options}' URL: '${api_url}'"

        # v4v6の場合、リトライ時にネットワークタイプを切り替え
        if [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ]; then
             if echo "$wget_options" | grep -q -- "-4"; then
                 wget_options="-6"
             else
                 wget_options="-4"
             fi
             debug_log "DEBUG" "get_country_ipapi: Retrying with wget option: $wget_options for v4v6"
        fi

        # wget コマンド実行 (不正なオプション --tries=1 と -L を削除)
        wget --no-check-certificate $wget_options -T "$API_TIMEOUT" -q -O "$tmp_file" \
             -U "$USER_AGENT" \
             "$api_url"
        wget_exit_code=$?
        debug_log "DEBUG" "get_country_ipapi: wget executed (code: $wget_exit_code)"

        # レスポンスチェック (変更なし)
        if [ "$wget_exit_code" -eq 0 ] && [ -s "$tmp_file" ]; then
            debug_log "DEBUG" "get_country_ipapi: Download successful (code: 0, size > 0)."
            # 必要な情報を抽出 (ok/ 版 translation 準拠の sed)
            SELECT_COUNTRY=$(grep '"country"' "$tmp_file" | sed -n 's/.*"country": *"\([^"]*\)".*/\1/p')
            SELECT_ZONENAME=$(grep '"timezone"' "$tmp_file" | sed -n 's/.*"timezone": *"\([^"]*\)".*/\1/p')

            # 必須情報が取得できたか確認
            if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                debug_log "DEBUG" "get_country_ipapi: Retrieved from $api_domain - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME"
                success=1
                TIMEZONE_API_SOURCE="$api_domain" # 成功時にAPIソースを設定
                break # 成功したのでループを抜ける
            else
                # 抽出失敗
                debug_log "DEBUG" "get_country_ipapi: Incomplete country/timezone data from $api_domain response."
                # エラーメッセージがあればログ出力
                local error_message=$(grep -o '"message":[^\}]*' "$tmp_file")
                [ -n "$error_message" ] && debug_log "DEBUG" "get_country_ipapi: API Error message found: $error_message"
            fi
        else
            # wget 失敗またはファイル空
            debug_log "DEBUG" "get_country_ipapi: wget failed (code: $wget_exit_code) or temp file is empty."
        fi

        # リトライ前の処理 (変更なし)
        rm -f "$tmp_file" 2>/dev/null # 次のリトライに備えて一時ファイルを削除
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            debug_log "DEBUG" "get_country_ipapi: Retrying after 1 second sleep..."
            sleep 1
        fi
    done
    # --- ループ終了 ---

    # 最終的な成功/失敗の判定と戻り値 (変更なし)
    if [ $success -eq 1 ]; then
        debug_log "DEBUG" "get_country_ipapi finished successfully."
        return 0 # 成功
    else
        debug_log "DEBUG" "get_country_ipapi finished with failure after ${API_MAX_RETRIES} attempts."
        # 失敗した場合も念のため一時ファイルを削除
        rm -f "$tmp_file" 2>/dev/null
        return 1 # 失敗
    fi
}

get_country_ipinfo() {
    local tmp_file="$1"
    local network_type="$2"
    local api_name="$3" # Optional API URL override

    local retry_count=0
    local success=0
    local api_domain=""
    local wget_options="" # wget options based on network_type
    local wget_exit_code=0

    # --- v4/v6 制御ロジック開始 ---
    # APIエンドポイント設定 (引数があれば優先、なければデフォルト)
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://ipinfo.io/json"
    fi

    # API URLからドメイン名を抽出 (表示用)
    api_domain=$(echo "$api_url" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$api_url" # フォールバック
    debug_log "DEBUG" "get_country_ipinfo: Using API domain: $api_domain"

    # ネットワークタイプに基づいてwgetオプションを設定
    case "$network_type" in
        "v4") wget_options="-4" ;;
        "v6") wget_options="-6" ;;
        "v4v6") wget_options="-4" ;; # 初期値 -4
        *) wget_options="" ;;
    esac
    debug_log "DEBUG" "get_country_ipinfo: Initial wget options: ${wget_options}"
    # --- v4/v6 制御ロジックここまで ---

    debug_log "DEBUG" "get_country_ipinfo: Querying country and timezone from $api_domain"

    # --- make_api_request の代わりに直接 wget を実行するループ ---
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        debug_log "DEBUG" "get_country_ipinfo: Attempt (Try $((retry_count + 1))/${API_MAX_RETRIES}) options: '${wget_options}' URL: '${api_url}'"

        # v4v6の場合、リトライ時にネットワークタイプを切り替え
        if [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ]; then
             if echo "$wget_options" | grep -q -- "-4"; then
                 wget_options="-6"
             else
                 wget_options="-4"
             fi
             debug_log "DEBUG" "get_country_ipinfo: Retrying with wget option: $wget_options for v4v6"
        fi

        # wget コマンド実行 (不正なオプション --tries=1 と -L を削除)
        wget --no-check-certificate $wget_options -T "$API_TIMEOUT" -q -O "$tmp_file" \
             -U "$USER_AGENT" \
             "$api_url"
        wget_exit_code=$?
        debug_log "DEBUG" "get_country_ipinfo: wget executed (code: $wget_exit_code)"

        # レスポンスチェック (変更なし)
        if [ "$wget_exit_code" -eq 0 ] && [ -s "$tmp_file" ]; then
            debug_log "DEBUG" "get_country_ipinfo: Download successful (code: 0, size > 0)."
            # 必要な情報を抽出
            SELECT_COUNTRY=$(grep '"country"' "$tmp_file" | sed -n 's/.*"country": *"\([^"]*\)".*/\1/p')
            SELECT_ZONENAME=$(grep '"timezone"' "$tmp_file" | sed -n 's/.*"timezone": *"\([^"]*\)".*/\1/p')

            # 必須情報が取得できたか確認
            if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                debug_log "DEBUG" "get_country_ipinfo: Retrieved from $api_domain - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME"
                success=1
                TIMEZONE_API_SOURCE="$api_domain" # 成功時にAPIソースを設定
                break # 成功したのでループを抜ける
            else
                # 抽出失敗
                debug_log "DEBUG" "get_country_ipinfo: Incomplete country/timezone data from $api_domain response."
                local error_message=$(grep -o '"message":[^\}]*' "$tmp_file")
                [ -n "$error_message" ] && debug_log "DEBUG" "get_country_ipinfo: API Error message found: $error_message"
            fi
        else
            # wget 失敗またはファイル空
            debug_log "DEBUG" "get_country_ipinfo: wget failed (code: $wget_exit_code) or temp file is empty."
        fi

        # リトライ前の処理 (変更なし)
        rm -f "$tmp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            debug_log "DEBUG" "get_country_ipinfo: Retrying after 1 second sleep..."
            sleep 1
        fi
    done
    # --- ループ終了 ---

    # 最終的な成功/失敗の判定と戻り値 (変更なし)
    if [ $success -eq 1 ]; then
        debug_log "DEBUG" "get_country_ipinfo finished successfully."
        return 0 # 成功
    else
        debug_log "DEBUG" "get_country_ipinfo finished with failure after ${API_MAX_RETRIES} attempts."
        rm -f "$tmp_file" 2>/dev/null
        return 1 # 失敗
    fi
}

get_country_cloudflare() {
    local tmp_file="$1"
    local network_type="$2"
    # この関数は特定の URL を使うため api_name 引数は無視する

    local api_url="https://location-api-worker.site-u.workers.dev" # 固定 URL
    local api_domain=""
    local retry_count=0
    local success=0
    local wget_options="" # wget options based on network_type
    local wget_exit_code=0

    # --- v4/v6 制御ロジック開始 ---
    # API URLからドメイン名を抽出 (表示用)
    api_domain=$(echo "$api_url" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$api_url" # フォールバック
    debug_log "DEBUG" "get_country_cloudflare: Using API domain: $api_domain"

    # ネットワークタイプに基づいてwgetオプションを設定
    case "$network_type" in
        "v4") wget_options="-4" ;;
        "v6") wget_options="-6" ;;
        "v4v6") wget_options="-4" ;; # 初期値 -4
        *) wget_options="" ;;
    esac
    debug_log "DEBUG" "get_country_cloudflare: Initial wget options: ${wget_options}"
    # --- v4/v6 制御ロジックここまで ---

    debug_log "DEBUG" "get_country_cloudflare: Querying location from $api_domain"

    # グローバル変数を初期化 (変更なし)
    SELECT_COUNTRY=""
    SELECT_ZONENAME=""
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    SELECT_REGION_NAME=""

    # --- make_api_request の代わりに直接 wget を実行するループ ---
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        debug_log "DEBUG" "get_country_cloudflare: Attempt (Try $((retry_count + 1))/${API_MAX_RETRIES}) options: '${wget_options}' URL: '${api_url}'"

        # v4v6の場合、リトライ時にネットワークタイプを切り替え
        if [ $retry_count -gt 0 ] && [ "$network_type" = "v4v6" ]; then
             if echo "$wget_options" | grep -q -- "-4"; then
                 wget_options="-6"
             else
                 wget_options="-4"
             fi
             debug_log "DEBUG" "get_country_cloudflare: Retrying with wget option: $wget_options for v4v6"
        fi

        # wget コマンド実行 (不正なオプション --tries=1 を削除, -L は元々なかった)
        wget --no-check-certificate $wget_options -T "$API_TIMEOUT" -q -O "$tmp_file" \
             -U "$USER_AGENT" \
             "$api_url"
        wget_exit_code=$?
        debug_log "DEBUG" "get_country_cloudflare: wget executed (code: $wget_exit_code)"

        # レスポンスチェック (変更なし)
        if [ "$wget_exit_code" -eq 0 ] && [ -s "$tmp_file" ]; then
            debug_log "DEBUG" "get_country_cloudflare: Download successful (code: 0, size > 0)."
            # JSON レスポンスのステータスを確認
            local json_status=$(grep -o '"status": *"[^"]*"' "$tmp_file" | sed 's/"status": "//;s/"//')
            if [ "$json_status" = "success" ]; then
                debug_log "DEBUG" "get_country_cloudflare: API status is 'success'. Extracting data."
                # 必要な情報を抽出
                SELECT_COUNTRY=$(grep -o '"country": *"[^"]*"' "$tmp_file" | sed 's/"country": "//;s/"//')
                SELECT_ZONENAME=$(grep -o '"timezone": *"[^"]*"' "$tmp_file" | sed 's/"timezone": "//;s/"//')
                ISP_NAME=$(grep -o '"isp": *"[^"]*"' "$tmp_file" | sed 's/"isp": "//;s/"//')
                local as_raw=$(grep -o '"as": *"[^"]*"' "$tmp_file" | sed 's/"as": "//;s/"//')
                if [ -n "$as_raw" ]; then ISP_AS=$(echo "$as_raw" | awk '{print $1}'); else ISP_AS=""; fi
                [ -n "$ISP_NAME" ] && ISP_ORG="$ISP_NAME" # ISP_ORG は ISP_NAME と同じ値
                SELECT_REGION_NAME=$(grep -o '"regionName": *"[^"]*"' "$tmp_file" | sed 's/"regionName": "//;s/"//')

                # 必須情報 (国とタイムゾーン名) が取得できたか確認
                if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                    debug_log "DEBUG" "get_country_cloudflare: Required fields extracted successfully."
                    success=1
                    TIMEZONE_API_SOURCE="$api_domain" # 成功時にAPIソースを設定
                    break # 成功したのでループを抜ける
                else
                    # 抽出失敗
                    debug_log "DEBUG" "get_country_cloudflare: Extraction failed for required fields (Country or ZoneName) despite success status."
                fi
            else
                 # API ステータスが success 以外
                 local fail_message=$(grep -o '"message": *"[^"]*"' "$tmp_file" | sed 's/"message": "//;s/"//')
                 debug_log "DEBUG" "get_country_cloudflare: Cloudflare Worker returned status '$json_status'. Message: '$fail_message'"
            fi
        else
            # wget 失敗またはファイル空
            debug_log "DEBUG" "get_country_cloudflare: wget failed (code: $wget_exit_code) or temp file is empty."
        fi

        # リトライ前の処理 (変更なし)
        rm -f "$tmp_file" 2>/dev/null
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            debug_log "DEBUG" "get_country_cloudflare: Retrying after 1 second sleep..."
            sleep 1
        fi
    done
    # --- ループ終了 ---

    # 最終的な成功/失敗の判定と戻り値 (変更なし)
    if [ $success -eq 1 ]; then
        debug_log "DEBUG" "get_country_cloudflare finished successfully."
        return 0 # 成功
    else
        debug_log "DEBUG" "get_country_cloudflare finished with failure after ${API_MAX_RETRIES} attempts."
        rm -f "$tmp_file" 2>/dev/null
        return 1 # 失敗
    fi
}

get_country_code() {
    # State variables
    local spinner_active=0
    local api_success=1 # Default to failure (1)
    local api_provider="" # ループ変数 (関数名)

    # Initialize variables
    SELECT_ZONE=""
    SELECT_ZONENAME=""
    SELECT_TIMEZONE=""
    SELECT_COUNTRY=""
    SELECT_REGION_NAME=""
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    TIMEZONE_API_SOURCE="" # API関数が成功時に設定する

    # Check cache directory
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"

    # Check network type
    local network_type=""
    if [ -f "${CACHE_DIR}/network.ch" ]; then
        network_type=$(cat "${CACHE_DIR}/network.ch")
        debug_log "DEBUG" "Network connectivity type detected: $network_type"
    else
        check_network_connectivity
        if [ -f "${CACHE_DIR}/network.ch" ]; then
            network_type=$(cat "${CACHE_DIR}/network.ch")
        else
            network_type="unknown"
        fi
        debug_log "DEBUG" "Network type after check: $network_type"
    fi

    if [ "$network_type" = "none" ] || [ "$network_type" = "unknown" ] || [ -z "$network_type" ]; then
        debug_log "DEBUG" "No network connectivity or unknown type ('$network_type'), cannot proceed with IP-based location"
        return 1
    fi

    # グローバル変数 API_PROVIDERS を参照
    if [ -z "$API_PROVIDERS" ]; then
         # デバッグログのみ出力し、return 1
         debug_log "CRITICAL" "Global API_PROVIDERS variable is empty! Cannot perform auto-detection. Check script configuration."
         return 1
    fi
    debug_log "DEBUG" "Starting location detection process using global providers: $API_PROVIDERS"

    local api_found=0
    # 汎用メッセージ取得 (従来通り)
    local success_msg=$(get_message "MSG_LOCATION_RESULT" "s=successfully")
    local fail_msg=$(get_message "MSG_LOCATION_RESULT" "s=failed")

    # Try API provider functions sequentially
    for api_provider in $API_PROVIDERS; do
        local tmp_file=""

        debug_log "DEBUG" "Processing API provider: $api_provider"

        if ! command -v "$api_provider" >/dev/null 2>&1; then
            debug_log "ERROR" "API provider function '$api_provider' not found. Skipping."
            continue
        fi

        tmp_file="${CACHE_DIR}/${api_provider}_tmp_$$.json"

        # スピナー開始 (関数名を表示)
        start_spinner "$(color "blue" "Currently querying: $api_provider")"
        spinner_active=1

        # API関数実行 (引数は2つ)
        "$api_provider" "$tmp_file" "$network_type"
        api_success=$? # API関数の戻り値 (0 or 1)

        rm -f "$tmp_file" 2>/dev/null

        # スピナー停止 (汎用メッセージを使用)
        if [ "$api_success" -eq 0 ]; then
            stop_spinner "$success_msg" "success"
        else
            stop_spinner "$fail_msg" "failed"
        fi
        spinner_active=0

        # 成功したらループを抜ける
        if [ "$api_success" -eq 0 ]; then
            debug_log "DEBUG" "API query succeeded with $api_provider (Source: ${TIMEZONE_API_SOURCE:-unknown}), breaking loop"
            api_found=1
            break
        else
            debug_log "DEBUG" "API query failed with $api_provider, trying next provider"
        fi
    done

    # ループが異常終了した場合のスピナー停止 (念のため)
    if [ $spinner_active -eq 1 ]; then
        stop_spinner "$fail_msg" "failed"
        spinner_active=0
    fi

    # ★★★ 修正: 全てのAPIが失敗した場合の特別な printf エラー表示を削除 ★★★
    # if [ $api_found -eq 0 ]; then
    #     # printf "%s\n" "$(color red "$(get_message "MSG_ALL_APIS_FAILED")")" # この部分を削除
    #     debug_log "ERROR" "All API providers failed to retrieve location information."
    #     # printf "\n" # この部分を削除
    # fi
    # デバッグログは残しても良いかもしれない
    if [ $api_found -eq 0 ]; then
        debug_log "ERROR" "All API providers failed to retrieve location information."
    fi

    # --- country.db processing (変更なし) ---
    if [ $api_found -eq 1 ] && [ -n "$SELECT_ZONENAME" ]; then
        debug_log "DEBUG" "API query successful. Processing ZoneName: $SELECT_ZONENAME"
        local db_file="${BASE_DIR}/country.db"
        SELECT_TIMEZONE=""

        if [ -f "$db_file" ]; then
            debug_log "DEBUG" "Searching country.db for ZoneName: $SELECT_ZONENAME"
            local matched_line=$(grep -F "$SELECT_ZONENAME" "$db_file" | head -1)

            if [ -n "$matched_line" ]; then
                 local zone_pairs=$(echo "$matched_line" | cut -d' ' -f6-)
                 local pair=""
                 local found_tz=""
                 debug_log "DEBUG" "Extracted zone pairs string: $zone_pairs"

                 for pair in $zone_pairs; do
                     debug_log "DEBUG" "Checking pair: $pair"
                     case "$pair" in
                         "$SELECT_ZONENAME,"*)
                             found_tz=$(echo "$pair" | cut -d',' -f2)
                             debug_log "DEBUG" "Found matching pair with case: $pair"
                             break
                             ;;
                         *)
                             debug_log "DEBUG" "Pair '$pair' does not match required format '$SELECT_ZONENAME,***'"
                             ;;
                     esac
                 done

                 if [ -n "$found_tz" ]; then
                     SELECT_TIMEZONE="$found_tz"
                     debug_log "DEBUG" "Found POSIX timezone in country.db and stored in SELECT_TIMEZONE: $SELECT_TIMEZONE"
                 else
                     debug_log "DEBUG" "No matching POSIX timezone pair found starting with '$SELECT_ZONENAME,' in zone pairs: $zone_pairs"
                 fi
            else
                 debug_log "DEBUG" "No matching line found in country.db containing '$SELECT_ZONENAME'"
            fi
        else
            debug_log "DEBUG" "country.db not found at: $db_file. Cannot retrieve POSIX timezone."
        fi
    elif [ $api_found -eq 0 ]; then
         debug_log "DEBUG" "All API queries failed. Cannot process timezone."
    else # api_found is 1 but SELECT_ZONENAME is empty
         debug_log "DEBUG" "ZoneName is empty even after successful API query? Cannot process timezone."
         SELECT_TIMEZONE=""
    fi
    # --- country.db processing complete ---

    # Save ISP information to cache (変更なし)
    if [ -n "$ISP_NAME" ] || [ -n "$ISP_AS" ]; then
        local cache_file="${CACHE_DIR}/isp_info.ch"
        echo "$ISP_NAME" > "$cache_file"
        echo "$ISP_AS" >> "$cache_file"
        debug_log "DEBUG" "Saved ISP information to cache"
    else
        rm -f "${CACHE_DIR}/isp_info.ch" 2>/dev/null
    fi

    # Final result determination and return status (変更なし)
    # この判定により、api_foundが0の場合や必須情報が欠けている場合は return 1 となる
    if [ $api_found -eq 1 ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$SELECT_ZONENAME" ]; then
        debug_log "DEBUG" "Location information retrieved successfully by get_country_code"
        return 0 # 成功
    else
        debug_log "DEBUG" "Location information retrieval or processing failed within get_country_code"
        return 1 # 失敗
    fi
}

process_location_info() {
    local skip_retrieval=0

    # パラメータ処理（将来的な拡張用） - use_cached で取得をスキップ
    if [ "$1" = "use_cached" ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$SELECT_ZONENAME" ]; then
        skip_retrieval=1
        debug_log "DEBUG: Using already retrieved location information"
    fi

    # デバイス情報の表示とキャッシュ
    debug_log "DEBUG: process_location_info() called"
    # ★★★ 変更点: 変数確認のデバッグログを get_country_code 後に移動 ★★★

    # 位置情報取得処理（スキップフラグが0の場合）
    if [ $skip_retrieval -eq 0 ]; then
        debug_log "DEBUG: Starting IP-based location information retrieval"
        get_country_code || {
            debug_log "ERROR: get_country_code failed to retrieve location information"
            return 1
        }
        # get_country_code() の戻り値
        local result=$?
        debug_log "DEBUG: get_country_code() returned: $result"

        # ★★★ 追加: get_country_code 後の変数確認 ★★★
        debug_log "DEBUG: After get_country_code - SELECT_COUNTRY: $SELECT_COUNTRY"
        debug_log "DEBUG: After get_country_code - SELECT_TIMEZONE: $SELECT_TIMEZONE"
        debug_log "DEBUG: After get_country_code - SELECT_ZONENAME: $SELECT_ZONENAME"
        debug_log "DEBUG: After get_country_code - ISP_NAME: $ISP_NAME"
        debug_log "DEBUG: After get_country_code - ISP_AS: $ISP_AS"
        debug_log "DEBUG: After get_country_code - SELECT_REGION_NAME: $SELECT_REGION_NAME"

        # ★★★ 変更点: get_country_code が失敗したら即時リターン ★★★
        if [ $result -ne 0 ]; then
            debug_log "ERROR: get_country_code failed, cannot process location info"
            return 1
        fi
    else
        # スキップした場合も変数確認
        debug_log "DEBUG: Using skipped/cached - SELECT_COUNTRY: $SELECT_COUNTRY"
        debug_log "DEBUG: Using skipped/cached - SELECT_TIMEZONE: $SELECT_TIMEZONE"
        debug_log "DEBUG: Using skipped/cached - SELECT_ZONENAME: $SELECT_ZONENAME"
        # Skip/cache does not guarantee ISP/Region info is present, check specifically if needed
        debug_log "DEBUG: Using skipped/cached - ISP_NAME: ${ISP_NAME:-[Not available in cache]}"
        debug_log "DEBUG: Using skipped/cached - ISP_AS: ${ISP_AS:-[Not available in cache]}"
        debug_log "DEBUG: Using skipped/cached - SELECT_REGION_NAME: ${SELECT_REGION_NAME:-[Not available in cache]}"
    fi

    # 必須情報（国、タイムゾーン、ゾーン名）が揃っているか最終確認
    debug_log "DEBUG: Processing location data - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME, Timezone: $SELECT_TIMEZONE"

    # ★★★ 削除: 一時キャッシュファイルパスの定義 ★★★
    # (No longer needed)

    # 必須情報が空でないかチェック
    if [ -z "$SELECT_COUNTRY" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_ZONENAME" ]; then
        debug_log "ERROR: Incomplete location data - required information missing (Country, Timezone, or ZoneName)"
        # ★★★ 削除: 古い一時キャッシュファイルの削除 ★★★
        # (No longer needed)

        # ★★★ 削除: 一時キャッシュからのフォールバック処理 ★★★
        # (No longer needed)

        # 必須情報がない場合はエラーで終了
        return 1
    fi

    # ★★★ 削除: 一時キャッシュへの書き込み処理 ★★★
    # (No longer needed)

    # --- START MODIFICATION (AS Cache) ---
    # Save AS number to its own persistent cache file
    local as_cache_file="${CACHE_DIR}/isp_as.ch"
    if [ -n "$ISP_AS" ]; then
        # Ensure CACHE_DIR exists before writing
        [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
        echo "$ISP_AS" > "$as_cache_file"
        debug_log "DEBUG" "Saved AS number to persistent cache: $as_cache_file"
    else
        # If ISP_AS is empty, remove the cache file if it exists
        rm -f "$as_cache_file" 2>/dev/null
        debug_log "DEBUG" "ISP_AS is empty, removed AS number cache file (if it existed): $as_cache_file"
    fi
    # --- END MODIFICATION (AS Cache) ---

    # --- START NEW MODIFICATION (Region Name Cache) ---
    # Save Region Name to its own persistent cache file
    local region_cache_file="${CACHE_DIR}/region_name.ch"
    if [ -n "$SELECT_REGION_NAME" ]; then
        # Ensure CACHE_DIR exists before writing
        [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
        echo "$SELECT_REGION_NAME" > "$region_cache_file"
        debug_log "DEBUG" "Saved Region Name to persistent cache: $region_cache_file"
    else
        # If SELECT_REGION_NAME is empty, remove the cache file if it exists
        rm -f "$region_cache_file" 2>/dev/null
        debug_log "DEBUG" "SELECT_REGION_NAME is empty, removed Region Name cache file (if it existed): $region_cache_file"
    fi
    # --- END NEW MODIFICATION (Region Name Cache) ---

    # ★★★ 維持: ISP情報の永続キャッシュへの書き込み (isp_info.ch) ★★★
    # (common-information.sh 内で行うのが自然なため維持)
    if [ -n "$ISP_NAME" ] || [ -n "$ISP_AS" ]; then
        local isp_cache_file="${CACHE_DIR}/isp_info.ch"
        # Ensure CACHE_DIR exists before writing
        [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
        echo "$ISP_NAME" > "$isp_cache_file"
        echo "$ISP_AS" >> "$isp_cache_file"
        # ★★★ 修正: ISP_ORG は ISP_NAME と同じ値が入るので不要 ★★★
        debug_log "DEBUG" "Saved ISP information to permanent cache: $isp_cache_file"
    else
        rm -f "${CACHE_DIR}/isp_info.ch" 2>/dev/null
    fi

    debug_log "DEBUG: Location information processing completed successfully in process_location_info"
    return 0
}

# display_detected_location 関数 (commit 0c929a84 時点)
# This is the version from the commit *before* 376f236...
display_detected_location() {
    local detection_source="$1"
    local detected_country="$2"
    local detected_zonename="$3"
    local detected_timezone="$4"
    # 引数5: ISP
    local detected_isp="${5:-}"
    # 引数6: AS
    local detected_as="${6:-}"

    debug_log "DEBUG" "Displaying location information from source: $detection_source"

    # 検出元情報の表示 (キー: MSG_USE_DETECTED_INFORMATION)
    # This key exists in the provided message_en.db (commit 376f236)
    printf "%s\n" "$(color white "$(get_message "MSG_USE_DETECTED_INFORMATION" "i=$detection_source")")"

    # タイムゾーンAPIの情報 (キー: MSG_TIMEZONE_API)
    # This key exists in the provided message_en.db (commit 376f236)
    if [ -n "$TIMEZONE_API_SOURCE" ]; then
        local domain=$(echo "$TIMEZONE_API_SOURCE" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
        [ -z "$domain" ] && domain="$TIMEZONE_API_SOURCE"
        printf "%s\n" "$(color white "$(get_message "MSG_TIMEZONE_API" "a=$domain")")"
    fi

    # ISP情報の表示 (キー: MSG_DETECTED_ISP, MSG_ISP_AS)
    # These keys exist in the provided message_en.db (commit 376f236)
    if [ -n "$detected_isp" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ISP")")" "$(color white "$detected_isp")"
    fi
    if [ -n "$detected_as" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_ISP_AS")")" "$(color white "$detected_as")"
    fi

    # 国、ゾーン名、タイムゾーンの表示 (キー: MSG_DETECTED_COUNTRY, MSG_DETECTED_ZONENAME, MSG_DETECTED_TIMEZONE)
    # These keys exist in the provided message_en.db (commit 376f236)
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_COUNTRY")")" "$(color white "$detected_country")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ZONENAME")")" "$(color white "$detected_zonename")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_TIMEZONE")")" "$(color white "$detected_timezone")"

    debug_log "DEBUG" "Location information displayed successfully"
}

# キャッシュされたロケーション情報を表示する関数
information_main() {
    debug_log "DEBUG" "Entering information_main() to display cached location"

    # 必要なキャッシュファイルのパス
    local cache_lang_file="${CACHE_DIR}/language.ch"
    local cache_zone_file="${CACHE_DIR}/zonename.ch"
    local cache_tz_file="${CACHE_DIR}/timezone.ch"
    local cache_isp_file="${CACHE_DIR}/isp_info.ch"

    # 必須キャッシュファイルの存在と中身をチェック
    if [ -s "$cache_lang_file" ] && [ -s "$cache_zone_file" ] && [ -s "$cache_tz_file" ]; then
        # キャッシュから情報を読み込み
        local cached_lang=$(cat "$cache_lang_file" 2>/dev/null)
        local cached_zone=$(cat "$cache_zone_file" 2>/dev/null)
        local cached_tz=$(cat "$cache_tz_file" 2>/dev/null)
        local cached_isp=""
        local cached_as=""

        # ISP情報があれば読み込み
        if [ -s "$cache_isp_file" ]; then
            cached_isp=$(sed -n '1p' "$cache_isp_file" 2>/dev/null)
            cached_as=$(sed -n '2p' "$cache_isp_file" 2>/dev/null)
        else
             cached_isp=$(get_message MSG_ISP_INFO_UNKNOWN)
             cached_as=$(get_message MSG_ISP_INFO_UNKNOWN)
        fi

        # 読み込んだ情報が空でないことを最終確認
        if [ -n "$cached_lang" ] && [ -n "$cached_zone" ] && [ -n "$cached_tz" ]; then
            debug_log "DEBUG" "Valid location cache found. Displaying information using display_detected_location."

            # 翻訳システムの初期化を確認/実行 (display_detected_location がメッセージキーを使うため)
            if command -v init_translation >/dev/null 2>&1; then
                 if [ -f "${CACHE_DIR}/message.ch" ] && [ "${MSG_MEMORY_INITIALIZED:-false}" != "true" ]; then
                     init_translation
                 elif [ ! -f "${CACHE_DIR}/message.ch" ]; then
                     init_translation # デフォルト試行
                 fi
            else
                 debug_log "WARNING" "init_translation function not found. Cannot ensure messages are translated."
            fi

            # 元の display_detected_location を呼び出す (引数も元の形式に戻す)
            if command -v display_detected_location >/dev/null 2>&1; then
                # ★★★ 変更点: 表示には display_detected_location を使う ★★★
                # ★★★ 変更点: ソースは "Cache" 固定 ★★★
                # ★★★ 変更点: ISP情報がない場合も考慮 (空文字列を渡す) ★★★
                display_detected_location "Cache" "$cached_lang" "$cached_zone" "$cached_tz" "$cached_isp" "$cached_as"
                printf "\n" # 表示後に改行を追加
            else
                debug_log "ERROR" "display_detected_location function not found. Cannot display location."
            fi
        else
            debug_log "DEBUG" "One or more essential cached values are empty after reading. Skipping display."
        fi
    else
        debug_log "DEBUG" "Essential location cache files missing or empty. Skipping display."
    fi

    debug_log "DEBUG" "Exiting information_main()"
    return 0
}

