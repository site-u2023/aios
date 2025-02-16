#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important! OpenWrt OS only works with Almquist Shell, not Bourne-again shell.
# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

COMMON_VERSION="2025.02.15-00-00"

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="${BASE_WGET:-wget -q -O}"
# BASE_WGET="${BASE_WGET:-wget -O}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
mkdir -p "$CACHE_DIR" "$LOG_DIR"
DEBUG_MODE="${DEBUG_MODE:-false}"

# 環境変数 INPUT_LANG のチェック（デフォルト 'ja' とする）
# INPUT_LANG="${INPUT_LANG:-ja}"
# debug_log "common.sh received INPUT_LANG: '$INPUT_LANG'"

script_update() (
    COMMON_CACHE="${CACHE_DIR}/common_version.ch"
    # キャッシュが存在しない、またはバージョンが異なる場合にアラートを表示
    if [ ! -f "$COMMON_CACHE" ] || [ "$(cat "$COMMON_CACHE" | tr -d '\r\n')" != "$COMMON_VERSION" ]; then
        echo -e "`color white_black "Updated to version $COMMON_VERSION common.sh "`"
        echo "$COMMON_VERSION" > "$COMMON_CACHE"
    fi
)

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
# デバッグモードの制御 (コマンドライン引数対応)
#########################################################################
DEBUG_MODE=false
DEBUG_LEVEL="INFO"  # デフォルトは INFO 以上のログを出力

# コマンドライン引数のチェック
for arg in "$@"; do
    case "$arg" in
        -d|--debug|-debug)
            DEBUG_MODE=true
            DEBUG_LEVEL="DEBUG"
            ;;
    esac
done

#########################################################################
# debug_log: デバッグ出力関数 (改良版)
#########################################################################
debug_log() {
    local level="$1"  # デバッグレベル (INFO, WARN, ERROR, DEBUG)
    local message="$2"
    
    # デバッグレベルの優先度
    case "$DEBUG_LEVEL" in
        DEBUG)    allowed_levels="DEBUG INFO WARN ERROR" ;;
        INFO)     allowed_levels="INFO WARN ERROR" ;;
        WARN)     allowed_levels="WARN ERROR" ;;
        ERROR)    allowed_levels="ERROR" ;;
        *)        allowed_levels="" ;;
    esac

    # 指定されたログレベルが有効な場合のみ出力
    if echo "$allowed_levels" | grep -q "$level"; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local log_message="[$timestamp] $level: $message"

        if [ "$DEBUG_MODE" = true ]; then
            echo "$log_message"
        fi

        if [ -n "$LOG_DIR" ]; then
            echo "$log_message" >> "$LOG_DIR/debug.log"
        fi
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
# Last Update: 2025-02-16 13:40:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
#
# get_message: 多言語対応メッセージ取得関数
#
# 【要件】
# 1. 言語の決定:
#    - 'message.ch' を最優先で参照する（normalize_country() により確定）
#    - 'message.ch' が無ければ、'country.ch' から国コードを取得し、デフォルトを "en" に設定
#
# 2. メッセージ取得の流れ:
#    - messages.db から、言語コード (例: "en", "US", "ja" 等) に対応するメッセージを取得
#    - 該当メッセージが無い場合、"US"（英語）をフォールバック
#    - それでも見つからなければ、キー ($1) をそのまま返す
#
# 3. country.ch との関係:
#    - country.ch はデバイス設定用（変更不可）で、ここから言語コードが取得される
#    - message.ch はシステムメッセージ表示用（フォールバック可能）で、通常は normalize_country() により決定
#
# 4. メンテナンス:
#    - 言語設定に影響を与えず、メッセージのみ message.ch で管理する
#    - normalize_country() によって message.ch が決定されるため、変更は normalize_country() 側で行う
#
# 5. オプション (quiet):
#    - 第二引数に "quiet" を指定すると、取得したメッセージを echo せず、出力を抑制する
#      （例: get_message "MSG_CONFIRM_INSTALL" quiet ）
#########################################################################
get_message() {
    local key="$1"
    local quiet_flag="$2"
    local message_cache="${CACHE_DIR}/message.ch"
    local lang="en"  # デフォルトは "en"

    # message.ch が無い場合、country.ch から言語コードを取得
    if [ ! -f "$message_cache" ]; then
        if [ -f "${CACHE_DIR}/country.ch" ]; then
            lang=$(awk '{print $5}' "${CACHE_DIR}/country.ch")
        fi
        [ -z "$lang" ] && lang="en"
    else
        lang=$(cat "$message_cache")
    fi

    local message_db="${BASE_DIR}/messages.db"
    local message=""

    # messages.db が無い場合は、キーそのままを返す
    if [ ! -f "$message_db" ]; then
        message="$key"
    else
        message=$(grep "^${lang}|${key}=" "$message_db" | cut -d'=' -f2-)
        # 該当メッセージが無ければ、US をフォールバック
        if [ -z "$message" ]; then
            message=$(grep "^US|${key}=" "$message_db" | cut -d'=' -f2-)
        fi
        # それでも見つからなければ、キーそのままとし、デバッグログを出す
        if [ -z "$message" ]; then
            debug_log "Message key '$key' not found in messages.db."
            message="$key"
        fi
    fi

    # quiet オプションが指定された場合は出力せず終了
    if [ "$quiet_flag" = "quiet" ]; then
        return 0
    else
        echo "$message"
    fi
}

