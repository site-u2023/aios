#!/bin/sh

SCRIPT_VERSION="2025.03.12-00-05"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-02-21
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 24.10.0)
#
# ⚠️ IMPORTANT NOTICE:
# OpenWrt OS exclusively uses **Almquist Shell (ash)** and
# is **NOT** compatible with Bourne-Again Shell (bash).
#
# 📢 POSIX Compliance Guidelines:
# ✅ Use `[` instead of `[[` for conditions
# ✅ Use $(command) instead of backticks `command`
# ✅ Use $(( )) for arithmetic instead of let
# ✅ Define functions as func_name() {} (no function keyword)
# ✅ No associative arrays (declare -A is NOT supported)
# ✅ No here-strings (<<< is NOT supported)
# ✅ No -v flag in test or [[
# ✅ Avoid bash-specific string operations like ${var:0:3}
# ✅ Avoid arrays entirely when possible (even indexed arrays can be problematic)
# ✅ Use printf followed by read instead of read -p
# ✅ Use printf instead of echo -e for portable formatting
# ✅ Avoid process substitution <() and >()
# ✅ Prefer case statements over complex if/elif chains
# ✅ Use command -v instead of which or type for command existence checks
# ✅ Keep scripts modular with small, focused functions
# ✅ Use simple error handling instead of complex traps
# ✅ Test scripts with ash/dash explicitly, not just bash
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
### =========================================================
### 📌 AI Assistance Request: POSIX-Compliant Debugging Guide
### 
### When debugging or fixing errors in this POSIX shell script:
### 
### 1️⃣ Create a minimal reproducible test case (avoid bash features)
### 2️⃣ Test with ash/dash explicitly: dash ./test.sh
### 3️⃣ Use portable debugging methods: echo, printf, or set -x
### 4️⃣ Validate fixes against all POSIX compliance guidelines
### 5️⃣ Ensure the solution works in resource-constrained OpenWrt
### 
### ⚠️ IMPORTANT:
### - Avoid suggesting bash-specific solutions
### - Always test fixes with ash/dash before implementation
### - Prefer simple solutions over complex ones
### - Do not modify production code without test verification
### 
### 🛠️ Keep debugging simple, focused, and POSIX-compliant!
### =========================================================

# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="${BASE_WGET:-wget --no-check-certificate -q -O}"
# BASE_WGET="${BASE_WGET:-wget -O}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
BUILD_DIR="${BUILD_DIR:-$BASE_DIR/build}"
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BUILD_DIR"
DEBUG_MODE="${DEBUG_MODE:-false}"

#########################################################################
# Last Update: 2025-02-18 23:00:00 (JST) 🚀
# "Ensuring consistent input handling and text normalization."
#
# 【要件】
# 1. **入力テキストを正規化（Normalize Input）**
#    - `iconv` が利用可能な場合、UTF-8 から ASCII//TRANSLIT に変換
#    - `iconv` がない場合、元の入力をそのまま返す（スルー）
#
# 2. **適用対象**
#    - **`select_country()`**: **Y/N 確認時のみ適用**
#    - **`select_list()`**: **番号選択 & Y/N 確認時のみ適用**
#    - **`download()`**: **ファイル名の正規化**
#
# 3. **適用しない対象**
#    - **言語選択の曖昧検索には適用しない**（例: `日本語` → `ja` に変換しない）
#    - **バージョンフォーマットの変更はしない**
#
# 4. **依存関係**
#    - `iconv` が **ない場合は何もしない**
#    - `sed` や `awk` を使わず `echo` ベースで処理
#
# 5. **影響範囲**
#    - `common.sh` に統合し、全スクリプトで共通関数として利用
#########################################################################
# 入力テキストを正規化する関数
normalize_input() {
    input="$1"
    # 全角数字を半角数字に変換
    input=$(echo "$input" | sed 'y/０１２３４５６７８９/0123456789/')
    echo "$input"
}

