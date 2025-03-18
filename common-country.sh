#!/bin/sh

SCRIPT_VERSION="2025.03.14-01-01"

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
DEBUG_MODE="${DEBUG_MODE:-false}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# sed用にテキストをエスケープする関数
escape_for_sed() {
    local input="$1"
    # sedで特殊扱いされる文字をエスケープ
    printf '%s' "$input" | sed 's/[\/&.*[\]^$]/\\&/g'
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
            local zone_result=$?
            
            # ゾーン選択の結果を処理
            case $zone_result in
                0) # 正常終了
                    debug_log "DEBUG" "Timezone selection completed successfully"
                    return 0
                    ;;
                2) # 「戻る」が選択された
                    debug_log "DEBUG" "User requested to return to country selection from command argument"
                    # 次の処理へ（言語引数は無効にして再選択）
                    input_lang=""
                    # country_write関数の結果をクリア
                    rm -f "${CACHE_DIR}/country.ch" 2>/dev/null
                    rm -f "${CACHE_DIR}/language.ch" 2>/dev/null
                    rm -f "${CACHE_DIR}/zone.tmp" 2>/dev/null
                    # 続行して通常の国選択へ
                    ;;
                *) # エラーまたはキャンセル
                    debug_log "ERROR" "Timezone selection failed or cancelled"
                    return 1
                    ;;
            esac
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
            input_lang=$(normalize_input "$input_lang")
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
            local escaped_input=$(escape_for_sed "$input_lang")
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

                debug_log "DEBUG" "Country selected from single match: $country_name"
                
                # ゾーン選択を実行
                select_zone
                local zone_result=$?
                
                # ゾーン選択の結果を処理
                case $zone_result in
                    0) # 正常終了
                        debug_log "DEBUG" "Timezone selection completed successfully"
                        return 0
                        ;;
                    2) # 「戻る」が選択された
                        debug_log "DEBUG" "User requested to return to country selection from single match"
                        # 一時キャッシュをクリアして国選択からやり直し
                        rm -f "${CACHE_DIR}/country.ch" 2>/dev/null
                        rm -f "${CACHE_DIR}/language.ch" 2>/dev/null
                        rm -f "${CACHE_DIR}/zone.tmp" 2>/dev/null
                        input_lang=""
                        continue
                        ;;
                    *) # エラーまたはキャンセル
                        debug_log "ERROR" "Timezone selection failed or cancelled"
                        return 1
                        ;;
                esac
            else
                input_lang=""
                continue
            fi
        fi

        # 複数結果の場合、select_list関数を使用
        debug_log "DEBUG" "Multiple results found for '$input_lang'. Using select_list function."

        # 表示用リスト作成（国名のみ抽出）
        local display_list=$(echo "$full_results" | awk '{print $2, $3}')
        local number_file="${CACHE_DIR}/number_selection.tmp"
        
        # select_list関数を呼び出し
        select_list "$display_list" "$number_file" "country"
        local select_result=$?
        
        # 選択結果処理
        case $select_result in
            0) # 選択成功
                # 選択結果の取得
                if [ ! -f "$number_file" ]; then
                    debug_log "ERROR" "Country selection number file not found"
                    return 1
                fi
                
                local selected_number=$(cat "$number_file")
                debug_log "DEBUG" "User selected number: $selected_number"
                
                # 選択された行を取得
                local selected_full=$(echo "$full_results" | sed -n "${selected_number}p")
                local selected_country=$(echo "$selected_full" | awk '{print $2, $3}')
                
                debug_log "DEBUG" "Selected country: $selected_country"
                
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
                
                # ゾーン選択を実行
                select_zone
                local zone_result=$?
                
                # ゾーン選択の結果を処理
                case $zone_result in
                    0) # 正常終了
                        debug_log "DEBUG" "Timezone selection completed successfully"
                        return 0
                        ;;
                    2) # 「戻る」が選択された
                        debug_log "DEBUG" "User requested to return to country selection from multiple choices"
                        # 一時キャッシュをクリアして国選択からやり直し
                        rm -f "${CACHE_DIR}/country.ch" 2>/dev/null
                        rm -f "${CACHE_DIR}/language.ch" 2>/dev/null
                        rm -f "${CACHE_DIR}/zone.tmp" 2>/dev/null
                        input_lang=""
                        continue
                        ;;
                    *) # エラーまたはキャンセル
                        debug_log "ERROR" "Timezone selection failed or cancelled"
                        return 1
                        ;;
                esac
                ;;
                
            2) # 「戻る」が選択された（国選択でRボタンが押された場合）
                debug_log "DEBUG" "User requested to return from country selection list"
                input_lang=""
                continue
                ;;
                
            *) # キャンセルまたはエラー
                # 選択がキャンセルされた場合
                debug_log "DEBUG" "User cancelled country selection"
                input_lang=""
                continue
                ;;
        esac
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

    # dynamic-system-info.shを一度だけ読み込む
    . "$BASE_DIR/dynamic-system-info.sh"

    # 国情報の取得
    system_country=$(get_country_info)
    debug_log "DEBUG" "Detected country info: ${system_country}"

    # タイムゾーン情報の取得
    system_timezone=$(get_timezone_info)
    debug_log "DEBUG" "Detected timezone info: ${system_timezone}"

    # ゾーン名の取得
    system_zonename=$(get_zonename_info)
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
            
            # タイムゾーン文字列の構築
            local timezone_str=""
            if [ -n "$system_zonename" ] && [ -n "$system_timezone" ]; then
                # ゾーン名とタイムゾーン情報を組み合わせる
                timezone_str="${system_zonename},${system_timezone}"
                debug_log "DEBUG" "Created combined timezone string: ${timezone_str}"
            else
                # タイムゾーン情報のみ
                timezone_str="${system_timezone}"
                debug_log "DEBUG" "Using timezone string: ${timezone_str}"
            fi
            
            # zone_write関数に処理を委譲（直接引数として渡す）
            debug_log "DEBUG" "Calling zone_write() with timezone data"
            zone_write "$timezone_str" || {
                debug_log "ERROR" "Failed to write timezone data"
                return 1
            }
            
            # ゾーン選択完了メッセージを表示（ここで1回だけ）
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
            printf "\n"
            
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
    debug_log "DEBUG" "Running select_list() function with type=$3"
    
    local select_list="$1"
    local tmp_file="$2"
    local type="$3"
    
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
    debug_log "DEBUG" "Total items in list: $total_items"
    
    # 項目が1つしかない場合は自動選択
    if [ "$total_items" -eq 1 ]; then
        debug_log "DEBUG" "Only one item in list, auto-selecting"
        echo "1" > "$tmp_file"
        return 0
    fi
    
    # 項目をリスト表示
    local display_count=1
    echo "$select_list" | while IFS= read -r line; do
        printf " [%d]: %s\n" "$display_count" "$line"
        display_count=$((display_count + 1))
    done
    
    # ユーザーに選択を促す
    while true; do
        # メッセージの取得と表示
        local prompt_msg=$(get_message "$prompt_msg_key")
        printf "%s " "$(color cyan "$prompt_msg")"
        
        local number
        read -r number
        number=$(normalize_input "$number")
        debug_log "DEBUG" "User input: $number"
        
        # 数値チェック
        if ! echo "$number" | grep -q '^[0-9]\+$'; then
            local error_msg=$(get_message "$error_msg_key")
            printf "%s\n" "$(color red "$error_msg")"
            continue
        fi
        
        # 範囲チェック
        if [ "$number" -lt 1 ] || [ "$number" -gt "$total_items" ]; then
            local range_msg=$(get_message "MSG_NUMBER_OUT_OF_RANGE")
            # プレースホルダー置換（sedでエスケープ処理）
            range_msg=$(echo "$range_msg" | sed "s|{0}|1-$total_items|g")
            printf "%s\n" "$(color red "$range_msg")"
            continue
        fi
        
        # 選択項目を取得
        local selected_item=$(echo "$select_list" | sed -n "${number}p")
        debug_log "DEBUG" "Selected item: $selected_item"
        
        # 確認メッセージ表示
        local msg_selected=""
        case "$type" in
            country)
                msg_selected=$(get_message "MSG_SELECTED_COUNTRY")
                ;;
            zone)
                msg_selected=$(get_message "MSG_SELECTED_ZONE")
                ;;
            *)
                msg_selected=$(get_message "MSG_SELECTED_ITEM")
                ;;
        esac
        
        # プレースホルダー置換（エスケープ処理された選択項目）
        local safe_item=$(escape_for_sed "$selected_item")
        local msg_prefix=${msg_selected%%\{0\}*}
        local msg_suffix=${msg_selected#*\{0\}}
        printf "%s%s%s\n" "$(color blue "$msg_prefix")" "$(color blue "$safe_item")" "$(color blue "$msg_suffix")"
        
        confirm "MSG_CONFIRM_YNR"
        ret=$?
        case $ret in
            0) # Yes
            echo "$number" > "$tmp_file"
            debug_log "DEBUG" "Selection confirmed: $number ($selected_item)"
            return 0
            ;;
        2) # Return to previous step
            debug_log "DEBUG" "User requested to return to previous step"
            return 2
            ;;
        *) # No または他
            debug_log "DEBUG" "Selection cancelled"
            ;;
        esac
        
        # 確認がキャンセルされた場合は再選択
        debug_log "DEBUG" "User cancelled, prompting again"
    done
}

