#!/bin/sh

SCRIPT_VERSION="2025.03.12-00-01"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-10
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
# ✅ Use `$(command)` instead of backticks `` `command` ``
# ✅ Use `$(( ))` for arithmetic instead of `let`
# ✅ Define functions as `func_name() {}` (no `function` keyword)
# ✅ No associative arrays (`declare -A` is NOT supported)
# ✅ No here-strings (`<<<` is NOT supported)
# ✅ No `-v` flag in `test` or `[[`
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
# =========================================================
### =========================================================
### 📌 AI Assistance Request: Bug Fixing Procedure
### 
### When debugging or fixing errors in this script, follow these steps:
### 
### 1️⃣ Create a minimal test script to identify the bug.
### 2️⃣ Execute the test and verify the reproducibility of the error.
### 3️⃣ Fix the error and re-run the test to confirm the solution.
### 4️⃣ Apply the corrected code to the production environment.
### 
### ⚠️ DO NOT modify the main script without first confirming the fix 
###     through a dedicated test script.
### 
### 🛠️ Keep the debugging process structured, efficient, and reliable.
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
normalize_input() {
    input="$1"
    # **全角数字 → 半角数字**
    input=$(echo "$input" | sed 'y/０１２３４５６７８９/0123456789/')

    # **不要なログを削除（echo のみを使用）**
    echo "$input"
}

#########################################################################
# Last Update: 2025-03-10 11:00:00 (JST) 🚀
# "Country selection with dynamic system information integration."
# select_country: ユーザーに国の選択を促す（システム情報とデータベース情報を統合）
#
# 1. システム情報からデフォルトの言語・国を検出
# 2. country.db と比較してマッチするエントリを探索
# 3. 見つかった場合、それをデフォルト選択として提案
# 4. ユーザーが選択または検索キーワードを入力
#########################################################################
select_country() {
    debug_log "DEBUG" "Entering select_country() with arg: '$1'"

    local cache_country="${CACHE_DIR}/country.ch"
    local tmp_country="${CACHE_DIR}/country_tmp.ch"
    local input_lang="$1"  # 引数として渡された言語コード（無ければ後で入力）

    # キャッシュがあればゾーン選択へスキップ
    if [ -f "$cache_country" ]; then
        debug_log "DEBUG" "Country cache found. Skipping selection."
        select_zone
        return
    fi

    # システム情報からデフォルト値を取得
    local system_language=""
    local system_country=""
    
    if type get_country_info >/dev/null 2>&1; then
        # システム情報から国データを取得
        local system_country_info=$(get_country_info)
        if [ -n "$system_country_info" ]; then
            debug_log "DEBUG" "Found system country info: $system_country_info"
            # デフォルトの言語コードを抽出 ($4)
            system_language=$(echo "$system_country_info" | awk '{print $4}')
            # デフォルトの国名を抽出 ($2)
            system_country=$(echo "$system_country_info" | awk '{print $2}')
        fi
    fi

    # デフォルト値をユーザーに提案
    if [ -z "$input_lang" ] && [ -n "$system_country" ]; then
        printf "%s\n" "$(color cyan "$(get_message "MSG_DETECTED_COUNTRY")" "$system_country")"
    
        if confirm "MSG_USE_DETECTED_COUNTRY"; then
            input_lang="$system_country"
            debug_log "DEBUG" "Using system country: $system_country"
        else
            input_lang=""
            debug_log "DEBUG" "User declined system country. Moving to manual input."
        fi
    fi

    # 国の入力と検索ループ
    while true; do
        # 入力がまだない場合は入力を求める
        if [ -z "$input_lang" ]; then
            printf "%s\n" "$(color cyan "$(get_message "MSG_ENTER_COUNTRY")")"
            printf "%s" "$(color cyan "$(get_message "MSG_SEARCH_KEYWORD")")"
            read -r input_lang
            debug_log "DEBUG" "User entered country search: $input_lang"
        fi

        # 入力の正規化と検索
        local cleaned_input=$(echo "$input_lang" | sed 's/[\/,_]/ /g')
        local full_results=$(awk -v search="$cleaned_input" \
            'BEGIN {IGNORECASE=1} { if ($0 ~ search) print $0 }' \
            "$BASE_DIR/country.db" 2>>"$LOG_DIR/debug.log")

        # 検索結果がない場合
        if [ -z "$full_results" ]; then
            printf "%s\n" "$(color red "$(get_message "MSG_COUNTRY_NOT_FOUND")" "$input_lang")"
            input_lang=""  # リセットして再入力
            continue
        fi

        # 結果が1件のみの場合、自動選択と確認
        local result_count=$(echo "$full_results" | wc -l)
        if [ "$result_count" -eq 1 ]; then
            local country_name=$(echo "$full_results" | awk '{print $2, $3}')
            printf "%s\n" "$(color cyan "$(get_message "MSG_SINGLE_MATCH_FOUND")" "$country_name")"
    
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

        # 複数結果の場合、リスト表示して選択
        debug_log "DEBUG" "Multiple matches found for '$input_lang'. Presenting selection list."
        
        # 表示用リスト作成
        local display_results=$(echo "$full_results" | awk '{print $2, $3}')
        
        echo "$display_results" > "$tmp_country"
        select_list "$display_results" "$tmp_country" "country"
        
        # 選択された番号の検証
        local selected_number=$(cat "$tmp_country")
        if [ -z "$selected_number" ] || ! echo "$selected_number" | grep -q '^[0-9]\+$'; then
            printf "%s\n" "$(color red "$(get_message "MSG_INVALID_NUMBER")")"
            continue
        fi
        
        # 選択されたデータの取得
        local selected_full=$(echo "$full_results" | sed -n "${selected_number}p")
        if [ -z "$selected_full" ]; then
            printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
            continue
        fi
        
        # 選択確認 (重複している部分を削除)
        local selected_country_name=$(echo "$selected_full" | awk '{print $2, $3}')
        printf "%s\n" "$(color cyan "$(get_message "MSG_SELECTED_COUNTRY")" "$selected_country_name")"

        if confirm "MSG_CONFIRM_ONLY_YN"; then
            echo "$selected_full" > "$tmp_country"
            country_write
            select_zone
            return 0
        else
            if confirm "MSG_SEARCH_AGAIN"; then
                input_lang=""
            fi
            continue
        fi
    done
}

