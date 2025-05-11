#!/bin/sh

SCRIPT_VERSION="2025.05.10-00-00"

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
DEBUG_MODE="${DEBUG_MODE:-false}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

normalize_input() {
    local input="$1"
    local output="$input"

    # デバッグメッセージを標準エラー出力へリダイレクト
    [ "$DEBUG_MODE" = "true" ] && printf "DEBUG: Starting character normalization for input text\n" >&2

    # 入力前処理 - スペースの削除（先に実行）
    output=$(echo "$output" | sed 's/　//g')  # 全角スペースを削除
    output=$(echo "$output" | sed 's/ //g')   # 半角スペースを削除
    output=$(echo "$output" | sed 's/\t//g')  # タブ文字を削除

    # 変換テーブル（各行はsedコマンドの負荷を分散するため分割）

    # 数字（0-9）: 日本語、中国語（簡体字・繁体字）、韓国語で共通
    output=$(echo "$output" | sed 's/０/0/g; s/１/1/g; s/２/2/g; s/３/3/g; s/４/4/g')
    output=$(echo "$output" | sed 's/５/5/g; s/６/6/g; s/７/7/g; s/８/8/g; s/９/9/g')

    # アルファベット大文字（A-Z）: 各国共通の全角英字
    output=$(echo "$output" | sed 's/Ａ/A/g; s/Ｂ/B/g; s/Ｃ/C/g; s/Ｄ/D/g; s/Ｅ/E/g')
    output=$(echo "$output" | sed 's/Ｆ/F/g; s/Ｇ/G/g; s/Ｈ/H/g; s/Ｉ/I/g; s/Ｊ/J/g')
    output=$(echo "$output" | sed 's/Ｋ/K/g; s/Ｌ/L/g; s/Ｍ/M/g; s/Ｎ/N/g; s/Ｏ/O/g')
    output=$(echo "$output" | sed 's/Ｐ/P/g; s/Ｑ/Q/g; s/Ｒ/R/g; s/Ｓ/S/g; s/Ｔ/T/g')
    output=$(echo "$output" | sed 's/Ｕ/U/g; s/Ｖ/V/g; s/Ｗ/W/g; s/Ｘ/X/g; s/Ｙ/Y/g; s/Ｚ/Z/g')

    # アルファベット小文字（a-z）: 各国共通の全角英字
    output=$(echo "$output" | sed 's/ａ/a/g; s/ｂ/b/g; s/ｃ/c/g; s/ｄ/d/g; s/ｅ/e/g')
    output=$(echo "$output" | sed 's/ｆ/f/g; s/ｇ/g/g; s/ｈ/h/g; s/ｉ/i/g; s/ｊ/j/g')
    output=$(echo "$output" | sed 's/ｋ/k/g; s/ｌ/l/g; s/ｍ/m/g; s/ｎ/n/g; s/ｏ/o/g')
    output=$(echo "$output" | sed 's/ｐ/p/g; s/ｑ/q/g; s/ｒ/r/g; s/ｓ/s/g; s/ｔ/t/g')
    output=$(echo "$output" | sed 's/ｕ/u/g; s/ｖ/v/g; s/ｗ/w/g; s/ｘ/x/g; s/ｙ/y/g; s/ｚ/z/g')

    # 主要な記号（日本語、中国語、韓国語で共通使用される記号）
    output=$(echo "$output" | sed 's/！/!/g; s/＂/"/g; s/＃/#/g; s/＄/$/g; s/％/%/g')
    output=$(echo "$output" | sed 's/＆/\&/g; s/＇/'\''/g; s/（/(/g; s/）/)/g; s/＊/*/g')
    output=$(echo "$output" | sed 's/＋/+/g; s/，/,/g; s/－/-/g; s/．/./g; s/／/\//g')

    # 主要な記号（続き）
    output=$(echo "$output" | sed 's/：/:/g; s/；/;/g; s/＜/</g; s/＝/=/g; s/＞/>/g')
    output=$(echo "$output" | sed 's/？/?/g; s/＠/@/g; s/［/[/g; s/＼/\\/g; s/］/]/g')
    output=$(echo "$output" | sed 's/＾/^/g; s/＿/_/g; s/｀/`/g; s/｛/{/g; s/｜/|/g')
    output=$(echo "$output" | sed 's/｝/}/g; s/～/~/g')

    # 韓国語特有の全角記号
    output=$(echo "$output" | sed 's/￦/\\/g; s/￥/\\/g')

    # デバッグメッセージを標準エラー出力へリダイレクト
    [ "$DEBUG_MODE" = "true" ] && printf "DEBUG: Character normalization completed\n" >&2

    # 正規化した結果のみを返す（デバッグ情報なし）
    printf '%s' "$output"
}

# 改行文字を処理するための関数
process_newlines() {
    local input="$1"
    # \nを実際の改行に変換
    printf "%b" "$input"
}

# 確認入力処理関数（パラメータ形式対応版）
confirm() {
    local msg_key="${1:-MSG_CONFIRM_DEFAULT}"  # デフォルトのメッセージキー
    local input_type="yn"  # デフォルトの入力タイプ
    local msg=""
    local yn=""

    # メッセージの取得
    if [ -n "$msg_key" ]; then
        # 最初に基本メッセージを取得
        msg=$(get_message "$msg_key")

        # パラメータの処理
        shift
        while [ $# -gt 0 ]; do
            local param="$1"

            # パラメータ形式の判定（name=value または input_type）
            case "$param" in
                *=*)
                    # name=value形式のパラメータ
                    local param_name=$(echo "$param" | cut -d'=' -f1)
                    local param_value=$(echo "$param" | cut -d'=' -f2-)

                    if [ -n "$param_name" ] && [ -n "$param_value" ]; then
                        local safe_value=$(echo "$param_value" | sed 's/[\/&]/\\&/g')
                        msg=$(echo "$msg" | sed "s|{$param_name}|$safe_value|g")
                        debug_log "DEBUG" "Replaced placeholder {$param_name} with value: $param_value"
                    fi
                    ;;
                yn|ynr)
                    # 入力タイプとして処理
                    input_type="$param"
                    ;;
                *)
                    # その他のパラメータは無視（互換性のため）
                    debug_log "DEBUG" "Ignoring unknown parameter: $param"
                    ;;
            esac

            shift
        done
    else
        debug_log "ERROR" "No message key specified for confirmation"
        return 1
    fi

    # 入力タイプに基づき適切な表示形式に置き換え
    if [ "$input_type" = "ynr" ]; then
        # (y/n/r)を表示用メッセージに追加
        msg=$(echo "$msg" | sed 's/{ynr}/(y\/n\/r)/g')
        debug_log "DEBUG" "Running in YNR mode with message: $msg_key"
    else
        # (y/n)を表示用メッセージに追加
        msg=$(echo "$msg" | sed 's/{yn}/(y\/n)/g')
        debug_log "DEBUG" "Running in YN mode with message: $msg_key"
    fi

    # ユーザー入力ループ
    while true; do
        # プロンプト表示（改行対応 - printf %bを使用）
        # ★★★ 変更点: 末尾の不要なスペースを削除 ★★★
        printf "%b" "$(color white "$msg")"
        
        # --- /dev/ttyから入力を受ける ---
        IFS= read -r yn < /dev/tty

        yn=$(normalize_input "$yn")
        debug_log "DEBUG" "Processing user input: $yn"

        # 入力の正規化
        yn=$(normalize_input "$yn")
        debug_log "DEBUG" "Processing user input: $yn"

        # 入力検証
        case "$yn" in
            [Yy]|[Yy][Ee][Ss]|はい|ハイ|ﾊｲ)
                debug_log "DEBUG" "User confirmed: Yes"
                CONFIRM_RESULT="Y"
                return 0
                ;;
            [Nn]|[Nn][Oo]|いいえ|イイエ|ｲｲｴ)
                debug_log "DEBUG" "User confirmed: No"
                CONFIRM_RESULT="N"
                return 1
                ;;
            [Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]|戻る|モドル|ﾓﾄﾞﾙ)
                # YNRモードの場合のみRを許可
                if [ "$input_type" = "ynr" ]; then
                    debug_log "DEBUG" "User selected: Return option"
                    CONFIRM_RESULT="R"
                    return 2
                fi
                # YNモードではRを無効として処理
                debug_log "DEBUG" "Return option not allowed in YN mode"
                show_invalid_input_error "$input_type"
                continue
                ;;
            *)
                # エラーメッセージ表示
                show_invalid_input_error "$input_type"
                debug_log "DEBUG" "Invalid input detected for $input_type mode"
                ;;
        esac
    done
}

# 無効な入力に対するエラーメッセージを表示する関数
show_invalid_input_error() {
    local input_type="$1"
    local error_msg
    local options_str="" # オプション文字列用変数

    if [ "$input_type" = "ynr" ]; then
        options_str="(y/n/r)" # y/n/r モードの時のオプション文字列
        error_msg=$(get_message "MSG_INVALID_INPUT" "op=$options_str") # 変更: 新しいプレースホルダ名 'op' を使用
    else
        options_str="(y/n)"   # y/n モードの時のオプション文字列
        error_msg=$(get_message "MSG_INVALID_INPUT" "op=$options_str") # 変更: 新しいプレースホルダ名 'op' を使用
    fi

    printf "%s\n" "$(color red "$error_msg")"
}

# 番号選択関数
select_list() {
    local select_list="$1"
    local tmp_file="$2"
    local type="$3"

    debug_log "DEBUG" "Running select_list() with t=$type"

    # メッセージキー設定
    local prompt_msg_key=""
    case "$type" in
        country) prompt_msg_key="MSG_SELECT_COUNTRY_NUMBER" ;;
        zone)    prompt_msg_key="MSG_SELECT_ZONE_NUMBER" ;;
        *)       prompt_msg_key="MSG_SELECT_NUMBER" ;;
    esac

    # リストの行数を計算
    local total_items=$(echo "$select_list" | wc -l)
    debug_log "DEBUG" "Total items in list: $total_items"

    # 項目が1つだけなら自動選択
    if [ "$total_items" -eq 1 ]; then
        debug_log "DEBUG" "Only one item available, auto-selecting"
        echo "1" > "$tmp_file"
        return 0
    fi

    # 選択肢を表示
    local display_count=1
    while IFS= read -r line; do
        printf "[%d] %s\n" "$display_count" "$line"
        display_count=$((display_count + 1))
    done <<EOF
$select_list
EOF

    # 選択ループ
    local prompt_msg=$(get_message "$prompt_msg_key")

    while true; do
        # プロンプト表示
        printf "%s " "$(color white "$prompt_msg")"

        # 入力読み取り
        read -r number
        number=$(normalize_input "$number")
        debug_log "DEBUG" "User entered: $number"

        # 数値チェック
        if ! echo "$number" | grep -q '^[0-9]\+$'; then
            # エラーの前は行間詰め
            printf "%s\n" "$(color red "$(get_message "CONFIG_ERROR_NOT_NUMBER")")"
            debug_log "DEBUG" "Invalid input: not a number"
            continue
        fi

        # 範囲チェック
        if [ "$number" -lt 1 ] || [ "$number" -gt "$total_items" ]; then
            # エラーの前は行間詰め
            printf "%s\n" "$(color red "$(get_message "MSG_NUMBER_OUT_OF_RANGE")")"
            debug_log "DEBUG" "Invalid input: number out of range (1-$total_items)"
            continue
        fi

        # 選択項目を取得
        local selected_item=$(echo "$select_list" | sed -n "${number}p")
        debug_log "DEBUG" "Selected item: $selected_item"

        # 確認メッセージを表示 (get_message を使って動的に生成)
        local confirm_msg_key="MSG_CONFIRM_SELECT" # 共通の確認メッセージキー
        local confirm_prompt=$(get_message "$confirm_msg_key" "i=$selected_item") # プレースホルダ {i} を置換

        # 確認（YNRモードで）
        # confirm 関数内でメッセージキーとパラメータを処理するように修正済みのため、
        # ここでは get_message を使って生成したメッセージではなく、キーとパラメータを渡す
        confirm "$confirm_msg_key" "ynr" "i=$selected_item"
        local ret=$?

        case $ret in
            0)  # Yes
                debug_log "DEBUG" "Selection confirmed for item #$number"
                echo "$number" > "$tmp_file"
                return 0
                ;;
            2)  # Return
                debug_log "DEBUG" "User requested to return to selection"
                return 2
                ;;
            *)  # No - 再選択
                debug_log "DEBUG" "Selection cancelled, prompting again"
                ;;
        esac
    done
}

# sed用にテキストをエスケープする関数
escape_for_sed() {
    local input="$1"
    # sedで特殊扱いされる文字をエスケープ
    printf '%s' "$input" | sed 's/[\/&.*[\]^$]/\\&/g'
}

# =========================================================
# 自動検出フローの統括関数 (キャッシュ -> IP)
# 内部ヘルパー関数を呼び出す
# 戻り値: 0 (成功), 1 (失敗またはユーザーによる拒否)
# =========================================================
detect_and_set_location() {
    debug_log "DEBUG" "Running detect_and_set_location() - orchestrating cache and IP detection"

    # 全体スキップフラグのチェック
    if [ "$SKIP_ALL_DETECTION" = "true" ]; then
        debug_log "DEBUG" "SKIP_ALL_DETECTION is true, skipping all detection methods"
        return 1
    fi

    # ステップ1: キャッシュからの検出試行
    debug_log "DEBUG" "Attempting detection from cache"
    if try_detect_from_cache; then
        debug_log "DEBUG" "Detection successful from cache"
        return 0 # キャッシュ成功
    fi

    # ステップ2: IPからの検出試行
    debug_log "DEBUG" "Cache detection failed or skipped, attempting detection from IP"
    if try_detect_from_ip; then
        debug_log "DEBUG" "Detection successful from IP"
        return 0 # IP検出成功
    fi

    # すべて失敗
    debug_log "DEBUG" "All automatic detection methods failed or were declined"
    return 1
}

# タイムゾーンの選択を処理する関数
select_zone() {
    debug_log "DEBUG" "Running select_zone() function"
    # 引数削除

    # 選択された国の情報を取得
    local selected_country_file="${CACHE_DIR}/country.ch"
    if [ ! -f "$selected_country_file" ]; then
        debug_log "ERROR" "Country selection file not found"
        return 1
    fi

    # 国のタイムゾーン情報を抽出（6列目以降がタイムゾーン情報）
    local zone_list=$(awk '{for(i=6;i<=NF;i++) print $i}' "$selected_country_file")
    if [ -z "$zone_list" ]; then
        debug_log "ERROR" "No timezone information found for selected country"
        return 1
    fi
    debug_log "DEBUG" "Extracted timezone list for selected country"

    # タイムゾーン数を数える
    local zone_count=$(echo "$zone_list" | wc -l)
    debug_log "DEBUG" "Found $zone_count timezone(s) for selected country"

    # タイムゾーンが1つだけの場合は自動選択
    if [ "$zone_count" -eq 1 ]; then
        local selected=$(echo "$zone_list")
        debug_log "DEBUG" "Only one timezone available: $selected - auto selecting"

        # zone_write関数に処理を委譲（直接引数として渡す）
        zone_write "$selected" || {
            debug_log "ERROR" "Failed to write timezone data (auto select)"
            return 1
        }

        # --- 削除 ---
        # 成功メッセージ表示ロジック
        # -------------

        return 0
    fi

    # 複数のタイムゾーンがある場合は選択肢を表示
    printf "\n%s\n" "$(color white "$(get_message "MSG_SELECT_TIMEZONE")")"

    # 番号付きリスト表示 - select_list関数を使用
    local number_file="${CACHE_DIR}/zone_selection.tmp"

    # select_list関数を呼び出す
    select_list "$zone_list" "$number_file" "zone"
    local select_result=$?

    # 戻り値に応じた処理
    case $select_result in
        0) # 選択成功
            if [ ! -f "$number_file" ]; then
                debug_log "ERROR" "Zone selection number file not found"
                return 1
            fi
            local number=$(cat "$number_file")
            rm -f "$number_file" # 一時ファイル削除
            if [ -z "$number" ]; then
                debug_log "ERROR" "Empty zone selection number"
                return 1
            fi

            local selected=$(echo "$zone_list" | sed -n "${number}p")
            debug_log "DEBUG" "Selected timezone from list: $selected"

            # zone_write関数に処理を委譲（直接引数として渡す）
            zone_write "$selected" || {
                debug_log "ERROR" "Failed to write timezone data (manual select)"
                return 1
            }

            # --- 削除 ---
            # 成功メッセージ表示ロジック
            # -------------

            return 0
            ;;
        2) # 「戻る」が選択された
            debug_log "DEBUG" "User requested return during timezone selection"
            return 2  # 上位関数で処理
            ;;
        *) # キャンセルまたはエラー
            debug_log "DEBUG" "Zone selection cancelled or error occurred"
            return 1
            ;;
    esac
}

# 国コード情報を書き込む関数（言語正規化、翻訳初期化）
country_write() {
    # 引数削除
    debug_log "DEBUG" "Entering country_write()"

    # 一時ファイルのパス
    local tmp_country="${CACHE_DIR}/country.tmp"

    # 出力先ファイルのパス
    local cache_country="${CACHE_DIR}/country.ch"
    local cache_language="${CACHE_DIR}/language.ch"
    local cache_luci="${CACHE_DIR}/luci.ch"
    local cache_message="${CACHE_DIR}/message.ch"

    # 一時ファイルが存在するか確認
    if [ ! -f "$tmp_country" ]; then
        debug_log "ERROR" "File not found: $tmp_country"
        return 1
    fi

    # 一時ファイルから国情報をキャッシュに保存
    cat "$tmp_country" > "$cache_country"
    debug_log "DEBUG" "Country information written to cache"

    # 選択された国と言語情報を抽出
    local selected_country=$(awk '{print $2, $3}' "$cache_country")
    debug_log "DEBUG" "Selected country: $selected_country"

    # 選択された国の言語コードを取得（5列目）
    local selected_lang_code=$(awk '{print $5}' "$cache_country")
    debug_log "DEBUG" "Selected language code: $selected_lang_code"

    # 言語設定をキャッシュに保存
    echo "$selected_lang_code" > "$cache_language"
    debug_log "DEBUG" "Language code written to cache"

    # LuCIインターフェース用言語コードを取得（4列目）
    local luci_code=$(awk '{print $4}' "$cache_country")
    debug_log "DEBUG" "LuCI interface language code: $luci_code"

    # LuCI言語コードをキャッシュに保存
    echo "$luci_code" > "$cache_luci"
    debug_log "DEBUG" "LuCI language code written to cache: $luci_code"

    # メッセージ言語コードを保存（LuCI言語コードと同じ）
    echo "$luci_code" > "$cache_message"
    debug_log "DEBUG" "Message language code written to cache: $luci_code"

    return 0
}

zone_write() {
    debug_log "DEBUG" "Entering zone_write()"

    # 引数またはファイルからタイムゾーン情報を取得
    local timezone_str=""
    local tmp_zone="${CACHE_DIR}/zone.tmp"

    if [ -n "$1" ]; then
        # 引数が提供された場合、それを使用
        timezone_str="$1"
        debug_log "DEBUG" "Using timezone string from argument: ${timezone_str}"
    elif [ -f "$tmp_zone" ]; then
        # 一時ファイルから読み込み
        timezone_str=$(cat "$tmp_zone")
        debug_log "DEBUG" "Reading timezone from temporary file: ${timezone_str}"
    else
        # 両方とも利用できない場合はエラー
        debug_log "ERROR" "No timezone data provided and no temporary file found"
        local safe_filename=$(escape_for_sed "$tmp_zone")
        debug_log "ERROR" "File not found: $safe_filename"
        return 1
    fi

    # タイムゾーン情報を分割して保存
    if [ -n "$timezone_str" ]; then
        local zonename=""
        local timezone=""

        if echo "$timezone_str" | grep -q ","; then
            # カンマで区切られている場合は分割
            zonename=$(echo "$timezone_str" | cut -d ',' -f 1)
            timezone=$(echo "$timezone_str" | cut -d ',' -f 2)
            debug_log "DEBUG" "Parsed comma-separated timezone: zonename=$zonename, timezone=$timezone"
        else
            # カンマがない場合はそのまま使用 (形式がおかしい可能性もあるが、そのまま保存)
            zonename="$timezone_str"
            timezone="GMT0" # デフォルト値？ またはエラー処理が必要か検討
            debug_log "WARNING" "Using simple timezone format (no comma): zonename=$zonename, assuming timezone=$timezone"
        fi

        # キャッシュに書き込み
        echo "$zonename" > "${CACHE_DIR}/zonename.ch"
        echo "$timezone" > "${CACHE_DIR}/timezone.ch"
        echo "$timezone_str" > "${CACHE_DIR}/zone.ch" # 元の文字列も保存しておく

        debug_log "DEBUG" "Timezone information written to cache successfully"
        return 0
    else
        debug_log "ERROR" "Empty timezone string provided"
        debug_log "ERROR" "An error occurred during timezone processing"
        return 1
    fi
}

# =========================================================
# ヘルパー関数: 手動選択による設定試行
# 戻り値: 0 (成功), 1 (失敗またはユーザーによるキャンセル)
# =========================================================
try_setup_from_manual_selection() {
    debug_log "DEBUG" "Starting manual country selection process"
    local input_lang="" # 検索キーワード用

    # 国の入力と検索ループ
    while true; do
        # 入力がまだない場合は入力を求める
        if [ -z "$input_lang" ]; then
            local msg_enter=$(get_message "MSG_ENTER_COUNTRY")
            printf "%s\n" "$(color white "$msg_enter")"

            local msg_search=$(get_message "MSG_SEARCH_KEYWORD")
            printf "%s " "$(color white "$msg_search")"

            read -r input_lang
            input_lang=$(normalize_input "$input_lang")
            debug_log "DEBUG" "User entered search keyword: $input_lang"
        fi

        printf "\n"

        # 空の入力をチェック
        if [ -z "$input_lang" ]; then
            debug_log "DEBUG" "Empty search keyword, prompting again"
            continue
        fi

        # 入力の正規化と検索
        local cleaned_input=$(echo "$input_lang" | sed 's/[\/,_]/ /g')
        local full_results=$(awk -v search="$cleaned_input" \
            'BEGIN {IGNORECASE=1} { if ($0 ~ search) print $0 }' \
            "$BASE_DIR/country.db" 2>>"$LOG_DIR/debug.log")

        # 検索結果がない場合
        if [ -z "$full_results" ]; then
            local msg_not_found=$(get_message "MSG_COUNTRY_NOT_FOUND")
            local escaped_input=$(escape_for_sed "$input_lang")
            msg_not_found=$(echo "$msg_not_found" | sed "s/{0}/$escaped_input/g")
            printf "%s\n" "$(color red "$msg_not_found")"
            input_lang=""  # リセットして再入力
            continue
        fi

        # 結果が1件のみの場合、自動選択と確認
        local result_count=$(echo "$full_results" | wc -l)
        if [ "$result_count" -eq 1 ]; then
            local country_name=$(echo "$full_results" | awk '{print $2, $3}')

            # メッセージと国名を別々に色付け
            local msg=$(get_message "MSG_SINGLE_MATCH_FOUND")
            local msg_prefix=${msg%%\{0\}*}
            local msg_suffix=${msg#*\{0\}}

            printf "%s%s%s" "$(color white "$msg_prefix")" "$(color yellow "$country_name")" "$(color white "$msg_suffix")"
            printf "\n"

            # 確認（confirm関数使用）
            if confirm "MSG_CONFIRM_ONLY_YN"; then
                echo "$full_results" > "${CACHE_DIR}/country.tmp"

                # country_write関数に処理を委譲 (メッセージ表示はここでしない)
                country_write || {
                    debug_log "ERROR" "Failed to write country data (single match)"
                    return 1 # 失敗
                }

                # 国選択完了メッセージを表示
                printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"

                debug_log "DEBUG" "Country selected from single match: $country_name"

                # ゾーン選択を実行
                select_zone
                local zone_result=$?
                case $zone_result in
                    0) # 正常終了
                        # ゾーン選択完了メッセージを表示
                        printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
                        EXTRA_SPACING_NEEDED="yes"
                        debug_log "DEBUG" "Timezone selection completed successfully (single match)"
                        return 0 # 成功
                        ;;
                    2) # 「戻る」が選択された
                        debug_log "DEBUG" "User requested return during timezone selection (single match), restarting country search"
                        # 一時キャッシュをクリア
                        rm -f "${CACHE_DIR}/country.ch" "${CACHE_DIR}/language.ch" "${CACHE_DIR}/message.ch" 2>/dev/null
                        rm -f "${CACHE_DIR}/zone.tmp" "${CACHE_DIR}/zonename.ch" "${CACHE_DIR}/timezone.ch" "${CACHE_DIR}/zone.ch" 2>/dev/null
                        input_lang="" # 国検索からやり直し
                        continue
                        ;;
                    *) # エラーまたはキャンセル
                        debug_log "ERROR" "Timezone selection failed or cancelled (single match)"
                        return 1 # 失敗
                        ;;
                esac
            else
                # 国確認でNoの場合
                input_lang="" # 国検索からやり直し
                continue
            fi
        fi

        # 複数結果の場合、select_list関数を使用
        debug_log "DEBUG" "Multiple results found for '$input_lang'. Using select_list function."

        # 表示用リスト作成（国名のみ抽出）
        local display_list=$(echo "$full_results" | awk '{print $2, $3}')
        local number_file="${CACHE_DIR}/number_selection.tmp"

        # select_list関数を呼び出し
        select_list "$display_list" "$number_file" "country"
        local select_result=$?

        # 選択結果処理
        case $select_result in
            0) # 選択成功
                if [ ! -f "$number_file" ]; then
                    debug_log "ERROR" "Country selection number file not found (multiple match)"
                    return 1 # 失敗
                fi
                local selected_number=$(cat "$number_file")
                rm -f "$number_file" # 一時ファイル削除

                local selected_full=$(echo "$full_results" | sed -n "${selected_number}p")
                local selected_country=$(echo "$selected_full" | awk '{print $2, $3}')
                debug_log "DEBUG" "Selected country from list: $selected_country"

                echo "$selected_full" > "${CACHE_DIR}/country.tmp"

                # country_write関数に処理を委譲 (メッセージ表示はここでしない)
                country_write || {
                    debug_log "ERROR" "Failed to write country data (multiple match)"
                    return 1 # 失敗
                }

                # 国選択完了メッセージを表示
                printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"

                debug_log "DEBUG" "Country selected from multiple choices: $selected_country"

                # ゾーン選択を実行
                select_zone
                local zone_result=$?
                case $zone_result in
                    0) # 正常終了
                        # ゾーン選択完了メッセージを表示
                        printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
                        EXTRA_SPACING_NEEDED="yes"
                        debug_log "DEBUG" "Timezone selection completed successfully (multiple match)"
                        return 0 # 成功
                        ;;
                    2) # 「戻る」が選択された
                        debug_log "DEBUG" "User requested return during timezone selection (multiple match), restarting country search"
                        # 一時キャッシュをクリア
                        rm -f "${CACHE_DIR}/country.ch" "${CACHE_DIR}/language.ch" "${CACHE_DIR}/message.ch" 2>/dev/null
                        rm -f "${CACHE_DIR}/zone.tmp" "${CACHE_DIR}/zonename.ch" "${CACHE_DIR}/timezone.ch" "${CACHE_DIR}/zone.ch" 2>/dev/null
                        input_lang="" # 国検索からやり直し
                        continue
                        ;;
                    *) # エラーまたはキャンセル
                        debug_log "ERROR" "Timezone selection failed or cancelled (multiple match)"
                        return 1 # 失敗
                        ;;
                esac
                ;;
            2) # 「戻る」が選択された（国リストでR）
                debug_log "DEBUG" "User requested return from country selection list, prompting for keyword again"
                input_lang="" # 国検索からやり直し
                continue
                ;;
            *) # キャンセルまたはエラー (国リストでNなど)
                debug_log "DEBUG" "User cancelled country selection or error occurred, prompting for keyword again"
                input_lang="" # 国検索からやり直し
                continue
                ;;
        esac
    done
}

# =========================================================
# ヘルパー関数: IPアドレスからの検出、確認、設定試行
# 戻り値: 0 (成功), 1 (失敗、拒否、またはスキップ)
# =========================================================
try_detect_from_ip() {
    # IP検出スキップフラグのチェック
    if [ "$SKIP_IP_DETECTION" = "true" ]; then
        debug_log "DEBUG" "IP detection skipped due to flag settings"
        return 1
    fi

    debug_log "DEBUG" "Attempting IP-based location detection via process_location_info()"

    # common-information.sh を source する必要があれば行う
    # (既に source されているか、依存関係で解決される想定)
    if ! command -v process_location_info >/dev/null 2>&1; then
        if [ -f "$BASE_DIR/common-information.sh" ]; then
            debug_log "DEBUG" "Sourcing common-information.sh for process_location_info"
            . "$BASE_DIR/common-information.sh"
        else
            debug_log "ERROR" "common-information.sh not found. Cannot perform IP detection."
            return 1
        fi
    fi

    # IP位置情報の取得 (結果はグローバル変数 SELECT_*, ISP_*, TIMEZONE_API_SOURCE に格納される)
    if ! process_location_info; then
        debug_log "DEBUG" "process_location_info() failed to retrieve or process location data"
        return 1
    fi

    # ★★★ 変更点: process_location_info は一時ファイルを使わなくなったため、読み込み処理は不要 ★★★
    # detected_ 変数への代入は process_location_info から取得したグローバル変数を使用
    local detected_country="$SELECT_COUNTRY"
    local detected_timezone="$SELECT_TIMEZONE" # POSIX TZ
    local detected_zonename="$SELECT_ZONENAME" # IANA Zone Name
    local detected_isp="$ISP_NAME"
    local detected_as="$ISP_AS"

    debug_log "DEBUG" "IP detection results - country: $detected_country, timezone: $detected_timezone, zonename: $detected_zonename, isp: $detected_isp, as: $detected_as"

    # 必須情報の検証
    if [ -z "$detected_country" ] || [ -z "$detected_timezone" ] || [ -z "$detected_zonename" ]; then
        debug_log "DEBUG" "One or more required IP location data values are empty after process_location_info"
        return 1 # 必須情報が欠けている場合は失敗
    fi

    # 国データをDBから取得
    local country_data=$(awk -v code="$detected_country" '$5 == code {print $0; exit}' "$BASE_DIR/country.db")
    if [ -z "$country_data" ]; then
        debug_log "ERROR" "Could not find country data in DB for detected country: $detected_country"
        return 1 # 国データが見つからない場合は失敗
    fi

    # 検出情報を表示 (成功メッセージなし)
    display_detected_location "IP Address" "$detected_country" "$detected_zonename" "$detected_timezone" "$detected_isp" "$detected_as"

    # 情報表示の後に空行を追加
    printf "\n"

    # ユーザーに確認 (短縮プロンプト)
    if ! confirm "MSG_CONFIRM_USE_SETTINGS_SHORT"; then
        debug_log "DEBUG" "User declined IP-based location settings"
        # ★★★ 削除: 一時ファイルのクリーンアップ処理 (一時ファイルを使わないため不要) ★★★
        # rm -f "${CACHE_DIR}/ip_"*.tmp 2>/dev/null
        return 1 # ユーザー拒否
    fi

    debug_log "DEBUG" "User accepted IP-based location settings"

    # ★★★ 変更点: 設定の適用 (永続キャッシュへの直接書き込み) ★★★
    debug_log "DEBUG" "Applying IP-based settings to permanent cache"

    # 1. 国設定の適用 (country_write を使用)
    debug_log "DEBUG" "Writing country data to temporary file for country_write"
    echo "$country_data" > "${CACHE_DIR}/country.tmp" # country_write は一時ファイルを読み込む仕様のため

    country_write || {
        debug_log "ERROR" "Failed to write country data via country_write"
        rm -f "${CACHE_DIR}/country.tmp" 2>/dev/null # エラー時は一時ファイルを削除
        return 1
    }
    # country_write が成功したら一時ファイルは不要
    rm -f "${CACHE_DIR}/country.tmp" 2>/dev/null

    # 2. タイムゾーン設定の適用 (zone_write を使用)
    local timezone_str="${detected_zonename},${detected_timezone}"
    debug_log "DEBUG" "Created combined timezone string for zone_write: ${timezone_str}"
    zone_write "$timezone_str" || {
        debug_log "ERROR" "Failed to write timezone data via zone_write"
        # 国設定は既に書き込まれているが、タイムゾーン設定に失敗した
        # 必要であればロールバック処理を追加する (今回はエラーリターンのみ)
        return 1
    }

    # 国と言語、タイムゾーンの選択完了メッセージをここで表示
    printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"
    printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
    EXTRA_SPACING_NEEDED="yes" # 後続処理のためのフラグ

    debug_log "DEBUG" "IP-based location settings applied successfully to permanent cache"
    return 0 # 成功
}

# =========================================================
# ヘルパー関数: キャッシュからの検出試行
# 戻り値: 0 (成功), 1 (失敗またはスキップ)
# =========================================================
try_detect_from_cache() {
    # キャッシュ関連スキップフラグのチェック (変更なし)
    if [ "$SKIP_CACHE_DETECTION" = "true" ] || [ "$SKIP_CACHE_DEVICE_DETECTION" = "true" ]; then
        debug_log "DEBUG" "Cache detection skipped due to flag settings"
        return 1
    fi

    # ★★★ 変更点: check_location_cache() の呼び出しを復元 ★★★
    debug_log "DEBUG" "Checking location cache using check_location_cache()"
    # check_location_cache は元のロジック (5ファイルチェック) のまま呼び出す
    if ! check_location_cache; then
        debug_log "DEBUG" "Cache check failed (check_location_cache returned non-zero)"
        return 1
    fi
    # ★★★ check_location_cache() 呼び出し復元ここまで ★★★

    debug_log "DEBUG" "Valid location cache found (based on check_location_cache), proceeding with cache initialization (translation)"

    # ★★★ 変更点: language.ch から国コードを読み込むロジックを復元 ★★★
    local cache_language="${CACHE_DIR}/language.ch"
    local detected_country_code=""
    if [ -s "$cache_language" ]; then
        detected_country_code=$(cat "$cache_language" 2>/dev/null)
    fi

    # 国コードがない場合は失敗 (check_location_cache が成功していれば通常ありえないはずだが念のため)
    if [ -z "$detected_country_code" ]; then
        debug_log "ERROR" "Required language code cache (language.ch) is empty or missing even after check_location_cache succeeded? Aborting cache use."
        return 1
    fi

    debug_log "DEBUG" "Cache data - language code (country code): $detected_country_code"

    # ★★★ 変更点: country.db から国データを取得するロジックを復元 ★★★
    local country_data=$(awk -v code="$detected_country_code" '$5 == code {print $0; exit}' "$BASE_DIR/country.db")
    if [ -z "$country_data" ]; then
         debug_log "ERROR" "Could not find country data in DB for cached country code: $detected_country_code. Aborting cache use."
         # 翻訳初期化ができないため失敗として扱う
         return 1
    fi

    # 国情報を一時ファイルに書き出し (country_write が読み込むため - 変更なし)
    echo "$country_data" > "${CACHE_DIR}/country.tmp"

    # country_write を呼び出し (翻訳初期化のため、メッセージ表示はしない - 変更なし)
    if ! country_write; then
         # country_write 失敗時は return 1 (変更なし)
         debug_log "ERROR" "Failed to initialize translation via country_write for cache (indicates broken state). Aborting cache use."
         rm -f "${CACHE_DIR}/country.tmp" 2>/dev/null # エラー時は一時ファイルを削除
         return 1 # 失敗として IP 検出に進む
    fi
    # country_write が成功したら一時ファイルは不要
    rm -f "${CACHE_DIR}/country.tmp" 2>/dev/null

    debug_log "DEBUG" "Cache-based initialization (translation) completed successfully"
    return 0 # キャッシュからの初期化成功
}

# =========================================================
# ヘルパー関数: 自動検出による設定試行
# 戻り値: 0 (成功), 1 (失敗またはユーザーによる拒否)
# =========================================================
try_setup_from_auto_detection() {
    debug_log "DEBUG" "Attempting setup via auto-detection by calling detect_and_set_location()"
    detect_and_set_location # 内部でキャッシュ検出、IP検出を実行
    local result=$?
    debug_log "DEBUG" "detect_and_set_location returned: $result"
    return $result # detect_and_set_location の結果をそのまま返す
}

# =========================================================
# ヘルパー関数: コマンドライン引数からの設定試行
# 引数: $1 - 国コード (例: JP, US)
# 戻り値: 0 (成功), 1 (失敗または引数なし)
# =========================================================
try_setup_from_argument() {
    local input_lang="$1"

    if [ -z "$input_lang" ]; then
        debug_log "DEBUG" "No country argument provided, skipping setup from argument"
        return 1 # 引数がない場合は失敗
    fi

    debug_log "DEBUG" "Attempting setup with country argument: $input_lang"

    # 短縮国名（$5）と完全一致するエントリを検索
    local lang_match=$(awk -v lang="$input_lang" '$5 == lang {print $0; exit}' "$BASE_DIR/country.db")

    if [ -z "$lang_match" ]; then
        debug_log "DEBUG" "No exact country code match found for argument: $input_lang"
        return 1 # 一致しない場合は失敗
    fi

    debug_log "DEBUG" "Exact country code match found: $lang_match"

    # 一時ファイルに書き込み
    echo "$lang_match" > "${CACHE_DIR}/country.tmp"

    # country_write関数に処理を委譲 (メッセージ表示はここでしない)
    country_write || {
        debug_log "ERROR" "Failed to write country data from language argument"
        rm -f "${CACHE_DIR}/country.tmp" 2>/dev/null # エラー時は一時ファイルを削除
        return 1
    }

    # 国選択完了メッセージを表示
    printf "%s\n" "$(color green "$(get_message "MSG_COUNTRY_SUCCESS")")"

    # ゾーン選択を実行
    select_zone
    local zone_result=$?

    # ゾーン選択の結果を処理
    case $zone_result in
        0) # 正常終了
            # ゾーン選択完了メッセージを表示
            printf "%s\n" "$(color green "$(get_message "MSG_TIMEZONE_SUCCESS")")"
            EXTRA_SPACING_NEEDED="yes"
            debug_log "DEBUG" "Timezone selection completed successfully after argument setup"
            return 0 # 成功
            ;;
        2) # 「戻る」が選択された (このフローでは実質キャンセル扱い)
            debug_log "DEBUG" "User requested to return during timezone selection after argument setup"
            # 一時ファイルをクリア
            rm -f "${CACHE_DIR}/country.ch" "${CACHE_DIR}/language.ch" "${CACHE_DIR}/message.ch" 2>/dev/null
            rm -f "${CACHE_DIR}/zone.tmp" "${CACHE_DIR}/zonename.ch" "${CACHE_DIR}/timezone.ch" "${CACHE_DIR}/zone.ch" 2>/dev/null
            return 1 # 失敗扱い
            ;;
        *) # エラーまたはキャンセル
            debug_log "ERROR" "Timezone selection failed or cancelled after argument setup"
            return 1 # 失敗
            ;;
    esac
}

setup_location() {
    # --- ローカルNTPサーバー機能の有効化オプション ---
    # true に設定すると、このデバイスがLAN内の他のデバイスにNTPサービスを提供します。
    # この場合、system.ntp.enable_server が '1' に、system.ntp.interface が 'lan' に設定されます。
    # false の場合、aios は system.ntp.enable_server と system.ntp.interface を変更しません。
    # デフォルトは true (デバイス自身の時刻同期を行い、NTPサーバーとしても機能する)。
    local ENABLE_LOCAL_NTP_SERVER='true' 
    # 例: LAN向けNTPサーバー機能をaiosで設定しない場合は以下のように変更
    # local ENABLE_LOCAL_NTP_SERVER='false'

    # 「DHCPから通知されたサーバを使用」を制御するUCIオプションのパス
    # ユーザー様の uci show network 出力に基づき、'network.wan.peerntp' を対象とします。
    local PEERNTP_UCI_PATH="network.wan.peerntp"
    local PEERNTP_SECTION_PATH="network.wan" # PEERNTP_UCI_PATH のセクション部分
    # --- ローカルNTPサーバー機能の有効化オプションここまで ---

    if [ ! -f "${CACHE_DIR}/language.ch" ]; then
        debug_log "DEBUG" "language.ch not found, skipping location setup"
        return
    fi

    # キャッシュファイルから値を取得
    local zonename timezone language
    zonename="$(cat "${CACHE_DIR}/zonename.ch" 2>/dev/null)"
    timezone="$(cat "${CACHE_DIR}/timezone.ch" 2>/dev/null)"
    language="$(cat "${CACHE_DIR}/language.ch" 2>/dev/null)"

    # zonenameのデフォルト判定と設定
    local current_zonename
    current_zonename="$(uci get system.@system[0].zonename 2>/dev/null)"
    if [ -z "$current_zonename" ] || [ "$current_zonename" = "00" ] || [ "$current_zonename" = "UTC" ]; then
        if [ -n "$zonename" ] && [ "$zonename" != "00" ] && [ "$zonename" != "UTC" ]; then
            debug_log "DEBUG" "Setting zonename from cache: $zonename"
            uci set system.@system[0].zonename="$zonename"
        fi
    fi

    # timezoneのデフォルト判定と設定
    local current_timezone
    current_timezone="$(uci get system.@system[0].timezone 2>/dev/null)"
    if [ -z "$current_timezone" ] || [ "$current_timezone" = "UTC" ]; then
        if [ -n "$timezone" ] && [ "$timezone" != "UTC" ]; then
            debug_log "DEBUG" "Setting timezone from cache: $timezone"
            uci set system.@system[0].timezone="$timezone"
        fi
    fi

    # NTPサーバ自動設定: language.ch値を使い、バリデートしてからセット
    local ntp_pool ntp_valid=0
    if [ -n "$language" ]; then
        ntp_pool="$language"
        if nslookup "0.$ntp_pool.pool.ntp.org" >/dev/null 2>&1; then
            ntp_valid=1
        fi
    fi

    if [ "$ntp_valid" -eq 1 ]; then
        debug_log "DEBUG" "Setting NTP server to 0.$ntp_pool.pool.ntp.org 1.$ntp_pool.pool.ntp.org 2.$ntp_pool.pool.ntp.org 3.$ntp_pool.pool.ntp.org"
        uci set system.ntp.server="0.$ntp_pool.pool.ntp.org 1.$ntp_pool.pool.ntp.org 2.$ntp_pool.pool.ntp.org 3.$ntp_pool.pool.ntp.org"
        
        # system.ntp セクションの存在確認
        if uci get system.ntp >/dev/null 2>&1; then
            # 1. NTPクライアント機能の有効化 (常に '1' を目指す)
            local current_ntp_enable
            current_ntp_enable=$(uci get system.ntp.enable 2>/dev/null)
            if [ "$current_ntp_enable" != "1" ]; then
                 debug_log "DEBUG" "Enabling NTP client (system.ntp.enable=1)"
                 uci set system.ntp.enable='1'
            fi

            # 2. ローカルNTPサーバー機能のオプションに応じた設定
            if [ "$ENABLE_LOCAL_NTP_SERVER" = "true" ]; then
                debug_log "DEBUG" "ENABLE_LOCAL_NTP_SERVER is true. Enabling device as a local NTP server for LAN."
                # NTPサーバー機能を有効化 (クライアントにNTPサービスを提供)
                local current_ntp_enable_server
                current_ntp_enable_server=$(uci get system.ntp.enable_server 2>/dev/null)
                if [ "$current_ntp_enable_server" != "1" ]; then
                    debug_log "DEBUG" "Enabling NTP server functionality to provide service (system.ntp.enable_server=1)"
                    uci set system.ntp.enable_server='1'
                fi
                # NTPサーバーとしてLANにバインド
                local current_ntp_interface
                current_ntp_interface=$(uci get system.ntp.interface 2>/dev/null)
                if [ "$current_ntp_interface" != "lan" ]; then
                    debug_log "DEBUG" "Binding NTP server to LAN interface (system.ntp.interface=lan)"
                    uci set system.ntp.interface='lan'
                fi
                # LuCI「DHCPから通知されたサーバを使用」: OFF (network.wan.peerntp='0')
                if uci get "$PEERNTP_SECTION_PATH" >/dev/null 2>&1; then # セクションの存在確認
                    if [ "$(uci get ${PEERNTP_UCI_PATH} 2>/dev/null)" != "0" ]; then
                        debug_log "DEBUG" "Setting ${PEERNTP_UCI_PATH}=0 to disable NTP from DHCP"
                        uci set "${PEERNTP_UCI_PATH}=0"
                        uci commit network
                    fi
                else
                    debug_log "WARN" "UCI section for peerntp not found: ${PEERNTP_SECTION_PATH}. Skipping peerntp configuration for 'true' state."
                fi
            else # ENABLE_LOCAL_NTP_SERVER is false
                debug_log "DEBUG" "ENABLE_LOCAL_NTP_SERVER is false."
                # LuCI「NTPサーバーを有効化」: OFF (system.ntp.enable_server='0')
                if [ "$(uci get system.ntp.enable_server 2>/dev/null)" != "0" ]; then
                    debug_log "DEBUG" "Setting system.ntp.enable_server=0"
                    uci set system.ntp.enable_server='0'
                fi
                # LuCI「DHCPから通知されたサーバを使用」: ON (network.wan.peerntp='1')
                if uci get "$PEERNTP_SECTION_PATH" >/dev/null 2>&1; then # セクションの存在確認
                    if [ "$(uci get ${PEERNTP_UCI_PATH} 2>/dev/null)" != "1" ]; then
                        debug_log "DEBUG" "Setting ${PEERNTP_UCI_PATH}=1 to enable NTP from DHCP"
                        uci set "${PEERNTP_UCI_PATH}=1"
                        uci commit network
                    fi
                else
                    debug_log "WARN" "UCI section for peerntp not found: ${PEERNTP_SECTION_PATH}. Skipping peerntp configuration for 'false' state."
                fi
            fi
        else
            debug_log "WARN" "system.ntp UCI section not found. Cannot configure NTP settings."
        fi
    else
        debug_log "DEBUG" "NTP pool for language '$language' not found or language.ch missing. Skipping NTP server change."
    fi

    # システムの説明と備考を設定
    local current_description current_notes
    current_description="$(uci get system.@system[0].description 2>/dev/null)"
    if [ -z "$current_description" ]; then
        uci set system.@system[0].description="Configured automatically by aios"
    fi
    current_notes="$(uci get system.@system[0].notes 2>/dev/null)"
    if [ -z "$current_notes" ]; then
        # 修正点: date コマンドのフォーマット指定を削除し、デフォルト出力を使用
        uci set system.@system[0].notes="Configured at $(date)"
    fi
    
    uci commit system
    # system と network の設定変更を反映させるため、関連サービスを再起動
    /etc/init.d/system reload
    /etc/init.d/sysntpd restart 
}

# =========================================================
# メインエントリーポイント関数
# 国・地域設定の全体的なフローを制御する
# 引数: $1 - オプション: 設定したい国の短縮コード (例: JP, US)
# 戻り値: 0 (成功), 1 (失敗またはユーザーによるキャンセル)
# =========================================================
country_main() {
    local country_arg="$1"
    local setup_result=1 # デフォルトは失敗

    debug_log "DEBUG" "Entering country_main() with argument: '$country_arg'"

    # ステップ1: 引数による設定試行
    debug_log "DEBUG" "Step 1: Attempting setup from argument"
    if try_setup_from_argument "$country_arg"; then
        setup_result=0
        debug_log "DEBUG" "Setup successful via argument"
    else
        debug_log "DEBUG" "Setup via argument failed or skipped"

        # ステップ2: 自動検出による設定試行
        debug_log "DEBUG" "Step 2: Attempting setup from auto-detection"
        if try_setup_from_auto_detection; then
            setup_result=0
            debug_log "DEBUG" "Setup successful via auto-detection"
        else
            debug_log "DEBUG" "Auto-detection failed or was declined"

            # ステップ3: 手動選択による設定試行
            debug_log "DEBUG" "Step 3: Attempting setup from manual selection"
            if try_setup_from_manual_selection; then
                setup_result=0
                debug_log "DEBUG" "Setup successful via manual selection"
            else
                debug_log "DEBUG" "Manual selection failed or was cancelled"
                # すべて失敗
                setup_result=1
            fi
        fi
    fi

    if [ "$setup_result" -eq 0 ]; then
        debug_log "DEBUG" "Country and timezone selection completed. Applying to system configuration."
        if command -v setup_location >/dev/null 2>&1; then
            setup_location
        else
            debug_log "DEBUG" "setup_location function not found. Cannot apply system configuration."
        fi
        # --- setup_location 呼び出しここまで ---
        debug_log "DEBUG" "country_main() completed successfully after attempting system setup."
        return 0
    else
        debug_log "DEBUG" "country_main() completed with failure. System setup not attempted."
        return 1
    fi
}
