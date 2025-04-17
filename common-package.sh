#!/bin/sh

SCRIPT_VERSION="2025.04.12-00-00"

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
# Last Update: 2025-04-12 05:23:31 (UTC) 🚀
# install_package: パッケージインストール処理関数
# 使用対象：OpenWrtとAlpine Linuxシステム向け
#
# 【主な機能】
#  ✅ パッケージインストールとリポジトリ更新
#  ✅ 言語パッケージの自動処理
#  ✅ サービスの自動設定
#  ✅ インストール前の確認ダイアログ表示
#
# 【基本構文】
#   install_package [オプション...] <パッケージ名>
#
# 【オプション一覧】
#   yn          - インストール前に確認ダイアログを表示
#                 例: install_package yn luci-app-statistics
#
#   nolang      - 言語パッケージのインストールをスキップ
#                 例: install_package nolang luci-app-firewall
#
#   force       - パッケージの強制再インストール
#                 例: install_package force luci-app-opkg
#
#   notpack     - local-package.dbの設定適用をスキップ
#                 例: install_package notpack htop
#
#   disabled    - サービスの自動設定をスキップ
#                 ※パッケージは通常通りインストールし、サービス開始のみスキップ
#                 例: install_package disabled irqbalance
#
#   hidden      - 一部の通知メッセージを表示しない
#                 例: install_package hidden luci-i18n-base
#
#   silent      - 進捗・通知メッセージを全て抑制（エラー以外）
#                 例: install_package silent htop
#
#   test        - テストモード（インストール前チェックをスキップ）
#                 例: install_package test luci-app-opkg
#
#   desc="説明" - パッケージの説明文を指定
#                 例: install_package yn luci-app-statistics "desc=統計情報を表示"
#
#   update      - パッケージリストの更新のみ実行
#                 例: install_package update
#
#   list        - インストール済みパッケージの一覧表示
#                 例: install_package list
#
# 【オプション組み合わせ例】
#   確認ダイアログ付き通知抑制:
#     install_package yn hidden luci-app-statistics
#
#   説明付き確認とサービス自動設定スキップ:
#     install_package yn disabled luci-app-banip "desc=IPブロックツール"
#
#   完全サイレントモード（通知なし・確認なし）:
#     install_package silent luci-i18n-base
#
# 【重要な動作特性】
#  1. オプションは順不同で指定可能
#  2. disabled: サービスの自動設定のみをスキップ（インストールは実行）
#  3. silent: yn指定があっても確認ダイアログを表示しない
#  4. hidden: 既にインストール済みの場合のメッセージなど一部通知のみ非表示
#
# 【返り値】
#   0: 成功 または ユーザーがインストールをキャンセル
#   1: エラー発生
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
    local silent_mode="$1"  # silentモードパラメータを追加
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

    # silent モードでない場合のみ表示
    if [ "$silent_mode" != "yes" ]; then
        printf "  %s\n"
        # スピナー開始
        start_spinner "$(color blue "$(get_message "MSG_RUNNING_UPDATE")")"
    fi

    # PACKAGE_MANAGERを取得
    if [ -f "${CACHE_DIR}/package_manager.ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/package_manager.ch")
    fi
    
    debug_log "DEBUG" "Using package manager: $PACKAGE_MANAGER"

    # パッケージリストの更新実行
    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        debug_log "DEBUG" "Running opkg update"
        opkg update > "${LOG_DIR}/opkg_update.log" 2>&1
        if [ $? -ne 0 ]; then
            if [ "$silent_mode" != "yes" ]; then
                stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            else
                # エラー時はsilentモードでもエラーメッセージを表示
                printf "%s\n" "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            fi
            debug_log "DEBUG" "Failed to update package lists with opkg"
            # タイムスタンプファイルを削除して、次回も更新を試みるようにする
            rm -f "$update_cache" 2>/dev/null
            return 1
        fi
        
        debug_log "DEBUG" "Saving package list to $package_cache"
        opkg list > "$package_cache" 2>/dev/null
        if [ $? -ne 0 ] || [ ! -s "$package_cache" ]; then
            if [ "$silent_mode" != "yes" ]; then
                stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            else
                # エラー時はsilentモードでもエラーメッセージを表示
                printf "%s\n" "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            fi
            debug_log "DEBUG" "Failed to save package list to $package_cache"
            # タイムスタンプファイルを削除して、次回も更新を試みるようにする
            rm -f "$update_cache" 2>/dev/null
            return 1
        fi
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        debug_log "DEBUG" "Running apk update"
        apk update > "${LOG_DIR}/apk_update.log" 2>&1
        if [ $? -ne 0 ]; then
            if [ "$silent_mode" != "yes" ]; then
                stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            else
                # エラー時はsilentモードでもエラーメッセージを表示
                printf "%s\n" "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            fi
            debug_log "DEBUG" "Failed to update package lists with apk"
            # タイムスタンプファイルを削除して、次回も更新を試みるようにする
            rm -f "$update_cache" 2>/dev/null
            return 1
        fi
        
        debug_log "DEBUG" "Saving package list to $package_cache"
        apk search > "$package_cache" 2>/dev/null
        if [ $? -ne 0 ] || [ ! -s "$package_cache" ]; then
            if [ "$silent_mode" != "yes" ]; then
                stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            else
                # エラー時はsilentモードでもエラーメッセージを表示
                printf "%s\n" "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
            fi
            debug_log "DEBUG" "Failed to save package list to $package_cache"
            # タイムスタンプファイルを削除して、次回も更新を試みるようにする
            rm -f "$update_cache" 2>/dev/null
            return 1
        fi
    else
        if [ "$silent_mode" != "yes" ]; then
            stop_spinner "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
        else
            # エラー時はsilentモードでもエラーメッセージを表示
            printf "%s\n" "$(color red "$(get_message "MSG_UPDATE_FAILED")")"
        fi
        debug_log "DEBUG" "Unknown package manager: $PACKAGE_MANAGER"
        # タイムスタンプファイルを削除して、次回も更新を試みるようにする
        rm -f "$update_cache" 2>/dev/null
        return 1
    fi

    # スピナー停止（成功メッセージを表示）- silent モードでなければ表示
    if [ "$silent_mode" != "yes" ]; then
        stop_spinner "$(color green "$(get_message "MSG_UPDATE_SUCCESS")")"
    fi
    
    # キャッシュのタイムスタンプを更新
    touch "$update_cache" 2>/dev/null
    if [ $? -ne 0 ]; then
        debug_log "DEBUG" "Failed to create/update cache file: $update_cache"
        # パッケージリストは更新できているのでエラー扱いはしない
        debug_log "WARN" "Cache timestamp could not be updated, next run will force update"
    else
        debug_log "DEBUG" "Cache timestamp updated: $update_cache"
    fi
    
    # package_cacheが作成されたか確認
    if [ -f "$package_cache" ] && [ -s "$package_cache" ]; then
        debug_log "DEBUG" "Package list cache successfully created: $package_cache"
    else
        debug_log "WARN" "Package list cache not properly created: $package_cache"
    fi

    return 0
}

