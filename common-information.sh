#!/bin/sh

SCRIPT_VERSION="2025.04.16-00-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX準拠シェルスクリプト
# 🚀 Last Update: 2025-03-14
#
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 Compatibility: OpenWrt >= 19.07 (24.10.0でテスト済み)
#
# ⚠️ 重要なお知らせ:
# OpenWrtは**Almquist Shell (ash)**のみを使用し、
# **Bourne-Again Shell (bash)**とは互換性がありません。
#
# 📢 POSIX準拠ガイドライン:
# ✅ 条件には `[[` の代わりに `[` を使用
# ✅ コマンド置換には `command` の代わりに $(command) を使用
# ✅ let の代わりに $(( )) を使用して算術演算
# ✅ 関数は func_name() {} として定義（functionキーワードなし）
# ✅ 連想配列は使用不可（declare -A はサポートされていません）
# ✅ ヒアストリング（<<<）は使用不可
# ✅ test や [[ で -v フラグは使用不可
# ✅ ${var:0:3} のようなbash固有の文字列操作を避ける
# ✅ 可能であれば配列を完全に避ける（インデックス付き配列でも問題になることがある）
# ✅ read -p の代わりに printf に続けて read を使用
# ✅ echo -e の代わりに printf を使用してポータブルなフォーマット
# ✅ プロセス置換 <() や >() を避ける
# ✅ 複雑なif/elifチェーンよりもcaseステートメントを優先
# ✅ コマンドの存在確認には which や type の代わりに command -v を使用
# ✅ 小さく焦点を絞った関数でスクリプトをモジュール化
# ✅ 複雑なtrapの代わりに単純なエラーハンドリングを使用
# ✅ bashだけでなく、ash/dashで明示的にスクリプトをテスト
#
# 🛠️ OpenWrtのために、シンプルでPOSIX準拠、軽量に保つ！
# =========================================================

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

SELECT_REGION_NAME=""