# ユーザーに国の選択を促す関数
select_country() {
    debug_log "DEBUG" "select_country() 実行: 引数='$1'"

    local cache_country="${CACHE_DIR}/country.ch"
    local tmp_country="${CACHE_DIR}/country_tmp.ch"
    local input_lang="$1"  # 引数として渡された言語コード

    # キャッシュがあればゾーン選択へスキップ
    if [ -f "$cache_country" ]; then
        debug_log "DEBUG" "国キャッシュが存在。選択をスキップ"
        select_zone
        return
    fi

    # キャッシュがない場合のみ自動検出を試みる
    if [ "$AUTO_DETECT" != "no" ]; then
        # システム情報の取得試行
        local system_country=""
        if type get_country_info >/dev/null 2>&1; then
            # 国名のみを抽出（ロケールなどの付加情報は除外）
            system_country=$(get_country_info | awk '{print $2}')
            debug_log "DEBUG" "システムから検出された国: $system_country"
            
            # 検出された国を表示（簡潔に）
            if [ -n "$system_country" ]; then
                local msg_detected=$(get_message "MSG_DETECTED_COUNTRY")
                printf "%s %s\n" "$(color blue "$msg_detected")" "$(color cyan "$system_country")"
                
                # 検出された国を使用するか確認
                if confirm "MSG_USE_DETECTED_COUNTRY"; then
                    # country.dbから完全な情報を検索
                    local country_data=$(grep -i "^[^ ]* *$system_country" "$BASE_DIR/country.db")
                    
                    if [ -n "$country_data" ]; then
                        # キャッシュに書き出し
                        echo "$country_data" > "$cache_country"
                        country_write
                        debug_log "INFO" "自動検出された国が設定されました: $system_country"
                        select_zone
                        return 0
                    else
                        debug_log "WARN" "検出された国に対応するエントリが見つかりません: $system_country"
                    fi
                fi
            fi
        else
            # 従来の自動検出を試行（互換性のため）
            if detect_and_set_location; then
                return 0
            fi
        fi
    fi

    # 以下、元のコードと同じ（手動選択部分）
    while true; do
        # 入力がまだない場合は入力を求める
        if [ -z "$input_lang" ]; then
            local msg_enter=$(get_message "MSG_ENTER_COUNTRY")
            printf "%s\n" "$(color blue "$msg_enter")"
            
            local msg_search=$(get_message "MSG_SEARCH_KEYWORD")
            printf "%s " "$(color cyan "$msg_search")"
            
            read -r input_lang
            debug_log "DEBUG" "ユーザーが入力した検索キーワード: $input_lang"
        fi

        # 入力の正規化と検索
        local cleaned_input=$(echo "$input_lang" | sed 's/[\/,_]/ /g')
        local full_results=$(awk -v search="$cleaned_input" \
            'BEGIN {IGNORECASE=1} { if ($0 ~ search) print $0 }' \
            "$BASE_DIR/country.db" 2>>"$LOG_DIR/debug.log")

        # 検索結果がない場合
        if [ -z "$full_results" ]; then
            local msg_not_found=$(get_message "MSG_COUNTRY_NOT_FOUND")
            # エスケープ処理付きのsedでプレースホルダーを置換
            escaped_input=$(echo "$input_lang" | sed 's/[\/&]/\\&/g')
            msg_not_found=$(echo "$msg_not_found" | sed "s/{0}/$escaped_input/g")
            printf "%s\n" "$(color red "$msg_not_found")"
            input_lang=""  # リセットして再入力
            continue
        fi

        # 結果が1件のみの場合、自動選択と確認
        local result_count=$(echo "$full_results" | wc -l)
        if [ "$result_count" -eq 1 ]; then
            local country_name=$(echo "$full_results" | awk '{print $2, $3}')
            
            # メッセージと国名を別々に色付け
            local msg=$(get_message "MSG_SINGLE_MATCH_FOUND")
            msg_prefix=${msg%%\{0\}*}
            msg_suffix=${msg#*\{0\}}
            
            printf "%s%s%s\n" "$(color blue "$msg_prefix")" "$(color blue_underline "$country_name")" "$(color blue "$msg_suffix")"
            
            # 確認（confirm関数使用）
            if confirm "MSG_CONFIRM_ONLY_YN"; then
                echo "$full_results" > "$tmp_country"
                country_write
                select_zone
                return 0
            else
                input_lang=""
                continue
            fi
        fi

        # 複数結果の場合は以下同じ...（省略）
    done
}

#!/bin/sh

# システムの地域情報を検出し設定する関数
detect_and_set_location() {
    debug_log "DEBUG" "detect_and_set_location() 実行"
    
    # システムから国とタイムゾーン情報を取得
    local system_country=""
    local system_timezone=""
    local system_zonename=""
    
    # スクリプトパスの確認
    [ -f "$BASE_DIR/dynamic-system-info.sh" ] || return 1
    
    # 国情報の取得
    system_country=$(. "$BASE_DIR/dynamic-system-info.sh" && get_country_info)
    
    # タイムゾーン情報の取得
    system_timezone=$(. "$BASE_DIR/dynamic-system-info.sh" && get_timezone_info)
    
    # ゾーン名の取得
    system_zonename=$(. "$BASE_DIR/dynamic-system-info.sh" && get_zonename_info)
    
    # 検出できなければ通常フローへ
    if [ -z "$system_country" ] || [ -z "$system_timezone" ]; then
        return 1
    fi
    
    # 検出情報表示
    printf "%s\n" "$(color yellow "$(get_message "MSG_USE_DETECTED_SETTINGS")")"
    printf "%s %s\n" "$(color blue "$(get_message "MSG_DETECTED_COUNTRY")")" "$system_country"
    
    # ゾーン名があれば表示、なければタイムゾーンのみ
    if [ -n "$system_zonename" ]; then
        printf "%s %s,%s\n\n" "$(color blue "$(get_message "MSG_DETECTED_ZONE")")" "$system_zonename" "$system_timezone"
    else
        printf "%s %s\n\n" "$(color blue "$(get_message "MSG_DETECTED_ZONE")")" "$system_timezone"
    fi
    
    # 確認
    printf "%s\n" "$(color blue "$(get_message "MSG_USE_DETECTED_SETTINGS")")"
    if confirm "MSG_CONFIRM_ONLY_YN"; then
        # グローバル変数に検出結果を設定
        DETECTED_COUNTRY="$system_country"
        DETECTED_TIMEZONE="$system_timezone"
        DETECTED_ZONENAME="$system_zonename"
        return 0
    else
        # 拒否された場合は通常フロー
        return 1
    fi
}

# 番号付きリストからユーザーに選択させる関数
# リスト選択を処理する関数
# $1: 表示するリストデータ
# $2: 結果を保存する一時ファイル
# $3: タイプ（country/zone）
# 番号付きリストからユーザーに選択させる関数
select_list() {
    debug_log "DEBUG" "select_list() function executing: type=$3"
    
    local select_list="$1"
    local tmp_file="$2"
    local type="$3"
    local count=1
    
    # タイプに応じたメッセージキーを設定
    local error_msg_key=""
    local prompt_msg_key=""
    
    case "$type" in
        country)
            error_msg_key="MSG_INVALID_COUNTRY_NUMBER"
            prompt_msg_key="MSG_SELECT_COUNTRY_NUMBER"
            ;;
        zone)
            error_msg_key="MSG_INVALID_ZONE_NUMBER"
            prompt_msg_key="MSG_SELECT_ZONE_NUMBER"
            ;;
        *)
            error_msg_key="MSG_INVALID_NUMBER"
            prompt_msg_key="MSG_SELECT_NUMBER"
            ;;
    esac
    
    # リストの行数を数える
    local total_items=$(echo "$select_list" | wc -l)
    
    # 項目が1つしかない場合は自動選択
    if [ "$total_items" -eq 1 ]; then
        echo "1" > "$tmp_file"
        return 0
    fi
    
    # 項目をリスト表示
    echo "$select_list" | while read -r line; do
        printf "%s: %s\n" "$count" "$(color white "$line")"
        count=$((count + 1))
    done
    
    # ユーザーに選択を促す
    while true; do
        # メッセージの取得と表示
        local prompt_msg=$(get_message "$prompt_msg_key" "番号を選択:")
        printf "%s " "$(color cyan "$prompt_msg")"
        read -r number
        number=$(normalize_input "$number")
        
        # 数値チェック
        if ! echo "$number" | grep -q '^[0-9]\+$'; then
            local error_msg=$(get_message "$error_msg_key" "無効な番号です")
            printf "%s\n" "$(color red "$error_msg")"
            continue
        fi
        
        # 範囲チェック
        if [ "$number" -lt 1 ] || [ "$number" -gt "$total_items" ]; then
            local range_msg=$(get_message "MSG_NUMBER_OUT_OF_RANGE" "範囲外の番号です: {0}")
            # プレースホルダー置換（sedでエスケープ処理）
            range_msg=$(echo "$range_msg" | sed "s|{0}|1-$total_items|g")
            printf "%s\n" "$(color red "$range_msg")"
            continue
        fi
        
        # 選択項目を取得
        local selected_value=$(echo "$select_list" | sed -n "${number}p")
        
        # 確認部分で選択内容の表示は行わない（重複表示を避けるため）
        if confirm "MSG_CONFIRM_YNR" "selected_value" "$selected_value"; then
            echo "$number" > "$tmp_file"
            break
        elif [ "$CONFIRM_RESULT" = "R" ]; then
            # リスタートオプション
            debug_log "DEBUG" "User selected restart option"
            rm -f "${CACHE_DIR}/country.ch"
            select_country
            return 0
        fi
        # 他の場合は再選択
    done
    
    debug_log "DEBUG" "Selection complete: $type number $(cat $tmp_file)"
}