# 🔵　ランゲージ（言語・ゾーン）系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# Last Update: 2025-02-12 17:25:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# select_country: ユーザーに国の選択を促す（検索機能付き）
#
# select_country()
# ├── selection_list()  → 選択結果を country_tmp.ch に保存
# ├── country_write()   → country.ch, country.ch, luci.ch, zone.ch に確定
# └── select_zone()     → zone.ch から zonename.ch, timezone.ch に確定
#
# [1] ユーザーが国を選択 → selection_list()
# [2] 一時キャッシュに保存 (country_tmp.ch)
# [3] country_write() を実行
# [4] 確定キャッシュを作成（country.ch, country.ch, luci.ch, zone.ch）→ 書き込み禁止にする
# [5] select_zone() を実行
#
# #️⃣ `$1` の存在確認
#   ├─ あり → `country.db` で検索
#   |    ├─ 見つかる → `select_zone()`（ゾーン選択へ）
#   |    ├─ 見つからない → 言語選択を実行
#   ├─ なし → `country.ch` を確認
#        ├─ あり → 言語系終了（以降の処理なし）
#        ├─ なし → 言語選択を実行
#########################################################################
select_country() {
    debug_log "INFO" "Entering select_country() with arg: '$1'"

    local cache_country="${CACHE_DIR}/country.ch"
    local tmp_country="${CACHE_DIR}/country_tmp.ch"

    if [ -n "$1" ]; then
        debug_log "INFO" "Processing input: $1"
        local predefined_country=$(awk -v search="$1" 'BEGIN {IGNORECASE=1} 
            $2 == search || $3 == search || $4 == search || $5 == search {print $0}' "$BASE_DIR/country.db")

        if [ -n "$predefined_country" ]; then
            debug_log "INFO" "Found country entry: $predefined_country"
            echo  "$predefined_country" > "$tmp_country"
            country_write
            select_zone  
            return
        else
            debug_log "ERROR" "Invalid input '$1' is not a valid country."
            printf "%s\n" "$(color red "Error: '$1' is not a recognized country name or code.")"
            printf "%s\n" "$(color yellow "Switching to language selection.")"
            set --  
        fi
    fi

    if [ -f "$cache_country" ]; then
        debug_log "INFO" "Country cache found. Skipping selection."
        select_zone
        return
    fi

    while true; do
        printf "%s\n" "$(color cyan "$(get_message "MSG_ENTER_COUNTRY")")"
        printf "%s" "$(color cyan "$(get_message "MSG_SEARCH_KEYWORD")")"
        read -r input
        
        # 入力の正規化: "/", ",", "_" をスペースに置き換え
        local cleaned_input
        cleaned_input=$(echo "$input" | sed 's/[\/,_]/ /g')
        
        # 完全一致を優先
        local search_results
        search_results=$(awk -v search="$cleaned_input" 'BEGIN {IGNORECASE=1} 
            { key = $2" "$3" "$4" "$5; if ($0 ~ search && !seen[key]++) print $0 }' "$BASE_DIR/country.db")


        # 完全一致がない場合、部分一致を検索
        if [ -z "$search_results" ]; then
            search_results=$(awk -v search="$cleaned_input" 'BEGIN {IGNORECASE=1} 
                { for (i=2; i<=NF; i++) if ($i ~ search) print $0 }' "$BASE_DIR/country.db")
        fi

        if [ -z "$search_results" ]; then
            printf "%s\n" "$(color red "Error: No matching country found for '$input'. Please try again.")"
            continue
        fi

        selection_list "$search_results" "$tmp_country" "country"
        country_write
        select_zone
        return
    done
}

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
    local list_file=""
    local i=1

    if [ "$mode" = "country" ]; then
        list_file="${CACHE_DIR}/country_tmp.ch"
    elif [ "$mode" = "zone" ]; then
        list_file="${CACHE_DIR}/zone_tmp.ch"
    else
        return 1
    fi

    : > "$list_file"

    echo "$input_data" | while IFS= read -r line; do
        if [ "$mode" = "country" ]; then
            local extracted
            extracted=$(echo "$line" | awk '{print $2, $3, $4, $5}')
            if [ -n "$extracted" ]; then
                printf "[%d] %s\n" "$i" "$extracted"
                echo "$line" >> "$list_file"
                i=$((i + 1))
            fi
        elif [ "$mode" = "zone" ]; then
            if [ -n "$line" ]; then
                echo "$line" >> "$list_file"
                printf "[%d] %s\n" "$i" "$line"
                i=$((i + 1))
            fi
        fi
    done

    while true; do
        printf "%s\n" "$(color cyan "$(get_message "MSG_ENTER_NUMBER_CHOICE")")"
        printf "%s" "$(get_message "MSG_SELECT_NUMBER")"
        read -r choice
        local selected_value
        selected_value=$(awk -v num="$choice" 'NR == num {print $0}' "$list_file")

        if [ -z "$selected_value" ]; then
            printf "%s\n" "$(color red "$(get_message "MSG_INVALID_SELECTION")")"
            continue
        fi

        local confirm_info=""
        if [ "$mode" = "country" ]; then
            confirm_info=$(echo "$selected_value" | awk '{print $2, $3, $4, $5}')
        elif [ "$mode" = "zone" ]; then
            confirm_info=$(echo "$selected_value" | awk '{print $1, $2}')
        fi

        printf "%s\n" "$(color cyan "$(get_message "MSG_CONFIRM_SELECTION") [$choice] $confirm_info")"
        printf "%s" "$(get_message "MSG_CONFIRM_YNR")"
        read -r yn
        
        case "$yn" in
            [Yy]*) 
                printf "%s\n" "$selected_value" > "$output_file"
                return
                ;;
            [Nn]*) 
                printf "%s\n" "$(color yellow "Returning to selection.")"
                selection_list "$input_data" "$output_file" "$mode"
                return
                ;;
            [Rr]*)                
                rm -f "$CACHE_DIR/country.ch" \
                "$CACHE_DIR/language.ch" \
                "$CACHE_DIR/luci.ch" \
                "$CACHE_DIR/zone.ch" \
                "$CACHE_DIR/zonename.ch" \
                "$CACHE_DIR/timezone.ch" \
                "$CACHE_DIR/country_success_done" \
                "$CACHE_DIR/timezone_success_done"
                select_country
                return
                ;;
            *)
                printf "%s\n" "$(color red "$(get_message "MSG_INVALID_INPUT_YNR")")"
                continue
                ;;
        esac
    done  
}

