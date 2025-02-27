#!/bin/sh

SCRIPT_VERSION="2025.02.27-01-17"

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

echo -e "\033[7;40mUpdated to version $SCRIPT_VERSION package-common.sh \033[0m"

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
BUILD_DIR="${BUILD_DIR:-$BASE_DIR/build}"
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BUILD_DIR"
DEBUG_MODE="${DEBUG_MODE:-false}"

#########################################################################
# Last Update: 2025-02-24 21:16:00 (JST) 🚀
# install_package: パッケージのインストール処理 (OpenWrt / Alpine Linux)
#
# 【概要】
# 指定されたパッケージをインストールし、オプションに応じて以下の処理を実行する。
# ✅ OpenWrt / Alpine の `opkg update` / `apk update` を適用（条件付き）
# ✅ 言語パッケージ・設定ファイル (`local-package.db`) の適用
#
# 【フロー】
# 1️⃣ デバイスにパッケージがインストール済みか確認
# 2️⃣ `update.ch` のキャッシュをチェックし、`opkg update / apk update` を実行
# 4️⃣ インストール確認（yn オプションが指定された場合）
# 5️⃣ パッケージのインストールを実行
# 6️⃣ 言語パッケージの適用（nolang オプションでスキップ可能）
# 7️⃣ `local-package.db` の適用（notpack オプションでスキップ可能）
# 8️⃣ 設定の有効化（デフォルト enabled、disabled オプションで無効化）
#
# 【グローバルオプション】
# DEV_NULL : 標準出力の制御
# DEBUG    : デバッグモード（詳細ログ出力）
#
# 【オプション】
# - yn         : インストール前に確認（デフォルト: 確認なし）
# - nolang     : 言語パッケージの適用をスキップ（デフォルト: 適用する）
# - force      : 強制インストール（デフォルト: 適用しない）
# - notpack    : `local-package.db` での設定適用をスキップ（デフォルト: 適用する）
# - disabled   : 設定を disabled にする（デフォルト: enabled）
# - hidden     : 既にインストール済みの場合のメッセージを非表示
# - test       : インストール済みのパッケージでも処理を実行
# - update     : `opkg update` / `apk update` を強制実行（`update.ch` のキャッシュ無視）
#
# 【仕様】
# - `update.ch` を書き出し、`opkg update / apk update` の実行管理
# - `downloader_ch` から `opkg` または `apk` を判定し、適切なパッケージ管理ツールを使用
# - `local-package.db` を オプションにより適用
# - `local-package.db` の設定がある場合、`uci set` を実行し適用（notpack オプションでスキップ可能）
# - 言語パッケージの適用対象は `luci-app-*`（nolang オプションでスキップ可能）
# - 設定の有効化はデフォルト enabled、disabled オプションで無効化可能
# - `update` は明示的に `install_package update` で実行（インストール時には自動実行しない）
#
# 【使用例】
# - install_package ttyd                  → `ttyd` をインストール（確認なし、local-package.db 適用、言語パック適用）
# - install_package ttyd yn               → `ttyd` をインストール（確認あり）
# - install_package ttyd nolang           → `ttyd` をインストール（言語パック適用なし）
# - install_package ttyd notpack          → `ttyd` をインストール（local-package.db の適用なし）
# - install_package ttyd disabled         → `ttyd` をインストール（設定を disabled にする）
# - install_package ttyd yn nolang disabled hidden
#   → `ttyd` をインストール（確認あり、言語パック適用なし、設定を disabled にし、
#      既にインストール済みの場合のメッセージを非表示）
# - install_package ttyd test             → `ttyd` をインストール（インストール済みでも強制インストール）
# - install_package ttyd update           → `ttyd` をインストール（`opkg update / apk update` を強制実行）
#
# 【messages.db の記述例】
# [ttyd]
# opkg update
# uci commit ttyd
# initd/ttyd/restart
# [ttyd] opkg update; uci commit ttyd; initd/ttyd/restart
#########################################################################
# **スピナー開始関数**
start_spinner() {
    local message="$1"
    SPINNER_MESSAGE="$message"  # 停止時のメッセージ保持
    spinner_chars='| / - \\'
    i=0

    echo -en "\e[?25l"

    while true; do
        # POSIX 準拠の方法でインデックスを計算し、1文字抽出
        local index=$(( i % 4 ))
        local spinner_char=$(expr substr "$spinner_chars" $(( index + 1 )) 1)
        printf "\r📡 %s %s" "$(color yellow "$SPINNER_MESSAGE")" "$spinner_char"
        if command -v usleep >/dev/null 2>&1; then
            usleep 200000
        else
            sleep 1
        fi
        i=$(( i + 1 ))
    done &
    SPINNER_PID=$!
}

