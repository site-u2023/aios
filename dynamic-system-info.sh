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
### 📌 AIサポート要求: POSIX準拠デバッグガイド
### 
### このPOSIXシェルスクリプトのデバッグやエラー修正時:
### 
### 1️⃣ 最小限の再現可能なテストケースを作成する（bash機能を避ける）
### 2️⃣ 明示的にash/dashでテスト: dash ./test.sh
### 3️⃣ 移植性のあるデバッグ方法を使用: echo、printf、または set -x
### 4️⃣ 修正をすべてのPOSIX準拠ガイドラインに対して検証する
### 5️⃣ リソースが制限されたOpenWrtでソリューションが機能するようにする
### 
### ⚠️ 重要:
### - bash固有のソリューションを提案しない
### - 実装前に必ずash/dashで修正をテストする
### - 複雑なものよりも単純なソリューションを優先する
### - テスト検証なしに本番コードを変更しない
### 
### 🛠️ デバッグはシンプル、的確、POSIX準拠に保つ！
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

# 📌 言語コードから国コードへのマッピングを行う関数
get_language_country_mapping() {
    local language_code="$1"
    local mapping=""
    local cache_file="${CACHE_DIR}/language_list.ch"
    
    debug_log "DEBUG" "Looking up country code for language: $language_code"
    
    # 言語コードに対応する国コードを直接マッピング
    case "$language_code" in
        en) mapping="US" ;;
        ja) mapping="JP" ;;
        zh-cn) mapping="CN" ;;
        zh-tw) mapping="TW" ;;
        ko) mapping="KR" ;;
        de) mapping="DE" ;;
        fr) mapping="FR" ;;
        es) mapping="ES" ;;
        it) mapping="IT" ;;
        ru) mapping="RU" ;;
        pl) mapping="PL" ;;
        ca) mapping="ES" ;;
        cs) mapping="CZ" ;;
        *) 
            # API取得または大文字変換でフォールバック
            if [ -n "$API_URL" ] && command -v curl >/dev/null 2>&1; then
                # APIから言語データを取得（例としての実装）
                tmp_result=$(curl -s "$API_URL/lang/$language_code" 2>/dev/null)
                if [ -n "$tmp_result" ]; then
                    mapping="$tmp_result"
                    debug_log "DEBUG" "Retrieved mapping from API: $language_code -> $mapping"
                else
                    mapping=$(echo "$language_code" | tr '[:lower:]' '[:upper:]')
                    debug_log "DEBUG" "API lookup failed, using uppercase: $language_code -> $mapping"
                fi
            else
                mapping=$(echo "$language_code" | tr '[:lower:]' '[:upper:]')
                debug_log "DEBUG" "Using uppercase conversion: $language_code -> $mapping"
            fi
            ;;
    esac
    
    debug_log "DEBUG" "Final mapping: $language_code -> $mapping"
    
    # キャッシュファイルに言語と国コードの対応を出力
    if [ ! -f "$cache_file" ] || ! grep -q "^$language_code:$mapping$" "$cache_file" 2>/dev/null; then
        echo "$language_code:$mapping" >> "$cache_file"
        debug_log "DEBUG" "Added mapping to cache file: $language_code:$mapping"
    fi
    
    # 国コードを返す
    echo "$mapping"
    return 0
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

# 📌 利用可能なタイムゾーンの取得
# 戻り値: システムから利用可能なタイムゾーン名のリスト
get_available_timezones() {
    local zonedir="/usr/share/zoneinfo"
    local tmplist="${CACHE_DIR}/available_timezones.tmp"
    
    # zoneinfoディレクトリが存在するか確認
    if [ -d "$zonedir" ]; then
        # findを使用してすべてのタイムゾーンファイルをリスト
        find "$zonedir" -type f -not -path "*/posix/*" -not -path "*/right/*" -not -path "*/Etc/*" | \
            sed "s|$zonedir/||" | sort > "$tmplist"
    else
        # 一般的なタイムゾーンの最小限のリストにフォールバック
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

# 📌 システムタイムゾーンの設定
# パラメータ: $1 - タイムゾーン名 (例: "Asia/Tokyo")
# 戻り値: 成功時は0、失敗時は非ゼロ
set_system_timezone() {
    local timezone="$1"
    local result=0
    
    if [ -z "$timezone" ]; then
        echo "Error: No timezone specified" >&2
        return 1
    fi
    
    # タイムゾーンが有効かどうか確認
    if [ ! -f "/usr/share/zoneinfo/$timezone" ]; then
        echo "Error: Invalid timezone '$timezone'" >&2
        return 2
    fi
    
    # uciを使用してタイムゾーンを設定（OpenWrt方式）
    if command -v uci >/dev/null 2>&1; then
        uci set system.@system[0].timezone="$timezone"
        uci commit system
        result=$?
    # Alpine Linux / 一般的なLinux方式
    else
        # タイムゾーンファイルへのシンボリックリンクを作成
        ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
        echo "$timezone" > /etc/timezone
        result=$?
    fi
    
    return "$result"
}

# 📌 システムロケール/言語の設定
# パラメータ: $1 - 言語コード (例: "fr", "ja", "zh-cn")
# 戻り値: 成功時は0、失敗時は非ゼロ
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
            # まだインストールされていない場合はOpenWrt用の言語パッケージをインストール
            if ! opkg list-installed | grep -q "luci-i18n-base-$lang_code"; then
                opkg update
                opkg install "luci-i18n-base-$lang_code"
                result=$?
                
                # UCI設定で言語を設定
                if [ "$result" -eq 0 ] && command -v uci >/dev/null 2>&1; then
                    uci set luci.main.lang="$lang_code"
                    uci commit luci
                fi
            else
                # 言語パッケージは既にインストールされているので、言語のみを設定
                if command -v uci >/dev/null 2>&1; then
                    uci set luci.main.lang="$lang_code"
                    uci commit luci
                fi
            fi
            ;;
        apk)
            # Alpine Linuxの場合、言語パッケージをインストール
            apk add "lang-$lang_code" 2>/dev/null
            result=$?
            
            # システムロケールを設定
            echo "LANG=${lang_code}.UTF-8" > /etc/locale.conf
            ;;
        *)
            echo "Unsupported package manager" >&2
            result=1
            ;;
    esac
    
    return "$result"
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

