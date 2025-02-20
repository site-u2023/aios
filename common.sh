#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important! OpenWrt OS only works with Almquist Shell, not Bourne-again shell.
# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

SCRIPT_VERSION="2025.02.20-12-07"
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

#########################################################################
# Last Update: 2025-02-18 18:00:00 (JST) 🚀
# "Efficiency in retrieval, clarity in communication."
# get_message: システムメッセージを取得する関数
#
# 【要件】
# 1. **メッセージの取得ロジック**
#    - `$ACTIVE_LANGUAGE` を最優先で使用（`normalize_language()` で設定）
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
#    - 言語取得ロジックを `normalize_language()` に統一し、責務を分離
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
    local hidden_mode="false"
    local quiet_mode="${QUIET_MODE:-false}"
    local file_name=""
    local local_version=""
    local remote_version=""
    local script_db="${CACHE_DIR}/script.ch"

    # **引数解析（順不同対応）**
    while [ "$#" -gt 0 ]; do
        case "$1" in
            hidden) hidden_mode="true" ;;
            quiet) quiet_mode="true" ;;
            debug) DEBUG_MODE="true" ;;
            *) file_name="$1" ;;  # 最初に見つかった非オプション引数をファイル名とする
        esac
        shift
    done

    # **ファイル名の正規化**
    file_name=$(normalize_input "$file_name")

    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"

    # **script.ch がなければ作成**
    if [ ! -f "$script_db" ]; then
        touch "$script_db"
    fi

    # **ローカルバージョンの取得（script.ch を参照）**
    if grep -q "^${file_name}=" "$script_db"; then
        local_version=$(grep "^${file_name}=" "$script_db" | cut -d'=' -f2)
    fi

    # **リモートバージョンの取得**
    remote_version=""
    remote_version=$(wget -qO- "$remote_url" | grep -Eo 'SCRIPT_VERSION=["'"'"']?[0-9]{4}[-.][0-9]{2}[-.][0-9]{2}[-.0-9]*' | cut -d'=' -f2 | tr -d '"')

    # **リモートバージョンが取得できない場合は仮のバージョンを設定**
    if [ -z "$remote_version" ]; then
        debug_log "DEBUG" "No version information found for $file_name. Skipping version check and proceeding with download."
        remote_version="2025.01.01-00-00"
    fi

    # **デバッグモード時のみ、バージョン情報を記録**
    debug_log "DEBUG" "Download function executed - Target Version: $remote_version"

    # **hidden モード時、ローカルファイルがあるなら即リターン**
    if [ "$hidden_mode" = "true" ] && [ -f "$install_path" ]; then
        debug_log "DEBUG" "hidden mode enabled - Skipping download for $file_name"
        return 0
    fi

    # **バージョンチェック**
    if [ -z "$local_version" ]; then
        debug_log "DEBUG" "No local version found for $file_name. Downloading..."
    elif [ "$local_version" = "$remote_version" ]; then
        if [ "$quiet_mode" != "true" ]; then
            echo "$(color yellow "$file_name is already up-to-date. (Version: $local_version)")"
        fi
        return 0
    else
        debug_log "DEBUG" "Updating $file_name (Local: $local_version, Remote: $remote_version)"
    fi

    # **ダウンロード開始**
    if ! $BASE_WGET "$install_path" "$remote_url"; then
        debug_log "ERROR" "Download failed: $file_name"
        return 1
    fi

    # **空ファイルチェック**
    if [ ! -s "$install_path" ]; then
        debug_log "ERROR" "Download failed: $file_name is empty."
        return 1
    fi

    # **ダウンロード成功メッセージ（hidden でも常に表示）**
    echo "$(color green "Download completed: $file_name - Version: $remote_version")"

    debug_log "DEBUG" "Download completed: $file_name is valid."

    # **script.ch にバージョン情報を更新**
    if grep -q "^${file_name}=" "$script_db"; then
        sed -i "s|^${file_name}=.*|${file_name}=${remote_version}|" "$script_db"
    else
        echo "${file_name}=${remote_version}" >> "$script_db"
    fi

    debug_log "DEBUG" "Updated script.ch: ${file_name}=${remote_version}"

    return 0
}