# タイムゾーンの選択を処理する関数
select_zone() {
    debug_log "DEBUG" "select_zone() 関数を実行開始"
    
    # キャッシュファイルのパス定義
    local cache_zone="${CACHE_DIR}/zone.ch"
    local cache_zonename="${CACHE_DIR}/zonename.ch"
    local cache_timezone="${CACHE_DIR}/timezone.ch"
    
    # すべてのキャッシュファイルが存在する場合はスキップ
    if [ -f "$cache_zone" ] && [ -f "$cache_zonename" ] && [ -f "$cache_timezone" ]; then
        debug_log "DEBUG" "タイムゾーン情報は既にキャッシュされています"
        return 0
    fi
    
    # システムからのタイムゾーン情報取得を試行
    local system_timezone=""
    local system_zonename=""
    
    # 新関数を使用してタイムゾーン情報を取得
    if type get_timezone_info >/dev/null 2>&1; then
        system_timezone=$(get_timezone_info)
        debug_log "DEBUG" "システムから取得したタイムゾーン: $system_timezone"
    fi
    
    if type get_zonename_info >/dev/null 2>&1; then
        system_zonename=$(get_zonename_info)
        debug_log "DEBUG" "システムから取得したゾーン名: $system_zonename"
    fi
    
    # 自動検出したタイムゾーン情報がある場合
    if [ -n "$system_timezone" ] && [ -n "$system_zonename" ]; then
        local detected_tz="$system_zonename,$system_timezone"
        
        # 検出結果を表示
        local msg_detected=$(get_message "MSG_DETECTED_TIMEZONE")
        printf "%s %s\n" "$(color blue "$msg_detected")" "$(color cyan "$detected_tz")"
        
        # 確認を求める
        if confirm "MSG_CONFIRM_ONLY_YN"; then
            # キャッシュファイルにタイムゾーン情報を保存
            echo "$system_zonename" > "$cache_zonename"
            echo "$system_timezone" > "$cache_timezone"
            echo "$detected_tz" > "$cache_zone"
            
            # 成功メッセージ
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
            debug_log "INFO" "タイムゾーンが自動設定されました: $detected_tz"
            return 0
        fi
    fi
    
    # 手動選択のための主要なタイムゾーンリスト（一覧が長すぎるため、主要なもののみ表示）
    local type="zone"
    local tmp_zone="${CACHE_DIR}/zone_tmp.ch"
    local zone_list=""
    
    # よく使われる主要なタイムゾーンを用意
    # 地域ごとのよく使われるタイムゾーンを優先表示
    local common_zones="America/New_York America/Chicago America/Denver America/Los_Angeles America/Anchorage America/Honolulu Asia/Tokyo Asia/Shanghai Asia/Singapore Asia/Kolkata Europe/London Europe/Paris Europe/Berlin Australia/Sydney Pacific/Auckland"
    
    # available_timezones関数から全リストを取得
    local all_timezones=""
    if type get_available_timezones >/dev/null 2>&1; then
        all_timezones=$(get_available_timezones)
        debug_log "DEBUG" "利用可能なタイムゾーンを取得しました: $(echo "$all_timezones" | wc -l)件"
    else
        # 関数が利用できない場合はフォールバックリストを使用
        debug_log "WARN" "get_available_timezones関数が利用できません。フォールバックリストを使用します"
        all_timezones="$common_zones"
    fi
    
    # 利用可能なタイムゾーンから表示用リストを生成
    # 共通の主要なタイムゾーンを先頭に表示し、その後に全タイムゾーンを表示
    for zone in $common_zones; do
        # タイムゾーン情報を取得 (例: JST-9)
        local tz_info=""
        if [ -f "/usr/share/zoneinfo/$zone" ]; then
            # 実際のタイムゾーン情報を取得するには、TZ環境変数を使用
            tz_info=$(TZ="$zone" date +"%Z%z" | sed 's/+/-/; s/00$//')
            zone_list="${zone_list}${zone} (${tz_info})\n"
        fi
    done
    
    # 重複を除去し、一時ファイルに保存
    echo -e "$zone_list" | sort -u > "$tmp_zone"
    
    # リスト選択実行
    select_list "$(cat "$tmp_zone")" "$tmp_zone" "$type"
    
    # 以下は既存の処理と同じ...
    local selected_number=$(cat "$tmp_zone")
    if [ -z "$selected_number" ] || ! echo "$selected_number" | grep -q '^[0-9]\+$'; then
        debug_log "WARN" "タイムゾーン選択が無効または取消されました"
        return 1
    fi
    
    # 選択されたタイムゾーンの取得と解析
    local selected_zone=$(cat "$tmp_zone" | sed -n "${selected_number}p")
    local zonename=$(echo "$selected_zone" | awk -F'[()]' '{print $1}' | sed 's/ *$//')
    local timezone=$(echo "$selected_zone" | awk -F'[()]' '{print $2}')
    
    # キャッシュファイルに保存
    echo "$zonename" > "$cache_zonename"
    echo "$timezone" > "$cache_timezone"
    echo "$zonename,$timezone" > "$cache_zone"
    
    printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
    debug_log "INFO" "タイムゾーン選択が完了しました: $zonename,$timezone"
    
    return 0
}

