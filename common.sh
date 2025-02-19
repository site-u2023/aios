#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important! OpenWrt OS only works with Almquist Shell, not Bourne-again shell.
# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

SCRIPT_VERSION="2025.02.19-08-05"
echo -e "\033[7;40mUpdated to version $SCRIPT_VERSION common.sh \033[0m"

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

# 🔵　エラー・デバッグ・アップデート系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# Last Update: 2025-02-16 16:00:00 (JST) 🚀
# "Clarity in errors, precision in handling. Every function must be robust."
#
# 【要件】
# 1. すべてのエラーメッセージを `messages.db` で管理し、多言語対応する。
# 2. `debug_log("ERROR", message)` も `message.db` を使用する。
# 3. `{file}`, `{version}` などの変数を動的に置換。
# 4. 影響範囲: `aios` & `common.sh`（矛盾なく適用）。
#########################################################################
handle_error() {
    local error_key="$1"
    local file="$2"
    local version="$3"
    local exit_required="${4:-no}"

    local error_message
    error_message=$(get_message "$error_key")

    # メッセージが取得できなかった場合のフォールバック
    if [ -z "$error_message" ]; then
        error_message="Unknown error occurred. Key: $error_key"
    fi

    # 変数を置換
    error_message=$(echo "$error_message" | sed -e "s/{file}/$file/g" -e "s/{version}/$version/g")

    # ログ記録 & 表示
    debug_log "ERROR" "$error_message"
    echo -e "$(color red "$error_message")"

    if [ "$exit_required" = "yes" ]; then
        debug_log "ERROR" "Critical error occurred, exiting: $error_message"
        exit 1
    else
        debug_log "WARN" "Non-critical error: $error_message"
        return 1
    fi
}

#########################################################################
# Last Update: 2025-02-16 16:10:00 (JST) 🚀
# "Logging with clarity, debugging with precision."
#
# 【要件】
# 1. すべてのログメッセージを `messages.db` で管理し、多言語対応する。
# 2. `{file}`, `{version}` などの変数を `sed` で動的に置換する。
# 3. `DEBUG_MODE` の設定に応じて `DEBUG`, `INFO`, `WARN`, `ERROR` を管理する。
# 4. 影響範囲: `aios` & `common.sh`（矛盾なく適用）。
#########################################################################
debug_log() {
    local level="$1"
    local message="$2"
    local file="$3"
    local version="$4"

    # `$1` にログレベルが指定されていない場合、デフォルトを `DEBUG` にする
    case "$level" in
        "DEBUG"|"INFO"|"WARN"|"ERROR") ;;  # 何もしない (正しいログレベル)
        "")
            level="DEBUG"
            message="$1"
            file="$2"
            version="$3"
            ;;
        *)
            message="$1"
            file="$2"
            version="$3"
            level="DEBUG"
            ;;
    esac

    # 変数を置換
    message=$(echo "$message" | sed -e "s/{file}/$file/g" -e "s/{version}/$version/g")

    # ログレベル制御
    case "$DEBUG_LEVEL" in
        DEBUG)    allowed_levels="DEBUG INFO WARN ERROR" ;;
        INFO)     allowed_levels="INFO WARN ERROR" ;;
        WARN)     allowed_levels="WARN ERROR" ;;
        ERROR)    allowed_levels="ERROR" ;;
        *)        allowed_levels="ERROR" ;;
    esac

    if echo "$allowed_levels" | grep -q "$level"; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local log_message="[$timestamp] $level: $message"

        # カラー表示
        case "$level" in
            "ERROR") echo -e "$(color red "$log_message")" ;;
            "WARN") echo -e "$(color yellow "$log_message")" ;;
            "INFO") echo -e "$(color cyan "$log_message")" ;;
            "DEBUG") echo -e "$(color white "$log_message")" ;;
        esac

        # ログファイルに記録
        echo "$log_message" >> "$LOG_DIR/debug.log"
    fi
}


