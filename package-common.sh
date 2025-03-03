#!/bin/sh

SCRIPT_VERSION="2025.03.01-01-04"

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
BASE_WGET="${BASE_WGET:-wget --no-check-certificate -q -O}"
# BASE_WGET="${BASE_WGET:-wget -O}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
BUILD_DIR="${BUILD_DIR:-$BASE_DIR/build}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BUILD_DIR" "$FEED_DIR"
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
# - `downloader.ch` から `opkg` または `apk` を判定し、適切なパッケージ管理ツールを使用
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

local_package_db() {
    package_name=$1  # どんなパッケージ名でも受け取れる

    debug_log "DEBUG" "Starting to apply local-package.db for package: $package_name"

    # `local-package.db` から `$package_name` に該当するセクションを抽出
    extract_commands() {
        awk -v pkg="$package_name" '
            $0 ~ "^\\[" pkg "\\]" {flag=1; next}
            $0 ~ "^\\[" {flag=0}
            flag && $0 !~ "^#" {print}
        ' "${BASE_DIR}/local-package.db"
    }

    # コマンドを取得
    local cmds
    cmds=$(extract_commands)

    if [ -z "$cmds" ]; then
        debug_log "DEBUG" "No commands found for package: $package_name"
        return 1
    fi

    # **変数の置換**
    echo "$cmds" > "${CACHE_DIR}/commands.ch"

    # **環境変数 `CUSTOM_*` を自動検出して置換**
    CUSTOM_VARS=$(env | grep "^CUSTOM_" | awk -F= '{print $1}')
    for var_name in $CUSTOM_VARS; do
        eval var_value=\$$var_name
        if [ -n "$var_value" ]; then
            sed -i "s|\\\${$var_name}|$var_value|g" "${CACHE_DIR}/commands.ch"
            debug_log "DEBUG" "Substituted: $var_name -> $var_value"
        else
            sed -i "s|.*\\\${$var_name}.*|# UNDEFINED: \0|g" "${CACHE_DIR}/commands.ch"
            debug_log "DEBUG" "Undefined variable: $var_name"
        fi
    done

    # **設定を適用**
    . "${CACHE_DIR}/commands.ch"
}

confirm_installation() {
    local package="$1"

    debug_log "DEBUG" "Confirming installation for package: $package"

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

package_pre_install() {
    local package_name="$1"
    local package_cache="${CACHE_DIR}/package_list.ch"

    debug_log "DEBUG" "Checking package: $package_name"
    
    # デバイス内パッケージ確認
    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        output=$(opkg list-installed "$package_name" 2>&1)
        if [ -n "$output" ]; then  # 出力があった場合
            debug_log "DEBUG" "Package $package_name is already installed on the device."
            return 1  # 既にインストールされている場合は終了
        fi
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        output=$(apk info "$package_name" 2>&1)
        if [ -n "$output" ]; then  # 出力があった場合
            debug_log "DEBUG" "Package $package_name is already installed on the device."
            return 1  # 既にインストールされている場合は終了
        fi
    fi
  
# リポジトリ内パッケージ確認
debug_log "DEBUG" "Checking repository for package: $package_name"

if [ ! -f "$package_cache" ]; then
    debug_log "ERROR" "Package cache not found! Run update_package_list() first."
    return 1
fi

# パッケージがキャッシュ内に存在するか確認
if grep -q "^$package_name " "$package_cache"; then
    debug_log "DEBUG" "Package $package_name found in repository."
    return 0  # パッケージが存在するのでOK
fi

# キャッシュに存在しない場合、FEED_DIR内を探してみる
if [ -f "$FEED_DIR/$package_name" ]; then
    debug_log "DEBUG" "Package $package_name found in FEED_DIR: $FEED_DIR"
    return 0  # FEED_DIR内にパッケージが見つかったのでOK
fi

debug_log "DEBUG" "Package $package_name not found in repository or FEED_DIR."
return 1  # パッケージが見つからなかった
}

install_normal_package() {
    local package_name="$1"
    local force_install="$2"

    debug_log "DEBUG" "Starting installation process for: $package_name"

    start_spinner "$(color yellow "$package_name $(get_message "MSG_INSTALLING_PACKAGE")")"
    #start_spinner "$(color yellow "$(get_message "MSG_INSTALLING_PACKAGE" | sed "s/{pkg}/$package_name/")")"

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

    stop_spinner "$(color green "$package_name $(get_message "MSG_INSTALL_SUCCESS")")"
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
    if [ -f "${CACHE_DIR}/downloader.ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/downloader.ch")
    else
        debug_log "ERROR" "$(color red "$(get_message "MSG_ERROR_NO_PACKAGE_MANAGER")")"
        return 1
    fi

    # **パッケージリスト更新**
    update_package_list || return 1

    # 言語コードの取得
    if [ -f "${CACHE_DIR}/luci.ch" ]; then
        lang_code=$(head -n 1 "${CACHE_DIR}/luci.ch" | awk '{print $1}')

        # luci.ch で指定されている言語コードが "xx" なら "en" に変更
        if [ "$lang_code" == "xx" ]; then
            lang_code="en"
        fi
    else
        lang_code="en"  # デフォルトで英語
    fi

    # 言語パッケージか通常パッケージかを判別
    if [[ "$package_name" == luci-i18n-* ]]; then
        # 言語パッケージの場合、package_name に言語コードを追加
        package_name="${package_name}-${lang_code}"
    fi

    package_pre_install "$package_name" || return 1
    
    # **YN確認 (オプションで有効時のみ)**
    if [ "$confirm_install" = "yes" ]; then
        confirm_installation "$package_name" || return 1
    fi
    
    install_normal_package "$package_name" "$force_install" || return 1

    # **ローカルパッケージDBの適用 (インストール成功後に実行)**
    if [ "$skip_package_db" != "yes" ]; then
        local_package_db "$package_name"
    fi

# サービスが存在し、かつリスタートが必要なサービスを判定
if [ -x "/etc/init.d/$package_name" ]; then
    # Luci関連のサービスの場合
    if [[ "$package_name" =~ luci- ]]; then
        # Luci関連のパッケージの場合はrpcdを再起動
        /etc/init.d/rpcd restart
        debug_log "DEBUG" "$package_name is a Luci package, rpcd has been restarted."
    else
        # その他のサービスは通常の再起動・有効化
        /etc/init.d/"$package_name" restart
        /etc/init.d/"$package_name" enable
        debug_log "DEBUG" "$package_name has been restarted and enabled."
    fi
else
    debug_log "DEBUG" "$package_name is not a service or the service script is not found."
fi
}
