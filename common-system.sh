#!/bin/sh

SCRIPT_VERSION="2025.04.07-00-00"

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX準拠シェルスクリプト
# 🚀 最終更新日: 2025-03-14
#
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 互換性: OpenWrt >= 19.07 (24.10.0でテスト済み)
#
# ⚠️ 重要な注意事項:
# OpenWrtは**Almquistシェル(ash)**のみを使用し、
# **Bourne-Again Shell(bash)**とは互換性がありません。
#
# 📢 POSIX準拠ガイドライン:
# ✅ 条件には `[[` ではなく `[` を使用する
# ✅ バックティック ``command`` ではなく `$(command)` を使用する
# ✅ `let` の代わりに `$(( ))` を使用して算術演算を行う
# ✅ 関数は `function` キーワードなしで `func_name() {}` と定義する
# ✅ 連想配列は使用しない (`declare -A` はサポートされていない)
# ✅ ヒアストリングは使用しない (`<<<` はサポートされていない)
# ✅ `test` や `[[` で `-v` フラグを使用しない
# ✅ `${var:0:3}` のようなbash特有の文字列操作を避ける
# ✅ 配列はできるだけ避ける（インデックス配列でも問題が発生する可能性がある）
# ✅ `read -p` の代わりに `printf` の後に `read` を使用する
# ✅ フォーマットには `echo -e` ではなく `printf` を使用する
# ✅ プロセス置換 `<()` や `>()` を避ける
# ✅ 複雑なif/elifチェーンよりもcaseステートメントを優先する
# ✅ コマンドの存在確認には `which` や `type` ではなく `command -v` を使用する
# ✅ スクリプトをモジュール化し、小さな焦点を絞った関数を保持する
# ✅ 複雑なtrapの代わりに単純なエラー処理を使用する
# ✅ スクリプトはbashだけでなく、明示的にash/dashでテストする
#
# 🛠️ OpenWrt向けにシンプル、POSIX準拠、軽量に保つ！
### =========================================================

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
ARCHITECTURE="${CACHE_DIR}/architecture.ch"
OSVERSION="${CACHE_DIR}/osversion.ch"
PACKAGE_MANAGER="${CACHE_DIR}/package_manager.ch"
PACKAGE_EXTENSION="${CACHE_DIR}/extension.ch"

# ロケーション情報取得用タイムアウト設定（秒）
LOCATION_API_TIMEOUT="${LOCATION_API_TIMEOUT:-5}"
# リトライ回数の設定
LOCATION_API_MAX_RETRIES="${LOCATION_API_MAX_RETRIES:-5}"

USER_AGENT="${USER_AGENT:-curl/7.74.0}"

# キャッシュファイルの存在と有効性を確認する関数
check_location_cache() {
    local cache_language="${CACHE_DIR}/language.ch"
    local cache_luci="${CACHE_DIR}/luci.ch"
    local cache_timezone="${CACHE_DIR}/timezone.ch"
    local cache_zonename="${CACHE_DIR}/zonename.ch"
    local cache_message="${CACHE_DIR}/message.ch"
    
    debug_log "DEBUG" "Checking location cache files"
    
    # すべての必要なキャッシュファイルが存在するか確認
    if [ -f "$cache_language" ] && [ -f "$cache_luci" ] && [ -f "$cache_timezone" ] && [ -f "$cache_zonename" ] && [ -f "$cache_message" ]; then
        # すべてのファイルの内容が空でないか確認
        if [ -s "$cache_language" ] && [ -s "$cache_luci" ] && [ -s "$cache_timezone" ] && [ -s "$cache_zonename" ] && [ -s "$cache_message" ]; then
            debug_log "DEBUG" "Valid location cache files found"
            return 0  # キャッシュ有効
        else
            debug_log "DEBUG" "One or more cache files are empty"
        fi
    else
        debug_log "DEBUG" "One or more required cache files are missing"
    fi
    
    return 1  # キャッシュ無効または不完全
}

# 📌 デバイスアーキテクチャの取得
# 戻り値: アーキテクチャ文字列 (例: "mips_24kc", "arm_cortex-a7", "x86_64")
get_device_architecture() {
    local arch=""
    local target=""
    
    # OpenWrtから詳細なアーキテクチャ情報を取得
    if [ -f "/etc/openwrt_release" ]; then
        target=$(grep "DISTRIB_TARGET" /etc/openwrt_release | cut -d "'" -f 2)
        arch=$(grep "DISTRIB_ARCH" /etc/openwrt_release | cut -d "'" -f 2)
    fi
    echo "$target $arch"
}