#########################################################################
# Last Update: 2025-03-10 11:00:00 (JST) 🚀
# "Handling numbered list selections with enhanced error handling."
#
# select_list: 番号付きリストからユーザーに選択させる関数
# パラメータ:
# $1: 表示するリスト文字列
# $2: 一時ファイルパス
# $3: リストタイプ (country/zone)
#########################################################################
select_list() {
    debug_log "DEBUG" "Entering select_list() with type: $3"
    
    local select_list="$1"
    local tmp_file="$2"
    local type="$3"
    local count=1
    
    # 数値でないときは、リスト表示
    local error_msg=""
    local prompt_msg=""
    
    case "$type" in
        country)
            error_msg="$(get_message "MSG_INVALID_COUNTRY_NUMBER")"
            prompt_msg="$(get_message "MSG_SELECT_COUNTRY_NUMBER")"
            ;;
        zone)
            error_msg="$(get_message "MSG_INVALID_ZONE_NUMBER")"
            prompt_msg="$(get_message "MSG_SELECT_ZONE_NUMBER")"
            ;;
        *)
            error_msg="$(get_message "MSG_INVALID_NUMBER")"
            prompt_msg="$(get_message "MSG_SELECT_NUMBER")"
            ;;
    esac
    
    # リストの行数を数える
    local total_items=$(echo "$select_list" | wc -l)
    
    # 結果が1つだけの場合は自動選択
    if [ "$total_items" -eq 1 ]; then
        echo "1" > "$tmp_file"
        return 0
    fi
    
    # リスト表示
    echo "$select_list" | while read -r line; do
        printf "%s: %s\n" "$count" "$line"
        count=$((count + 1))
    done
    
    # ユーザーに選択を促す
    while true; do
        printf "%s" "$(color cyan "$prompt_msg")"
        read -r number
        number=$(normalize_input "$number")
        
        # 数値チェック
        if ! echo "$number" | grep -q '^[0-9]\+$'; then
            printf "%s\n" "$(color red "$error_msg")"
            continue
        fi
        
        # 範囲チェック
        if [ "$number" -lt 1 ] || [ "$number" -gt "$total_items" ]; then
            printf "%s\n" "$(color red "$(get_message "MSG_NUMBER_OUT_OF_RANGE")" "1-$total_items")"
            continue
        fi
        
        # 選択番号を保存
        echo "$number" > "$tmp_file"
        break
    done
    
    debug_log "DEBUG" "Selected $type number: $(cat $tmp_file)"
}