# local-package.dbからの設定を適用
local_package_db() {
    local package_name="$1"  # どんなパッケージ名でも受け取れる

    debug_log "DEBUG" "Starting to apply local-package.db for package: $package_name"

    # `local-package.db` から `$package_name` に該当するセクションを抽出
    extract_commands() {
        # ★ 修正: pkg 変数名を変更 (p から pkg へ) し、正規表現をより厳密に
        awk -v pkg="$package_name" '
            $0 ~ "^\\[" pkg "\\]$" {flag=1; next} # ★ セクション名を完全一致で検索
            $0 ~ "^\\[" {flag=0}
            flag && $0 !~ "^#" && $0 !~ "^[[:space:]]*$" {print} # ★ 空行も除外
        ' "${BASE_DIR}/local-package.db"
    }

    # コマンドを取得
    local cmds
    cmds=$(extract_commands)

    if [ -z "$cmds" ]; then
        debug_log "DEBUG" "No commands found for package: $package_name in ${BASE_DIR}/local-package.db" # ★ DBファイルパスをログに追加
        return 1 # ★ コマンドが見つからない場合はエラーコード 1 を返すように変更
    fi

    # ★ 修正: commands.ch のパスを修正 (BASE_DIR から CACHE_DIR へ)
    local commands_file="${CACHE_DIR}/commands.ch"
    # **変数の置換**
    printf "%s\n" "$cmds" > "$commands_file" # ★ 改行を追加

    # **環境変数 `CUSTOM_*` を自動検出して置換**
    CUSTOM_VARS=$(env | grep "^CUSTOM_" | awk -F= '{print $1}')
    for var_name in $CUSTOM_VARS; do
        # ★ 修正: eval を使わずに変数の値を取得 (POSIX準拠のため eval は慎重に)
        # シェルによっては printenv $var_name が使えるが、ash にはない可能性
        # POSIX準拠のため、可能な限り eval を避けるが、ここでは必要悪か
        # より安全な方法があれば検討したいが、ash の制約を考えると難しい
        # 今回は元のロジックを維持しつつ、デバッグログを強化
        eval var_value=\$$var_name
        if [ -n "$var_value" ]; then
            # ★ 修正: sed のデリミタを | に変更 (パスに / が含まれる可能性を考慮)
            sed -i "s|\\\${$var_name}|$var_value|g" "$commands_file"
            debug_log "DEBUG" "Substituted variable in $commands_file: $var_name -> $var_value"
        else
            # ★ 修正: 未定義変数の行をコメントアウトする処理を改善
            # sed で直接コメントアウトし、マッチした行全体をコメント化
            sed -i "/\${$var_name}/s/^/# UNDEFINED: /" "$commands_file"
            debug_log "DEBUG" "Commented out line due to undefined variable: $var_name in $commands_file"
        fi
    done

    # **設定を適用**
    # ★★★ 修正点: サブシェル内でコマンドを実行 ★★★
    debug_log "DEBUG" "Executing commands from $commands_file in a subshell"
    # ★ 修正点: commands.ch の内容をログに出力（デバッグ用）
    debug_log "DEBUG" "Content of $commands_file before execution:"
    # 各行の先頭に "> " を付けてログ出力
    while IFS= read -r line; do
        debug_log "DEBUG" "> $line"
    done < "$commands_file"

    ( . "$commands_file" ) # ★ コマンドをサブシェルで実行
    local exit_status=$? # ★ サブシェルの終了ステータスを取得

    if [ $exit_status -ne 0 ]; then
        debug_log "DEBUG" "Error executing commands from $commands_file for package $package_name (Exit status: $exit_status)"
        # ★★★ 修正点: エラー発生時に commands.ch の内容を再度ログ出力 ★★★
        debug_log "DEBUG" "Content of $commands_file that caused the error:"
        # 各行の先頭に "E> " を付けてログ出力
        while IFS= read -r line; do
            debug_log "DEBUG" "E> $line"
        done < "$commands_file"
        rm -f "$commands_file" # ★ エラー時はファイルを削除
        return 1 # ★ エラーが発生した場合は 1 を返す
    fi

    debug_log "DEBUG" "Successfully executed commands from $commands_file for package $package_name"
    # ★ 成功時は commands.ch を削除しても良いかもしれない (デバッグ用に残すか要検討)
    rm -f "$commands_file" # ★ 成功時もファイルを削除

    return 0 # ★ 成功時は 0 を返す
}