# 国と言語情報をキャッシュに書き込む関数
country_write() {
    debug_log "DEBUG" "Entering country_write()"
    
    local tmp_country="${CACHE_DIR}/country_tmp.ch"
    local cache_country="${CACHE_DIR}/country.ch"
    
    # 一時ファイルが存在するか確認
    if [ ! -f "$tmp_country" ]; then
        debug_log "ERROR" "File not found: $tmp_country"
        printf "%s\n" "$(color red "$(get_message "ERR_FILE_NOT_FOUND" | sed "s/{file}/$tmp_country/g")")"
        return 1
    fi
    
    # 選択されたデータを取得
    local country_data=""
    # 数値でない場合はフルラインが含まれていると判断
    if ! grep -qE '^[0-9]+$' "$tmp_country"; then
        country_data=$(cat "$tmp_country")
    else
        # country.dbから該当行を抽出
        local line_number=$(cat "$tmp_country")
        country_data=$(sed -n "${line_number}p" "${BASE_DIR}/country.db")
    fi
    
    # キャッシュに保存
    if [ -n "$country_data" ]; then
        # 1. country.ch - 完全な国情報（基準データ）
        echo "$country_data" > "$cache_country"
        
        # 2. language.ch - 言語コード ($4)
        echo "$(echo "$country_data" | awk '{print $4}')" > "${CACHE_DIR}/language.ch"
        
        # 3. luci.ch - LuCI UI言語コード ($4 - language.chと同じ)
        echo "$(echo "$country_data" | awk '{print $4}')" > "${CACHE_DIR}/luci.ch"
        
        # 4. zone_tmp.ch - タイムゾーン情報 ($6以降)
        echo "$(echo "$country_data" | awk '{for(i=6; i<=NF; i++) printf "%s ", $i; print ""}')" > "${CACHE_DIR}/zone_tmp.ch"
        
        # 成功フラグの設定
        echo "1" > "${CACHE_DIR}/country_success_done"
        
        debug_log "DEBUG" "Country information written to cache"
        debug_log "DEBUG" "Selected country: $(echo "$country_data" | awk '{print $2, $3}')"
    else
        debug_log "ERROR" "No country data to write to cache"
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
        return 1
    fi
    
    return 0
}