#########################################################################
# Last Update: 2025-02-13 14:18:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# country_write(): 国の選択情報をキャッシュに保存する関数
#
# 【要件】
# 1. `country.ch` は **すべての基準（真）**
#     - `select_country()` で選択したデータを **無条件で `country.ch` に保存**
#     - `country.ch` が存在しないと `zone()` や `country()` は動作しない
#     - `country.ch` 作成時に **即 `chattr +i` で上書き禁止**
#     - **country.ch のデータを元に、以下の `ch` ファイルも作成**
#       - `country.ch` (`$3`: 言語名)
#       - `luci.ch` (`$4`: 言語コード)
#
# 2. `zone_tmp.ch` は **カンマ区切りのまま保存**
#     - `$6` 以降のデータを **カンマ区切りのまま `zone_tmp.ch` に保存**（タイムゾーン情報はセットだから）
#     - `zone()` のタイミングで **選択された行を `zonename.ch` / `timezone.ch` に分割保存**
#       - `zonename.ch` → `$6`（ゾーン名）
#       - `timezone.ch` → `$7`（タイムゾーン）
#
# 3. 上書き禁止 (`ch` ファイル)
#     - `country.ch`
#     - `luci.ch`
#     - `country.ch`
#     - `zonename.ch`
#     - `timezone.ch`
#
# 4. `zone_tmp.ch` から `[1] 番号付き選択方式`
#     - `zone_tmp.ch` には **カンマ区切りのまま** 保存
#     - **選択時に `zonename.ch` / `timezone.ch` に分割書き込み**
#     - **`zonename.ch` / `timezone.ch` は上書き禁止（1回だけ書き込み可能）**
#
# 5. `zone_tmp.ch` が空なら再選択
#     - `zone_tmp.ch` が **空だったら、`select_country()` に戻る**
#     - `zone_tmp.ch` の **`NO_TIMEZONE` は許可しない**
#########################################################################
#########################################################################
# country_write: 選択された国情報をキャッシュに保存
#
# 【要件】
# - `country.ch` に **該当行を丸ごと保存**（データの基準）
# - `language.ch` に **$5（言語名）** を保存
# - `luci.ch` に **$4（言語コード）** を保存
# - `country_tmp.ch`（$1-$5）を作成
# - `zone_tmp.ch`（$6-）を作成（ゾーン情報がない場合は `NO_TIMEZONE` を記録）
# - `zonename.ch`、`timezone.ch` は `select_zone()` で作成
#########################################################################
country_write() {
    local tmp_country="${CACHE_DIR}/country_tmp.ch"
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_language="${CACHE_DIR}/language.ch"
    local cache_luci="${CACHE_DIR}/luci.ch"
    local cache_zone="${CACHE_DIR}/zone.ch"

    local country_data=$(cat "$tmp_country" 2>/dev/null)
    if [ -z "$country_data" ]; then
        return
    fi

    local short_code=$(echo "$country_data" | awk '{print $5}')
    local luci_code=$(echo "$country_data" | awk '{print $4}')
    local zone_data=$(echo "$country_data" | awk '{for(i=6; i<=NF; i++) printf "%s ", $i; print ""}')

    echo "$country_data" > "$cache_country"
    echo "$short_code" > "$cache_language"
    echo "$luci_code" > "$cache_luci"
    echo "$zone_data" > "$cache_zone"

    chmod 444 "$cache_country" "$cache_language" "$cache_luci" "$cache_zone"
    
    normalize_country
}

