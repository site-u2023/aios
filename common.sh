#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important! OpenWrt OS only works with Almquist Shell, not Bourne-again shell.
# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

COMMON_VERSION="2025.02.14-13-9"

# 基本定数の設定
BASE_WGET="wget --quiet -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
mkdir -p "$CACHE_DIR" "$LOG_DIR"
DEBUG_MODE="${DEBUG_MODE:-false}"

# 環境変数 INPUT_LANG のチェック（デフォルト 'ja' とする）
# INPUT_LANG="${INPUT_LANG:-ja}"
debug_log "common.sh received INPUT_LANG: '$INPUT_LANG'"

script_update() (
    COMMON_CACHE="${CACHE_DIR}/common_version.ch"
    # キャッシュが存在しない、またはバージョンが異なる場合にアラートを表示
    if [ ! -f "$COMMON_CACHE" ] || [ "$(cat "$COMMON_CACHE" | tr -d '\r\n')" != "$COMMON_VERSION" ]; then
        echo -e "`color white_black "common.sh Updated to version $COMMON_VERSION"`"
        echo "$COMMON_VERSION" > "$COMMON_CACHE"
    fi
)

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



# 🔵　ランゲージ（言語・ゾーン）系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# Last Update: 2025-02-12 17:25:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# select_country: ユーザーに国の選択を促す（検索機能付き）
#
# select_country()
# ├── selection_list()  → 選択結果を country_tmp.ch に保存
# ├── country_write()   → country.ch, language.ch, luci.ch, zone.ch に確定
# └── select_zone()     → zone.ch から zonename.ch, timezone.ch に確定
#
# [1] ユーザーが国を選択 → selection_list()
# [2] 一時キャッシュに保存 (country_tmp.ch)
# [3] country_write() を実行
# [4] 確定キャッシュを作成（country.ch, language.ch, luci.ch, zone.ch）→ 書き込み禁止にする
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
            printf  "$predefined_country" > "$tmp_country"
            country_write
            select_zone  
            return
        else
            debug_log "ERROR" "Invalid input '$1' is not a valid country."
            printf  "$(color red "Error: '$1' is not a recognized country name or code.")"
            printf  "$(color yellow "Switching to language selection.")"
            set --  
        fi
    fi

    if [ -f "$cache_country" ]; then
        debug_log "INFO" "Country cache found. Skipping selection."
        select_zone
        return
    fi

    while true; do
        printf  "$(color cyan "Enter country name, code, or language to search.")"
        printf "%s" "Search (Keyword/Code): "
        read -r input

        local search_results=$(awk -v search="$input" 'BEGIN {IGNORECASE=1} 
            $2 ~ search || $3 ~ search || $4 ~ search || $5 ~ search {print $0}' "$BASE_DIR/country.db")

        if [ -z "$search_results" ]; then
            printf  "$(color red "Error: No matching country found for '$input'. Please try again.")"
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
        printf "%s\n" "$(color cyan "Enter the number of your choice.")"
        printf "Select Number: "
        read -r choice

        local selected_value
        selected_value=$(awk -v num="$choice" 'NR == num {print $0}' "$list_file")

        if [ -z "$selected_value" ]; then
            printf "%s\n" "$(color red "Invalid selection. Please choose a valid number.")"
            continue
        fi

        local confirm_info=""
        if [ "$mode" = "country" ]; then
            confirm_info=$(echo "$selected_value" | awk '{print $2, $3, $4, $5}')
        elif [ "$mode" = "zone" ]; then
            confirm_info=$(echo "$selected_value" | awk '{print $1, $2}')
        fi

        printf "%s\n" "$(color cyan "Confirm selection: [$choice] $confirm_info")"
        printf "Confirm (Y=Yes / N=No / R=Restart): "
        read -r yn

        case "$yn" in
            [Yy]*) 
                printf "%s\n" "$selected_value" > "$output_file"
                return
                ;;
            [Nn]*) 
                printf "%s\n" "$(color yellow "Returning to selection.")"
                continue
                ;;
            [Rr]*) 
                check_common
                return
                ;;
            *) 
                printf "%s\n" "$(color red "Invalid input. Please enter 'Y', 'N', or 'R'.")"
                continue
                ;;
        esac
    done
}


XXX_selection_list() {
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
            local extracted=$(echo "$line" | awk '{print $2, $3, $4, $5}')
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
        printf "%s" "$(color cyan "Enter the number of your choice: ")"
        read -r choice

        if [ "$choice" = "R" ] || [ "$choice" = "r" ]; then
            debug_log "INFO" "User selected R: Returning to language selection start."
            check_common
            return
        fi

        local selected_value
        selected_value=$(awk -v num="$choice" 'NR == num {print $0}' "$list_file")

        if [ -z "$selected_value" ]; then
            printf "%s\n" "$(color red "Invalid selection. Please choose a valid number.")"
            printf "%s\n" "$display_list"
            continue
        fi
        
        if [ "$mode" = "country" ]; then
            local confirm_info=$(printf "%s\n" "$selected_value" | awk '{print $2, $3, $4, $5}')
        elif [ "$mode" = "zone" ]; then
            local confirm_info=$(printf "%s\n" "$selected_value" | awk '{print $1, $2}')
        fi

        printf "%s\n" "$(color cyan "Confirm selection: [$choice] $confirm_info")"
        printf "%s" "(Y/N/R)?: "
        read -r yn

        case "$yn" in
            [Yy]*) printf "%s\n" "$selected_value" > "$output_file"
                   return
                   ;;
            [Nn]*) printf "%s\n" "$(color yellow "Returning to selection.")"
                   selection_list "$input_data" "$output_file" "$mode"
                   continue
                   ;;
            [Rr]*) check_common
                   return
                   ;;
            *)     printf "%s\n" $(color red "Invalid input. Please enter 'Y', 'N', or 'R'.")
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
#       - `language.ch` (`$3`: 言語名)
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
#     - `language.ch`
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
# - `language.ch` に **$3（言語名）** を保存
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

    echo "$(get_message "MSG_TIMEZONE_SUCCESS")"
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

# 🔴　ランゲージ（言語・ゾーン）系　ここまで　-------------------------------------------------------------------------------------------------------------------------------------------

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
    local lang_code="$1"
    
    debug_log "INFO" "check_common called with lang_code: '$lang_code'"
    script_update || handle_error "ERR_SCRIPT_UPDATE" "script_update" "latest"
    download_script messages.db || handle_error "ERR_DOWNLOAD" "messages.db" "latest"
    download_script country.db || handle_error "ERR_DOWNLOAD" "country.db" "latest"
    download_script openwrt.db || handle_error "ERR_DOWNLOAD" "openwrt.db" "latest"
    check_openwrt || handle_error "ERR_OPENWRT_VERSION" "check_openwrt" "latest"
    select_country "$lang_code"
}

XXX_check_common() {
    local mode="$1"
    local lang_code="$2"  # ✅ `$1` は mode、`$2` は言語情報
    
    local lang_code="${1:-}"  # ✅ `$1` を `lang_code` にセット
    #SELECTED_LANGUAGE="$lang_code"
    debug_log "check_common received lang_code: '$lang_code'"

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
