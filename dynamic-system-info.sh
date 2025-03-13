#!/bin/sh

SCRIPT_VERSION="2025.03.10-02-00"

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
### 📌 AI Assistance Request: POSIX-Compliant Debugging Guide
### 
### When debugging or fixing errors in this POSIX shell script:
### 
### 1️⃣ Create a minimal reproducible test case (avoid bash features)
### 2️⃣ Test with ash/dash explicitly: dash ./test.sh
### 3️⃣ Use portable debugging methods: echo, printf, or set -x
### 4️⃣ Validate fixes against all POSIX compliance guidelines
### 5️⃣ Ensure the solution works in resource-constrained OpenWrt
### 
### ⚠️ IMPORTANT:
### - Avoid suggesting bash-specific solutions
### - Always test fixes with ash/dash before implementation
### - Prefer simple solutions over complex ones
### - Do not modify production code without test verification
### 
### 🛠️ Keep debugging simple, focused, and POSIX-compliant!
### =========================================================

# 基本定数の設定
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
mkdir -p "$CACHE_DIR" "$LOG_DIR"
DEBUG_MODE="${DEBUG_MODE:-false}"

# ==========================================================================
# Dynamic System Information - Helper Functions for common-country.sh
# ==========================================================================

# 📌 Get device architecture
# Returns: Architecture string (e.g., "mips_24kc", "arm_cortex-a7", "x86_64")
get_device_architecture() {
    local arch=""
    
    # Try to get detailed architecture from OpenWrt
    if [ -f "/etc/openwrt_release" ]; then
        arch=$(grep "DISTRIB_ARCH" /etc/openwrt_release | cut -d "'" -f 2)
    fi
    
    # Fallback to basic architecture if specific arch not found
    if [ -z "$arch" ]; then
        arch=$(uname -m)
    fi
    
    echo "$arch"
}

# 📌 Get OS type and version
# Returns: OS type and version string (e.g., "OpenWrt 24.10.0", "Alpine 3.18.0")
get_os_info() {
    local os_type=""
    local os_version=""
    
    # Check for OpenWrt
    if [ -f "/etc/openwrt_release" ]; then
        os_type="OpenWrt"
        os_version=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2)
    # Check for Alpine Linux
    elif [ -f "/etc/alpine-release" ]; then
        os_type="Alpine"
        os_version=$(cat /etc/alpine-release)
    # Generic Linux fallback
    else
        os_type=$(uname -s)
        os_version=$(uname -r)
    fi
    
    echo "${os_type} ${os_version}"
}

# 📌 Detect package manager
# Returns: Package manager info (e.g., "opkg", "apk")
get_package_manager() {
    if command -v opkg >/dev/null 2>&1; then
        echo "opkg"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# 📌 Get available language packages
# Returns: List of available language packages in the format "language_code:language_name"
get_available_language_packages() {
    local pkg_manager=$(get_package_manager)
    local lang_packages=""
    local tmp_file="${CACHE_DIR}/lang_packages.tmp"
    
    case "$pkg_manager" in
        opkg)
            # Get installed language packages
            opkg list-installed | grep "luci-i18n-base" | cut -d ' ' -f 1 > "$tmp_file" || :
            
            # Also check available (not installed) packages
            opkg list | grep "luci-i18n-base" | cut -d ' ' -f 1 >> "$tmp_file" || :
            ;;
        apk)
            # For Alpine Linux, use apk to find language packages
            apk list | grep -i "lang" | cut -d ' ' -f 1 > "$tmp_file" || :
            ;;
        *)
            # Fallback: Create empty file
            touch "$tmp_file"
            ;;
    esac
    
    # Process the output into a usable format
    if [ -s "$tmp_file" ]; then
        # Sort and remove duplicates
        sort -u "$tmp_file" | while read -r line; do
            # Extract language code (e.g., extract "fr" from luci-i18n-base-fr)
            local lang_code=$(echo "$line" | sed -n 's/.*-\([a-z][a-z]\(-[a-z][a-z]\)\?\)$/\1/p')
            if [ -n "$lang_code" ]; then
                lang_packages="${lang_packages}${lang_code} "
            fi
        done
    fi
    
    rm -f "$tmp_file"
    echo "$lang_packages"
}

