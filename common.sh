
#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
COMMON_VERSION="2025.02.08-09-03"
echo "common.sh Last update: $COMMON_VERSION"

# === 基本定数の設定 ===
BASE_WGET="wget -O"
# BASE_WGET="wget --quiet -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
AIOS_DIR="/usr/bin"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
SUPPORTED_VERSIONS="${SUPPORTED_VERSIONS:-19.07 21.02 22.03 23.05 24.10.0 SNAPSHOT}"
SUPPORTED_LANGUAGES="${SUPPORTED_LANGUAGES:-en ja zh-cn zh-tw id ko de ru}"

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
    local script_cache="${BASE_DIR}/script.ch"
    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"

    # `aios` の場合は `/usr/bin/aios` に配置
    if [ "$file_name" = "aios" ]; then
        install_path="${AIOS_DIR}/${file_name}"
    fi

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
    wget --quiet -O "$install_path" "$remote_url"

    local new_version=$(grep "^version=" "$install_path" | cut -d'=' -f2)
    echo "$file_name=$new_version" >> "$script_cache"

    # `aios` のみ実行権限を付与
    if [ "$file_name" = "aios" ]; then
        chmod +x "$install_path"
        echo -e "$(color cyan "Applied execute permissions to: $install_path")"
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
        if ! wget --quiet -O "${BASE_DIR}/messages.db" "${BASE_URL}/messages.db"; then
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
    wget --quiet -O "$install_path" "$remote_url"

    local new_version=$(grep "^version=" "$install_path" | cut -d'=' -f2)
    echo "$file_name=$new_version" >> "$script_cache"
}

#########################################################################
# select_country: `country.db` から国を検索し、ユーザーに選択させる
#########################################################################
select_country() {
    local country_file="${BASE_DIR}/country.db"
    local country_cache="${BASE_DIR}/country.ch"
    local user_input=""
    local found_entries=""
    local selected_entry=""
    local selected_timezone=""

    # **データベース存在確認**
    if [ ! -f "$country_file" ]; then
        echo "$(color red "Country database not found!")"
        return
    fi

    while true; do
        # **国リスト表示**
        awk '{print "[" NR "]", $1, $2, $3, $4}' "$country_file"

        # **ユーザー入力**
        echo -e "$(color cyan "Enter number, country name, code, or language:")"
        read -r user_input

        # **番号入力の処理**
        if echo "$user_input" | grep -qE '^[0-9]+$'; then
            selected_entry=$(awk -v num="$user_input" 'NR == num {print $0}' "$country_file")
        else
            # **完全一致検索**
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

        # **選択した国が正しいか `confirm()` で Y/N 判定**
        if [ -n "$selected_entry" ]; then
            local country_name
            local display_name
            local lang_code
            local country_code
            local tz_data

            country_name=$(echo "$selected_entry" | awk '{print $1}')
            display_name=$(echo "$selected_entry" | awk '{print $2}')
            lang_code=$(echo "$selected_entry" | awk '{print $3}')
            country_code=$(echo "$selected_entry" | awk '{print $4}')
            tz_data=$(echo "$selected_entry" | awk -F';' '{print $2}')

            confirm_message=$(get_message 'MSG_CONFIRM_COUNTRY' "$SELECTED_LANGUAGE" | sed -e "s/{file}/$country_name/" -e "s/{version}/$display_name ($lang_code, $country_code)/")

            # **YN確認の修正**
            if ! confirm "$confirm_message"; then
                echo "$(color yellow "Invalid selection. Please try again.")"
                continue
            fi

            # **タイムゾーンの選択**
            if echo "$tz_data" | grep -q ","; then
                echo "$(color cyan "Select a timezone for $country_name:")"
                local i=1
                echo "$tz_data" | awk -F',' '{for (i=1; i<=NF; i++) print "["i"] "$i}'
                
                while true; do
                    read -p "Enter the number of your choice: " tz_choice
                    selected_timezone=$(echo "$tz_data" | awk -F',' -v num="$tz_choice" '{print $num}')
                    
                    if [ -z "$selected_timezone" ]; then
                        echo "$(color red "Invalid selection. Please enter a valid number.")"
                        continue
                    fi

                    confirm_message=$(get_message 'MSG_CONFIRM_TIMEZONE' "$SELECTED_LANGUAGE" | sed -e "s/{file}/$selected_timezone/")
                    if confirm "$confirm_message"; then
                        break
                    fi
                done
            else
                selected_timezone="$tz_data"
            fi

            # **キャッシュに保存**
            echo "$country_name $display_name $lang_code $country_code $selected_timezone" > "$country_cache"
            echo "$(color green "Country and timezone set: $country_name, $selected_timezone")"
            return
        fi
    done
}