# 📌 OSタイプとバージョンの取得
# 戻り値: OSタイプとバージョン文字列 (例: "OpenWrt 24.10.0", "Alpine 3.18.0")
get_os_info() {
    local os_type=""
    local os_version=""
    
    # OpenWrtのチェック
    if [ -f "/etc/openwrt_release" ]; then
        os_type="OpenWrt"
        os_version=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2)
    fi
    
    echo "$os_type $os_version"
}

# 📌 パッケージマネージャーの検出
# 戻り値: パッケージマネージャー情報 (例: "opkg", "apk")
get_package_manager() {
    if command -v opkg >/dev/null 2>&1; then
        echo "opkg"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
} 

# 📌 利用可能な言語パッケージの取得
# 戻り値: "language_code:language_name"形式の利用可能な言語パッケージのリスト
# 📌 LuCIで利用可能な言語パッケージを検出し、luci.chに保存する関数
get_available_language_packages() {
    local pkg_manager=""
    local lang_packages=""
    local tmp_file="${CACHE_DIR}/lang_packages.tmp"
    local package_cache="${CACHE_DIR}/package_list.ch"
    local luci_cache="${CACHE_DIR}/luci.ch"
    local country_cache="${CACHE_DIR}/country.ch"
    local default_lang="en"
    
    debug_log "DEBUG" "Running get_available_language_packages() to detect LuCI languages"
    
    # パッケージマネージャーの検出
    pkg_manager=$(get_package_manager)
    debug_log "DEBUG" "Using package manager: $pkg_manager"
    
    # package_list.chが存在しない場合はupdate_package_list()を呼び出す
    if [ ! -f "$package_cache" ]; then
        debug_log "DEBUG" "Package list cache not found, calling update_package_list()"
        
        # common-package.shが読み込まれているか確認
        if type update_package_list >/dev/null 2>&1; then
            update_package_list
            debug_log "DEBUG" "Package list updated successfully"
        else
            debug_log "ERROR" "update_package_list() function not available"
        fi
    fi
    
    # package_list.chが存在するか再確認
    if [ ! -f "$package_cache" ]; then
        debug_log "ERROR" "Package list cache still not available after update attempt"
        # デフォルト言語をluci.chに設定
        echo "$default_lang" > "$luci_cache"
        debug_log "DEBUG" "Default language '$default_lang' written to luci.ch"
        return 1
    fi
    
    # LuCI言語パッケージを一時ファイルに格納
    if [ "$pkg_manager" = "opkg" ]; then
        debug_log "DEBUG" "Extracting LuCI language packages from package_list.ch"
        grep "luci-i18n-base-" "$package_cache" > "$tmp_file" || touch "$tmp_file"
        
        # 言語コードを抽出
        lang_packages=$(sed -n 's/luci-i18n-base-\([a-z][a-z]\(-[a-z][a-z]\)\?\) .*/\1/p' "$tmp_file" | sort -u)
        debug_log "DEBUG" "Available LuCI languages: $lang_packages"
    else
        debug_log "ERROR" "Unsupported package manager: $pkg_manager"
        touch "$tmp_file"
    fi
    
    # country.chからLuCI言語コード（$4）を取得
    local preferred_lang=""
    if [ -f "$country_cache" ]; then
        preferred_lang=$(awk '{print $4}' "$country_cache")
        debug_log "DEBUG" "Preferred language from country.ch: $preferred_lang"
    else
        debug_log "WARNING" "Country cache not found, using default language"
    fi
    
    # LuCI言語の決定ロジック
    local selected_lang="$default_lang"  # デフォルトは英語
    
    if [ -n "$preferred_lang" ]; then
        if [ "$preferred_lang" = "xx" ]; then
            # xxの場合はそのまま使用
            selected_lang="xx"
            debug_log "DEBUG" "Using special language code: xx (no localization)"
        elif echo "$lang_packages" | grep -q "^$preferred_lang$"; then
            # country.chの言語コードがパッケージリストに存在する場合
            selected_lang="$preferred_lang"
            debug_log "DEBUG" "Using preferred language: $selected_lang"
        else
            debug_log "DEBUG" "Preferred language not available, using default: $default_lang"
        fi
    fi
    
    # luci.chに書き込み
    echo "$selected_lang" > "$luci_cache"
    debug_log "DEBUG" "Selected LuCI language '$selected_lang' written to luci.ch"
    
    # 一時ファイル削除
    rm -f "$tmp_file"
    
    # 利用可能な言語リストを返す
    echo "$lang_packages"
    return 0
}