#########################################################################
# Last Update: 2025-02-16 17:30:00 (JST) 🚀
# "Debug with clarity, test with precision. Every log tells a story."
#
# 【要件】
# 1. `test_country_search()`, `test_timezone_search()`, `test_cache_contents()` を統合。
# 2. `debug_log()` を使用し、メッセージを `message.db` から取得。
# 3. `country.db` の検索結果が適切に出力されるか確認できるようにする。
# 4. 影響範囲: `common.sh` のみ（`aios` には影響なし）。
#########################################################################
test_debug_functions() {
    local test_type="$1"
    local test_input="$2"

    case "$test_type" in
        country)
            debug_log "INFO" "MSG_TEST_COUNTRY_SEARCH" "$test_input"
            if [ ! -f "${BASE_DIR}/country.db" ]; then
                handle_error "ERR_FILE_NOT_FOUND" "country.db"
                return 1
            fi
            awk -v query="$test_input" '
                $2 ~ query || $3 ~ query || $4 ~ query || $5 ~ query {
                    print NR, $2, $3, $4, $5, $6, $7, $8, $9
                }' "${BASE_DIR}/country.db"
            ;;

        timezone)
            debug_log "INFO" "MSG_TEST_TIMEZONE_SEARCH" "$test_input"
            if [ ! -f "${BASE_DIR}/country.db" ]; then
                handle_error "ERR_FILE_NOT_FOUND" "country.db"
                return 1
            fi
            awk -v country="$test_input" '
                $2 == country || $4 == country || $5 == country {
                    print NR, $5, $6, $7, $8, $9, $10, $11
                }' "${BASE_DIR}/country.db"
            ;;

        cache)
            debug_log "INFO" "MSG_TEST_CACHE_CONTENTS"
            for cache_file in "country_tmp.ch" "zone_tmp.ch"; do
                if [ -f "${CACHE_DIR}/$cache_file" ]; then
                    debug_log "INFO" "MSG_CACHE_CONTENTS" "$cache_file"
                    cat "${CACHE_DIR}/$cache_file"
                else
                    debug_log "WARN" "MSG_CACHE_NOT_FOUND" "$cache_file"
                fi
            done
            ;;
        
        *)
            debug_log "ERROR" "ERR_INVALID_ARGUMENT" "$test_type"
            return 1
            ;;
    esac
}

# 🔴　エラー・デバッグ・アップデート系　ここまで　🔴-------------------------------------------------------------------------------------------------------------------------------------------

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
# check_downloader: パッケージマネージャー判定（apk / opkg 対応）
#########################################################################
check_downloader() {
    if [ -f "${BASE_DIR}/downloader_ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/downloader_ch")
    else
        if command -v apk >/dev/null 2>&1; then
            PACKAGE_MANAGER="apk"
        elif command -v opkg >/dev/null 2>&1; then
            PACKAGE_MANAGER="opkg"
        else
            PACKAGE_MANAGER="opkg"  # デフォルトをセット
        fi
        echo "$PACKAGE_MANAGER" > "${CACHE_DIR}/downloader_ch"
    fi
    echo -e "$(color green "Downloader $PACKAGE_MANAGER")"
}

#########################################################################
# Last Update: 2025-02-18 23:00:00 (JST) 🚀
# "Standardizing version formatting for consistency."
#
# 【要件】
# 1. **バージョン番号のフォーマットを統一**
#    - `YYYY.MM.DD-自由形式`
#    - `YYYYMMDDHHMMSS-自由形式`
#    - 許可される区切り文字: `- . , ; : 空白`
#
# 2. **処理内容**
#    - **許可された文字のみを抽出**
#    - **先頭のゼロを削除（例: `02` → `2`）**
#    - **前後の余計なスペースを削除**
#
# 3. **適用対象**
#    - **`download()`**: **スクリプトバージョンの取得・比較**
#    - **`compare_versions()`**: **バージョン比較時のフォーマット統一**
#
# 4. **適用しない対象**
#    - **バージョン番号の解釈を変更しない（順番の入れ替えはしない）**
#    - **日付以外の文字列は削除せず、フォーマットの標準化のみ行う**
#
# 5. **依存関係**
#    - `normalize_input()` を使用し、iconv による処理を統一
#
# 6. **影響範囲**
#    - `common.sh` に統合し、`download()` & `compare_versions()` で使用
#########################################################################
normalize_version() {
    input="$1"

    # **二バイト → 一バイト変換**
    input=$(normalize_input "$input")
    [ -z "$input" ] && { echo "Error: normalize_input() returned empty string"; return 1; }

    # **許可された文字（数字, 記号）以外を削除**
    input=$(echo "$input" | sed 's/[^0-9A-Za-z._-]//g')

    # **不要な改行やスペースを削除**
    input=$(echo "$input" | tr -d '\n' | sed 's/ *$//')

    # **区切り文字を正しく処理**
    input=$(echo "$input" | awk -F'[._-]' '{
        for (i=1; i<=NF; i++) {
            if ($i ~ /^[0-9]+$/) sub(/^0+/, "", $i)  # 先頭ゼロ削除（ただし区切りは保持）
            printf "%s%s", $i, (i<NF ? (FS == "_" ? "-" : ".") : "")
        }
        print ""
    }')

    echo "$input"
}

