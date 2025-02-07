
#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
COMMON_VERSION="2025.02.05-28"
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
#########################################################################
download_script() {
    local file_name="$1"
    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"

    # `aios` の場合は `/usr/bin/aios` に配置
    if [ "$file_name" = "aios" ]; then
        install_path="/usr/bin/aios"
    fi

    # ファイルが存在しない場合はダウンロード
    if [ ! -f "$install_path" ]; then
        echo -e "$(color yellow "$(get_message 'MSG_DOWNLOADING_MISSING_FILE' "$SELECTED_LANGUAGE" | sed "s/{file}/$file_name/")")"
        if ! wget --quiet -O "$install_path" "$remote_url"; then
            echo -e "$(color red "Failed to download: $file_name")"
            return 1
        fi
        echo -e "$(color green "Successfully downloaded: $file_name")"
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
        if ! wget --quiet -O "$install_path" "$remote_url"; then
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
    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"

    if [ "$file_name" = "aios" ]; then
        install_path="/usr/bin/aios"
    fi

    if [ ! -f "$install_path" ]; then
        echo -e "$(color yellow "$(get_message 'MSG_DOWNLOADING_MISSING_FILE' "$SELECTED_LANGUAGE" | sed "s/{file}/$file_name/")")"
        if ! wget --quiet -O "$install_path" "$remote_url"; then
            echo -e "$(color red "Failed to download: $file_name")"
            return 1
        fi
        echo -e "$(color green "Successfully downloaded: $file_name")"
    fi

    # バージョン取得
    local current_version="N/A"
    local remote_version="N/A"

    if test -s "$install_path"; then
        current_version=$(grep "^version=" "$install_path" | cut -d'=' -f2 | tr -d '"\r')
        [ -z "$current_version" ] && current_version="N/A"
    fi

    remote_version=$(wget -qO- "${remote_url}" | grep "^version=" | cut -d'=' -f2 | tr -d '"\r')
    [ -z "$remote_version" ] && remote_version="N/A"

    echo -e "$(color cyan "DEBUG: Checking version for $file_name | Local: [$current_version], Remote: [$remote_version]")"
}

