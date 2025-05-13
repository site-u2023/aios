#!/bin/sh

SCRIPT_VERSION="2025.05.10-00-04"

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

packages_usb() {
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color gray_white "$header_text")"
    }

    # === USBストレージ ===
    print_section_header "PKG_SECTION_USB"
    install_package kmod-usb-storage yn hidden
    install_package dosfstools yn hidden
    install_package e2fsprogs yn hidden
    install_package f2fs-tools yn hidden
    install_package exfat-fsck yn hidden
    install_package ntfs-3g yn hidden
    install_package hfsfsck yn hidden
    install_package hdparm yn hidden
    
    debug_log "DEBUG" "USB and storage related packages installation process completed"
    return 0
}

package_samba() {

    print_section_title
    
    # セクションヘッダーを表示する関数
    print_section_header() {
        local section_key="$1"
        local header_text=$(get_message "$section_key")
        printf "\n%s\n" "$(color gray_white "$header_text")"
    }

    # === ファイル共有 ===
    print_section_header "PKG_SECTION_SAMBA"
    install_package luci-app-samba4 yn hidden
    
    debug_log "DEBUG" "Samba file sharing packages installation process completed"
    return 0
}

# USBデバイスを検出し、必要なパッケージをインストールする関数
install_usb_packages() {
    # USBデバイスのキャッシュファイルを確認
    if [ ! -f "${CACHE_DIR}/usbdevice.ch" ]; then
        debug_log "DEBUG" "USB device cache file not found, skipping USB detection"
        return 0
    fi
    
    # USBデバイスが検出されているか確認
    if [ "$(cat "${CACHE_DIR}/usbdevice.ch")" = "detected" ]; then
        debug_log "DEBUG" "USB device detected, installing USB packages"
        packages_usb
    else
        debug_log "DEBUG" "No USB device detected, skipping USB packages"
    fi
    
    return 0
}

