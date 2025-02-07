#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
COMMON_VERSION="2025.02.05-10"
echo "common.sh Last update: $COMMON_VERSION"

# === 基本定数の設定 ===
BASE_WGET="wget -O"
# BASE_WGET="wget --quiet -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
SUPPORTED_VERSIONS="${SUPPORTED_VERSIONS:-19.07 21.02 22.03 23.05 24.10.0 SNAPSHOT}"
SUPPORTED_LANGUAGES="${SUPPORTED_LANGUAGES:-en ja zh-cn zh-tw id ko de ru}"

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
# 使い方:
#   download_script aios
#   download_script openwrt.db
#########################################################################
download_script() {
    local file_name="$1"
    local file_ext="${file_name##*.}"
    local install_path

    # `aios` の場合は `/usr/bin/aios` に配置
    if [ "$file_name" = "aios" ]; then
        install_path="/usr/bin/aios"
    else
        install_path="${BASE_DIR}/${file_name}"
    fi

    local remote_url="${BASE_URL}/${file_name}"

    # ファイルが存在しない場合はダウンロード
    if [ ! -f "$install_path" ]; then
        echo -e "$(color yellow "$(get_message 'MSG_DOWNLOADING_MISSING_FILE' "$SELECTED_LANGUAGE" | sed "s/{file}/$file_name/")")"
        if ! download "$file_name" "$install_path"; then
            handle_error "Failed to download: $file_name"
        fi
    fi

    # ローカルバージョンを取得
    local current_version=""
    if [ -f "$install_path" ]; then
        current_version=$(grep "^version=" "$install_path" | cut -d'=' -f2 | tr -d '"\r')
    fi

    # リモートバージョンを取得
    local remote_version=""
    remote_version=$(wget -qO- "${remote_url}" | grep "^version=" | cut -d'=' -f2 | tr -d '"\r')

    # デバッグログ
    echo -e "DEBUG: Checking version for $file_name | Local: [$current_version], Remote: [$remote_version]"

    # バージョンチェック: 最新があればダウンロード
    if [ -n "$remote_version" ] && [ "$current_version" != "$remote_version" ]; then
        echo -e "$(color cyan "$(get_message 'MSG_UPDATING_SCRIPT' "$SELECTED_LANGUAGE" | sed -e "s/{file}/$file_name/" -e "s/{old_version}/$current_version/" -e "s/{new_version}/$remote_version/")")"
        if ! download "$file_name" "$install_path"; then
            handle_error "Failed to download: $file_name"
        fi
    else
        echo -e "$(color green "$(get_message 'MSG_NO_UPDATE_NEEDED' "$SELECTED_LANGUAGE" | sed -e "s/{file}/$file_name/" -e "s/{version}/$current_version/")")"
    fi

    # `aios` の場合のみ実行権限を付与
    if [ "$file_name" = "aios" ]; then
        chmod +x /usr/bin/aios
    fi

    # `.sh` の場合のみ実行
    if [ "$file_ext" = "sh" ]; then
        sh "$install_path"
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
# messages_db: 選択された言語のメッセージファイルをダウンロード
#########################################################################
messages_db() {
    if [ ! -f "${BASE_DIR}/messages.db" ]; then
        echo -e "$(color yellow "Downloading messages.db...")"
        if ! ${BASE_WGET} "${BASE_URL}/messages.db" -O "${BASE_DIR}/messages.db"; then
            echo -e "$(color red "Failed to download messages.db")"
            return 1  # エラー時は `return 1` にして `exit` しない
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
# print_banner: 言語に応じたバナー表示 (messages.db からメッセージ取得)
#########################################################################
print_banner() {
    local msg
    msg=$(get_message 'MSG_BANNER' "$SELECTED_LANGUAGE")

    echo
    echo -e "\033[1;35m                    ii i                              \033[0m"
    echo -e "\033[1;34m         aaaa      iii       oooo      sssss          \033[0m"
    echo -e "\033[1;36m            aa      ii      oo  oo    ss              \033[0m"
    echo -e "\033[1;32m         aaaaa      ii      oo  oo     sssss          \033[0m"
    echo -e "\033[1;33m        aa  aa      ii      oo  oo         ss         \033[0m"
    echo -e "\033[1;31m         aaaaa     iiii      oooo     ssssss          \033[0m"
    echo
    echo -e "\033[1;37m$msg\033[0m"
}

#########################################################################
# バージョン確認とパッケージマネージャーの取得関数
#########################################################################
check_openwrt() {
    local version_file="${BASE_DIR}/check_openwrt"
    local supported_versions_db="${BASE_DIR}/openwrt.db"

    # バージョンデータベースが無い場合はダウンロード
    if [ ! -f "$supported_versions_db" ]; then
        openwrt_db || handle_error \
            "$(get_message 'download_fail' "$SELECTED_LANGUAGE"): openwrt.db"
    fi

    # バージョンをキャッシュファイル or /etc/openwrt_release から取得
    if [ -f "$version_file" ]; then
        CURRENT_VERSION=$(cat "version_file")
    else
        CURRENT_VERSION=$(awk -F"'" '/DISTRIB_RELEASE/ {print $2}' /etc/openwrt_release)
        # --- ハイフン '-' 以降を削除し、19.07-rc1 → 19.07, 23.05-2 → 23.05 にする ---
        CURRENT_VERSION=$(echo "$CURRENT_VERSION" | cut -d'-' -f1)

        echo "$CURRENT_VERSION" > "version_file"
    fi

    # openwrt.db にエントリがあるか
    if grep -q "^$CURRENT_VERSION=" "$supported_versions_db"; then
        local db_entry db_manager db_status
        # 例: "24.10.0=apk|stable" → db_entry="apk|stable"
        db_entry=$(grep "^$CURRENT_VERSION=" "$supported_versions_db" | cut -d'=' -f2)
        db_manager=$(echo "$db_entry" | cut -d'|' -f1)   # "apk" など
        db_status=$(echo "$db_entry" | cut -d'|' -f2)    # "stable" など

        # 初期値を設定
        PACKAGE_MANAGER="$db_manager"
        VERSION_STATUS="$db_status"

        # === ここからフォールバックロジック ===
        case "$PACKAGE_MANAGER" in
            apk)
                if ! command -v apk >/dev/null 2>&1; then
                    if command -v opkg >/dev/null 2>&1; then
                        PACKAGE_MANAGER="opkg"
                    else
                        handle_error "No valid package manager found. 'apk' not found, 'opkg' not found."
                    fi
                fi
                ;;
            opkg)
                if ! command -v opkg >/dev/null 2>&1; then
                    if command -v apk >/dev/null 2>&1; then
                        PACKAGE_MANAGER="apk"
                    else
                        handle_error "No valid package manager found. 'opkg' not found, 'apk' not found."
                    fi
                fi
                ;;
            *)
                handle_error "Unsupported package manager: $PACKAGE_MANAGER (from $supported_versions_db)"
                ;;
        esac
        # === フォールバックロジックここまで ===

        echo -e "\033[1;32m$(get_message 'version_supported' "$SELECTED_LANGUAGE"): $CURRENT_VERSION ($VERSION_STATUS)\033[0m"
    else
        # openwrt.db に該当バージョンが無い場合
        handle_error "$(get_message 'unsupported_version' "$SELECTED_LANGUAGE"): $CURRENT_VERSION"
    fi
}

