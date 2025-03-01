#!/bin/sh

SCRIPT_VERSION="2025.03.01-00-01"

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

echo -e "\033[7;40mUpdated to version $SCRIPT_VERSION build-common.sh \033[0m"

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
# Last Update: 2025-03-01 12:00:00 (JST) 🚀
# install_build: パッケージのビルド処理 (OpenWrt / Alpine Linux)
#
# 【概要】
# 指定されたパッケージをビルドし、オプションに応じて処理を実行する。
# 1回の動作で１つのビルドのみパッケージを作りインストール作業
# DEBUG に応じて出力制御（必須事項：変数確認、キャッシュ確認、フロー確認）
#
# 【フロー】
# 2️⃣ デバイスにパッケージがインストール済みか確認（hiddenの場合メッセージは非表示）
# 4️⃣ インストール確認（yn オプションが指定された場合）
# 4️⃣ スワップ適用（サイズ自動判別）
# 4️⃣ ビルド用汎用パッケージ（リポジトリにあるパッケージは全てinstall_package()利用）
# 7️⃣ custom-package.db の適用（ビルド用設定）
# 4️⃣ ビルド作業
# 5️⃣ インストールの実行（.ipk）
#
# 【ビルド用汎用パッケージ】
# install_package = 以下
# {git make gcc git libtool-bin automake pkg-config zlib-dev libncurses-dev curl libxml2 libxml2-dev autoconf automake bison flex perl patch wget wget-ssl tar unzip) hidden
#
# 【グローバルオプション】
# debug_log() 例：debug_log "INFO" 
# get_message() 例：get_message "MSG_RUNNING_UPDATE"
# color() 例：color red
#
# 【オプション】※順不同で適用可
# - yn         : インストール前に確認する（デフォルト: 確認なし）
# - swap       : スワップを設定する（デフォルト：なし）
# - hidden     : 既にインストール済みの場合、"パッケージ xxx はすでにインストールされています" のメッセージを非表示にする（デフォルト: 表示）
# - clean      : ビルド作業に利用したキャッシュ、ファイルのリムーブ（デフォルト: なし）
#
# 【仕様】
# - ${CACHE_DIR}/downloader.ch フォーマット：opkg もしくは apk
# - ${CACHE_DIR}/openwrt.ch フォーマット例：24.10.0 や　23.05.4　など
# - ${CACHE_DIR}/architecture.ch フォーマット例：armv7l　など
# - ${BASE_DIR}/messages.db（JP/US 対応） フォーマット例：US|MSG_UNDER_TEST=👽 Under test
# - ${BASE_DIR}/custom-package.db （INI形式）
#
# 【使用例】
# - install_build uconv                  → インストール（確認なし）
# - install_build uconv yn               → インストール（確認あり）
# - install_build uconv yn hidden        → インストール（確認あり、既にインストール済みの場合のメッセージは非表示）
# - install_build uconv swap=1024 swap=force
#
#
# 【custom-package.dbの記述例】
# [luci-app-temp-status] 
# source_url = https://github.com/gSpotx2f/luci-app-temp-status.git
# ver_21.02.install_package = git, make, gcc, autoconf, automake, lua, luci-lib-nixio, luci-lib-jsonc
# ver_21.02.build_command = make package/luci-app-temp-status/compile
# ver_19.07.install_package = git, make, gcc, autoconf, automake, lua, luci-lib-nixio
# ver_19.07.build_command = make package/luci-app-temp-status/compile V=99
#########################################################################
setup_swap() {
    local swap_size=""
    local force_enable="no"
    local disable_swap="no"

    # **オプションの処理**
    for arg in "$@"; do
        case "$arg" in
            size=*) swap_size="${arg#size=}" ;;  # size=512 などの指定
            force) force_enable="yes" ;;  # スワップ強制再設定
            disable) disable_swap="yes" ;;  # スワップ無効化
        esac
    done

    # **スワップを無効化する処理**
    if [ "$disable_swap" = "yes" ]; then
        cleanup_swap
        debug_log "INFO" "Swap has been disabled as per request."
        return 0
    fi

    local RAM_TOTAL_MB
    RAM_TOTAL_MB=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)

    # **空き容量を確認**
    local STORAGE_FREE_MB
    STORAGE_FREE_MB=$(df -m /overlay | awk 'NR==2 {print $4}')  # MB単位の空き容量

    # **df コマンドの結果が数値であることを確認**
    if ! echo "$STORAGE_FREE_MB" | grep -q '^[0-9]\+$'; then
        STORAGE_FREE_MB=0
        debug_log "ERROR" "Invalid storage free size. Skipping swap setup."
        return 1
    fi

    # **スワップサイズの決定**
    local ZRAM_SIZE_MB
    if [ -n "$swap_size" ]; then
        ZRAM_SIZE_MB="$swap_size"
    else
        if [ "$RAM_TOTAL_MB" -lt 512 ]; then
            ZRAM_SIZE_MB=512
        elif [ "$RAM_TOTAL_MB" -lt 1024 ]; then
            ZRAM_SIZE_MB=256
        else
            ZRAM_SIZE_MB=128
        fi

        # **ストレージの空きが十分ならスワップサイズを最大 1024MB まで増やす**
        if [ "$STORAGE_FREE_MB" -ge 1024 ]; then
            ZRAM_SIZE_MB=1024
        elif [ "$STORAGE_FREE_MB" -ge 512 ] && [ "$ZRAM_SIZE_MB" -lt 512 ]; then
            ZRAM_SIZE_MB=512
        fi
    fi

    debug_log "INFO" "RAM: ${RAM_TOTAL_MB}MB, Setting zram size to ${ZRAM_SIZE_MB}MB"

    # **環境変数を登録 (`CUSTOM_*` に統一)**
    export CUSTOM_ZRAM_SIZE="$ZRAM_SIZE_MB"

    debug_log "INFO" "Exported: CUSTOM_ZRAM_SIZE=${CUSTOM_ZRAM_SIZE}"

    if ! echo "$STORAGE_FREE_MB" | grep -q '^[0-9]\+$'; then
        STORAGE_FREE_MB=0
        debug_log "ERROR" "Insufficient storage for swap (${STORAGE_FREE_MB}MB free). Skipping swap setup."
        return 1  # **ストレージ不足なら即終了** 
    fi

    # **既存スワップの処理**
    if grep -q 'zram' /proc/swaps; then
        if [ "$force_enable" = "yes" ]; then
            debug_log "INFO" "Force enabling swap. Cleaning up existing swap..."
            cleanup_swap
        else
            debug_log "INFO" "Swap is already enabled. Skipping setup."
            return 0
        fi
    fi

    # **zswap (zram-swap) のインストール**
    install_package zram-swap yn hidden

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