# **スピナー停止関数**
stop_spinner() {
    local message="$1"

    if [ -n "$SPINNER_PID" ] && ps | grep -q " $SPINNER_PID "; then
        kill "$SPINNER_PID" >/dev/null 2>&1
        printf "\r\033[K"  # 行をクリア
        echo "$(color green "$message")"
    else
        printf "\r\033[K"
        echo "$(color red "$message")"
    fi
    unset SPINNER_PID

    echo -en "\e[?25h"
}

# パッケージリストの更新
update_package_list() {
    local update_cache="${CACHE_DIR}/update.ch"
    local package_cache="${CACHE_DIR}/package_list.ch"
    local current_time
    current_time=$(date '+%s')  # 現在のUNIXタイムスタンプ取得
    local cache_time=0
    local max_age=$((24 * 60 * 60))  # 24時間 (86400秒)

    # キャッシュディレクトリの作成
    mkdir -p "$CACHE_DIR"

    # キャッシュが存在する場合、最終更新時刻を取得
    if [ -f "$update_cache" ]; then
        cache_time=$(date -r "$update_cache" '+%s' 2>/dev/null || echo 0)
    fi

    # キャッシュが最新なら `opkg update` をスキップ
    if [ $((current_time - cache_time)) -lt $max_age ]; then
        debug_log "DEBUG" "パッケージリストは24時間以内に更新されています。スキップします。"
        return 0
    fi

    # スピナー開始
    start_spinner "$(color yellow "$(get_message "MSG_RUNNING_UPDATE")")"

    # **パッケージリストの取得 & 保存**
    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        opkg update > "${LOG_DIR}/opkg_update.log" 2>&1 || {
            stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            debug_log "ERROR" "$(get_message "MSG_ERROR_UPDATE_FAILED")"
            return 1
        }
        opkg list > "$package_cache" 2>/dev/null
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        apk update > "${LOG_DIR}/apk_update.log" 2>&1 || {
            stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            debug_log "ERROR" "$(get_message "MSG_ERROR_UPDATE_FAILED")"
            return 1
        }
        apk search > "$package_cache" 2>/dev/null
    fi

    # スピナー停止 (成功メッセージを表示)
    stop_spinner "$(color green "$(get_message "MSG_UPDATE_SUCCESS")")"

    # キャッシュのタイムスタンプを更新
    touch "$update_cache" || {
        debug_log "ERROR" "$(color red "$(get_message "MSG_ERROR_WRITE_CACHE")")"
        return 1
    }

    return 0
}

# パッケージ名（引数として渡せるように変更）
apply_local_package_db() {
    package_name=$1  # ここでパッケージ名を引数として受け取る

    debug_log "DEBUG" "Starting to apply local-package.db for package: $package_name" "$0" "$SCRIPT_VERSION"

    # local-package.dbから指定されたセクションを抽出
    extract_commands() {
        # [PACKAGE] をエスケープして検索、コメント行は無視
        awk -v pkg="$package_name" '
            $0 ~ "^\\[" pkg "\\]" {flag=1; next}  # [****]セクションに到達
            $0 ~ "^\\[" {flag=0}                  # 次のセクションが始まったらflagをリセット
            flag && $0 !~ "^#" {print}             # コメント行（#）を除外
        ' "${BASE_DIR}/local-package.db"
    }

    # コマンドを実行するために抽出したコマンドを格納
    local cmds
    cmds=$(extract_commands)  # コマンドを取得

    # コマンドが見つからない場合、エラーメッセージを表示して終了
    if [ -z "$cmds" ]; then
        echo "No commands found for package: $package_name"
        return 1
    fi

    echo "Executing commands for $package_name..."
    # コマンドを一時ファイルに書き出し
    echo "$cmds" > ${CACHE_DIR}/commands.ch

    # ここで一括でコマンドを実行
    # chファイルに書き出したコマンドをそのまま実行する
    . ${CACHE_DIR}/commands.ch  # chファイル内のコマンドをそのまま実行

    # 最後に設定を確認（デバッグ用）
    debug_log "DEBUG" "Displaying current configuration for $package_name: $(uci show "$package_name")"

    echo "All commands executed successfully."
}