# タイムゾーン情報をキャッシュに書き込む関数
zone_write() {
    debug_log "DEBUG" "Entering zone_write()"
    
    local tmp_zone="${CACHE_DIR}/zone_tmp.ch"
    
    # 一時ファイルが存在するか確認
    if [ ! -f "$tmp_zone" ]; then
        debug_log "ERROR" "File not found: $tmp_zone"
        printf "%s\n" "$(color red "$(get_message "ERR_FILE_NOT_FOUND" | sed "s/{file}/$tmp_zone/g")")"
        return 1
    fi
    
    # 選択された番号または直接タイムゾーン情報を取得
    local selected_timezone=""
    local selected_number=""
    
    # ファイルの内容が数値かどうかをチェック
    if grep -qE '^[0-9]+$' "$tmp_zone"; then
        selected_number=$(cat "$tmp_zone")
        
        # zone_tmp.ch から選択された行のタイムゾーンを取得
        local zone_list="${CACHE_DIR}/zone_list.ch"
        if [ -f "$zone_list" ]; then
            selected_timezone=$(sed -n "${selected_number}p" "$zone_list")
        else
            # zone_tmp.chをスペースで分割してn番目の項目を取得
            local zone_data=$(cat "${CACHE_DIR}/zone_tmp.ch")
            selected_timezone=$(echo "$zone_data" | tr ' ' '\n' | sed -n "${selected_number}p")
        fi
    else
        # 直接タイムゾーン情報が含まれている場合
        selected_timezone=$(cat "$tmp_zone")
    fi
    
    # タイムゾーン情報を分割して保存
    if [ -n "$selected_timezone" ]; then
        # タイムゾーン情報を解析（フォーマットに依存）
        local zonename=""
        local timezone=""
        
        # 一般的なフォーマットの場合: "America/New_York"
        if echo "$selected_timezone" | grep -q "/"; then
            zonename="$selected_timezone"
            timezone="$selected_timezone"
        else
            # それ以外の場合、カスタム解析
            zonename="$selected_timezone"
            timezone="$selected_timezone"
        fi
        
        # キャッシュに書き込み
        echo "$zonename" > "${CACHE_DIR}/zonename.ch"
        echo "$timezone" > "${CACHE_DIR}/timezone.ch"
        echo "$selected_timezone" > "${CACHE_DIR}/zone.ch"
        
        # 成功フラグの設定
        echo "1" > "${CACHE_DIR}/timezone_success_done"
        
        debug_log "INFO" "Timezone information written to cache"
        debug_log "INFO" "Selected timezone: $selected_timezone"
    else
        debug_log "ERROR" "No timezone data to write to cache"
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
        return 1
    fi
    
    return 0
}

