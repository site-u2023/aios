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

# normalize_input 関数 - デバッグ出力を標準エラー出力に分離
normalize_input() {
    local input="$1"
    local output="$input"
    
    # デバッグメッセージを標準エラー出力へリダイレクト
    [ "$DEBUG_MODE" = "true" ] && printf "DEBUG: Starting character normalization for input text\n" >&2
    
    # 変換テーブル（各行はsedコマンドの負荷を分散するため分割）
    
    # 数字（0-9）: 日本語、中国語（簡体字・繁体字）、韓国語で共通
    output=$(echo "$output" | sed 's/０/0/g; s/１/1/g; s/２/2/g; s/３/3/g; s/４/4/g')
    output=$(echo "$output" | sed 's/５/5/g; s/６/6/g; s/７/7/g; s/８/8/g; s/９/9/g')
    
    # アルファベット大文字（A-Z）: 各国共通の全角英字
    output=$(echo "$output" | sed 's/Ａ/A/g; s/Ｂ/B/g; s/Ｃ/C/g; s/Ｄ/D/g; s/Ｅ/E/g')
    output=$(echo "$output" | sed 's/Ｆ/F/g; s/Ｇ/G/g; s/Ｈ/H/g; s/Ｉ/I/g; s/Ｊ/J/g')
    output=$(echo "$output" | sed 's/Ｋ/K/g; s/Ｌ/L/g; s/Ｍ/M/g; s/Ｎ/N/g; s/Ｏ/O/g')
    output=$(echo "$output" | sed 's/Ｐ/P/g; s/Ｑ/Q/g; s/Ｒ/R/g; s/Ｓ/S/g; s/Ｔ/T/g')
    output=$(echo "$output" | sed 's/Ｕ/U/g; s/Ｖ/V/g; s/Ｗ/W/g; s/Ｘ/X/g; s/Ｙ/Y/g; s/Ｚ/Z/g')
    
    # アルファベット小文字（a-z）: 各国共通の全角英字
    output=$(echo "$output" | sed 's/ａ/a/g; s/ｂ/b/g; s/ｃ/c/g; s/ｄ/d/g; s/ｅ/e/g')
    output=$(echo "$output" | sed 's/ｆ/f/g; s/ｇ/g/g; s/ｈ/h/g; s/ｉ/i/g; s/ｊ/j/g')
    output=$(echo "$output" | sed 's/ｋ/k/g; s/ｌ/l/g; s/ｍ/m/g; s/ｎ/n/g; s/ｏ/o/g')
    output=$(echo "$output" | sed 's/ｐ/p/g; s/ｑ/q/g; s/ｒ/r/g; s/ｓ/s/g; s/ｔ/t/g')
    output=$(echo "$output" | sed 's/ｕ/u/g; s/ｖ/v/g; s/ｗ/w/g; s/ｘ/x/g; s/ｙ/y/g; s/ｚ/z/g')
    
    # 主要な記号（日本語、中国語、韓国語で共通使用される記号）
    output=$(echo "$output" | sed 's/　/ /g')  # 全角スペース
    output=$(echo "$output" | sed 's/！/!/g; s/＂/"/g; s/＃/#/g; s/＄/$/g; s/％/%/g')
    output=$(echo "$output" | sed 's/＆/\&/g; s/＇/'\''/g; s/（/(/g; s/）/)/g; s/＊/*/g')
    output=$(echo "$output" | sed 's/＋/+/g; s/，/,/g; s/－/-/g; s/．/./g; s/／/\//g')
    
    # 主要な記号（続き）
    output=$(echo "$output" | sed 's/：/:/g; s/；/;/g; s/＜/</g; s/＝/=/g; s/＞/>/g')
    output=$(echo "$output" | sed 's/？/?/g; s/＠/@/g; s/［/[/g; s/＼/\\/g; s/］/]/g')
    output=$(echo "$output" | sed 's/＾/^/g; s/＿/_/g; s/｀/`/g; s/｛/{/g; s/｜/|/g')
    output=$(echo "$output" | sed 's/｝/}/g; s/～/~/g')
    
    # 韓国語特有の全角記号
    output=$(echo "$output" | sed 's/￦/\\/g; s/￥/\\/g')
    
    # デバッグメッセージを標準エラー出力へリダイレクト
    [ "$DEBUG_MODE" = "true" ] && printf "DEBUG: Character normalization completed\n" >&2
    
    # 正規化した結果のみを返す（デバッグ情報なし）
    printf '%s' "$output"
}

# 確認入力処理関数
confirm() {
    local msg_key="${1:-MSG_CONFIRM_DEFAULT}"  # デフォルトのメッセージキー
    local param_name="$2"    # パラメータ名（置換用）
    local param_value="$3"   # パラメータ値（置換用）
    local direct_msg="$4"    # 直接メッセージ
    local input_type="${5:-yn}"  # 入力タイプ: yn (デフォルト) または ynr
    local msg=""
    local yn=""
    
    # メッセージの取得
    if [ -n "$msg_key" ]; then
        msg=$(get_message "$msg_key")
        if [ -n "$param_name" ] && [ -n "$param_value" ]; then
            local safe_value=$(echo "$param_value" | sed 's/[\/&]/\\&/g')
            msg=$(echo "$msg" | sed "s|{$param_name}|$safe_value|g")
        fi
    else
        msg="$direct_msg"
        debug_log "DEBUG" "Using direct message instead of message key"
    fi
    
    # 入力タイプに基づき適切な表示形式に置き換え
    if [ "$input_type" = "ynr" ]; then
        msg=$(echo "$msg" | sed 's/{type}/(y\/n\/r)/g' | sed 's/{yn}/(y\/n)/g' | sed 's/{ynr}/(y\/n\/r)/g')
        debug_log "DEBUG" "Running in YNR mode with message: $msg_key" 
    else
        msg=$(echo "$msg" | sed 's/{type}/(y\/n)/g' | sed 's/{yn}/(y\/n)/g' | sed 's/{ynr}/(y\/n\/r)/g')
        debug_log "DEBUG" "Running in YN mode with message: $msg_key"
    fi
    
    # ユーザー入力ループ
    while true; do
        # プロンプト表示
        printf "%s " "$(color white "$msg")"
        
        # 入力を読み取り
        if ! read -r yn; then
            debug_log "ERROR" "Failed to read user input"
            return 1
        fi
        
        # 入力の正規化
        yn=$(normalize_input "$yn")
        debug_log "DEBUG" "Processing user input: $yn"
        
        # 入力検証
        case "$yn" in
            [Yy]|[Yy][Ee][Ss]|はい|ハイ|ﾊｲ) 
                debug_log "DEBUG" "User confirmed: Yes"
                CONFIRM_RESULT="Y"
                return 0 
                ;;
            [Nn]|[Nn][Oo]|いいえ|イイエ|ｲｲｴ)
                debug_log "DEBUG" "User confirmed: No"
                CONFIRM_RESULT="N"
                return 1 
                ;;
            [Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]|戻る|モドル|ﾓﾄﾞﾙ)
                # YNRモードの場合のみRを許可
                if [ "$input_type" = "ynr" ]; then
                    debug_log "DEBUG" "User selected: Return option"
                    CONFIRM_RESULT="R"
                    return 2
                fi
                # YNモードではRを無効として処理（エラーとして処理）
                debug_log "DEBUG" "Return option not allowed in YN mode"
                # エラーメッセージを表示して次のループへ
                show_invalid_input_error "$input_type"
                continue
                ;;
            *)
                # エラーメッセージ表示（行間詰め）
                show_invalid_input_error "$input_type"
                debug_log "DEBUG" "Invalid input detected for $input_type mode"
                ;;
        esac
    done
}

# 無効な入力に対するエラーメッセージを表示する関数
show_invalid_input_error() {
    local input_type="$1"
    local error_msg=$(get_message "MSG_INVALID_INPUT")
    if [ "$input_type" = "ynr" ]; then
        # YNRモード用の置換
        error_msg=$(echo "$error_msg" | sed 's/{type}/(y\/n\/r)/g')
    else
        # YNモード用の置換
        error_msg=$(echo "$error_msg" | sed 's/{type}/(y\/n)/g')
    fi
    printf "%s\n" "$(color red "$error_msg")"
}

# 番号選択関数
select_list() {
    local select_list="$1"
    local tmp_file="$2"
    local type="$3"
    
    debug_log "DEBUG" "Running select_list() with type=$type"
    
    # メッセージキー設定
    local prompt_msg_key=""
    case "$type" in
        country) prompt_msg_key="MSG_SELECT_COUNTRY_NUMBER" ;;
        zone)    prompt_msg_key="MSG_SELECT_ZONE_NUMBER" ;;
        *)       prompt_msg_key="MSG_SELECT_NUMBER" ;;
    esac
    
    # リストの行数を計算
    local total_items=$(echo "$select_list" | wc -l)
    debug_log "DEBUG" "Total items in list: $total_items"
    
    # 項目が1つだけなら自動選択
    if [ "$total_items" -eq 1 ]; then
        debug_log "DEBUG" "Only one item available, auto-selecting"
        echo "1" > "$tmp_file"
        return 0
    fi
    
    # 選択肢を表示
    local display_count=1
    echo "$select_list" | while IFS= read -r line; do
        printf "[%d] %s\n" "$display_count" "$line"
        display_count=$((display_count + 1))
    done
    
    # 選択ループ
    local prompt_msg=$(get_message "$prompt_msg_key")
    
    while true; do
        # プロンプト表示
        printf "%s " "$(color white "$prompt_msg")"
        
        # 入力読み取り
        read -r number
        number=$(normalize_input "$number")
        debug_log "DEBUG" "User entered: $number"
        
        # 数値チェック
        if ! echo "$number" | grep -q '^[0-9]\+$'; then
            # エラーの前は行間詰め
            printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_NOT_NUMBER")")"
            debug_log "DEBUG" "Invalid input: not a number"
            continue
        fi
        
        # 範囲チェック
        if [ "$number" -lt 1 ] || [ "$number" -gt "$total_items" ]; then
            # エラーの前は行間詰め
            printf "%s\n" "$(color red "$(get_message "MSG_NUMBER_OUT_OF_RANGE")")"
            debug_log "DEBUG" "Invalid input: number out of range (1-$total_items)"
            continue
        fi
        
        # 選択項目を取得
        local selected_item=$(echo "$select_list" | sed -n "${number}p")
        debug_log "DEBUG" "Selected item: $selected_item"
        
        # 確認メッセージを表示
        local msg_selected=""
        case "$type" in
            country) msg_selected=$(get_message "MSG_SELECTED_COUNTRY") ;;
            zone)    msg_selected=$(get_message "MSG_SELECTED_ZONE") ;;
            *)       msg_selected=$(get_message "MSG_SELECTED_ITEM") ;;
        esac
        
        # プレースホルダー置換
        local safe_item=$(escape_for_sed "$selected_item")
        msg_selected=$(echo "$msg_selected" | sed "s|{item}|$safe_item|g")
        printf "%s\n" "$(color white "$msg_selected")"
        
        # 確認（YNRモードで）
        confirm "MSG_CONFIRM_SELECT" "" "" "" "ynr"
        local ret=$?
        
        case $ret in
            0)  # Yes
                debug_log "DEBUG" "Selection confirmed for item #$number"
                echo "$number" > "$tmp_file"
                return 0
                ;;
            2)  # Return
                debug_log "DEBUG" "User requested to return to selection"
                return 2
                ;;
            *)  # No - 再選択
                debug_log "DEBUG" "Selection cancelled, prompting again"
                ;;
        esac
    done
}

# sed用にテキストをエスケープする関数
escape_for_sed() {
    local input="$1"
    # sedで特殊扱いされる文字をエスケープ
    printf '%s' "$input" | sed 's/[\/&.*[\]^$]/\\&/g'
}

# ユーザーに国の選択を促す関数
select_country() {
    debug_log "DEBUG" "Running select_country() function with arg='$1'"

    # 引数として渡された言語コード
    local input_lang="$1"

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
            # country_write関数に処理を委譲（メッセージ表示あり）
            country_write false || {
                debug_log "ERROR" "Failed to write country data from language argument"
                return 1
            }
            
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

    # 2. 自動検出処理を実行（キャッシュチェックも内部で行われる）
    detect_and_set_location
    if [ $? -eq 0 ]; then
        debug_log "DEBUG" "Location detection successful, applying settings"
        return 0
    fi

    # 3. 自動検出が失敗または拒否された場合、手動入力へ
    debug_log "DEBUG" "Automatic location detection failed or was declined. Proceeding to manual input."

    # 国の入力と検索ループ
    while true; do
        # 入力がまだない場合は入力を求める
        if [ -z "$input_lang" ]; then
            local msg_enter=$(get_message "MSG_ENTER_COUNTRY")
            printf "%s\n" "$(color white "$msg_enter")"

            local msg_search=$(get_message "MSG_SEARCH_KEYWORD")
            printf "%s " "$(color white "$msg_search")"

            read -r input_lang
            input_lang=$(normalize_input "$input_lang")
            debug_log "DEBUG" "User entered search keyword: $input_lang"
        fi

        printf "\n"
            
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
            
            printf "%s%s%s" "$(color white "$msg_prefix" "$country_name" "$msg_suffix")"

            printf "\n"
            
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

# 検出した地域情報を表示する共通関数
display_detected_location() {
    local detection_source="$1"
    local detected_country="$2"
    local detected_zonename="$3"
    local detected_timezone="$4"
    local show_success_message="${5:-false}"
    
    debug_log "DEBUG" "Displaying location information from source: $detection_source"
    
    # 検出情報表示
    local msg_info=$(get_message "MSG_USE_DETECTED_INFORMATION")
    msg_info=$(echo "$msg_info" | sed "s/{info}/$detection_source/g")
    printf "\n%s\n" "$(color white "$msg_info")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_COUNTRY")")" "$(color white "$detected_country")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_ZONENAME")")" "$(color white "$detected_zonename")"
    printf "%s %s\n" "$(color white "$(get_message "MSG_DETECTED_TIMEZONE")")" "$(color white "$detected_timezone")"
    
    # 成功メッセージの表示（オプション）
    if [ "$show_success_message" = "true" ]; then
        printf "%s\n" "$(color white "$(get_message "MSG_COUNTRY_SUCCESS")")"
        printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SET")")"
        printf "%s\n" "$(color white "$(get_message "MSG_TIMEZONE_SUCCESS")")"
        EXTRA_SPACING_NEEDED="yes"
        debug_log "DEBUG" "Success messages displayed"
    fi
    
    debug_log "DEBUG" "Location information displayed successfully"
}

# システムの地域情報を検出し設定する関数
# 引数: $1: 
#      "skip-cache" - cache情報の検出をスキップ
#      "skip_device" - デバイス内情報の検出をスキップ
#      "skip_ip" - IP検索をスキップ
#      "skip_cache-device" - cache情報とデバイス内情報の検出をスキップ
#      "skip_all" - すべての検出をスキップ
#      未指定の場合はすべての検出方法を試行
# システムの地域情報を検出し設定する関数
detect_and_set_location() {
    # デバッグログ出力
    debug_log "DEBUG" "Running detect_and_set_location() with skip flags: cache=$SKIP_CACHE_DETECTION, device=$SKIP_DEVICE_DETECTION, cache-device=$SKIP_CACHE_DEVICE_DETECTION, ip=$SKIP_IP_DETECTION, all=$SKIP_ALL_DETECTION"
    
    # 共通変数の宣言
    local detected_country=""
    local detected_timezone=""
    local detected_zonename=""
    local country_data=""
    local detection_source=""
    local preview_applied="false"
    local skip_confirmation="false"
    
    # 0. "SKIP_ALL_DETECTION"が指定された場合はすべての検出をスキップ
    if [ "$SKIP_ALL_DETECTION" = "true" ]; then
        debug_log "DEBUG" "SKIP_ALL_DETECTION is true, skipping all detection methods (cache, device, IP)"
        return 1
    fi
    
    # 1. キャッシュから情報取得を試みる
    if [ "$SKIP_CACHE_DETECTION" != "true" ] && [ "$SKIP_CACHE_DEVICE_DETECTION" != "true" ]; then
        debug_log "DEBUG" "Checking location cache using check_location_cache()"
    
        if check_location_cache; then
            debug_log "DEBUG" "Valid location cache found, loading cache data"
        
            # キャッシュファイルのパス定義
            local cache_language="${CACHE_DIR}/language.ch"
            local cache_luci="${CACHE_DIR}/luci.ch"
            local cache_timezone="${CACHE_DIR}/timezone.ch"
            local cache_zonename="${CACHE_DIR}/zonename.ch"
            local cache_message="${CACHE_DIR}/message.ch"
        
            # キャッシュからデータ読み込み
            if [ -s "$cache_language" ]; then
                detected_country=$(cat "$cache_language" 2>/dev/null)
                debug_log "DEBUG" "Country loaded from language.ch: $detected_country"
            else
                detected_country=$(grep -m 1 "country" "$cache_country" | cut -d'=' -f2 2>/dev/null)
                debug_log "DEBUG" "Country extracted from country.ch: $detected_country"
            
                # 抽出できなかった場合はファイル内容全体を試す
                if [ -z "$detected_country" ]; then
                    detected_country=$(cat "$cache_country" 2>/dev/null)
                    debug_log "DEBUG" "Using entire country.ch content as country: $detected_country"
                fi
            fi
        
            # タイムゾーン情報の取得
            detected_timezone=$(cat "$cache_timezone" 2>/dev/null)
            detected_zonename=$(cat "$cache_zonename" 2>/dev/null)
            detection_source="cache"
            skip_confirmation="true"
        
            debug_log "DEBUG" "Cache detection complete - country: $detected_country, timezone: $detected_timezone, zonename: $detected_zonename"
        
            # 検出データの検証と表示
            if [ -n "$detected_country" ] && [ -n "$detected_timezone" ] && [ -n "$detected_zonename" ]; then
                country_data=$(awk -v code="$detected_country" '$5 == code {print $0; exit}' "$BASE_DIR/country.db")
                debug_log "DEBUG" "Country data retrieved from database for display"
            
                # 共通関数を使用して検出情報と成功メッセージを表示
                display_detected_location "$detection_source" "$detected_country" "$detected_zonename" "$detected_timezone" "true"
            
                debug_log "DEBUG" "Cache-based location settings have been applied successfully"
                return 0
            else
                debug_log "DEBUG" "One or more cache values are empty despite files existing"
            fi
        else
            debug_log "DEBUG" "Cache check failed, proceeding to next detection method"
        fi
    else
        debug_log "DEBUG" "Cache detection skipped due to flag settings"
    fi

    # 2. デバイス内情報の検出（キャッシュが見つからない場合）
    if [ -z "$detected_country" ] && [ "$SKIP_DEVICE_DETECTION" != "true" ] && [ "$SKIP_CACHE_DEVICE_DETECTION" != "true" ]; then
        debug_log "DEBUG" "Attempting device-based information detection"
        
        if [ -f "$BASE_DIR/dynamic-system-info.sh" ]; then
            if ! command -v get_country_info >/dev/null 2>&1; then
                debug_log "DEBUG" "Loading dynamic-system-info.sh"
                . "$BASE_DIR/dynamic-system-info.sh"
            fi

            # 情報の取得
            detected_country=$(get_country_info)
            detected_timezone=$(get_timezone_info)
            detected_zonename=$(get_zonename_info)
            detection_source="device"
            
            debug_log "DEBUG" "Device detection results - country: $detected_country, timezone: $detected_timezone, zonename: $detected_zonename"
        else
            debug_log "DEBUG" "dynamic-system-info.sh not found. Cannot use system detection."
        fi
    fi

    # 2. デバイス内情報の検出（キャッシュが見つからない場合）
    if [ -z "$detected_country" ] && [ "$SKIP_DEVICE_DETECTION" != "true" ] && [ "$SKIP_CACHE_DEVICE_DETECTION" != "true" ]; then
        debug_log "DEBUG" "Attempting device-based information detection"
        
        if [ -f "$BASE_DIR/dynamic-system-info.sh" ]; then
            if ! command -v get_country_info >/dev/null 2>&1; then
                debug_log "DEBUG" "Loading dynamic-system-info.sh"
                . "$BASE_DIR/dynamic-system-info.sh"
            fi

            # 情報の取得
            detected_country=$(get_country_info)
            detected_timezone=$(get_timezone_info)
            detected_zonename=$(get_zonename_info)
            detection_source="device"
            
            debug_log "DEBUG" "Device detection results - country: $detected_country, timezone: $detected_timezone, zonename: $detected_zonename"
        else
            debug_log "DEBUG" "dynamic-system-info.sh not found. Cannot use system detection."
        fi
    fi
    
    # 3. IPアドレスによる検出（情報が揃っていない場合のみ）
    if [ -z "$detected_country" ] && [ "$SKIP_IP_DETECTION" != "true" ]; then
        debug_log "DEBUG" "Attempting IP-based location detection"
        
        if [ -f "$BASE_DIR/dynamic-system-info.sh" ]; then
            if ! command -v process_location_info >/dev/null 2>&1; then
                debug_log "DEBUG" "Loading dynamic-system-info.sh for IP detection"
                . "$BASE_DIR/dynamic-system-info.sh"
            fi
            
            if command -v process_location_info >/dev/null 2>&1; then
                if process_location_info; then
                    debug_log "DEBUG" "Successfully retrieved and cached location data"
                    
                    if [ -f "${CACHE_DIR}/ip_country.tmp" ] && [ -f "${CACHE_DIR}/ip_timezone.tmp" ] && [ -f "${CACHE_DIR}/ip_zonename.tmp" ]; then
                        detected_country=$(cat "${CACHE_DIR}/ip_country.tmp" 2>/dev/null)
                        detected_timezone=$(cat "${CACHE_DIR}/ip_timezone.tmp" 2>/dev/null)
                        detected_zonename=$(cat "${CACHE_DIR}/ip_zonename.tmp" 2>/dev/null)
                        detection_source="IP address"
                        
                        debug_log "DEBUG" "IP detection results - country: $detected_country, timezone: $detected_timezone, zonename: $detected_zonename"
                    else
                        debug_log "DEBUG" "One or more required IP location data files missing"
                    fi
                else
                    debug_log "DEBUG" "process_location_info() failed to retrieve location data"
                fi
            else
                debug_log "DEBUG" "process_location_info function not available"
            fi
        else
            debug_log "DEBUG" "dynamic-system-info.sh not found. Cannot use IP detection."
        fi
    fi
    
    # 4. 検出した情報の処理（検出ソースに関わらず共通処理）
    if [ -n "$detected_country" ] && [ -n "$detected_timezone" ] && [ -n "$detected_zonename" ]; then
        country_data=$(awk -v code="$detected_country" '$5 == code {print $0; exit}' "$BASE_DIR/country.db")
        
        if [ -n "$country_data" ]; then
            # プレビュー用に言語設定を適用（キャッシュ以外の場合）
            if [ "$detection_source" != "cache" ]; then
                echo "$country_data" > "${CACHE_DIR}/country.tmp"
                debug_log "DEBUG" "Applying temporary language settings for preview"
                country_write true && {
                    preview_applied="true"
                    debug_log "DEBUG" "Preview language applied from $detection_source detection"
                }
            fi

            debug_log "DEBUG" "Before display - source: $detection_source, country: $detected_country, skip_confirmation: $skip_confirmation"
        
            # 共通関数を使用して検出情報を表示（成功メッセージなし）
            display_detected_location "$detection_source" "$detected_country" "$detected_zonename" "$detected_timezone"
            
            # ユーザーに確認
            local proceed_with_settings="false"
            
            if [ "$skip_confirmation" = "true" ]; then
                # キャッシュの場合は自動承認
                proceed_with_settings="true"
                debug_log "DEBUG" "Cache-based location settings automatically applied without confirmation"
            else
                # キャッシュ以外の場合はユーザーに確認
                if confirm "MSG_CONFIRM_ONLY_YN"; then
                    proceed_with_settings="true"
                    debug_log "DEBUG" "User accepted $detection_source-based location settings"
                else
                    debug_log "DEBUG" "User declined $detection_source-based location settings"
                fi
            fi
            
            # 設定の適用処理（承認された場合）
            if [ "$proceed_with_settings" = "true" ]; then
                # キャッシュ以外の場合に設定を適用（プレビューで適用済みなら再適用不要）
                if [ "$detection_source" != "cache" ] && [ "$preview_applied" = "false" ]; then
                    debug_log "DEBUG" "Writing country data to temporary file"
                    echo "$country_data" > "${CACHE_DIR}/country.tmp"
                    debug_log "DEBUG" "Calling country_write() with suppress_message flag"
                    country_write true || {
                        debug_log "ERROR" "Failed to write country data"
                        return 1
                    }
                fi
                
                # 国選択完了メッセージを表示
                printf "%s\n" "$(color white "$(get_message "MSG_COUNTRY_SUCCESS")")"
                printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SET")")"
                
                # タイムゾーン設定（キャッシュ以外の場合のみ）
                if [ "$detection_source" != "cache" ]; then
                    local timezone_str="${detected_zonename},${detected_timezone}"
                    debug_log "DEBUG" "Created combined timezone string: ${timezone_str}"
                    
                    if [ "$detection_source" = "IP address" ]; then
                        echo "$timezone_str" > "${CACHE_DIR}/zone.tmp"
                        zone_write || {
                            debug_log "ERROR" "Failed to write timezone data"
                            return 1
                        }
                    else
                        zone_write "$timezone_str" || {
                            debug_log "ERROR" "Failed to write timezone data"
                            return 1
                        }
                    fi
                fi
                
                # ゾーン選択完了メッセージを表示
                printf "%s\n" "$(color white "$(get_message "MSG_TIMEZONE_SUCCESS")")"
                EXTRA_SPACING_NEEDED="yes"
                
                debug_log "DEBUG" "$detection_source-based location settings have been applied successfully"
                return 0
            else
                # 拒否された場合は一時的な言語設定をクリア（キャッシュ以外の場合）
                if [ "$detection_source" != "cache" ] && [ "$preview_applied" = "true" ]; then
                    debug_log "DEBUG" "Cleaning up preview language settings"
                    rm -f "${CACHE_DIR}/language.ch" "${CACHE_DIR}/message.ch" "${CACHE_DIR}/country.tmp" 2>/dev/null
                fi
                
                # リセットして次の検出方法に進む
                detected_country=""
                detected_timezone=""
                detected_zonename=""
                detection_source=""
                preview_applied="false"
                skip_confirmation="false"
            fi
        else
            debug_log "DEBUG" "No matching entry found for detected country: $detected_country"
        fi
    fi
    
    # 継続した検出処理のため、ここで検出ソースが空かどうか確認
    if [ -z "$detection_source" ]; then
        debug_log "DEBUG" "All automatic detection methods failed, proceeding with manual input"
        return 1
    fi
    
    return 0
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
            printf "%s\n" "$(color white "$(get_message "MSG_TIMEZONE_SUCCESS")")"
        fi
        
        return 0
    fi

    # 複数のタイムゾーンがある場合は選択肢を表示
    printf "\n%s\n" "$(color white "$(get_message "MSG_SELECT_TIMEZONE")")"
    
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
            printf "%s\n" "$(color white "$(get_message "MSG_TIMEZONE_SUCCESS")")"
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

# 国コード情報を書き込む関数（言語正規化機能付き）
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
    
    # 言語を正規化（この行を追加）
    debug_log "DEBUG" "Calling normalize_language to process language code"
    normalize_language
    
    # 成功メッセージを表示（スキップフラグが設定されていない場合のみ）
    if [ "$skip_message" = "false" ]; then
        # 国と言語の選択完了メッセージを表示
        printf "%s\n" "$(color white "$(get_message "MSG_COUNTRY_SUCCESS")")"
        printf "%s\n" "$(color white "$(get_message "MSG_LANGUAGE_SET")")"
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