#########################################################################
# check_country: 言語キャッシュの確認および設定（country.db からデータ取得）
#########################################################################
check_country() {
    local country_file="${BASE_DIR}/country.db"
    local found_entries found_entry num_matches choice

    if [ -f "${BASE_DIR}/check_country" ]; then
        SELECTED_LANGUAGE=$(cat "${BASE_DIR}/check_country")
        return
    fi

    if [ ! -f "$country_file" ]; then
        country_db || handle_error "Failed to download country.db"
    fi

    echo -e "$(color cyan "Select your language (matching country):")"

    while true; do
        read -p "Enter country name, code, or language (e.g., 'Japan', 'JP', 'ja'): " input_lang
        input_lang=$(echo "$input_lang" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        found_entries=$(grep -i -w "$input_lang" "$country_file")

        if [ -z "$found_entries" ]; then
            found_entries=$(grep -i "$input_lang" "$country_file")
        fi

        if [ -z "$found_entries" ]; then
            echo -e "$(color red "No matching entry found. Please try again.")"
            continue
        fi

        num_matches=$(echo "$found_entries" | wc -l)
        if [ "$num_matches" -eq 1 ]; then
            found_entry="$found_entries"
        else
            echo -e "$(color yellow "Multiple matches found. Please select:")"
            local i=1
            echo "$found_entries" | while IFS= read -r line; do
                echo "[$i] $line"
                i=$((i+1))
            done
            echo "[0] Re-enter language"

            while true; do
                read -p "Enter the number of your choice: " choice
                if [ "$choice" = "0" ]; then
                    continue 2  # `while true` を再実行
                fi

                found_entry=$(echo "$found_entries" | sed -n "${choice}p")
                if [ -z "$found_entry" ]; then
                    echo -e "$(color red "Invalid selection. Please try again.")"
                    continue
                fi
                break
            done
        fi

        break
    done

    SELECTED_LANGUAGE=$(echo "$found_entry" | awk '{print $3}')
    echo "$SELECTED_LANGUAGE" > "${BASE_DIR}/check_country"

    echo -e "$(color green "Selected Language: $SELECTED_LANGUAGE")"
}

#########################################################################
# normalize_country: 言語コードがサポート対象か検証し、サポート外なら `en` に変更
#########################################################################
normalize_country() {
    local lang_file="${BASE_DIR}/check_country"

    if [ -f "$lang_file" ]; then
        local read_lang=$(cat "$lang_file")
    else
        read_lang="en"
    fi

    SELECTED_LANGUAGE=""
    for lang in $SUPPORTED_LANGUAGES; do
        if [ "$read_lang" = "$lang" ]; then
            SELECTED_LANGUAGE="$read_lang"
            break
        fi
    done

    if [ -z "$SELECTED_LANGUAGE" ]; then
        SELECTED_LANGUAGE="en"
        echo -e "$(color yellow "Language '$read_lang' is not supported. Defaulting to English (en).")"
        echo "$SELECTED_LANGUAGE" > "$lang_file"
    fi
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
# check_openwrt: OpenWrtのバージョンを確認し、サポートされているか検証する
#########################################################################
check_openwrt() {
    local supported_versions_db="${BASE_DIR}/openwrt.db"

    if [ ! -f "$supported_versions_db" ]; then
        openwrt_db || handle_error "Failed to download openwrt.db"
    fi

    CURRENT_VERSION=$(awk -F"'" '/DISTRIB_RELEASE/ {print $2}' /etc/openwrt_release | cut -d'-' -f1)

    if grep -q "^$CURRENT_VERSION=" "$supported_versions_db"; then
        local db_entry db_manager db_status
        db_entry=$(grep "^$CURRENT_VERSION=" "$supported_versions_db" | cut -d'=' -f2)
        db_manager=$(echo "$db_entry" | cut -d'|' -f1)  
        db_status=$(echo "$db_entry" | cut -d'|' -f2)  

        PACKAGE_MANAGER="$db_manager"
        VERSION_STATUS="$db_status"

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

        echo -e "$(color green "$(get_message 'version_supported' "$SELECTED_LANGUAGE" "$CURRENT_VERSION" "$VERSION_STATUS")")"
    else
        handle_error "$(get_message 'unsupported_version' "$SELECTED_LANGUAGE" "$CURRENT_VERSION")"
    fi
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
# install_packages: パッケージをインストールし、言語パックも適用
#########################################################################
install_packages() {
    local confirm_flag="$1"
    shift
    local package_list="$*"  # `ash` ではスペース区切りの文字列として扱う

    echo "DEBUG: Calling install_packages() with confirm_flag=$confirm_flag and package_list=[$package_list]"

    if [ -n "${INSTALLATION_STARTED:-}" ]; then
        echo "DEBUG: Skipping duplicate install_packages() call."
        return
    fi
    INSTALLATION_STARTED=1

    if [ "$confirm_flag" = "yn" ] && [ -z "${CONFIRMATION_DONE:-}" ]; then
        local package_names=$(echo "$package_list" | sed 's/  */, /g')

        echo "DEBUG: Package list for confirmation: [$package_names]"

        if ! confirm "MSG_INSTALL_PROMPT_PKG" "$package_names"; then
            echo "$(color yellow "Skipping installation of: $package_names")"
            return 1
        fi
        CONFIRMATION_DONE=1
    fi

    for pkg in $package_list; do
        attempt_package_install "$pkg"
    done
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
# check_common: 初期化処理
# - モード: "full" (通常), "light" (最低限)
#########################################################################
check_common() {
    local mode="$1"
    case "$mode" in
        full)
            download_script messages.db
            download_script country.db
            download_script openwrt.db
            check_country  
            normalize_country  
            check_openwrt  
            ;;
        light)
            check_country
            normalize_country
            check_openwrt
            ;;
        *)
            check_country
            normalize_country
            check_openwrt
            ;;
    esac
}