# タイムゾーンの選択を処理する関数
select_zone() {
    debug_log "DEBUG" "Running select_zone() function"
    
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
        
        # zone_write関数に処理を委譲（直接引数として渡す）
        zone_write "$selected" || {
            debug_log "ERROR" "Failed to write timezone data"
            return 1
        }
        
        # メッセージを表示（スキップフラグが設定されていない場合のみ）
        if [ "$skip_message" = "false" ]; then
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
            printf "\n"
        fi
        
        return 0
    fi

    # 複数のタイムゾーンがある場合は選択肢を表示
    printf "%s\n" "$(color blue "$(get_message "MSG_SELECT_TIMEZONE")")"
    
    # 番号付きリスト表示 - select_list関数を使用
    local number_file="${CACHE_DIR}/zone_selection.tmp"
    
    # select_list関数を呼び出す
    select_list "$zone_list" "$number_file" "zone"
    local select_result=$?
    
    # 戻り値に応じた処理
    case $select_result in
        0) # 選択成功
            # 選択結果の取得
            if [ ! -f "$number_file" ]; then
                debug_log "ERROR" "Zone selection number file not found"
                return 1
            fi
            
            local number=$(cat "$number_file")
            if [ -z "$number" ]; then
                debug_log "ERROR" "Empty zone selection number"
                return 1
            fi
            
            # 選択されたタイムゾーンの取得
            local selected=$(echo "$zone_list" | sed -n "${number}p")
            debug_log "DEBUG" "Selected timezone: $selected"
            
            # zone_write関数に処理を委譲（直接引数として渡す）
            zone_write "$selected" || {
                debug_log "ERROR" "Failed to write timezone data"
                return 1
            }
            
            # 成功メッセージを表示
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
            printf "\n"
            return 0
            ;;
            
        2) # 「戻る」が選択された
            debug_log "DEBUG" "User requested to return to previous step"
            return 2  # この戻り値2を上位関数で処理する
            ;;
            
        *) # キャンセルまたはエラー
            debug_log "DEBUG" "Zone selection cancelled or error occurred"
            return 1
            ;;
    esac
}