# 📌 包括的なシステムレポートの生成
# レポートをファイルに保存し、ファイル名を返す
generate_system_report() {
    local report_file="${CACHE_DIR}/system_report.txt"
    
    # ヘッダーの作成
    cat > "$report_file" << EOF
============================================
システム情報レポート
生成日時: $(date)
============================================

EOF
    
    # システム情報
    cat >> "$report_file" << EOF
デバイス情報:
------------------
アーキテクチャ: $(get_device_architecture)
オペレーティングシステム: $(get_os_info)
パッケージマネージャー: $(get_package_manager)
ホスト名: $(hostname)
カーネル: $(uname -r)
EOF

    # ネットワーク情報
    cat >> "$report_file" << EOF

ネットワーク情報:
-------------------
EOF
    # IPアドレスとインターフェースの取得
    ifconfig 2>/dev/null >> "$report_file" || ip addr 2>/dev/null >> "$report_file" || echo "ネットワーク情報は利用できません" >> "$report_file"
    
    # 言語とタイムゾーン情報
    cat >> "$report_file" << EOF

ローカライゼーション:
------------
現在のタイムゾーン: $(get_timezone_info)
利用可能な言語パッケージ: $(get_available_language_packages)
EOF

    # UCIが利用可能な場合、LuCI言語を取得
    if command -v uci >/dev/null 2>&1; then
        echo "LuCI言語: $(uci get luci.main.lang 2>/dev/null || echo "未設定")" >> "$report_file"
    fi
    
    # パッケージ情報
    cat >> "$report_file" << EOF

パッケージ情報:
-------------------
EOF
    case "$(get_package_manager)" in
        opkg)
            echo "インストール済みパッケージ (部分リスト - 最初の20件):" >> "$report_file"
            opkg list-installed | head -n 20 >> "$report_file"
            echo "..." >> "$report_file"
            ;;
        apk)
            echo "インストール済みパッケージ (部分リスト - 最初の20件):" >> "$report_file"
            apk list --installed | head -n 20 >> "$report_file"
            echo "..." >> "$report_file"
            ;;
        *)
            echo "パッケージ情報は利用できません" >> "$report_file"
            ;;
    esac
    
    # ストレージ情報
    cat >> "$report_file" << EOF

ストレージ情報:
-------------------
EOF
    df -h >> "$report_file" 2>/dev/null || echo "ストレージ情報は利用できません" >> "$report_file"
    
    # メモリ情報
    cat >> "$report_file" << EOF

メモリ情報:
------------------
EOF
    free -m >> "$report_file" 2>/dev/null || echo "メモリ情報は利用できません" >> "$report_file"
    
    # ファイル名を返す
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
        echo "INFO: Created architecture cache: $arch"
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
            echo "INFO: Created OS version cache: $version"
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
            echo "INFO: Detected and saved package manager: opkg"
        elif command -v apk >/dev/null 2>&1; then
            echo "apk" > "${CACHE_DIR}/package_manager.ch"
            echo "apk" > "${CACHE_DIR}/extension.ch"
            echo "INFO: Detected and saved package manager: apk"
        else
            # デフォルトとしてopkgを使用
            echo "opkg" > "${CACHE_DIR}/package_manager.ch"
            echo "ipk" > "${CACHE_DIR}/extension.ch"
            echo "WARN: No package manager detected, using opkg as default"
        fi
    fi
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
    detect_and_save_package_manager
}

# スクリプトの実行
main "$@"