# --- ▼▼▼ 変更点 (display_detected_location) ▼▼▼ ---
# 検出された場所情報を表示する関数 (成功メッセージ表示ロジック削除)
display_detected_location() {
    local detection_source="$1"
    local detected_country="$2"
    local detected_zonename="$3"
    local detected_timezone="$4"
    # local show_success_message="${5:-false}" # 引数削除
    local detected_isp="${5:-}" # 引数番号変更 (5番目)
    local detected_as="${6:-}"  # 引数番号変更 (6番目)

    debug_log "DEBUG" "Displaying location information from source: $detection_source"

    # 検出元情報の表示
    printf "%s\n" "$(color white "$(get_message "MSG_USE_DETECTED_INFORMATION" "i=$detection_source")")"

    # タイムゾーンAPIの情報（Cloudflare等、設定されていれば）
    if [ -n "$TIMEZONE_API_SOURCE" ]; then
        # APIのURLからドメイン名を抽出
        local domain=$(echo "$TIMEZONE_API_SOURCE" | sed -n 's|^https\?://\([^/]*\).*|\1|p')

        if [ -z "$domain" ]; then
             # URLがなければそのまま使用
             domain="$TIMEZONE_API_SOURCE"
        fi

        # タイムゾーン取得元の情報（プロバイダー名等）を表示
        printf "%s\n" "$(color white "$(get_message "MSG_TIMEZONE_API" "a=$domain")")"
    fi

    # ISP情報の表示（ISP情報があれば）
    if [ -n "$detected_isp" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ISP")")" "$(color white "$detected_isp")"
    fi

    if [ -n "$detected_as" ]; then
        printf "%s %s\n" "$(color white "$(get_message "MSG_ISP_AS")")" "$(color white "$detected_as")"
    fi

    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_COUNTRY")")" "$(color white "$detected_country")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ZONENAME")")" "$(color white "$detected_zonename")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_TIMEZONE")")" "$(color white "$detected_timezone")"

    # 成功メッセージの表示ロジックを削除
    # if [ "$show_success_message" = "true" ]; then
    #     printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"
    #     printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
    #     EXTRA_SPACING_NEEDED="yes"
    #     debug_log "DEBUG" "Success messages displayed"
    # fi

    debug_log "DEBUG" "Location information displayed successfully"
}
# --- ▲▲▲ 変更点 (display_detected_location) ▲▲▲ ---

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
    local api_name="$3"

    local retry_count=0
    local success=0

    # APIエンドポイント設定
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://ipapi.co/json"
    fi

    # APIドメインを抽出して記録
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
                error_message=$(grep -o '"message":[^\}]*' "$tmp_file")
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

    # APIエンドポイント設定
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://ipinfo.io/json"
    fi

    # APIドメインを抽出して記録
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
                error_message=$(grep -o '"message":[^\}]*' "$tmp_file")
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
    local api_name="$3"      # API名（カスタムURL等）

    local retry_count=0
    local success=0

    # --- ▼▼▼ APIエンドポイント設定 ▼▼▼ ---
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://location-api-worker.site-u.workers.dev"
    fi
    # ---------------------------------------

    debug_log "DEBUG" "Querying location from $api_url"

    # 変数の初期化
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
            local json_status=$(grep -o '"status": *"[^"]*"' "$tmp_file" | sed 's/"status": "//;s/"//')
            debug_log "DEBUG" "Extracted JSON status: '$json_status'"

            if [ "$json_status" = "success" ]; then
                debug_log "DEBUG" "JSON status is 'success'. Proceeding with field extraction."
                SELECT_COUNTRY=$(grep -o '"country": *"[^"]*"' "$tmp_file" | sed 's/"country": "//;s/"//')
                SELECT_ZONENAME=$(grep -o '"timezone": *"[^"]*"' "$tmp_file" | sed 's/"timezone": "//;s/"//')
                ISP_NAME=$(grep -o '"isp": *"[^"]*"' "$tmp_file" | sed 's/"isp": "//;s/"//')
                local as_raw=$(grep -o '"as": *"[^"]*"' "$tmp_file" | sed 's/"as": "//;s/"//')
                if [ -n "$as_raw" ]; then
                    ISP_AS=$(echo "$as_raw" | awk '{print $1}')
                     debug_log "DEBUG" "Extracted AS number and stored in ISP_AS: '$ISP_AS' from raw value: '$as_raw'"
                else
                     ISP_AS=""
                     debug_log "DEBUG" "AS field ('as') not found or empty in Cloudflare Worker response."
                fi
                [ -n "$ISP_NAME" ] && ISP_ORG="$ISP_NAME"
                SELECT_REGION_NAME=$(grep -o '"regionName": *"[^"]*"' "$tmp_file" | sed 's/"regionName": "//;s/"//')

                if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                    debug_log "DEBUG" "Required fields (Country & ZoneName) extracted successfully."
                    success=1
                    break
                else
                    debug_log "DEBUG" "Extraction failed for required fields (Country or ZoneName)."
                fi
            else
                 local fail_message=$(grep -o '"message": *"[^"]*"' "$tmp_file" | sed 's/"message": "//;s/"//')
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
    # 状態変数
    local spinner_active=0
    local api_success=1 # デフォルトを失敗(1)に設定
    local api_provider="" # APIプロバイダー名を保持

    # 変数の初期化
    SELECT_ZONE="" # Workerからの結果
    SELECT_ZONENAME="" # 例: Asia/Tokyo
    SELECT_TIMEZONE="" # process_location_info で設定される (POSIX TZ形式)
    SELECT_COUNTRY=""
    SELECT_REGION_NAME="" # 地域名
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    TIMEZONE_API_SOURCE="" # APIプロバイダーの記録用

    # キャッシュディレクトリ確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"

    # ネットワークタイプ確認
    local network_type=""
    if [ -f "${CACHE_DIR}/network.ch" ]; then
        network_type=$(cat "${CACHE_DIR}/network.ch")
        debug_log "DEBUG" "Network connectivity type detected: $network_type"
    else
        debug_log "DEBUG" "Network connectivity information not available, running check"
        check_network_connectivity # なければ実行
        if [ -f "${CACHE_DIR}/network.ch" ]; then
            network_type=$(cat "${CACHE_DIR}/network.ch")
            debug_log "DEBUG" "Network type after check: $network_type"
        else
            network_type="unknown"
            debug_log "DEBUG" "Network type still unknown after check"
        fi
    fi

    # 接続がない場合は終了
    if [ "$network_type" = "none" ] || [ "$network_type" = "unknown" ] || [ -z "$network_type" ]; then
        debug_log "DEBUG" "No network connectivity or unknown type ('$network_type'), cannot proceed with IP-based location"
        return 1
    fi

    debug_log "DEBUG" "Starting location detection process with providers: $API_PROVIDERS"

    local success_msg=$(get_message "MSG_LOCATION_RESULT" "s=successfully")
    local fail_msg=$(get_message "MSG_LOCATION_RESULT" "s=failed")
    local api_found=0

    # APIプロバイダーを順に試行
    for api_provider in $API_PROVIDERS; do
        # 関数が存在するか確認
        if ! command -v "$api_provider" >/dev/null 2>&1; then
            debug_log "ERROR" "Invalid API provider function: $api_provider"
            api_success=1 # 失敗として次へ
            continue # 次のプロバイダーへ
        fi

        # forループでのAPI実行と一時ファイルパス
        local tmp_file="${CACHE_DIR}/${api_provider}_tmp_$$.json"

        # スピナー表示
        start_spinner "$(color "blue" "Currently querying: $api_provider")" "yellow"
        spinner_active=1

        # APIプロバイダー関数を実行
        debug_log "DEBUG" "Calling API provider function: $api_provider"
        $api_provider "$tmp_file" "$network_type"
        api_success=$?

        # 一時ファイルを削除（エラー時も）
        rm -f "$tmp_file" 2>/dev/null

        # 成功かつ必要な情報が取得できたらループを抜ける
        if [ "$api_success" -eq 0 ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
            stop_spinner "$success_msg" "success"
            spinner_active=0
            debug_log "DEBUG" "API query succeeded with $TIMEZONE_API_SOURCE, breaking loop"
            api_found=1
            break
        else
            # 失敗した場合
            stop_spinner "" ""
            spinner_active=0
            debug_log "DEBUG" "API query failed with $api_provider, trying next provider"
        fi
    done

    # スピナーがまだアクティブなら停止（全てのAPIが失敗した場合）
    if [ $spinner_active -eq 1 ]; then
        stop_spinner "$fail_msg" "failed"
        spinner_active=0
    fi

    # --- country.db 処理 (POSIXタイムゾーン取得) ---
    # API実行後、成功していればZoneNameからPOSIXタイムゾーンをマッピング
    if [ $api_success -eq 0 ] && [ -n "$SELECT_ZONENAME" ]; then
        debug_log "DEBUG" "API query successful. Processing ZoneName: $SELECT_ZONENAME"

        # country.db から POSIXタイムゾーン (SELECT_TIMEZONE) を取得
        debug_log "DEBUG" "Trying to map ZoneName to POSIX timezone using country.db"
        local db_file="${BASE_DIR}/country.db"
        SELECT_TIMEZONE="" # 初期化

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
        SELECT_TIMEZONE="" # 念のためクリア
    fi
    # --- country.db 処理完了 ---

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

    # 最終結果の判定とキャッシュ書き込み
    if [ $api_success -eq 0 ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$SELECT_ZONENAME" ]; then
        debug_log "DEBUG" "Location information retrieved successfully by get_country_code"
        return 0
    else
        debug_log "DEBUG" "Location information retrieval or processing failed within get_country_code"
        return 1
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
    debug_log "DEBUG: SELECT_COUNTRY: $SELECT_COUNTRY"
    debug_log "DEBUG: SELECT_TIMEZONE: $SELECT_TIMEZONE"
    debug_log "DEBUG: SELECT_ZONENAME: $SELECT_ZONENAME"

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
    fi

    # 必須情報（国、タイムゾーン、ゾーン名）が揃っているか最終確認
    debug_log "DEBUG: Processing location data - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME, Timezone: $SELECT_TIMEZONE"

    # キャッシュファイルパス
    local tmp_country="${CACHE_DIR}/ip_country.tmp"
    local tmp_timezone="${CACHE_DIR}/ip_timezone.tmp"
    local tmp_zonename="${CACHE_DIR}/ip_zonename.tmp"
    local tmp_isp="${CACHE_DIR}/ip_isp.tmp"
    local tmp_as="${CACHE_DIR}/ip_as.tmp"
    local tmp_region_name="${CACHE_DIR}/ip_region_name.tmp"

    # 必須情報が空でないかチェック
    if [ -z "$SELECT_COUNTRY" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_ZONENAME" ]; then
        debug_log "ERROR: Incomplete location data - required information missing (Country, Timezone, or ZoneName)"
        # 古いキャッシュファイルがあれば削除
        rm -f "$tmp_country" "$tmp_timezone" "$tmp_zonename" "$tmp_isp" "$tmp_as" "$tmp_region_name" 2>/dev/null

        # フォールバックとして以前のキャッシュを使用試行
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

    # ゾーン名をキャッシュに保存
    echo "$SELECT_ZONENAME" > "$tmp_zonename"
    debug_log "DEBUG: Zone name saved to cache: $SELECT_ZONENAME"

    # POSIXタイムゾーンをキャッシュに保存
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

    # 地域名をキャッシュに保存
    if [ -n "$SELECT_REGION_NAME" ]; then
        echo "$SELECT_REGION_NAME" > "$tmp_region_name"
        debug_log "DEBUG: Region name saved to cache: $SELECT_REGION_NAME"
    else
        rm -f "$tmp_region_name" 2>/dev/null
    fi

    debug_log "DEBUG: Location information cache process completed successfully"
    return 0
}