country_write() {
    local skip_message="${1:-false}"  # 成功メッセージをスキップするかのフラグ
    
    debug_log "DEBUG" "Entering country_write() with skip_message=$skip_message"
    
    # 一時ファイルのパス
    local tmp_country="${CACHE_DIR}/country.tmp"
    
    # 出力先ファイルのパス
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_language="${CACHE_DIR}/language.ch"
    local cache_luci="${CACHE_DIR}/luci.ch"
    
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
    
    # 言語設定をキャッシュに保存
    echo "$selected_lang_code" > "$cache_language"
    debug_log "DEBUG" "Language code written to cache"
    
    # LuCIインターフェース用言語コードを取得（4列目）
    local luci_code=$(awk '{print $4}' "$cache_country")
    debug_log "DEBUG" "LuCI interface language code: $luci_code"
    
    # LuCI言語コードをキャッシュに保存
    echo "$luci_code" > "$cache_luci"
    debug_log "DEBUG" "LuCI language code written to cache: $luci_code"
    
    # 成功メッセージを表示（スキップフラグが設定されていない場合のみ）
    if [ "$skip_message" = "false" ]; then
        printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"
    fi
    
    return 0
}

# 国コードから言語コードへのマッピング関数
map_country_code() {
    local country_code="$1"
    local db_dir="${BASE_DIR}"
    
    # デバッグ出力
    debug_log "DEBUG" "Processing country code: $country_code"
    
    # 各DBファイルを順に確認して言語マッピングを検索
    local db_files="messages_etc.db messages_euro.db messages_asian.db messages_base.db"
    
    for db_file in $db_files; do
        local full_path="${db_dir}/${db_file}"
        
        if [ -f "$full_path" ]; then
            # ファイル先頭の20行を取得
            local header=$(head -n 20 "$full_path")
            
            # サポート言語リストを取得
            local langs=$(echo "$header" | grep "SUPPORTED_LANGUAGES" | cut -d'"' -f2)
            
            # まず直接一致するか確認
            if echo " $langs " | grep -q " $country_code "; then
                debug_log "DEBUG" "Direct language match: $country_code in $db_file"
                echo "$country_code"
                return 0
            fi
            
            # マッピングを確認
            for lang in $langs; do
                local map_line=$(echo "$header" | grep "SUPPORTED_LANGUAGE_${lang}=" | head -1)
                
                if [ -n "$map_line" ]; then
                    local countries=$(echo "$map_line" | cut -d'"' -f2)
                    
                    if echo " $countries " | grep -q " $country_code "; then
                        debug_log "DEBUG" "Found mapping: $country_code -> $lang in $db_file"
                        echo "$lang"
                        return 0
                    fi
                fi
            done
        fi
    done
    
    # マッピングが見つからない場合は元の値を返す
    debug_log "DEBUG" "No mapping found for country code: $country_code, using as is"
    echo "$country_code"
    return 0
}