#########################################################################
# Last Update: 2025-03-10 11:00:00 (JST) 🚀
# "Timezone selection with dynamic system data integration."
#
# select_zone: ユーザーにタイムゾーンの選択を促す
# 1. 選択された国に基づきタイムゾーン候補を取得
# 2. 動的システムデータとマッチングし、デフォルト値を提案
# 3. ユーザーにタイムゾーンの選択を促す
#########################################################################
select_zone() {
    debug_log "DEBUG" "Entering select_zone()"
    
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_zone="${CACHE_DIR}/zone.ch"
    local tmp_zone="${CACHE_DIR}/zone_tmp.ch"
    
    # すでにキャッシュファイルがある場合はスキップ
    if [ -f "$cache_zone" ]; then
        debug_log "DEBUG" "Zone cache found. Skipping zone selection."
        return 0
    fi

    # カントリーファイルが存在するか確認
    if [ ! -f "$cache_country" ]; then
        debug_log "ERROR" "Country file not found. Running select_country first."
        select_country
        return $?
    fi
    
    # カントリー情報を読み込む
    local country_data=$(cat "$cache_country")
    local country_col=$(echo "$country_data" | awk '{print $2}')
    local timezone_cols=$(echo "$country_data" | awk '{for(i=6; i<=NF; i++) printf "%s ", $i; print ""}')
    
    # システムから現在のタイムゾーンを取得
    local current_tz=""
    if type get_current_timezone >/dev/null 2>&1; then
        current_tz=$(get_current_timezone)
        debug_log "DEBUG" "Current system timezone: $current_tz"
    fi
    
    # デフォルトタイムゾーンの検出
    local default_tz=""
    local default_tz_index=0
    local tz_count=0
    
    for zone in $timezone_cols; do
        tz_count=$((tz_count + 1))
        if [ -n "$current_tz" ] && echo "$zone" | grep -q "$current_tz"; then
            default_tz="$zone"
            default_tz_index=$tz_count
            break
        fi
    done
    
    # デフォルト値が見つかった場合、それを提案
    if [ -n "$default_tz" ]; then
        printf "%s\n" "$(color cyan "$(get_message "MSG_DETECTED_TIMEZONE")" "$default_tz")"
    
        if confirm "MSG_USE_DETECTED_TIMEZONE"; then
            debug_log "DEBUG" "Using detected timezone: $default_tz (index: $default_tz_index)"
            echo "$default_tz_index" > "$tmp_zone"
            echo "$default_tz" > "$cache_zone"
            return 0
        fi
    fi
    
    # タイムゾーン一覧を表示して選択させる
    echo "$timezone_cols" | tr ' ' '\n' | grep -v "^$" > "$tmp_zone"
    select_list "$(cat "$tmp_zone")" "$tmp_zone" "zone"
    
    # 選択されたタイムゾーンを取得
    local selected_number=$(cat "$tmp_zone")
    local selected_timezone=$(echo "$timezone_cols" | tr ' ' '\n' | sed -n "${selected_number}p")
    
    # 結果をキャッシュに書き込み
    echo "$selected_timezone" > "$cache_zone"
    
    debug_log "DEBUG" "Selected timezone: $selected_timezone (number: $selected_number)"
}

#########################################################################
# Last Update: 2025-03-10 11:00:00 (JST) 🚀
# "Cache management for country and timezone data."
#
# country_write: 選択された国の情報をキャッシュに書き込む
#########################################################################
# 国と言語情報をキャッシュに書き込む関数
country_write() {
    debug_log "DEBUG" "Entering country_write()"
    
    local tmp_country="${CACHE_DIR}/country_tmp.ch"
    local cache_country="${CACHE_DIR}/country.ch"
    
    # 一時ファイルが存在するか確認
    if [ ! -f "$tmp_country" ]; then
        debug_log "ERROR" "File not found: $tmp_country"
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
        
        debug_log "INFO" "Country information written to cache"
        debug_log "INFO" "Selected country: $(echo "$country_data" | awk '{print $2, $3}')"
    else
        debug_log "ERROR" "No country data to write to cache"
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
            # それ以外の場合、カスタム解析が必要かもしれません
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
        return 1
    fi
    
    return 0
}

#########################################################################
# Last Update: 2025-03-10 11:00:00 (JST) 🚀
# "Seamless timezone configuration with fallback mechanisms."
#
# timezone_setup: タイムゾーンの設定を実行
# 1. キャッシュからタイムゾーン情報を取得
# 2. システム関数を使用して設定（dynamic-system-info.sh から）
# 3. 失敗した場合は伝統的な方法でタイムゾーンを設定
#########################################################################
timezone_setup() {
    debug_log "DEBUG" "Entering timezone_setup()"
    
    local cache_zone="${CACHE_DIR}/zone.ch"
    
    # タイムゾーンキャッシュが存在するか確認
    if [ ! -f "$cache_zone" ]; then
        debug_log "ERROR" "Zone cache not found. Running select_zone first."
        select_zone
        if [ ! -f "$cache_zone" ]; then
            handle_error "ERR_FILE_NOT_FOUND" "$cache_zone"
            return 1
        fi
    fi
    
    # タイムゾーンを取得
    local timezone=$(cat "$cache_zone")
    
    # 動的システム関数を使用して設定
    if type set_system_timezone >/dev/null 2>&1; then
        debug_log "INFO" "Setting timezone using set_system_timezone(): $timezone"
        if set_system_timezone "$timezone"; then
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SET")" "$timezone")"
            return 0
        else
            debug_log "WARN" "Failed to set timezone using set_system_timezone(). Falling back to traditional method."
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
            handle_error "ERR_TIMEZONE_NOT_SUPPORTED"
            return 1
        fi
        
        printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SET")" "$timezone")"
    else
        handle_error "ERR_TIMEZONE_EMPTY"
        return 1
    fi
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
