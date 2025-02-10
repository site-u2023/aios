#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important! OpenWrt OS only works with Almquist Shell, not Bourne-again shell.
# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

COMMON_VERSION="2025.02.11-0-0"

# 基本定数の設定
BASE_WGET="wget --quiet -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-${BASE_DIR}/cache}"
LOG_DIR="${LOG_DIR:-${BASE_DIR}/logs}"
mkdir -p "$CACHE_DIR" "$LOG_DIR"
DEBUG_MODE="${DEBUG_MODE:-false}"

script_update() (
COMMON_CACHE="${CACHE_DIR}/common_version.ch"
# **キャッシュが存在しない、またはバージョンが異なる場合にアラートを表示**
if [ ! -f "$COMMON_CACHE" ] || [ "$(cat "$COMMON_CACHE" | tr -d '\r\n')" != "$COMMON_VERSION" ]; then
    echo -e "`color white_black "common.sh Updated to version $COMMON_VERSION"`"
    echo "$COMMON_VERSION" > "$COMMON_CACHE"
fi
)

#########################################################################
# テスト用関数: データ取得を個別に確認
#########################################################################
test_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG: Running debug tests..." | tee -a "$LOG_DIR/debug.log"

        test_country_search "US"
        test_country_search "Japan"
        test_timezone_search "US"
        test_timezone_search "JP"
        test_cache_contents

        echo "DEBUG: luci.ch content: $(cat "$CACHE_DIR/luci.ch" 2>/dev/null || echo 'Not Found')" | tee -a "$LOG_DIR/debug.log"
        echo "DEBUG: country.ch content: $(cat "$CACHE_DIR/country.ch" 2>/dev/null || echo 'Not Found')" | tee -a "$LOG_DIR/debug.log"
        echo "DEBUG: language.ch content: $(cat "$CACHE_DIR/language.ch" 2>/dev/null || echo 'Not Found')" | tee -a "$LOG_DIR/debug.log"
    fi
}

# 国検索テスト
test_country_search() {
    local test_input="$1"
    echo "`color cyan "TEST: Searching for country with input '$test_input'"`"
    if [ ! -f "${BASE_DIR}/country.db" ]; then
        echo "`color red "ERROR: country.db not found at ${BASE_DIR}/country.db"`"
        return 1
    fi
    awk -v query="$test_input" '
        $2 ~ query || $3 ~ query || $4 ~ query || $5 ~ query {print NR, $2, $3, $4, $5, $6, $7, $8, $9}' "${BASE_DIR}/country.db"
}

# タイムゾーン検索テスト
test_timezone_search() {
    local test_country="$1"
    echo "`color cyan "TEST: Searching for timezones of country '$test_country'"`"
    if [ ! -f "${BASE_DIR}/country.db" ]; then
        echo "`color red "ERROR: country.db not found at ${BASE_DIR}/country.db"`"
        return 1
    fi
    awk -v country="$test_country" '
        $2 == country || $4 == country || $5 == country {print NR, $5, $6, $7, $8, $9, $10, $11}' "${BASE_DIR}/country.db"
}

# キャッシュ内容確認テスト
test_cache_contents() {
    echo "`color yellow "DEBUG: country_tmp.ch content:"`"
    cat "${CACHE_DIR}/country_tmp.ch"
    echo "`color yellow "DEBUG: zone_tmp.ch content:"`"
    cat "${CACHE_DIR}/zone_tmp.ch"
}

#########################################################################
# check_language: 言語のチェックと `luci.ch` への書き込み
#########################################################################
check_language() {
    local lang_code="$1"

    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG: check_language received lang_code: '$lang_code'" | tee -a "$LOG_DIR/debug.log"
    fi

    if [ -z "$lang_code" ]; then
        lang_code="en"
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: No language provided, defaulting to 'en'" | tee -a "$LOG_DIR/debug.log"
    fi

    if grep -q "^$lang_code" "$CACHE_DIR/luci.ch"; then
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: Language '$lang_code' found in luci.ch" | tee -a "$LOG_DIR/debug.log"
        return
    fi

    if grep -q "\b$lang_code\b" "$BASE_DIR/country.db"; then
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: Language '$lang_code' found in country.db" | tee -a "$LOG_DIR/debug.log"
        echo "$lang_code" > "$CACHE_DIR/luci.ch"
    else
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: No matching language in country.db, defaulting to 'en'" | tee -a "$LOG_DIR/debug.log"
        echo "en" > "$CACHE_DIR/luci.ch"
    fi
}


# -------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# select_country: 国と言語、タイムゾーンを選択（検索・表示を `country.db` に統一）
#########################################################################
select_country() {
    local country_file="${BASE_DIR}/country.db"
    local country_cache="${CACHE_DIR}/country.ch"
    local language_cache="${CACHE_DIR}/luci.ch"
    local zone_cache="${CACHE_DIR}/zone.ch"
    local country_tmp="${CACHE_DIR}/country_tmp.ch"
    local zone_tmp="${CACHE_DIR}/zone_tmp.ch"
    local user_input=""
    local found_entries=""
    local selected_entry=""
    local selected_zonename=""
    local selected_timezone=""
    local index=1
    local max_display=10  # 一度に表示する最大件数
    
    # **キャッシュの初期化**
    > "$country_tmp"
    > "$zone_tmp"

    # **データベース存在確認**
    if [ ! -f "$country_file" ]; then
        echo "$(color red \"Country database not found!\")"
        return 1
    fi

    while true; do
        echo "$(color cyan \"Enter country name, code, or language to set language and retrieve timezone.\")"
        echo -n "$(color cyan \"Please input: \")"
        read user_input
        user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[\/,_]+/ /g')

        if [ -z "$user_input" ]; then
            echo "$(color yellow \"Invalid input. Please enter a valid country name, code, or language.\")"
            continue
        fi

        # **検索処理: 完全一致 → 前方一致 → 後方一致 → 部分一致**
        found_entries=$(awk -v query="$user_input" '$4 == query {print NR, $2, $3, $4, $5, $6, $7}' "$country_file")

        if [ -z "$found_entries" ]; then
            found_entries=$(awk -v query="^"query '$0 ~ query {print NR, $2, $3, $4, $5, $6, $7}' "$country_file")
        fi

        if [ -z "$found_entries" ]; then
            found_entries=$(awk -v query=query"$" '$0 ~ query {print NR, $2, $3, $4, $5, $6, $7}' "$country_file")
        fi

        if [ -z "$found_entries" ]; then
            found_entries=$(awk -v query="$user_input" '$0 ~ query {print NR, $2, $3, $4, $5, $6, $7}' "$country_file")
        fi

        if [ -z "$found_entries" ]; then
            echo "$(color yellow \"No matching country found. Please try again.\")"
            continue
        fi

        echo "$(color cyan \"Select a country (max $max_display at a time, type 'more' to show more):\")"
        i=1
        echo "$found_entries" | head -n $max_display | while read -r index country_name lang_code country_code zonename timezone; do
            echo "[$i] $country_name ($lang_code)"
            echo "$i $country_name $lang_code $country_code $zonename $timezone" >> "$country_tmp"
            i=$((i + 1))
        done
        echo "[0] Cancel / /back to return"

        while true; do
            echo -n "$(color cyan \"Enter the number of your choice (or 0 to retry): \")"
            read choice
            if [ "$choice" = "0" ]; then
                echo "$(color yellow \"Returning to country selection.\")"
                break
            fi

            selected_entry=$(awk -v num="$choice" '$1 == num {print $2, $3, $4, $5}' "$country_tmp")

            if [ -z "$selected_entry" ]; then
                echo "$(color red \"Invalid selection. Please choose a valid number.\")"
                continue
            fi

            echo "$(color cyan \"Confirm selection: [$choice] $selected_entry (Y/n)?\")"
            read yn
            case "$yn" in
                [Yy]*)
                    echo "$(color green \"Final selection: $selected_entry\")"
                    echo "$selected_entry" > "$country_cache"
                    return
                    ;;
                [Nn]*)
                    echo "$(color yellow \"Returning to country selection.\")"
                    break
                    ;;
                *)
                    echo "$(color red \"Invalid input. Please enter 'Y' or 'N'.\")"
                    ;;
            esac
        done
    done
}