#########################################################################
# Last Update: 2025-02-12 17:25:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path.""
# select_zone: 選択した国に対応するタイムゾーンを選択
#
# [1] ユーザーがゾーンを選択 ← zone.ch
# [2] 一時キャッシュに保存 (zone_tmp.ch)
# [3] zone.ch から zonename.ch, timezone.ch を分離
# [4] zonename.ch, timezone.ch を書き込み禁止にする
#[5] → normalize_country()
#########################################################################
select_zone() {
    local cache_zone="${CACHE_DIR}/zone.ch"
    local cache_zone_tmp="${CACHE_DIR}/zone_tmp.ch"
    local cache_zonename="${CACHE_DIR}/zonename.ch"
    local cache_timezone="${CACHE_DIR}/timezone.ch"
    local flag_zone="${CACHE_DIR}/timezone_success_done"
    
    if [ -s "$cache_zonename" ] && [ -s "$cache_timezone" ]; then
        debug_log "INFO" "Timezone is already set. Skipping select_zone()."
        return
    fi
    
    local zone_data=$(cat "$cache_zone" 2>/dev/null)
    if [ -z "$zone_data" ]; then
        return
    fi

    local formatted_zone_list=$(awk '{gsub(",", " "); for (i=1; i<=NF; i+=2) print $i, $(i+1)}' "$cache_zone")

    selection_list "$formatted_zone_list" "$cache_zone_tmp" "zone"

    local selected_zone=$(cat "$cache_zone_tmp" 2>/dev/null)
    if [ -z "$selected_zone" ]; then
        return
    fi

    local zonename=$(echo "$selected_zone" | awk '{print $1}')
    local timezone=$(echo "$selected_zone" | awk '{print $2}')

    echo "$zonename" > "$cache_zonename"
    echo "$timezone" > "$cache_timezone"

    chmod 444 "$cache_zonename" "$cache_timezone"

    if [ ! -f "$flag_zone" ]; then
        echo "$(get_message "MSG_TIMEZONE_SUCCESS")"
        touch "$flag_zone"
    fi
}

