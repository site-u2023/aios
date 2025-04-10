#!/bin/sh

SCRIPT_VERSION="2025.03.14-02-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-14
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
# ✅ Use $(command) instead of backticks `command`
# ✅ Use $(( )) for arithmetic instead of let
# ✅ Define functions as func_name() {} (no function keyword)
# ✅ No associative arrays (declare -A is NOT supported)
# ✅ No here-strings (<<< is NOT supported)
# ✅ No -v flag in test or [[
# ✅ Avoid bash-specific string operations like ${var:0:3}
# ✅ Avoid arrays entirely when possible (even indexed arrays can be problematic)
# ✅ Use printf followed by read instead of read -p
# ✅ Use printf instead of echo -e for portable formatting
# ✅ Avoid process substitution <() and >()
# ✅ Prefer case statements over complex if/elif chains
# ✅ Use command -v instead of which or type for command existence checks
# ✅ Keep scripts modular with small, focused functions
# ✅ Use simple error handling instead of complex traps
# ✅ Test scripts with ash/dash explicitly, not just bash
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
### =========================================================

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"

#########################################################################
# Last Update: 2025-03-14 06:00:00 (JST) 🚀
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
# 3️⃣ インストール確認（yn オプションが指定された場合）
# 4️⃣ パッケージのインストールを実行
# 5️⃣ 言語パッケージの適用（nolang オプションでスキップ可能）
# 6️⃣ `local-package.db` の適用（notpack オプションでスキップ可能）
# 7️⃣ 設定の有効化（デフォルト enabled、disabled オプションで無効化）
#########################################################################

# インストール後のパッケージリストを表示
check_install_list() {
    printf "\n%s\n" "$(color blue "Packages installed after flashing.")"

    # パッケージマネージャの種類を確認
    if [ -f "${CACHE_DIR}/package_manager.ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/package_manager.ch")
    fi

    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        # opkg用の処理 - 元のロジックを維持
        debug_log "DEBUG" "Using opkg package manager"
        FLASH_TIME="$(awk '
        $1 == "Installed-Time:" && ($2 < OLDEST || OLDEST=="") {
          OLDEST=$2
        }
        END {
          print OLDEST
        }
        ' /usr/lib/opkg/status)"

        awk -v FT="$FLASH_TIME" '
        $1 == "Package:" {
          PKG=$2
          USR=""
        }
        $1 == "Status:" && $3 ~ "user" {
          USR=1
        }
        $1 == "Installed-Time:" && USR && $2 != FT {
          print PKG
        }
        ' /usr/lib/opkg/status | sort
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        # apk用の処理
        debug_log "DEBUG" "Using apk package manager"
        if [ -f /etc/apk/world ]; then
            # /etc/apk/worldには明示的にインストールされたパッケージリスト
            cat /etc/apk/world | sort
        else
            # フォールバック：インストール済みパッケージを表示
            apk info | sort
        fi
    else
        debug_log "DEBUG" "Unknown package manager: $PACKAGE_MANAGER"
    fi

    return 0    
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

    # キャッシュの状態確認
    # パッケージリストが存在しないか、タイムスタンプが古い場合は更新
    local need_update="yes"
    
    if [ -f "$package_cache" ] && [ -f "$update_cache" ]; then
        cache_time=$(date -r "$update_cache" '+%s' 2>/dev/null || echo 0)
        if [ $((current_time - cache_time)) -lt $max_age ]; then
            debug_log "DEBUG" "Package list was updated within 24 hours. Skipping update."
            need_update="no"
        else
            debug_log "DEBUG" "Package list cache is outdated. Will update now."
        fi
    else
        debug_log "DEBUG" "Package list cache not found or incomplete. Will create it now."
    fi
    
    # 更新が必要ない場合は終了
    if [ "$need_update" = "no" ]; then
        return 0
    fi

    printf "  %s\n"

    # スピナー開始
    start_spinner "$(color blue "$(get_message "MSG_RUNNING_UPDATE")")"

    # PACKAGE_MANAGERの使用（既存の情報を尊重）
    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        debug_log "DEBUG" "Running opkg update and saving package list"
        opkg update > "${LOG_DIR}/opkg_update.log" 2>&1 || {
            stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            debug_log "ERROR" "Failed to update package lists with opkg"
            return 1
        }
        opkg list > "$package_cache" 2>/dev/null || {
            stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            debug_log "ERROR" "Failed to save package list with opkg"
            return 1
        }
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        debug_log "DEBUG" "Running apk update and saving package list"
        apk update > "${LOG_DIR}/apk_update.log" 2>&1 || {
            stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            debug_log "ERROR" "Failed to update package lists with apk"
            return 1
        }
        apk search > "$package_cache" 2>/dev/null || {
            stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            debug_log "ERROR" "Failed to save package list with apk"
            return 1
        }
    fi

    # スピナー停止 (成功メッセージを表示)
    stop_spinner "$(color green "$(get_message "MSG_UPDATE_SUCCESS")")"
    
    # キャッシュのタイムスタンプを更新
    touch "$update_cache" || {
        debug_log "ERROR" "Failed to write to cache file: $update_cache"
        # パッケージリストは更新できているのでエラー扱いはしない
        debug_log "WARN" "Cache timestamp could not be updated, next run will force update"
    }

    return 0
}