#########################################################################
# select_country: 国と言語、タイムゾーンを選択（検索・表示を `country.db` に統一）
#########################################################################
XXXXX_0210_1_select_country() {
    local country_file="${BASE_DIR}/country.db"
    local country_cache="${CACHE_DIR}/country.ch"
    local language_cache="${CACHE_DIR}/language.ch"
    local luci_cache="${CACHE_DIR}/luci.ch"
    local zone_cache="${CACHE_DIR}/zone.ch"
    local country_tmp="${CACHE_DIR}/country_tmp.ch"
    local zone_tmp="${CACHE_DIR}/zone_tmp.ch"
    local user_input=""
    local found_entries=""
    local selected_entry=""
    local selected_zonename=""
    local selected_timezone=""
    local index=1

    # **キャッシュの初期化**
    > "$country_tmp"
    > "$zone_tmp"

    # **データベース存在確認**
    if [ ! -f "$country_file" ]; then
        echo "$(color red \"Country database not found!\")"
        return 1
    fi

    while true; do
        echo "`color cyan \"Enter country name, code, or language to set language and retrieve timezone.\"`"
        echo -n "`color cyan \"Please input: \"`"
        read user_input
        user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[\/,_]+/ /g')

        if [ -z "$user_input" ]; then
            echo "`color yellow \"Invalid input. Please enter a valid country name, code, or language.\"`"
            continue
        fi

        # **検索処理: 完全一致 → 前方一致 → 後方一致 → 部分一致**
        found_entries=$(awk -v query="$user_input" '$3 == query || $4 == query || $5 == query {print NR, $2, $3, $4, $5, $6, $7}' "$country_file")

        if [ -z "$found_entries" ]; then
            found_entries=$(awk -v query="^"query '$0 ~ query {print NR, $2, $3, $4, $5, $6, $7}' "$country_file")
        fi

        if [ -z "$found_entries" ]; then
            found_entries=$(awk -v query=query"$" '$0 ~ query {print NR, $2, $3, $4, $5, $6, $7}' "$country_file")
        fi

        if [ -z "$found_entries" ]; then
            found_entries=$(awk -v query="$user_input" '$0 ~ query {print NR, $2, $3, $4, $5, $6, $7}' "$country_file")
        fi

        if [ -z "$found_entries" ]; then
            echo "`color yellow \"No matching country found. Please try again.\"`"
            continue
        fi

        echo "`color cyan \"Select a country:\"`"
        i=1
        echo "$found_entries" | while read -r index country_name lang_code country_code zonename timezone; do
            echo "[$i] $country_name ($lang_code)"
            echo "$i $country_name $lang_code $country_code $zonename $timezone" >> "$country_tmp"
            i=$((i + 1))
        done
        echo "[0] Try again"

        while true; do
            echo -n "`color cyan \"Enter the number of your choice (or 0 to retry): \"`"
            read choice
            if [ "$choice" = "0" ]; then
                echo "`color yellow \"Returning to country selection.\"`"
                break
            fi

            selected_entry=$(awk -v num="$choice" '$1 == num {print $2, $3, $4, $5}' "$country_tmp")

            if [ -z "$selected_entry" ]; then
                echo "`color red \"Invalid selection. Please choose a valid number.\"`"
                continue
            fi

            echo "`color cyan \"Select a timezone for $selected_entry:\"`"
            i=1
            echo "$found_entries" | while read -r line; do
                zone_name=$(echo "$line" | awk '{print $5}')
                tz=$(echo "$line" | awk '{print $6}')
                echo "[$i] $zone_name ($tz)"
                echo "$i $zone_name $tz" >> "$zone_tmp"
                i=$((i + 1))
            done
            echo "[0] Try again"
            
            while true; do
                echo -n "`color cyan \"Enter the number of your timezone choice (or 0 to retry): \"`"
                read tz_choice
                if [ "$tz_choice" = "0" ]; then
                    echo "`color yellow \"Returning to timezone selection.\"`"
                    break
                fi
                selected_zonename=$(awk -v num="$tz_choice" '$1 == num {print $2}' "$zone_tmp")
                selected_timezone=$(awk -v num="$tz_choice" '$1 == num {print $3}' "$zone_tmp")
                if [ -z "$selected_zonename" ] || [ -z "$selected_timezone" ]; then
                    echo "`color red \"Invalid selection. Please choose a valid number.\"`"
                    continue
                fi
                echo "`color cyan \"Confirm selection: [$tz_choice] $selected_zonename ($selected_timezone)? [Y/n]\"`"
                read yn
                case "$yn" in
                    [Yy]*)
                        echo "`color green \"Final selection: $selected_entry (Zone: [$tz_choice] $selected_zonename, Timezone: $selected_timezone)\"`"
                        echo "$selected_entry" > "$country_cache"
                        echo "$selected_zonename" > "$luci_cache"
                        echo "$selected_timezone" > "$language_cache"
                        return
                        ;;
                    [Nn]*)
                        echo "`color yellow \"Returning to timezone selection.\"`"
                        break
                        ;;
                    *)
                        echo "`color red \"Invalid input. Please enter 'Y' or 'N'.\"`"
                        ;;
                esac
            done
        done
    done
}

