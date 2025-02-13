#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important! OpenWrt OS only works with Almquist Shell, not Bourne-again shell.
# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

COMMON_VERSION="2025.02.13-1-5"

# 基本定数の設定
BASE_WGET="wget --quiet -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
mkdir -p "$CACHE_DIR" "$LOG_DIR"
DEBUG_MODE="${DEBUG_MODE:-false}"
   
script_update() (
    COMMON_CACHE="${CACHE_DIR}/common_version.ch"
    # キャッシュが存在しない、またはバージョンが異なる場合にアラートを表示
    if [ ! -f "$COMMON_CACHE" ] || [ "$(cat "$COMMON_CACHE" | tr -d '\r\n')" != "$COMMON_VERSION" ]; then
        echo -e "`color white_black "common.sh Updated to version $COMMON_VERSION"`"
        echo "$COMMON_VERSION" > "$COMMON_CACHE"
    fi
)

#########################################################################
# debug_log: デバッグ出力関数
#########################################################################
debug_log() {
    local message="$1"
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: $message" | tee -a "$LOG_DIR/debug.log"
}

# 環境変数 INPUT_LANG のチェック（デフォルト 'ja' とする）
INPUT_LANG="${INPUT_LANG:-ja}"
debug_log "common.sh received INPUT_LANG: '$INPUT_LANG'"

#########################################################################
# テスト用関数: データ取得を個別に確認
#########################################################################
test_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG: Running debug tests..." | tee -a "$LOG_DIR/debug.log"
        if [ ! -f "${BASE_DIR}/country.db" ]; then
            echo "DEBUG: ERROR - country.db not found!" | tee -a "$LOG_DIR/debug.log"
        else
            echo "DEBUG: country.db found at ${BASE_DIR}/country.db" | tee -a "$LOG_DIR/debug.log"
        fi

        test_country_search "US"
        test_country_search "Japan"
        test_timezone_search "US"
        test_timezone_search "JP"
        test_cache_contents
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
    echo "  sh aios.sh full ja       # Run in full mode with language set to Japanese"
    echo "  sh aios.sh full          # If language cache exists, use it; otherwise, prompt for language"
}

#########################################################################
# color: ANSI エスケープシーケンスを使って色付きメッセージを出力する関数
#########################################################################
color() {
    local color_code
    color_code=$(color_code_map "$1")
    shift
    echo -e "${color_code}$*$(color_code_map "reset")"
}

#########################################################################
# color_code_map: カラー名から ANSI エスケープシーケンスを返す関数
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



# 🔵　ランゲージ系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# Last Update: 2025-02-12 16:12:39 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
#########################################################################
# selection_list()
# 選択リストを作成し、選択結果をファイルに保存する関数。
#
# 【要件】
# 1. `mode=country`:
#     - 国リストを `$2 $3 $4 $5`（国名・言語・言語コード・国コード）で表示
#     - `$6` 以降（ゾーンネーム・タイムゾーン）は **`zone_list_tmp.ch` に保存**
# 2. `mode=zone`:
#     - ゾーンリストを表示
#     - **ゾーン情報の保存は `select_zone()` に任せる**
# 3. その他:
#     - 入力データが空ならエラーを返す
#     - 選択後に `Y/N` で確認
#########################################################################
selection_list() {
    local input_data="$1"
    local output_file="$2"
    local mode="$3"
    local list_file="${CACHE_DIR}/zone_tmp.ch"
    local i=1

    echo -n "" > "$list_file"
    debug_log "DEBUG: input_data='$input_data'"

    echo "[0] Cancel / back to return"
    if [ "$mode" = "country" ]; then
        echo "$input_data" | while IFS= read -r line; do
            local extracted=$(echo "$line" | awk '{print $2, $3, $4, $5}')  # ✅ `$2-$5` のみ表示
            if [ -n "$extracted" ]; then
                echo "[$i] $extracted"
                echo "$i $line" >> "$list_file"
                i=$((i + 1))
            fi
        done
    elif [ "$mode" = "zone" ]; then
        echo "$input_data" | while IFS= read -r zone; do
            if [ -n "$zone" ]; then
                echo "[$i] $zone"
                echo "$i $zone" >> "$list_file"
                i=$((i + 1))
            fi
        done
    fi

    local choice=""
    while true; do
        echo -n "$(color cyan "Enter the number of your choice: ")"
        read choice
        if [ "$choice" = "0" ]; then
            echo "$(color yellow "Returning to previous menu.")"
            return
        fi
        local selected_value=$(awk -v num="$choice" '$1 == num {print $2, $3, $4, $5}' "$list_file")  # ✅ `$2-$5` のみ取得
        if [ -z "$selected_value" ]; then
            echo "$(color red "Invalid selection. Please choose a valid number.")"
            continue
        fi
        
        echo "$(color cyan "Confirm selection: [$choice] $selected_value")" 
        echo -n "(Y/n)?: "
        read yn
        case "$yn" in
            [Yy]*)
                printf "%s\n" "$selected_value" > "$output_file" 
                return
                ;;
            [Nn]*)
                echo "$(color yellow "Returning to selection.")"
                ;;
            *)
                echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")"
                ;;
        esac
    done
}

