#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important!　OpenWrt OS only works with Almquist Shell, not Bourne-again shell.
# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

COMMON_VERSION="2025.02.10-1-15"
 
# 基本定数の設定
# BASE_WGET="wget -O" # テスト用
BASE_WGET="wget --quiet -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-${BASE_DIR}/cache}"; mkdir -p "$CACHE_DIR"
LOG_DIR="${LOG_DIR:-${BASE_DIR}/logs}"; mkdir -p "$LOG_DIR"
#SUPPORTED_VERSIONS="${SUPPORTED_VERSIONS:-19.07 21.02 22.03 23.05 24.10.0 SNAPSHOT}"
#SUPPORTED_LANGUAGES="${SUPPORTED_LANGUAGES:-en ja"
INPUT_LANG="$1"


script_update() (
COMMON_CACHE="${BASE_DIR}/common_version.ch"
# **キャッシュが存在しない、またはバージョンが異なる場合にアラートを表示**
if [ ! -f "$COMMON_CACHE" ] || [ "$(cat "$COMMON_CACHE" | tr -d '\r\n')" != "$COMMON_VERSION" ]; then
    echo "`color white_black "Updated to version $COMMON_VERSION"`"
    echo "$COMMON_VERSION" > "$COMMON_CACHE"
fi
)