#########################################################################
# select_country: アップロードされた common.sh & country.sh OKバージョン
#########################################################################
OK_0210_select_country() {
    local country_file="${BASE_DIR}/country.db"
    local country_cache="${BASE_DIR}/country.ch"
    local language_cache="${BASE_DIR}/language.ch"
    local timezone_cache="${BASE_DIR}/timezone.ch"
    local user_input=""
    local selected_entry=""
    local selected_zone=""
    local selected_timezone=""

    if [ ! -f "$country_file" ]; then
        echo "`color red "Country database not found!"`"
        return 1
    fi

    while true; do
        echo "`color cyan "Enter country name, code, or language to set language and retrieve timezone."`"
        echo -n "`color cyan "Please input: "`"
        read user_input
        user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[\/,_]+/ /g')

        if [ -z "$user_input" ]; then
            echo "`color yellow "Invalid input. Please enter a valid country name, code, or language."`"
            continue
        fi

        found_entries=$(awk -v query="$user_input" '{if ($0 ~ query) print $0}' "$country_file")

        if [ -z "$found_entries" ]; then
            echo "`color yellow "No matching country found. Please try again."`"
            continue
        fi

        echo "`color cyan "Select a country:"`"
        i=1
        > /tmp/country_selection.tmp
        echo "$found_entries" | while read -r line; do
            country_name=$(echo "$line" | awk '{print $2}')
            lang_code=$(echo "$line" | awk '{print $3}')
            country_code=$(echo "$line" | awk '{print $4}')
            echo "[$i] $country_name ($lang_code)"
            echo "$i $country_name $lang_code $country_code" >> /tmp/country_selection.tmp
            i=$((i + 1))
        done
        echo "[0] Try again"

        while true; do
            echo -n "`color cyan "Enter the number of your choice (or 0 to retry): "`"
            read choice
            if [ "$choice" = "0" ]; then
                echo "`color yellow "Returning to country selection."`"
                break
            fi

            selected_entry=$(awk -v num="$choice" '$1 == num {print $2, $3, $4}' /tmp/country_selection.tmp)

            if [ -z "$selected_entry" ]; then
                echo "`color red "Invalid selection. Please choose a valid number."`"
                continue
            fi

            echo "`color cyan "Select a timezone for $selected_entry:"`"
            i=1
            > /tmp/timezone_selection.tmp
            echo "$found_entries" | while read -r line; do
                zone_name=$(echo "$line" | awk '{print $5}')
                tz=$(echo "$line" | awk '{print $6}')
                echo "[$i] $zone_name ($tz)"
                echo "$i $zone_name $tz" >> /tmp/timezone_selection.tmp
                i=$((i + 1))
            done
            echo "[0] Try again"
            
            while true; do
                echo -n "`color cyan "Enter the number of your timezone choice (or 0 to retry): "`"
                read tz_choice
                if [ "$tz_choice" = "0" ]; then
                    echo "`color yellow "Returning to timezone selection."`"
                    break
                fi
                selected_zone=$(awk -v num="$tz_choice" '$1 == num {print $2}' /tmp/timezone_selection.tmp)
                selected_timezone=$(awk -v num="$tz_choice" '$1 == num {print $3}' /tmp/timezone_selection.tmp)
                if [ -z "$selected_zone" ] || [ -z "$selected_timezone" ]; then
                    echo "`color red "Invalid selection. Please choose a valid number."`"
                    continue
                fi
                echo "`color cyan "Confirm selection: [$tz_choice] $selected_zone ($selected_timezone)? [Y/n]"`"
                read yn
                case "$yn" in
                    [Yy]*)
                        echo "`color green "Final selection: $selected_entry (Zone: [$tz_choice] $selected_zone, Timezone: $selected_timezone)"`"
                        echo "$selected_entry" > "$country_cache"
                        echo "$selected_zone" > "$language_cache"
                        echo "$selected_timezone" > "$timezone_cache"
                        echo "`color green "Saved to cache: country.ch=$selected_entry, language.ch=$selected_zone, timezone.ch=$selected_timezone"`"
                        return
                        ;;
                    [Nn]*)
                        echo "`color yellow "Returning to timezone selection."`"
                        break
                        ;;
                    *)
                        echo "`color red "Invalid input. Please enter 'Y' or 'N'."`"
                        ;;
                esac
            done
        done
    done
}



#########################################################################
# select_country: 国と言語、タイムゾーンを選択（検索・表示を `country.db` に統一）
#########################################################################
OK_0209_select_country() {
    local country_file="${BASE_DIR}/country.db"
    local country_cache="${BASE_DIR}/country.ch"
    local language_cache="${BASE_DIR}/language.ch"
    local user_input=""
    local selected_entry=""

    if [ ! -f "$country_file" ]; then
        echo "$(color red "Country database not found!")"
        return 1
    fi

    while true; do
        echo "$(color cyan "Fuzzy search: Enter a country name, code, or language.")"
        echo -n "$(color cyan "Please input: ")"
        read user_input
        user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[\/,_]+/ /g')

        if [ -z "$user_input" ]; then
            echo "$(color yellow "Invalid input. Please enter a valid country name, code, or language.")"
            continue
        fi

        # **検索は `country.db` を直接使用（ゾーン情報は除外）**
        found_entries=$(awk -v query="$user_input" '
            {
                line = tolower($0);
                gsub(/[\/,_]+/, " ", line);  # 検索対象から / , _ を削除
                if (line ~ query) 
                    print NR, $2, $3, $4  # 出力は行番号, 国名, 言語, 国コード（ゾーン情報は除外）
            }' "$country_file")

        if [ -z "$found_entries" ]; then
            echo "$(color yellow "No matching country found. Please try again.")"
            continue
        fi

        echo "$(color cyan "DEBUG: Search results:")"
        echo "$found_entries"

        matches_found=$(echo "$found_entries" | wc -l)

        if [ "$matches_found" -eq 1 ]; then
            selected_entry=$(echo "$found_entries" | awk '{print $2, $3, $4}')
            echo -e "$(color cyan "Confirm country selection: \"$selected_entry\"? [Y/n]:")"
            read yn
            case "$yn" in
                [Yy]*) break ;;
                [Nn]*) continue ;;
                *) echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")" ;;
            esac
        else
            echo "$(color yellow "Multiple matches found. Please select:")"
            i=1
            echo "$found_entries" | while read -r index country_name lang_code country_code; do
                echo "[$i] $country_name ($lang_code)"
                echo "$i $country_name $lang_code $country_code" >> /tmp/country_selection.tmp
                i=$((i + 1))
            done
            echo "[0] Try again"

            while true; do
                echo -n "$(color cyan "Enter the number of your choice (or 0 to retry): ")"
                read choice
                if [ "$choice" = "0" ]; then
                    echo "$(color yellow "Returning to country selection.")"
                    break
                fi

                selected_entry=$(awk -v num="$choice" '$1 == num {print $2, $3, $4}' /tmp/country_selection.tmp)

                if [ -z "$selected_entry" ]; then
                    echo "$(color red "Invalid selection. Please choose a valid number.")"
                    continue
                fi

                echo -e "$(color cyan "Confirm country selection: \"$selected_entry\"? [Y/n]:")"
                read yn
                case "$yn" in
                    [Yy]*) break 2 ;;
                    [Nn]*) break ;;
                    *) echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")" ;;
                esac
            done
        fi
    done

    # **デバッグ情報**
    echo "$(color cyan "DEBUG: Selected Country: $selected_entry")"

    # **キャッシュへの保存**
    echo "$selected_entry" > "$country_cache"
    echo "$(echo "$selected_entry" | awk '{print $2}')" > "$language_cache"

    echo "$(color green "Final selection: $selected_entry")"
}
























