#######################################################################
get_script_version() {
    local script_file="$1"
    local script_db="${CACHE_DIR}/script.ch"

    # **スクリプトファイルが指定されていない場合はエラー**
    if [ -z "$script_file" ]; then
        echo "Error: No script file specified." >&2
        return 1
    fi

    # **スクリプトが存在しない場合はエラー**
    if [ ! -f "$script_file" ]; then
        echo "Error: Script file not found: $script_file" >&2
        return 1
    fi

    local version=""
    
    # **`SCRIPT_VERSION="..."` の値を取得**
    version=$(grep -Eo 'SCRIPT_VERSION=["'"'"']?[0-9]{4}[-.][0-9]{2}[-.][0-9]{2}[-.0-9]*' "$script_file" | cut -d'=' -f2 | tr -d '"')

    # **バージョンの正規化**
    version=$(normalize_version "$version")

    # **バージョン取得に失敗した場合はエラー**
    if [ -z "$version" ]; then
        echo "Error: Could not extract SCRIPT_VERSION from $script_file" >&2
        return 1
    fi

    # **script.ch がなければ作成**
    if [ ! -f "$script_db" ]; then
        touch "$script_db"
    fi

    # **script.ch への書き込み**
    if grep -q "^${script_file}=" "$script_db"; then
        sed -i "s|^${script_file}=.*|${script_file}=${version}|" "$script_db"
    else
        echo "${script_file}=${version}" >> "$script_db"
    fi

    # **デバッグログに記録**
    debug_log "INFO" "Updated script.ch: ${script_file}=${version}"

    echo "$version"
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
    local input_lang="$1"  # 引数として渡された言語コード（無ければ後で入力）

    # キャッシュがあればゾーン選択へスキップ
    if [ -f "$cache_country" ]; then
        debug_log "DEBUG" "Country cache found. Skipping selection."
        select_zone
        return
    fi

    while true; do
        # `$1` がある場合は read せず、直接 `input_lang` を使う
        if [ -z "$input_lang" ]; then
            printf "%s\n" "$(color cyan "$(get_message "MSG_ENTER_COUNTRY")")"
            printf "%s" "$(color cyan "$(get_message "MSG_SEARCH_KEYWORD")")"
            read -r input_lang
        fi

        # 入力の正規化: "/", ",", "_" をスペースに置き換え
        local cleaned_input
        cleaned_input=$(echo "$input_lang" | sed 's/[\/,_]/ /g')

        # 🔹 `country.db` から検索（フルライン取得）
        local full_results
        full_results=$(awk -v search="$cleaned_input" 'BEGIN {IGNORECASE=1} { if ($0 ~ search) print $0 }' "$BASE_DIR/country.db" 2>>"$LOG_DIR/debug.log")

        if [ -z "$full_results" ]; then
            printf "%s\n" "$(color red "Error: No matching country found for '$input_lang'. Please try again.")"
            input_lang=""  # 🔹 エラー時はリセットして再入力
            continue
        fi

        debug_log "DEBUG" "Country found for '$input_lang'. Presenting selection list."

        # 🔹 表示用リスト作成（`$2 $3` のみを抽出してリスト表示）
        local display_results
        display_results=$(echo "$full_results" | awk '{print $2, $3}')

        # 🔹 選択リスト表示（番号付き）
        echo "$display_results" > "$tmp_country"
        select_list "$display_results" "$tmp_country" "country"

        # 🔹 ユーザー選択番号を取得
        local selected_number
        selected_number=$(awk 'END {print NR}' "$tmp_country")

        if [ -z "$selected_number" ]; then
            printf "%s\n" "$(color red "Error: No selection made. Please try again.")"
            continue
        fi

        # 🔹 `full_results` から該当行のフルデータを取得
        local selected_full
        selected_full=$(echo "$full_results" | sed -n "${selected_number}p")

        if [ -z "$selected_full" ]; then
            printf "%s\n" "$(color red "Error: Failed to retrieve full country information. Please try again.")"
            continue
        fi

        # 🔹 フルラインを `tmp_country` に保存
        echo "$selected_full" > "$tmp_country"

        # 🔹 `country_write()` に渡す（キャッシュ書き込み）
        country_write

        # 🔹 ゾーン選択へ進む
        debug_log "DEBUG" "Country selection completed. Proceeding to select_zone()."
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
            debug_log "DEBUG" "Invalid selection: '$choice'. Available options: $(cat "$list_file")"
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
        elif [ "$yn" = "R" ] || [ "$yn" = "r" ]; then
            debug_log "DEBUG" "User chose to restart selection."
            rm -f "${CACHE_DIR}/country.ch"  # **キャッシュ削除で完全リセット**
            select_country
            return
            #continue  # **選択をリスタート**
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

    local country_data
    country_data=$(cat "$tmp_country" 2>/dev/null)
    if [ -z "$country_data" ]; then
        debug_log "ERROR" "No country data found in tmp_country."
        return 1
    fi

    local field_count
    field_count=$(echo "$country_data" | awk '{print NF}')

    local language_name=""
    local luci_code=""
    local zone_data=""

    if [ "$field_count" -ge 5 ]; then
        # フルラインに必要なフィールドが存在する場合:
        # $1: 国名, $2: 何か, $3: 何か, $4: 言語コード, $5: 言語名, $6～: ゾーン情報
        luci_code=$(echo "$country_data" | awk '{print $4}')
        language_name=$(echo "$country_data" | awk '{print $5}')
        zone_data=$(echo "$country_data" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}')
    else
        # もしフィールド数が2の場合（表示用として country.db から抽出されたケース）
        # 想定: $1: 国名, $2: 言語名
        luci_code="default"  # デフォルト値
        language_name=$(echo "$country_data" | awk '{print $2}')
        zone_data="NO_TIMEZONE"
    fi

    # キャッシュファイルへ書き込み
    echo "$country_data" > "$cache_country"
    echo "$language_name" > "$cache_language"
    echo "$luci_code" > "$cache_luci"
    echo "$zone_data" > "$cache_zone"

    chmod 444 "$cache_country" "$cache_language" "$cache_luci" "$cache_zone"

    normalize_language
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
#[5] → normalize_language()
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
# normalize_language: 言語設定の正規化
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
#    - `normalize_language()` 実行時に `$ACTIVE_LANGUAGE` を設定
#    - `$ACTIVE_LANGUAGE` は `message.ch` の値を常に参照
#    - `$ACTIVE_LANGUAGE` が未設定の場合、フォールバックで `US`
#
# 5. メンテナンス:
#    - `country.ch` はどのような場合でも変更しない
#    - `message.ch` のみフォールバックを適用し、システムメッセージの一貫性を維持
#    - 言語設定に影響を与えず、メッセージの表示のみを制御する
#########################################################################
normalize_language() {
    local message_db="${BASE_DIR}/messages.db"
    local country_cache="${CACHE_DIR}/country.ch"
    local message_cache="${CACHE_DIR}/message.ch"
    local selected_language=""
    local flag_file="${CACHE_DIR}/country_success_done"

    if [ -f "$flag_file" ]; then
        debug_log "INFO" "normalize_language() already done. Skipping repeated success message."
        return 0
    fi

    if [ ! -f "$country_cache" ]; then
        debug_log "ERROR" "country.ch not found. Cannot determine language."
        return 1
    fi

    local field_count
    field_count=$(awk '{print NF}' "$country_cache")

    if [ "$field_count" -ge 5 ]; then
        selected_language=$(awk '{print $5}' "$country_cache")
    else
        selected_language=$(awk '{print $2}' "$country_cache")
    fi

    debug_log "DEBUG" "Selected language extracted from country.ch -> $selected_language"

    local supported_languages
    supported_languages=$(grep "^SUPPORTED_LANGUAGES=" "$message_db" | cut -d'=' -f2 | tr -d '"')

    if echo "$supported_languages" | grep -qw "$selected_language"; then
        debug_log "DEBUG" "Using message database language: $selected_language"
        echo "$selected_language" > "$message_cache"
        ACTIVE_LANGUAGE="$selected_language"
    else
        debug_log "WARNING" "Language '$selected_language' not found in messages.db. Using 'US' as fallback."
        echo "US" > "$message_cache"
        ACTIVE_LANGUAGE="US"
    fi

    debug_log "DEBUG" "Final system message language -> $ACTIVE_LANGUAGE"
    echo "$(get_message "MSG_COUNTRY_SUCCESS")"
    touch "$flag_file"
}


# 🔴　ランゲージ（言語・ゾーン）系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

# 🔵　パッケージ系　ここから　🔵-------------------------------------------------------------------------------------------------------------------------------------------

#########################################################################
# Last Update: 2025-02-20 16:22:00 (JST) 🚀
# install_package: パッケージのインストール処理 (OpenWrt / Alpine Linux)
#
# 【概要】
# 指定されたパッケージをインストールし、オプションに応じて以下の処理を実行する。
#　GitHub の package.db のリモート管理　　＜＜＜　追加要件
#
# 【フロー】
# 2️⃣ デバイスにパッケージがインストール済みか確認
# 1️⃣ update は初回に一回後最適な管理（２４時間で更新）、opkg update / apk update を実行
# 3️⃣ パッケージがリポジトリに存在するか確認
# 4️⃣ インストール確認（yn オプションが指定された場合）
# 5️⃣ インストールの実行
# 6️⃣ 言語パッケージの適用（lang オプションがない場合）
# 7️⃣ local-package.db の適用（notpack オプションがない場合）
# 8️⃣ 設定の有効化（デフォルト enabled、disabled オプションで無効化）
#
# 【グローバルオプション】
# DEV_NULL
# DEBUG : 要所にセット
#
# 【オプション】
# - yn         : インストール前に確認する（デフォルト: 確認なし）
# - nolang     : 言語パッケージの適用をスキップ（デフォルト: 適用する）
# - force      : 強制インストール （デフォルト: 適用しない）
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
# - local-package.db の設定がある場合、uci set を実行し適用（notset オプションで無効化可能）
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
    local force_install="no"
    local update_mode="no"
    local package_name=""
    local package_db_remote="${BASE_URL}/packages.db"
    local package_db_local="${CACHE_DIR}/local-package.db"
    local update_cache="${CACHE_DIR}/update.ch"

    # **オプションの処理**
    for arg in "$@"; do
        case "$arg" in
            yn) confirm_install="yes" ;;
            nolang) skip_lang_pack="yes" ;;
            notpack) skip_package_db="yes" ;;
            disabled) set_disabled="yes" ;;
            hidden) hidden="yes" ;;
            test) test_mode="yes" ;;
            force) force_install="yes" ;;
            update) update_mode="yes" ;;
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
        echo "$(get_message "MSG_INSTALL_ABORTED")" >&2
        return 1
    fi

    # **パッケージマネージャーの確認**
    if [ -f "${CACHE_DIR}/downloader_ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/downloader_ch")
    else 
        echo "$(get_message "MSG_ERROR_NO_PACKAGE_MANAGER")" >&2
        return 1
    fi

    # **パッケージのインストール済みチェック**
    if [ "$test_mode" = "no" ] && [ "$force_install" = "no" ]; then
        if [ "$PACKAGE_MANAGER" = "opkg" ] && opkg list-installed | grep -q "^$package_name "; then
            [ "$hidden" != "yes" ] && echo "$(get_message "MSG_PACKAGE_ALREADY_INSTALLED" | sed "s/{pkg}/$package_name/")"
            return 0
        elif [ "$PACKAGE_MANAGER" = "apk" ] && apk info -e "$package_name" >/dev/null 2>&1; then
            [ "$hidden" != "yes" ] && echo "$(get_message "MSG_PACKAGE_ALREADY_INSTALLED" | sed "s/{pkg}/$package_name/")"
            return 0
        fi
    fi

    # **update の管理**
    local current_date
    current_date=$(date '+%Y-%m-%d')

    if [ "$update_mode" = "yes" ] || [ ! -f "$update_cache" ] || ! grep -q "LAST_UPDATE=$current_date" "$update_cache"; then
        debug_log "DEBUG" "$(get_message "MSG_RUNNING_UPDATE")"

        # **アップデートの開始メッセージ（hidden でも必ず表示）**
        echo -en "\r$(color cyan "$(get_message "MSG_UPDATE_IN_PROGRESS")") "

        # **スピナー表示を開始（バックグラウンド）**
        spin() {
            local delay=0.1  # スピナーの更新間隔
            local spin_chars='-\|/'  # スピナーの回転パターン
            local i=0

            while true; do
                # スピナーの表示
                printf "\r%s %s" "$(color cyan "$(get_message "MSG_UPDATE_IN_PROGRESS")")" "${spin_chars:i++%4:1}"
            
                # `usleep` があれば精密な待機、それ以外は `sleep`
                if command -v usleep >/dev/null 2>&1; then
                    usleep 100000  # 0.1秒 = 100,000マイクロ秒
                else
                    sleep "$delay"
                fi
            done
        }

        # スピナーをバックグラウンドで実行し、プロセスIDを保存
        spin &  
        SPINNER_PID=$!

        # **トラップを設定し、スクリプト終了時にスピナーを確実に停止**
        XXX_cleanup_spinner() {
            if [ -n "$SPINNER_PID" ] && ps | grep -q " $SPINNER_PID "; then
                kill "$SPINNER_PID" >/dev/null 2>&1
                sleep 0.1  # プロセス終了待機
                kill -9 "$SPINNER_PID" >/dev/null 2>&1
            fi
            unset SPINNER_PID  # `wait` のエラーを防ぐ
        }

        cleanup_spinner() {
            if [ -n "$SPINNER_PID" ] && ps | grep -q " $SPINNER_PID "; then
                kill "$SPINNER_PID" >/dev/null 2>&1
                sleep 0.1
                kill -9 "$SPINNER_PID" >/dev/null 2>&1
            fi
            unset SPINNER_PID
        }

        trap cleanup_spinner EXIT INT TERM

        # **実際の update コマンド**
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg update > "${LOG_DIR}/opkg_update.log" 2>&1
            UPDATE_STATUS=$?
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk update > "${LOG_DIR}/apk_update.log" 2>&1
            UPDATE_STATUS=$?
        fi

        # **スピナーを停止**
        cleanup_spinner

        # **エラーハンドリング**
        if [ "$UPDATE_STATUS" -ne 0 ]; then
            debug_log "ERROR" "$(get_message "MSG_UPDATE_FAILED")"
            printf "\r%s\n" "$(color red "$(get_message "MSG_UPDATE_FAILED")")"  # `\r` で行を上書き + `\n` で改行
            return 1
        else
            echo "LAST_UPDATE=$(date '+%Y-%m-%d')" > "$update_cache"
            printf "\r%s\n" "$(color green "$(get_message "MSG_UPDATE_COMPLETE")")"  # ✅ 修正
        fi

        # **トラップ解除**
        trap - EXIT
    fi
    
    # **インストール前の確認**
    if [ "$confirm_install" = "yes" ]; then
        while true; do
            echo "$(get_message "MSG_CONFIRM_INSTALL" | sed "s/{pkg}/$package_name/")"
            echo -n "$(get_message "MSG_CONFIRM_ONLY_YN")"
            read -r yn
            case "$yn" in
                [Yy]*) break ;;
                [Nn]*) return 1 ;;
                *) echo "Invalid input. Please enter Y or N." ;;
            esac
        done
    fi

    debug_log "DEBUG" "Installing package: $package_name"
    if [ "$DEV_NULL" = "on" ]; then
        $PACKAGE_MANAGER install "$package_name" > /dev/null 2>&1
    else
        $PACKAGE_MANAGER install "$package_name"
    fi

    echo "$(get_message "MSG_PACKAGE_INSTALLED" | sed "s/{pkg}/$package_name/")"
    debug_log "DEBUG" "Successfully installed package: $package_name"
}