# Function: package_pre_install
# Description: Check if a package should be installed.
# Args: $1 - package name
#       $2 - package category (e.g., main, luci, custom)
#       $3 - package options (e.g., hidden, force)
# Returns: 0 - Ready to install
#          1 - Error or user refused
#          2 - Already installed or held
#          3 - Not found in repository (skip)
package_pre_install() {
  local pkg_name="$1"
  local pkg_category="$2"
  local pkg_options="$3"
  local pkg_status installed_version available_version user_input is_hidden is_force is_disabled

  is_hidden() { echo "$pkg_options" | grep -q "hidden"; }
  is_force() { echo "$pkg_options" | grep -q "force"; }
  is_disabled() { echo "$pkg_options" | grep -q "disabled"; }

  log_debug "Running pre-install check for package: $pkg_name ($pkg_category, $pkg_options)"

  opkg_find_package "$pkg_name"
  pkg_status=$?

  case $pkg_status in
    0) # Found
      installed_version=$(opkg info "$pkg_name" | grep '^Version:' | awk '{print $2}')
      available_version=$(opkg info-available "$pkg_name" | grep '^Version:' | awk '{print $2}')
      if [ -n "$installed_version" ]; then
        if [ "$installed_version" = "$available_version" ]; then
          log_info "Package '$pkg_name' is already installed and up-to-date (Version: $installed_version)."
          return 2 # Already installed
        else
          log_info "Package '$pkg_name' is installed (Version: $installed_version), available (Version: $available_version)."
          # Potentially handle upgrade logic here if needed in the future, for now treat as installed
          return 2 # Treat as installed for now
        fi
      fi
      # Package found and not installed, ready to install
      ;;
    1) # Not found
      log_debug "Package '$pkg_name' not found in repository, skipping installation."
      # No error message to user, just skip
      return 3 # Not found in repository (skip)
      ;;
    2) # Held
      log_info "Package '$pkg_name' is held. Skipping."
      return 2 # Held
      ;;
    *) # Other opkg error
      log_error "Error checking status for package '$pkg_name' (opkg_find_package returned $pkg_status)."
      return 1 # Error
      ;;
  esac

  # Ask user if not hidden
  if ! is_hidden; then
    echo "" # Add newline for better formatting
    get_package_description "$pkg_name" # Display description
    if ! confirm_action "Install package '$pkg_name' (y/n): "; then
      log_info "User declined installation for package '$pkg_name'."
      return 1 # User refused
    fi
  fi

  log_debug "Pre-install check passed for package: $pkg_name"
  return 0 # Ready to install
}