# -------------------------------------------------------------------------------------------------------------------------------------------

#########################################################################
# print_help: ヘルプメッセージを表示
#########################################################################
print_help() {
    echo "Usage: aios.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -reset, --reset, -r     Reset all cached data"
    echo "  -help, --help, -h       Show this help message"
    echo "  ja, en, zh-cn, ...      Set language"
    echo ""
    echo "Examples:"
    echo "  sh aios.sh --reset      # Reset cache"
    echo "  sh aios.sh -ja          # Set language to Japanese"
    echo "  sh aios.sh -ja --reset  # Set language to Japanese and reset cache"
}

#########################################################################
# color: ANSI エスケープシーケンスを使って色付きメッセージを出力する関数
# 引数1: 色の名前 (例: red, green, blue_white など)
# 引数2以降: 出力するメッセージ
#########################################################################
color() {
    local color_code
    color_code=$(color_code_map "$1")
    shift
    echo -e "${color_code}$*$(color_code_map "reset")"
}

#########################################################################
# color_code_map: カラー名から ANSI エスケープシーケンスを返す関数
# 引数: 色の名前
#########################################################################
color_code_map() {
    local color="$1"
    case "$color" in
        "red") echo "\033[1;31m" ;;
        "green") echo "\033[1;32m" ;;
        "yellow") echo "\033[1;33m" ;;
        "blue") echo "\033[1;34m" ;;
        "magenta") echo "\033[1;35m" ;;
        "cyan") echo "\033[1;36m" ;;
        "white") echo "\033[1;37m" ;;
        "red_underline") echo "\033[4;31m" ;;
        "green_underline") echo "\033[4;32m" ;;
        "yellow_underline") echo "\033[4;33m" ;;
        "blue_underline") echo "\033[4;34m" ;;
        "magenta_underline") echo "\033[4;35m" ;;
        "cyan_underline") echo "\033[4;36m" ;;
        "white_underline") echo "\033[4;37m" ;;
        "red_white") echo "\033[1;41m" ;;
        "green_white") echo "\033[1;42m" ;;
        "yellow_white") echo "\033[1;43m" ;;
        "blue_white") echo "\033[1;44m" ;;
        "magenta_white") echo "\033[1;45m" ;;
        "cyan_white") echo "\033[1;46m" ;;
        "white_black") echo "\033[7;40m" ;;
        "reset") echo "\033[0;39m" ;;
        *) echo "\033[0;39m" ;;  # デフォルトでリセット
    esac
}

#########################################################################
# handle_error: 汎用エラーハンドリング関数
#########################################################################
# **デバッグ出力関数**
debug_log() {
    local message="$1"
    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG: $message" | tee -a "$LOG_DIR/debug.log"
    fi
}

# 環境変数 INPUT_LANG のチェック (デフォルト 'en')
INPUT_LANG="${INPUT_LANG:-en}"
debug_log "common.sh received INPUT_LANG: '$INPUT_LANG'"

# **エラーハンドリング + デバッグログ**
handle_error() {
    local message_key="$1"
    local file="$2"
    local version="$3"

    local error_message
    error_message=$(get_message "$message_key")

    error_message=$(echo "$error_message" | sed -e "s/{file}/$file/" -e "s/{version}/$version/")

    echo -e "$(color red "$error_message")"
    return 1  # `exit 1` → `return 1` に変更
}

#########################################################################
# download_script: 指定されたスクリプト・データベースのバージョン確認とダウンロード
#########################################################################
download_script() {
    local file_name="$1"
    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"
    
    # `aios` の場合は `/usr/bin` に配置
    if [ "$file_name" = "aios" ]; then
        install_path="${AIOS_DIR}/${file_name}"
    fi

    # ファイルが存在しない場合はダウンロード
    if [ ! -f "$install_path" ]; then
        echo -e "$(color yellow "$(get_message 'MSG_DOWNLOADING_MISSING_FILE' "$SELECTED_LANGUAGE" | sed "s/{file}/$file_name/")")"
        if ! ${BASE_WGET} "$install_path" "$remote_url"; then
            echo -e "$(color red "Failed to download: $file_name")"
            return 1
        fi
        echo -e "$(color green "Successfully downloaded: $file_name")"

        # `aios` のみ実行権限を付与
        if [ "$file_name" = "aios" ]; then
            chmod +x "$install_path"
            echo -e "$(color cyan "Applied execute permissions to: $install_path")"
        fi
    fi

    # バージョン取得
    local current_version="N/A"
    local remote_version="N/A"

    if test -s "$install_path"; then
        current_version=$(grep "^version=" "$install_path" | cut -d'=' -f2 | tr -d '"\r')
        [ -z "$current_version" ] && current_version="N/A"
    fi
    
    # ローカルバージョンを取得
    local current_version=""
    if [ -f "$install_path" ]; then
        current_version=$(grep "^version=" "$install_path" | cut -d'=' -f2 | tr -d '"\r')
    fi

    # リモートバージョンを取得
    local remote_version=""
    remote_version=$(wget -qO- "${remote_url}" | grep "^version=" | cut -d'=' -f2 | tr -d '"\r')

    # 空のバージョン情報が表示されるのを防ぐ
    if [ -z "$current_version" ]; then current_version="N/A"; fi
    if [ -z "$remote_version" ]; then remote_version="N/A"; fi

    # デバッグログ
    echo -e "$(color cyan "DEBUG: Checking version for $file_name | Local: [$current_version], Remote: [$remote_version]")"

    # バージョンチェック: 最新があればダウンロード
    if [ -n "$remote_version" ] && [ "$current_version" != "$remote_version" ]; then
        echo -e "$(color cyan "$(get_message 'MSG_UPDATING_SCRIPT' "$SELECTED_LANGUAGE" | sed -e "s/{file}/$file_name/" -e "s/{old_version}/$current_version/" -e "s/{new_version}/$remote_version/")")"
        if ! ${BASE_WGET} "$install_path" "$remote_url"; then
            echo -e "$(color red "Failed to download: $file_name")"
            return 1
        fi
        echo -e "$(color green "Successfully downloaded: $file_name")"
    else
        echo -e "$(color green "$(get_message 'MSG_NO_UPDATE_NEEDED' "$SELECTED_LANGUAGE" | sed -e "s/{file}/$file_name/" -e "s/{version}/$current_version/")")"
    fi
}

