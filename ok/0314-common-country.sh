#!/bin/sh

SCRIPT_VERSION="2025.03.14-00-01"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-14
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

# ディレクトリ作成（エラーハンドリング追加）
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BUILD_DIR" || {
    echo "Error: Failed to create required directories" >&2
    exit 1
}

DEBUG_MODE="${DEBUG_MODE:-false}"

#########################################################################
# Last Update: 2025-03-14 01:24:18 (UTC) 🚀
# "Ensuring consistent input handling and text normalization."
#
# 【要件】
# 1. **入力テキストを正規化（Normalize Input）**
#    - 全角数字を半角数字に変換
#    - 将来的には他の文字種も対応予定
#
# 2. **適用対象**
#    - **`select_country()`**: **Y/N 確認時のみ適用**
#    - **`select_list()`**: **番号選択 & Y/N 確認時のみ適用**
#    - **`download()`**: **ファイル名の正規化**
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

    # 1. 引数で短縮国名（JP、USなど）が指定されている場合（最優先）
    if [ -n "$input_lang" ]; then
        debug_log "DEBUG" "Language argument provided: $input_lang"
        
        # 短縮国名（$5）と完全一致するエントリを検索
        local lang_match=$(awk -v lang="$input_lang" '$5 == lang {print $0; exit}' "$BASE_DIR/country.db")
        
        if [ -n "$lang_match" ]; then
            debug_log "DEBUG" "Exact language code match found: $lang_match"
            
            # 一時ファイルに書き込み
            echo "$lang_match" > "${CACHE_DIR}/country.tmp"
            
            # country_write関数に処理を委譲（成功メッセージをスキップ）
            country_write true || {
                debug_log "ERROR" "Failed to write country data from language argument"
                return 1
            }
            
            # 言語を正規化（メッセージキャッシュを作成）
            normalize_language
            
            # 言語に対応するタイムゾーン情報を取得
            echo "$(echo "$lang_match" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone.tmp"
            
            # zone_write関数に処理を委譲
            zone_write || {
                debug_log "ERROR" "Failed to write timezone data from language argument"
                return 1
            }
            
            debug_log "DEBUG" "Language selected via command argument: $input_lang"
            # ここで1回だけ成功メッセージを表示
            printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"
            
            # 選択されたタイムゾーンのゾーン情報からゾーンを選択
            select_zone
            return 0
        else
            debug_log "DEBUG" "No exact language code match for: $input_lang, proceeding to next selection method"
            # 引数一致しない場合は次へ進む（メッセージ表示なし）
            input_lang=""  # 引数をクリア
        fi
    fi

    # 2. キャッシュがあれば全ての選択プロセスをスキップ
    if [ -f "$cache_country" ] && [ -f "$cache_zone" ]; then
        debug_log "DEBUG" "Country and Timezone cache exist. Skipping selection process."
        return 0
    fi

    # 3. 自動選択を試行（一度だけ検出処理を行う）
    if detect_and_set_location; then
        # 正常に設定された場合はここで終了
        return 0
    fi

    # 4. 自動検出が失敗または拒否された場合、手動入力へ
    debug_log "DEBUG" "Automatic location detection failed or was declined. Proceeding to manual input."

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
            debug_log "DEBUG" "Empty search keyword"
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
                echo "$full_results" > "${CACHE_DIR}/country.tmp"

                # country_write関数に処理を委譲
                country_write || {
                    debug_log "ERROR" "Failed to write country data"
                    return 1
                }

                # 言語を正規化
                normalize_language
                
                # zone_write関数に処理を委譲
                echo "$(echo "$full_results" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone.tmp"
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

        # 複数結果の場合、select_list関数を使用（将来実装）
        debug_log "DEBUG" "Multiple results found for '$input_lang'. Displaying selection list."

        # 表示用リスト作成（現在の実装）
        echo "$full_results" | awk '{print NR, ":", $2, $3}'

        # 番号入力要求
        local msg_select=$(get_message "MSG_SELECT_COUNTRY_NUMBER")
        printf "%s " "$(color cyan "$msg_select")"

        local number
        read -r number
        number=$(normalize_input "$number")
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
                    echo "$selected_full" > "${CACHE_DIR}/country.tmp"

                    # country_write関数に処理を委譲
                    country_write || {
                        debug_log "ERROR" "Failed to write country data"
                        return 1
                    }

                    # 言語を正規化
                    normalize_language
                    
                    # zone_write関数に処理を委譲
                    echo "$(echo "$selected_full" | cut -d ' ' -f 6-)" > "${CACHE_DIR}/zone.tmp"
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

        # 検索プロンプトを表示
        input_lang=""
        debug_log "DEBUG" "Resetting search and showing prompt again"
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
    if [ ! -f "$BASE_DIR/dynamic-system-info.sh" ]; then
        debug_log "DEBUG" "dynamic-system-info.sh not found. Cannot detect location."
        return 1
    fi
    
    # 国情報の取得
    system_country=$(. "$BASE_DIR/dynamic-system-info.sh" && get_country_info)
    debug_log "DEBUG" "Detected country info: ${system_country}"
    
    # タイムゾーン情報の取得
    system_timezone=$(. "$BASE_DIR/dynamic-system-info.sh" && get_timezone_info)
    debug_log "DEBUG" "Detected timezone info: ${system_timezone}"
    
    # ゾーン名の取得
    system_zonename=$(. "$BASE_DIR/dynamic-system-info.sh" && get_zonename_info)
    debug_log "DEBUG" "Detected zone name info: ${system_zonename}"
    
    # 検出できなければ通常フローへ
    if [ -z "$system_country" ] || [ -z "$system_timezone" ]; then
        debug_log "DEBUG" "Could not detect system country or timezone"
        return 1
    fi
    
    # 検出情報表示
    printf "%s\n" "$(color yellow "$(get_message "MSG_USE_DETECTED_SETTINGS")")"
    printf "%s %s\n" "$(color blue "$(get_message "MSG_DETECTED_COUNTRY")")" "$(color blue "$(echo "$system_country" | cut -d' ' -f2)")"
    
    # ゾーン名があればゾーン名とタイムゾーン、なければタイムゾーンのみ表示
    if [ -n "$system_zonename" ]; then
        printf "%s %s$(color blue ",")%s\n\n" "$(color blue "$(get_message "MSG_DETECTED_ZONE")")" "$(color blue "$system_zonename")" "$(color blue "$system_timezone")"
    else
        printf "%s %s\n\n" "$(color blue "$(get_message "MSG_DETECTED_ZONE")")" "$(color blue "$system_timezone")"
    fi
    
    # 確認
    if confirm "MSG_CONFIRM_ONLY_YN"; then
        # country.dbから完全な国情報を検索
        local country_data=$(grep -i "^[^ ]* *$system_country" "$BASE_DIR/country.db")
        debug_log "DEBUG" "Found country data: ${country_data}"
        
        if [ -n "$country_data" ]; then
            # 国情報を一時ファイルに書き込み
            debug_log "DEBUG" "Writing country data to temporary file"
            echo "$country_data" > "${CACHE_DIR}/country.tmp"
            
            # country_write関数に処理を委譲（メッセージ表示スキップ）
            debug_log "DEBUG" "Calling country_write()"
            country_write true || {
                debug_log "ERROR" "Failed to write country data"
                return 1
            }
            
            # 言語を正規化
            normalize_language
            
            # 国選択完了メッセージを表示（ここで1回だけ）
            printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"
            
            # ゾーン情報を一時ファイルに書き込み
            if [ -n "$system_zonename" ] && [ -n "$system_timezone" ]; then
                # ゾーン名とタイムゾーン情報を組み合わせて一時ファイルに書き込む
                debug_log "DEBUG" "Writing combined zone info to temporary file: ${system_zonename},${system_timezone}"
                echo "${system_zonename},${system_timezone}" > "${CACHE_DIR}/zone.tmp"
            else
                # タイムゾーン情報のみを一時ファイルに書き込む
                debug_log "DEBUG" "Writing timezone only to temporary file: ${system_timezone}"
                echo "${system_timezone}" > "${CACHE_DIR}/zone.tmp"
            fi
            
            # zone_write関数に処理を委譲
            debug_log "DEBUG" "Calling zone_write()"
            zone_write || {
                debug_log "ERROR" "Failed to write timezone data"
                return 1
            }
            
            # ゾーン選択完了メッセージを表示（ここで1回だけ）
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
            
            debug_log "DEBUG" "Auto-detected settings have been applied successfully"
            return 0
        else
            debug_log "DEBUG" "No matching entry found for detected country: $system_country"
            return 1
        fi
    else
        debug_log "DEBUG" "User declined auto-detected settings"
        return 1
    fi
}