# local-package.dbからの設定を適用
local_package_db() {
    local package_name="$1"  # どんなパッケージ名でも受け取れる

    debug_log "DEBUG" "Starting to apply local-package.db for package: $package_name"

    # `local-package.db` から `$package_name` に該当するセクションを抽出
    extract_commands() {
        awk -v p="$package_name" '
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
    printf "%s" "$cmds" > "${CACHE_DIR}/commands.ch"

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

# パッケージインストール前のチェック
package_pre_install() {
    local package_name="$1"
    local package_cache="${CACHE_DIR}/package_list.ch"

    debug_log "DEBUG" "Checking package: $package_name"

    # デバイス内パッケージ確認
    local check_extension=$(basename "$package_name" .ipk)
    check_extension=$(basename "$check_extension" .apk)

    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        output=$(opkg list-installed "$check_extension" 2>&1)
        if [ -n "$output" ]; then  # 出力があった場合
            debug_log "DEBUG" "Package \"$check_extension\" is already installed on the device"
            return 1  # 既にインストールされている場合は終了
        fi
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        output=$(apk info "$check_extension" 2>&1)
        if [ -n "$output" ]; then  # 出力があった場合
            debug_log "DEBUG" "Package \"$check_extension\" is already installed on the device"
            return 1  # 既にインストールされている場合は終了
        fi
    fi
  
    # リポジトリ内パッケージ確認
    debug_log "DEBUG" "Checking repository for package: $check_extension"

    if [ ! -f "$package_cache" ]; then
        debug_log "DEBUG" "Package cache not found. Attempting to update."
        update_package_list >/dev/null 2>&1
        
        # 更新後も存在しない場合は警告を出すが処理は継続
        if [ ! -f "$package_cache" ]; then
            debug_log "WARNING" "Package cache still not available after update attempt"
            # キャッシュがなくてもインストール処理は続行（ローカルファイル等の場合）
        fi
    fi

    # パッケージキャッシュが存在する場合のみチェック
    if [ -f "$package_cache" ]; then
        # パッケージがキャッシュ内に存在するか確認
        if grep -q "^$package_name " "$package_cache"; then
            debug_log "DEBUG" "Package $package_name found in repository"
            return 0  # パッケージが存在するのでOK
        fi
    fi

    # キャッシュに存在しない場合、FEED_DIR内を探してみる
    if [ -f "$package_name" ]; then
        debug_log "DEBUG" "Package $package_name found in FEED_DIR: $FEED_DIR"
        return 0  # FEED_DIR内にパッケージが見つかったのでOK
    fi

    debug_log "DEBUG" "Package $package_name not found in repository or FEED_DIR"
    # リポジトリにもFEED_DIRにも存在しないパッケージはスキップする
    return 1  # 修正: 0から1に変更
}

# 通常パッケージのインストール処理
install_normal_package() {
    local package_name="$1"
    local force_install="$2"

    debug_log "DEBUG" "Starting installation process for: $package_name"

    start_spinner "$(color blue "$package_name $(get_message "MSG_INSTALLING_PACKAGE")")"

    if [ "$force_install" = "yes" ]; then
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install --force-reinstall "$package_name" > /dev/null 2>&1 || {
                stop_spinner "$(color red "Failed to install package $package_name")"
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add --force-reinstall "$package_name" > /dev/null 2>&1 || {
                stop_spinner "$(color red "Failed to install package $package_name")"
                return 1
            }
        fi
    else
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install "$package_name" > /dev/null 2>&1 || {
                stop_spinner "$(color red "Failed to install package $package_name")"
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add "$package_name" > /dev/null 2>&1 || {
                stop_spinner "$(color red "Failed to install package $package_name")"
                return 1
            }
        fi
    fi

    stop_spinner "$(color green "$package_name $(get_message "MSG_INSTALL_SUCCESS")")"
    return 0
}

# パッケージマネージャーの確認
verify_package_manager() {
    if [ -f "${CACHE_DIR}/package_manager.ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/package_manager.ch")
        debug_log "DEBUG" "Package manager detected: $PACKAGE_MANAGER"
        return 0
    else
        debug_log "ERROR" "Cannot determine package manager. File not found: ${CACHE_DIR}/package_manager.ch"
        return 1
    fi
}

# 言語コードの取得
get_language_code() {
    local lang_code="en"  # デフォルト値
    local luci_cache="${CACHE_DIR}/luci.ch"
    
    debug_log "DEBUG" "Getting LuCI language code"
    
    # luci.chファイルが存在するか確認
    if [ -f "$luci_cache" ]; then
        lang_code=$(head -n 1 "$luci_cache" | awk '{print $1}')
        debug_log "DEBUG" "Found language code in luci.ch: $lang_code"
    else
        debug_log "DEBUG" "luci.ch not found, generating language package information"
        
        # luci.chがない場合はget_available_language_packagesを呼び出す
        if type get_available_language_packages >/dev/null 2>&1; then
            get_available_language_packages >/dev/null
            
            # 生成されたluci.chを再度読み込み
            if [ -f "$luci_cache" ]; then
                lang_code=$(head -n 1 "$luci_cache" | awk '{print $1}')
                debug_log "DEBUG" "Retrieved language code after generating luci.ch: $lang_code"
            else
                debug_log "ERROR" "Failed to generate luci.ch, using default language: en"
            fi
        else
            debug_log "ERROR" "get_available_language_packages() function not available"
        fi
    fi
    
    debug_log "DEBUG" "Using LuCI language code: $lang_code"
    echo "$lang_code"
}

# サービス設定
configure_service() {
    local package_name="$1"
    local base_name="$2"
    
    debug_log "DEBUG" "Configuring service for: $package_name"
    
    # サービスが存在するかチェックし、処理を分岐
    if [ -x "/etc/init.d/$base_name" ]; then
        if echo "$base_name" | grep -q "^luci-"; then
            # Luci関連のパッケージの場合はrpcdを再起動
            /etc/init.d/rpcd restart
            debug_log "DEBUG" "$package_name is a LuCI package, rpcd has been restarted"
        else
            /etc/init.d/"$base_name" restart
            /etc/init.d/"$base_name" enable
            debug_log "DEBUG" "$package_name has been restarted and enabled"
        fi
    else
        debug_log "DEBUG" "$package_name is not a service or the service script is not found"
    fi
}

# オプション解析
parse_package_options() {
    # 変数初期化（既存の変数）
    PKG_OPTIONS_CONFIRM="no"
    PKG_OPTIONS_SKIP_LANG="no"
    PKG_OPTIONS_FORCE="no"
    PKG_OPTIONS_SKIP_PACKAGE_DB="no"
    PKG_OPTIONS_DISABLED="no"
    PKG_OPTIONS_HIDDEN="no"
    PKG_OPTIONS_TEST="no"
    PKG_OPTIONS_UPDATE="no"
    PKG_OPTIONS_UNFORCE="no"
    PKG_OPTIONS_LIST="no"
    PKG_OPTIONS_PACKAGE_NAME=""
    
    # 新しい変数：説明文用
    PKG_OPTIONS_DESCRIPTION=""
    
    # オプション解析
    while [ $# -gt 0 ]; do
        case "$1" in
            yn) PKG_OPTIONS_CONFIRM="yes" ;;
            nolang) PKG_OPTIONS_SKIP_LANG="yes" ;;
            force) PKG_OPTIONS_FORCE="yes" ;;
            notpack) PKG_OPTIONS_SKIP_PACKAGE_DB="yes" ;;
            disabled) PKG_OPTIONS_DISABLED="yes" ;;
            hidden) PKG_OPTIONS_HIDDEN="yes" ;;
            test) PKG_OPTIONS_TEST="yes" ;;
            desc=*) 
                # 説明文オプション処理 - "desc=" 以降の文字列を取得
                PKG_OPTIONS_DESCRIPTION="${1#desc=}"
                debug_log "DEBUG" "Package description set to: $PKG_OPTIONS_DESCRIPTION" 
                ;;
            update)
                PKG_OPTIONS_UPDATE="yes"
                shift
                if [ $# -gt 0 ]; then
                    PKG_OPTIONS_PACKAGE_UPDATE="$1"
                    shift
                fi
                continue
                ;;
            unforce) PKG_OPTIONS_UNFORCE="yes" ;;
            list) PKG_OPTIONS_LIST="yes" ;;
            -*) 
                debug_log "ERROR" "Unknown option: $1"
                return 1 
                ;;
            *)
                if [ -z "$PKG_OPTIONS_PACKAGE_NAME" ]; then
                    PKG_OPTIONS_PACKAGE_NAME="$1"
                else
                    debug_log "DEBUG" "Additional argument will be treated as description: $1"
                    # 説明文がまだ設定されていなければ、2番目の引数を説明文として扱う
                    if [ -z "$PKG_OPTIONS_DESCRIPTION" ]; then
                        PKG_OPTIONS_DESCRIPTION="$1"
                        debug_log "DEBUG" "Package description set from positional argument: $PKG_OPTIONS_DESCRIPTION"
                    else
                        debug_log "DEBUG" "Unexpected additional argument: $1"
                    fi
                fi
                ;;
        esac
        shift
    done
    
    # パッケージ名が指定されていない場合の処理
    if [ -z "$PKG_OPTIONS_PACKAGE_NAME" ] && [ "$PKG_OPTIONS_LIST" != "yes" ] && [ "$PKG_OPTIONS_UPDATE" != "yes" ]; then
        debug_log "ERROR" "No package name specified"
        return 1
    fi
    
    return 0
}

