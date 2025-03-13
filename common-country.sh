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
    local cache_zone="${CACHE_DIR}/zone.ch"
    local input_lang="$1"  # 引数として渡された言語コード

    # キャッシュがあれば全ての選択プロセスをスキップ
    if [ -f "$cache_country" ] && [ -f "$cache_zone" ]; then
        debug_log "DEBUG" "Country and Timezone cache exist. Skipping selection process."
        return 0
    fi

    # 自動選択を試行
    detect_and_set_location
    if [ $? -eq 0 ]; then
        return 0
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
            printf "%s %s\n" "$(color blue "$(get_message "MSG_DETECTED_COUNTRY")")" "$(color blue "$system_country")"
            # 次に確認メッセージを表示
            printf "%s\n" "$(color blue "$(get_message "MSG_USE_DETECTED_COUNTRY")")"
            # 最後にconfirm関数でYN判定を表示
            if confirm "MSG_CONFIRM_ONLY_YN"; then
                # country.dbから完全な情報を検索
                local country_data=$(grep -i "^[^ ]* *$system_country" "$BASE_DIR/country.db")

                if [ -n "$country_data" ]; then
                    # 一時ファイルに書き込み
                    echo "$country_data" > "${CACHE_DIR}/country_tmp.ch"
                    # country_write関数に処理を委譲
                    country_write || {
                        debug_log "ERROR" "Failed to write country data"
                        return 1
                    }

                    # zone_write関数に処理を委譲
                    echo "$(echo "$country_data" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone_tmp.ch"
                    zone_write || {
                        debug_log "ERROR" "Failed to write timezone data"
                        return 1
                    }

                    debug_log "DEBUG" "Auto-detected country has been set: $system_country"
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
            local escaped_input="$input_lang"
            escaped_input=$(echo "$escaped_input" | sed 's/\//\\\//g')
            escaped_input=$(echo "$escaped_input" | sed 's/&/\\\&/g')
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

            printf "%s%s%s\n" "$(color blue "$msg_prefix" "$country_name" "$msg_suffix")"

            # 確認（confirm関数使用）
            if confirm "MSG_CONFIRM_ONLY_YN"; then
                echo "$full_results" > "${CACHE_DIR}/country_tmp.ch"

                # country_write関数に処理を委譲
                country_write || {
                    debug_log "ERROR" "Failed to write country data"
                    return 1
                }

                # zone_write関数に処理を委譲
                echo "$(echo "$full_results" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone_tmp.ch"
                zone_write || {
                    debug_log "ERROR" "Failed to write timezone data"
                    return 1
                }

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

                printf "%s%s%s\n" "$(color blue "$msg_prefix" "$selected_country" "$msg_suffix")"

                if confirm "MSG_CONFIRM_ONLY_YN"; then
                    # 一時ファイルに書き込み
                    echo "$selected_full" > "${CACHE_DIR}/country_tmp.ch"

                    # country_write関数に処理を委譲
                    country_write || {
                        debug_log "ERROR" "Failed to write country data"
                        return 1
                    }

                    # zone_write関数に処理を委譲
                    echo "$(echo "$selected_full" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone_tmp.ch"
                    zone_write || {
                        debug_log "ERROR" "Failed to write timezone data"
                        return 1
                    }

                    debug_log "DEBUG" "Country selected from multiple choices: $selected_country"
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
    debug_log "DEBUG" "Running detect_and_set_location() function"
    
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
        debug_log "WARN" "Could not detect system country or timezone"
        return 1
    fi
    
    # 検出情報表示
    printf "%s\n" "$(color yellow "$(get_message "MSG_USE_DETECTED_SETTINGS")")"
    printf "%s %s\n" "$(color blue "$(get_message "MSG_DETECTED_COUNTRY")")" "$(color blue "$system_country")"
    
    # ゾーン名があれば表示、なければタイムゾーンのみ
    if [ -n "$system_zonename" ]; then
        printf "%s %s,%s\n\n" "$(color blue "$(get_message "MSG_DETECTED_ZONE")")" "$system_zonename" "$system_timezone"
    else
        printf "%s %s\n\n" "$(color blue "$(get_message "MSG_DETECTED_ZONE")")" "$system_timezone"
    fi
    
    # 確認
    printf "%s\n" "$(color blue "$(get_message "MSG_USE_DETECTED_SETTINGS")")"
    if confirm "MSG_CONFIRM_ONLY_YN"; then
        # country.dbから完全な国情報を検索
        local country_data=$(grep -i "^[^ ]* *$system_country" "$BASE_DIR/country.db")
        
        if [ -n "$country_data" ]; then
            # 国情報を一時ファイルに書き込み
            echo "$country_data" > "${CACHE_DIR}/country_tmp.ch"
            # country_write関数に処理を委譲
            country_write || {
                debug_log "ERROR" "Failed to write country data"
                return 1
            }
            
            # タイムゾーン情報の抽出 ($6以降) と書き込み
            local timezone_data=$(echo "$country_data" | cut -d ' ' -f 6-)
            echo "$timezone_data" > "${CACHE_DIR}/zone_tmp.ch"
            # zone_write関数に処理を委譲
            zone_write || {
                debug_log "ERROR" "Failed to write timezone data"
                return 1
            }
            
            debug_log "DEBUG" "Auto-detected settings have been applied successfully"
            return 0
        else
            debug_log "WARN" "No matching entry found for detected country: $system_country"
            return 1
        fi
    else
        debug_log "DEBUG" "User declined auto-detected settings"
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
    
    # 選択された国の情報を取得
    local selected_country_file="${CACHE_DIR}/country.ch"
    if [ ! -f "$selected_country_file" ]; then
        debug_log "ERROR" "Country selection file not found"
        return 1
    fi
    
    # 国のタイムゾーン情報を抽出（6列目以降がタイムゾーン情報）
    local zone_list=$(awk '{for(i=6;i<=NF;i++) print $i}' "$selected_country_file")
    if [ -z "$zone_list" ]; then
        debug_log "ERROR" "No timezone information found for selected country"
        return 1
    fi
    debug_log "DEBUG" "Extracted timezone list for selected country"
    
    # タイムゾーンリストの表示
    printf "%s\n" "$(color blue "$(get_message "MSG_SELECT_TIMEZONE")")"
    
    # 番号付きリスト表示
    local count=1
    echo "$zone_list" | while IFS= read -r line; do
        [ -n "$line" ] && printf "%3d: %s\n" "$count" "$line"
        count=$((count + 1))
    done
    
    # 番号入力受付
    printf "%s " "$(color cyan "$(get_message "MSG_ENTER_NUMBER")")"
    read -r number
    debug_log "DEBUG" "User input: $number"
    
    # 入力検証
    if [ -z "$number" ] || ! echo "$number" | grep -q '^[0-9]\+$'; then
        printf "%s\n" "$(color red "$(get_message "MSG_INVALID_NUMBER")")"
        return 1
    fi
    
    # 選択されたタイムゾーンの取得
    local selected=$(echo "$zone_list" | sed -n "${number}p")
    if [ -z "$selected" ]; then
        printf "%s\n" "$(color red "$(get_message "MSG_INVALID_NUMBER")")"
        return 1
    fi
    debug_log "DEBUG" "Selected timezone: $selected"
    
    # タイムゾーン情報の分割
    local zonename=""
    local timezone=""
    
    if echo "$selected" | grep -q ","; then
        zonename=$(echo "$selected" | cut -d ',' -f 1)
        timezone=$(echo "$selected" | cut -d ',' -f 2)
    else
        zonename="$selected"
        timezone="GMT0"
    fi
    
    # 確認
    printf "%s\n" "$(color blue "$(get_message "MSG_CONFIRM_TIMEZONE") $zonename,$timezone")"
    
    if confirm "MSG_CONFIRM_ONLY_YN"; then
        echo "$zonename" > "$cache_zonename"
        echo "$timezone" > "$cache_timezone"
        echo "$zonename,$timezone" > "$cache_zone"
        printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
        return 0
    fi
    
    # 再選択
    select_zone
    return $?
}

