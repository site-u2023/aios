#!/bin/sh

SCRIPT_VERSION="2025.02.27-01-06"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-02-21
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 24.10.0)
#
# ⚠️ IMPORTANT NOTICE:
# OpenWrt OS exclusively uses **Almquist Shell (ash)** and
# is **NOT** compatible with Bourne-Again Shell (bash).
#
# 📢 POSIX Compliance Guidelines:
# ✅ Use `[` instead of `[[` for conditions
# ✅ Use `$(command)` instead of backticks `` `command` ``
# ✅ Use `$(( ))` for arithmetic instead of `let`
# ✅ Define functions as `func_name() {}` (no `function` keyword)
# ✅ No associative arrays (`declare -A` is NOT supported)
# ✅ No here-strings (`<<<` is NOT supported)
# ✅ No `-v` flag in `test` or `[[`
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
# =========================================================
### =========================================================
### 📌 AI Assistance Request: Bug Fixing Procedure
### 
### When debugging or fixing errors in this script, follow these steps:
### 
### 1️⃣ Create a minimal test script to identify the bug.
### 2️⃣ Execute the test and verify the reproducibility of the error.
### 3️⃣ Fix the error and re-run the test to confirm the solution.
### 4️⃣ Apply the corrected code to the production environment.
### 
### ⚠️ DO NOT modify the main script without first confirming the fix 
###     through a dedicated test script.
### 
### 🛠️ Keep the debugging process structured, efficient, and reliable.
### =========================================================

# 各種共通処理（ヘルプ表示、カラー出力、システム情報確認、言語選択、確認・通知メッセージの多言語対応など）を提供する。

echo -e "\033[7;40mUpdated to version $SCRIPT_VERSION common.sh \033[0m"

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="${BASE_WGET:-wget --no-check-certificate -q -O}"
# BASE_WGET="${BASE_WGET:-wget -O}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
BUILD_DIR="${BUILD_DIR:-$BASE_DIR/build}"
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BUILD_DIR"
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
        debug_log "DEBUG" "Non-critical error: $error_message"
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
            debug_log "DEBUG" "MSG_TEST_COUNTRY_SEARCH" "$test_input"
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
            debug_log "DEBUG" "MSG_TEST_TIMEZONE_SEARCH" "$test_input"
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
            debug_log "DEBUG" "MSG_TEST_CACHE_CONTENTS"
            for cache_file in "country_tmp.ch" "zone_tmp.ch"; do
                if [ -f "${CACHE_DIR}/$cache_file" ]; then
                    debug_log "DEBUG" "MSG_CACHE_CONTENTS" "$cache_file"
                    cat "${CACHE_DIR}/$cache_file"
                else
                    debug_log "DEBUG" "MSG_CACHE_NOT_FOUND" "$cache_file"
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
# check_openwrt: OpenWrtのバージョン確認・管理のみを担当
#########################################################################
check_openwrt() {
    local version_file="${CACHE_DIR}/openwrt.ch"

    # **キャッシュがあれば使用**
    if [ -f "$version_file" ]; then
        CURRENT_VERSION=$(cat "$version_file")
    else
        local raw_version=""
        local distrib_id=""

        # **① /etc/openwrt_release から取得（最優先）**
        if [ -f "/etc/openwrt_release" ]; then
            distrib_id=$(awk -F"'" '/DISTRIB_ID/ {print $2}' /etc/openwrt_release)
            
            # **GL.iNet カスタム版は弾く**
            if [ "$distrib_id" != "OpenWrt" ]; then
                handle_error "Unsupported OpenWrt version: $distrib_id (Only OpenWrt is supported)"
                exit 1  # 🚨 スクリプト全体を終了
            fi

            if grep -q "DISTRIB_RELEASE=" /etc/openwrt_release; then
                raw_version=$(awk -F"'" '/DISTRIB_RELEASE/ {print $2}' /etc/openwrt_release)
            fi
        fi

        # **② /etc/openwrt_version が存在すれば使用**
        if [ -z "$raw_version" ] && [ -f "/etc/openwrt_version" ]; then
            raw_version=$(cat /etc/openwrt_version)
        fi

        # **③ バージョンが取得できなければスクリプト全体を終了**
        if [ -z "$raw_version" ]; then
            handle_error "Could not determine OpenWrt version. Check system files."
            exit 1  # 🚨 スクリプト全体を終了
        fi

        # **④ バージョン表記の統一**
        CURRENT_VERSION=$(echo "$raw_version" | tr '-' '.')

        # **⑤ キャッシュに書き出し**
        echo "$CURRENT_VERSION" > "$version_file"
        chmod 444 "$version_file"  # 読み取り専用
    fi

    # **⑥ データベースにバージョンがあるか確認**
    if grep -q "^$CURRENT_VERSION=" "${BASE_DIR}/openwrt.db"; then
        local db_entry=$(grep "^$CURRENT_VERSION=" "${BASE_DIR}/openwrt.db" | cut -d'=' -f2)
        PACKAGE_MANAGER=$(echo "$db_entry" | cut -d'|' -f1)
        VERSION_STATUS=$(echo "$db_entry" | cut -d'|' -f2)
        echo -e "$(color green "Version $CURRENT_VERSION is supported ($VERSION_STATUS)")"
    else
        handle_error "Unsupported OpenWrt version: $CURRENT_VERSION"
        exit 1  # 🚨 スクリプト全体を終了
    fi
}