# -------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# テスト用関数: データ取得を個別に確認
#########################################################################

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
    local lang_code=""
    local default_lang="en"
    local messages_db="$BASE_DIR/messages.db"

    # **`luci.ch` の確認**
    if [ -s "$CACHE_DIR/luci.ch" ]; then
        lang_code=$(cat "$CACHE_DIR/luci.ch")
        echo "DEBUG: Using cached language from luci.ch -> $lang_code" | tee -a "$LOG_DIR/debug.log"
    else
        # **country.ch から言語コードを取得**
        if [ -s "$CACHE_DIR/country.ch" ]; then
            lang_code=$(awk '{print $3}' "$CACHE_DIR/country.ch" | grep -m 1 '^[a-z][a-z]$')
        fi

        # **取得できない場合デフォルト `en`**
        if [ -z "$lang_code" ]; then
            lang_code="$default_lang"
            echo "DEBUG: No language found in country.ch, defaulting to '$lang_code'." | tee -a "$LOG_DIR/debug.log"
        fi

        echo "$lang_code" > "$CACHE_DIR/luci.ch"
    fi

    # **`messages.db` の存在確認**
    if [ ! -f "$messages_db" ]; then
        echo "DEBUG: messages.db not found! Downloading..." | tee -a "$LOG_DIR/debug.log"
        download_script messages.db
        sleep 1  # 確実にダウンロードが終わるまで待つ
    fi

    # **messages.db の言語チェック**
    if ! grep -q "^$lang_code|" "$messages_db"; then
        echo "DEBUG: Language '$lang_code' not found in messages.db. Using default 'en'." | tee -a "$LOG_DIR/debug.log"
        echo "en" > "$CACHE_DIR/luci.ch"
    fi
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
handle_error() {
    local message_key="$1"
    local file="$2"
    local version="$3"

    local error_message
    error_message=$(get_message "$message_key")

    # {file} や {version} の置換処理
    error_message=$(echo "$error_message" | sed -e "s/{file}/$file/" -e "s/{version}/$version/")

    echo -e "$(color red "$error_message")"
    exit 1
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
# normalize_country
#########################################################################
normalize_country() {
    local message_db="${BASE_DIR}/messages.db"
    local language_cache="${BASE_DIR}/luci.ch"

    # `luci.ch` から言語コードを取得
    if [ -f "$language_cache" ]; then
        SELECTED_LANGUAGE=$(cat "$language_cache")
        echo "DEBUG: Loaded language from luci.ch -> $SELECTED_LANGUAGE"
    else
        SELECTED_LANGUAGE="en"
        echo "DEBUG: No luci.ch found, defaulting to 'en'"
    fi

    # `message.db` に `SELECTED_LANGUAGE` があるか確認
    if grep -q "^$SELECTED_LANGUAGE|" "$message_db"; then
        echo "`color green "Using message database language: $SELECTED_LANGUAGE"`"
    else
        SELECTED_LANGUAGE="en"
        echo "`color yellow "Language not found in messages.db. Using: en"`"
    fi

    echo "DEBUG: Final language after normalization -> $SELECTED_LANGUAGE"
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
# check_country: 国コードを `language.ch` に書き込む
#########################################################################
check_country() {
    local country_code=""

    if [ -s "$CACHE_DIR/country.ch" ]; then
        country_code=$(awk '{print $4}' "$CACHE_DIR/country.ch" | head -n 1)
    else
        country_code=$(awk '{print $4}' "$BASE_DIR/country.db" | grep -m 1 '^[A-Z][A-Z]$')
    fi

    if [ -n "$country_code" ]; then
        echo "$country_code" > "$CACHE_DIR/language.ch"
        echo "DEBUG: Country code set to '$country_code'." | tee -a "$LOG_DIR/debug.log"
    else
        echo "DEBUG: No valid country code found, defaulting to 'US'." | tee -a "$LOG_DIR/debug.log"
        echo "US" > "$CACHE_DIR/language.ch"
    fi
}

#########################################################################
# check_zone: 選択された国のゾーン情報を取得して zone.ch に保存
#########################################################################
check_zone() {
    local country_code="$1"
    local country_file="${BASE_DIR}/country.db"
    local zone_cache="${CACHE_DIR}/zone.ch"

    if [ -z "$country_code" ]; then
        echo "DEBUG: No country code provided to check_zone()"
        return 1
    fi

    # **データベースからゾーン情報を検索**
    local zone_data
    zone_data=$(awk -v code="$country_code" '$4 == code {print $5, $6}' "$country_file")

    if [ -z "$zone_data" ]; then
        echo "DEBUG: No timezone found for country: $country_code"
        return 1
    fi

    # **zone.ch に保存**
    echo "$zone_data" > "$zone_cache"
    echo "DEBUG: zone.ch updated -> $(cat "$zone_cache")"
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
    local version_file="${BASE_DIR}/openwrt.ch"

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
    local language_cache="${CACHE_DIR}/luci.ch"
    local country_cache="${CACHE_DIR}/country.ch"
    local message_db="${BASE_DIR}/messages.db"

    # `luci.ch` が存在する場合、それを使用
    if [ -f "$language_cache" ]; then
        SELECTED_LANGUAGE=$(cat "$language_cache")
        echo "DEBUG: Using cached language from luci.ch -> $SELECTED_LANGUAGE"
    else
        # `country.ch` から言語コード (3列目) を取得し、`luci.ch` に保存
        if [ -f "$country_cache" ]; then
            SELECTED_LANGUAGE=$(awk '{print $3}' "$country_cache")
            echo "$SELECTED_LANGUAGE" > "$language_cache"
            echo "DEBUG: Language set from country.ch -> $SELECTED_LANGUAGE"
        else
            SELECTED_LANGUAGE="en"
            echo "$SELECTED_LANGUAGE" > "$language_cache"
            echo "DEBUG: No language found. Defaulting to 'en'."
        fi
    fi

    # `message.db` に `SELECTED_LANGUAGE` があるか確認
    if grep -q "^$SELECTED_LANGUAGE|" "$message_db"; then
        echo "DEBUG: Using message database language -> $SELECTED_LANGUAGE"
    else
        SELECTED_LANGUAGE="en"
        echo "DEBUG: Language not found in messages.db. Using: en"
    fi
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
    local DEBUG=false
    local INPUT_LANG=""
    
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
                DEBUG=true
                ;;
            *)
                INPUT_LANG="$arg"
                ;;
        esac
    done

    # キャッシュリセット処理
    if [ "$RESET_CACHE" = true ]; then
        reset_cache
    fi

    # ヘルプ表示
    if [ "$SHOW_HELP" = true ]; then
        print_help
        exit 0
    fi

    # **`luci.ch` のチェックを先に行う**
    check_language

    # **デバッグモード**
    if [ "$DEBUG" = true ]; then
        echo "DEBUG: Running in debug mode..." | tee -a "$LOG_DIR/debug.log"

        read -p "何かキーを押してください"
        
        check_language "ja"
        check_country "JP"
        check_zone "JP"

        # TEST 
        test_country_search "US"
        test_country_search "Japan"
        test_timezone_search "US"  # "United_States" → "US"
        test_timezone_search "JP"  # "Japan" → "JP"
        test_cache_contents

        
        # **キャッシュデータの出力**
        echo "DEBUG: luci.ch content: $(cat "$CACHE_DIR/luci.ch" 2>/dev/null || echo "en")" | tee -a "$LOG_DIR/debug.log"
        echo "DEBUG: country.ch content: $(cat "$CACHE_DIR/country.ch" 2>/dev/null || echo "No country data")" | tee -a "$LOG_DIR/debug.log"
        echo "DEBUG: language.ch content: $(cat "$CACHE_DIR/language.ch" 2>/dev/null || echo "No language data")" | tee -a "$LOG_DIR/debug.log"
        echo "DEBUG: zone.ch content: $(cat "$CACHE_DIR/zone.ch" 2>/dev/null || echo "No zone data")" | tee -a "$LOG_DIR/debug.log"
        exit 0
    fi
    
   case "$mode" in
    full)      
        script_update
        download_script messages.db
        download_script country.db
        download_script openwrt.db
        check_openwrt
        check_country
        check_language  # 🔴 修正： 言語チェックの位置を修正
        check_zone "$(cat "$CACHE_DIR/language.ch" 2>/dev/null || echo "US")"
        normalize_country  
        ;;
    light)
        check_openwrt
        check_country
        check_language  # 🔴 修正
        check_zone "$(cat "$CACHE_DIR/language.ch" 2>/dev/null || echo "US")"
        normalize_country  
        ;;
    *)
        check_openwrt
        check_country
        check_language  # 🔴 修正
        check_zone "$(cat "$CACHE_DIR/language.ch" 2>/dev/null || echo "US")"
        normalize_country  
        ;;
esac

}