#########################################################################
# 汎用ファイルダウンロード関数
#########################################################################
download() {
    local file_url="$1"
    local destination="$2"

    # ダウンロード前の確認
    if ! confirm "MSG_DOWNLOAD_CONFIRM" "$file_url"; then
        echo -e "$(color yellow "Skipping download of $file_url")"
        return 0
    fi

    # 実際のダウンロード処理
    ${BASE_WGET} "$destination" "${file_url}?cache_bust=$(date +%s)"
    if [ $? -eq 0 ]; then
        echo -e "$(color green "Downloaded: $file_url")"
    else
        echo -e "$(color red "Failed to download: $file_url")"
        exit 1
    fi
}

#########################################################################
# openwrt_db: バージョンデータベースのダウンロード
#########################################################################
openwrt_db() {
    if [ ! -f "${BASE_DIR}/openwrt.db" ]; then
        ${BASE_WGET} "${BASE_DIR}/openwrt.db" "${BASE_URL}/openwrt.db" || handle_error "Failed to download openwrt.db"
    fi
}

#########################################################################
# messages_db: 選択された言語のメッセージファイルをダウンロード
#########################################################################
XXXXX_messages_db() {
    if [ ! -f "${BASE_DIR}/messages.db" ]; then
        ${BASE_WGET} "${BASE_DIR}/messages.db" "${BASE_URL}/messages.db" || handle_error "Failed to download messages.db"
    fi
}

#########################################################################
# messages_db: メッセージデータベースのダウンロード
#########################################################################
messages_db() {
    if [ ! -f "${BASE_DIR}/messages.db" ]; then
        echo -e "$(color yellow "Downloading messages.db...")"
        if ! ${BASE_WGET} "${BASE_DIR}/messages.db" "${BASE_URL}/messages.db"; then
            echo -e "$(color red "Failed to download messages.db")"
            return 1  # `handle_error` を使わず `return 1` に変更
        fi
        echo -e "$(color green "Successfully downloaded messages.db")"
    fi
}


#########################################################################
# packages_db: 選択されたパッケージファイルをダウンロード
#########################################################################
packages_db() {
    if [ ! -f "${BASE_DIR}/packages.db" ]; then
        ${BASE_WGET} "${BASE_DIR}/packages.db" "${BASE_URL}/packages.db" || handle_error "Failed to download packages.db"
    fi
}

#########################################################################
# download_script: 指定されたスクリプト・データベースのバージョン確認とダウンロード
#########################################################################
download_script() {
    local file_name="$1"
    local script_cache="${BASE_DIR}/script.ch"
    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"

    # キャッシュが存在する場合は利用
    if [ -f "$script_cache" ] && grep -q "^$file_name=" "$script_cache"; then
        local cached_version=$(grep "^$file_name=" "$script_cache" | cut -d'=' -f2)
        local remote_version=$(wget -qO- "${remote_url}" | grep "^version=" | cut -d'=' -f2)

        if [ "$cached_version" = "$remote_version" ]; then
            echo "$(color green "$file_name is up-to-date ($cached_version). Skipping download.")"
            return
        fi
    fi

    echo "$(color yellow "Downloading latest version of $file_name")"
    ${BASE_WGET} "$install_path" "$remote_url"

    local new_version=$(grep "^version=" "$install_path" | cut -d'=' -f2)
    echo "$file_name=$new_version" >> "$script_cache"
}