#########################################################################
# Last Update: 2025-02-12 17:10:05 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# normalize_country: 言語設定の正規化
#
# 【要件】
# 1. 言語の決定:
#    - `country.ch` を最優先で参照（変更不可）
#    - `country.ch` が無い場合は `select_country()` を実行し、手動選択
#
# 2. システムメッセージの言語 (`message.ch`) の確定:
#    - `message.db` の `SUPPORTED_LANGUAGES` を確認
#    - `country.ch` に記録された言語が `SUPPORTED_LANGUAGES` にあれば、それを `message.ch` に保存
#    - `SUPPORTED_LANGUAGES` に無い場合、`message.ch` に `en` を設定
#
# 3. `country.ch` との関係:
#    - `country.ch` はデバイス設定用（変更不可）
#    - `message.ch` はシステムメッセージ表示用（フォールバック可能）
#
# 4. メンテナンス:
#    - `country.ch` はどのような場合でも変更しない
#    - `message.ch` のみフォールバックを適用し、システムメッセージの一貫性を維持
#    - 言語設定に影響を与えず、メッセージの表示のみを制御する
#########################################################################
normalize_country() {
    local message_db="${BASE_DIR}/messages.db"
    local country_cache="${CACHE_DIR}/country.ch"  # 主（真）データ
    local message_cache="${CACHE_DIR}/message.ch"
    local selected_language=""
    local flag_file="${CACHE_DIR}/country_success_done"

    # もし既に「国と言語設定完了」を示すフラグファイルがあれば、何もしない
    if [ -f "$flag_file" ]; then
        debug_log "INFO" "normalize_country() already done. Skipping repeated success message."
        return
    fi

    # ✅ `country.ch` が存在しない場合、エラーを返して終了
    if [ ! -f "$country_cache" ]; then
        debug_log "ERROR: country.ch not found. Cannot determine language."
        return
    fi

    # ✅ `country.ch` の $5（国コード）を取得
    selected_language=$(awk '{print $5}' "$country_cache")

    debug_log "DEBUG: Selected language extracted from country.ch -> $selected_language"

    # ✅ `messages.db` からサポートされている言語を取得
    local supported_languages
    supported_languages=$(grep "^SUPPORTED_LANGUAGES=" "$message_db" | cut -d'=' -f2 | tr -d '"')

    # ✅ `selected_language` が `messages.db` にある場合、それを `message.ch` に設定
    if echo "$supported_languages" | grep -qw "$selected_language"; then
        debug_log "INFO: Using message database language: $selected_language"
        echo "$selected_language" > "$message_cache"
    else
        debug_log "WARNING: Language '$selected_language' not found in messages.db. Using 'en' as fallback."
        echo "US" > "$message_cache"
    fi

    debug_log "INFO: Final system message language -> $(cat "$message_cache")"
    echo "$(get_message "MSG_COUNTRY_SUCCESS")"
    touch "$flag_file"    
}

# 🔴　ランゲージ（言語・ゾーン）系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

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