normalize_language() {
    # 必要なパス定義
    local base_db="${BASE_DIR}/messages_base.db"
    local asian_db="${BASE_DIR}/messages_asian.db"
    local euro_db="${BASE_DIR}/messages_euro.db"
    local etc_db="${BASE_DIR}/messages_etc.db" 
    local language_cache="${CACHE_DIR}/language.ch"
    local message_cache="${CACHE_DIR}/message.ch"
    local message_db_ch="${CACHE_DIR}/message_db.ch"
    local country_code=""
    local selected_language=""
    
    # デバッグログの出力
    debug_log "DEBUG" "Normalizing language settings"
    debug_log "DEBUG" "language_cache=${language_cache}"
    debug_log "DEBUG" "message_cache=${message_cache}"
    
    # language.chファイルの存在確認
    if [ ! -f "$language_cache" ]; then
        debug_log "DEBUG" "language.ch not found. Cannot determine language."
        return 1
    fi

    # language.chから国コードを読み込み
    country_code=$(cat "$language_cache")
    debug_log "DEBUG" "Original country code: ${country_code}"
    
    # 国コードから言語コードへのマッピング処理
    selected_language=$(map_country_code "$country_code")
    debug_log "DEBUG" "Mapped language code: ${selected_language}"

    # 対応するDBファイルを検索
    local target_db=""
    local found=0
    
    # 各DBファイルをチェック
    for db_file in "$etc_db" "$euro_db" "$asian_db" "$base_db"; do
        if [ -f "$db_file" ]; then
            # DBファイルからSUPPORTED_LANGUAGESを抽出
            local supported_langs=$(grep "^SUPPORTED_LANGUAGES=" "$db_file" | cut -d'=' -f2 | tr -d '"')
            debug_log "DEBUG" "Checking DB ${db_file} for language ${selected_language}"
            debug_log "DEBUG" "Supported languages: ${supported_langs}"
            
            # 指定言語がサポートされているか確認
            if echo " $supported_langs " | grep -q " $selected_language "; then
                target_db="$db_file"
                found=1
                debug_log "DEBUG" "Found matching DB: ${target_db}"
                break
            fi
        fi
    done

    # DBが見つからなかった場合はデフォルトを使用
    if [ $found -eq 0 ]; then
        if [ -f "$base_db" ]; then
            target_db="$base_db"
            debug_log "DEBUG" "Language not found in any DB, using base_db"
        else
            debug_log "ERROR" "No valid message DB found"
            return 1
        fi
    fi
    
    # 設定を保存（許可されたファイルのみ - message.chとmessage_db.ch）
    echo "$selected_language" > "$message_cache"
    echo "$target_db" > "$message_db_ch"  # ここで.chファイルに書き込む
    debug_log "DEBUG" "Updated message_cache=${selected_language}"
    debug_log "DEBUG" "Updated message_db_ch with target DB path"
    
    ACTIVE_LANGUAGE="$selected_language"
    
    # 言語セットのメッセージを表示
    printf "%s\n" "$(color green "$(get_message "MSG_LANGUAGE_SET")")"
    return 0
}