# インストール後のパッケージリストを表示
check_install_list() {

    print_section_title
    
    # 表示モード切り替え: 0=パッケージ名のみ, 1=worldファイルの内容そのまま
    local SHOW_APK_ENTRY_DETAIL="${SHOW_APK_ENTRY_DETAIL:-0}"

    printf "\n%s\n" "$(color blue "$(get_message "MSG_PACKAGES_INSTALLED_AFTER_FLASHING")")"
    
    # パッケージマネージャの種類を確認
    if [ -f "${CACHE_DIR}/package_manager.ch" ]; then
        PACKAGE_MANAGER=$(cat "${CACHE_DIR}/package_manager.ch")
    else
        debug_log "DEBUG" "Package manager type not found in cache. Please run detection first."
        return 1
    fi

    if [ "$PACKAGE_MANAGER" = "opkg" ]; then
        # opkg用の処理
        debug_log "DEBUG" "Using opkg package manager"
        local opkg_status_file="/usr/lib/opkg/status"
        local FLASH_TIME=""

        if [ ! -s "$opkg_status_file" ]; then
            debug_log "DEBUG" "$opkg_status_file not found or empty. No packages to list for opkg."
        else
            FLASH_TIME="$(awk '
            $1 == "Installed-Time:" && ($2 < OLDEST || OLDEST=="") {
              OLDEST=$2
            }
            END {
              if (OLDEST != "") {
                print OLDEST
              }
            }
            ' "$opkg_status_file")"

            if [ -z "$FLASH_TIME" ]; then
                debug_log "DEBUG" "Could not determine flash time from opkg status. Listing all user-installed packages for opkg."
                awk '
                $1 == "Package:" { PKG=$2; USR="" }
                $1 == "Status:" && $3 ~ "user" { USR=1 }
                $1 == "Installed-Time:" && USR { print PKG }
                END { if (NR==0) { debug_log "DEBUG" "No user-installed packages found in opkg status." } }
                ' "$opkg_status_file" | sort
            else
                debug_log "DEBUG" "Flash time determined for opkg ($FLASH_TIME). Listing packages installed not at this specific time."
                awk -v FT="$FLASH_TIME" '
                $1 == "Package:" { PKG=$2; USR="" }
                $1 == "Status:" && $3 ~ "user" { USR=1 }
                $1 == "Installed-Time:" && USR && $2 != FT { print PKG }
                END { if (NR==0) { debug_log "DEBUG" "No user-installed packages found not matching flash time for opkg." } }
                ' "$opkg_status_file" | sort
            fi
        fi
    elif [ "$PACKAGE_MANAGER" = "apk" ]; then
        debug_log "DEBUG" "Using apk package manager"
        local apk_world_initial_snapshot="/etc/apk/world.base"
        local current_apk_world_file="/etc/apk/world"
        local temp_world_base_sorted="${AIOS_TMP_DIR}/.world.base.sorted"
        local temp_world_current_sorted="${AIOS_TMP_DIR}/.world.current.sorted"

        if [ ! -s "$current_apk_world_file" ]; then
            debug_log "DEBUG" "$current_apk_world_file not found or empty."
        elif [ -s "$apk_world_initial_snapshot" ]; then
            debug_log "DEBUG" "Comparing $current_apk_world_file with $apk_world_initial_snapshot."
            sort "$apk_world_initial_snapshot" > "$temp_world_base_sorted"
            sort "$current_apk_world_file" > "$temp_world_current_sorted"
            if [ "$SHOW_APK_ENTRY_DETAIL" = "1" ]; then
                grep -vxFf "$temp_world_base_sorted" "$temp_world_current_sorted"
            else
                grep -vxFf "$temp_world_base_sorted" "$temp_world_current_sorted" | \
                    sed -e 's|^.*/\([^/]*\)\.apk$|\1|' \
                        -e 's|\.apk$||' \
                        -e 's|>.*$||'
            fi
            rm -f "$temp_world_base_sorted" "$temp_world_current_sorted"
        else
            debug_log "DEBUG" "$apk_world_initial_snapshot not found or empty. Listing all from $current_apk_world_file."
            if [ "$SHOW_APK_ENTRY_DETAIL" = "1" ]; then
                sort "$current_apk_world_file"
            else
                sort "$current_apk_world_file" | \
                    sed -e 's|^.*/\([^/]*\)\.apk$|\1|' \
                        -e 's|\.apk$||' \
                        -e 's|>.*$||'
            fi
        fi
    else
        debug_log "DEBUG" "Unknown package manager: $PACKAGE_MANAGER"
    fi

    return 0    
}