# 通常パッケージのインストール処理
install_normal_package() {
    local package_name="$1"
    local force_install="$2"
    local silent_mode="$3"
    
    # 表示用の名前を作成（パスと拡張子を除去）
    local display_name
    display_name=$(basename "$package_name")
    display_name=${display_name%.*}  # 拡張子を除去

    debug_log "DEBUG" "Starting installation process for: $package_name"
    debug_log "DEBUG" "Display name for messages: $display_name"

    # silent モードが有効でない場合のみスピナーを開始
    if [ "$silent_mode" != "yes" ]; then
        start_spinner "$(color blue "$display_name $(get_message "MSG_INSTALLING_PACKAGE")")"
    fi

    if [ "$force_install" = "yes" ]; then
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install --force-reinstall "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add --force-reinstall "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        fi
    else
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        fi
    fi

    # silent モードが有効でない場合のみスピナーを停止
    if [ "$silent_mode" != "yes" ]; then
        stop_spinner "$(color green "$display_name $(get_message "MSG_INSTALL_SUCCESS")")"
    fi
    
    return 0
}

# パッケージマネージャーの確認
verify_package_manager() {
    if [ -f "${CACHE_DIR}/package_manager.ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/package_manager.ch")
        debug_log "DEBUG" "Package manager detected: $PACKAGE_MANAGER"
        return 0
    else
        debug_log "DEBUG" "Cannot determine package manager. File not found: ${CACHE_DIR}/package_manager.ch"
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
                debug_log "DEBUG" "Failed to generate luci.ch, using default language: en"
            fi
        else
            debug_log "DEBUG" "get_available_language_packages() function not available"
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
    PKG_OPTIONS_SILENT="no"
    
    # 変数初期化：説明文用
    PKG_OPTIONS_DESCRIPTION=""

    # 引数のデバッグ出力
    debug_log "DEBUG" "parse_package_options: 受け取った引数 ($#): $*"
    
    # オプション解析
    while [ $# -gt 0 ]; do
        # 現在処理中の引数をデバッグ出力
        debug_log "DEBUG" "parse_package_options: 処理中の引数: $1"
        
        case "$1" in
            yn) PKG_OPTIONS_CONFIRM="yes"; debug_log "DEBUG" "Option: confirm=yes" ;;
            nolang) PKG_OPTIONS_SKIP_LANG="yes"; debug_log "DEBUG" "Option: skip_lang=yes" ;;
            force) PKG_OPTIONS_FORCE="yes"; debug_log "DEBUG" "Option: force=yes" ;;
            notpack) PKG_OPTIONS_SKIP_PACKAGE_DB="yes"; debug_log "DEBUG" "Option: skip_package_db=yes" ;;
            disabled) PKG_OPTIONS_DISABLED="yes"; debug_log "DEBUG" "Option: disabled=yes" ;;
            hidden) PKG_OPTIONS_HIDDEN="yes"; debug_log "DEBUG" "Option: hidden=yes" ;;
            test) PKG_OPTIONS_TEST="yes"; debug_log "DEBUG" "Option: test=yes" ;;
            silent) PKG_OPTIONS_SILENT="yes"; debug_log "DEBUG" "Option: silent=yes" ;;  # silent オプションの追加
            desc=*) 
                # 説明文オプション処理 - "desc=" 以降の文字列を取得
                PKG_OPTIONS_DESCRIPTION="${1#desc=}"
                debug_log "DEBUG" "Option: description=$PKG_OPTIONS_DESCRIPTION" 
                ;;
            update)
                PKG_OPTIONS_UPDATE="yes"
                debug_log "DEBUG" "Option: update=yes"
                shift
                if [ $# -gt 0 ]; then
                    PKG_OPTIONS_PACKAGE_UPDATE="$1"
                    debug_log "DEBUG" "Package update: $PKG_OPTIONS_PACKAGE_UPDATE"
                    shift
                fi
                continue
                ;;
            unforce) PKG_OPTIONS_UNFORCE="yes"; debug_log "DEBUG" "Option: unforce=yes" ;;
            list) PKG_OPTIONS_LIST="yes"; debug_log "DEBUG" "Option: list=yes" ;;
            -*) 
                debug_log "DEBUG" "Unknown option: $1"
                return 1 
                ;;
            *)
                if [ -z "$PKG_OPTIONS_PACKAGE_NAME" ]; then
                    PKG_OPTIONS_PACKAGE_NAME="$1"
                    debug_log "DEBUG" "Package name: $PKG_OPTIONS_PACKAGE_NAME"
                else
                    debug_log "DEBUG" "Additional argument after package name: $1"
                    # 既に説明文が設定されている場合は追加の引数として処理しない
                    if [ -n "$PKG_OPTIONS_DESCRIPTION" ]; then
                        debug_log "DEBUG" "Description already set, ignoring: $1"
                    else
                        # 追加の引数を説明文として扱う（旧動作との互換性のため）
                        debug_log "DEBUG" "Additional argument will be treated as description: $1"
                        PKG_OPTIONS_DESCRIPTION="$1"
                    fi
                fi
                ;;
        esac
        shift
    done
    
    # パッケージ名が指定されていない場合の処理
    if [ -z "$PKG_OPTIONS_PACKAGE_NAME" ] && [ "$PKG_OPTIONS_LIST" != "yes" ] && [ "$PKG_OPTIONS_UPDATE" != "yes" ]; then
        debug_log "DEBUG" "No package name specified"
        return 1
    fi
    
    # オプションに関する情報を出力
    debug_log "DEBUG" "Options parsed: confirm=$PKG_OPTIONS_CONFIRM, force=$PKG_OPTIONS_FORCE, silent=$PKG_OPTIONS_SILENT, description='$PKG_OPTIONS_DESCRIPTION', package=$PKG_OPTIONS_PACKAGE_NAME"
    
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