#########################################################################
# check_country: 言語キャッシュの確認および設定
#########################################################################
check_country() {
    if [ -f "${BASE_DIR}/country.ch" ]; then
        SELECTED_LANGUAGE=$(cat "${BASE_DIR}/country.ch")
    else
        echo -e "\033[1;32mSelect your language:\033[0m"

        # サポート言語リストを表示
        i=1
        for lang in $SUPPORTED_LANGUAGES; do
            echo "$i) $lang"
            i=$((i+1))
        done

        # 入力受付ループ
        while true; do
            read -p "Enter number or language (e.g., en, ja): " input

            # 数字入力の場合
            if echo "$input" | grep -qE '^[0-9]+$'; then
                lang=$(echo $SUPPORTED_LANGUAGES | cut -d' ' -f$input)
            else
                # iconv を使わずに大文字小文字変換のみ
                input_normalized=$(echo "$input" | tr '[:upper:]' '[:lower:]')
                lang=$(echo "$SUPPORTED_LANGUAGES" | tr '[:upper:]' '[:lower:]' | grep -wo "$input_normalized")
            fi

            # 有効な言語かどうか確認
            if [ -n "$lang" ]; then
                SELECTED_LANGUAGE="$lang"
                echo "$SELECTED_LANGUAGE" > "${BASE_DIR}/country.ch"
                break
            else
                echo -e "\033[1;31mInvalid selection. Try again.\033[0m"
            fi
        done
    fi

    echo -e "\033[1;32mLanguage supported: $SELECTED_LANGUAGE\033[0m"
}