get_script_version() {
    local version=""
    version=$(grep -Eo 'SCRIPT_VERSION=["'"'"']?[0-9]{4}[-.][0-9]{2}[-.][0-9]{2}[-.0-9]*' "$0" | cut -d'=' -f2 | tr -d '"')
    version=$(normalize_version "$version")

    echo "$version"
}

#########################################################################
# Last Update: 2025-02-18 18:00:00 (JST) 🚀
# "Efficiency in retrieval, clarity in communication."
# get_message: システムメッセージを取得する関数
#
# 【要件】
# 1. **メッセージの取得ロジック**
#    - `$ACTIVE_LANGUAGE` を最優先で使用（`normalize_country()` で設定）
#    - `$ACTIVE_LANGUAGE` が未設定の場合は `US` をフォールバックとして使用
#
# 2. **メッセージ検索の順序**
#    ① `$ACTIVE_LANGUAGE|キー=` で `messages.db` を検索
#    ② `US|キー=` で `messages.db` を検索（フォールバック）
#    ③ どちらにも該当しない場合、`キー` をそのまま返す
#
# 3. **動作の最適化**
#    - `$ACTIVE_LANGUAGE` を直接参照し、キャッシュ (`message.ch`) には依存しない
#    - `$quiet_flag` に `"quiet"` が指定された場合、出力せずに `return 0`
#
# 4. **メンテナンス**
#    - 言語取得ロジックを `normalize_country()` に統一し、責務を分離
#    - `get_message()` は「取得するだけ」に特化し、書き込み・設定は行わない
#
# 5. **影響範囲**
#    - `common.sh` 内のメッセージ取得全般（`debug_log()` 含む）
#    - `messages.db` のフォーマット変更時も `get_message()` の修正は不要
#########################################################################
get_message() {
    local key="$1"
    local quiet_flag="$2"
    local message_db="${BASE_DIR}/messages.db"
    local lang="${ACTIVE_LANGUAGE:-US}"  # `ACTIVE_LANGUAGE` が未設定なら `US`

    # `messages.db` が存在しない場合、キーそのままを返す
    if [ ! -f "$message_db" ]; then
        debug_log "WARN" "messages.db not found. Returning key as message."
        message="$key"
    else
        # **言語優先検索**
        message=$(grep "^${lang}|${key}=" "$message_db" | cut -d'=' -f2-)

        # **フォールバック検索**
        if [ -z "$message" ]; then
            message=$(grep "^US|${key}=" "$message_db" | cut -d'=' -f2-)
        fi

        # **それでも見つからなければ、キーそのままを返す**
        if [ -z "$message" ]; then
            debug_log "WARN" "Message key '$key' not found in messages.db."
            message="$key"
        fi
    fi

    # **quiet モード対応**
    if [ "$quiet_flag" = "quiet" ]; then
        return 0
    else
        echo "$message"
    fi
}

# 🔵　ダウンロード系　ここから　🔵　-------------------------------------------------------------------------------------------------------------------------------------------

#########################################################################
# Last Update: 2025-02-18 23:30:00 (JST) 🚀
# "Efficient downloading with precise versioning and silent modes."
#
# 【要件】
# 1. `BASE_WGET` を使用してファイルをダウンロードする。
# 2. `hidden` オプション:
#    - ダウンロードの成否ログを記録するが、既存ファイルがある場合の出力を抑制する。
# 3. `quiet` オプション:
#    - `check_option()` で設定された `QUIET_MODE` に従い、すべてのログを抑制する。
# 4. **引数の順序は自由** (`hidden` `quiet` の順番は任意)。
# 5. `wget` のエラーハンドリングを行い、失敗時の詳細を `debug_log()` に記録する。
# 6. **影響範囲:** `common.sh` の `download()` のみ（他の関数には影響なし）。
#########################################################################
download() {
    # **バージョン情報の表示**
    if [ "$QUIET_MODE" != "true" ]; then
        echo -e "$(color cyan "Executing download function - Version: ${SCRIPT_VERSION}")"
    fi

    local hidden_mode="false"
    local quiet_mode="${QUIET_MODE:-false}"
    local file_name=""

    # **引数解析（順不同対応）**
    while [ "$#" -gt 0 ]; do
        case "$1" in
            hidden) hidden_mode="true" ;;
            quiet) quiet_mode="true" ;;
            *) file_name="$1" ;;  # 最初に見つかった非オプション引数をファイル名とする
        esac
        shift
    done

    # **ファイル名の正規化**
    file_name=$(normalize_input "$file_name")

    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"

    # **既存ファイルのチェック**
    if [ -f "$install_path" ]; then
        if [ "$hidden_mode" = "true" ]; then
            return 0
        fi
        if [ "$quiet_mode" != "true" ]; then
            echo "$(color yellow "$file_name already exists. Skipping download.")"
        fi
        return 0
    fi

    # **ダウンロード開始**
    debug_log "DEBUG" "Starting download of $file_name from $remote_url"
    if ! $BASE_WGET "$install_path" "$remote_url"; then
        debug_log "ERROR" "Download failed: $file_name"
        return 1
    fi

    # **空ファイルチェック**
    if [ ! -s "$install_path" ]; then
        debug_log "ERROR" "Download failed: $file_name is empty."
        return 1
    fi

    # **ダウンロード成功メッセージ**
    if [ "$quiet_mode" != "true" ]; then
        echo "$(color green "Download completed: $file_name")"
    fi

    debug_log "INFO" "Download completed: $file_name is valid."
    return 0
}

