#!/bin/sh

SCRIPT_VERSION="2025.03.14-01-01"

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
BASE_WGET="${BASE_WGET:-wget --no-check-certificate -q -O}"
# BASE_WGET="${BASE_WGET:-wget -O}"
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

# グローバルIPから国コードを取得する関数
get_country_code() {
    # ローカル変数の定義
    local IP=""
    local country_code=""
    local tmp_file="${CACHE_DIR}/ip_json.tmp"
    
    # まずIPv4の取得を試みる
    debug_log "DEBUG" "Attempting to get IPv4 address"
    IP=$(wget -qO- "https://api.ipify.org" 2>/dev/null)
    
    # IPv4の取得に失敗した場合はIPv6にフォールバック
    if [ -z "$IP" ]; then
        debug_log "DEBUG" "IPv4 retrieval failed, falling back to IPv6"
        IP=$(wget -qO- "https://api64.ipify.org" 2>/dev/null)
    fi

    # デバッグログ
    debug_log "DEBUG" "Global IP address retrieved: $IP"

    # IPが取得できたら国コードを取得
    if [ -n "$IP" ]; then
        debug_log "DEBUG" "Fetching country code for IP: $IP"
        
        # 一時ファイルを使用して応答を保存
        wget -qO "$tmp_file" "http://ip-api.com/json/$IP" 2>/dev/null
        
        # ファイルからデータを読み取り
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            country_code=$(grep -o '"countryCode":"[^"]*' "$tmp_file" | awk -F'"' '{print $4}')
            rm -f "$tmp_file" 2>/dev/null
            
            # 国コードが取得できた場合
            if [ -n "$country_code" ]; then
                debug_log "DEBUG" "Country code retrieved: $country_code"
                # 国コードのみを返す（テキストなし）
                echo "$country_code"
                return 0
            else
                debug_log "DEBUG" "Failed to retrieve country code for IP: $IP"
                return 1
            fi
        else
            debug_log "DEBUG" "Failed to retrieve data from IP-API service"
            rm -f "$tmp_file" 2>/dev/null
            return 1
        fi
    else
        debug_log "DEBUG" "Failed to retrieve global IP address"
        return 1
    fi
}

# グローバルIPからタイムゾーンとゾーンネームを取得する関数
get_zone_code() {
    # ローカル変数の定義
    local IP=""
    local TIMEZONE=""
    local ZONENAME=""
    local tmp_file="${CACHE_DIR}/ip_zone.tmp"
    
    # まずIPv4の取得を試みる
    debug_log "DEBUG" "Attempting to get IPv4 address"
    IP=$(wget -qO- "https://api.ipify.org" 2>/dev/null)
    
    # IPv4の取得に失敗した場合はIPv6にフォールバック
    if [ -z "$IP" ]; then
        debug_log "DEBUG" "IPv4 retrieval failed, falling back to IPv6"
        IP=$(wget -qO- "https://api64.ipify.org" 2>/dev/null)
    fi

    # デバッグログ
    debug_log "DEBUG" "Global IP address retrieved: $IP"

    # IPが取得できたらタイムゾーンとゾーンネームを取得
    if [ -n "$IP" ]; then
        echo "Device's Global IP: $IP"
        debug_log "DEBUG" "Fetching timezone and zone name for IP: $IP"
        
        # 一時ファイルを使用して応答を保存
        wget -qO "$tmp_file" "http://ip-api.com/json/$IP" 2>/dev/null
        
        # ファイルからデータを読み取り
        if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
            # タイムゾーンを抽出
            TIMEZONE=$(grep -o '"timezone":"[^"]*' "$tmp_file" | awk -F'"' '{print $4}')
            
            # IP-APIではZONENAMEは取得できないので、TIMEZONEと同じ値を使用
            ZONENAME="$TIMEZONE"
            
            rm -f "$tmp_file" 2>/dev/null
            
            # タイムゾーンが取得できた場合
            if [ -n "$TIMEZONE" ]; then
                echo "Device's Timezone: $TIMEZONE"
                echo "Device's Zonename: $ZONENAME"
                debug_log "DEBUG" "Timezone retrieved: $TIMEZONE, Zonename: $ZONENAME"
                return 0
            else
                debug_log "DEBUG" "Failed to retrieve timezone for IP: $IP"
                return 1
            fi
        else
            debug_log "DEBUG" "Failed to retrieve data from IP-API service"
            rm -f "$tmp_file" 2>/dev/null
            return 1
        fi
    else
        debug_log "DEBUG" "Failed to retrieve global IP address"
        return 1
    fi
}