#########################################################################
# select_country: `country.db` から国を検索し、ユーザーに選択させる
#########################################################################
XXXXX_select_country() {
    local country_file="${BASE_DIR}/country.db"
    local country_cache="${BASE_DIR}/country.ch"
    local language_cache="${BASE_DIR}/language.ch"
    local zone_cache="${BASE_DIR}/zone.ch"
    local user_input=""
    local found_entries=""
    local selected_entry=""
    local selected_zonename=""
    local selected_timezone=""
    local index=1

    # **データベース存在確認**
    if [ ! -f "$country_file" ]; then
        echo "$(color red "Country database not found!")"
        return 1
    fi

    while true; do
        # **国リスト表示（1 から順に番号を振る）**
        index=1
        awk '{printf "[%d] %s %s %s %s\n", index++, $1, $2, $3, $4}' "$country_file"

        # **ユーザー入力**
        echo -e "$(color cyan "Enter country name, code, or language (or press Enter to list all):")"
        read user_input

        # **番号入力の処理**
        if echo "$user_input" | grep -qE '^[0-9]+$'; then
            selected_entry=$(awk -v num="$user_input" 'NR == num {print $0}' "$country_file")
        else
            # **検索処理**
            found_entries=$(awk -v query="$user_input" '
                tolower($1) == tolower(query) ||
                tolower($2) == tolower(query) ||
                tolower($3) == tolower(query) ||
                tolower($4) == tolower(query) {printf "[%d] %s\n", NR, $0}' "$country_file")

            # **曖昧検索**
            if [ -z "$found_entries" ]; then
                found_entries=$(awk -v query="$user_input" '
                    tolower($1) ~ tolower(query) ||
                    tolower($2) ~ tolower(query) ||
                    tolower($3) ~ tolower(query) ||
                    tolower($4) ~ tolower(query) {printf "[%d] %s\n", NR, $0}' "$country_file")
            fi

            # **検索結果の処理**
            if [ -z "$found_entries" ]; then
                echo "$(color yellow "No matching country found. Please try again.")"
                continue
            fi

            # **複数ヒット時の選択**
            if [ "$(echo "$found_entries" | wc -l)" -gt 1 ]; then
                echo "$(color yellow "Multiple matches found. Please select:")"
                echo "$found_entries"
                read -p "Enter the number of your choice: " choice
                selected_entry=$(awk -v num="$choice" 'NR == num {print $0}' "$country_file")
            else
                selected_entry=$(echo "$found_entries" | sed -E 's/\[[0-9]+\] //')
            fi
        fi

        # **選択した国が正しいか確認**
        if [ -n "$selected_entry" ]; then
            local country_name=$(echo "$selected_entry" | awk '{print $1}')
            local display_name=$(echo "$selected_entry" | awk '{print $2}')
            local lang_code=$(echo "$selected_entry" | awk '{print $3}')
            local country_code=$(echo "$selected_entry" | awk '{print $4}')
            local tz_data=$(echo "$selected_entry" | cut -d' ' -f5-)

            echo -e "$(color cyan "Confirm country selection: $country_name ($display_name, $lang_code, $country_code)? [Y/n]:")"
            read yn
            case "$yn" in
                Y|y) break ;;
                N|n) echo "$(color yellow "Invalid selection. Please try again.")" ; continue ;;
                *) echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")" ;;
            esac
        fi
    done

    # **タイムゾーンの選択**
    if echo "$tz_data" | grep -q ","; then
        echo "$(color cyan "Select a timezone for $country_name:")"
        index=1
        echo "$tz_data" | awk -F' ' '{for (i=1; i<=NF; i++) print "[" i "] " $i}'

        while true; do
            echo "Enter the number of your choice (or 0 to go back): "
            read tz_choice

            if [ "$tz_choice" = "0" ]; then
                echo "$(color yellow "Returning to timezone selection.")"
                continue
            fi

            selected_zonename=$(echo "$tz_data" | awk -F' ' -v num="$tz_choice" 'NR == num {print $1}')
            selected_timezone=$(echo "$tz_data" | awk -F' ' -v num="$tz_choice" 'NR == num {print $2}')

            if [ -z "$selected_zonename" ] || [ -z "$selected_timezone" ]; then
                echo "$(color red "Invalid selection. Please enter a valid number.")"
                continue
            fi

            echo -e "$(color cyan "Confirm timezone selection: $selected_zonename, $selected_timezone? [Y/n]:")"
            read yn
            case "$yn" in
                Y|y) break ;;
                N|n) echo "$(color yellow "Invalid selection. Please try again.")" ; continue ;;
                *) echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")" ;;
            esac
        done
    else
        selected_zonename=$(echo "$tz_data" | awk '{print $1}')
        selected_timezone=$(echo "$tz_data" | awk '{print $2}')
    fi

    # **キャッシュに保存**
    echo "$country_name $display_name $lang_code $country_code" > "$country_cache"
    echo "$selected_zonename $selected_timezone" > "$zone_cache"

    echo "$(color green "Country and timezone set: $country_name, $selected_zonename, $selected_timezone")"
    echo "$(color green "Language saved to language.ch: $lang_code")"
    echo "$lang_code" > "$language_cache"
}

#########################################################################
# normalize_country: 言語設定の正規化
#########################################################################
normalize_country() {
    local message_db="${BASE_DIR}/messages.db"
    local language_cache="${CACHE_DIR}/luci.ch"
    local selected_language="en"

    if [ -f "$language_cache" ]; then
        selected_language=$(cat "$language_cache")
        debug_log "Loaded language from luci.ch -> $selected_language"
    else
        debug_log "No luci.ch found, defaulting to 'en'"
    fi

    if grep -q "^$selected_language|" "$message_db"; then
        debug_log "Using message database language: $selected_language"
    else
        selected_language="en"
        debug_log "Language not found in messages.db. Using: en"
    fi

    debug_log "Final language after normalization -> $selected_language"
}

#########################################################################
# confirm: Y/N 確認関数
# ✅ 1回だけ実行されるように修正
#########################################################################
confirm() {
    local key="$1"
    local replace_param1="$2"
    local replace_param2="$3"
    local prompt_message
    prompt_message=$(get_message "$key" "$SELECTED_LANGUAGE")

    # 置換処理
    [ -n "$replace_param1" ] && prompt_message=$(echo "$prompt_message" | sed "s/{pkg}/$replace_param1/g")
    [ -n "$replace_param2" ] && prompt_message=$(echo "$prompt_message" | sed "s/{version}/$replace_param2/g")

    # デバッグログ
    echo "DEBUG: Confirm message -> [$prompt_message]"

    # ユーザー入力待ち
    while true; do
        read -r -p "$prompt_message " confirm
        confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')  # 小文字変換

        case "$confirm" in
            ""|"y"|"yes") return 0  ;;  # YES
            "n"|"no") return 1  ;;  # NO
            *) echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")" ;;
        esac
    done
}

#########################################################################
# check_country: 国データの取得とキャッシュ保存
#########################################################################
check_country() {
    local country_file="${BASE_DIR}/country.db"
    local country_cache="${CACHE_DIR}/country.ch"
    local luci_cache="${CACHE_DIR}/luci.ch"
    local lang_code="${1:-$INPUT_LANG}"

    debug_log "check_country received lang_code: '$lang_code'"

    if [ -z "$lang_code" ]; then
        debug_log "No language provided, defaulting to 'en'"
        lang_code="en"
    fi

    # `country.db` から `$4` の言語コードが一致する行を取得
    local country_data
    country_data=$(awk -v lang="$lang_code" '$4 == lang {print $0}' "$country_file")

    if [ -z "$country_data" ]; then
        debug_log "No matching country found for language: $lang_code"
        return
    fi

    echo "$country_data" > "$country_cache"
    echo "$lang_code" > "$luci_cache"
    debug_log "Country data saved to $country_cache -> $country_data"
    debug_log "Language saved to $luci_cache -> $lang_code"
}

OK_0210_check_country() {
    local country_file="${BASE_DIR}/country.db"
    local country_cache="${CACHE_DIR}/country.ch"
    local luci_cache="${CACHE_DIR}/luci.ch"
    local lang_code="${1:-$INPUT_LANG}"

    debug_log "check_country received lang_code: '$lang_code'"

    if [ -z "$lang_code" ]; then
        debug_log "No language provided, defaulting to 'en'"
        lang_code="en"
    fi

    # `country.db` から `$4` の言語コードが一致する行を取得
    local country_data
    country_data=$(awk -v lang="$lang_code" '$4 == lang {print $0}' "$country_file")

    if [ -z "$country_data" ]; then
        debug_log "No matching country found for language: $lang_code"
        return
    fi

    echo "$country_data" > "$country_cache"
    echo "$lang_code" > "$luci_cache"
    debug_log "Country data saved to $country_cache -> $country_data"
    debug_log "Language saved to $luci_cache -> $lang_code"
}