# Function: process_package
# Description: Process a single package installation request.
# Args: $1 - package name
#       $2 - package category
#       $3 - package options
# Returns: 0 - Success or skipped
#          1 - Failure or user refused
process_package() {
  local pkg_name="$1"
  local pkg_category="$2"
  local pkg_options="$3"
  local pre_install_status install_status=1 # Default to failure

  log_debug "Processing package: $pkg_name ($pkg_category, $pkg_options)"

  package_pre_install "$pkg_name" "$pkg_category" "$pkg_options"
  pre_install_status=$?

  case $pre_install_status in
    0) # Ready to install
      log_debug "Pre-install check returned 0 (Ready to install) for $pkg_name."
      install_normal_package "$pkg_name" "$pkg_category" "$pkg_options"
      install_status=$?
      ;;
    1) # Error or user refused
      log_debug "Pre-install check returned 1 (Error or user refused) for $pkg_name."
      install_status=1 # Ensure status reflects failure/refusal
      ;;
    2) # Already installed or held
      log_debug "Pre-install check returned 2 (Already installed or held) for $pkg_name."
      install_status=0 # Treat as success (already done or skipped intentionally)
      ;;
    3) # Not found in repository (skip)
      log_debug "Pre-install check returned 3 (Not found in repository) for $pkg_name. Skipping install step."
      install_status=0 # Treat as success (skipped intentionally as per requirement)
      ;;
    *) # Unexpected status
      log_error "Unexpected status $pre_install_status from package_pre_install for $pkg_name."
      install_status=1
      ;;
  esac

  if [ $install_status -eq 0 ] && ! echo "$pkg_options" | grep -q "disabled"; then
      configure_service "$pkg_name"
  fi

  log_debug "Finished processing package: $pkg_name. Final status: $install_status"
  return $install_status
}