# IPアドレスから取得した地域情報を処理する関数
process_location_info() {
    debug_log "DEBUG" "Starting IP-based location information processing"
    
    # 国コードを直接取得（余分なテキストを含まない形式で）
    local country_code=""
    local timezone=""
    local zonename=""
    
    # 国コードの取得
    if command -v get_country_code >/dev/null 2>&1; then
        debug_log "DEBUG" "Calling get_country_code()"
        country_code=$(get_country_code)
        debug_log "DEBUG" "Country code obtained: $country_code"
    else
        debug_log "ERROR" "get_country_code function not available"
        return 1
    fi
    
    # タイムゾーン情報の取得
    if command -v get_zone_code >/dev/null 2>&1; then
        debug_log "DEBUG" "Calling get_zone_code()"
        # get_zone_code の出力から必要な情報を抽出
        local zone_info=$(get_zone_code)
        
        # Device's Timezone: XXX の行からタイムゾーン情報を抽出
        timezone=$(echo "$zone_info" | grep "Device's Timezone:" | awk '{print $3}')
        
        # Device's Zonename: XXX の行からゾーン名情報を抽出
        zonename=$(echo "$zone_info" | grep "Device's Zonename:" | awk '{print $3}')
        
        debug_log "DEBUG" "Timezone obtained: $timezone, Zonename: $zonename"
    else
        debug_log "ERROR" "get_zone_code function not available"
        return 1
    fi
    
    # 国コードが取得できたか確認
    if [ -n "$country_code" ]; then
        debug_log "DEBUG" "Setting country: $country_code"
        
        # country.dbから完全な国情報を検索
        local country_db="${BASE_DIR}/country.db"
        if [ -f "$country_db" ]; then
            local country_data=$(grep -i "^[^ ]* *[^ ]* *[^ ]* *[^ ]* *$country_code" "$country_db")
            
            if [ -n "$country_data" ]; then
                # 国情報を一時ファイルに書き込み
                echo "$country_data" > "${CACHE_DIR}/country.tmp"
                
                # country_write関数に処理を委譲（メッセージ表示スキップ）
                if command -v country_write >/dev/null 2>&1; then
                    debug_log "DEBUG" "Calling country_write with IP detected data"
                    country_write true || {
                        debug_log "ERROR" "Failed to write country data from IP detection"
                        return 1
                    }
                else
                    debug_log "ERROR" "country_write function not available"
                    return 1
                fi
            else
                debug_log "ERROR" "No matching country found in database for code: $country_code"
                return 1
            fi
        else
            debug_log "ERROR" "Country database not found at: $country_db"
            return 1
        fi
    else
        debug_log "ERROR" "Failed to obtain country code"
        return 1
    fi
    
    # タイムゾーン情報が取得できたか確認
    if [ -n "$timezone" ]; then
        debug_log "DEBUG" "Setting timezone: $timezone, zonename: $zonename"
        
        # タイムゾーン文字列の構築
        local timezone_str=""
        if [ -n "$zonename" ] && [ -n "$timezone" ]; then
            timezone_str="${zonename},${timezone}"
        else
            timezone_str="${timezone}"
        fi
        
        # zone_write関数に処理を委譲
        if command -v zone_write >/dev/null 2>&1; then
            debug_log "DEBUG" "Calling zone_write with timezone: $timezone_str"
            zone_write "$timezone_str" || {
                debug_log "ERROR" "Failed to write timezone data from IP detection"
                return 1
            }
        else
            debug_log "ERROR" "zone_write function not available"
            return 1
        fi
    else
        debug_log "ERROR" "Failed to obtain timezone information"
        return 1
    fi
    
    debug_log "DEBUG" "IP-based location information processed successfully"
    return 0
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
        # まず言語コードで照合
        country_info=$(awk -v lang="$current_lang" '$4 == lang {print $0; exit}' "$country_db")
        
        # 言語で一致しない場合、タイムゾーンで照合
        if [ -z "$country_info" ] && [ -n "$current_timezone" ]; then
            country_info=$(awk -v tz="$current_timezone" '$0 ~ tz {print $0; exit}' "$country_db")
        fi
        
        # まだ一致しない場合は空を返す
        if [ -n "$country_info" ]; then
            echo "$country_info"
            return 0
        fi
    fi
    
    # 一致が見つからないか、country.dbがない場合は空を返す
    echo ""
    return 1
}