# タイムゾーン情報を取得（例: JST-9）
get_timezone_info() {
    local timezone=""

    # UCI（OpenWrt）設定から直接取得
    if command -v uci >/dev/null 2>&1; then
        timezone="$(uci get system.@system[0].timezone 2>/dev/null)"
    fi

    echo "$timezone"
}

# ゾーン名を取得（例: Asia/Tokyo）
get_zonename_info() {
    local zonename=""

    # UCI（OpenWrt）から取得
    if command -v uci >/dev/null 2>&1; then
        zonename="$(uci get system.@system[0].zonename 2>/dev/null)"
    fi

    echo "$zonename"
}

# USBデバイス検出
# USBデバイス検出関数
get_usb_devices() {
    # キャッシュファイルパスの設定
    USB_DEVICE="${CACHE_DIR}/usbdevice.ch"
    
    # USBデバイスの存在確認
    if [ -d "/sys/bus/usb/devices" ] && ls /sys/bus/usb/devices/[0-9]*-[0-9]*/idVendor >/dev/null 2>&1; then
        # USBデバイスが存在する場合
        debug_log "DEBUG" "USB device detected"
        echo "detected" > "${CACHE_DIR}/usbdevice.ch"
    else
        # USBデバイスが存在しない場合
        debug_log "DEBUG" "No USB devices detected"
        echo "not_detected" > "${CACHE_DIR}/usbdevice.ch"
    fi
}

# 📌 デバイスの国情報の取得
# 戻り値: システム設定とデータベースに基づく組み合わせた国情報
# 戻り値: システム設定とデータベースに基づく2文字の国コード
# 戻り値: システム設定から推定される2文字の国コード（JP、USなど）
get_country_info() {
    local current_lang=""
    local current_timezone=""
    local country_code=""
    local country_db="${BASE_DIR}/country.db"
    
    # 現在のシステム言語を取得
    if command -v uci >/dev/null 2>&1; then
        current_lang=$(uci get luci.main.lang 2>/dev/null)
    fi
    
    # 現在のタイムゾーンを取得
    current_timezone=$(get_timezone_info)
    
    # country.dbが存在する場合、情報を照合
    if [ -f "$country_db" ] && [ -n "$current_lang" ]; then
        # まず言語コードで照合（5列目の国コードを取得）
        country_code=$(awk -v lang="$current_lang" '$4 == lang {print $5; exit}' "$country_db")
        
        # 言語で一致しない場合、タイムゾーンで照合（同じく5列目）
        if [ -z "$country_code" ] && [ -n "$current_timezone" ]; then
            country_code=$(awk -v tz="$current_timezone" '$0 ~ tz {print $5; exit}' "$country_db")
        fi
        
        # 値が取得できた場合は返す
        if [ -n "$country_code" ]; then
            [ "$DEBUG_MODE" = "true" ] && printf "DEBUG: Found country code from database: %s\n" "$country_code" >&2
            echo "$country_code"
            return 0
        fi
    fi
    
    # 一致が見つからないか、country.dbがない場合は空を返す
    [ "$DEBUG_MODE" = "true" ] && printf "DEBUG: No country code found in database\n" >&2
    echo ""
    return 1
}

# パッケージマネージャー情報を検出・保存する関数
detect_and_save_package_manager() {
    if [ ! -f "${CACHE_DIR}/package_manager.ch" ]; then
        if command -v opkg >/dev/null 2>&1; then
            echo "opkg" > "${CACHE_DIR}/package_manager.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            PACKAGE_MANAGER="opkg"  # グローバル変数を設定
            debug_log "DEBUG" "Detected and saved package manager: opkg"
        elif command -v apk >/dev/null 2>&1; then
            echo "apk" > "${CACHE_DIR}/package_manager.ch"
            echo "apk" > "${CACHE_DIR}/extension.ch"
            PACKAGE_MANAGER="apk"  # グローバル変数を設定
            debug_log "DEBUG" "Detected and saved package manager: apk" 
        else
            # デフォルトとしてopkgを使用
            echo "opkg" > "${CACHE_DIR}/package_manager.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            PACKAGE_MANAGER="opkg"  # グローバル変数を設定
            debug_log "WARN" "No package manager detected, using opkg as default"
        fi
    else
        # すでにファイルが存在する場合は、グローバル変数を設定
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/package_manager.ch")
        debug_log "DEBUG" "Loaded package manager from cache: $PACKAGE_MANAGER"
    fi
}