# **YN 確認を行う関数**
OK_confirm_installation() {
    local package="$1"
    local package_with_lang="$package"  # デフォルトではそのままのパッケージ名

    # 言語パッケージがある場合は言語コードを付け加える
    if echo "$package" | grep -q "luci-i18n-"; then
        if [ -f "${CACHE_DIR}/luci.ch" ]; then
            local lang_code
            lang_code=$(head -n 1 "${CACHE_DIR}/luci.ch" | awk '{print $1}')
            package_with_lang="${package}-${lang_code}"  # 言語コードを追加
        else
            package_with_lang="${package}-en"  # 言語コードがなければ、英語パッケージを使用
        fi
    fi

    # メッセージにパッケージ名を差し込む
    local msg=$(get_message "MSG_CONFIRM_INSTALL")
    msg="${msg//\{pkg\}/$package_with_lang}"  # パッケージ名を適切に置き換える
    echo "$msg"
    printf "%s " "$(get_message "MSG_CONFIRM_ONLY_YN")"

    # ユーザー入力待機
    read -r yn || return 1
    case "$yn" in
        [Yy]*) return 0 ;;  # 継続
        [Nn]*) return 1 ;;  # キャンセル
        *) echo "$(color red "Invalid input. Please enter Y or N.")" ;;  # 無効な入力
    esac
}

confirm_installation() {
    local package="$1"

    debug_log "DEBUG" "Confirming installation for package: $package"

    # 言語コードが正しくついているかチェック
    if echo "$package" | grep -q "^luci-i18n-"; then
        if ! echo "$package" | grep -qE "-[a-z]{2,3}$"; then
            debug_log "ERROR" "Invalid package name detected: $package (missing language code)"
            return 1  # 言語コードなしならエラー
        fi
    fi

    while true; do
        local msg=$(get_message "MSG_CONFIRM_INSTALL")
        msg="${msg//\{pkg\}/$package}"
        echo "$msg"
        printf "%s " "$(get_message "MSG_CONFIRM_ONLY_YN")"
        read -r yn || return 1
        case "$yn" in
            [Yy]*) return 0 ;;  # 継続
            [Nn]*) return 1 ;;  # キャンセル
            *) echo "$(color red "Invalid input. Please enter Y or N.")" ;;
        esac
    done
}

# **インストール前確認 (デバイス内パッケージ確認 + リポジトリ確認)**
check_package_pre_install() {
    local package_name="$1"
    local package_cache="${CACHE_DIR}/package_list.ch"
    local lang_code=""
    local base_package="$package_name"  # デフォルトでは変更なし

    # 言語パッケージの特別処理
    if echo "$package_name" | grep -q "^luci-i18n-"; then
        # キャッシュから言語コードを取得
        if [ -f "${CACHE_DIR}/luci.ch" ]; then
            lang_code=$(head -n 1 "${CACHE_DIR}/luci.ch" | awk '{print $1}')
        else
            lang_code="en"  # デフォルトで英語
        fi

        # 言語付きのパッケージ名を作成
        package_name="${package_name}-${lang_code}"

        # **フォールバック処理 (`ja` → `en`)**
        if ! grep -q "^$package_name " "$package_cache"; then
            debug_log "WARN" "Package $package_name not found. Falling back to English (en)."
            package_name="${package_name%-*}-en"
        fi

        # **`en` も無かったらエラーで終了**
        if ! grep -q "^$package_name " "$package_cache"; then
            debug_log "ERROR" "Package $package_name not found. No fallback available."
            return 1
        fi
    fi

    # **デバイス内パッケージ確認**
    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        if opkg list-installed | grep -qE "^$package_name "; then
            debug_log "DEBUG" "Package $package_name is already installed on the device."
            return 0  # ここで終了！ → インストール確認を出さない！
        fi
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        if apk info | grep -q "^$package_name$"; then
            debug_log "DEBUG" "Package $package_name is already installed on the device."
            return 0  # ここで終了！ → インストール確認を出さない！
        fi
    fi

    # **リポジトリ内パッケージ確認**
    debug_log "DEBUG" "Checking repository for package: $package_name"

    # キャッシュファイルがない場合はエラー
    if [ ! -f "$package_cache" ]; then
        debug_log "ERROR" "Package cache not found! Run update_package_list() first."
        return 1
    fi

    if grep -qE "^$package_name " "$package_cache"; then
        debug_log "DEBUG" "Package $package_name found in repository."
        return 0  # パッケージが存在するのでOK
    fi

    debug_log "ERROR" "Package $package_name not found in repository."
    return 1  # パッケージが見つからなかった
}