# タイムゾーン情報をキャッシュに書き込む関数
zone_write() {
    debug_log "DEBUG" "Entering zone_write()"
    
    # 引数またはファイルからタイムゾーン情報を取得
    local timezone_str=""
    local tmp_zone="${CACHE_DIR}/zone.tmp"
    
    if [ -n "$1" ]; then
        # 引数が提供された場合、それを使用
        timezone_str="$1"
        debug_log "DEBUG" "Using timezone string from argument: ${timezone_str}"
    elif [ -f "$tmp_zone" ]; then
        # 一時ファイルから読み込み
        timezone_str=$(cat "$tmp_zone")
        debug_log "DEBUG" "Reading timezone from temporary file: ${timezone_str}"
    else
        # 両方とも利用できない場合はエラー
        debug_log "ERROR" "No timezone data provided and no temporary file found"
        local safe_filename=$(escape_for_sed "$tmp_zone")
        local err_msg=$(get_message "ERR_FILE_NOT_FOUND")
        err_msg=$(echo "$err_msg" | sed "s/{file}/$safe_filename/g")
        printf "%s\n" "$(color red "$err_msg")"
        return 1
    fi
    
    # タイムゾーン情報を分割して保存
    if [ -n "$timezone_str" ]; then
        local zonename=""
        local timezone=""
        
        if echo "$timezone_str" | grep -q ","; then
            # カンマで区切られている場合は分割
            zonename=$(echo "$timezone_str" | cut -d ',' -f 1)
            timezone=$(echo "$timezone_str" | cut -d ',' -f 2)
            debug_log "DEBUG" "Parsed comma-separated timezone: zonename=$zonename, timezone=$timezone"
        else
            # カンマがない場合はそのまま使用
            zonename="$timezone_str"
            timezone="GMT0"
            debug_log "DEBUG" "Using simple timezone format: zonename=$zonename, timezone=$timezone"
        fi
        
        # キャッシュに書き込み
        echo "$zonename" > "${CACHE_DIR}/zonename.ch"
        echo "$timezone" > "${CACHE_DIR}/timezone.ch"
        echo "$timezone_str" > "${CACHE_DIR}/zone.ch"
        
        debug_log "DEBUG" "Timezone information written to cache successfully"
        return 0
    else
        debug_log "ERROR" "Empty timezone string provided"
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_OCCURRED")")"
        return 1
    fi
}

# スクリプト情報表示（デバッグモード有効時）
if [ "$DEBUG_MODE" = "true" ]; then
    debug_log "DEBUG" "common-country.sh loaded with BASE_DIR=$BASE_DIR"
    if type get_device_architecture >/dev/null 2>&1; then
        debug_log "DEBUG" "dynamic-system-info.sh loaded successfully"
    else
        debug_log "DEBUG" "dynamic-system-info.sh not loaded or functions not available"
    fi
    
    # セキュリティとコード改善に関するデバッグメッセージ
    debug_log "DEBUG" "Added escape_for_sed function to safely handle special characters in user inputs"
    debug_log "DEBUG" "Enhanced zone_write function to centralize timezone data processing"
    debug_log "DEBUG" "Improved code efficiency by reducing duplicate timezone parsing logic"
fi