# OpenWrtでシステムのCPUコア数・メモリ・フラッシュ容量を検出しキャッシュに保存する関数
detect_device() {
    # CPUコア数検出
    local cpu_count=1
    if [ -f /proc/cpuinfo ]; then
        cpu_count=$(grep -c "^processor" /proc/cpuinfo)
    fi
    if [ "$cpu_count" -lt 1 ]; then
        cpu_count=1
    fi
    CPU_CORES="$cpu_count"

    # メモリ総量（MB単位）検出
    local memory_total=0
    if [ -f /proc/meminfo ]; then
        memory_total=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    fi
    if [ -z "$memory_total" ] || [ "$memory_total" -lt 1 ]; then
        memory_total=0
    fi
    MEMORY_TOTAL="$memory_total"

    # フラッシュ総容量（MB単位）検出
    # "/" マウントポイントのブロックサイズ
    local flash_total=0
    flash_total=$(df -m / 2>/dev/null | awk 'NR==2{print $2}')
    if [ -z "$flash_total" ] || [ "$flash_total" -lt 1 ]; then
        flash_total=0
    fi
    FLASH_TOTAL="$flash_total"

    # キャッシュ保存
    mkdir -p "$CACHE_DIR" 2>/dev/null
    printf "%s\n" "$cpu_count" > "${CACHE_DIR}/cpu_core.ch"
    printf "%s\n" "$memory_total" > "${CACHE_DIR}/memory_total.ch"
    printf "%s\n" "$flash_total" > "${CACHE_DIR}/flash_total.ch"

    debug_log "DEBUG" "Detected CPU cores: $cpu_count"
    debug_log "DEBUG" "Detected memory total: $memory_total MB"
    debug_log "DEBUG" "Detected flash total: $flash_total MB"
}

# wgetの機能を検出する関数（キャッシュ対応版）
detect_wget_capabilities() {
    local tmp_file="/tmp/wget_test.tmp"
    local capability="basic"
    local redirect_support=0
    local https_support=0
    local cache_file="${CACHE_DIR}/wget_capability.ch"

    # キャッシュファイルがある場合はそれを使用して即時返す
    if [ -f "$cache_file" ]; then
        capability=$(cat "$cache_file")
        echo "$capability"
        return 0
    fi

    debug_log "DEBUG" "Detecting wget capabilities"
    
    # キャッシュディレクトリ確認
    mkdir -p "$CACHE_DIR" 2>/dev/null
    
    # -Lオプション（リダイレクト機能）のサポート検出
    if wget -L --help 2>&1 | grep -q "unrecognized option"; then
        debug_log "DEBUG" "wget does not support -L option (BusyBox detected)"
        redirect_support=0
    else
        debug_log "DEBUG" "wget supports -L option (full wget)"
        redirect_support=1
    fi
    
    # HTTPS直接アクセスのサポート検出（User-Agentを追加）
    if wget --no-check-certificate -q -U "${USER_AGENT}" -O "$tmp_file" "https://location-api-worker.site-u.workers.dev" >/dev/null 2>&1; then
        if [ -s "$tmp_file" ]; then
            debug_log "DEBUG" "wget supports HTTPS connections"
            https_support=1
        else
            debug_log "DEBUG" "wget HTTPS test returned empty file"
            https_support=0
        fi
    else
        debug_log "DEBUG" "wget HTTPS test failed"
        https_support=0
    fi
    
    # 一時ファイルのクリーンアップ
    rm -f "$tmp_file" 2>/dev/null
    
    # 機能に基づいて種類を判定
    if [ $redirect_support -eq 1 ] && [ $https_support -eq 1 ]; then
        capability="full"
    elif [ $https_support -eq 1 ]; then
        capability="https_only"
    else
        capability="basic"
    fi
    
    # 検出結果をキャッシュに保存
    echo "$capability" > "$cache_file"
    debug_log "DEBUG" "wget capability detected and cached: $capability"
    
    echo "$capability"
}

# デバッグヘルパー関数
debug_info() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "===== SYSTEM DEBUG INFO ====="
        echo "Architecture: $(get_device_architecture)"
        echo "OS: $(get_os_info)"
        echo "Package Manager: $(get_package_manager)"
        echo "Current Zonename: $(get_zonename_info)"
        echo "Current Timezone: $(get_timezone_info)"
        echo "==========================="
    fi
}

# メイン処理
common_system_main() {
    detect_device
    get_usb_devices
    detect_and_save_package_manager
}

# スクリプトの実行
common_system_main "$@"