install_package_func() {
    local package_name="$1"
    local force_install="$2"
    local base=""
    local cache_lang=""
    local lang_pkg=""

    debug_log "DEBUG" "Starting installation process for: $package_name"

    # **言語パッケージの場合は適切な言語コードを取得**
    if echo "$package_name" | grep -q "^luci-i18n-"; then
        base="${package_name%-*}"  # "luci-i18n-base" の "base" を取得
        debug_log "DEBUG" "Detected language package base: $base"

        if [ -f "${CACHE_DIR}/luci.ch" ]; then
            cache_lang=$(head -n 1 "${CACHE_DIR}/luci.ch" | awk '{print $1}')
        else
            cache_lang="en"
        fi

        debug_log "DEBUG" "Language detected from cache: $cache_lang"

        package_name="${base}-${cache_lang}"  # 言語コードを付け加える
        debug_log "DEBUG" "Final package name set to: $package_name"

        # **フォールバックチェック**
        if ! opkg list-installed | grep -q "^$package_name "; then
            debug_log "WARN" "Package $package_name not found, falling back to English"
            package_name="${base}-en"
        fi

        if ! opkg list-installed | grep -q "^$package_name "; then
            debug_log "ERROR" "Neither $package_name nor its English fallback exists. Aborting."
            return 1
        fi
    fi

    # **スピナー開始**
    start_spinner "$(color yellow "$(get_message "MSG_INSTALLING_PACKAGE" | sed "s/{pkg}/$package_name/")")"

    # **パッケージのインストール**
    if [ "$force_install" = "yes" ]; then
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install --force-reinstall "$package_name" > /dev/null 2>&1 || {
                stop_spinner "$(color red "❌ Failed to install package $package_name")"
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add --force-reinstall "$package_name" > /dev/null 2>&1 || {
                stop_spinner "$(color red "❌ Failed to install package $package_name")"
                return 1
            }
        fi
    else
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install "$package_name" > /dev/null 2>&1 || {
                stop_spinner "$(color red "❌ Failed to install package $package_name")"
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add "$package_name" > /dev/null 2>&1 || {
                stop_spinner "$(color red "❌ Failed to install package $package_name")"
                return 1
            }
        fi
    fi

    # **スピナー停止**
    stop_spinner "$(color green "$(get_message "MSG_INSTALL_SUCCESS" | sed "s/{pkg}/$package_name/")")"
}


# **言語パッケージのインストール**
install_language_package() {
    local package_name="$1"
    local base="luci-i18n-${package_name#luci-app-}"
    local cache_lang=""
    local lang_pkg=""

    # 言語キャッシュの取得
    if [ -f "${CACHE_DIR}/luci.ch" ]; then
        cache_lang=$(head -n 1 "${CACHE_DIR}/luci.ch" | awk '{print $1}')
    else
        cache_lang="en"
    fi

    # 言語パッケージの検索順リスト
    local package_search_list="${base}-${cache_lang} ${base}-en $base"

    debug_log "DEBUG" "Checking for package variations in repository: $package_search_list"

    local package_found="no"
    for pkg in $package_search_list; do
        # **インストール済みチェック**
        if opkg list-installed | grep -qE "^$pkg "; then
            debug_log "DEBUG" "Package $pkg is already installed. Skipping installation."
            return 0
        fi

        # **リポジトリ検索**
        if grep -qE "^$pkg " "${CACHE_DIR}/package_list.ch"; then
            lang_pkg="$pkg"
            package_found="yes"
            break
        fi
    done

    if [ "$package_found" = "no" ]; then
        debug_log "ERROR" "No suitable language package found for $package_name."
        return 1
    fi

    debug_log "DEBUG" "Found $lang_pkg in repository"
    confirm_installation "$lang_pkg" || return 1
    install_package_func "$lang_pkg" "$force_install"
}

# **インストール関数**
install_package() {
    # 変数初期化
    local confirm_install="no"
    local skip_lang_pack="no"
    local force_install="no"
    local skip_package_db="no"
    local set_disabled="no"
    local hidden="no"
    local test_mode="no"
    local update_mode="no"
    local unforce="no"
    local package_name=""

    # オプション解析
    while [ $# -gt 0 ]; do
        case "$1" in
            yn) confirm_install="yes" ;;
            nolang) skip_lang_pack="yes" ;;
            force) force_install="yes" ;;
            notpack) skip_package_db="yes" ;;
            disabled) set_disabled="yes" ;;
            hidden) hidden="yes" ;;
            test) test_mode="yes" ;;
            update)
                update_mode="yes"
                shift
                if [ $# -gt 0 ]; then
                    package_to_update="$1"
                    shift
                fi
                continue
                ;;
            unforce) unforce="yes" ;;
            -*) echo "Unknown option: $1"; return 1 ;;
            *)
                if [ -z "$package_name" ]; then
                    package_name="$1"
                else
                    debug_log "DEBUG" "$(color yellow "$(get_message "MSG_UNKNOWN_OPTION" | sed "s/{option}/$1/")")"
                fi
                ;;
        esac
        shift
    done

    # update オプション処理
    if [ "$update_mode" = "yes" ]; then
        update_package_list
        return 0
    fi

    # パッケージマネージャー確認
    if [ -f "${CACHE_DIR}/downloader_ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/downloader_ch")
    else
        debug_log "ERROR" "$(color red "$(get_message "MSG_ERROR_NO_PACKAGE_MANAGER")")"
        return 1
    fi

    # **パッケージリスト更新**
    update_package_list || return 1

    # **インストール前確認 (デバイス内パッケージ確認 + リポジトリ確認)**
    if ! check_package_pre_install "$package_name"; then
        debug_log "ERROR" "$(color red "❌ Package $package_name is either already installed or not found in repository.")"
        return 1
    fi

    # **YN確認 (オプションで有効時のみ)**
    if [ "$confirm_install" = "yes" ]; then
        confirm_installation "$package_name" || return 1
    fi

    # **通常パッケージのインストール**
    install_package_func "$package_name" "$force_install"

    # **ローカルパッケージDBの適用 (インストール成功後に実行)**
    if [ "$skip_package_db" != "yes" ]; then
        apply_local_package_db "$package_name"
    fi

    # **言語パッケージのインストール**
    if [ "$skip_lang_pack" != "yes" ]; then
        install_language_package "$package_name"
    fi
}