#########################################################################
# normalize_country: `message.db` に対応する言語があるか確認
# - `message.db` に `$SELECT_COUNTRY` があればそのまま使用
# - 無ければ `message.db` にあるデフォルト言語 (`SELECT_COUNTRY=en` など) を使用
#########################################################################
normalize_country() {
    local country_file="${BASE_DIR}/country.ch"
    local message_db="${BASE_DIR}/messages.db"

    # `country.ch` を読み込む
    if [ -f "$country_file" ]; then
        SELECT_COUNTRY=$(cat "$country_file")
    else
        SELECT_COUNTRY="en"
    fi

    if grep -q "^$SELECT_COUNTRY|" "$message_db"; then
        echo "$(color green "Using message database language: $SELECT_COUNTRY")"
    else
        echo "en" > "$country_file"
        echo "$(color yellow "Language not found in messages.db. Using: en")"
    fi
}

#########################################################################
# confirm: Y/N 確認関数
# 引数1: 確認メッセージキー（多言語対応）
# 引数2: 置換パラメータ1（オプション）
# 引数3: 置換パラメータ2（オプション）
# 使用例: confirm "MSG_INSTALL_PROMPT" "ttyd"
#########################################################################
confirm() {
    local key="$1"
    local replace_param1="$2"
    local replace_param2="$3"
    local prompt_message
    prompt_message=$(get_message "$key" "$SELECTED_LANGUAGE")

    # メッセージが見つからない場合、デフォルトメッセージを使用
    if [ -z "$prompt_message" ]; then
        case "$key" in
            "MSG_INSTALL_PROMPT")
                prompt_message="Do you want to install {pkg}? [Y/n]:"
                ;;
            *)
                prompt_message="Confirm action? [Y/n]:"
                ;;
        esac
    fi

    # {pkg}, {file}, {version} の置換処理
    if [ -n "$replace_param1" ]; then
        prompt_message=$(echo "$prompt_message" | sed "s/{pkg}/$replace_param1/g")
        prompt_message=$(echo "$prompt_message" | sed "s/{file}/$replace_param1/g")
    fi
    if [ -n "$replace_param2" ]; then
        prompt_message=$(echo "$prompt_message" | sed "s/{version}/$replace_param2/g")
    fi

    # デバッグ: 確認メッセージの出力
    echo "DEBUG: Confirm message -> [$prompt_message]"

    while true; do
        read -r -p "$prompt_message " confirm
        confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')  # 小文字変換

        case "$confirm" in
            ""|"y"|"yes")
                echo "$(color green "Settings applied successfully.")"
                return 0
                ;;
            "n"|"no")
                echo "$(color yellow "Settings were not applied.")"
                return 1
                ;;
            *)
                echo "$(color red "Invalid input. Please enter 'Y' or 'N'.")"
                ;;
        esac
    done
}

