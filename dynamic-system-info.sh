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

SELECT_COUNTRY=""
SELECT_ZONE=""
SELECT_TIMEZONE=""
SELECT_ZONENAME=""


# 国コードとタイムゾーン情報を一括取得する関数
get_country_code() {
    # ローカル変数の宣言
    local ip_v4=""
    local ip_v6=""
    local select_ip=""
    local select_ip_ver=""
    local select_utcoffset=""
    local select_posix_tz=""
    local offset_sign=""
    local offset_hours=""
    
    # IPv4アドレスの取得を試行
    debug_log "DEBUG: Attempting to retrieve IPv4 address"
    ip_v4=$(wget -qO- https://api.ipify.org 2>/dev/null || echo "")
    
    # IPv6アドレスの取得を試行
    debug_log "DEBUG: Attempting to retrieve IPv6 address"
    ip_v6=$(wget -qO- https://api64.ipify.org 2>/dev/null || echo "")
    
    # 取得したIPアドレスの確認
    if [ -n "$ip_v4" ]; then
        debug_log "DEBUG: IPv4 address retrieved: $ip_v4"
    fi
    
    if [ -n "$ip_v6" ]; then
        debug_log "DEBUG: IPv6 address retrieved: $ip_v6"
    fi
    
    # いずれかのIPアドレスが取得できたか確認
    if [ -z "$ip_v4" ] && [ -z "$ip_v6" ]; then
        debug_log "DEBUG: Failed to retrieve any IP address"
        return 1
    fi
    
    # IPv4を使用してWorldTimeAPIからタイムゾーン情報を取得
    if [ -n "$ip_v4" ]; then
        debug_log "DEBUG: Trying WorldTimeAPI with IPv4 address"
        SELECT_ZONE=$(wget -qO- "http://worldtimeapi.org/api/ip" 2>/dev/null)
        
        if [ -n "$SELECT_ZONE" ]; then
            select_ip="$ip_v4"
            select_ip_ver="IPv4"
            debug_log "DEBUG: WorldTimeAPI responded successfully using IPv4"
        else
            debug_log "DEBUG: WorldTimeAPI failed with IPv4, response is empty"
        fi
    fi
    
    # IPv4で取得できなかった場合やデータが不完全な場合はIPv6を試す
    if { [ -z "$SELECT_ZONE" ] || ! echo "$SELECT_ZONE" | grep -q '"timezone"' || ! echo "$SELECT_ZONE" | grep -q '"abbreviation"' || ! echo "$SELECT_ZONE" | grep -q '"utc_offset"'; } && [ -n "$ip_v6" ]; then
        debug_log "DEBUG: Trying WorldTimeAPI with IPv6 address"
        
        SELECT_ZONE=$(wget -qO- "http://worldtimeapi.org/api/ip" 2>/dev/null)
        
        if [ -n "$SELECT_ZONE" ]; then
            select_ip="$ip_v6"
            select_ip_ver="IPv6"
            debug_log "DEBUG: WorldTimeAPI responded successfully using IPv6"
        else
            debug_log "DEBUG: WorldTimeAPI also failed with IPv6"
        fi
    fi
    
    # WorldTimeAPIからのデータを処理
    if [ -n "$SELECT_ZONE" ]; then
        # タイムゾーン情報を抽出
        SELECT_ZONENAME=$(echo "$SELECT_ZONE" | grep -o '"timezone":"[^"]*' | awk -F'"' '{print $4}')
        SELECT_TIMEZONE=$(echo "$SELECT_ZONE" | grep -o '"abbreviation":"[^"]*' | awk -F'"' '{print $4}')
        select_utcoffset=$(echo "$SELECT_ZONE" | grep -o '"utc_offset":"[^"]*' | awk -F'"' '{print $4}')
        
        # 国コードも同時に抽出
        SELECT_COUNTRY=$(echo "$SELECT_ZONE" | grep -o '"client_ip":"[^"]*' | awk -F'"' '{print $4}' | xargs wget -qO- "http://ip-api.com/json/" 2>/dev/null | grep -o '"countryCode":"[^"]*' | awk -F'"' '{print $4}')
        
        debug_log "DEBUG: Data extracted from WorldTimeAPI - ZoneName: $SELECT_ZONENAME, TZ: $SELECT_TIMEZONE, Offset: $select_utcoffset, Country: $SELECT_COUNTRY"
        
        # すべての情報が揃っているか確認
        if [ -n "$SELECT_ZONENAME" ] && [ -n "$SELECT_TIMEZONE" ] && [ -n "$select_utcoffset" ]; then
            # POSIX形式のタイムゾーン文字列を生成（例：JST-9）
            offset_sign=$(echo "$select_utcoffset" | cut -c1)
            offset_hours=$(echo "$select_utcoffset" | cut -c2-3 | sed 's/^0//')
            
            if [ "$offset_sign" = "+" ]; then
                # +9 -> -9（POSIXでは符号が反転）
                select_posix_tz="${SELECT_TIMEZONE}-${offset_hours}"
            else
                # -5 -> 5（POSIXではプラスの符号は省略）
                select_posix_tz="${SELECT_TIMEZONE}${offset_hours}"
            fi
            
            debug_log "DEBUG: Generated POSIX timezone: $select_posix_tz"
        else
            debug_log "DEBUG: WorldTimeAPI response incomplete, missing required timezone data"
        fi
    else
        debug_log "DEBUG: Failed to get any valid response from WorldTimeAPI"
    fi
    
    # 結果の確認
    if [ -z "$SELECT_ZONENAME" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_COUNTRY" ]; then
        debug_log "DEBUG: Failed to retrieve all required information"
        return 1
    else
        debug_log "DEBUG: Successfully retrieved all required information"
        return 0
    fi
}

# グローバル変数の情報をキャッシュファイルに保存する関数
# IPアドレスから地域情報を取得しキャッシュファイルに保存する関数
process_location_info() {
    debug_log "DEBUG: Starting IP-based location information retrieval"
    
    # get_country_code関数を呼び出して情報を取得
    get_country_code || {
        debug_log "ERROR: get_country_code failed to retrieve location information"
        return 1
    }
    
    debug_log "DEBUG: Retrieved location data - Country: $SELECT_COUNTRY, ZoneName: $SELECT_ZONENAME, Timezone: $SELECT_TIMEZONE"

    # キャッシュファイルのパス定義
    local tmp_country="${CACHE_DIR}/ip_country.tmp"
    local tmp_zone="${CACHE_DIR}/ip_zone.tmp"
    local tmp_timezone="${CACHE_DIR}/ip_timezone.tmp"
    local tmp_zonename="${CACHE_DIR}/ip_zonename.tmp"
    
    # 3つの重要情報が揃っているか確認
    if [ -z "$SELECT_COUNTRY" ] || [ -z "$SELECT_TIMEZONE" ] || [ -z "$SELECT_ZONENAME" ]; then
        debug_log "ERROR: Incomplete location data - required information missing"
        # 既存のファイルを削除してクリーンな状態を確保
        rm -f "$tmp_country" "$tmp_zone" "$tmp_timezone" "$tmp_zonename" 2>/dev/null
        return 1
    fi
    
    debug_log "DEBUG: All required location data available, saving to cache files"
    
    # 国コードをキャッシュに保存
    echo "$SELECT_COUNTRY" > "$tmp_country"
    debug_log "DEBUG: Country code saved to cache: $SELECT_COUNTRY"
    
    # 生のゾーン情報（JSON形式）をキャッシュに保存
    if [ -n "$SELECT_ZONE" ]; then
        echo "$SELECT_ZONE" > "$tmp_zone"
        debug_log "DEBUG: Zone data saved to cache (JSON format)"
    fi
    
    # ゾーンネームをキャッシュに保存（例：Asia/Tokyo）
    echo "$SELECT_ZONENAME" > "$tmp_zonename"
    debug_log "DEBUG: Zone name saved to cache: $SELECT_ZONENAME"
    
    # POSIX形式のタイムゾーン文字列を構築（例：JST-9）
    local posix_tz="$SELECT_TIMEZONE"
    local utc_offset=""
    
    if [ -n "$SELECT_ZONE" ]; then
        utc_offset=$(echo "$SELECT_ZONE" | grep -o '"utc_offset":"[^"]*' | awk -F'"' '{print $4}')
        
        if [ -n "$utc_offset" ]; then
            debug_log "DEBUG: Found UTC offset in zone data: $utc_offset"
            # +09:00のような形式からPOSIX形式（-9）に変換
            local offset_sign=$(echo "$utc_offset" | cut -c1)
            local offset_hours=$(echo "$utc_offset" | cut -c2-3 | sed 's/^0//')
            
            if [ "$offset_sign" = "+" ]; then
                # +9 -> -9（POSIXでは符号が反転）
                posix_tz="${SELECT_TIMEZONE}-${offset_hours}"
            else
                # -5 -> 5（POSIXではプラスの符号は省略）
                posix_tz="${SELECT_TIMEZONE}${offset_hours}"
            fi
            
            debug_log "DEBUG: Generated POSIX timezone: $posix_tz"
        fi
    fi
    
    # タイムゾーン情報をPOSIX形式で保存
    echo "$posix_tz" > "$tmp_timezone"
    debug_log "DEBUG: Timezone saved to cache in POSIX format: $posix_tz"
    
    debug_log "DEBUG: Location information cache process completed successfully"
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
    init_device_cache
    get_usb_devices
    detect_and_save_package_manager
}

# スクリプトの実行
main "$@"