#########################################################################
# Last Update: 2025-02-19 20:15:00 (JST) 🚀
# install_build: パッケージのビルド処理 (OpenWrt / Alpine Linux)
#
# 【概要】
# 指定されたパッケージをビルド後インストールし、オプションに応じて以下の処理を実行する。
# 1回の動作で１つのビルドのみパッケージを作りインストール作業
# DEV_NULL に応じて出力制御
# DEBUG に応じて出力制御（要所にセット）
# package名は、ビルド前は build_*, ビルド後は *
# 例：build_uconv　>>>　uconv
#
# 【フロー】
# 2️⃣ デバイスにパッケージがインストール済みか確認（ビルド後のパッケージ名で確認）
# 4️⃣ インストール確認（yn オプションが指定された場合）
# 4️⃣ ビルド用汎用パッケージ（例：make, gcc）をインストール ※install_package()利用
# 4️⃣ ビルド作業
# 7️⃣ package.db の適用（ビルド用設定：DBの記述に従う）
# 5️⃣ インストールの実行（install_package()利用）
# 7️⃣ package.db の適用（ビルド後の設定適用がある場合：DBの記述に従う）
#
# 【グローバルオプション】
# DEV_NULL
# DEBUG : 要所にセット
#
# 【オプション】※順不同で適用可
# - yn         : インストール前に確認する（デフォルト: 確認なし）
# - hidden     : 既にインストール済みの場合、"パッケージ xxx はすでにインストールされています" のメッセージを非表示にする
#
# 【仕様】
# - downloader_ch から opkg または apk を取得し、適切なパッケージ管理ツールを使用
# - package.db の設定がある場合、該当パッケージの記述 を実行し適用
# - messages.db を参照し、すべてのメッセージを取得（JP/US 対応）
#
# 【使用例】
# - install_build build_uconv                  → uconv をビルド後インストール（確認なし）
# - install_build build_uconv yn               → uconv をビルド後インストール（確認あり）
# - install_build build_uconv yn hidden        → uconv をビルド後インストール（確認あり、既にインストール済みの場合のメッセージは非表示）
# - install_build make                         → ビルド環境用のパッケージ（例：make, gcc）をインストール
#
# 【messages.dbの記述例】
# [build_uconv]　※行、列問わず記述可
# [uconv]　※行、列問わず記述可
#########################################################################
install_build() {
    local confirm_install="no"
    local hidden="no"
    local package_name=""
    
    # オプションの処理
    for arg in "$@"; do
        case "$arg" in
            yn) confirm_install="yes" ;;
            hidden) hidden="yes" ;;
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

    # パッケージマネージャーの確認（downloader_ch のキャッシュを参照）
    if [ -f "${CACHE_DIR}/downloader_ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/downloader_ch")
    else
        echo "Error: No package manager information found in cache." >&2
        return 1
    fi

    if [ "$confirm_install" = "yes" ]; then
        while true; do
            echo "$(get_message "MSG_CONFIRM_INSTALL" | sed "s/{pkg}/$package_name/")"
            echo -n "$(get_message "MSG_CONFIRM_ONLY_YN")"
            read -r yn
            case "$yn" in
                [Yy]*) break ;;
                [Nn]*) return 1 ;;
                *) echo "Invalid input. Please enter Y or N." ;;
            esac
        done
    fi

    # ビルド用の汎用パッケージをインストール（hidden で確認なし）
    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        install_package make hidden
        install_package gcc hidden
        install_package git hidden
        install_package libtool hidden
        install_package automake hidden
        install_package pkg-config hidden
        install_package zlib-dev hidden
        install_package libssl-dev hidden
        install_package libicu-dev hidden
        install_package ncurses-dev hidden
        install_package libcurl4-openssl-dev hidden
        install_package libxml2-dev hidden
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        install_package build-base hidden
        install_package gcc hidden
        install_package musl-dev hidden
        install_package libtool hidden
        install_package automake hidden
        install_package pkgconfig hidden
        install_package zlib-dev hidden
        install_package openssl-dev hidden
        install_package icu-dev hidden
        install_package ncurses-dev hidden
        install_package curl-dev hidden
        install_package libxml2-dev hidden
    else
        echo "Error: Unsupported package manager '$PACKAGE_MANAGER'." >&2
        return 1
    fi

    # ビルド前のパッケージ名を取得
    local built_package="${package_name#build_}"

    # すでにインストールされているか確認（opkg または apk に対応）
    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        if opkg list-installed | grep -q "^$built_package "; then
            [ "$hidden" != "yes" ] && echo "$(get_message "MSG_PACKAGE_ALREADY_INSTALLED" | sed "s/{pkg}/$built_package/")"
            return 0
        fi
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        if apk info -e "$built_package" >/dev/null 2>&1; then
            [ "$hidden" != "yes" ] && echo "$(get_message "MSG_PACKAGE_ALREADY_INSTALLED" | sed "s/{pkg}/$built_package/")"
            return 0
        fi
    fi

    # ビルド開始メッセージ
    echo "$(get_message "MSG_BUILD_START" | sed "s/{pkg}/$built_package/")"

    # ビルド用パッケージのインストール（install_package() を利用）
    install_package "$package_name"

    # ビルド作業の開始時間を記録
    local start_time=$(date +%s)
    debug_log "INFO" "Building package: $built_package"
    if ! build_package "$package_name"; then
        echo "$(get_message "MSG_BUILD_FAIL" | sed "s/{pkg}/$built_package/")"
        debug_log "ERROR" "Build failed for package: $built_package"
        return 1
    fi
    local end_time=$(date +%s)
    local build_time=$((end_time - start_time))
    echo "$(get_message "MSG_BUILD_TIME" | sed "s/{pkg}/$built_package/" | sed "s/{time}/$build_time/")"
    debug_log "INFO" "Build time for $built_package: $build_time seconds"

    # package.db の適用（ビルド用設定）
    if grep -q "^$package_name=" "${BASE_DIR}/packages.db"; then
        eval "$(grep "^$package_name=" "${BASE_DIR}/packages.db" | cut -d'=' -f2-)"
    fi

    # ビルド後のパッケージのインストールを install_package() に依頼
    install_package "$built_package"
    echo "$(get_message "MSG_BUILD_SUCCESS" | sed "s/{pkg}/$built_package/")"
    debug_log "INFO" "Successfully built and installed package: $built_package"
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
 
    # モードごとの処理
    case "$mode" in
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
            download "hidden" "messages.db"
            download "hidden" "openwrt.db"
            download "hidden" "country.db"
            download "hidden" "local-package.db"
            check_openwrt
            check_downloader
            select_country "$lang_code"
            ;;
        light|debug)
            download "messages.db"
            download "openwrt.db"
            download "country.db"
            download "local-package.db"
            check_openwrt
            check_downloader
            select_country "$lang_code"
            ;;
        return)
            rm -f "${CACHE_DIR}/country.ch" \
                  "${CACHE_DIR}/language.ch" \
                  "${CACHE_DIR}/luci.ch" \
                  "${CACHE_DIR}/zone.ch" \
                  "${CACHE_DIR}/zonename.ch" \
                  "${CACHE_DIR}/timezone.ch" \
                  "${CACHE_DIR}/country_success_done" \
                  "${CACHE_DIR}/timezone_success_done"
            select_country
            ;;
        *)
            ;;
    esac
}