# パッケージリストから説明を取得する関数
get_package_description() {
    local package_name="$1"
    local package_cache="${CACHE_DIR}/package_list.ch"
    local description=""
    
    # パッケージキャッシュの存在確認
    if [ ! -f "$package_cache" ]; then
        debug_log "DEBUG" "Package cache not found. Cannot retrieve description."
        return 1
    fi
    
    # パッケージ名に一致する行を取得
    local package_line=$(grep "^$package_name " "$package_cache" 2>/dev/null)
    if [ -z "$package_line" ]; then
        debug_log "DEBUG" "Package $package_name not found in cache."
        return 1
    fi
    
    # 説明部分を抽出（3番目のフィールド: 2つ目の '-' 以降、3つ目の '-' 以前）
    description=$(echo "$package_line" | awk -F' - ' '{if (NF >= 3) print $3}')
    
    # 説明が見つかった場合は出力
    if [ -n "$description" ]; then
        echo "$description"
        return 0
    fi
    
    debug_log "DEBUG" "No description found for package $package_name"
    return 1
}

# パッケージ処理メイン部分
process_package() {
    local package_name="$1"
    local base_name="$2"
    local confirm_install="$3"
    local force_install="$4"
    local skip_package_db="$5"
    local set_disabled="$6"
    local test_mode="$7"
    local lang_code="$8"
    local description=""

    # 言語パッケージか通常パッケージかを判別
    case "$base_name" in
        luci-i18n-*)
            # 言語パッケージの場合、package_name に言語コードを追加
            package_name="${base_name}-${lang_code}"
            debug_log "DEBUG" "Language package detected, using: $package_name"
            ;;
    esac

    # test_mode が有効でなければパッケージの事前チェックを行う
    if [ "$test_mode" != "yes" ]; then
        if ! package_pre_install "$package_name"; then
            debug_log "DEBUG" "Package $package_name is already installed or not found"
            return 1
        fi
    else
        debug_log "DEBUG" "Test mode enabled, skipping pre-install checks"
    fi
    
    # YN確認 (オプションで有効時のみ)
    if [ "$confirm_install" = "yes" ]; then
        # パッケージ名からパスと拡張子を除去した表示用の名前を作成
        local display_name
        display_name=$(basename "$package_name")
        display_name=${display_name%.*}  # 拡張子を除去

        debug_log "DEBUG" "Original package name: $package_name"
        debug_log "DEBUG" "Displaying package name: $display_name"
    
        # 説明文の優先順位：
        # 1. パラメータで指定された説明（PKG_OPTIONS_DESCRIPTION）があれば優先
        # 2. なければパッケージリストから取得
        if [ -n "$PKG_OPTIONS_DESCRIPTION" ]; then
            description="$PKG_OPTIONS_DESCRIPTION"
            debug_log "DEBUG" "Using manually provided description: $description"
        else
            # パッケージリストから説明を取得
            description=$(get_package_description "$package_name")
            debug_log "DEBUG" "Using repository description: $description"
        fi
        
        # 説明文があれば専用のメッセージキーを使用
        if [ -n "$description" ]; then
            # 説明文付きの確認メッセージ - パラメータ形式を修正
            if ! confirm "MSG_CONFIRM_INSTALL_WITH_DESC" "pkg=$display_name" "desc=$description"; then
                debug_log "DEBUG" "User declined installation of $display_name with description"
                return 0
            fi
        else
            # 通常の確認メッセージ - パラメータ形式を修正
            if ! confirm "MSG_CONFIRM_INSTALL" "pkg=$display_name"; then
                debug_log "DEBUG" "User declined installation of $display_name"
                return 0
            fi
        fi
    fi
     
    # パッケージのインストール
    if ! install_normal_package "$package_name" "$force_install"; then
        debug_log "DEGUB" "Failed to install package: $package_name"
        return 1
    fi

    # **ローカルパッケージDBの適用 (インストール成功後に実行)**
    if [ "$skip_package_db" != "yes" ]; then
        local_package_db "$base_name"
    else
        debug_log "DEBUG" "Skipping local-package.db application for $package_name"
    fi
    
    return 0
}