#########################################################################
# check_country: 言語キャッシュの確認および設定
# - `$1` (`SELECT_COUNTRY`) があればそれを優先
# - それが無ければ `country.ch` を参照
# - さらに無ければ `select_country()` で `country.db` を検索し完全一致 → 曖昧検索
# - 見つからなかった場合は `confirm()` による Y/N 選択
# - すべて失敗したら `en` をセット
#########################################################################
check_country() {
    local country_file="${BASE_DIR}/country.db"

    # `country.ch` のキャッシュがあれば利用
    if [ -f "${BASE_DIR}/country.ch" ]; then
        SELECTED_LANGUAGE=$(cat "${BASE_DIR}/country.ch")
        echo "Using cached country: $SELECTED_LANGUAGE"
        return
    fi

    # country.db がない場合はダウンロード
    if [ ! -f "$country_file" ]; then
        download_script "country.db"
    fi

    # ユーザーに国を選択させる
    echo -e "$(color cyan "Available countries:")"
    awk '{print "["NR"] "$0}' "$country_file"

    while true; do
        read -p "Enter number, country name, code, or language: " input_lang
        input_lang=$(echo "$input_lang" | tr -d '[:space:]')  # 空白削除

        # 数字入力の場合
        if echo "$input_lang" | grep -qE '^[0-9]+$'; then
            SELECTED_LANGUAGE=$(awk -v num="$input_lang" 'NR == num {print $3}' "$country_file")
        else
            SELECTED_LANGUAGE=$(awk -v lang="$input_lang" '$1 == lang || $2 == lang || $3 == lang || $4 == lang {print $3}' "$country_file")
        fi

        if [ -n "$SELECTED_LANGUAGE" ]; then
            if confirm "MSG_CONFIRM_COUNTRY" "$SELECTED_LANGUAGE"; then
                echo "$SELECTED_LANGUAGE" > "${BASE_DIR}/country.ch"
                echo "Country and timezone set: $SELECTED_LANGUAGE"
                break
            fi
        else
            echo -e "$(color red "No matching country found. Please try again.")"
        fi
    done
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

        echo -e "$(color green "バージョン $CURRENT_VERSION はサポートされています ($VERSION_STATUS)")"
    else
        handle_error "Unsupported OpenWrt version: $CURRENT_VERSION"
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
    if [ -f "${BASE_DIR}/downloader_cache" ]; then
        PACKAGE_MANAGER=$(cat "${BASE_DIR}/downloader_cache")
    else
        # パッケージマネージャーの存在確認のみ
        if command -v apk >/dev/null 2>&1; then
            PACKAGE_MANAGER="apk"
        elif command -v opkg >/dev/null 2>&1; then
            PACKAGE_MANAGER="opkg"
        else
            handle_error "$(get_message 'no_package_manager_found' "$SELECTED_LANGUAGE")"
        fi
        echo "$PACKAGE_MANAGER" > "${BASE_DIR}/downloader_cache"
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
# 引数:
#   $1: 'yn' を指定すると Y/N 確認を行う
#   $2 以降: インストールするパッケージ名 (複数指定可)
#########################################################################
install_packages() {
    local confirm_flag="$1"
    shift  # 最初の引数 (`yn` など) を削除
    local package_list="$@"  # 残りの引数を取得
    local packages_to_install=""
    local installed_packages=""

    # インストール済みのパッケージをチェック
    for pkg in $package_list; do
        if is_package_installed "$pkg"; then
            installed_packages="$installed_packages $pkg"
        else
            packages_to_install="$packages_to_install $pkg"
        fi
    done

    # すでにインストール済みのパッケージを表示
    if [ -n "$installed_packages" ]; then
        echo "$(color cyan "Already installed:$installed_packages")"
    fi

    # インストールが必要なパッケージがない場合は終了
    if [ -z "$packages_to_install" ]; then
        return 0
    fi

    # `yn` フラグがある場合、確認メッセージを出す（ここで1回のみ）
    if [ "$confirm_flag" = "yn" ]; then
        if ! confirm "MSG_INSTALL_PROMPT" "$packages_to_install"; then
            echo "$(color yellow "Skipping installation of:$packages_to_install")"
            return 1
        fi
    fi

    # 必要なパッケージをインストール
    install_package_list "$packages_to_install"

    echo "$(color green "Installed:$packages_to_install")"
    return 0
}

#########################################################################
# is_package_installed: パッケージがインストール済みか確認
# 引数: パッケージ名
# 戻り値: 0 (インストール済み), 1 (未インストール)
#########################################################################
is_package_installed() {
    local pkg="$1"
    if command -v apk >/dev/null 2>&1; then
        apk list-installed | grep -q "^$pkg "
    elif command -v opkg >/dev/null 2>&1; then
        opkg list-installed | grep -q "^$pkg "
    else
        return 1  # パッケージマネージャが見つからない場合は未インストール扱い
    fi
}

#########################################################################
# install_package_list: 必要なパッケージをインストール
# 引数: インストールするパッケージリスト
#########################################################################
install_package_list() {
    local packages="$@"
    if command -v apk >/dev/null 2>&1; then
        apk add $packages
    elif command -v opkg >/dev/null 2>&1; then
        opkg install $packages
    else
        echo "$(color red "No package manager found.")"
        return 1
    fi
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
# - 言語 (`INPUT_LANG`) を `SELECTED_LANGUAGE` に渡す
# - `full` (通常モード), `light` (最低限モード) の選択
#########################################################################
check_common() {
    local mode="$1"
    shift  # 最初の引数 (モード) を削除

    local RESET_CACHE=false
    local SHOW_HELP=false
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

    # 言語キャッシュのチェック
    if [ -f "${BASE_DIR}/country.ch" ]; then
        SELECTED_LANGUAGE=$(cat "${BASE_DIR}/country.ch")
        echo "Using cached language: $SELECTED_LANGUAGE"
    else
        check_country "$INPUT_LANG"
        normalize_country
    fi

    case "$mode" in
        full)
            download_script messages.db
            download_script country.db
            download_script openwrt.db
            check_openwrt
            ;;
        light)
            check_openwrt
            ;;
        *)
            check_openwrt
            ;;
    esac
}