#########################################################################
# Last Update: 2025-02-22 15:35:00 (JST) 🚀
# install_build: パッケージのビルド処理 (OpenWrt / Alpine Linux)
#
# 【概要】
# 指定されたパッケージをビルドし、オプションに応じて以下の処理を実行する。
# 1回の動作で１つのビルドのみパッケージを作りインストール作業
# DEBUG に応じて出力制御（要所にセット）
#
# 【フロー】
# 2️⃣ デバイスにパッケージがインストール済みか確認
# 4️⃣ インストール確認（yn オプションが指定された場合）
# 4️⃣ ビルド用汎用パッケージ（例：make, gcc）をインストール ※install_package()利用
# 4️⃣ ビルド作業
# 7️⃣ custom-package.db の適用（ビルド用設定：DBの記述に従う）
# 5️⃣ インストールの実行（install_package()利用）
# 7️⃣ package.db の適用（ビルド後の設定適用がある場合：DBの記述に従う）
#
# 【ビルド用汎用パッケージ】
# install_package jq
# install_package = 以下
# {make gcc git libtool-bin automake pkg-config zlib-dev libncurses-dev curl libxml2 libxml2-dev autoconf automake bison flex perl patch wget wget-ssl tar unzip) hidden
#
# 【グローバルオプション】
# DEBUG : 要所にセット
#
# 【オプション】※順不同で適用可
# - yn         : インストール前に確認する（デフォルト: 確認なし）
# - hidden     : 既にインストール済みの場合、"パッケージ xxx はすでにインストールされています" のメッセージを非表示にする
#
# 【仕様】
# - ${CACHE_DIR}/downloader.ch から取得、フォーマット：opkg もしくは apk
# - ${CACHE_DIR}/openwrt.ch　から取得、フォーマット例：24.10.0 や　23.05.4　など
# - ${CACHE_DIR}/architecture.ch　から取得、フォーマット例：armv7l　など
# - custom-package.db の設定がある場合、該当パッケージの記述 を実行し適用
# - messages.db を参照し、すべてのメッセージを取得（JP/US 対応）
#
# 【使用例】
# - install_build uconv                  → インストール（確認なし）
# - install_build uconv yn               → インストール（確認あり）
# - install_build uconv yn hidden        → インストール（確認あり、既にインストール済みの場合のメッセージは非表示）
#
# 【messages.dbの記述例】
# [uconv]　※行、列問わず記述可
#########################################################################
setup_swap() {
    local ZRAM_SIZE_MB
    local RAM_TOTAL_MB
    RAM_TOTAL_MB=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)

    # **スワップサイズを RAM に応じて自動調整**
    if [ "$RAM_TOTAL_MB" -lt 512 ]; then
        ZRAM_SIZE_MB=512
    elif [ "$RAM_TOTAL_MB" -lt 1024 ]; then
        ZRAM_SIZE_MB=256
    else
        ZRAM_SIZE_MB=128
    fi

    debug_log "INFO" "RAM: ${RAM_TOTAL_MB}MB, Setting zram size to ${ZRAM_SIZE_MB}MB"

    # **空き容量を確認**
    local STORAGE_FREE_MB
    STORAGE_FREE_MB=$(df -m /overlay | awk 'NR==2 {print $4}')  # MB単位の空き容量

    if [ -z "$STORAGE_FREE_MB" ] || [ "$STORAGE_FREE_MB" -lt 50 ]; then
        debug_log "ERROR" "Insufficient storage for swap (${STORAGE_FREE_MB}MB free). Skipping swap setup."
        return 1  # **ストレージ不足なら即終了**
    fi

    # **zswap (zram-swap) のインストール**
    install_package zram-swap hidden

    # **zswap の設定適用**
    if uci get system.@zram[0] &>/dev/null; then
        debug_log "INFO" "Applying zswap settings from local-package.db..."
        uci set system.@zram[0].enabled='1'
        uci set system.@zram[0].size="${ZRAM_SIZE_MB}"
        uci set system.@zram[0].comp_algorithm='zstd'
        uci commit system
    else
        debug_log "ERROR" "zswap configuration not found in UCI. Skipping swap setup."
        return 1  # **設定が見つからない場合も即終了**
    fi

    # **zram-swap の有効化**
    debug_log "INFO" "Enabling zram-swap..."
    /etc/init.d/zram restart

    sleep 2  # **スワップが確実に有効化されるまで待機**

    # **スワップが有効になったか確認**
    if [ -f /proc/swaps ] && grep -q 'zram' /proc/swaps; then
        debug_log "INFO" "zram-swap is successfully enabled."
    else
        debug_log "ERROR" "Failed to enable zram-swap."
        return 1  # **有効化に失敗したら即終了**
    fi

    # **現在のメモリとスワップ状況を表示**
    debug_log "INFO" "Memory and Swap Status:"
    free -m
    cat /proc/swaps
}