# 🔵　パッケージ系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# Last Update: 2025-02-15 10:00:00 (JST) 🚀
# install_package: パッケージのインストール処理 (OpenWrt / Alpine Linux)
#
# 【概要】
# 指定されたパッケージをインストールし、オプションに応じて以下の処理を実行する。
#
# 【フロー】
# 1️⃣ install_package update が実行された場合、opkg update / apk update を実行
# 2️⃣ デバイスにパッケージがインストール済みか確認
# 3️⃣ パッケージがリポジトリに存在するか確認
# 4️⃣ インストール確認（yn オプションが指定された場合）
# 5️⃣ インストールの実行
# 6️⃣ 言語パッケージの適用（dont オプションがない場合）
# 7️⃣ package.db の適用（notset オプションがない場合）
# 8️⃣ 設定の有効化（デフォルト enabled、disabled オプションで無効化）
#
# 【オプション】
# - yn         : インストール前に確認する（デフォルト: 確認なし）
# - dont       : 言語パッケージの適用をスキップ（デフォルト: 適用する）
# - notset     : package.db での設定適用をスキップ（デフォルト: 適用する）
# - disabled   : 設定を disabled にする（デフォルト: enabled）
# - update     : opkg update または apk update を実行（他の場所では update しない）
# - hidden     : 既にインストール済みの場合、"パッケージ xxx はすでにインストールされています" のメッセージを非表示にする
#
# 【仕様】
# - downloader_ch から opkg または apk を取得し、適切なパッケージ管理ツールを使用
# - messages.db を参照し、すべてのメッセージを取得（JP/US 対応）
# - package.db の設定がある場合、uci set を実行し適用（notset オプションで無効化可能）
# - 言語パッケージは luci-app-xxx 形式を対象に適用（dont オプションで無効化可能）
# - 設定の有効化はデフォルト enabled、disabled オプション指定時のみ disabled
# - update は明示的に install_package update で実行（パッケージインストール時には自動実行しない）
#
# 【使用例】
# - install_package update                → パッケージリストを更新
# - install_package ttyd                  → ttyd をインストール（確認なし、package.db 適用、言語パック適用）
# - install_package ttyd yn               → ttyd をインストール（確認あり）
# - install_package ttyd dont             → ttyd をインストール（言語パック適用なし）
# - install_package ttyd notset           → ttyd をインストール（package.db の適用なし）
# - install_package ttyd disabled         → ttyd をインストール（設定を disabled にする）
# - install_package ttyd yn dont disabled hidden
#   → ttyd をインストール（確認あり、言語パック適用なし、設定を disabled にし、
#      既にインストール済みの場合のメッセージは非表示）
#########################################################################
install_package() {
    local package_name="$1"
    shift  # 最初の引数 (パッケージ名) を取得し、残りをオプションとして処理

    # オプション解析
    local confirm_install="no"
    local skip_lang_pack="no"
    local skip_package_db="no"
    local set_disabled="no"
    local hidden="no"   # hidden オプション：既にインストール済みの場合のメッセージを抑制

    for arg in "$@"; do
        case "$arg" in
            yn) confirm_install="yes" ;;
            dont) skip_lang_pack="yes" ;;
            notset) skip_package_db="yes" ;;
            disabled) set_disabled="yes" ;;
            update) 
                if [ "$PACKAGE_MANAGER" = "opkg" ]; then
                    opkg update
                elif [ "$PACKAGE_MANAGER" = "apk" ]; then
                    apk update
                fi
                ;;
            hidden) hidden="yes" ;;
        esac
    done

    # downloader_ch からパッケージマネージャーを取得
    if [ -f "${BASE_DIR}/downloader_ch" ]; then
        PACKAGE_MANAGER=$(cat "${BASE_DIR}/downloader_ch")
    else
        echo "$(get_message "MSG_PACKAGE_MANAGER_NOT_FOUND")"
        return 1
    fi

    # すでにインストール済みか確認
    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        if opkg list-installed | grep -q "^$package_name "; then
            if [ "$hidden" != "yes" ]; then
                echo "$(get_message "MSG_PACKAGE_ALREADY_INSTALLED" | sed "s/{pkg}/$package_name/")"
            fi
            return 0
        fi
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        if apk list-installed | grep -q "^$package_name "; then
            if [ "$hidden" != "yes" ]; then
                echo "$(get_message "MSG_PACKAGE_ALREADY_INSTALLED" | sed "s/{pkg}/$package_name/")"
            fi
            return 0
        fi
    fi

    # インストール確認 (yn オプションが指定された場合)
    if [ "$confirm_install" = "yes" ]; then
        while true; do
            echo "$(get_message "MSG_CONFIRM_INSTALL" | sed "s/{pkg}/$package_name/")"
            echo -n "$(get_message "MSG_CONFIRM_ONLY_YN")"
            read -r yn
            case "$yn" in
                [Yy]*) break ;;
                [Nn]*) echo "$(get_message "MSG_INSTALL_ABORTED")"; return 1 ;;
                *) echo "Invalid input. Please enter Y or N." ;;
            esac
        done
    fi

    # パッケージのインストール (DEV_NULL に応じて出力制御)
    if [ "$DEV_NULL" = "on" ]; then
        $PACKAGE_MANAGER install "$package_name" > /dev/null 2>&1
    else
        $PACKAGE_MANAGER install "$package_name"
    fi

    # package.db の適用 (notset オプションがない場合)
    if [ "$skip_package_db" = "no" ] && grep -q "^$package_name=" "${BASE_DIR}/packages.db"; then
        eval "$(grep "^$package_name=" "${BASE_DIR}/packages.db" | cut -d'=' -f2-)"
    fi

    # 設定の有効化/無効化
    if [ "$skip_package_db" = "no" ]; then
        if uci get "$package_name.@$package_name[0].enabled" >/dev/null 2>&1; then
            if [ "$set_disabled" = "yes" ]; then
                uci set "$package_name.@$package_name[0].enabled=0"
            else
                uci set "$package_name.@$package_name[0].enabled=1"
            fi
            uci commit "$package_name"
        fi
    fi

    # 言語パッケージの適用 (dont オプションがない場合)
    if [ "$skip_lang_pack" = "no" ] && echo "$package_name" | grep -qE '^luci-app-'; then
        local lang_code
        lang_code=$(cat "${CACHE_DIR}/luci.ch" 2>/dev/null || echo "en")
        local lang_package="luci-i18n-${package_name#luci-app-}-$lang_code"

        if [ "$DEV_NULL" = "on" ]; then
            if $PACKAGE_MANAGER list > /dev/null 2>&1 | grep -q "^$lang_package "; then
                install_package "$lang_package" hidden
            else
                if [ "$lang_code" = "xx" ]; then
                    if $PACKAGE_MANAGER list > /dev/null 2>&1 | grep -q "^luci-i18n-${package_name#luci-app-}-en "; then
                        install_package "luci-i18n-${package_name#luci-app-}-en" hidden
                    elif $PACKAGE_MANAGER list > /dev/null 2>&1 | grep -q "^luci-i18n-${package_name#luci-app-} "; then
                        install_package "luci-i18n-${package_name#luci-app-}" hidden
                    fi
                fi
            fi
        else
            if $PACKAGE_MANAGER list | grep -q "^$lang_package "; then
                install_package "$lang_package"
            else
                if [ "$lang_code" = "xx" ]; then
                    if $PACKAGE_MANAGER list | grep -q "^luci-i18n-${package_name#luci-app-}-en "; then
                        install_package "luci-i18n-${package_name#luci-app-}-en"
                    elif $PACKAGE_MANAGER list | grep -q "^luci-i18n-${package_name#luci-app-} "; then
                        install_package "luci-i18n-${package_name#luci-app-}"
                    fi
                fi
            fi
        fi
    fi

    # サービスの有効化/開始
    if [ "$set_disabled" = "no" ] && ! echo "$package_name" | grep -qE '^(lib|luci)$'; then
        if [ -f "/etc/init.d/$package_name" ]; then
            /etc/init.d/$package_name enable
            /etc/init.d/$package_name start
        fi
    fi
}