# **パッケージインストールのメイン関数**
install_package() {
    # オプション解析
    if ! parse_package_options "$@"; then
        return 1
    fi
    
    # インストール一覧表示モードの場合（silentモードでなければ表示）
    if [ "$PKG_OPTIONS_LIST" = "yes" ]; then
        if [ "$PKG_OPTIONS_SILENT" != "yes" ]; then
            check_install_list
        fi
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
        # silentモードを渡して更新を実行
        update_package_list "$PKG_OPTIONS_SILENT"
        return $?
    fi

    # パッケージマネージャー確認
    if ! verify_package_manager; then
        debug_log "DEBUG" "Failed to verify package manager"
        return 1
    fi

    # **パッケージリスト更新** - silentモードを引数として渡す
    update_package_list "$PKG_OPTIONS_SILENT" || return 1

    # 言語コード取得
    local lang_code
    lang_code=$(get_language_code)
    
    # パッケージ処理 - silentモードもパラメータとして渡す
    if ! process_package \
            "$PKG_OPTIONS_PACKAGE_NAME" \
            "$BASE_NAME" \
            "$PKG_OPTIONS_CONFIRM" \
            "$PKG_OPTIONS_FORCE" \
            "$PKG_OPTIONS_SKIP_PACKAGE_DB" \
            "$PKG_OPTIONS_DISABLED" \
            "$PKG_OPTIONS_TEST" \
            "$lang_code" \
            "$PKG_OPTIONS_DESCRIPTION" \
            "$PKG_OPTIONS_SILENT"; then
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
