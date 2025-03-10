#!/bin/sh

SCRIPT_VERSION="2025.03.10-01-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-10
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

# ダイナミックシステム情報の読み込み（存在する場合）
DYNAMIC_INFO_SCRIPT="${BASE_DIR}/dynamic-system-info.sh"
if [ -f "$DYNAMIC_INFO_SCRIPT" ]; then
    . "$DYNAMIC_INFO_SCRIPT"
else
    # ダイナミック情報スクリプトが存在しない場合はダウンロード
    mkdir -p "$BASE_DIR"
    if [ ! -f "$DYNAMIC_INFO_SCRIPT" ]; then
        $BASE_WGET "$DYNAMIC_INFO_SCRIPT" "$BASE_URL/dynamic-system-info.sh"
        chmod +x "$DYNAMIC_INFO_SCRIPT"
        . "$DYNAMIC_INFO_SCRIPT"
    fi
fi

#########################################################################
# Last Update: 2025-03-10 11:00:00 (JST) 🚀
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
        
        system)
            # 新機能: システム情報の表示
            debug_log "DEBUG" "MSG_TEST_SYSTEM_INFO"
            echo "Architecture: $(get_device_architecture)"
            echo "OS: $(get_os_info)"
            echo "Package Manager: $(get_package_manager)"
            echo "Current Timezone: $(get_current_timezone)"
            echo "Available Languages: $(get_available_language_packages)"
            ;;
            
        *)
            debug_log "ERROR" "ERR_INVALID_ARGUMENT" "$test_type"
            return 1
            ;;
    esac
}

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
# Last Update: 2025-03-10 11:00:00 (JST) 🚀
# "Country selection with dynamic system information integration."
# select_country: ユーザーに国の選択を促す（システム情報とデータベース情報を統合）
#
# 1. システム情報からデフォルトの言語・国を検出
# 2. country.db と比較してマッチするエントリを探索
# 3. 見つかった場合、それをデフォルト選択として提案
# 4. ユーザーが選択または検索キーワードを入力
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

    # システム情報からデフォルト値を取得 (dynamic-system-info.sh から)
    local system_language=""
    local system_country=""
    
    if type get_country_info >/dev/null 2>&1; then
        # システム情報から国データを取得
        local system_country_info=$(get_country_info)
        if [ -n "$system_country_info" ]; then
            debug_log "DEBUG" "Found system country info: $system_country_info"
            # デフォルトの言語コードを抽出 ($4)
            system_language=$(echo "$system_country_info" | awk '{print $4}')
            # デフォルトの国名を抽出 ($2)
            system_country=$(echo "$system_country_info" | awk '{print $2}')
        fi
    fi

    # デフォルト値をユーザーに提案
    if [ -n "$system_country" ]; then
        printf "%s\n" "$(color cyan "$(get_message "MSG_DETECTED_COUNTRY")" "$system_country")"
        printf "%s" "$(color cyan "$(get_message "MSG_USE_DETECTED_COUNTRY")")" 
        read -r yn
        yn=$(normalize_input "$yn")
        
        if [ "$yn" = "Y" ] || [ "$yn" = "y" ]; then
            input_lang="$system_country"
        fi
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
        echo "$display