#########################################################################
# check_architecture: OpenWrtのアーキテクチャを確認・キャッシュ
#########################################################################
check_architecture() {
    local arch_file="${CACHE_DIR}/architecture.ch"

    # **キャッシュがあれば再取得しない**
    if [ -f "$arch_file" ]; then
        arch=$(cat "$arch_file" | tr -d '\r')
        debug_log "DEBUG" "Using cached architecture: $arch"
        return 0
    fi

    # **アーキテクチャを取得**
    local arch=$(uname -m)

    # **キャッシュに保存（アーキテクチャ名のみ）**
    echo "$arch" > "$arch_file"

    debug_log "DEBUG" "Architecture detected: $arch"
}

#########################################################################
# check_downloader: パッケージマネージャー判定（apk / opkg 対応）
#########################################################################
check_downloader() {
    if [ -f "${BASE_DIR}/downloader.ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/downloader.ch")
    else
        if command -v apk >/dev/null 2>&1; then
            PACKAGE_MANAGER="apk"
        elif command -v opkg >/dev/null 2>&1; then
            PACKAGE_MANAGER="opkg"
        else
            PACKAGE_MANAGER="opkg"  # デフォルトをセット
        fi
        echo "$PACKAGE_MANAGER" > "${CACHE_DIR}/downloader.ch"
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
        debug_log "DEBUG" "messages.db not found. Returning key as message."
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
            debug_log "DEBUG" "Message key '$key' not found in messages.db."
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

    local install_path="${BASE_DIR}/${file_name}"
    local remote_url="${BASE_URL}/${file_name}"

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
        debug_log "DEBUG" "No version DEBUGrmation found for $file_name. Skipping version check and proceeding with download."
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
    debug_log "DEBUG" "Updated script.ch: ${script_file}=${version}"

    echo "$version"
}

# 🔴　ダウンロード系　ここまで　🔴　-------------------------------------------------------------------------------------------------------------------------------------------

#########################################################################
# country_DEBUG: 選択された国と言語の詳細情報を表示
#########################################################################
country_DEBUG() {
    local country_DEBUG_file="${BASE_DIR}/country.ch"
    local selected_language_code=$(cat "${BASE_DIR}/check_country")
    if [ -f "$country_DEBUG_file" ]; then
        grep -w "$selected_language_code" "$country_DEBUG_file"
    else
        printf "%s\n" "$(color red "Country DEBUGrmation not found.")"
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
            download "hidden" "custom-package.db"
            check_openwrt
            check_architecture
            check_downloader
            select_country "$lang_code"
            ;;
        light|debug)
            download "messages.db"
            download "openwrt.db"
            download "country.db"
            download "local-package.db"
            download "custom-package.db"
            check_openwrt
            check_architecture
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