# 【DBファイルから値を取得する関数】
get_ini_value() {
    local section="$1"
    local key="$2"
    awk -F'=' -v s="[$section]" -v k="$key" '
        $0 ~ s {flag=1; next} /^\[/{flag=0}
        flag && $1==k {print $2; exit}
    ' "$DB_FILE"
}

# 【セクションから値を取得（デフォルト値を含める）】
get_value_with_fallback() {
    local section="$1"
    local key="$2"
    local value
    value=$(get_ini_value "$section" "$key")
    if [ -z "$value" ]; then
        value=$(get_ini_value "default" "$key")
    fi
    echo "$value"
}

install_build() {
    local confirm_install="no"
    local hidden="no"
    local package_name=""

    # **オプションの処理**
    for arg in "$@"; do
        case "$arg" in
            yn) confirm_install="yes" ;;
            hidden) hidden="yes" ;;
            *)
                if [ -z "$package_name" ]; then
                    package_name="$arg"
                else
                    debug_log "DEBUG" "Unknown option: $arg"
                fi
                ;;
        esac
    done

    # **パッケージ名が指定されているか確認**
    if [ -z "$package_name" ]; then
        debug_log "ERROR" "$(get_message "MSG_ERROR_NO_PACKAGE_NAME")"
        return 1
    fi

    # **スワップの動作チェック**
    setup_swap
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "$(get_message 'MSG_ERR_INSUFFICIENT_SWAP')"
        return 1
    fi

    # **インストールの確認 (YNオプションが有効な場合のみ)**
    if [ "$confirm_install" = "yes" ]; then
        while true; do
            local msg=$(get_message "MSG_CONFIRM_INSTALL" | sed "s/{pkg}/$package_name/")
            echo "$msg"

            echo -n "$(get_message "MSG_CONFIRM_ONLY_YN")"
            read -r yn
            case "$yn" in
                [Yy]*) break ;;  # Yes → インストール続行
                [Nn]*) return 1 ;; # No → キャンセル
                *) echo "Invalid input. Please enter Y or N." ;;
            esac
        done
    fi

    # **OpenWrt バージョン取得**
    local openwrt_version=""
    if [ -f "${CACHE_DIR}/openwrt.ch" ]; then
        openwrt_version=$(cat "${CACHE_DIR}/openwrt.ch")
    fi
    debug_log "DEBUG" "Using OpenWrt version: $openwrt_version"

    # **ビルド環境の準備**
    install_package jq
    local build_tools="make gcc git libtool-bin automake pkg-config zlib-dev libncurses-dev curl libxml2 libxml2-dev autoconf automake bison flex perl patch wget wget-ssl tar unzip"
                      
    for tool in $build_tools; do
        install_package "$tool" hidden
    done

    # **`custom-package.db` からビルドコマンドを取得**
    local build_command=$(jq -r --arg pkg "$package_name" --arg ver "$openwrt_version" '
        .[$pkg].build.commands[$ver] // 
        .[$pkg].build.commands.default // empty' "$CACHE_DIR/custom-package.db" 2>/dev/null)

    if [ -z "$build_command" ]; then
        debug_log "ERROR" "$(get_message "MSG_ERROR_BUILD_COMMAND_NOT_FOUND" | sed "s/{pkg}/$package_name/" | sed "s/{ver}/$openwrt_version/")"
        return 1
    fi

    debug_log "DEBUG" "Executing build command: $build_command"

    # **ビルド開始メッセージ**
    echo "$(get_message "MSG_BUILD_START" | sed "s/{pkg}/$package_name/")"

    # **ビルド実行（スピナー開始）**
    start_spinner "$(get_message 'MSG_BUILD_RUNNING')"
    local start_time=$(date +%s)
    if ! eval "$build_command"; then
        stop_spinner
        echo "$(get_message "MSG_BUILD_FAIL" | sed "s/{pkg}/$package_name/")"
        debug_log "ERROR" "$(get_message "MSG_ERROR_BUILD_FAILED" | sed "s/{pkg}/$package_name/")"
        return 1
    fi
    local end_time=$(date +%s)
    local build_time=$((end_time - start_time))
    stop_spinner  # スピナー停止

    echo "$(get_message "MSG_BUILD_TIME" | sed "s/{pkg}/$package_name/" | sed "s/{time}/$build_time/")"
    debug_log "DEBUG" "Build time for $package_name: $build_time seconds"

    # **ビルド完了後のメッセージ**
    echo "$(get_message "MSG_BUILD_SUCCESS" | sed "s/{pkg}/$package_name/")"
    debug_log "DEBUG" "Successfully built and installed package: $package_name"
}