cleanup_swap() {
    debug_log "INFO" "Cleaning up zram-swap..."

    # **スワップが有効か確認**
    if grep -q 'zram' /proc/swaps; then
        swapoff /dev/zram0
        if [ $? -eq 0 ]; then
            debug_log "INFO" "Swap successfully disabled."
        else
            debug_log "ERROR" "Failed to disable swap!"
            return 1
        fi
    else
        debug_log "INFO" "No active swap found."
    fi

    # **zram0 の削除**
    if [ -e "/sys/class/zram-control/hot_remove" ]; then
        echo 1 > /sys/class/zram-control/hot_remove
        debug_log "INFO" "zram device removed."
    else
        debug_log "WARN" "zram-control not found. Skipping hot remove."
    fi

    # **カーネルモジュールを削除**
    if lsmod | grep -q "zram"; then
        rmmod zram
        if [ $? -eq 0 ]; then
            debug_log "INFO" "Removed kmod-zram module."
        else
            debug_log "ERROR" "Failed to remove kmod-zram!"
        fi
    else
        debug_log "INFO" "zram module not loaded."
    fi

    debug_log "INFO" "zram-swap cleanup completed."
}

cleanup_build() {
    debug_log "INFO" "Cleaning up build directory..."

    # `.ipk` 以外を削除（BusyBox find の制約を回避）
    # `.ipk` 以外のファイルを削除
    find "$BUILD_DIR" -type f ! -name "*.ipk" -exec rm -f {} +

    # 空のディレクトリを削除（-empty を使わずに実行）
    find "$BUILD_DIR" -type d -exec rmdir {} 2>/dev/null \;


    debug_log "INFO" "Build directory cleanup completed."
}

