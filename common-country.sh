#!/bin/sh

SCRIPT_VERSION="2025.03.06-00-00"

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
            printf "%s\n" "$(color red "Error: Failed to retrieve full country DEBUGrmation. Please try again.")"
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
        debug_log "DEBUG" "Timezone is already set. Skipping select_zone()."
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

    install_package luci-i18n-base yn hidden
    install_package luci-i18n-opkg yn hidden
    install_package luci-i18n-firewall yn hidden
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
        debug_log "DEBUG" "normalize_language() already done. Skipping repeated success message."
        return 0
    fi

    if [ ! -f "$country_cache" ]; then
        debug_log "ERROR" "country.ch not found. Cannot determine language."
        return 1
    fi

    local country_data
    country_data=$(cat "$country_cache")
    debug_log "DEBUG" "country.ch content: $country_data"

    local field_count
    field_count=$(echo "$country_data" | awk '{print NF}')
    debug_log "DEBUG" "Field count in country.ch: $field_count"

    if [ "$field_count" -ge 5 ]; then
        selected_language=$(echo "$country_data" | awk '{print $5}')
    else
        selected_language=$(echo "$country_data" | awk '{print $2}')
    fi

    debug_log "DEBUG" "Selected language extracted from country.ch -> $selected_language"

    local supported_languages
    supported_languages=$(grep "^SUPPORTED_LANGUAGES=" "$message_db" | cut -d'=' -f2 | tr -d '"')
    debug_log "DEBUG" "Supported languages: $supported_languages"

    if echo "$supported_languages" | grep -qw "$selected_language"; then
        debug_log "DEBUG" "Using message database language: $selected_language"
        echo "$selected_language" > "$message_cache"
        ACTIVE_LANGUAGE="$selected_language"
    else
        debug_log "DEBUG" "Language '$selected_language' not found in messages.db. Using 'US' as fallback."
        echo "US" > "$message_cache"
        ACTIVE_LANGUAGE="US"
    fi

    debug_log "DEBUG" "Final system message language -> $ACTIVE_LANGUAGE"
    echo "$(get_message "MSG_COUNTRY_SUCCESS")"
    touch "$flag_file"
}