# 📌 Get current system timezone
# Returns: Current timezone (e.g., "Asia/Tokyo")
get_current_timezone() {
    local timezone=""
    
    # Try to get from UCI (OpenWrt specific)
    if command -v uci >/dev/null 2>&1; then
        timezone=$(uci get system.@system[0].timezone 2>/dev/null)
    fi
    
    # Fallback to /etc/timezone
    if [ -z "$timezone" ] && [ -f "/etc/timezone" ]; then
        timezone=$(cat /etc/timezone)
    fi
    
    # Fallback to TZ environment variable
    if [ -z "$timezone" ] && [ -n "$TZ" ]; then
        timezone="$TZ"
    fi
    
    # Last resort - use readlink on /etc/localtime
    if [ -z "$timezone" ] && [ -L "/etc/localtime" ]; then
        timezone=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
    fi
    
    echo "$timezone"
}

# 📌 Get available timezones
# Returns: List of available timezone names from the system
get_available_timezones() {
    local zonedir="/usr/share/zoneinfo"
    local tmplist="${CACHE_DIR}/available_timezones.tmp"
    
    # Check if zoneinfo directory exists
    if [ -d "$zonedir" ]; then
        # Using find to list all timezone files
        find "$zonedir" -type f -not -path "*/posix/*" -not -path "*/right/*" -not -path "*/Etc/*" | \
            sed "s|$zonedir/||" | sort > "$tmplist"
    else
        # Fallback to a minimal list of common timezones
        cat > "$tmplist" << EOF
Africa/Cairo
Africa/Johannesburg
Africa/Lagos
America/Anchorage
America/Chicago
America/Denver
America/Los_Angeles
America/New_York
America/Sao_Paulo
Asia/Dubai
Asia/Hong_Kong
Asia/Kolkata
Asia/Seoul
Asia/Shanghai
Asia/Singapore
Asia/Tokyo
Australia/Melbourne
Australia/Sydney
Europe/Amsterdam
Europe/Berlin
Europe/London
Europe/Moscow
Europe/Paris
Europe/Rome
Pacific/Auckland
EOF
    fi
    
    cat "$tmplist"
    rm -f "$tmplist"
}

#!/bin/sh

# タイムゾーン情報を取得（例: JST-9）
get_timezone_info() {
    local timezone=""
    
    # /etc/TZファイルから取得（OpenWrtやAlpineで一般的）
    if [ -f "/etc/TZ" ]; then
        timezone=$(cat /etc/TZ)
    fi
    
    # 取得できない場合はdateコマンドを使う
    if [ -z "$timezone" ]; then
        timezone=$(date +%Z%z)
    fi
    
    echo "$timezone"
}

# ゾーン名を取得（例: Asia/Tokyo）
get_zonename_info() {
    local zonename=""
    
    # UCI（OpenWrt）から取得
    if command -v uci >/dev/null 2>&1; then
        zonename=$(uci get system.@system[0].timezone 2>/dev/null)
    fi
    
    # /etc/timezoneから取得
    if [ -z "$zonename" ] && [ -f "/etc/timezone" ]; then
        zonename=$(cat /etc/timezone)
    fi
    
    # シンボリックリンクから取得
    if [ -z "$zonename" ] && [ -L "/etc/localtime" ]; then
        zonename=$(readlink -f /etc/localtime | sed 's|.*/zoneinfo/||')
    fi
    
    # ゾーン名が取得できない場合はタイムゾーンから推測
    if [ -z "$zonename" ]; then
        local tz=$(get_timezone_info)
        case "$tz" in
            JST-9)
                zonename="Asia/Tokyo"
                ;;
            # 必要に応じて他のケースを追加
            *)
                # 不明な場合は空を返す
                zonename=""
                ;;
        esac
    fi
    
    echo "$zonename"
}

# 📌 Set system timezone
# Param: $1 - Timezone name (e.g., "Asia/Tokyo")
# Returns: 0 on success, non-zero on error
set_system_timezone() {
    local timezone="$1"
    local result=0
    
    if [ -z "$timezone" ]; then
        echo "Error: No timezone specified" >&2
        return 1
    fi
    
    # Check if the timezone is valid
    if [ ! -f "/usr/share/zoneinfo/$timezone" ]; then
        echo "Error: Invalid timezone '$timezone'" >&2
        return 2
    fi
    
    # Attempt to set timezone using uci (OpenWrt method)
    if command -v uci >/dev/null 2>&1; then
        uci set system.@system[0].timezone="$timezone"
        uci commit system
        result=$?
    # Alpine Linux / Generic Linux method
    else
        # Create symlink to timezone file
        ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
        echo "$timezone" > /etc/timezone
        result=$?
    fi
    
    return $result
}