cleanup_build_tools() {
    debug_log "INFO" "Removing build tools to free up space..."

    # **インストールしたビルドツールのリスト**
    local build_tools="make gcc git libtool-bin automake pkg-config zlib-dev libncurses-dev curl libxml2 libxml2-dev autoconf automake bison flex perl patch wget wget-ssl tar unzip"

    # **現在インストールされているパッケージを取得**
    local installed_tools
    installed_tools=$(opkg list-installed | awk '{print $1}')

    # **削除対象リストを作成**
    local remove_list=""
    for tool in $build_tools; do
        if echo "$installed_tools" | grep -q "^$tool$"; then
            remove_list="$remove_list $tool"
        else
            debug_log "DEBUG" "Package not installed: $tool (Skipping)"
        fi
    done

    # **一括で削除実行**
    if [ -n "$remove_list" ]; then
        debug_log "INFO" "Removing packages: $remove_list"
        opkg remove $remove_list
    else
        debug_log "DEBUG" "No build tools found to remove."
    fi

    debug_log "INFO" "Build tools cleanup completed."
}

build_package_db() {
    local package_name="$1"
    local openwrt_version=""

    # **OpenWrtバージョンの取得**
    if [ ! -f "${CACHE_DIR}/openwrt.ch" ]; then
        debug_log "ERROR" "OpenWrt version file not found: ${CACHE_DIR}/openwrt.ch"
        return 1
    fi

    openwrt_version=$(cat "${CACHE_DIR}/openwrt.ch" 2>/dev/null)
    if [ -z "$openwrt_version" ]; then
        debug_log "ERROR" "Failed to retrieve OpenWrt version from ${CACHE_DIR}/openwrt.ch"
        return 1
    fi

    debug_log "DEBUG" "Using OpenWrt version: $openwrt_version for package: $package_name"

    # **パッケージ名を正規化（"-"を削除）**
    local normalized_name
    normalized_name=$(echo "$package_name" | sed 's/-//g')
    if [ -z "$normalized_name" ]; then
        debug_log "ERROR" "Invalid package name: $package_name"
        return 1
    fi

    # **パッケージセクションをキャッシュへ保存**
    local package_section_cache="${CACHE_DIR}/package_section.ch"
    if [ ! -f "${BASE_DIR}/custom-package.db" ]; then
        debug_log "ERROR" "custom-package.db not found: ${BASE_DIR}/custom-package.db"
        return 1
    fi

    awk -v pkg="\\[$normalized_name\\]" '
        $0 ~ pkg {flag=1; next}
        flag && /^\[/ {flag=0}
        flag {print}
    ' "${BASE_DIR}/custom-package.db" > "$package_section_cache"

    if [ ! -s "$package_section_cache" ]; then
        debug_log "ERROR" "Package not found in database: $package_name ($normalized_name)"
        return 1
    fi

    debug_log "DEBUG" "Package section cached: $package_section_cache"

    # **最適なバージョンを決定**
    local target_version=""
    target_version=$(grep -o 'ver_[0-9.]*' "$package_section_cache" | sed 's/ver_//' | sort -Vr | head -n1)

    if [ -z "$target_version" ]; then
        debug_log "ERROR" "No compatible version found for $package_name on OpenWrt $openwrt_version"
        debug_log "DEBUG" "Available versions: $(grep -o 'ver_[0-9.]*' "$package_section_cache")"
        return 1
    fi

    debug_log "DEBUG" "Using version: $target_version"

    # **ソースURLを取得**
    local source_url=""
    source_url=$(awk -F '=' -v key="source_url" '$1 ~ key {print $2}' "$package_section_cache" 2>/dev/null)

    if [ -z "$source_url" ]; then
        debug_log "ERROR" "No source_url found for $package_name"
        debug_log "DEBUG" "Package section content:\n$(cat "$package_section_cache")"
        return 1
    fi

    debug_log "INFO" "Source URL: $source_url"

    # **ビルドコマンドを取得**
    local build_command=""
    build_command=$(awk -F '=' -v ver="ver_${target_version}.build_command" '$1 ~ ver {print $2}' "$package_section_cache" 2>/dev/null)

    if [ -z "$build_command" ]; then
        debug_log "ERROR" "No build command found for $package_name (version: $target_version)"
        debug_log "DEBUG" "Package section content:\n$(cat "$package_section_cache")"
        return 1
    fi

    debug_log "INFO" "Build command: $build_command"

    # **キャッシュへ保存**
    if ! echo "$build_command" > "${CACHE_DIR}/build_command.ch"; then
        debug_log "ERROR" "Failed to write build command to cache: ${CACHE_DIR}/build_command.ch"
        return 1
    fi

    return 0
}

install_build() {
    local confirm_install="no"
    local swap_enable="no"
    local swap_size=""
    local swap_force="no"
    local hidden="no"
    local cleanup_after_build="no"
    local package_name=""

    # **オプションの処理**
    for arg in "$@"; do
        case "$arg" in
            yn) confirm_install="yes" ;;
            swap) swap_enable="yes" ;;  # スワップを有効化
            swap=*)  # スワップサイズ指定または force
                swap_enable="yes"
                if echo "$arg" | grep -q "force"; then
                    swap_force="yes"
                else
                    swap_size="${arg#swap=}"
                fi
                ;;
            hidden) hidden="yes" ;;
            clean) cleanup_after_build="yes" ;;
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
        echo "$(get_message 'MSG_ERROR_NO_PACKAGE_NAME')"
        debug_log "ERROR" "$(get_message 'MSG_ERROR_NO_PACKAGE_NAME')"
        return 1
    fi

    # **スワップを設定（オプションが有効な場合）**
    local swap_status=0
    if [ "$swap_enable" = "yes" ]; then
        if [ -n "$swap_size" ]; then
            echo "$(get_message 'MSG_SWAP_SETUP' | sed "s/{size}/$swap_size/")"
            setup_swap "size=$swap_size"
        elif [ "$swap_force" = "yes" ]; then
            echo "$(get_message 'MSG_SWAP_FORCE')"
            setup_swap "force"
        else
            echo "$(get_message 'MSG_SWAP_DEFAULT')"
            setup_swap
        fi

        # **スワップの設定が失敗した場合はエラーログを出して終了**
        swap_status=$?
        if [ "$swap_status" -ne 0 ]; then
            echo "$(get_message 'MSG_SWAP_FAILED')"
            debug_log "ERROR" "Swap setup failed with status $swap_status"
            return 1
        fi
    fi

    # **インストールの確認 (YNオプションが有効な場合のみ)**
    if [ "$confirm_install" = "yes" ]; then
        while true; do
            echo "$(get_message 'MSG_CONFIRM_INSTALL' | sed "s/{pkg}/$package_name/")"
            echo -n "$(get_message 'MSG_CONFIRM_ONLY_YN')"
            read -r yn
            case "$yn" in
                [Yy]*) break ;;  # Yes → インストール続行
                [Nn]*) return 1 ;; # No → キャンセル
                *) echo "$(get_message 'MSG_INVALID_INPUT')" ;;
            esac
        done
    fi

    # **ビルド環境の準備**
    echo "$(get_message 'MSG_BUILD_ENV_SETUP')"
    local build_tools="make gcc git libtool-bin automake pkg-config zlib-dev libncurses-dev curl libxml2 libxml2-dev autoconf automake bison flex perl patch wget wget-ssl tar unzip"

    for tool in $build_tools; do
        install_package "$tool" hidden
    done

    # **パッケージ情報の取得**
    build_package_db "$package_name"

    # **ビルド開始**
    echo "$(get_message 'MSG_BUILD_START' | sed "s/{pkg}/$package_name/")"
    start_spinner "$(get_message 'MSG_BUILD_RUNNING')"
    local start_time=$(date +%s)
    if ! eval "$build_command"; then
        stop_spinner
        echo "$(get_message 'MSG_BUILD_FAIL' | sed "s/{pkg}/$package_name/")"
        debug_log "ERROR" "$(get_message 'MSG_BUILD_FAIL' | sed "s/{pkg}/$package_name/")"
        return 1
    fi
    local end_time=$(date +%s)
    local build_time=$((end_time - start_time))
    stop_spinner  # スピナー停止

    echo "$(get_message 'MSG_BUILD_SUCCESS' | sed "s/{pkg}/$package_name/" | sed "s/{time}/$build_time/")"
    debug_log "DEBUG" "Build time for $package_name: $build_time seconds"

    # **クリーンアップ（オプションが指定された場合のみ）**
    if [ "$cleanup_after_build" = "yes" ]; then
        echo "$(get_message 'MSG_CLEANUP_START')"
        cleanup_build_tools
        echo "$(get_message 'MSG_CLEANUP_DONE')"
    fi

    echo "$(get_message 'MSG_BUILD_COMPLETE' | sed "s/{pkg}/$package_name/")"
}