# 🔴　ダウンロード系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　ランゲージ（言語・ゾーン）系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------
#########################################################################
# Last Update: 2025-02-18 23:00:00 (JST) 🚀
# "Ensuring consistent input handling and text normalization."
#
# 【要件】
# 1. **入力テキストを正規化（Normalize Input）**
#    - `iconv` が利用可能な場合、UTF-8 から ASCII//TRANSLIT に変換
#    - `iconv` がない場合、元の入力をそのまま返す（スルー）
#
# 2. **適用対象**
#    - **`select_country()`**: **Y/N 確認時のみ適用**
#    - **`select_list()`**: **番号選択 & Y/N 確認時のみ適用**
#    - **`download()`**: **ファイル名の正規化**
#
# 3. **適用しない対象**
#    - **言語選択の曖昧検索には適用しない**（例: `日本語` → `ja` に変換しない）
#    - **バージョンフォーマットの変更はしない**
#
# 4. **依存関係**
#    - `iconv` が **ない場合は何もしない**
#    - `sed` や `awk` を使わず `echo` ベースで処理
#
# 5. **影響範囲**
#    - `common.sh` に統合し、全スクリプトで共通関数として利用
#########################################################################
normalize_input() {
    input="$1"
    # **全角数字 → 半角数字**
    input=$(echo "$input" | sed 'y/０１２３４５６７８９/0123456789/')

    # **不要なログを削除（echo のみを使用）**
    echo "$input"
}

