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
API_PROVIDERS="get_country_cloudflare get_country_ipapi get_country_ipinfo"

SELECT_REGION_NAME=""

# 検出された場所情報を表示する関数
display_detected_location() {
    local detection_source="$1"
    local detected_country="$2"
    local detected_zonename="$3"
    local detected_timezone="$4"
    # 引数番号変更 (5番目)
    local detected_isp="${5:-}"
    # 引数番号変更 (6番目)
    local detected_as="${6:-}"

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

    # --- 削除 ---
    # 成功メッセージの表示ロジック
    # -------------

    debug_log "DEBUG" "Location information displayed successfully"
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
    local api_name="$3"

    local retry_count=0
    local success=0
    local api_domain=""      # ★★★ 追加: ドメイン名格納用変数 ★★★

    # APIエンドポイント設定
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://ipapi.co/json"
    fi

    # ★★★ 追加: API URLからドメイン名を抽出 ★★★
    api_domain=$(echo "$api_url" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    # ドメイン名が取得できなかった場合のフォールバック (URL自体を使う)
    [ -z "$api_domain" ] && api_domain="$api_url"
    debug_log "DEBUG" "Using API domain for IPAPI: $api_domain"

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
                # ★★★ 変更点: 成功時に API ドメイン名を TIMEZONE_API_SOURCE に設定 ★★★
                TIMEZONE_API_SOURCE="$api_domain"
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

    # ★★★ 削除: 成功時の TIMEZONE_API_SOURCE 設定 (ループ内で実施済) ★★★
    # if [ $success -eq 1 ]; then
    #     TIMEZONE_API_SOURCE="$api_domain"
    #     debug_log "DEBUG" "get_country_ipapi succeeded"
    #     return 0
    # else
    #     debug_log "DEBUG" "get_country_ipapi failed"
    #     return 1
    # fi
    # ★★★ 変更点: 戻り値のみ返す ★★★
    if [ $success -eq 1 ]; then
        debug_log "DEBUG" "get_country_ipapi finished successfully."
        return 0
    else
        debug_log "DEBUG" "get_country_ipapi finished with failure."
        return 1
    fi
}

get_country_ipinfo() {
    local tmp_file="$1"
    local network_type="$2"
    local api_name="$3"

    local retry_count=0
    local success=0
    local api_domain=""      # ★★★ 追加: ドメイン名格納用変数 ★★★

    # APIエンドポイント設定
    local api_url=""
    if [ -n "$api_name" ]; then
        api_url="$api_name"
    else
        api_url="https://ipinfo.io/json"
    fi

    # ★★★ 追加: API URLからドメイン名を抽出 ★★★
    api_domain=$(echo "$api_url" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    # ドメイン名が取得できなかった場合のフォールバック (URL自体を使う)
    [ -z "$api_domain" ] && api_domain="$api_url"
    debug_log "DEBUG" "Using API domain for IPINFO: $api_domain"

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
                # ★★★ 変更点: 成功時に API ドメイン名を TIMEZONE_API_SOURCE に設定 ★★★
                TIMEZONE_API_SOURCE="$api_domain"
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

    # ★★★ 削除: 成功時の TIMEZONE_API_SOURCE 設定 (ループ内で実施済) ★★★
    # if [ $success -eq 1 ]; then
    #     TIMEZONE_API_SOURCE="$api_domain"
    #     debug_log "DEBUG" "get_country_ipinfo succeeded"
    #     return 0
    # else
    #     debug_log "DEBUG" "get_country_ipinfo failed"
    #     return 1
    # fi
    # ★★★ 変更点: 戻り値のみ返す ★★★
    if [ $success -eq 1 ]; then
        debug_log "DEBUG" "get_country_ipinfo finished successfully."
        return 0
    else
        debug_log "DEBUG" "get_country_ipinfo finished with failure."
        return 1
    fi
}

get_country_cloudflare() {
    local tmp_file="$1"
    local network_type="$2"

    local api_url="https://location-api-worker.site-u.workers.dev"
    local api_domain=""

    local retry_count=0
    local success=0

    api_domain=$(echo "$api_url" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$api_url"
    debug_log "DEBUG" "Using API URL for Cloudflare: $api_url (Domain: $api_domain)"

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
            local json_status=$(grep -o '"status": *"[^"]*"' "$tmp_file" | sed 's/"status": "//;s/"//')
            if [ "$json_status" = "success" ]; then
                SELECT_COUNTRY=$(grep -o '"country": *"[^"]*"' "$tmp_file" | sed 's/"country": "//;s/"//')
                SELECT_ZONENAME=$(grep -o '"timezone": *"[^"]*"' "$tmp_file" | sed 's/"timezone": "//;s/"//')
                ISP_NAME=$(grep -o '"isp": *"[^"]*"' "$tmp_file" | sed 's/"isp": "//;s/"//')
                local as_raw=$(grep -o '"as": *"[^"]*"' "$tmp_file" | sed 's/"as": "//;s/"//')
                if [ -n "$as_raw" ]; then ISP_AS=$(echo "$as_raw" | awk '{print $1}'); else ISP_AS=""; fi
                [ -n "$ISP_NAME" ] && ISP_ORG="$ISP_NAME"
                SELECT_REGION_NAME=$(grep -o '"regionName": *"[^"]*"' "$tmp_file" | sed 's/"regionName": "//;s/"//')

                if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                    debug_log "DEBUG" "Required fields (Country & ZoneName) extracted successfully."
                    success=1
                    TIMEZONE_API_SOURCE="$api_domain" # ★★★ 成功時に設定 ★★★
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

        retry_count=$((retry_count + 1))
        [ $retry_count -lt $API_MAX_RETRIES ] && sleep 1
    done

    if [ $success -eq 1 ]; then
        debug_log "DEBUG" "get_country_cloudflare finished successfully."
        return 0 # ★★★ 戻り値 0 (成功) ★★★
    else
        debug_log "DEBUG" "get_country_cloudflare finished with failure."
        return 1 # ★★★ 戻り値 1 (失敗) ★★★
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
        start_spinner "$(color "blue" "Currently querying: $api_provider")" "yellow"
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
    fi

    # 必須情報（国、タイムゾーン、ゾーン名）が揃っているか最終確認
    debug_log "DEBUG: Processing location data - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME, Timezone: $SELECT_TIMEZONE"

    # ★★★ 削除: 一時キャッシュファイルパスの定義 ★★★
    # local tmp_country="${CACHE_DIR}/ip_country.tmp"
    # local tmp_timezone="${CACHE_DIR}/ip_timezone.tmp"
    # local tmp_zonename="${CACHE_DIR}/ip_zonename.tmp"
    # local tmp_isp="${CACHE_DIR}/ip_isp.tmp"
    # local tmp_as="${CACHE_DIR}/ip_as.tmp"
    # local tmp_region_name="${CACHE_DIR}/ip_region_name.tmp"

    # 必須情報が空でないかチェック
    if [ -z "$SELECT_COUNTRY" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_ZONENAME" ]; then
        debug_log "ERROR: Incomplete location data - required information missing (Country, Timezone, or ZoneName)"
        # ★★★ 削除: 古い一時キャッシュファイルの削除 ★★★
        # rm -f "$tmp_country" "$tmp_timezone" "$tmp_zonename" "$tmp_isp" "$tmp_as" "$tmp_region_name" 2>/dev/null

        # ★★★ 削除: 一時キャッシュからのフォールバック処理 ★★★
        # (一時キャッシュを使わないため不要)

        # 必須情報がない場合はエラーで終了
        return 1
    fi

    # ★★★ 削除: 一時キャッシュへの書き込み処理 ★★★
    # echo "$SELECT_COUNTRY" > "$tmp_country"
    # echo "$SELECT_ZONENAME" > "$tmp_zonename"
    # echo "$SELECT_TIMEZONE" > "$tmp_timezone"
    # if [ -n "$ISP_NAME" ]; then echo "$ISP_NAME" > "$tmp_isp"; else rm -f "$tmp_isp" 2>/dev/null; fi
    # if [ -n "$ISP_AS" ]; then echo "$ISP_AS" > "$tmp_as"; else rm -f "$tmp_as" 2>/dev/null; fi
    # if [ -n "$SELECT_REGION_NAME" ]; then echo "$SELECT_REGION_NAME" > "$tmp_region_name"; else rm -f "$tmp_region_name" 2>/dev/null; fi

    # ★★★ 維持: ISP情報の永続キャッシュへの書き込み ★★★
    # (common-information.sh 内で行うのが自然なため維持)
    if [ -n "$ISP_NAME" ] || [ -n "$ISP_AS" ]; then
        local isp_cache_file="${CACHE_DIR}/isp_info.ch"
        echo "$ISP_NAME" > "$isp_cache_file"
        echo "$ISP_AS" >> "$isp_cache_file"
        # ★★★ 修正: ISP_ORG は ISP_NAME と同じ値が入るので不要 ★★★
        # echo "$ISP_ORG" >> "$isp_cache_file"
        debug_log "DEBUG" "Saved ISP information to permanent cache: $isp_cache_file"
    else
        rm -f "${CACHE_DIR}/isp_info.ch" 2>/dev/null
    fi

    debug_log "DEBUG: Location information processing completed successfully in process_location_info"
    return 0
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
        fi

        # 読み込んだ情報が空でないことを最終確認
        if [ -n "$cached_lang" ] && [ -n "$cached_zone" ] && [ -n "$cached_tz" ]; then
            debug_log "DEBUG" "Valid location cache found. Displaying information."

            # 翻訳システムの初期化を確認/実行 (display_detected_location がメッセージキーを使うため)
            # check_common 内で common-translation.sh が source されていれば不要かもしれないが念のため
            if command -v init_translation >/dev/null 2>&1; then
                 # message.ch が存在し、メモリキャッシュが初期化されていなければ初期化
                 if [ -f "${CACHE_DIR}/message.ch" ] && [ "${MSG_MEMORY_INITIALIZED:-false}" != "true" ]; then
                     init_translation
                 elif [ ! -f "${CACHE_DIR}/message.ch" ]; then
                     # message.ch がなければデフォルトで初期化試行
                     init_translation
                 fi
            else
                 debug_log "WARNING" "init_translation function not found. Cannot ensure messages are translated."
            fi

            # common-information.sh の display_detected_location を呼び出す
            if command -v display_detected_location >/dev/null 2>&1; then
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