# 📌 Set system locale/language
# Param: $1 - Language code (e.g., "fr", "ja", "zh-cn")
# Returns: 0 on success, non-zero on error
set_system_language() {
    local lang_code="$1"
    local pkg_manager=$(get_package_manager)
    local result=0
    
    if [ -z "$lang_code" ]; then
        echo "Error: No language code specified" >&2
        return 1
    fi
    
    case "$pkg_manager" in
        opkg)
            # Install language package for OpenWrt if not already installed
            if ! opkg list-installed | grep -q "luci-i18n-base-$lang_code"; then
                opkg update
                opkg install "luci-i18n-base-$lang_code"
                result=$?
                
                # Set language in UCI configuration
                if [ $result -eq 0 ] && command -v uci >/dev/null 2>&1; then
                    uci set luci.main.lang="$lang_code"
                    uci commit luci
                fi
            else
                # Language package already installed, just set the language
                if command -v uci >/dev/null 2>&1; then
                    uci set luci.main.lang="$lang_code"
                    uci commit luci
                fi
            fi
            ;;
        apk)
            # For Alpine Linux, install language package
            apk add "lang-$lang_code" 2>/dev/null
            result=$?
            
            # Set system locale
            echo "LANG=${lang_code}.UTF-8" > /etc/locale.conf
            ;;
        *)
            echo "Unsupported package manager" >&2
            result=1
            ;;
    esac
    
    return $result
}

# 📌 Get country information for device
# Returns: Combined country information based on system settings and database
get_country_info() {
    local current_lang=""
    local current_timezone=""
    local country_code=""
    local country_db="${BASE_DIR}/country.db"
    
    # Get current system language
    if command -v uci >/dev/null 2>&1; then
        current_lang=$(uci get luci.main.lang 2>/dev/null)
    fi
    
    # Get current timezone
    current_timezone=$(get_current_timezone)
    
    # If country.db exists, try to match the information
    if [ -f "$country_db" ] && [ -n "$current_lang" ]; then
        # Try to match by language code first
        country_info=$(awk -v lang="$current_lang" '$4 == lang {print $0; exit}' "$country_db")
        
        # If no match by language, try to match by timezone
        if [ -z "$country_info" ] && [ -n "$current_timezone" ]; then
            country_info=$(awk -v tz="$current_timezone" '$0 ~ tz {print $0; exit}' "$country_db")
        fi
        
        # If still no match, return empty
        if [ -n "$country_info" ]; then
            echo "$country_info"
            return 0
        fi
    fi
    
    # If we couldn't find a match or don't have country.db, return empty
    echo ""
    return 1
}

# 📌 Generate comprehensive system report
# Saves the report to a file and returns the filename
generate_system_report() {
    local report_file="${CACHE_DIR}/system_report.txt"
    
    # Create header
    cat > "$report_file" << EOF
============================================
System Information Report
Generated: $(date)
============================================

EOF
    
    # System information
    cat >> "$report_file" << EOF
DEVICE INFORMATION:
------------------
Architecture: $(get_device_architecture)
Operating System: $(get_os_info)
Package Manager: $(get_package_manager)
Hostname: $(hostname)
Kernel: $(uname -r)
EOF

    # Network information
    cat >> "$report_file" << EOF

NETWORK INFORMATION:
-------------------
EOF
    # Get IP addresses and interfaces
    ifconfig 2>/dev/null >> "$report_file" || ip addr 2>/dev/null >> "$report_file" || echo "Network information not available" >> "$report_file"
    
    # Language and timezone information
    cat >> "$report_file" << EOF

LOCALIZATION:
------------
Current Timezone: $(get_current_timezone)
Available Language Packages: $(get_available_language_packages)
EOF

    # If UCI is available, get LuCI language
    if command -v uci >/dev/null 2>&1; then
        echo "LuCI Language: $(uci get luci.main.lang 2>/dev/null || echo "Not set")" >> "$report_file"
    fi
    
    # Package information
    cat >> "$report_file" << EOF

PACKAGE INFORMATION:
-------------------
EOF
    case "$(get_package_manager)" in
        opkg)
            echo "Installed Packages (partial list - first 20):" >> "$report_file"
            opkg list-installed | head -n 20 >> "$report_file"
            echo "..." >> "$report_file"
            ;;
        apk)
            echo "Installed Packages (partial list - first 20):" >> "$report_file"
            apk list --installed | head -n 20 >> "$report_file"
            echo "..." >> "$report_file"
            ;;
        *)
            echo "Package information not available" >> "$report_file"
            ;;
    esac
    
    # Storage information
    cat >> "$report_file" << EOF

