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
    debug_log "DEBUG" "Running select_country() function with arg='$1'"
    
    # キャッシュファイルのパス定義
    local cache_country="${CACHE_DIR}/country.ch"
    local tmp_country="${CACHE_DIR}/country_tmp.ch"
    local input_lang="$1"  # 引数として渡された言語コード

    # キャッシュがあればゾーン選択へスキップ
    if [ -f "$cache_country" ]; then
        debug_log "DEBUG" "Country cache exists. Skipping country selection."
        select_zone
        return
    fi

    # システム情報の取得試行
    local system_country=""
    if type get_country_info >/dev/null 2>&1; then
        # 国名のみを抽出（ロケールなどの付加情報は除外）
        system_country=$(get_country_info | awk '{print $2}')
        debug_log "DEBUG" "Detected system country: $system_country"
        
        # 検出された国を表示
        if [ -n "$system_country" ]; then
            # まず検出された国を表示
            printf "%s %s\n" "$(get_message "MSG_DETECTED_COUNTRY")" "$(color white_underline "$system_country")"
            # 次に確認メッセージを表示
            printf "%s\n" "$(get_message "MSG_USE_DETECTED_COUNTRY")"
            # 最後にconfirm関数でYN判定を表示
            if confirm "MSG_CONFIRM_ONLY_YN"; then
                # country.dbから完全な情報を検索
                local country_data=$(grep -i "^[^ ]* *$system_country" "$BASE_DIR/country.db")
                
                if [ -n "$country_data" ]; then
                    # キャッシュに直接書き込み
                    echo "$country_data" > "$cache_country"
                    
                    # 言語情報の抽出と保存
                    echo "$(echo "$country_data" | awk '{print $4}')" > "${CACHE_DIR}/language.ch"
                    echo "$(echo "$country_data" | awk '{print $4}')" > "${CACHE_DIR}/luci.ch"
                    
                    # タイムゾーン情報の抽出 ($6以降)
                    echo "$(echo "$country_data" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone_tmp.ch"
                    
                    # 成功フラグ設定
                    echo "1" > "${CACHE_DIR}/country_success_done"
                    
                    debug_log "INFO" "Auto-detected country has been set: $system_country"
                    select_zone
                    return 0
                else
                    debug_log "WARN" "No matching entry found for detected country: $system_country"
                fi
            fi
        fi
    fi

    # 国の入力と検索ループ
    while true; do
        # 入力がまだない場合は入力を求める
        if [ -z "$input_lang" ]; then
            local msg_enter=$(get_message "MSG_ENTER_COUNTRY")
            printf "%s\n" "$(color blue "$msg_enter")"
            
            local msg_search=$(get_message "MSG_SEARCH_KEYWORD")
            printf "%s " "$(color cyan "$msg_search")"
            
            read -r input_lang
            debug_log "DEBUG" "User entered search keyword: $input_lang"
        fi

        # 空の入力をチェック
        if [ -z "$input_lang" ]; then
            debug_log "WARN" "Empty search keyword"
            continue
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
            local escaped_input=$(echo "$input_lang" | sed 's/[\/&]/\\&/g')
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
            local msg_prefix=${msg%%\{0\}*}
            local msg_suffix=${msg#*\{0\}}
            
            printf "%s%s%s\n" "$(color blue "$msg_prefix")" "$(color white_underline "$country_name")" "$(color blue "$msg_suffix")"
            
            # 確認（confirm関数使用）
            if confirm "MSG_CONFIRM_ONLY_YN"; then
                echo "$full_results" > "$tmp_country"
                
                # 直接キャッシュ書き込み（country_write関数を使用しない場合）
                echo "$full_results" > "$cache_country"
                echo "$(echo "$full_results" | awk '{print $4}')" > "${CACHE_DIR}/language.ch"
                echo "$(echo "$full_results" | awk '{print $4}')" > "${CACHE_DIR}/luci.ch"
                echo "$(echo "$full_results" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone_tmp.ch"
                echo "1" > "${CACHE_DIR}/country_success_done"
                
                debug_log "INFO" "Country selected from single match: $country_name"
                select_zone
                return 0
            else
                input_lang=""
                continue
            fi
        fi

        # 複数結果の場合、リスト表示して選択
        debug_log "DEBUG" "Multiple results found for '$input_lang'. Displaying selection list."
        
        # 表示用リスト作成
        echo "$full_results" | awk '{print NR, ":", $2, $3}'
        
        # 番号入力要求
        local msg_select=$(get_message "MSG_SELECT_COUNTRY_NUMBER")
        printf "%s " "$(color cyan "$msg_select")"
        
        local number
        read -r number
        debug_log "DEBUG" "User selected number: $number"
        
        # 選択された番号の検証
        if echo "$number" | grep -q '^[0-9]\+$'; then
            if [ "$number" -gt 0 ] && [ "$number" -le "$result_count" ]; then
                # 選択された行を取得
                local selected_full=$(echo "$full_results" | sed -n "${number}p")
                local selected_country=$(echo "$selected_full" | awk '{print $2, $3}')
                
                # 確認メッセージ表示
                local msg_selected=$(get_message "MSG_SELECTED_COUNTRY")
                local msg_prefix=${msg_selected%%\{0\}*}
                local msg_suffix=${msg_selected#*\{0\}}
                
                printf "%s%s%s\n" "$(color blue "$msg_prefix")" "$(color white_underline "$selected_country")" "$(color blue "$msg_suffix")"
                
                if confirm "MSG_CONFIRM_ONLY_YN"; then
                    # 直接キャッシュに書き込み
                    echo "$selected_full" > "$cache_country"
                    echo "$(echo "$selected_full" | awk '{print $4}')" > "${CACHE_DIR}/language.ch"
                    echo "$(echo "$selected_full" | awk '{print $4}')" > "${CACHE_DIR}/luci.ch"
                    echo "$(echo "$selected_full" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone_tmp.ch"
                    echo "1" > "${CACHE_DIR}/country_success_done"
                    
                    debug_log "INFO" "Country selected from multiple choices: $selected_country"
                    select_zone
                    return 0
                fi
            else
                local msg_invalid=$(get_message "MSG_INVALID_NUMBER")
                printf "%s\n" "$(color red "$msg_invalid")"
            fi
        else
            local msg_invalid=$(get_message "MSG_INVALID_NUMBER")
            printf "%s\n" "$(color red "$msg_invalid")"
        fi
        
        # 再検索するか確認
        if confirm "MSG_SEARCH_AGAIN"; then
            input_lang=""
        else
            # キャンセル処理
            debug_log "INFO" "Country selection canceled by user"
            return 1
        fi
    done
}

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
    debug_log "DEBUG" "Running select_zone() function"
    
    # キャッシュファイルのパス定義
    local cache_zone="${CACHE_DIR}/zone.ch"
    local cache_zonename="${CACHE_DIR}/zonename.ch"
    local cache_timezone="${CACHE_DIR}/timezone.ch"
    
    # すべてのキャッシュファイルが存在する場合はスキップ
    if [ -f "$cache_zone" ] && [ -f "$cache_zonename" ] && [ -f "$cache_timezone" ]; then
        debug_log "DEBUG" "Timezone info already cached. Skipping selection."
        return 0
    fi
    
    # country.dbからタイムゾーン情報を取得
    local tmp_zone="${CACHE_DIR}/zone_tmp.ch"
    
    # zone_tmp.chファイルが存在する場合はそれを使用
    if [ -f "$tmp_zone" ]; then
        debug_log "DEBUG" "Using timezone data from existing temporary file"
        local zone_data=$(cat "$tmp_zone")
        
        # データが空でないことを確認
        if [ -z "$zone_data" ]; then
            debug_log "WARN" "Empty timezone data in temporary file"
        else
            # フォーマットの確認（カンマを含むかどうか）
            if echo "$zone_data" | grep -q ","; then
                # カンマで区切られているデータ
                local zonename=$(echo "$zone_data" | cut -d ',' -f 1)
                local timezone=$(echo "$zone_data" | cut -d ',' -f 2)
                
                debug_log "INFO" "Timezone data parsed: zonename='$zonename', timezone='$timezone'"
                
                # キャッシュに保存
                echo "$zonename" > "$cache_zonename"
                echo "$timezone" > "$cache_timezone"
                echo "$zone_data" > "$cache_zone"
                
                printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
                debug_log "INFO" "Timezone has been set: $zone_data"
                return 0
            fi
        fi
    fi
    
    # システムからのタイムゾーン情報取得
    local system_timezone=""
    local system_zonename=""
    
    if type get_timezone_info >/dev/null 2>&1; then
        system_timezone=$(get_timezone_info)
        debug_log "DEBUG" "System timezone info retrieved: $system_timezone"
    fi
    
    if type get_zonename_info >/dev/null 2>&1; then
        system_zonename=$(get_zonename_info)
        debug_log "DEBUG" "System zonename info retrieved: $system_zonename"
    fi
    
    # タイムゾーン情報がある場合は表示
    if [ -n "$system_timezone" ] && [ -n "$system_zonename" ]; then
        local detected_tz="$system_zonename,$system_timezone"
        
        # 検出結果を表示
        local msg_detected=$(get_message "MSG_DETECTED_TIMEZONE")
        printf "%s %s\n" "$(color blue "$msg_detected")" "$(color white_underline "$detected_tz")"
        
        # 確認を求める
        if confirm "MSG_CONFIRM_ONLY_YN"; then
            # キャッシュファイルに保存
            echo "$system_zonename" > "$cache_zonename"
            echo "$system_timezone" > "$cache_timezone"
            echo "$detected_tz" > "$cache_zone"
            
            # 成功メッセージ
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
            debug_log "INFO" "Timezone has been set: $detected_tz"
            return 0
        fi
    fi
    
    # country.dbからタイムゾーンリストを抽出
    debug_log "DEBUG" "Extracting timezone list from country.db"
    local country_db="${BASE_DIR}/country.db"
    local zone_list=""
    
    if [ -f "$country_db" ]; then
        # country.dbからすべてのユニークなタイムゾーンを抽出 (最終フィールドからカンマ区切りで)
        zone_list=$(awk '{print $NF}' "$country_db" | sort -u)
        debug_log "DEBUG" "Extracted timezone list from country.db"
    else
        debug_log "ERROR" "country.db file not found at: $country_db"
        zone_list="Asia/Tokyo,JST-9"  # デフォルト値
    fi
    
    # リスト表示
    debug_log "DEBUG" "Displaying timezone selection list"
    local msg_select=$(get_message "MSG_SELECT_TIMEZONE")
    printf "%s\n" "$(color blue "$msg_select")"
    
    # 番号付きでリスト表示
    local line_num=0
    echo "$zone_list" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            line_num=$((line_num + 1))
            printf "%3d: %s\n" "$line_num" "$line"
        fi
    done
    
    # 番号入力要求
    local msg_enter=$(get_message "MSG_ENTER_NUMBER")
    printf "%s " "$(color cyan "$msg_enter")"
    
    # 選択番号の入力
    local selected_number
    read -r selected_number
    debug_log "DEBUG" "User selected timezone number: $selected_number"
    
    # 選択結果の処理
    if [ -z "$selected_number" ] || ! echo "$selected_number" | grep -q '^[0-9]\+$'; then
        debug_log "WARN" "Invalid timezone selection or canceled"
        return 1
    fi
    
    # 選択されたタイムゾーンの取得
    local selected_zone=$(echo "$zone_list" | sed -n "${selected_number}p")
    debug_log "DEBUG" "Selected timezone: $selected_zone"
    
    # 選択されたゾーンが空でないことを確認
    if [ -z "$selected_zone" ]; then
        debug_log "ERROR" "Empty timezone selection, invalid number: $selected_number"
        local msg_invalid=$(get_message "MSG_INVALID_NUMBER")
        printf "%s\n" "$(color red "$msg_invalid")"
        return 1
    fi
    
    # 選択されたゾーンの解析
    local zonename=""
    local timezone=""
    
    if echo "$selected_zone" | grep -q ","; then
        # カンマで区切られているデータ
        zonename=$(echo "$selected_zone" | cut -d ',' -f 1)
        timezone=$(echo "$selected_zone" | cut -d ',' -f 2)
    else
        # カンマがない場合はゾーン名としてそのまま使用
        zonename="$selected_zone"
        timezone="GMT0"  # デフォルト値
    fi
    
    # 確認メッセージ表示
    local selected_tz="$zonename,$timezone"
    local msg_confirm=$(get_message "MSG_CONFIRM_TIMEZONE")
    local msg_prefix=${msg_confirm%%\{0\}*}
    local msg_suffix=${msg_confirm#*\{0\}}
    
    printf "%s%s%s\n" "$(color blue "$msg_prefix")" "$(color white_underline "$selected_tz")" "$(color blue "$msg_suffix")"
    
    if confirm "MSG_CONFIRM_ONLY_YN"; then
        # キャッシュファイルに保存
        echo "$zonename" > "$cache_zonename"
        echo "$timezone" > "$cache_timezone"
        echo "$selected_tz" > "$cache_zone"
        
        printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
        debug_log "INFO" "Timezone selection completed: $selected_tz"
        return 0
    else
        # 再選択
        debug_log "INFO" "User canceled timezone selection, restarting"
        select_zone
        return $?
    fi
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
