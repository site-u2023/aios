#!/bin/sh

SCRIPT_VERSION="2025.04.13-00-07"

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
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"
API_MAX_REDIRECTS="${API_MAX_REDIRECTS:-2}"
TIMEZONE_API_SOURCE=""
USER_AGENT="aios-script/${SCRIPT_VERSION:-unknown}"

SELECT_POSIX_TZ=""
SELECT_REGION_NAME=""
SELECT_REGION_CODE=""

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


# ip-api.comから国コードとタイムゾーン情報を取得する関数
get_country_ipapi() {
    local tmp_file="$1"      # 一時ファイルパス
    local network_type="$2"  # ネットワークタイプ
    local api_name="$3"      # API名（ログ用）
    
    local retry_count=0
    local success=0
    
    # API名からドメイン名を抽出
    local api_domain=$(echo "$api_name" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$api_name"
    
    debug_log "DEBUG" "Querying country and timezone from $api_domain"
    
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        # 共通関数を使用してAPIリクエストを実行
        make_api_request "$api_name" "$tmp_file" "$API_TIMEOUT" "IPAPI"
        local request_status=$?
        debug_log "DEBUG" "API request status: $request_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"
        
        if [ $request_status -eq 0 ]; then
            # JSONデータから国コードとタイムゾーン情報を抽出
            SELECT_COUNTRY=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
            SELECT_ZONENAME=$(grep -o '"timezone":"[^"]*' "$tmp_file" | sed 's/"timezone":"//')
            
            # ISP情報も抽出
            ISP_NAME=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
            ISP_AS=$(grep -o '"as":"[^"]*' "$tmp_file" | sed 's/"as":"//')
            ISP_ORG=$(grep -o '"org":"[^"]*' "$tmp_file" | sed 's/"org":"//')
            
            # データが正常に取得できたか確認
            if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                debug_log "DEBUG" "Retrieved from $api_domain - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME"
                if [ -n "$ISP_NAME" ]; then
                    debug_log "DEBUG" "Retrieved ISP info - Name: $ISP_NAME, AS: $ISP_AS"
                fi
                success=1
                break
            else
                debug_log "DEBUG" "Incomplete country/timezone data from $api_domain"
            fi
        else
            debug_log "DEBUG" "Failed to download data from $api_domain"
        fi
        
        debug_log "DEBUG" "API query attempt $((retry_count+1)) failed"
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

# ipinfo.ioから国コードとタイムゾーン情報を取得する関数
get_country_ipinfo() {
    local tmp_file="$1"      # 一時ファイルパス
    local network_type="$2"  # ネットワークタイプ
    local api_name="$3"      # API名（ログ用）
    
    local retry_count=0
    local success=0
    
    # API名からドメイン名を抽出
    local api_domain=$(echo "$api_name" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$api_name"
    
    debug_log "DEBUG" "Querying country and timezone from $api_domain"
    
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        # 共通関数を使用してAPIリクエストを実行
        make_api_request "$api_name" "$tmp_file" "$API_TIMEOUT" "IPINFO"
        local request_status=$?
        debug_log "DEBUG" "API request status: $request_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"
        
        if [ $request_status -eq 0 ]; then
            # JSONデータから国コードとタイムゾーン情報を抽出（スペースを許容するパターン）
            SELECT_COUNTRY=$(grep -o '"country"[[:space:]]*:[[:space:]]*"[^"]*' "$tmp_file" | sed 's/"country"[[:space:]]*:[[:space:]]*"//')
            SELECT_ZONENAME=$(grep -o '"timezone"[[:space:]]*:[[:space:]]*"[^"]*' "$tmp_file" | sed 's/"timezone"[[:space:]]*:[[:space:]]*"//')
            
            # ISP情報も抽出
            local org_raw=$(grep -o '"org"[[:space:]]*:[[:space:]]*"[^"]*' "$tmp_file" | sed 's/"org"[[:space:]]*:[[:space:]]*"//')
            
            # orgフィールドからAS番号とISP名を分離
            if [ -n "$org_raw" ]; then
                ISP_AS=$(echo "$org_raw" | awk '{print $1}')
                ISP_NAME=$(echo "$org_raw" | cut -d' ' -f2-)
                ISP_ORG="$ISP_NAME"
            fi
            
            # データが正常に取得できたか確認
            if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                debug_log "DEBUG" "Retrieved from $api_domain - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME"
                if [ -n "$ISP_NAME" ]; then
                    debug_log "DEBUG" "Retrieved ISP info - Name: $ISP_NAME, AS: $ISP_AS"
                fi
                success=1
                break
            else
                debug_log "DEBUG" "Incomplete country/timezone data from $api_domain"
            fi
        else
            debug_log "DEBUG" "Failed to download data from $api_domain"
        fi
        
        debug_log "DEBUG" "API query attempt $((retry_count+1)) failed"
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

# APIリクエストを実行する共通関数（ネットワークオプション対応版）
make_api_request() {
    # パラメータ
    local url="$1"
    local tmp_file="$2"
    local timeout="${3:-$API_TIMEOUT}"
    local debug_tag="${4:-API}"
    
    # wgetの機能検出
    local wget_capability=$(detect_wget_capabilities)
    local used_url="$url"
    local status=0
    
    debug_log "DEBUG" "[$debug_tag] Making API request to: $url"
    
    # コマンド構築と実行
    case "$wget_capability" in
        "full")
            # 完全なwgetの場合
            debug_log "DEBUG" "[$debug_tag] Using full wget with redirect support"
            wget --no-check-certificate -q -L --max-redirect="${API_MAX_REDIRECTS:-2}" \
                -U "${USER_AGENT}" \
                -O "$tmp_file" "$used_url" -T "$timeout" 2>/dev/null
            status=$?
            ;;
        "https_only"|"basic")
            # 基本wgetの場合（HTTPSを直接指定）
            used_url=$(echo "$url" | sed 's|^http:|https:|')
            debug_log "DEBUG" "[$debug_tag] Using BusyBox wget, forcing HTTPS URL: $used_url"
            wget --no-check-certificate -q -U "${USER_AGENT}" \
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

# Cloudflare Workerから地域情報を取得する関数 (grep/sedパターン修正版)
get_country_cloudflare() {
    local tmp_file="$1" # 一時ファイルパス
    local api_name="Cloudflare Worker (api-relay-worker.site-u.workers.dev)" # ログ用

    local retry_count=0
    local success=0
    local worker_url="https://api-relay-worker.site-u.workers.dev" # Worker URL

    debug_log "DEBUG" "Querying location from $api_name"

    # グローバル変数を初期化
    SELECT_COUNTRY=""
    SELECT_ZONENAME=""
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    SELECT_REGION_NAME=""
    SELECT_REGION_CODE=""

    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        # Worker URLを直接呼び出す
        make_api_request "$worker_url" "$tmp_file" "$API_TIMEOUT" "CLOUDFLARE"
        local request_status=$?
        debug_log "DEBUG" "Cloudflare Worker request status: $request_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"

        # make_api_request の結果とファイルの状態を厳密にチェック
        if [ $request_status -eq 0 ] && [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # 成功した場合のみJSON解析へ進む
            debug_log "DEBUG" "make_api_request successful and tmp_file exists and is not empty."

            # JSONが取得できたか、statusがsuccessか確認 (スペースありパターンに修正)
            local json_status=$(grep -o '"status": "[^"]*' "$tmp_file" | sed 's/"status": "//')
            debug_log "DEBUG" "Extracted JSON status: '$json_status'"

            if [ "$json_status" = "success" ]; then
                debug_log "DEBUG" "JSON status is 'success'. Proceeding with field extraction."

                # JSONデータから情報を抽出 (スペースありパターンに修正)
                SELECT_COUNTRY=$(grep -o '"countryCode": "[^"]*' "$tmp_file" | sed 's/"countryCode": "//')
                SELECT_ZONENAME=$(grep -o '"timezone": "[^"]*' "$tmp_file" | sed 's/"timezone": "//')
                ISP_NAME=$(grep -o '"isp": "[^"]*' "$tmp_file" | sed 's/"isp": "//')
                ISP_AS=$(grep -o '"as": "[^"]*' "$tmp_file" | sed 's/"as": "//')
                [ -n "$ISP_NAME" ] && ISP_ORG="$ISP_NAME"
                SELECT_REGION_NAME=$(grep -o '"regionName": "[^"]*' "$tmp_file" | sed 's/"regionName": "//')
                SELECT_REGION_CODE=$(grep -o '"region": "[^"]*' "$tmp_file" | sed 's/"region": "//')

                # 必須情報が取得できたか確認 (国コードとタイムゾーン名)
                if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                    debug_log "DEBUG" "Required fields (Country & ZoneName) extracted successfully."
                    success=1
                    break # 成功したのでループを抜ける
                else
                    debug_log "DEBUG" "Extraction failed for required fields (Country or ZoneName)."
                    # status:successでも中身が欠けている場合があるのでリトライへ
                fi
            else
                # JSONのstatusが"fail" または statusフィールドがない場合
                local fail_message=$(grep -o '"message": "[^"]*' "$tmp_file" | sed 's/"message": "//') # failメッセージもスペースありパターンに
                debug_log "DEBUG" "Cloudflare Worker returned status '$json_status'. Message: '$fail_message'"
                # status:failの場合はリトライしても無駄な可能性が高いのでループを抜けるか検討。ここではリトライする。
            fi
        else
            # make_api_request失敗、またはファイルに問題がある場合のログを強化
            if [ $request_status -ne 0 ]; then
                 debug_log "DEBUG" "make_api_request failed with status: $request_status"
            elif [ ! -f "$tmp_file" ]; then
                 debug_log "DEBUG" "make_api_request succeeded but tmp_file '$tmp_file' not found."
            elif [ ! -s "$tmp_file" ]; then
                 debug_log "DEBUG" "make_api_request succeeded but tmp_file '$tmp_file' is empty."
            fi
            # リトライ処理へ進む
        fi

        # リトライ処理
        debug_log "DEBUG" "API query attempt $((retry_count+1)) failed, proceeding to retry or exit."
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $API_MAX_RETRIES ]; then
            debug_log "DEBUG" "Sleeping for 1 second before retry."
            sleep 1
        fi
    done

    # 成功した場合は0を、失敗した場合は1を返す
    if [ $success -eq 1 ]; then
        TIMEZONE_API_SOURCE="Cloudflare Worker"
        debug_log "DEBUG" "get_country_cloudflare finished successfully."
        return 0
    else
        debug_log "DEBUG" "get_country_cloudflare finished with failure."
        return 1
    fi
}

get_country_code() {
    # 変数宣言
    local tmp_file=""
    local spinner_active=0
    local api_success=1 # 初期値を失敗(1)に設定

    # グローバル変数の初期化
    SELECT_ZONE="" # Workerからは取得できない
    SELECT_ZONENAME="" # 例: Asia/Tokyo
    # SELECT_TIMEZONE="" # 略称は使用しない
    SELECT_COUNTRY=""
    SELECT_POSIX_TZ="" # 例: JST-9 (country.dbから取得)
    SELECT_REGION_NAME="" # 追加
    SELECT_REGION_CODE="" # 追加
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    TIMEZONE_API_SOURCE="Cloudflare Worker" # 固定

    # キャッシュディレクトリの確認
    [ -d "${CACHE_DIR}" ] || mkdir -p "${CACHE_DIR}"

    # ネットワーク接続状況の取得 (元のコードをそのまま流用)
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

    # 接続がない場合は早期リターン (元のコードをそのまま流用)
    if [ -z "$network_type" ]; then
        debug_log "DEBUG" "No network connectivity, cannot proceed"
        return 1
    fi

    # スピナー開始
    start_spinner "$(color "blue" "Currently querying: Cloudflare Worker")" "yellow"
    spinner_active=1
    debug_log "DEBUG" "Starting location detection process using Cloudflare Worker"

    # --- プライマリ試行: Cloudflare Worker ---
    tmp_file="$(mktemp -t location.XXXXXX)"
    debug_log "DEBUG" "Calling get_country_cloudflare (Primary Attempt)" # 関数名変更
    get_country_cloudflare "$tmp_file" # 関数名変更
    api_success=$?
    rm -f "$tmp_file" 2>/dev/null
    # --- プライマリ試行ここまで ---

    # --- フォールバック処理: 再度 Cloudflare Worker ---
    # プライマリが失敗した場合、再度同じWorkerに試行する枠組み
    if [ $api_success -ne 0 ]; then
        debug_log "DEBUG" "Primary Cloudflare Worker query failed, attempting fallback (retry)."
        update_spinner "$(color "blue" "Retrying query: Cloudflare Worker")" "yellow"

        tmp_file="$(mktemp -t location_fallback.XXXXXX)"
        debug_log "DEBUG" "Calling get_country_cloudflare (Fallback Attempt)" # 関数名変更
        get_country_cloudflare "$tmp_file" # 関数名変更
        api_success=$?
        rm -f "$tmp_file" 2>/dev/null
    fi
    # --- フォールバック処理ここまで ---

    # --- country.db 検索 (POSIXタイムゾーン取得) ---
    # API呼び出しが成功し、ZoneNameが取得できた場合のみ実行
    if [ $api_success -eq 0 ] && [ -n "$SELECT_ZONENAME" ]; then
        debug_log "DEBUG" "Worker query successful. Processing ZoneName: $SELECT_ZONENAME"

        # country.db から POSIXタイムゾーン (SELECT_POSIX_TZ) の取得
        debug_log "DEBUG" "Trying to map ZoneName to POSIX timezone using country.db"
        local db_file="${BASE_DIR}/country.db"
        SELECT_POSIX_TZ="" # 事前にクリア

        if [ -f "$db_file" ]; then
            debug_log "DEBUG" "Searching country.db for ZoneName: $SELECT_ZONENAME"
            local matched_line=$(grep "$SELECT_ZONENAME" "$db_file" | head -1)

            if [ -n "$matched_line" ]; then
                local zone_pairs=$(echo "$matched_line" | cut -d' ' -f5-)
                local found_tz=""

                for pair in $zone_pairs; do
                    # ゾーン名とPOSIX TZがカンマ区切りになっているか確認 (前方一致)
                    if echo "$pair" | grep -q "^$SELECT_ZONENAME,"; then
                        found_tz=$(echo "$pair" | cut -d',' -f2)
                        break
                    fi
                done

                if [ -n "$found_tz" ]; then
                    SELECT_POSIX_TZ="$found_tz"
                    debug_log "DEBUG" "Found POSIX timezone in country.db: $SELECT_POSIX_TZ"
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
        # Workerからの情報取得失敗、またはZoneNameが空の場合
        if [ $api_success -ne 0 ]; then
             debug_log "DEBUG" "Worker query failed. Cannot process timezone."
        else
             debug_log "DEBUG" "ZoneName is empty. Cannot process timezone."
        fi
        SELECT_POSIX_TZ="" # 確実に空にする
    fi
    # --- country.db 検索ここまで ---

    # ISP情報をキャッシュに保存 (元のコードと同じロジック, Worker関数で設定された値を使う)
    if [ -n "$ISP_NAME" ] || [ -n "$ISP_AS" ]; then
        local cache_file="${CACHE_DIR}/isp_info.ch"
        echo "$ISP_NAME" > "$cache_file"
        echo "$ISP_AS" >> "$cache_file"
        echo "$ISP_ORG" >> "$cache_file" # ISP_ORGはISP_NAMEと同じ値が入る想定
        debug_log "DEBUG" "Saved ISP information to cache"
    else
        # キャッシュファイルが存在すれば削除 (古い情報を残さないため)
        rm -f "${CACHE_DIR}/isp_info.ch" 2>/dev/null
    fi

    # 結果のチェックとスピナー停止
    if [ $spinner_active -eq 1 ]; then
        # 成功条件: 国コードとタイムゾーン名(IANA)が取得できていること
        if [ $api_success -eq 0 ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
            local success_msg=$(get_message "MSG_LOCATION_RESULT" "s=successfully")
            stop_spinner "$success_msg" "success"
            debug_log "DEBUG" "Location information retrieved and processed successfully"
            [ -z "$SELECT_POSIX_TZ" ] && debug_log "WARN" "POSIX timezone could not be determined from country.db for $SELECT_ZONENAME"
            return 0 # 成功
        else
            local fail_msg=$(get_message "MSG_LOCATION_RESULT" "s=failed")
            stop_spinner "$fail_msg" "failed"
            debug_log "DEBUG" "Location information retrieval or processing failed"
            return 1 # 失敗
        fi
    fi

    # スピナーがアクティブでなかった場合 (念のため)
    if [ $api_success -eq 0 ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
        return 0 # 成功
    else
        return 1 # 失敗
    fi
}

OK_get_country_code() {
    # 変数宣言
    local network_type=""
    local tmp_file=""
    local spinner_active=0
    
    # API URLの定数化
    local API_IPINFO="https://ipinfo.io"
    local API_IPAPI="http://ip-api.com/json"
    
    # パラメータ（タイムゾーンAPIの種類）
    local timezone_api="${1:-$API_IPAPI}"
    TIMEZONE_API_SOURCE="$timezone_api"
    
    # タイムゾーンAPIと関数のマッピング
    local api_func=""
    case "$timezone_api" in
        *"ipinfo.io"*)
            api_func="get_country_ipinfo"
            timezone_api="$API_IPINFO"
            ;;
        *"ip-api.com"*)
            api_func="get_country_ipapi"
            timezone_api="$API_IPAPI"
            ;;
        *)
            # デフォルトはipinfo.ioを使用
            api_func="get_country_ipinfo"
            timezone_api="$API_IPINFO"
            ;;
    esac
    
    # APIドメイン名を抽出
    local api_domain=$(echo "$timezone_api" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    [ -z "$api_domain" ] && api_domain="$timezone_api"
    
    # グローバル変数の初期化
    SELECT_ZONE=""
    SELECT_ZONENAME=""
    SELECT_TIMEZONE=""
    SELECT_COUNTRY=""
    SELECT_POSIX_TZ=""
    
    # ISP関連の変数も初期化（追加）
    ISP_NAME=""
    ISP_AS=""
    ISP_ORG=""
    
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
    
    # スピナー開始 - 翻訳APIスタイルに統一
    start_spinner "$(color "blue" "Currently querying: $api_domain")" "yellow"
    spinner_active=1
    debug_log "DEBUG" "Starting location detection process"
    
    # IPアドレス、国コードとタイムゾーン情報の取得
    tmp_file="$(mktemp -t location.XXXXXX)"
    debug_log "DEBUG" "Calling API function: $api_func for API: $timezone_api"
    
    # 動的に関数を呼び出し
    $api_func "$tmp_file" "$network_type" "$timezone_api"
    local api_success=$?
    
    # 一時ファイルの削除
    rm -f "$tmp_file" 2>/dev/null
    
    # API呼び出しが失敗した場合、代替APIを試行
    if [ $api_success -ne 0 ]; then
        debug_log "DEBUG" "Primary API failed, trying alternative API"
        
        # 代替APIとそれに対応する関数を選択
        local alt_api=""
        local alt_func=""
        
        if [ "$api_func" = "get_country_ipinfo" ]; then
            alt_api="$API_IPAPI"
            alt_func="get_country_ipapi"
        else
            alt_api="$API_IPINFO"
            alt_func="get_country_ipinfo"
        fi
        
        # 代替APIのドメイン名を抽出
        local alt_api_domain=$(echo "$alt_api" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
        [ -z "$alt_api_domain" ] && alt_api_domain="$alt_api"

        # スピナーメッセージ更新 - 翻訳APIスタイルに統一
        update_spinner "$(color "blue" "Currently querying: $alt_api_domain")" "yellow"
        
        # 代替API呼び出し
        tmp_file="$(mktemp -t location.XXXXXX)"
        debug_log "DEBUG" "Calling alternative API function: $alt_func for API: $alt_api"
        
        $alt_func "$tmp_file" "$network_type" "$alt_api"
        api_success=$?
        
        # 一時ファイルの削除
        rm -f "$tmp_file" 2>/dev/null
    fi
    
    # ゾーン名が取得できている場合は、country.dbからマッピングを試みる
    if [ -n "$SELECT_ZONENAME" ]; then
        debug_log "DEBUG" "Trying to map zonename to timezone using country.db"
        local db_file="${BASE_DIR}/country.db"
        
        # country.dbが存在するか確認
        if [ -f "$db_file" ]; then
            # ゾーン名からタイムゾーン文字列を検索
            debug_log "DEBUG" "Searching country.db for zonename: $SELECT_ZONENAME"
            
            # 行全体を取得してから、ゾーン名を含む部分のタイムゾーンを抽出
            local matched_line=$(grep "$SELECT_ZONENAME" "$db_file" | head -1)
            
            if [ -n "$matched_line" ]; then
                # ゾーン名に一致するフィールドを見つける
                local zone_pairs=$(echo "$matched_line" | cut -d' ' -f5-)
                local found_tz=""
                
                # スペースで区切られた各ペアをチェック
                for pair in $zone_pairs; do
                    # ゾーン名とタイムゾーンがカンマで区切られているか確認
                    if echo "$pair" | grep -q "$SELECT_ZONENAME,"; then
                        # ゾーン名に続くタイムゾーンを抽出
                        found_tz=$(echo "$pair" | cut -d',' -f2)
                        break
                    fi
                done
                
                if [ -n "$found_tz" ]; then
                    # SELECT_TIMEZONEを上書き
                    SELECT_TIMEZONE="$found_tz"
                    debug_log "DEBUG" "Found timezone in country.db: $SELECT_TIMEZONE for zonename: $SELECT_ZONENAME"
                else
                    debug_log "DEBUG" "No matching timezone pair found in country.db for: $SELECT_ZONENAME"
                    
                    # 既存のタイムゾーンがない場合は、ゾーン名から3文字の略称を生成
                    if [ -z "$SELECT_TIMEZONE" ]; then
                        SELECT_TIMEZONE=$(echo "$SELECT_ZONENAME" | awk -F'/' '{print $NF}' | cut -c1-3 | tr 'a-z' 'A-Z')
                        debug_log "DEBUG" "Generated timezone abbreviation: $SELECT_TIMEZONE"
                    fi
                fi
            else
                debug_log "DEBUG" "No matching line found in country.db for: $SELECT_ZONENAME"
                
                # 既存のタイムゾーンがない場合は、ゾーン名から3文字の略称を生成
                if [ -z "$SELECT_TIMEZONE" ]; then
                    SELECT_TIMEZONE=$(echo "$SELECT_ZONENAME" | awk -F'/' '{print $NF}' | cut -c1-3 | tr 'a-z' 'A-Z')
                    debug_log "DEBUG" "Generated timezone abbreviation: $SELECT_TIMEZONE"
                fi
            fi
        else
            debug_log "DEBUG" "country.db not found at: $db_file"
            
            # country.dbがない場合も、ゾーン名から3文字の略称を生成
            if [ -z "$SELECT_TIMEZONE" ]; then
                SELECT_TIMEZONE=$(echo "$SELECT_ZONENAME" | awk -F'/' '{print $NF}' | cut -c1-3 | tr 'a-z' 'A-Z')
                debug_log "DEBUG" "Generated timezone abbreviation (no DB): $SELECT_TIMEZONE"
            fi
        fi
    fi
    
    # ISP情報をキャッシュに保存（追加）
    if [ -n "$ISP_NAME" ] || [ -n "$ISP_AS" ]; then
        local cache_file="${CACHE_DIR}/isp_info.ch"
        echo "$ISP_NAME" > "$cache_file"
        echo "$ISP_AS" >> "$cache_file"
        echo "$ISP_ORG" >> "$cache_file"
        debug_log "DEBUG" "Saved ISP information to cache"
    fi
    
    # 結果のチェックとスピナー停止
    if [ $spinner_active -eq 1 ]; then
        if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ]; then
            local success_msg=$(get_message "MSG_LOCATION_RESULT" "s=successfully")
            stop_spinner "$success_msg" "success"
            debug_log "DEBUG" "Location information retrieved successfully"
            return 0
        else
            local fail_msg=$(get_message "MSG_LOCATION_RESULT" "s=failed")
            stop_spinner "$fail_msg" "failed"
            debug_log "DEBUG" "Location information process failed - incomplete data received"
            return 1
        fi
    fi
    
    return 1
}

# IPアドレスから地域情報を取得しキャッシュファイルに保存する関数 (変数参照修正版)
process_location_info() {
    local skip_retrieval=0

    # パラメータ処理（オプション）
    # SELECT_POSIX_TZ もチェックに加える
    if [ "$1" = "use_cached" ] && [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_POSIX_TZ" ] && [ -n "$SELECT_ZONENAME" ]; then
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

    # デバッグログで SELECT_POSIX_TZ も表示するように修正
    debug_log "DEBUG: Processing location data - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME, POSIX TZ: $SELECT_POSIX_TZ"

    # キャッシュファイルのパス定義
    local tmp_country="${CACHE_DIR}/ip_country.tmp"
    # local tmp_zone="${CACHE_DIR}/ip_zone.tmp" # SELECT_ZONE は Cloudflare Worker から取得しないので不要
    local tmp_timezone="${CACHE_DIR}/ip_timezone.tmp"
    local tmp_zonename="${CACHE_DIR}/ip_zonename.tmp"
    local tmp_isp="${CACHE_DIR}/ip_isp.tmp"
    local tmp_as="${CACHE_DIR}/ip_as.tmp"
    local tmp_region_name="${CACHE_DIR}/ip_region_name.tmp" # 追加
    local tmp_region_code="${CACHE_DIR}/ip_region_code.tmp" # 追加

    # 必須情報 (国コード, POSIXタイムゾーン, IANAゾーン名) が揃っているか確認 (SELECT_TIMEZONE -> SELECT_POSIX_TZ に変更)
    if [ -z "$SELECT_COUNTRY" ] || [ -z "$SELECT_POSIX_TZ" ] || [ -z "$SELECT_ZONENAME" ]; then
        # POSIXタイムゾーンが見つからない場合でも、国とZoneNameがあれば処理を続けたい場合もあるが、
        # ここではPOSIXタイムゾーンも必須とする。country.dbが見つからない場合は get_country_code が失敗する想定。
        # もしPOSIX TZが必須でないなら、ここの条件から SELECT_POSIX_TZ を外す。
        debug_log "ERROR: Incomplete location data - required information missing (Country, POSIX TZ, or ZoneName)"
        # 既存のファイルを削除してクリーンな状態を確保
        rm -f "$tmp_country" "$tmp_timezone" "$tmp_zonename" "$tmp_isp" "$tmp_as" "$tmp_region_name" "$tmp_region_code" 2>/dev/null
        return 1
    fi

    debug_log "DEBUG: All required location data available, saving to cache files"

    # 国コードをキャッシュに保存
    echo "$SELECT_COUNTRY" > "$tmp_country"
    debug_log "DEBUG: Country code saved to cache: $SELECT_COUNTRY"

    # ゾーンネームをキャッシュに保存（例：Asia/Tokyo）
    echo "$SELECT_ZONENAME" > "$tmp_zonename"
    debug_log "DEBUG: Zone name saved to cache: $SELECT_ZONENAME"

    # POSIXタイムゾーン文字列をキャッシュに保存（例：JST-9）
    echo "$SELECT_POSIX_TZ" > "$tmp_timezone"
    debug_log "DEBUG: POSIX timezone saved to cache: $SELECT_POSIX_TZ"

    # ISP情報をキャッシュに保存
    if [ -n "$ISP_NAME" ]; then
        echo "$ISP_NAME" > "$tmp_isp"
        debug_log "DEBUG: ISP name saved to cache: $ISP_NAME"
    else
        rm -f "$tmp_isp" 2>/dev/null # 空ならファイルを削除
    fi

    if [ -n "$ISP_AS" ]; then
        echo "$ISP_AS" > "$tmp_as"
        debug_log "DEBUG: AS number saved to cache: $ISP_AS"
    else
        rm -f "$tmp_as" 2>/dev/null # 空ならファイルを削除
    fi

    # 地域情報をキャッシュに保存 (追加)
    if [ -n "$SELECT_REGION_NAME" ]; then
        echo "$SELECT_REGION_NAME" > "$tmp_region_name"
        debug_log "DEBUG: Region name saved to cache: $SELECT_REGION_NAME"
    else
        rm -f "$tmp_region_name" 2>/dev/null
    fi
    if [ -n "$SELECT_REGION_CODE" ]; then
        echo "$SELECT_REGION_CODE" > "$tmp_region_code"
        debug_log "DEBUG: Region code saved to cache: $SELECT_REGION_CODE"
    else
        rm -f "$tmp_region_code" 2>/dev/null
    fi

    # 不要になったSELECT_ZONE関連の処理と、POSIXタイムゾーンのフォールバック生成ロジックを削除
    # (get_country_code で SELECT_POSIX_TZ が設定されるため)

    debug_log "DEBUG: Location information cache process completed successfully"
    return 0
}

# IPアドレスから地域情報を取得しキャッシュファイルに保存する関数
OK_process_location_info() {
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
    local tmp_isp="${CACHE_DIR}/ip_isp.tmp"
    local tmp_as="${CACHE_DIR}/ip_as.tmp"
    
    # 3つの重要情報が揃っているか確認
    if [ -z "$SELECT_COUNTRY" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_ZONENAME" ]; then
        debug_log "ERROR: Incomplete location data - required information missing"
        # 既存のファイルを削除してクリーンな状態を確保
        rm -f "$tmp_country" "$tmp_zone" "$tmp_timezone" "$tmp_zonename" "$tmp_isp" "$tmp_as" 2>/dev/null
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
    
    # ISP情報をキャッシュに保存（追加）
    if [ -n "$ISP_NAME" ]; then
        echo "$ISP_NAME" > "$tmp_isp"
        debug_log "DEBUG: ISP name saved to cache: $ISP_NAME"
    fi
    
    if [ -n "$ISP_AS" ]; then
        echo "$ISP_AS" > "$tmp_as"
        debug_log "DEBUG: AS number saved to cache: $ISP_AS"
    fi
    
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