#########################################################################
# Last Update: 2025-02-18 23:30:00 (JST) 🚀
# "Country selection with precise Y/N confirmation."
# select_country: ユーザーに国の選択を促す（検索機能付き）
#
# select_country()
# ├── select_list()  → 選択結果を country_tmp.ch に保存
# ├── country_write()   → country.ch, country.ch, luci.ch, zone.ch に確定
# └── select_zone()     → zone.ch から zonename.ch, timezone.ch に確定
#
# [1] ユーザーが国を選択 → select_list()
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
    debug_log "DEBUG" "Entering select_country() with arg: '$1'"

    local cache_country="${CACHE_DIR}/country.ch"
    local tmp_country="${CACHE_DIR}/country_tmp.ch"

    # **キャッシュがあればゾーン選択へスキップ**
    if [ -f "$cache_country" ]; then
        debug_log "INFO" "Country cache found. Skipping selection."
        select_zone
        return
    fi

    while true; do
        printf "%s\n" "$(color cyan "$(get_message "MSG_ENTER_COUNTRY")")"
        printf "%s" "$(color cyan "$(get_message "MSG_SEARCH_KEYWORD")")"
        read -r input

        # **入力の正規化: "/", ",", "_" をスペースに置き換え**
        local cleaned_input
        cleaned_input=$(echo "$input" | sed 's/[\/,_]/ /g')

        # **完全一致を優先（$2, $3, $4, $5 で検索）**
        local search_results
        search_results=$(awk -v search="$cleaned_input" 'BEGIN {IGNORECASE=1} 
            { key = $2" "$3" "$4" "$5; if ($0 ~ search && !seen[key]++) print $2, $3 }' "$BASE_DIR/country.db" 2>>"$LOG_DIR/debug.log")

        # **完全一致がない場合、部分一致を検索**
        if [ -z "$search_results" ]; then
            search_results=$(awk -v search="$cleaned_input" 'BEGIN {IGNORECASE=1} 
                { for (i=2; i<=NF; i++) if ($i ~ search) print $2, $3 }' "$BASE_DIR/country.db")
        fi

        # **検索結果がない場合のエラーハンドリング**
        if [ -z "$search_results" ]; then
            printf "%s\n" "$(color red "Error: No matching country found for '$input'. Please try again.")"
            continue
        fi

        # **検索結果リストを表示（$2, $3 のみ）**
        select_list "$search_results" "$tmp_country" "country"

        # **選択結果をキャッシュへ書き込み**
        country_write

        # **ゾーン選択へ進む**
        debug_log "INFO" "Country selection completed. Proceeding to select_zone()."
        select_zone
        return
    done
}

#########################################################################
# Last Update: 2025-02-18 23:30:00 (JST) 🚀
# "Handling numbered list selections with confirmation."
# select_list()
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
select_list() {
    local input_data="$1"
    local output_file="$2"
    local mode="$3"
    local list_file="${CACHE_DIR}/${mode}_tmp.ch"
    local i=1

    # **リストファイルを初期化**
    : > "$list_file"

    # **リストを表示**
    echo "$input_data" | while IFS= read -r line; do
        printf "[%d] %s\n" "$i" "$line"
        echo "$line" >> "$list_file"
        i=$((i + 1))
    done

    while true; do
        printf "%s\n" "$(color cyan "$(get_message "MSG_ENTER_NUMBER_CHOICE")")"
        printf "%s" "$(get_message "MSG_SELECT_NUMBER")"
        read -r choice

        # **入力を正規化（全角→半角）**
        choice=$(normalize_input "$choice")

        local selected_value
        selected_value=$(awk -v num="$choice" 'NR == num {print $0}' "$list_file")

        if [ -z "$selected_value" ]; then
            printf "%s\n" "$(color red "$(get_message "MSG_INVALID_SELECTION")")"
            debug_log "WARN" "Invalid selection: '$choice'. Available options: $(cat "$list_file")"
            continue
        fi

        printf "%s\n" "$(color cyan "$(get_message "MSG_CONFIRM_SELECTION")")"
        printf "%s" "$(get_message "MSG_CONFIRM_YNR")"
        read -r yn

        # **確認用の入力も正規化**
        yn=$(normalize_input "$yn")

        if [ "$yn" = "Y" ] || [ "$yn" = "y" ]; then
            printf "%s\n" "$selected_value" > "$output_file"
            return
        fi
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

    select_list "$formatted_zone_list" "$cache_zone_tmp" "zone"

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
# Last Update: 2025-02-18 11:00:00 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
# normalize_country: 言語設定の正規化
#
# 【要件】
# 1. 言語の決定:
#    - `country.ch` を最優先で参照（変更不可）
#    - `country.ch` が無い場合は `select_country()` を実行し、手動選択
#
# 2. システムメッセージの言語 (`message.ch`) の確定:
#    - `messages.db` の `SUPPORTED_LANGUAGES` を確認
#    - `country.ch` に記録された言語が `SUPPORTED_LANGUAGES` に含まれる場合、それを `message.ch` に保存
#    - `SUPPORTED_LANGUAGES` に無い場合、`message.ch` に `US`（フォールバック）を設定
#
# 3. `country.ch` との関係:
#    - `country.ch` はデバイス設定用（変更不可）
#    - `message.ch` はシステムメッセージ表示用（フォールバック可能）
#
# 4. `$ACTIVE_LANGUAGE` の管理:
#    - `normalize_country()` 実行時に `$ACTIVE_LANGUAGE` を設定
#    - `$ACTIVE_LANGUAGE` は `message.ch` の値を常に参照
#    - `$ACTIVE_LANGUAGE` が未設定の場合、フォールバックで `US`
#
# 5. メンテナンス:
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
        ACTIVE_LANGUAGE="$selected_language"  # ✅ `$ACTIVE_LANGUAGE` にも設定
    else
        debug_log "WARNING: Language '$selected_language' not found in messages.db. Using 'US' as fallback."
        echo "US" > "$message_cache"
        ACTIVE_LANGUAGE="US"  # ✅ フォールバック時も `$ACTIVE_LANGUAGE` に設定
    fi

    debug_log "INFO: Final system message language -> $ACTIVE_LANGUAGE"
    echo "$(get_message "MSG_COUNTRY_SUCCESS")"
    touch "$flag_file"    
}


# 🔴　ランゲージ（言語・ゾーン）系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　パッケージ系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------

#########################################################################
# Last Update: 2025-02-19 15:14:00 (JST) 🚀
# install_package: パッケージのインストール処理 (OpenWrt / Alpine Linux)
#
# 【概要】
# 指定されたパッケージをインストールし、オプションに応じて以下の処理を実行する。
#
# 【フロー】
# 2️⃣ デバイスにパッケージがインストール済みか確認
# 1️⃣ update は初回に一回のみ、opkg update / apk update を実行
# 3️⃣ パッケージがリポジトリに存在するか確認
# 4️⃣ インストール確認（yn オプションが指定された場合）
# 5️⃣ インストールの実行
# 6️⃣ 言語パッケージの適用（lang オプションがない場合）
# 7️⃣ package.db の適用（notpack オプションがない場合）
# 8️⃣ 設定の有効化（デフォルト enabled、disabled オプションで無効化）
#
# 【グローバルオプション】
# DEV_NULL
# DEBUG : 要所にセット
#
# 【オプション】
# - yn         : インストール前に確認する（デフォルト: 確認なし）
# - nolang     : 言語パッケージの適用をスキップ（デフォルト: 適用する）
# - notpack    : package.db での設定適用をスキップ（デフォルト: 適用する）
# - disabled   : 設定を disabled にする（デフォルト: enabled）
# - hidden     : 既にインストール済みの場合、"パッケージ xxx はすでにインストールされています" のメッセージを非表示にする
# - test       : インストール済みのパッケージであっても、インストール処理を実行する
# - update     : opkg update / apk update を強制的に実行し、update.ch のキャッシュを無視する
#
# 【仕様】
# - update.ch を書き出し、updateを管理する（${CACHE_DIR}/update.ch）
# - update オプションが指定された場合、update.ch のキャッシュを無視して強制的に update を実行
# - downloader_ch から opkg または apk を取得し、適切なパッケージ管理ツールを使用
# - messages.db を参照し、すべてのメッセージを取得（JP/US 対応）
# - package.db の設定がある場合、uci set を実行し適用（notset オプションで無効化可能）
# - 言語パッケージは luci-app-xxx 形式を対象に適用（dont オプションで無効化可能）
# - 設定の有効化はデフォルト enabled、disabled オプション指定時のみ disabled
# - update は明示的に install_package update で実行（パッケージインストール時には自動実行しない）
#
# 【使用例】
# - install_package ttyd                  → ttyd をインストール（確認なし、package.db 適用、言語パック適用）
# - install_package ttyd yn               → ttyd をインストール（確認あり）
# - install_package ttyd nolang           → ttyd をインストール（言語パック適用なし）
# - install_package ttyd notpack          → ttyd をインストール（package.db の適用なし）
# - install_package ttyd disabled         → ttyd をインストール（設定を disabled にする）
# - install_package ttyd yn nolang disabled hidden
#   → ttyd をインストール（確認あり、言語パック適用なし、設定を disabled にし、
#      既にインストール済みの場合のメッセージは非表示）
# - install_package ttyd test             → ttyd をインストール（インストール済みでも強制インストール）
# - install_package ttyd update           → ttyd をインストール（opkg update / apk update を強制実行）
#
# 【messages.dbの記述例】
# [ttyd]
# opkg update
# uci commit ttyd
# initd/ttyd/restat
# [ttyd] opkg update; uci commit ttyd; initd/ttyd/restat
#########################################################################
install_package() {
    local confirm_install="no"
    local skip_lang_pack="no"
    local skip_package_db="no"
    local set_disabled="no"
    local hidden="no"
    local test_mode="no"
    local package_name=""

    # オプションの処理
    for arg in "$@"; do
        case "$arg" in
            yn) confirm_install="yes" ;;
            nolang) skip_lang_pack="yes" ;;
            notpack) skip_package_db="yes" ;;
            disabled) set_disabled="yes" ;;
            hidden) hidden="yes" ;;
            test) test_mode="yes" ;;
            *)
                if [ -z "$package_name" ]; then
                    package_name="$arg"
                else
                    debug_log "WARN" "Unknown option: $arg"
                fi
                ;;
        esac
    done

    if [ -z "$package_name" ]; then
        echo "Error: No package specified." >&2
        return 1
    fi

    # まず、パッケージがすでにインストールされているか確認（testモード時はスキップ）
    if [ "$test_mode" = "no" ]; then
        if [ "$PACKAGE_MANAGER" = "opkg" ] && opkg list-installed | grep -q "^$package_name "; then
            [ "$hidden" != "yes" ] && echo "$(get_message "MSG_PACKAGE_ALREADY_INSTALLED" | sed "s/{pkg}/$package_name/")"
            return 0
        elif [ "$PACKAGE_MANAGER" = "apk" ] && apk list-installed | grep -q "^$package_name "; then
            [ "$hidden" != "yes" ] && echo "$(get_message "MSG_PACKAGE_ALREADY_INSTALLED" | sed "s/{pkg}/$package_name/")"
            return 0
        fi
    fi

    # 最初の実行時に一度だけ update を実行
    if [ ! -f "${CACHE_DIR}/update.ch" ]; then
        debug_log "INFO" "Running package manager update..."
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            if opkg update > /dev/null 2>&1; then
                debug_log "INFO" "opkg update completed successfully."
            else
                debug_log "ERROR" "opkg update failed."
            fi
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            if apk update > /dev/null 2>&1; then
                debug_log "INFO" "apk update completed successfully."
            else
                debug_log "ERROR" "apk update failed."
            fi
        fi
        touch "${CACHE_DIR}/update.ch"
    fi

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

    debug_log "INFO" "Installing package: $package_name"
    if [ "$DEV_NULL" = "on" ]; then
        $PACKAGE_MANAGER install "$package_name" > /dev/null 2>&1
    else
        $PACKAGE_MANAGER install "$package_name"
    fi

    if [ "$skip_lang_pack" = "no" ] && echo "$package_name" | grep -qE '^luci-app-'; then
        local lang_code=$(cat "${CACHE_DIR}/luci.ch" 2>/dev/null || echo "en")
        local lang_package="luci-i18n-${package_name#luci-app-}-$lang_code"
        install_package "$lang_package" hidden
    fi

    if [ "$skip_package_db" = "no" ] && grep -q "^$package_name=" "${BASE_DIR}/packages.db"; then
        eval "$(grep "^$package_name=" "${BASE_DIR}/packages.db" | cut -d'=' -f2-)"
    fi

    if [ "$skip_package_db" = "no" ]; then
        if uci get "$package_name.@$package_name[0].enabled" >/dev/null 2>&1; then
            uci set "$package_name.@$package_name[0].enabled=$([ "$set_disabled" = "yes" ] && echo "0" || echo "1")"
            uci commit "$package_name"
        fi
    fi

    if [ "$set_disabled" = "no" ] && [ -f "/etc/init.d/$package_name" ]; then
        /etc/init.d/$package_name enable
        /etc/init.d/$package_name start
    fi
}