#########################################################################
# Last Update: 2025-02-12 17:25:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# select_country: ユーザーに国の選択を促す（検索機能付き）
#
# 【要件】
# 1. 役割:
#    - 言語処理の入口として `$1` または `language.ch` を判定
#    - `$1` が指定されている場合は最優先で処理
#    - キャッシュ (`language.ch`) がある場合は、それを使用
#    - どちらも無い場合、手動で選択させる
#
# 2. キャッシュ処理:
#    - `language.ch` が存在する場合、それを使用し `normalize_country()` へ
#    - キャッシュが無い場合、手動入力を求める
#
# 3. 言語コードの処理:
#    - `$1` が `SUPPORTED_LANGUAGES` に含まれているかを確認
#    - 含まれていなければ、手動で言語を選択させる
#    - 選択後、キャッシュ (`language.ch`) に保存
#
# 4. フロー:
#    - 言語の決定 → `normalize_country()` に進む
#
# 5. メンテナンス:
#    - `language.ch` は一度書き込んだら変更しない
#    - 言語の決定はすべて `select_country()` 内で完結させる
#    - `normalize_country()` ではキャッシュを上書きしない
#########################################################################
select_country() {
    debug_log "=== Entering select_country() ==="

    local cache_country="${CACHE_DIR}/country.ch"
    local cache_language="${CACHE_DIR}/language.ch"
    local tmp_country="${CACHE_DIR}/country_tmp.ch"

    if [ -f "$cache_country" ] && [ -f "$cache_language" ]; then
        debug_log "Using cached country and language. Skipping selection."
        return
    fi

    echo "$(color cyan "Enter country name, code, or language to search:")"
    read input

    if [ -z "$input" ]; then
        echo "$(color red "No input provided. Please enter a country code or name.")"
        select_country
        return
    fi

    search_results=$(awk -v search="$input" '
        BEGIN {IGNORECASE=1}
        $2 ~ search || $3 ~ search || $4 ~ search || $5 ~ search {print $0}
    ' "$BASE_DIR/country.db")

    if [ -z "$search_results" ]; then
        echo "$(color red "No matching country found. Please try again.")"
        select_country
        return
    fi

    debug_log "DEBUG: search_results content -> $(echo "$search_results" | tr '\n' ';')"

    echo "$(color cyan "Select your country from the following options:")"
    selection_list "$search_results" "$tmp_country" "country"

    debug_log "DEBUG: country_tmp.ch content AFTER selection -> $(cat "$tmp_country" 2>/dev/null)"

    # ✅ `country_tmp.ch` のデータを `country_write()` に渡す
    if [ -s "$tmp_country" ]; then
        country_write "$(cat "$tmp_country")"
    else
        debug_log "DEBUG: tmp_country is empty! Retrying select_country()"
        select_country
    fi
}

#########################################################################
# Last Update: 2025-02-12 17:25:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# country_write: 選択された国をキャッシュに保存
#########################################################################
country_write() {
    local selected_line="$1"

    debug_log "DEBUG: country_write() received line -> $selected_line"

    # ✅ `country.ch` に該当行を **丸ごと** 保存（データの基準）
    echo "$selected_line" > "$CACHE_DIR/country.ch"
    debug_log "DEBUG: country.ch updated with -> $(cat "$CACHE_DIR/country.ch" 2>/dev/null)"

    # ✅ `language.ch` に `$5`（国コード）を保存
    echo "$selected_line" | awk '{print $5}' > "$CACHE_DIR/language.ch"
    debug_log "DEBUG: language.ch updated -> $(cat "$CACHE_DIR/language.ch" 2>/dev/null)"

    # ✅ `luci.ch` に `$4`（言語コード）を保存
    echo "$selected_line" | awk '{print $4}' > "$CACHE_DIR/luci.ch"
    debug_log "DEBUG: luci.ch updated -> $(cat "$CACHE_DIR/luci.ch" 2>/dev/null)"

    # ✅ `country_tmp.ch`（国情報）を作成（$1-$5）
    echo "$selected_line" | awk '{print $1, $2, $3, $4, $5}' > "$CACHE_DIR/country_tmp.ch"
    debug_log "DEBUG: country_tmp.ch created -> $(cat "$CACHE_DIR/country_tmp.ch" 2>/dev/null)"

    # ✅ `zone_tmp.ch`（ゾーン情報）を作成（$6-）
    echo "$selected_line" | cut -d' ' -f6- > "$CACHE_DIR/zone_tmp.ch"
    debug_log "DEBUG: zone_tmp.ch content AFTER extraction -> $(cat "$CACHE_DIR/zone_tmp.ch" 2>/dev/null)"

    # ✅ `zone_tmp.ch` にデータがあれば `select_zone()` に進む
    if [ -s "$CACHE_DIR/zone_tmp.ch" ] && grep -q '[^[:space:]]' "$CACHE_DIR/zone_tmp.ch"; then
        select_zone
    else
        echo "$(color red "No timezone data found for this country.")"
        debug_log "ERROR: No timezone data found for selected country."
    fi
}
#########################################################################
# Last Update: 2025-02-12 17:25:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path.""
# select_zone: 選択した国に対応するタイムゾーンを選択
#########################################################################
select_zone() {
    debug_log "=== Entering select_zone() ==="
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_zone="${CACHE_DIR}/zone_tmp.ch"

    local zone_info=$(awk '{for(i=6; i<=NF; i++) print $i}' "$cache_country")
    echo "$zone_info" > "$cache_zone"

    if [ "$DEBUG_MODE" = "true" ]; then
        debug_log "DEBUG: zone_tmp.ch content AFTER extraction ->"
        cat "$cache_zone"
    fi

    if [ -z "$zone_info" ]; then
        echo "$(color red "ERROR: No timezone data found. Please reselect your country.")"
        select_country
        return
    fi

    echo "$(color cyan "Select your timezone from the following options:")"
    selection_list "$zone_info" "$cache_zone" "zone"

    if [ -s "$cache_zone" ]; then
        local selected_zone=$(cat "$cache_zone")
        echo "$(color cyan "Confirm selection: $selected_zone")"
    fi

    debug_log "DEBUG: Final selection -> $(cat "$cache_zone")"
}

#########################################################################
# Last Update: 2025-02-12 17:10:05 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# normalize_country: 言語設定の正規化
#
# 【要件】
# 1. 言語の決定:
#    - `language.ch` を最優先で参照（変更不可）
#    - `language.ch` が無い場合は `select_country()` を実行し、手動選択
#
# 2. システムメッセージの言語 (`message.ch`) の確定:
#    - `message.db` の `SUPPORTED_LANGUAGES` を確認
#    - `language.ch` に記録された言語が `SUPPORTED_LANGUAGES` にあれば、それを `message.ch` に保存
#    - `SUPPORTED_LANGUAGES` に無い場合、`message.ch` に `en` を設定
#
# 3. `language.ch` との関係:
#    - `language.ch` はデバイス設定用（変更不可）
#    - `message.ch` はシステムメッセージ表示用（フォールバック可能）
#
# 4. メンテナンス:
#    - `language.ch` はどのような場合でも変更しない
#    - `message.ch` のみフォールバックを適用し、システムメッセージの一貫性を維持
#    - 言語設定に影響を与えず、メッセージの表示のみを制御する
#########################################################################
normalize_country() {
    local message_db="${BASE_DIR}/messages.db"
    local language_cache="${CACHE_DIR}/language.ch"
    local message_cache="${CACHE_DIR}/message.ch"
    local tmp_country="${CACHE_DIR}/country_tmp.ch"
    local selected_language=""

    if [ -f "$tmp_country" ]; then
        selected_language=$(awk '{print $4}' "$tmp_country")
        debug_log "Loaded language from country_tmp.ch -> $selected_language"
    else
        debug_log "No country_tmp.ch found. Selecting manually."
        select_country
        return
    fi

    debug_log "DEBUG: Selected language before validation -> $selected_language"

    local supported_languages=$(grep "^SUPPORTED_LANGUAGES=" "$message_db" | cut -d'=' -f2 | tr -d '"')

    if echo "$supported_languages" | grep -qw "$selected_language"; then
        debug_log "Using message database language: $selected_language"
        echo "$selected_language" > "$message_cache"
    else
        debug_log "Language '$selected_language' not found in messages.db. Using 'en' for system messages."
        echo "en" > "$message_cache"
    fi

    debug_log "Final system message language -> $(cat "$message_cache")"
}

# 🔴　ランゲージ系　ここまで　-------------------------------------------------------------------------------------------------------------------------------------------

#########################################################################
# download_script: 指定されたスクリプト・データベースのバージョン確認とダウンロード
#########################################################################
download_script() {
    local file_name="$1"
    local script_cache="${BASE_DIR}/script.ch"
    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"

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
# download: 汎用ファイルダウンロード関数
#########################################################################
download() {
    local file_url="$1"
    local destination="$2"
    if ! confirm "MSG_DOWNLOAD_CONFIRM" "$file_url"; then
        echo -e "$(color yellow "Skipping download of $file_url")"
        return 0
    fi
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
# messages_db: メッセージデータベースのダウンロード
#########################################################################
messages_db() {
    if [ ! -f "${BASE_DIR}/messages.db" ]; then
        echo -e "$(color yellow "Downloading messages.db...")"
        if ! ${BASE_WGET} "${BASE_DIR}/messages.db" "${BASE_URL}/messages.db"; then
            echo -e "$(color red "Failed to download messages.db")"
            return 1
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
# confirm: Y/N 確認関数
#########################################################################
confirm() {
    local key="$1"
    local replace_param1="$2"
    local replace_param2="$3"
    local prompt_message
    prompt_message=$(get_message "$key" "$SELECTED_LANGUAGE")
    [ -n "$replace_param1" ] && prompt_message=$(echo "$prompt_message" | sed "s/{pkg}/$replace_param1/g")
    [ -n "$replace_param2" ] && prompt_message=$(echo "$prompt_message" | sed "s/{version}/$replace_param2/g")
    echo "DEBUG: Confirm message -> [$prompt_message]"
    while true; do
        read -r -p "$prompt_message " confirm
        confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
        case "$confirm" in
            ""|"y"|"yes") return 0 ;;
            "n"|"no") return 1 ;;
            *) echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")" ;;
        esac
    done
}

#########################################################################
# check_openwrt: OpenWrtのバージョン確認・検証
#########################################################################
check_openwrt() {
    local version_file="${CACHE_DIR}/openwrt.ch"
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
# country_info: 選択された国と言語の詳細情報を表示
#########################################################################
country_info() {
    local country_info_file="${BASE_DIR}/country.ch"
    local selected_language_code=$(cat "${BASE_DIR}/check_country")
    if [ -f "$country_info_file" ]; then
        grep -w "$selected_language_code" "$country_info_file"
    else
        printf "%s\n" "$(color red "Country information not found.")"
    fi
}

#########################################################################
# get_package_manager: パッケージマネージャー判定（apk / opkg 対応）
#########################################################################
get_package_manager() {
    if [ -f "${BASE_DIR}/downloader_ch" ]; then
        PACKAGE_MANAGER=$(cat "${BASE_DIR}/downloader_ch")
    else
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
# Last Update: 2025-02-12 14:35:26 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path." 
# get_message: 多言語対応メッセージ取得関数
#
# 【要件】
# 1. 言語の決定:
#    - `message.ch` を最優先で参照する（normalize_country() により確定）
#    - `message.ch` が無ければデフォルト `en`
#
# 2. メッセージ取得の流れ:
#    - `messages.db` から `message.ch` に記録された言語のメッセージを取得
#    - 該当するメッセージが `messages.db` に無い場合、`en` にフォールバック
#    - `en` にも無い場合は、キー（`$1`）をそのまま返す
#
# 3. `language.ch` との関係:
#    - `language.ch` はデバイス設定用（変更不可）
#    - `message.ch` はシステムメッセージ表示用（フォールバック可能）
#
# 4. メンテナンス:
#    - 言語設定に影響を与えず、メッセージのみ `message.ch` で管理
#    - `normalize_country()` で `message.ch` が決定されるため、変更は `normalize_country()` 側で行う
#########################################################################
get_message() {
    local key="$1"
    local message_cache="${CACHE_DIR}/message.ch"
    local lang="en"  # デフォルト `en` にするが `message.ch` を優先

    # ✅ `message.ch` があれば、それを使用
    if [ -f "$message_cache" ]; then
        lang=$(cat "$message_cache")
    fi

    local message_db="${BASE_DIR}/messages.db"

    # ✅ `messages.db` から `lang` に対応するメッセージを取得
    local message
    message=$(grep "^${lang}|${key}=" "$message_db" | cut -d'=' -f2-)

    # ✅ `lang` に該当するメッセージが無い場合は `en` を参照
    if [ -z "$message" ]; then
        message=$(grep "^en|${key}=" "$message_db" | cut -d'=' -f2-)
    fi

    # ✅ `message.db` にも無い場合はキーをそのまま返す
    if [ -z "$message" ]; then
        debug_log "Message key '$key' not found in messages.db."
        echo "$key"
    else
        echo "$message"
    fi
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
    error_message=$(echo "$error_message" | sed -e "s/{file}/$file/" -e "s/{version}/$version/")
    echo -e "$(color red "$error_message")"
    return 1
}

#########################################################################
# handle_exit: 正常終了メッセージを表示して終了
#########################################################################
handle_exit() {
    local message="$1"
    color yellow "$message"
    exit 0
}

#########################################################################
# install_packages: パッケージのインストール（既にインストール済みならスキップ）
#########################################################################
install_packages() {
    local confirm_flag="$1"
    shift
    local package_list="$@"
    local packages_to_install=""
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
    if [ -z "$packages_to_install" ]; then
        return 0
    fi
    if [ "$confirm_flag" = "yn" ]; then
        echo -e "$(color cyan "Do you want to install: $packages_to_install? [Y/n]:")"
        read -r yn
        case "$yn" in
            [Yy]*) ;;
            [Nn]*) echo "$(color yellow "Skipping installation.")" ; return 1 ;;
            *) echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")" ;;
        esac
    fi
    if command -v apk >/dev/null 2>&1; then
        apk add $packages_to_install
    elif command -v opkg >/dev/null 2>&1; then
        opkg install $packages_to_install
    fi
    echo "$(color green "Installed:$packages_to_install")"
}