# parse_package_db_switch <group> <version>
# - 優先度・重複判定はローカル変数スイッチで制御
# - カスタマイズ性を担保
# - OpenWrt busybox ash互換
# - デバッグ等メッセージは英語
parse_package_db_switch() {
    local group="$1"
    local version="$2"
    local dbfile="${BASE_DIR}/package.db"

    local PARSE_DB_PRIORITY="COMMON_FIRST"
    local PARSE_DB_SKIP_MODE="FULL"

    local section_common="[$group.COMMON]"
    local section_version="[$group.$version]"

    local sections=""
    case "$PARSE_DB_PRIORITY" in
        COMMON_FIRST) sections="$section_common $section_version" ;;
        VERSION_FIRST) sections="$section_version $section_common" ;;
        *) echo "Unknown priority mode: $PARSE_DB_PRIORITY" >&2; return 1 ;;
    esac

    local seen_cmds=""
    local seen_pkgs=""
    local in_section=0
    local line pkg

    [ ! -f "$dbfile" ] && { echo "package.db not found" >&2; return 1; }

    # 一時ファイルでバッファ
    local tmpfile="${CACHE_DIR}/parse_package_db_switch_$$.tmp"
    > "$tmpfile"

    for section in $sections; do
        in_section=0
        while IFS= read -r line; do
            line="${line%"${line##*[!$'\r']}" }"
            [ -z "$line" ] && continue
            case "$line" in
                \#*) continue ;;
                \[*)
                    [ "$line" = "$section" ] && in_section=1 || in_section=0
                    continue
                    ;;
                *)
                    [ $in_section -eq 1 ] || continue

                    if [ "$PARSE_DB_SKIP_MODE" = "FULL" ]; then
                        case " $seen_cmds " in
                            *" $line "*) continue ;;
                            *)
                                seen_cmds="$seen_cmds $line"
                                printf "%s\n" "$line" >> "$tmpfile"
                                ;;
                        esac
                    elif [ "$PARSE_DB_SKIP_MODE" = "PACKAGE" ]; then
                        set -- $line
                        pkg="$2"
                        [ -z "$pkg" ] && continue
                        case " $seen_pkgs " in
                            *" $pkg "*) continue ;;
                            *)
                                seen_pkgs="$seen_pkgs $pkg"
                                printf "%s\n" "$line" >> "$tmpfile"
                                ;;
                        esac
                    else
                        echo "Unknown skip mode: $PARSE_DB_SKIP_MODE" >&2
                        rm -f "$tmpfile"
                        return 1
                    fi
                    ;;
            esac
        done < "$dbfile"
    done

    # 行ごとにコマンド＋引数で実行（stdinを/dev/nullにして副作用防止）
    while IFS= read -r exec_line; do
        [ -z "$exec_line" ] && continue
        set -- $exec_line
        cmd="$1"; shift
        if type "$cmd" >/dev/null 2>&1; then
            "$cmd" "$@" < /dev/null
        else
            echo "Unknown command: $cmd (line: $exec_line)" >&2
        fi
    done < "$tmpfile"
    rm -f "$tmpfile"
}
# OSバージョンに基づいて適切なパッケージ関数を実行する
install_packages_version() {
    # OSバージョンファイルの確認
    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        debug_log "DEBUG" "OS version file not found, using DEFAULT section from package.db"
        parse_package_db_switch "BASE_SYSTEM" "DEFAULT"
        return 0
    fi

    # OSバージョンの読み込み
    local os_version
    os_version=$(cat "${CACHE_DIR}/osversion.ch")

    debug_log "DEBUG" "Detected OS version: $os_version"

    case "$os_version" in
        19.*)
            debug_log "DEBUG" "Installing packages for OpenWrt 19.x series (RELEASE19)"
            parse_package_db_switch "BASE_SYSTEM" "RELEASE19"
            ;;
        *[Ss][Nn][Aa][Pp][Ss][Hh][Oo][Tt]*)
            debug_log "DEBUG" "Installing packages for OpenWrt SNAPSHOT"
            parse_package_db_switch "BASE_SYSTEM" "SNAPSHOT"
            ;;
        *)
            debug_log "DEBUG" "Installing standard packages (DEFAULT)"
            parse_package_db_switch "BASE_SYSTEM" "DEFAULT"
            ;;
    esac

    return 0
}

# メイン処理
package_main() {
    debug_log "DEBUG" "package_main called. PACKAGE_INSTALL_MODE is currently: '$PACKAGE_INSTALL_MODE'"

    download "package.db"
    
    print_section_title
    
    if [ "$PACKAGE_INSTALL_MODE" = "auto" ]; then
        # common-country.sh の confirm 関数を使用する
        # メッセージキーは適切なものを get_message で取得するか、直接指定
        # 例: "MSG_CONFIRM_AUTO_INSTALL_ALL" のようなキーを messages.db に定義
        # ここでは仮のメッセージキーを使用
        if ! confirm "MSG_PACKAGE_INSTALL_AUTO"; then
            debug_log "DEBUG" "User cancelled automatic package installation."
            printf "\n%s\n" "$(color yellow "$(get_message "MSG_PACKAGE_INSTALL_CANCELLED")")"
            return 1 # 中断して終了
        fi
        debug_log "DEBUG" "User confirmed automatic package installation."
    fi
    
    # OSバージョンに基づいたパッケージインストール
    install_packages_version
    
    # USB関連パッケージのインストール
    install_usb_packages

    # 自動インストール成功時のメッセージ (オプション)
    if [ "$PACKAGE_INSTALL_MODE" = "auto" ]; then
        printf "\n%s\n" "$(color green "$(get_message "MSG_PACKAGE_INSTALL_COMPLETED")")"
    fi
    return 0 # 正常終了
}

# スクリプトの実行
# package_main "$@"
