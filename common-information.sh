#!/bin/sh

SCRIPT_VERSION="2025.04.16-00-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX準拠シェルスクリプト
# 🚀 最終更新日: 2025-03-14
#
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 互換性: OpenWrt >= 19.07 (24.10.0でテスト済み)
#
# ⚠️ 重要な注意事項:
# OpenWrtは**Almquistシェル(ash)**のみを使用し、
# **Bourne-Again Shell(bash)**とは互換性がありませんget_country_cloudflare() {。
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
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"
API_MAX_REDIRECTS="${API_MAX_REDIRECTS:-2}"
TIMEZONE_API_SOURCE=""
USER_AGENT="aios-script/${SCRIPT_VERSION:-unknown}"

SELECT_REGION_NAME=""

# 検出した地域情報を表示する共通関数
display_detected_location() {
    local detection_source="$1"
    local detected_country="$2"
    local detected_zonename="$3"
    local detected_timezone="$4"
    local show_success_message="${5:-false}"
    local detected_isp="${6:-}"
    local detected_as="${7:-}"
    
    debug_log "DEBUG" "Displaying location information from source: $detection_source"
    
    # 検出情報表示
    printf "%s\n" "$(color white "$(get_message "MSG_USE_DETECTED_INFORMATION" "i=$detection_source")")"
    
    # タイムゾーンAPI情報の表示（グローバル変数を使用）
    if [ -n "$TIMEZONE_API_SOURCE" ]; then
        # APIのURLからドメイン名のみを抽出
        local domain=$(echo "$TIMEZONE_API_SOURCE" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
        
        if [ -z "$domain" ]; then
            # URLでない場合はそのまま使用
            domain="$TIMEZONE_API_SOURCE"
        fi
        
        # タイムゾーン取得元の表示（プレースホルダーを使用）
        printf "%s\n" "$(color white "$(get_message "MSG_TIMEZONE_API" "a=$domain")")"
    fi
    
    # ISP情報の表示（ISP情報がある場合のみ）
    if [ -n "$detected_isp" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ISP")")" "$(color white "$detected_isp")"
    fi
    
    if [ -n "$detected_as" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_ISP_AS")")" "$(color white "$detected_as")"
    fi
    
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_COUNTRY")")" "$(color white "$detected_country")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ZONENAME")")" "$(color white "$detected_zonename")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_TIMEZONE")")" "$(color white "$detected_timezone")"
    
    # 成功メッセージの表示（オプション）
    if [ "$show_success_message" = "true" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"
        printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
        EXTRA_SPACING_NEEDED="yes"
        debug_log "DEBUG" "Success messages displayed"
    fi
    
    debug_log "DEBUG" "Location information displayed successfully"
}