# 番号付きリストからユーザーに選択させる関数
# $1: 表示するリストデータ
# $2: 結果を保存する一時ファイル
# $3: タイプ（country/zone）
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
    local skip_message="${1:-false}"
    
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
    
    # タイムゾーン数を数える
    local zone_count=$(echo "$zone_list" | wc -l)
    debug_log "DEBUG" "Found $zone_count timezone(s) for selected country"
    
    # タイムゾーンが1つだけの場合は自動選択
    if [ "$zone_count" -eq 1 ]; then
        local selected=$(echo "$zone_list")
        debug_log "DEBUG" "Only one timezone available: $selected - auto selecting"
        
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
        
        # キャッシュに直接書き込み
        echo "$zonename" > "$cache_zonename"
        echo "$timezone" > "$cache_timezone"
        echo "$selected" > "$cache_zone"
        
        # メッセージを表示（スキップフラグが設定されていない場合のみ）
        if [ "$skip_message" = "false" ]; then
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
        fi
        
        return 0
    fi
    
    # 複数のタイムゾーンがある場合は選択肢を表示
    printf "%s\n" "$(color blue "$(get_message "MSG_SELECT_TIMEZONE")")"
    
    # 番号付きリスト表示 - select_list関数を使用
    local number_file="${CACHE_DIR}/selection_number.tmp"
    
    # select_list関数を呼び出す（今後の実装）
    # select_list "$zone_list" "$number_file" "zone"
    
    # 今回は従来のロジックを使用（互換性のため）
    local count=1
    echo "$zone_list" | while IFS= read -r line; do
        [ -n "$line" ] && printf "%3d: %s\n" "$count" "$line"
        count=$((count + 1))
    done
    
    # 番号入力受付
    local number=""
    while true; do
        printf "%s " "$(color cyan "$(get_message "MSG_ENTER_NUMBER")")"
        read -r number
        number=$(normalize_input "$number")
        debug_log "DEBUG" "User input: $number"
        
        # 入力検証 - 空白またはゼロは許可しない
        if [ -z "$number" ]; then
            printf "%s\n" "$(color red "$(get_message "MSG_EMPTY_INPUT")")"
            continue
        fi
        
        # 数字かどうか確認
        if ! echo "$number" | grep -q '^[0-9]\+$'; then
            printf "%s\n" "$(color red "$(get_message "MSG_INVALID_NUMBER")")"
            continue
        fi
        
        # 選択範囲内かどうか確認
        if [ "$number" -lt 1 ] || [ "$number" -gt "$zone_count" ]; then
            printf "%s\n" "$(color red "$(get_message "MSG_NUMBER_OUT_OF_RANGE")")"
            continue
        fi
        
        # ここまで来れば有効な入力
        break
    done
    
    # 選択されたタイムゾーンの取得
    local selected=$(echo "$zone_list" | sed -n "${number}p")
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
    printf "%s %s\n" "$(color blue "$(get_message "MSG_CONFIRM_TIMEZONE")")" "$(color blue "$selected")"
    
    if confirm "MSG_CONFIRM_ONLY_YN"; then
        echo "$timezone" > "$cache_timezone"
        echo "$selected" > "$cache_zone"
        printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
        return 0
    fi
    
    # 再選択
    select_zone
    return $?
}