#########################################################################
# attempt_package_install: 個別パッケージのインストールと、言語パック適用
#########################################################################
attempt_package_install() {
    local package_name="$1"
    if $PACKAGE_MANAGER list-installed | grep -q "^$package_name "; then
        echo -e "$(color cyan "$package_name is already installed. Skipping...")"
        return
    fi
    if $PACKAGE_MANAGER list | grep -q "^$package_name - "; then
        $PACKAGE_MANAGER install $package_name && echo -e "$(color green "Successfully installed: $package_name")" || \
        echo -e "$(color yellow "Failed to install: $package_name. Continuing...")"
        install_language_pack "$package_name"
    else
        echo -e "$(color yellow "Package not found: $package_name. Skipping...")"
    fi
}

#########################################################################
# install_language_pack: 言語パッケージの確認とインストール
#########################################################################
install_language_pack() {
    local base_pkg="$1"
    local lang_pkg="luci-i18n-${base_pkg#luci-app-}-${SELECTED_LANGUAGE}"
    if echo "$base_pkg" | grep -qE '^(en|ja|zh-cn|zh-tw|id|ko|de|ru)$'; then
        echo "DEBUG: Skipping language pack installation for language code: $base_pkg"
        return
    fi
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
# Last Update: 2025-02-12 14:35:26 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path." 
# check_common: 共通処理の初期化
#
# 【要件】
# 1. 役割:
#    - `common.sh` のフロー制御を行う
#    - `select_country()` に言語処理を委ねる（言語処理はここでは行わない）
#
# 2. フロー:
#    - 第一引数 (`$1`) は動作モード（例: full, light）
#    - 第二引数 (`$2`) は言語コード（あれば `select_country()` に渡す）
#    - `$2` が無い場合、`select_country()` によって処理を継続
#
# 3. キャッシュ処理:
#    - 言語キャッシュ (`language.ch`) の有無を `select_country()` に判定させる
#    - キャッシュがある場合は `normalize_country()` に進む
#
# 4. 追加オプション処理:
#    - `-reset` フラグが指定された場合、キャッシュをリセット
#    - `-help` フラグが指定された場合、ヘルプメッセージを表示して終了
#
# 5. メンテナンス:
#    - `check_common()` は **フロー制御のみ** を行う
#    - 言語の選択やキャッシュ管理は **`select_country()` に委ねる**
#    - 将来的にフローが変更される場合は、ここを修正する
#########################################################################
check_common() {
    local mode="$1"
    shift  # 最初の引数 (モード) を削除
    
    local lang_code="${2:-}"

    SELECTED_LANGUAGE="$lang_code"
    debug_log "check_common received lang_code: '$lang_code'"

    local RESET_CACHE=false
    local SHOW_HELP=false
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
            select_country "$lang_code"
            ;;
        light)
            script_update || handle_error "ERR_SCRIPT_UPDATE" "script_update" "latest"
            download_script messages.db || handle_error "ERR_DOWNLOAD" "messages.db" "latest"
            download_script country.db || handle_error "ERR_DOWNLOAD" "country.db" "latest"
            download_script openwrt.db || handle_error "ERR_DOWNLOAD" "openwrt.db" "latest"
            check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
            select_country "$lang_code"
            ;;
        *)
            script_update || handle_error "ERR_SCRIPT_UPDATE" "script_update" "latest"
            download_script messages.db || handle_error "ERR_DOWNLOAD" "messages.db" "latest"
            download_script country.db || handle_error "ERR_DOWNLOAD" "country.db" "latest"
            download_script openwrt.db || handle_error "ERR_DOWNLOAD" "openwrt.db" "latest"
            check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
            select_country "$lang_code"
            ;;
    esac
}