# APIリクエストを実行する共通関数（ネットワークオプション対応版）
make_api_request() {
    # パラメータ
    local url="$1"
    local tmp_file="$2"
    local timeout="${3:-$API_TIMEOUT}"
    local debug_tag="${4:-API}"
    local user_agent="$5"

    # UAが空の場合はグローバルを使う
    if [ -z "$user_agent" ]; then
        user_agent="$USER_AGENT"
    fi

    # wgetの機能検出
    local wget_capability=$(detect_wget_capabilities)
    local used_url="$url"
    local status=0

    debug_log "DEBUG" "[$debug_tag] Making API request to: $url"
    debug_log "DEBUG" "[$debug_tag] Using User-Agent: $user_agent"

    # コマンド構築と実行
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
    local api_name="$3"

    local retry_count=0
    local success=0

    # APIエンドポイントを関数内で管理
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://ipapi.co/json"
    fi

    # API名からドメイン名を抽出
    local api_domain=$(echo "$api_url" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$api_url"

    debug_log "DEBUG" "Querying country and timezone from $api_domain"

    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        make_api_request "$api_url" "$tmp_file" "$API_TIMEOUT" "IPAPI" "$USER_AGENT"
        local request_status=$?
        debug_log "DEBUG" "API request status: $request_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"

        if [ $request_status -eq 0 ]; then
            SELECT_COUNTRY=$(grep '"country"' "$tmp_file" | sed -n 's/.*"country": *"\([^"]*\)".*/\1/p')
            SELECT_ZONENAME=$(grep '"timezone"' "$tmp_file" | sed -n 's/.*"timezone": *"\([^"]*\)".*/\1/p')

            if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                debug_log "DEBUG" "Retrieved from $api_domain - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME"
                success=1
                break
            else
                debug_log "DEBUG" "Incomplete country/timezone data from $api_domain"
                error_message=$(grep -o '"message":[^}]*' "$tmp_file")
                if [ -n "$error_message" ]; then
                  debug_log "DEBUG" "API Error: $error_message"
                fi
            fi
        else
            debug_log "DEBUG" "Failed to download data from $api_domain"
            debug_log "DEBUG" "wget exit code: $request_status"
        fi

        debug_log "DEBUG" "API query attempt $((retry_count+1)) failed"
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $API_MAX_RETRIES ] && sleep 1
    done

    if [ $success -eq 1 ]; then
        TIMEZONE_API_SOURCE="$api_domain"
        debug_log "DEBUG" "get_country_ipapi succeeded"
        return 0
    else
        debug_log "DEBUG" "get_country_ipapi failed"
        return 1
    fi
}

get_country_ipinfo() {
    local tmp_file="$1"
    local network_type="$2"
    local api_name="$3"

    local retry_count=0
    local success=0

    # APIエンドポイントを関数内で管理
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://ipinfo.io/json"
    fi

    # API名からドメイン名を抽出
    local api_domain=$(echo "$api_url" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$api_url"

    debug_log "DEBUG" "Querying country and timezone from $api_domain"

    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        make_api_request "$api_url" "$tmp_file" "$API_TIMEOUT" "IPINFO" "$USER_AGENT"
        local request_status=$?
        debug_log "DEBUG" "API request status: $request_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"

        if [ $request_status -eq 0 ]; then
            SELECT_COUNTRY=$(grep '"country"' "$tmp_file" | sed -n 's/.*"country": *"\([^"]*\)".*/\1/p')
            SELECT_ZONENAME=$(grep '"timezone"' "$tmp_file" | sed -n 's/.*"timezone": *"\([^"]*\)".*/\1/p')

            if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                debug_log "DEBUG" "Retrieved from $api_domain - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME"
                success=1
                break
            else
                debug_log "DEBUG" "Incomplete country/timezone data from $api_domain"
                error_message=$(grep -o '"message":[^}]*' "$tmp_file")
                if [ -n "$error_message" ]; then
                  debug_log "DEBUG" "API Error: $error_message"
                fi
            fi
        else
            debug_log "DEBUG" "Failed to download data from $api_domain"
            debug_log "DEBUG" "wget exit code: $request_status"
        fi

        debug_log "DEBUG" "API query attempt $((retry_count+1)) failed"
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $API_MAX_RETRIES ] && sleep 1
    done

    if [ $success -eq 1 ]; then
        TIMEZONE_API_SOURCE="$api_domain"
        debug_log "DEBUG" "get_country_ipinfo succeeded"
        return 0
    else
        debug_log "DEBUG" "get_country_ipinfo failed"
        return 1
    fi
}

