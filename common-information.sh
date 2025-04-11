#!/bin/sh

SCRIPT_VERSION="2025.04.11-00-00"

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
    
    # ローカルでwgetコマンドを設定（リダイレクト対応）
    local wget_cmd="wget --no-check-certificate -q -L --max-redirect=${API_MAX_REDIRECTS:-2}"
    
    local retry_count=0
    local success=0
    
    # スピナー更新メッセージ
    local country_msg=$(get_message "MSG_QUERY_INFO" "t=country+timezone" "api=ip-api.com" "n=$network_type")
    update_spinner "$(color "blue" "$country_msg")" "yellow"
    
    debug_log "DEBUG" "Querying country and timezone from ip-api.com"
    
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        # リダイレクト対応のwgetコマンドを使用
        $wget_cmd -O "$tmp_file" "$api_name" -T $API_TIMEOUT 2>/dev/null
        local wget_status=$?
        debug_log "DEBUG" "wget exit code: $wget_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"
        
        if [ $wget_status -eq 0 ] && [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # JSONデータから国コードとタイムゾーン情報を抽出
            SELECT_COUNTRY=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | sed 's/"countryCode":"//')
            SELECT_ZONENAME=$(grep -o '"timezone":"[^"]*' "$tmp_file" | sed 's/"timezone":"//')
            
            # ISP情報も抽出（追加）
            ISP_NAME=$(grep -o '"isp":"[^"]*' "$tmp_file" | sed 's/"isp":"//')
            ISP_AS=$(grep -o '"as":"[^"]*' "$tmp_file" | sed 's/"as":"//')
            ISP_ORG=$(grep -o '"org":"[^"]*' "$tmp_file" | sed 's/"org":"//')
            
            # データが正常に取得できたか確認
            if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                debug_log "DEBUG" "Retrieved from ip-api.com - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME"
                if [ -n "$ISP_NAME" ]; then
                    debug_log "DEBUG" "Retrieved ISP info - Name: $ISP_NAME, AS: $ISP_AS"
                fi
                success=1
                break
            else
                debug_log "DEBUG" "Incomplete country/timezone data from ip-api.com"
            fi
        else
            debug_log "DEBUG" "Failed to download data from ip-api.com (status: $wget_status)"
        fi
        
        debug_log "DEBUG" "ip-api.com query attempt $((retry_count+1)) failed"
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
    
    # ローカルでwgetコマンドを設定（リダイレクト対応）
    local wget_cmd="wget --no-check-certificate -q -L --max-redirect=${API_MAX_REDIRECTS:-2}"
    
    local retry_count=0
    local success=0
    
    # スピナー更新メッセージ
    local country_msg=$(get_message "MSG_QUERY_INFO" "t=country+timezone" "a=ipinfo.io" "n=$network_type")
    update_spinner "$(color "blue" "$country_msg")" "yellow"
    
    debug_log "DEBUG" "Querying country and timezone from ipinfo.io"
    
    while [ $retry_count -lt $API_MAX_RETRIES ]; do
        # リダイレクト対応のwgetコマンドを使用
        $wget_cmd -O "$tmp_file" "$api_name" -T $API_TIMEOUT 2>/dev/null
        local wget_status=$?
        debug_log "DEBUG" "wget exit code: $wget_status (attempt: $((retry_count+1))/$API_MAX_RETRIES)"
        
        if [ $wget_status -eq 0 ] && [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # JSONデータから国コードとタイムゾーン情報を抽出（スペースを許容するパターン）
            SELECT_COUNTRY=$(grep -o '"country"[[:space:]]*:[[:space:]]*"[^"]*' "$tmp_file" | sed 's/"country"[[:space:]]*:[[:space:]]*"//')
            SELECT_ZONENAME=$(grep -o '"timezone"[[:space:]]*:[[:space:]]*"[^"]*' "$tmp_file" | sed 's/"timezone"[[:space:]]*:[[:space:]]*"//')
            
            # ISP情報も抽出（追加）
            local org_raw=$(grep -o '"org"[[:space:]]*:[[:space:]]*"[^"]*' "$tmp_file" | sed 's/"org"[[:space:]]*:[[:space:]]*"//')
            
            # orgフィールドからAS番号とISP名を分離
            if [ -n "$org_raw" ]; then
                ISP_AS=$(echo "$org_raw" | awk '{print $1}')
                ISP_NAME=$(echo "$org_raw" | cut -d' ' -f2-)
                ISP_ORG="$ISP_NAME"  # ipinfo.ioではISP名と組織名が分かれていないため
            fi
            
            # データが正常に取得できたか確認
            if [ -n "$SELECT_COUNTRY" ] && [ -n "$SELECT_ZONENAME" ]; then
                debug_log "DEBUG" "Retrieved from ipinfo.io - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME"
                if [ -n "$ISP_NAME" ]; then
                    debug_log "DEBUG" "Retrieved ISP info - Name: $ISP_NAME, AS: $ISP_AS"
                fi
                success=1
                break
            else
                debug_log "DEBUG" "Incomplete country/timezone data from ipinfo.io"
            fi
        else
            debug_log "DEBUG" "Failed to download data from ipinfo.io (status: $wget_status)"
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
    local network_type=""
    local tmp_file=""
    local spinner_active=0
    
    # API URLの定数化
    local API_IPINFO="https://ipinfo.io"
    local API_IPAPI="https://ip-api.com/json"
    
    # パラメータ（タイムゾーンAPIの種類）
    local timezone_api="${1:-$API_IPINFO}"
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
    
    # スピナー開始
    local init_msg=$(get_message "MSG_QUERY_INFO" "t=location information" "a=$timezone_api" "n=$network_type")
    start_spinner "$(color "blue" "$init_msg")" "yellow"
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
        
        # スピナーメッセージ更新
        local retry_msg=$(get_message "MSG_QUERY_INFO" "t=location information" "a=alternative API" "n=$network_type")
        update_spinner "$(color "blue" "$retry_msg")" "yellow"
        
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