# タイムゾーンの設定を実行する関数
timezone_setup() {
    debug_log "DEBUG" "Entering timezone_setup()"
    
    local cache_zone="${CACHE_DIR}/zone.ch"
    
    # タイムゾーンキャッシュが存在するか確認
    if [ ! -f "$cache_zone" ]; then
        debug_log "ERROR" "Zone cache not found. Running select_zone first."
        printf "%s\n" "$(color yellow "$(get_message "MSG_TIMEZONE_NOT_FOUND" "タイムゾーンが見つかりません")")"
        select_zone
        if [ ! -f "$cache_zone" ]; then
            printf "%s\n" "$(color red "$(get_message "ERR_FILE_NOT_FOUND" | sed "s/{file}/$cache_zone/g")")"
            return 1
        fi
    fi
    
    # タイムゾーンを取得
    local timezone=$(cat "$cache_zone")
    
    # 動的システム関数を使用して設定
    if type set_system_timezone >/dev/null 2>&1; then
        debug_log "INFO" "Setting timezone using set_system_timezone(): $timezone"
        if set_system_timezone "$timezone"; then
            local msg_set=$(get_message "MSG_TIMEZONE_SET")
            msg_set=$(echo "$msg_set" | sed "s/{timezone}/$timezone/g")
            printf "%s\n" "$(color green "$msg_set")"
            return 0
        else
            debug_log "WARN" "Failed to set timezone using set_system_timezone(). Falling back to traditional method."
            printf "%s\n" "$(color yellow "$(get_message "WARN_FALLBACK_METHOD" "代替方法で設定を試みます")")"
        fi
    fi
    
    # 伝統的な方法でタイムゾーンを設定
    if [ -n "$timezone" ]; then
        debug_log "INFO" "Setting timezone using traditional method: $timezone"
        
        # OpenWrt用タイムゾーン設定（UCI経由）
        if command -v uci >/dev/null 2>&1; then
            uci set system.@system[0].zonename="$timezone"
            uci set system.@system[0].timezone="$timezone"
            uci commit system
            /etc/init.d/system reload
            
        # 汎用Unix系システム用タイムゾーン設定
        elif [ -d "/usr/share/zoneinfo" ]; then
            ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
            echo "$timezone" > /etc/timezone
        else
            printf "%s\n" "$(color red "$(get_message "ERR_TIMEZONE_NOT_SUPPORTED")")"
            return 1
        fi
        
        local msg_set=$(get_message "MSG_TIMEZONE_SET")
        msg_set=$(echo "$msg_set" | sed "s/{timezone}/$timezone/g")
        printf "%s\n" "$(color green "$msg_set")"
    else
        printf "%s\n" "$(color red "$(get_message "ERR_TIMEZONE_EMPTY")")"
        return 1
    fi
    
    return 0
}

# デバッグモードが有効な場合は情報表示
if [ "$DEBUG_MODE" = "true" ]; then
    debug_log "DEBUG" "common-country.sh loaded with BASE_DIR=$BASE_DIR"
    if type get_device_architecture >/dev/null 2>&1; then
        debug_log "DEBUG" "dynamic-system-info.sh loaded successfully"
    else
        debug_log "WARN" "dynamic-system-info.sh not loaded or functions not available"
    fi
fi