get_country_cloudflare() {
    local tmp_file="$1"      # 一時ファイルパス
    local network_type="$2"  # ネットワークタイプ
    local api_name="$3"      # API名（実際のURLを受け取る）

    local retry_count=0
    local success=0

    # --- ここでAPIエンドポイントを関数内で管理 ---
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://location-api-worker.site-u.workers.dev"
    fi
    # ------------------------------------------------

    debug_log "DEBUG" "Querying location from $api_url"

    # グローバル変数の初期化
    SELECT_COUNTRY=""
    SELECT_ZONENAME=""
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    SELECT_REGION_NAME=""

    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        make_api_request "$api_url" "$tmp_file" "$API_TIMEOUT" "CLOUDFLARE" "$USER_AGENT"
        local request_status=$?
        debug_log "DEBUG" "Cloudflare Worker request status: $request_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"

        if [ $request_status -eq 0 ] && [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            debug_log "DEBUG" "make_api_request successful and tmp_file exists and is not empty."
            local json_status=$(grep -o '"status": "[^"]*' "$tmp_file" | sed 's/"status": "//')
            debug_log "DEBUG" "Extracted JSON status: '$json_status'"

            if [ "$json_status" = "success" ]; then
                debug_log "DEBUG" "JSON status is 'success'. Proceeding with field extraction."
                SELECT_COUNTRY=$(grep -o '"countryCode": "[^"]*' "$tmp_file" | sed 's/"countryCode": "//')
                SELECT_ZONENAME=$(grep -o '"timezone": "[^"]*' "$tmp_file" | sed 's/"timezone": "//')
                ISP_NAME=$(grep -o '"isp": "[^"]*' "$tmp_file" | sed 's/"isp": "//')
                local as_raw=$(grep -o '"as": "[^"]*' "$tmp_file" | sed 's/"as": "//')
                if [ -n "$as_raw" ]; then
                    ISP_AS=$(echo "$as_raw" | awk '{print $1}')
                    debug_log "DEBUG" "Extracted AS number and stored in ISP_AS: '$ISP_AS' from raw value: '$as_raw'"
                else
                    ISP_AS=""
                    debug_log "DEBUG" "AS field ('as') not found or empty in Cloudflare Worker response."
                fi
                [ -n "$ISP_NAME" ] && ISP_ORG="$ISP_NAME"
                SELECT_REGION_NAME=$(grep -o '"regionName": "[^"]*' "$tmp_file" | sed 's/"regionName": "//')

                if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                    debug_log "DEBUG" "Required fields (Country & ZoneName) extracted successfully."
                    success=1
                    break
                else
                    debug_log "DEBUG" "Extraction failed for required fields (Country or ZoneName)."
                fi
            else
                local fail_message=$(grep -o '"message": "[^"]*' "$tmp_file" | sed 's/"message": "//')
                debug_log "DEBUG" "Cloudflare Worker returned status '$json_status'. Message: '$fail_message'"
            fi
        else
            if [ $request_status -ne 0 ]; then
                debug_log "DEBUG" "make_api_request failed with status: $request_status"
            elif [ ! -f "$tmp_file" ]; then
                debug_log "DEBUG" "make_api_request succeeded but tmp_file '$tmp_file' not found."
            elif [ ! -s "$tmp_file" ]; then
                debug_log "DEBUG" "make_api_request succeeded but tmp_file '$tmp_file' is empty."
            fi
        fi

        debug_log "DEBUG" "API query attempt $((retry_count+1)) failed, proceeding to retry or exit."
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            debug_log "DEBUG" "Sleeping for 1 second before retry."
            sleep 1
        fi
    done

    if [ $success -eq 1 ]; then
        TIMEZONE_API_SOURCE="Cloudflare"
        debug_log "DEBUG" "get_country_cloudflare finished successfully."
        return 0
    else
        debug_log "DEBUG" "get_country_cloudflare finished with failure."
        return 1
    fi
}

get_country_code() {
    # 変数宣言
    local spinner_active=0
    local api_success=1 # 初期値を失敗(1)に設定
    local api_provider="" # APIプロバイダーを追跡

    # グローバル変数の初期化
    SELECT_ZONE="" # Workerからは取得できない
    SELECT_ZONENAME="" # 例: Asia/Tokyo
    SELECT_TIMEZONE="" # process_location_info が期待する変数 (POSIX TZをここに直接格納)
    SELECT_COUNTRY=""
    SELECT_REGION_NAME="" # 追加
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    TIMEZONE_API_SOURCE="" # APIソースは動的に決定

    # ユーザーが指定するAPIプロバイダー (デフォルトはget_country_cloudflare)
    API_PROVIDERS="${API_PROVIDERS:-get_country_ipinfo}"
    # API_PROVIDERS="${API_PROVIDERS:-get_country_cloudflare}"
    debug_log "DEBUG" "API_PROVIDERS set to: $API_PROVIDERS"

    # キャッシュディレクトリの確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"

    # ネットワーク接続状況の取得
    local network_type=""
    if [ -f "${CACHE_DIR}/network.ch" ]; then
        network_type=$(cat "${CACHE_DIR}/network.ch")
        debug_log "DEBUG" "Network connectivity type detected: $network_type"
    else
        debug_log "DEBUG" "Network connectivity information not available, running check"
        check_network_connectivity # この関数が存在する前提

        if [ -f "${CACHE_DIR}/network.ch" ]; then
            network_type=$(cat "${CACHE_DIR}/network.ch")
            debug_log "DEBUG" "Network type after check: $network_type"
        else
            network_type="unknown"
            debug_log "DEBUG" "Network type still unknown after check"
        fi
    fi

    # 接続がない場合は早期リターン
    if [ "$network_type" = "none" ] || [ "$network_type" = "unknown" ] || [ -z "$network_type" ]; then
        debug_log "DEBUG" "No network connectivity or unknown type ('$network_type'), cannot proceed with IP-based location"
        return 1
    fi

    debug_log "DEBUG" "Starting location detection process with providers: $API_PROVIDERS"

    # APIプロバイダーを順番に処理
    for api_provider in $API_PROVIDERS; do
        # 関数が存在するか確認
        if ! command -v "$api_provider" >/dev/null 2>&1; then
            debug_log "ERROR" "Invalid API provider function: $api_provider"
            api_success=1 # 失敗として扱う
            continue # 次のプロバイダーを試す
        fi

        # forループ内でAPIごとにユニークな一時ファイル名を生成
        local tmp_file="${CACHE_DIR}/${api_provider}_tmp_$$.json"

        # スピナー開始：今のAPIのみ表示
        start_spinner "$(color "blue" "Currently querying: $api_provider")" "yellow"
        spinner_active=1

        # APIプロバイダーの関数を呼び出す
        debug_log "DEBUG" "Calling API provider function: $api_provider"
        ${api_provider} "$tmp_file" "$network_type"

        api_success=$?

        # スピナー停止（都度停止）
        stop_spinner "" ""
        spinner_active=0

        # 一時ファイル削除（都度クリーンアップ）
        rm -f "$tmp_file" 2>/dev/null

        # 成功したらループを抜ける
        if [ "$api_success" -eq 0 ]; then
            debug_log "DEBUG" "API query succeeded with $TIMEZONE_API_SOURCE, breaking loop"
            break
        else
            debug_log "DEBUG" "API query failed with $api_provider, trying next provider"
        fi
    done
    
    # --- country.db 検索 (POSIXタイムゾーン取得) ---
    # API呼び出しが成功し、ZoneNameが取得できた場合のみ実行
    if [ $api_success -eq 0 ] && [ -n "$SELECT_ZONENAME" ]; then
        debug_log "DEBUG" "API query successful. Processing ZoneName: $SELECT_ZONENAME"

        # country.db から POSIXタイムゾーン (SELECT_TIMEZONE) の取得
        debug_log "DEBUG" "Trying to map ZoneName to POSIX timezone using country.db"
        local db_file="${BASE_DIR}/country.db"
        SELECT_TIMEZONE="" # 事前にクリア

        if [ -f "$db_file" ]; then
            debug_log "DEBUG" "Searching country.db for ZoneName: $SELECT_ZONENAME"
            local matched_line=$(grep -F "$SELECT_ZONENAME" "$db_file" | head -1)

            if [ -n "$matched_line" ]; then
                local zone_pairs=$(echo "$matched_line" | cut -d' ' -f5-)
                local pair=""
                local found_tz=""

                for pair in $zone_pairs; do
                    case "$pair" in
                        "$SELECT_ZONENAME,"*)
                            found_tz=$(echo "$pair" | cut -d',' -f2)
                            break
                            ;;
                    esac
                done

                if [ -n "$found_tz" ]; then
                    SELECT_TIMEZONE="$found_tz"
                    debug_log "DEBUG" "Found POSIX timezone in country.db and stored in SELECT_TIMEZONE: $SELECT_TIMEZONE"
                else
                    debug_log "DEBUG" "No matching POSIX timezone pair found in country.db for: $SELECT_ZONENAME"
                fi
            else
                debug_log "DEBUG" "No matching line found in country.db for: $SELECT_ZONENAME"
            fi
        else
            debug_log "DEBUG" "country.db not found at: $db_file. Cannot retrieve POSIX timezone."
        fi
    else
        if [ $api_success -ne 0 ]; then
             debug_log "DEBUG" "All API queries failed. Cannot process timezone."
        else
             debug_log "DEBUG" "ZoneName is empty. Cannot process timezone."
        fi
        SELECT_TIMEZONE="" # 確実に空にする
    fi
    # --- country.db 検索ここまで ---

    # ISP情報をキャッシュに保存
    if [ -n "$ISP_NAME" ] || [ -n "$ISP_AS" ]; then
        local cache_file="${CACHE_DIR}/isp_info.ch"
        echo "$ISP_NAME" > "$cache_file"
        echo "$ISP_AS" >> "$cache_file"
        echo "$ISP_ORG" >> "$cache_file"
        debug_log "DEBUG" "Saved ISP information to cache"
    else
        rm -f "${CACHE_DIR}/isp_info.ch" 2>/dev/null
    fi

    # 結果のチェックとスピナー停止
    if [ $spinner_active -eq 1 ]; then
        # 成功条件: 国コードとタイムゾーン名(IANA)が取得できていること
        if [ $api_success -eq 0 ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
            local success_msg=$(get_message "MSG_LOCATION_RESULT" "s=successfully")
            stop_spinner "$success_msg" "success"
            debug_log "DEBUG" "Location information retrieved successfully by get_country_code"
            return 0 # 成功
        else
            local fail_msg=$(get_message "MSG_LOCATION_RESULT" "s=failed")
            stop_spinner "$fail_msg" "failed"
            debug_log "DEBUG" "Location information retrieval or processing failed within get_country_code"
            return 1 # 失敗
        fi
    fi

    # スピナーがアクティブでなかった場合
    if [ $api_success -eq 0 ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
        return 0 # 成功
    else
        return 1 # 失敗
    fi
}

process_location_info() {
    local skip_retrieval=0

    # パラメータ処理（オプション） - SELECT_TIMEZONE をチェックするように戻す
    if [ "$1" = "use_cached" ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$SELECT_ZONENAME" ]; then
        skip_retrieval=1
        debug_log "DEBUG: Using already retrieved location information"
    fi

    # デバッグログの追加
    debug_log "DEBUG: process_location_info() called"
    debug_log "DEBUG: SELECT_COUNTRY: $SELECT_COUNTRY"
    debug_log "DEBUG: SELECT_TIMEZONE: $SELECT_TIMEZONE"
    debug_log "DEBUG: SELECT_ZONENAME: $SELECT_ZONENAME"

    # 必要な場合のみget_country_code関数を呼び出し
    if [ $skip_retrieval -eq 0 ]; then
        debug_log "DEBUG: Starting IP-based location information retrieval"
        get_country_code || {
            debug_log "ERROR: get_country_code failed to retrieve location information"
            return 1
        }
        # get_country_code() 関数の戻り値を確認
        local result=$?
        debug_log "DEBUG: get_country_code() returned: $result"
    fi

    # デバッグログ - Timezone と $SELECT_TIMEZONE を表示するように戻す
    debug_log "DEBUG: Processing location data - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME, Timezone: $SELECT_TIMEZONE"

    # キャッシュファイルのパス定義
    local tmp_country="${CACHE_DIR}/ip_country.tmp"
    # local tmp_zone="${CACHE_DIR}/ip_zone.tmp" # 不要
    local tmp_timezone="${CACHE_DIR}/ip_timezone.tmp"
    local tmp_zonename="${CACHE_DIR}/ip_zonename.tmp"
    local tmp_isp="${CACHE_DIR}/ip_isp.tmp"
    local tmp_as="${CACHE_DIR}/ip_as.tmp"
    local tmp_region_name="${CACHE_DIR}/ip_region_name.tmp"
    # local tmp_region_code="${CACHE_DIR}/ip_region_code.tmp" # 削除

    # 必須情報 (国コード, タイムゾーン, IANAゾーン名) が揃っているか確認 - SELECT_TIMEZONE をチェックするように戻す
    if [ -z "$SELECT_COUNTRY" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_ZONENAME" ]; then
        # エラーメッセージも Timezone に戻す
        debug_log "ERROR: Incomplete location data - required information missing (Country, Timezone, or ZoneName)"
        # 既存のファイルを削除してクリーンな状態を確保
        rm -f "$tmp_country" "$tmp_timezone" "$tmp_zonename" "$tmp_isp" "$tmp_as" "$tmp_region_name" # "tmp_region_code" 削除 2>/dev/null

        # フォールバックロジック: 以前に取得した地域情報を使用する
        if [ -f "$tmp_country" ] && [ -f "$tmp_timezone" ] && [ -f "$tmp_zonename" ]; then
            debug_log "DEBUG: Using previously cached location information as fallback"
            SELECT_COUNTRY=$(cat "$tmp_country")
            SELECT_TIMEZONE=$(cat "$tmp_timezone")
            SELECT_ZONENAME=$(cat "$tmp_zonename")
            ISP_NAME=$(cat "$tmp_isp")
            ISP_AS=$(cat "$tmp_as")
            SELECT_REGION_NAME=$(cat "$tmp_region_name")
            debug_log "DEBUG: Fallback location data - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME, Timezone: $SELECT_TIMEZONE"
        else
            debug_log "ERROR: No previously cached location information available for fallback"
            return 1
        fi
    fi

    debug_log "DEBUG: All required location data available, saving to cache files"

    # 国コードをキャッシュに保存
    echo "$SELECT_COUNTRY" > "$tmp_country"
    debug_log "DEBUG: Country code saved to cache: $SELECT_COUNTRY"

    # ゾーンネームをキャッシュに保存
    echo "$SELECT_ZONENAME" > "$tmp_zonename"
    debug_log "DEBUG: Zone name saved to cache: $SELECT_ZONENAME"

    # POSIXタイムゾーン文字列をキャッシュに保存 - SELECT_TIMEZONE を書き込むように戻す
    echo "$SELECT_TIMEZONE" > "$tmp_timezone"
    debug_log "DEBUG: Timezone saved to cache: $SELECT_TIMEZONE"

    # ISP情報をキャッシュに保存
    if [ -n "$ISP_NAME" ]; then
        echo "$ISP_NAME" > "$tmp_isp"
        debug_log "DEBUG: ISP name saved to cache: $ISP_NAME" 
    else
        rm -f "$tmp_isp" 2>/dev/null
    fi

    if [ -n "$ISP_AS" ]; then
        echo "$ISP_AS" > "$tmp_as"
        debug_log "DEBUG: AS number saved to cache: $ISP_AS"
    else
        rm -f "$tmp_as" 2>/dev/null
    fi

    # 地域情報をキャッシュに保存
    if [ -n "$SELECT_REGION_NAME" ]; then
        echo "$SELECT_REGION_NAME" > "$tmp_region_name"
        debug_log "DEBUG: Region name saved to cache: $SELECT_REGION_NAME"
    else
        rm -f "$tmp_region_name" 2>/dev/null
    fi

    debug_log "DEBUG: Location information cache process completed successfully"
    return 0
}
