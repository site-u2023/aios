#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important! OpenWrt OS only works with Almquist Shell, not Bourne-again shell.
# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

COMMON_VERSION="2025.02.12-1-3"

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


# 🔵　ランゲージ系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# selection_list: リストから選択させる処理
#########################################################################
selection_list() {
    local input_data="$1"
    local output_file="$2"
    local mode="$3"
    local list_file="${CACHE_DIR}/tmp_list.ch"
    local i=1

    echo -n "" > "$list_file"
    debug_log "DEBUG: input_data='$input_data'"

    echo "[0] Cancel / back to return"
    if [ "$mode" = "country" ]; then
        echo "$input_data" | while IFS= read -r line; do
            local extracted=$(echo "$line" | awk '{print $2, $3, $4, $5}')
            if [ -n "$extracted" ]; then
                echo "[$i] $extracted"
                echo "$i $line" >> "$list_file"
                i=$((i + 1))
            fi
        done
    elif [ "$mode" = "zone" ]; then
        echo "$input_data" | tr ',' '\n' | sort -u | while read -r zone; do
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
        local selected_value=$(awk -v num="$choice" '$1 == num {for(i=2; i<=NF; i++) printf "%s ", $i; print ""}' "$list_file")
        if [ -z "$selected_value" ]; then
            echo "$(color red "Invalid selection. Please choose a valid number.")"
            continue
        fi
        echo "$(color cyan "Confirm selection: [$choice] $selected_value")"
        echo -n "(Y/n)?: "
        read yn
        case "$yn" in
            [Yy]*)
                echo "$selected_value" > "$output_file"
                debug_log "Final selection: $selected_value"
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
# select_country: ユーザーに国の選択を促す（検索機能付き）
#########################################################################
select_country() {
    debug_log "=== Entering select_country() ==="
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_language="${CACHE_DIR}/luci.ch"

    # キャッシュがあれば選択済みと判断
    if [ -f "$cache_country" ] && [ -f "$cache_language" ]; then
        debug_log "Using cached country and language. Skipping selection."
        return
    fi

    if [ -n "$1" ]; then
        local input="$1"
    else
        local input=""
    fi

    echo "$(color cyan "Enter country name, code, or language to search:")"
    if [ -n "$input" ]; then
        echo "$(color yellow "Auto-selecting based on input: $input")"
    else
        echo -n "Please input: "
        read input
    fi

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

    echo "$(color cyan "Select your country from the following options:")"
    selection_list "$search_results" "$cache_country" "country"
    if [ -s "$cache_country" ]; then
        country_write "$(cat "$cache_country")"
    else
        select_country
    fi
}

#########################################################################
# country_write: 選択された国をキャッシュに保存
#########################################################################
country_write() {
    local country_data="$1"
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_language="${CACHE_DIR}/language.ch"
    local cache_luci="${CACHE_DIR}/luci.ch"

    local short_country=$(echo "$country_data" | awk '{print $5}')
    local luci_lang=$(echo "$country_data" | awk '{print $4}')

    debug_log "DEBUG: Full country_data -> '$country_data'"
    debug_log "DEBUG: Extracted short_country='$short_country', luci_lang='$luci_lang'"

    echo "$short_country" > "$cache_language"
    echo "$luci_lang" > "$cache_luci"
    echo "$country_data" > "$cache_country"

    debug_log "DEBUG: Written to country.ch -> $(cat "$cache_country")"
    select_zone
}

#########################################################################
# select_zone: 選択した国に対応するタイムゾーンを選択
#########################################################################
select_zone() {
    debug_log "=== Entering select_zone() ==="
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_zone="${CACHE_DIR}/zone.ch"
    local zone_info=$(awk '{for(i=6; i<=NF; i++) print $i}' "$cache_country" | tr ',' '\n' | grep -E '^[A-Za-z]+/' | sort -u)

    if [ -z "$zone_info" ]; then
        echo "$(color red "ERROR: No timezone data found. Please reselect your country.")"
        select_country
        return
    fi

    debug_log "DEBUG: Extracted zones -> $zone_info"
    echo "$(color cyan "Select your timezone from the following options:")"
    selection_list "$zone_info" "$cache_zone" "zone"

    if [ -s "$cache_zone" ]; then
        debug_log "Final selection: $(cat "$cache_zone")"
    else
        select_zone
    fi
}