#########################################################################
# check_zone: 選択された国のゾーン情報を取得して zone.ch に保存
#########################################################################
check_zone() {
    local country_cache="${CACHE_DIR}/country.ch"
    local zone_cache="${CACHE_DIR}/zone.ch"
    
    local country_code
    country_code=$(awk '{print $4}' "$country_cache" 2>/dev/null | head -n 1)

    if [ -z "$country_code" ]; then
        debug_log "No country code found in country.ch, defaulting to 'US'"
        country_code="US"
    fi

    # `country.db` からゾーン情報を取得
    local zone_info
    zone_info=$(awk -v code="$country_code" '$4 == code {print $5, $6}' "${BASE_DIR}/country.db")

    if [ -z "$zone_info" ]; then
        debug_log "No timezone found for country: $country_code"
        return
    fi

    echo "$zone_info" > "$zone_cache"
    debug_log "Timezone data saved to $zone_cache -> $zone_info"
}

OK_0210_check_zone() {
    local country_cache="${CACHE_DIR}/country.ch"
    local zone_cache="${CACHE_DIR}/zone.ch"
    
    local country_code
    country_code=$(awk '{print $4}' "$country_cache" 2>/dev/null | head -n 1)

    if [ -z "$country_code" ]; then
        debug_log "No country code found in country.ch, defaulting to 'US'"
        country_code="US"
    fi

    # `country.db` からゾーン情報を取得
    local zone_info
    zone_info=$(awk -v code="$country_code" '$4 == code {print $5, $6}' "${BASE_DIR}/country.db")

    if [ -z "$zone_info" ]; then
        debug_log "No timezone found for country: $country_code"
        return
    fi

    echo "$zone_info" > "$zone_cache"
    debug_log "Timezone data saved to $zone_cache -> $zone_info"
}

#########################################################################
# update_country_cache
#########################################################################
update_country_cache() {
    echo "$selected_entry" > "$CACHE_DIR/country.ch"
    echo "$selected_zonename" > "$CACHE_DIR/luci.ch"
    echo "$selected_timezone" > "$CACHE_DIR/language.ch"
    echo "$selected_zonename $selected_timezone" > "$CACHE_DIR/zone.ch"
}

#########################################################################
# check_openwrt: OpenWrtのバージョンを確認し、サポートされているか検証する
#########################################################################
check_openwrt() {
    local version_file="${CACHE_DIR}/openwrt.ch"

    # キャッシュが存在する場合は利用
    if [ -f "$version_file" ]; then
        CURRENT_VERSION=$(cat "$version_file")
    else
        CURRENT_VERSION=$(awk -F"'" '/DISTRIB_RELEASE/ {print $2}' /etc/openwrt_release | cut -d'-' -f1)
        echo "$CURRENT_VERSION" > "$version_file"
    fi

    if grep -q "^$CURRENT_VERSION=" "${BASE_DIR}/openwrt.db"; then
        local db_entry=$(grep "^$CURRENT_VERSION=" "${BASE_DIR}/openwrt.db" | cut -d'=' -f2)
        PACKAGE_MANAGER=$(echo "$db_entry" | cut -d'|' -f1)
        VERSION_STATUS=$(echo "$db_entry" | cut -d'|' -f2)

        echo -e "$(color green "Version $CURRENT_VERSION is supported ($VERSION_STATUS)")"
    else
        handle_error "Unsupported OpenWrt version: $CURRENT_VERSION"
    fi
}

#########################################################################
# check_language: 言語キャッシュの確認および設定
# - `luci.ch` を参照し、適切な言語コード (ja, en, etc.) を取得
# - 存在しない場合、 `country.ch` から取得し、 `luci.ch` に保存
# - `message.db` に対応する言語があるか確認し、 `SELECTED_LANGUAGE` にセット
#########################################################################
check_language() {
    local luci_cache="${CACHE_DIR}/luci.ch"

    if [ -s "$luci_cache" ]; then
        echo "DEBUG: Using cached language from luci.ch -> $(cat $luci_cache)" | tee -a "$LOG_DIR/debug.log"
        return
    fi

    # `INPUT_LANG` を `luci.ch` に保存
    echo "$INPUT_LANG" > "$luci_cache"
    echo "DEBUG: Saved INPUT_LANG to luci.ch -> $INPUT_LANG" | tee -a "$LOG_DIR/debug.log"
}

#########################################################################
# 選択された国と言語の詳細情報を表示
#########################################################################
country_info() {
    local country_info_file="${BASE_DIR}/country.ch"
    local selected_language_code=$(cat "${BASE_DIR}/check_country")

    if [ -f "$country_info_file" ]; then
        grep -w "$selected_language_code" "$country_info_file"
    else
        echo -e "$(color red "Country information not found.")"
    fi
}

#########################################################################
# パッケージマネージャー判定関数（apk / opkg 対応）
#########################################################################
get_package_manager() {
    if [ -f "${BASE_DIR}/downloader_ch" ]; then
        PACKAGE_MANAGER=$(cat "${BASE_DIR}/downloader_ch")
    else
        # パッケージマネージャーの存在確認のみ
        if command -v apk >/dev/null 2>&1; then
            PACKAGE_MANAGER="apk"
        elif command -v opkg >/dev/null 2>&1; then
            PACKAGE_MANAGER="opkg"
        else
            handle_error "$(get_message 'no_package_manager_found' "$SELECTED_LANGUAGE")"
        fi
        echo "$PACKAGE_MANAGER" > "${BASE_DIR}/downloader_ch"
    fi
    echo -e "\033[1;32m$(get_message 'detected_package_manager' "$SELECTED_LANGUAGE"): $PACKAGE_MANAGER\033[0m"
}

#########################################################################
# get_message: 多言語対応メッセージ取得関数
# 引数: $1 = メッセージキー, $2 = 言語コード (オプション, デフォルトは 'ja')
#########################################################################
#########################################################################
# get_message: 多言語対応メッセージ取得関数
#########################################################################
get_message() {
    local key="$1"
    local lang="${SELECTED_LANGUAGE:-en}"
    local message_db="${BASE_DIR}/messages.db"

    if [ ! -f "$message_db" ]; then
        echo -e "$(color red "Message database not found. Defaulting to key: $key")"
        return
    fi

    local message
    message=$(grep "^${lang}|${key}=" "$message_db" | cut -d'=' -f2-)
    [ -z "$message" ] && message=$(grep "^en|${key}=" "$message_db" | cut -d'=' -f2-)

    if [ -n "$2" ]; then message=$(echo "$message" | sed -e "s/{file}/$2/"); fi
    if [ -n "$3" ]; then message=$(echo "$message" | sed -e "s/{version}/$3/"); fi
    if [ -n "$4" ]; then message=$(echo "$message" | sed -e "s/{status}/$4/"); fi

    if [ -z "$message" ]; then
        echo -e "$(color yellow "Message key not found in database: $key")"
        echo "$key"
    else
        echo "$message"
    fi
}