#########################################################################
# Last Update: 2025-02-18 11:00:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# normalize_language: 言語設定の正規化
#
# 【要件】
# 1. 言語の決定:
#    - `country.ch` を最優先で参照（変更不可）
#    - `country.ch` が無い場合は `select_country()` を実行し、手動選択
#
# 2. システムメッセージの言語 (`message.ch`) の確定:
#    - `messages.db` の `SUPPORTED_LANGUAGES` を確認
#    - `country.ch` に記録された言語が `SUPPORTED_LANGUAGES` に含まれる場合、それを `message.ch` に保存
#    - `SUPPORTED_LANGUAGES` に無い場合、`message.ch` に `US`（フォールバック）を設定
#
# 3. `country.ch` との関係:
#    - `country.ch` はデバイス設定用（変更不可）
#    - `message.ch` はシステムメッセージ表示用（フォールバック可能）
#
# 4. `$ACTIVE_LANGUAGE` の管理:
#    - `normalize_language()` 実行時に `$ACTIVE_LANGUAGE` を設定
#    - `$ACTIVE_LANGUAGE` は `message.ch` の値を常に参照
#    - `$ACTIVE_LANGUAGE` が未設定の場合、フォールバックで `US`
#
# 5. メンテナンス:
#    - `country.ch` はどのような場合でも変更しない
#    - `message.ch` のみフォールバックを適用し、システムメッセージの一貫性を維持
#    - 言語設定に影響を与えず、メッセージの表示のみを制御する
#########################################################################
normalize_language() {
    local message_db="${BASE_DIR}/messages.db"
    local country_cache="${CACHE_DIR}/country.ch"
    local message_cache="${CACHE_DIR}/message.ch"
    local selected_language=""
    local flag_file="${CACHE_DIR}/country_success_done"

    if [ -f "$flag_file" ]; then
        debug_log "DEBUG" "normalize_language() already done. Skipping repeated success message."
        return 0
    fi

    if [ ! -f "$country_cache" ]; then
        debug_log "ERROR" "country.ch not found. Cannot determine language."
        return 1
    fi

    local country_data
    country_data=$(cat "$country_cache")
    debug_log "DEBUG" "country.ch content: $country_data"

    local field_count
    field_count=$(echo "$country_data" | awk '{print NF}')
    debug_log "DEBUG" "Field count in country.ch: $field_count"

    if [ "$field_count" -ge 5 ]; then
        selected_language=$(echo "$country_data" | awk '{print $5}')
    else
        selected_language=$(echo "$country_data" | awk '{print $2}')
    fi

    debug_log "DEBUG" "Selected language extracted from country.ch -> $selected_language"

    local supported_languages
    supported_languages=$(grep "^SUPPORTED_LANGUAGES=" "$message_db" | cut -d'=' -f2 | tr -d '"')
    debug_log "DEBUG" "Supported languages: $supported_languages"

    if echo "$supported_languages" | grep -qw "$selected_language"; then
        debug_log "DEBUG" "Using message database language: $selected_language"
        echo "$selected_language" > "$message_cache"
        ACTIVE_LANGUAGE="$selected_language"
    else
        debug_log "DEBUG" "Language '$selected_language' not found in messages.db. Using 'US' as fallback."
        echo "US" > "$message_cache"
        ACTIVE_LANGUAGE="US"
    fi

    debug_log "DEBUG" "Final system message language -> $ACTIVE_LANGUAGE"
    echo "$(get_message "MSG_COUNTRY_SUCCESS")"
    touch "$flag_file"
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
        
        # 2. language.ch - 国コード ($5)
        echo "$(echo "$country_data" | awk '{print $5}')" > "${CACHE_DIR}/language.ch"
        
        # 3. luci.ch - LuCI UI言語コード ($4)
        echo "$(echo "$country_data" | awk '{print $4}')" > "${CACHE_DIR}/luci.ch"
        
        # 4. zone_tmp.ch - タイムゾーン情報 ($6以降)
        echo "$(echo "$country_data" | awk '{for(i=6; i<=NF; i++) printf "%s ", $i; print ""}')" > "${CACHE_DIR}/zone_tmp.ch"
        
        # 成功フラグの設定
        echo "1" > "${CACHE_DIR}/country_success_done"
        
        debug_log "DEBUG" "Country information written to cache"
        debug_log "DEBUG" "Selected country: $(echo "$country_data" | awk '{print $2, $3}')"
        
        # 言語設定の正規化を実行
        normalize_language
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
        
        debug_log "DEBUG" "Timezone information written to cache"
        debug_log "DEBUG" "Selected timezone: $selected_timezone"
    else
        debug_log "ERROR" "No timezone data to write to cache"
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
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