#########################################################################
# normalize_country: 言語設定の正規化
#########################################################################
normalize_country() {
    local message_db="${BASE_DIR}/messages.db"
    local language_cache="${CACHE_DIR}/luci.ch"
    local selected_language="ja"  # デフォルトは日本語

    if [ -f "$language_cache" ]; then
        selected_language=$(cat "$language_cache")
        debug_log "Loaded language from luci.ch -> $selected_language"
    else
        debug_log "No luci.ch found, defaulting to 'ja'"
    fi

    if grep -q "^$selected_language|" "$message_db"; then
        debug_log "Using message database language: $selected_language"
    else
        selected_language="ja"
        debug_log "Language not found in messages.db. Using: ja"
    fi

    debug_log "Final language after normalization -> $selected_language"
    SELECTED_LANGUAGE="$selected_language"
}
# 🔴　ランゲージ系　ここまで　-------------------------------------------------------------------------------------------------------------------------------------------

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

#########################################################################
# debug_log: デバッグ出力関数
#########################################################################
debug_log() {
    local message="$1"
    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG: $message" | tee -a "$LOG_DIR/debug.log"
    fi
}

# 環境変数 INPUT_LANG のチェック（デフォルト 'ja' とする）
INPUT_LANG="${INPUT_LANG:-ja}"
debug_log "common.sh received INPUT_LANG: '$INPUT_LANG'"

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
# download_script: 指定されたスクリプト・データベースのバージョン確認とダウンロード
#########################################################################
download_script() {
    local file_name="$1"
    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"
    
    if [ "$file_name" = "aios" ]; then
        install_path="${AIOS_DIR}/${file_name}"
    fi

    if [ ! -f "$install_path" ]; then
        echo -e "$(color yellow "$(get_message 'MSG_DOWNLOADING_MISSING_FILE' "$SELECTED_LANGUAGE" | sed "s/{file}/$file_name/")")"
        if ! ${BASE_WGET} "$install_path" "$remote_url"; then
            echo -e "$(color red "Failed to download: $file_name")"
            return 1
        fi
        echo -e "$(color green "Successfully downloaded: $file_name")"
        if [ "$file_name" = "aios" ]; then
            chmod +x "$install_path"
            echo -e "$(color cyan "Applied execute permissions to: $install_path")"
        fi
    fi

    local current_version="N/A"
    local remote_version="N/A"

    if test -s "$install_path"; then
        current_version=$(grep "^version=" "$install_path" | cut -d'=' -f2 | tr -d '"\r')
        [ -z "$current_version" ] && current_version="N/A"
    fi

    local current_version=""
    if [ -f "$install_path" ]; then
        current_version=$(grep "^version=" "$install_path" | cut -d'=' -f2 | tr -d '"\r')
    fi

    local remote_version=""
    remote_version=$(wget -qO- "${remote_url}" | grep "^version=" | cut -d'=' -f2 | tr -d '"\r')
    if [ -z "$current_version" ]; then current_version="N/A"; fi
    if [ -z "$remote_version" ]; then remote_version="N/A"; fi

    echo -e "$(color cyan "DEBUG: Checking version for $file_name | Local: [$current_version], Remote: [$remote_version]")"

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
# download_script (再定義): 指定されたスクリプト・データベースのバージョン確認とダウンロード
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
# get_message: 多言語対応メッセージ取得関数
#########################################################################
get_message() {
    local key="$1"
    local lang="${SELECTED_LANGUAGE:-ja}"
    local message_db="${BASE_DIR}/messages.db"
    if [ ! -f "$message_db" ]; then
        echo -e "$(color red "Message database not found. Defaulting to key: $key")"
        return
    fi
    local message
    message=$(grep "^${lang}|${key}=" "$message_db" | cut -d'=' -f2-)
    [ -z "$message" ] && message=$(grep "^ja|${key}=" "$message_db" | cut -d'=' -f2-)
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
# check_common: 初期化処理
#
# 【仕様】
# ・第一引数は動作モード（例: full, light）
# ・引数がある場合、その次の引数を言語コードとして使用する
# ・引数が無い場合、キャッシュ（$CACHE_DIR/luci.ch）があればその値を使用
# ・引数が無くキャッシュも無ければ、ユーザーに言語選択を促す（デフォルトは INPUT_LANG）
#
#########################################################################
check_common() {
    local mode="$1"
    shift  # 最初の引数 (モード) を削除

    local lang_code="${2:-$INPUT_LANG}"

    # **"manual" の場合、強制的に手動選択にする**
    if [ "$lang_code" = "manual" ]; then
        debug_log "Manual language selection triggered."
        select_country
        return
    fi

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
            check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
            check_country "$lang_code" || handle_error "ERR_COUNTRY_CHECK" "check_country" "latest"
            select_country
            normalize_country || handle_error "ERR_NORMALIZE" "normalize_country" "latest"
            ;;
        *)
            check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
            check_country "$lang_code" || handle_error "ERR_COUNTRY_CHECK" "check_country" "latest"
            select_country
            normalize_country || handle_error "ERR_NORMALIZE" "normalize_country" "latest"
            ;;
    esac
}