#########################################################################
# handle_exit: 正常終了メッセージを表示してスクリプトを終了する関数
# 引数: 終了時に表示するメッセージ
#########################################################################
handle_exit() {
    local message="$1"
    color yellow "$message"
    exit 0
}

#########################################################################
# install_packages: パッケージをインストールし、インストール済みならスキップ
#########################################################################
install_packages() {
    local confirm_flag="$1"
    shift
    local package_list="$@"
    local packages_to_install=""

    # インストール済みチェック
    for pkg in $package_list; do
        if command -v apk >/dev/null 2>&1; then
            if ! apk list-installed | grep -q "^$pkg "; then
                packages_to_install="$packages_to_install $pkg"
            fi
        elif command -v opkg >/dev/null 2>&1; then
            if ! opkg list-installed | grep -q "^$pkg "; then
                packages_to_install="$packages_to_install $pkg"
            fi
        fi
    done

    # インストール不要なら終了
    if [ -z "$packages_to_install" ]; then
        return 0
    fi

    # ✅ `yn` フラグがある場合のみ確認
    if [ "$confirm_flag" = "yn" ]; then
        echo -e "$(color cyan "Do you want to install: $packages_to_install? [Y/n]:")"
        read -r yn
        case "$yn" in
            [Yy]*) ;;
            [Nn]*) echo "$(color yellow "Skipping installation.")" ; return 1 ;;
            *) echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")" ;;
        esac
    fi

    # パッケージをインストール
    if command -v apk >/dev/null 2>&1; then
        apk add $packages_to_install
    elif command -v opkg >/dev/null 2>&1; then
        opkg install $packages_to_install
    fi

    echo "$(color green "Installed:$packages_to_install")"
}

#########################################################################
# attempt_package_install: 個別パッケージのインストールおよび言語パック適用
# 引数: インストールするパッケージ名
#########################################################################
attempt_package_install() {
    local package_name="$1"

    # 既にインストール済みならスキップ
    if $PACKAGE_MANAGER list-installed | grep -q "^$package_name "; then
        echo -e "$(color cyan "$package_name is already installed. Skipping...")"
        return
    fi

    if $PACKAGE_MANAGER list | grep -q "^$package_name - "; then
        $PACKAGE_MANAGER install $package_name && echo -e "$(color green "Successfully installed: $package_name")" || \
        echo -e "$(color yellow "Failed to install: $package_name. Continuing...")"

        # 言語パッケージの自動インストール
        install_language_pack "$package_name"
    else
        echo -e "$(color yellow "Package not found: $package_name. Skipping...")"
    fi
}

#########################################################################
# install_language_pack: 言語パッケージの存在確認とインストール
# 例: luci-app-ttyd → luci-i18n-ttyd-ja (存在すればインストール)
#########################################################################
install_language_pack() {
    local base_pkg="$1"
    local lang_pkg="luci-i18n-${base_pkg#luci-app-}-${SELECTED_LANGUAGE}"

    # 言語コード (`ja`, `en` など) をダウンロードしないよう防ぐ
    if echo "$base_pkg" | grep -qE '^(en|ja|zh-cn|zh-tw|id|ko|de|ru)$'; then
        echo "DEBUG: Skipping language pack installation for language code: $base_pkg"
        return
    fi

    # `packages.db` から言語パッケージがあるか確認
    if grep -q "^packages=" "${BASE_DIR}/packages.db"; then
        local available_pkgs
        available_pkgs=$(grep "^packages=" "${BASE_DIR}/packages.db" | cut -d'=' -f2)

        if echo "$available_pkgs" | grep -qw "$lang_pkg"; then
            $PACKAGE_MANAGER install "$lang_pkg"
            echo "$(color green "Installed language pack: $lang_pkg")"
        else
            echo "$(color yellow "Language pack not available in packages.db: $lang_pkg")"
        fi
    else
        echo "$(color yellow "packages.db not found or invalid. Skipping language pack installation.")"
    fi
}

#########################################################################
# check_common: 初期化処理
# - `--reset`, `-reset`, `-r` でキャッシュリセット
# - `--help`, `-help`, `-h` でヘルプ表示
# - 言語 (`INPUT_LANG`) を `SELECT_COUNTRY` に渡す
# - `full` (通常モード), `light` (最低限モード) の選択
#########################################################################
check_common() {
    local mode="$1"
    shift  # 最初の引数 (モード) を削除

    local RESET_CACHE=false
    local SHOW_HELP=false
    local lang_code="${1:-$INPUT_LANG}"  # ✅ $1 があれば使用、なければ環境変数 INPUT_LANG を使う

    debug_log "check_common received lang_code: '$lang_code'"

    # 引数解析
    for arg in "$@"; do
        case "$arg" in
            -reset|--reset|-r)
                RESET_CACHE=true
                ;;
            -help|--help|-h)
                SHOW_HELP=true
                ;;
            -debug|--debug|-d)
                DEBUG_MODE=true
                ;;
        esac
    done

    if [ "$RESET_CACHE" = true ]; then
        reset_cache
    fi

    if [ "$SHOW_HELP" = true ]; then
        print_help
        exit 0
    fi

    case "$mode" in
        full)      
            script_update || handle_error "ERR_SCRIPT_UPDATE" "script_update" "latest"
            download_script messages.db || handle_error "ERR_DOWNLOAD" "messages.db" "latest"
            download_script country.db || handle_error "ERR_DOWNLOAD" "country.db" "latest"
            download_script openwrt.db || handle_error "ERR_DOWNLOAD" "openwrt.db" "latest"
            check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
            check_country "$lang_code" || handle_error "ERR_COUNTRY_CHECK" "check_country" "latest"
            check_zone "$(cat "$CACHE_DIR/language.ch" 2>/dev/null || echo "US")"
            normalize_country || handle_error "ERR_NORMALIZE" "normalize_country" "latest"
            ;;
        light)
            check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
            check_country "$lang_code" || handle_error "ERR_COUNTRY_CHECK" "check_country" "latest"
            check_zone "$(cat "$CACHE_DIR/language.ch" 2>/dev/null || echo "US")"
            normalize_country || handle_error "ERR_NORMALIZE" "normalize_country" "latest"
            ;;
        *)
            check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
            check_country "$lang_code" || handle_error "ERR_COUNTRY_CHECK" "check_country" "latest"
            check_zone "$(cat "$CACHE_DIR/language.ch" 2>/dev/null || echo "US")"
            normalize_country || handle_error "ERR_NORMALIZE" "normalize_country" "latest"
            ;;
    esac
}