# 🔴　パッケージ系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

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
# check_option: コマンドラインオプション解析・正規化関数
#
# 【概要】
# この関数は、aios 起動時に渡されたコマンドライン引数を解析し、
# ダッシュ付きの引数はオプションとして解析、非ダッシュ引数はすべて
# 言語オプションとして扱い、最初に見つかった値を SELECTED_LANGUAGE に設定します。
#
# ※ MODE の指定は必ずダッシュ付きで行い、以下の各パターンを受け付けます。
#     common_full  : -cf, --cf, -common_full, --common_full  → MODE="full"
#     common_light : -cl, --cl, -ocommon_light, --ocommon_light → MODE="light"
#     common_debug : -cd, --cd, -common_debug, --common_debug, --ocommon_debug → MODE="debug"
#     reset        : -r, --r, -reset, --reset, -resrt, --resrt → MODE="reset" および RESET="true"
#
# 【対応オプション】
#  - ヘルプ:         -h, --h, -help, --help, -?, --?  
#  - バージョン:     -v, --v, -version, --version  
#  - デバッグ:       -d, --d, -debug, --debug, -d1, --d1  
#                     → DEBUG_MODE="true", DEBUG_LEVEL="DEBUG"
#                   -d2, --d2, -debug2, --debug2  
#                     → DEBUG_MODE="true", DEBUG_LEVEL="DEBUG2"
#  - モード指定:
#       - full:       -cf, --cf, -common_full, --common_full  → MODE="full"
#       - light:      -cl, --cl, -ocommon_light, --ocommon_light → MODE="light"
#       - debug:      -cd, --cd, -common_debug, --common_debug, --ocommon_debug → MODE="debug"
#       - reset:      -r, --r, -reset, --reset, -resrt, --resrt → MODE="reset", RESET="true"
#  - 強制実行:       -f, --f, -force, --force  → FORCE="true"
#  - ドライラン:     -dr, --dr, -dry-run, --dry-run  → DRY_RUN="true"
#  - ログ出力先:     -l, --l, -logfile, --logfile <path>  → LOGFILE に指定パス
#
# 【仕様】
# 1. ダッシュ付きの引数はオプションとして解析し、非ダッシュ引数はすべて SELECTED_LANGUAGE として扱います。
# 2. 解析結果はグローバル変数 SELECTED_LANGUAGE, DEBUG_MODE, DEBUG_LEVEL, MODE, DRY_RUN, LOGFILE, FORCE, RESET, HELP としてエクスポートされ、
#    後続の check_common(), select_country(), debug(), script_version() などに正規化された値として渡されます。
#
# 【使用例】
#   sh aios.sh -d --dry-run --reset -l /var/log/aios.log -f -cf en
#    → 言語 "en" が SELECTED_LANGUAGE に設定され、MODE は "full"（-cf等で指定）、デバッグモード有効、
#       キャッシュリセット、ドライラン、ログ出力先 /var/log/aios.log、強制実行が有効になる。
#########################################################################
check_option() {
    debug_log DEBUG "check_option received before args: $*"

    # デフォルト値の設定
    SELECTED_LANGUAGE=""
    MODE="full"
    DEBUG_MODE="false"
    DEBUG_LEVEL="INFO"
    DRY_RUN="false"
    LOGFILE=""
    FORCE="false"
    RESET="false"
    HELP="false"

    # 言語およびオプション引数の処理
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--h|-help|--help|-\?|--\?)
                HELP="true"
                print_help
                exit 0
                ;;
            -v|--v|-version|--version)
                script_version
                exit 0
                ;;
            -d|--d|-debug|--debug|-d1|--d1)
                DEBUG_MODE="true"
                DEBUG_LEVEL="DEBUG"
                ;;
            -d2|--d2|-debug2|--debug2)
                DEBUG_MODE="true"
                DEBUG_LEVEL="DEBUG2"
                ;;
            -cf|--cf|-common_full|--common_full)
                MODE="full"
                ;;
            -cl|--cl|-ocommon_light|--ocommon_light)
                MODE="light"
                ;;
            -cd|--cd|-common_debug|--common_debug|--ocommon_debug)
                MODE="debug"
                ;;
            -r|--r|-reset|--reset|-resrt|--resrt)
                MODE="reset"
                RESET="true"
                ;;
            -f|--f|-force|--force)
                FORCE="true"
                ;;
            -dr|--dr|-dry-run|--dry-run)
                DRY_RUN="true"
                ;;
            -l|--l|-logfile|--logfile)
                if [ -n "$2" ] && [ "${2#-}" != "$2" ]; then
                    LOGFILE="$2"
                    shift
                else
                    echo "Error: --logfile requires a path argument"
                    exit 1
                fi
                ;;
            -*)
                echo "Warning: Unknown option: $1" >&2
                ;;
            *)
                if [ -z "$SELECTED_LANGUAGE" ]; then
                    SELECTED_LANGUAGE="$1"
                fi
                ;;
        esac
        shift
    done

    # 環境変数として設定
    export SELECTED_LANGUAGE DEBUG_MODE DEBUG_LEVEL MODE DRY_RUN LOGFILE FORCE RESET HELP

    # デバッグ情報を出力
    debug_log DEBUG "check_option: SELECTED_LANGUAGE='$SELECTED_LANGUAGE', MODE='$MODE', DEBUG_MODE='$DEBUG_MODE', DEBUG_LEVEL='$DEBUG_LEVEL', DRY_RUN='$DRY_RUN', LOGFILE='$LOGFILE', FORCE='$FORCE', RESET='$RESET', HELP='$HELP'"

    # 設定された言語を `check_common()` に渡す
    check_common "$SELECTED_LANGUAGE"
}