# 国情報をキャッシュに書き込む関数
country_write() {
    local skip_message="${1:-false}"  # 成功メッセージをスキップするかのフラグ
    
    debug_log "DEBUG" "Entering country_write() with skip_message=$skip_message"
    
    # 一時ファイルのパス
    local tmp_country="${CACHE_DIR}/country.tmp"
    
    # 出力先ファイルのパス
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_language="${CACHE_DIR}/language.ch"
    
    # 一時ファイルが存在するか確認
    if [ ! -f "$tmp_country" ]; then
        local err_msg=$(get_message "ERR_FILE_NOT_FOUND")
        local err_msg_final=$(echo "$err_msg" | sed "s/{file}/$tmp_country/g")
        printf "%s\n" "$(color red "$err_msg_final")"
        return 1
    fi
    
    # 一時ファイルから国情報をキャッシュに保存
    cat "$tmp_country" > "$cache_country"
    debug_log "DEBUG" "Country information written to cache"
    
    # 選択された国と言語情報を抽出
    local selected_country=$(awk '{print $2, $3}' "$cache_country")
    debug_log "DEBUG" "Selected country: $selected_country"
    
    # 選択された国の言語コードを取得（5列目）
    local selected_lang_code=$(awk '{print $5}' "$cache_country")
    debug_log "DEBUG" "Selected language code: $selected_lang_code"
    
    # 言語設定をキャッシュに保存（message.chはnormalize_languageで生成）
    echo "$selected_lang_code" > "$cache_language"
    debug_log "DEBUG" "Language code written to cache"
    
    # 成功メッセージを表示（スキップフラグが設定されていない場合のみ）
    if [ "$skip_message" = "false" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"
    fi
    
    return 0
}

# 言語設定を正規化する関数
normalize_language() {
    # 必要なパス定義
    local message_db="${BASE_DIR}/messages.db"
    local language_cache="${CACHE_DIR}/language.ch"
    local message_cache="${CACHE_DIR}/message.ch"
    local selected_language=""

    # デバッグログの出力
    debug_log "DEBUG" "Normalizing language settings"
    debug_log "DEBUG" "message_db=${message_db}"
    debug_log "DEBUG" "language_cache=${language_cache}"
    debug_log "DEBUG" "message_cache=${message_cache}"

    # メッセージキャッシュが既に存在するか確認
    if [ -f "$message_cache" ]; then
        debug_log "DEBUG" "message.ch already exists. Using existing language settings."
        return 0
    fi

    # language.chファイルの存在確認
    if [ ! -f "$language_cache" ]; then
        debug_log "DEBUG" "language.ch not found. Cannot determine language."
        return 1
    fi

    # language.chから直接言語コードを読み込み
    selected_language=$(cat "$language_cache")
    debug_log "DEBUG" "Selected language code: ${selected_language}"

    # サポート言語の取得方法を統一（より正確なパターンマッチング）
    local supported_languages=""
    if [ -f "$message_db" ]; then
        # パターン：JP|MSG_KEY=value または US|MSG_KEY=value
        supported_languages=$(grep -o "^[A-Z][A-Z]|" "$message_db" | sort -u | tr -d "|" | tr '\n' ' ')
        debug_log "DEBUG" "Available supported languages: ${supported_languages}"
    else
        supported_languages="US"  # デフォルト言語
        debug_log "DEBUG" "Message DB not found, defaulting to US only"
    fi

    # 選択された言語がサポートされているか確認（grep使用に変更）
    if echo " $supported_languages " | grep -q " $selected_language "; then
        debug_log "DEBUG" "Language ${selected_language} is supported"
        echo "$selected_language" > "$message_cache"
        ACTIVE_LANGUAGE="$selected_language"
    else
        debug_log "DEBUG" "Language ${selected_language} not supported, falling back to US"
        echo "US" > "$message_cache"
        ACTIVE_LANGUAGE="US"
    fi

    debug_log "DEBUG" "Final active language: ${ACTIVE_LANGUAGE}"
    # 言語セットのメッセージ（country_writeとは別メッセージ）
    printf "%s\n" "$(color green "$(get_message "MSG_LANGUAGE_SET")")"
    return 0
}

# タイムゾーン情報をキャッシュに書き込む関数
zone_write() {
    debug_log "DEBUG" "Entering zone_write()"
    
    local tmp_zone="${CACHE_DIR}/zone.tmp"
    
    # 一時ファイルが存在するか確認
    if [ ! -f "$tmp_zone" ]; then
        debug_log "ERROR" "File not found: $tmp_zone"
        # sedのデリミタを#に変更
        printf "%s\n" "$(color red "$(get_message "ERR_FILE_NOT_FOUND" | sed "s#{file}#$tmp_zone#g")")"
        return 1
    fi
    
    # タイムゾーン情報を取得
    local selected_timezone=$(cat "$tmp_zone")
    debug_log "DEBUG" "Processing timezone from file: ${selected_timezone}"
    
    # タイムゾーン情報を分割して保存
    if [ -n "$selected_timezone" ]; then
        local zonename=""
        local timezone=""
        
        if echo "$selected_timezone" | grep -q ","; then
            # カンマで区切られている場合は分割
            zonename=$(echo "$selected_timezone" | cut -d ',' -f 1)
            timezone=$(echo "$selected_timezone" | cut -d ',' -f 2)
        else
            # カンマがない場合はそのまま使用
            zonename="$selected_timezone"
            timezone="$selected_timezone"
        fi
        
        # キャッシュに書き込み
        echo "$zonename" > "${CACHE_DIR}/zonename.ch"
        echo "$timezone" > "${CACHE_DIR}/timezone.ch"
        echo "$selected_timezone" > "${CACHE_DIR}/zone.ch"
        
        debug_log "DEBUG" "Timezone information written to cache"
        debug_log "DEBUG" "Selected zonename: $zonename, timezone: $timezone"
    else
        debug_log "ERROR" "No timezone data to write to cache"
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
        return 1
    fi
    
    return 0
}

# スクリプト情報表示（デバッグモード有効時）
if [ "$DEBUG_MODE" = "true" ]; then
    debug_log "DEBUG" "common-country.sh loaded with BASE_DIR=$BASE_DIR"
    if type get_device_architecture >/dev/null 2>&1; then
        debug_log "DEBUG" "dynamic-system-info.sh loaded successfully"
    else
        debug_log "DEBUG" "dynamic-system-info.sh not loaded or functions not available"
    fi
fi