STORAGE INFORMATION:
-------------------
EOF
    df -h >> "$report_file" 2>/dev/null || echo "Storage information not available" >> "$report_file"
    
    # Memory information
    cat >> "$report_file" << EOF

MEMORY INFORMATION:
------------------
EOF
    free -m >> "$report_file" 2>/dev/null || echo "Memory information not available" >> "$report_file"
    
    # Return the filename
    echo "$report_file"
}

# デバイス情報キャッシュを初期化・保存する関数
init_device_cache() {
    # キャッシュディレクトリの確保
    mkdir -p "$CACHE_DIR" 2>/dev/null || {
        echo "ERROR: Failed to create cache directory: $CACHE_DIR"
        return 1
    }
    
    # アーキテクチャ情報の保存
    if [ ! -f "${CACHE_DIR}/architecture.ch" ]; then
        local arch
        arch=$(uname -m)
        echo "$arch" > "${CACHE_DIR}/architecture.ch"
        debug_log "INFO" "Created architecture cache: $arch"
    fi
    
    # OSバージョン情報の保存
    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        local version=""
        # OpenWrtバージョン取得
        if [ -f "/etc/openwrt_release" ]; then
            # ファイルからバージョン抽出
            version=$(grep -E "DISTRIB_RELEASE" /etc/openwrt_release | cut -d "'" -f 2)
            
            # スナップショット情報の取得
            local snapshot=""
            snapshot=$(grep -E "DISTRIB_DESCRIPTION" /etc/openwrt_release | grep -o "r[0-9]*")
            if [ -n "$snapshot" ]; then
                version="${version}-${snapshot}"
            fi
        elif [ -f "/etc/os-release" ]; then
            # Alpine等の他のOSの場合
            version=$(grep -E "^VERSION_ID=" /etc/os-release | cut -d "=" -f 2 | tr -d '"')
        fi
        
        if [ -n "$version" ]; then
            echo "$version" > "${CACHE_DIR}/osversion.ch"
            debug_log "INFO" "Created OS version cache: $version"
        else
            echo "unknown" > "${CACHE_DIR}/osversion.ch"
            debug_log "WARN" "Could not determine OS version"
        fi
    fi
    
    return 0
}

# パッケージマネージャー情報を検出・保存する関数
detect_and_save_package_manager() {
    if [ ! -f "${CACHE_DIR}/downloader.ch" ]; then
        if command -v opkg >/dev/null 2>&1; then
            echo "opkg" > "${CACHE_DIR}/downloader.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            debug_log "INFO" "Detected and saved package manager: opkg"
        elif command -v apk >/dev/null 2>&1; then
            echo "apk" > "${CACHE_DIR}/downloader.ch"
            echo "apk" > "${CACHE_DIR}/extension.ch"
            debug_log "INFO" "Detected and saved package manager: apk"
        else
            # デフォルトとしてopkgを使用
            echo "opkg" > "${CACHE_DIR}/downloader.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            debug_log "WARN" "No package manager detected, using opkg as default"
        fi
    fi
}

# 📌 Debug helper function
debug_info() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "===== SYSTEM DEBUG INFO ====="
        echo "Architecture: $(get_device_architecture)"
        echo "OS: $(get_os_info)"
        echo "Package Manager: $(get_package_manager)"
        echo "Current Timezone: $(get_current_timezone)"
        echo "Available Languages: $(get_available_language_packages)"
        echo "==========================="
    fi
}

# Initial debug info when script is sourced
debug_info