# **パッケージインストールのメイン関数**
install_package() {
    # オプション解析
    if ! parse_package_options "$@"; then
        return 1
    fi
    
    # インストール一覧表示モードの場合
    if [ "$PKG_OPTIONS_LIST" = "yes" ]; then
        check_install_list
        return 0
    fi
    
    # **ベースネームを取得**
    local BASE_NAME
    if [ -n "$PKG_OPTIONS_PACKAGE_NAME" ]; then
        BASE_NAME=$(basename "$PKG_OPTIONS_PACKAGE_NAME" .ipk)
        BASE_NAME=$(basename "$BASE_NAME" .apk)
    fi

    # update オプション処理
    if [ "$PKG_OPTIONS_UPDATE" = "yes" ]; then
        debug_log "DEBUG" "Updating package lists"
        update_package_list
        return $?
    fi

    # パッケージマネージャー確認
    if ! verify_package_manager; then
        debug_log "ERROR" "Failed to verify package manager"
        return 1
    fi

    # **パッケージリスト更新**
    update_package_list || return 1

    # 言語コード取得
    local lang_code
    lang_code=$(get_language_code)
    
    # パッケージ処理
    if ! process_package \
            "$PKG_OPTIONS_PACKAGE_NAME" \
            "$BASE_NAME" \
            "$PKG_OPTIONS_CONFIRM" \
            "$PKG_OPTIONS_FORCE" \
            "$PKG_OPTIONS_SKIP_PACKAGE_DB" \
            "$PKG_OPTIONS_DISABLED" \
            "$PKG_OPTIONS_TEST" \
            "$lang_code"; then
        return 1
    fi

    # サービス関連の処理（disabled オプションが有効な場合は全スキップ）
    if [ "$PKG_OPTIONS_DISABLED" != "yes" ]; then
        configure_service "$PKG_OPTIONS_PACKAGE_NAME" "$BASE_NAME"
    else
        debug_log "DEBUG" "Skipping service handling for $PKG_OPTIONS_PACKAGE_NAME due to disabled option"
    fi
    
    return 0
}
