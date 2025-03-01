#!/bin/sh

SCRIPT_VERSION="2025.03.01-00-0"

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
# 4️⃣ ビルド作業
# 7️⃣ custom-package.db の適用（ビルド用設定：DBの記述に従う）
# 5️⃣ インストールの実行（.ipk）
# 7️⃣ package.db の適用（ビルド後の設定適用がある場合：DBの記述に従う）
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
#
# 【custom-package.dbの記述例】
#  [luci-app-temp-status] 
#  source_url = https://github.com/gSpotx2f/luci-app-temp-status.git
#  ver_21.02.install_package = git, make, gcc, autoconf, automake, lua, luci-lib-nixio, luci-lib-jsonc
#  ver_21.02.build_command = make package/luci-app-temp-status/compile
#  ver_19.07.install_package = git, make, gcc, autoconf, automake, lua, luci-lib-nixio
#  ver_19.07.build_command = make package/luci-app-temp-status/compile V=99
#########################################################################
setup_swap() {
    local RAM_TOTAL_MB
    RAM_TOTAL_MB=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)

    # **空き容量を確認**
    local STORAGE_FREE_MB
    STORAGE_FREE_MB=$(df -m /overlay | awk 'NR==2 {print $4}')  # MB単位の空き容量
    
    # **スワップサイズを RAM とストレージの両方で決定**
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

    debug_log "INFO" "RAM: ${RAM_TOTAL_MB}MB, Setting zram size to ${ZRAM_SIZE_MB}MB"

   # **環境変数を登録 (`CUSTOM_*` に統一)**
    export CUSTOM_ZRAM_SIZE="$ZRAM_SIZE_MB"

    debug_log "INFO" "Exported: CUSTOM_ZRAM_SIZE=${CUSTOM_ZRAM_SIZE}"

    if ! echo "$STORAGE_FREE_MB" | grep -q '^[0-9]\+$'; then
        STORAGE_FREE_MB=0
        debug_log "ERROR" "Insufficient storage for swap (${STORAGE_FREE_MB}MB free). Skipping swap setup."
        return 1  # **ストレージ不足なら即終了** 
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

    # **スワップを無効化**
    swapoff /dev/zram0

    # **zram0 を削除**
    echo 1 > /sys/class/zram-control/hot_remove

    # **`kmod-zram` がロードされているなら `rmmod`**
    if lsmod | grep -q "zram"; then
        rmmod zram
        debug_log "INFO" "Removed kmod-zram module."
    fi

    debug_log "INFO" "zram-swap successfully removed."
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

build_package_db() {
    local package_name="$1"
    local openwrt_version=""

    # OpenWrtバージョンの取得
    if [ -f "${CACHE_DIR}/openwrt.ch" ]; then
        openwrt_version=$(cat "${CACHE_DIR}/openwrt.ch")
    else
        debug_log "ERROR" "OpenWrt version not found!"
        return 1
    fi

    debug_log "DEBUG" "Using OpenWrt version: $openwrt_version for package: $package_name"

    # **パッケージ名を正規化（"-"を削除）**
    local normalized_name
    normalized_name=$(echo "$package_name" | sed 's/-//g')

    # **パッケージセクションをキャッシュへ保存**
    local package_section_cache="${CACHE_DIR}/package_section.ch"
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

    # **バージョンリストを取得**
    local version_list_cache="${CACHE_DIR}/version_list.ch"
    grep -o 'ver_[0-9.]*' "$package_section_cache" | sed 's/ver_//' | sort -Vr > "$version_list_cache"

    if [ ! -s "$version_list_cache" ]; then
        debug_log "ERROR" "No versions found for package: $package_name"
        return 1
    fi

    debug_log "DEBUG" "Available versions cached: $version_list_cache"

    # **最も近い下位互換バージョンを探す**
    local target_version=""
    while read -r version; do
        if [ "$(echo -e "$version\n$openwrt_version" | sort -Vr | head -n1)" = "$openwrt_version" ]; then
            target_version="$version"
            break
        fi
    done < "$version_list_cache"

    if [ -z "$target_version" ]; then
        debug_log "ERROR" "No compatible version found for $package_name on OpenWrt $openwrt_version"
        return 1
    fi

    debug_log "DEBUG" "Using version: $target_version"

    # **ビルドコマンドを取得**
    local build_command=""
    build_command=$(awk -F '=' -v ver="ver_${target_version}.build_command" '$1 ~ ver {print $2}' "$package_section_cache")

    if [ -z "$build_command" ]; then
        debug_log "ERROR" "No build command found for package: $package_name (version: $target_version)"
        return 1
    fi

    debug_log "INFO" "Build command found: $build_command"

    # **ビルドコマンドをキャッシュに保存**
    echo "$build_command" > "${CACHE_DIR}/build_command.ch"

    # **デバッグログ: 置換後のビルドコマンド**
    debug_log "DEBUG" "Final build command: $(cat "${CACHE_DIR}/build_command.ch")"

    return 0
}

install_build() {
    local confirm_install="no"
    local hidden="no"
    local cleanup_after_build="no"
    local package_name=""

    # **オプションの処理**
    for arg in "$@"; do
        case "$arg" in
            yn) confirm_install="yes" ;;
            hidden) hidden="yes" ;;
            clean) cleanup_after_build="yes" ;;  # `clean` が指定されたら cleanup_build_tools を実行
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

    setup_swap || { debug_log "ERROR" "$(get_message 'MSG_ERR_INSUFFICIENT_SWAP')"; return 1; }

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
    local build_tools="make gcc git libtool-bin automake pkg-config zlib-dev libncurses-dev curl libxml2 libxml2-dev autoconf automake bison flex perl patch wget wget-ssl tar unzip"
                      
    for tool in $build_tools; do
        install_package "$tool" hidden
    done

    build_package_db "$package_name"
    
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

    # **ビルド後の .ipk 確認**
    ipk_files=$(find "${BASE_DIR}/bin/packages/" -type f -name "*.ipk" 2>/dev/null)

    # **ビルドディレクトリのクリーンアップ**
    # cleanup_build

    # **`clean` オプションが指定された場合のみ、ビルドツールを削除**
    if [ "$cleanup_after_build" = "yes" ]; then
        debug_log "INFO" "Cleaning up build tools after build..."
        cleanup_build_tools
    fi

    # **スワップを削除する場合（必要ならコメント解除）**
    # cleanup_swap

    # **ビルド完了後のメッセージ**
    echo "$(get_message "MSG_BUILD_SUCCESS" | sed "s/{pkg}/$package_name/")"
    debug_log "DEBUG" "Successfully built and installed package: $package_name"
}