# 🔴　パッケージ系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------


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
# handle_exit: 正常終了メッセージを表示して終了
#########################################################################
handle_exit() {
    local message="$1"
    color yellow "$message"
    exit 0
}

#########################################################################
# Last Update: 2025-02-15 10:00:00 (JST) 🚀
# check_option: コマンドラインオプション解析関数
#
# 【概要】
# この関数は、aios 起動時に渡されたコマンドライン引数を解析し、以下のグローバルオプションを設定します。
#
# 【対応オプション】
#  - -h, --help              : ヘルプメッセージを表示して終了
#  - -v, --version           : スクリプトのバージョン情報を表示して終了
#  - -d, --debug, --debug1   : デバッグモードを有効にし、DEBUG_LEVEL を "DEBUG" に設定
#  - --debug2                : DEBUG_LEVEL を "DEBUG2" に設定
#  - --debug3                : DEBUG_LEVEL を "DEBUG3" に設定
#  - -m, --mode <mode>       : 動作モードを指定 (full, light, debug)。指定がなければデフォルトは full
#  - -l, --logfile <path>    : ログ出力先のパスを指定
#  - -f, --force             : 強制実行モード。確認プロンプトをスキップして処理を実行
#  - --dry-run               : ドライランモード。実際の変更を行わず、処理内容をシミュレーション表示
#  - --reset                 : キャッシュ（country.ch、luci.ch、zone.ch など）をリセットする
#
# なお、言語オプションは、オプションとして "-" や "--" を付けずに、非オプション引数として
# 渡され、最初に見つかったものが SELECTED_LANGUAGE に設定されます。
#
# 【仕様】
# 1. この関数は、渡された引数を解析し、以下のグローバル変数を設定します：
#      SELECTED_LANGUAGE, DEBUG_MODE, DEBUG_LEVEL, MODE, DRY_RUN, LOGFILE, FORCE, RESET, HELP
#
# 2. オプションの位置は自由で、"-" および "--" の両形式が認識されます。
#
# 3. チェック後、グローバル変数はエクスポートされ、check_common() や select_country() などで利用されます。
#
# 【使用例】
#   sh aios.sh -d --mode light -l /var/log/aios.log -f --dry-run --reset en
#    → 言語 "en" が指定され、デバッグモード有効 (DEBUG_LEVEL="DEBUG")、モードは light、
#       ログ出力先は /var/log/aios.log、強制実行、ドライラン、キャッシュリセットが有効になる。
#########################################################################
check_option() {
    # デフォルト値の設定
    SELECTED_LANGUAGE=""
    DEBUG_MODE="false"
    DEBUG_LEVEL="INFO"
    MODE="full"
    DRY_RUN="false"
    LOGFILE=""
    FORCE="false"
    RESET="false"
    HELP="false"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                HELP="true"
                shift
                ;;
            -v|--version)
                echo "AIOS version: $AIOS_VERSION"
                exit 0
                ;;
            -d|--debug|-debug|--debug1)
                DEBUG_MODE="true"
                DEBUG_LEVEL="DEBUG"
                shift
                ;;
            --debug2)
                DEBUG_MODE="true"
                DEBUG_LEVEL="DEBUG2"
                shift
                ;;
            --debug3)
                DEBUG_MODE="true"
                DEBUG_LEVEL="DEBUG3"
                shift
                ;;
            -m|--mode)
                if [ -n "$2" ]; then
                    MODE="$2"
                    shift 2
                else
                    echo "Error: --mode requires an argument (full, light, debug)"
                    exit 1
                fi
                ;;
            -l|--logfile)
                if [ -n "$2" ]; then
                    LOGFILE="$2"
                    shift 2
                else
                    echo "Error: --logfile requires a path argument"
                    exit 1
                fi
                ;;
            -f|--force)
                FORCE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --reset)
                RESET="true"
                shift
                ;;
            -*)
                # 未知のオプションについては警告して無視
                echo "Warning: Unknown option: $1" >&2
                shift
                ;;
            *)
                # オプションでない引数は、最初に見つかったものを言語として設定
                if [ -z "$SELECTED_LANGUAGE" ]; then
                    SELECTED_LANGUAGE="$1"
                fi
                shift
                ;;
        esac
    done

    export SELECTED_LANGUAGE DEBUG_MODE DEBUG_LEVEL MODE DRY_RUN LOGFILE FORCE RESET HELP

    debug_log "DEBUG" "check_option: SELECTED_LANGUAGE='$SELECTED_LANGUAGE', DEBUG_MODE='$DEBUG_MODE', DEBUG_LEVEL='$DEBUG_LEVEL', MODE='$MODE', DRY_RUN='$DRY_RUN', LOGFILE='$LOGFILE', FORCE='$FORCE', RESET='$RESET', HELP='$HELP'"
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
#    - 言語キャッシュ (`country.ch`) の有無を `select_country()` に判定させる
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
    local lang_code="$SELECTED_LANGUAGE"
    
    debug_log "INFO" "check_common called with lang_code: '$lang_code' and MODE: '$MODE'"
    script_update || handle_error "ERR_SCRIPT_UPDATE" "script_update" "latest"
    download openwrt.db || handle_error "ERR_DOWNLOAD" "openwrt.db" "latest"
    download messages.db || handle_error "ERR_DOWNLOAD" "messages.db" "latest"
    download country.db || handle_error "ERR_DOWNLOAD" "country.db" "latest"
    download packages.db || handle_error "ERR_DOWNLOAD" "packages.db" "latest"
    check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
    get_package_manager
    select_country

    # MODE に応じた処理の振り分け
    case "$MODE" in
        full)
            common_full "$lang_code"
            ;;
        light)
            common_light "$lang_code"
            ;;
        debug)
            common_debug "$lang_code"
            ;;
        *)
            common_full "$lang_code"
            ;;
    esac
}