#########################################################################
# confirm: Y/N 確認関数
# 引数1: 確認メッセージキー（多言語対応）
# 使用例: confirm 'MSG_INSTALL_PROMPT'
#########################################################################
confirm() {
    local key="$1"
    local replace_param="$2"
    local prompt_message
    prompt_message=$(get_message "$key" "$SELECTED_LANGUAGE")

    if [ -n "$replace_param" ]; then
        # {pkg} → $replace_param へ単純置換
        prompt_message="${prompt_message//\{pkg\}/$replace_param}"
    fi
    
    # メッセージが取得できなければデフォルトメッセージを使用
    [ -z "$prompt_message" ] && prompt_message="Do you want to proceed? [Y/n]:"

    while true; do
        read -p "$prompt_message " confirm
        confirm=${confirm:-Y}  # デフォルトは "Y"

        case "$confirm" in
            [Yy]|[Yy][Ee][Ss]|はい|ハイ)
                echo -e "$(color green "$(get_message 'MSG_SETTINGS_APPLIED' "$SELECTED_LANGUAGE")")"
                return 0
                ;;
            [Nn]|[Nn][Oo]|いいえ|イイエ)
                echo -e "$(color yellow "$(get_message 'MSG_SETTINGS_CANCEL' "$SELECTED_LANGUAGE")")"
                return 1
                ;;
            *)
                echo -e "$(color red "$(get_message 'MSG_INVALID_SELECTION' "$SELECTED_LANGUAGE")")"
                ;;
        esac
    done
}

#########################################################################
# 国とタイムゾーンの選択
#########################################################################
select_country() {
    local country_file="${BASE_DIR}/country-zone.sh"

    if [ ! -f "$country_file" ]; then
        download "${BASE_URL}/country-zone.sh" "$country_file"
    fi

    echo -e "$(color cyan "Select a country for language and timezone configuration.")"
    sh "$country_file" | nl -w2 -s'. '

    read -p "Enter the number or country name (partial matches allowed): " selection
    local matched_country
    matched_country=$(sh "$country_file" | grep -i "$selection")

    if [ -z "$matched_country" ]; then
        echo -e "$(color red "No matching country found.")"
        return 1
    fi

    local language_code
    language_code=$(echo "$matched_country" | awk '{print $3}')
    echo "$language_code" > "${BASE_DIR}/check_country"

    echo -e "$(color green "Selected Language: $language_code")"
    confirm_settings || select_country
}