#########################################################################
# Last Update: 2025-02-16 21:45:00 (JST) 🚀
# "Ensuring seamless updates, one script at a time."
#
# 【要件】
# 1. `download_script()` を `download()` に統合し、一貫性を確保する。
# 2. `debug_log()` を強化し、ダウンロード状況を詳細に記録。
# 3. `download()` のエラーハンドリングを見直し、失敗時の挙動を改善。
# 4. `openwrt.db`, `messages.db`, `country.db`, `packages.db` を適切にダウンロード。
# 5. 影響範囲: `common.sh`（矛盾なく適用）。
#########################################################################
check_common() {
    local lang_code="$1"
    local mode="${2:-full}" 

    case "$MODE" in
        reset)
            rm -f "${CACHE_DIR}/country.ch" \
                  "${CACHE_DIR}/language.ch" \
                  "${CACHE_DIR}/luci.ch" \
                  "${CACHE_DIR}/zone.ch" \
                  "${CACHE_DIR}/zonename.ch" \
                  "${CACHE_DIR}/timezone.ch" \
                  "${CACHE_DIR}/country_success_done" \
                  "${CACHE_DIR}/timezone_success_done"
            echo "$(get_message "MSG_RESET_COMPLETE")"
            exit 0
            ;;
        full)
            download "hidden" "openwrt.db"
            download "hidden" "country.db"
            download "hidden" "packages.db"
            download "hidden" "messages.db"
            check_openwrt
            check_downloader
            select_country "$lang_code"
            ;;
        light)
            select_country "$lang_code"
            ;;
        debug)
            select_country "$lang_code"
            ;;
        *)
            select_country "$lang_code"
            ;;
    esac
}