# デバイス情報キャッシュを初期化・保存する関数
init_device_cache() {
   
    # アーキテクチャ情報の保存
    if [ ! -f "${CACHE_DIR}/architecture.ch" ]; then
        local arch
        arch=$(uname -m)
        echo "$arch" > "${CACHE_DIR}/architecture.ch"
        debug_log "DEBUG" "Created architecture cache: $arch"
    fi

    # OSバージョン情報の保存
    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        local version=""
        # OpenWrtバージョン取得
        if [ -f "/etc/openwrt_release" ]; then
            # ファイルからバージョン抽出
            version=$(grep -E "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2)
            echo "$version" > "${CACHE_DIR}/osversion.ch"
            debug_log "DEBUG" "Created OS version cache: $version"
        else
            echo "unknown" > "${CACHE_DIR}/osversion.ch"
            echo "WARN: Could not determine OS version"
        fi
    fi
 
    return 0
}

# パッケージマネージャー情報を検出・保存する関数
detect_and_save_package_manager() {
    if [ ! -f "${CACHE_DIR}/package_manager.ch" ]; then
        if command -v opkg >/dev/null 2>&1; then
            echo "opkg" > "${CACHE_DIR}/package_manager.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            debug_log "DEBUG" "Detected and saved package manager: opkg"
        elif command -v apk >/dev/null 2>&1; then
            echo "apk" > "${CACHE_DIR}/package_manager.ch"
            echo "apk" > "${CACHE_DIR}/extension.ch"
            debug_log "DEBUG" "Detected and saved package manager: apk"
        else
            # デフォルトとしてopkgを使用
            echo "opkg" > "${CACHE_DIR}/package_manager.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            echo "WARN: No package manager detected, using opkg as default"
        fi
    fi
}

# 端末の表示能力を検出する関数
detect_terminal_capability() {
    # 環境変数による明示的指定を最優先
    if [ -n "$AIOS_BANNER_STYLE" ]; then
        debug_log "DEBUG" "Using environment override: AIOS_BANNER_STYLE=$AIOS_BANNER_STYLE"
        echo "$AIOS_BANNER_STYLE"
        return 0
    fi
    
    # キャッシュが存在する場合はそれを使用
    if [ -f "$CACHE_DIR/banner_style.ch" ]; then
        CACHED_STYLE=$(cat "$CACHE_DIR/banner_style.ch")
        debug_log "DEBUG" "Using cached banner style: $CACHED_STYLE"
        echo "$CACHED_STYLE"
        return 0
    fi
    
    # デフォルトスタイル（安全なASCII）
    STYLE="ascii"
    
    # ロケールの確認
    LOCALE_CHECK=""
    if [ -n "$LC_ALL" ]; then
        LOCALE_CHECK="$LC_ALL"
    elif [ -n "$LANG" ]; then
        LOCALE_CHECK="$LANG"
    fi
    
    debug_log "DEBUG" "Checking locale: $LOCALE_CHECK"
    
    # UTF-8検出
    if echo "$LOCALE_CHECK" | grep -i "utf-\?8" >/dev/null 2>&1; then
        debug_log "DEBUG" "UTF-8 locale detected"
        STYLE="unicode"
    else
        debug_log "DEBUG" "Non-UTF-8 locale or unset locale"
    fi
    
    # ターミナル種別の確認
    if [ -n "$TERM" ]; then
        debug_log "DEBUG" "Checking terminal type: $TERM"
        case "$TERM" in
            *-256color|xterm*|rxvt*|screen*)
                STYLE="unicode"
                debug_log "DEBUG" "Advanced terminal detected"
                ;;
            dumb|vt100|linux)
                STYLE="ascii"
                debug_log "DEBUG" "Basic terminal detected"
                ;;
        esac
    fi
    
    # OpenWrt固有の検出
    if [ -f "/etc/openwrt_release" ]; then
        debug_log "DEBUG" "OpenWrt environment detected"
        # OpenWrtでの追加チェック（必要に応じて）
    fi
    
    # スタイルをキャッシュに保存（ディレクトリが存在する場合）
    if [ -d "$CACHE_DIR" ]; then
        echo "$STYLE" > "$CACHE_DIR/banner_style.ch"
        debug_log "DEBUG" "Banner style saved to cache: $STYLE"
    fi
    
    debug_log "DEBUG" "Selected banner style: $STYLE"
    echo "$STYLE"
}

# 📌 デバッグヘルパー関数
debug_info() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "===== SYSTEM DEBUG INFO ====="
        echo "Architecture: $(get_device_architecture)"
        echo "OS: $(get_os_info)"
        echo "Package Manager: $(get_package_manager)"
        echo "Current Zonename: $(get_zonename_info)"
        echo "Current Timezone: $(get_timezone_info)"
        echo "Available Languages: $(get_available_language_packages)"
        echo "==========================="
    fi
}

# メイン処理
main() {
    get_country_code
    init_device_cache
    get_usb_devices
    detect_and_save_package_manager
}

# スクリプトの実行
main "$@"