#########################################################################
# 選択された国と言語の詳細情報を表示
#########################################################################
country_info() {
    local country_info_file="${BASE_DIR}/country-zone.sh"
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
get_message() {
    local key="$1"
    local lang="${SELECTED_LANGUAGE:-en}"
    local message_db="${BASE_DIR}/messages.db"

    # メッセージDBが存在しない場合のエラーハンドリング
    if [ ! -f "$message_db" ]; then
        echo -e "$(color red "Message database not found. Defaulting to key: $key")"
        return
    fi

    # メッセージDBから対応メッセージを取得
    local message
    message=$(grep "^${lang}|${key}=" "$message_db" | cut -d'=' -f2-)

    # 見つからない場合、英語のデフォルトメッセージを適用
    if [ -z "$message" ]; then
        message=$(grep "^en|${key}=" "$message_db" | cut -d'=' -f2-)
    fi

    # メッセージが見つからない場合、デフォルトの警告を出力
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
# install_packages: パッケージをインストールし、言語パックも適用
#########################################################################
install_packages() {
    local confirm="$1"  # yn (インストール確認)
    local package_name="$2"
    shift 2  # 最初の2つの引数を削除
    local options="$@"  # スペース区切りの文字列として取得

    # 最新の packages.db を取得
    packages_db

    local db_package_list=""
    local db_uci_list=""
    local db_command_list=""

    # packages.db から該当パッケージの情報を取得
    while IFS='=' read -r key value; do
        case "$key" in
            "packages") db_package_list="$value" ;;
            "uci") db_uci_list="$db_uci_list\n$value" ;;
            "command") db_command_list="$db_command_list\n$value" ;;
        esac
    done < "${BASE_DIR}/packages.db"

    # インストール確認 (`yn` の場合のみ `confirm()` を使用)
    if [ "$confirm" = "yn" ]; then
        if ! confirm "MSG_INSTALL_PROMPT_PKG" "$package_name"; then
            echo "$(color yellow "Skipping installation of: $package_name")"
            return 1
        fi
    fi

    # パッケージのダウンロード (`download()` を使用)
    if [ -n "$db_package_list" ]; then
        for pkg in $db_package_list; do
            download "$pkg" "${BASE_DIR}/$pkg"
        done
    fi

    # パッケージのインストール
    if [ -n "$db_package_list" ]; then
        attempt_package_install $db_package_list
    fi

    # UCI の適用（`uci` が指定された場合）
    if echo "$options" | grep -q "uci" && [ -n "$db_uci_list" ]; then
        echo -e "$db_uci_list" | uci batch
        uci commit
    fi

    # コマンドの実行（`ash` が指定された場合）
    if echo "$options" | grep -q "ash" && [ -n "$db_command_list" ]; then
        echo -e "$db_command_list" | while read -r cmd; do
            eval "$cmd"
        done
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
    local lang_pkg="luci-i18n-${base_pkg#luci-app-}-${SELECTED_LANGUAGE}"  # luci-app- の部分を削除してパッケージ名作成

    # 言語DBやキャッシュをチェック
    if grep -q "^$lang_pkg" "${BASE_DIR}/messages.db"; then
        if $PACKAGE_MANAGER list | grep -q "^$lang_pkg - "; then
            $PACKAGE_MANAGER install $lang_pkg && echo -e "$(color green "Language pack installed: $lang_pkg")" || \
            echo -e "$(color yellow "Failed to install language pack: $lang_pkg. Continuing...")"
        else
            echo -e "$(color cyan "Language pack not found in repo for: $base_pkg. Skipping language pack...")"
        fi
    else
        echo -e "$(color cyan "Language pack $lang_pkg not listed in messages.db. Skipping...")"
    fi
}

#########################################################################
# check_common 
# 初期化処理:
# - モード: "full" (通常), "light" (最低限), "aios" (aios.sh 専用)
#########################################################################
check_common() {
    local mode="$1"
    case "$mode" in
        full)
            check_country
            check_openwrt
            download_script openwrt.db
            #download_script messages.db
            wget -o https://raw.githubusercontent.com/site-u2023/aios/refs/heads/main/messages.db
            download_script country.db
            ;;
        light)
            check_country
            check_openwrt
            ;;
        *)
            check_country
            check_openwrt
            ;;
    esac
}
