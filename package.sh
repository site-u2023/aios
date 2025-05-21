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
        parse_package_db_switch "USB" "COMMON"
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

    # printf "%s\n" "$(color blue "$(get_message "MSG_PACKAGES_INSTALLED_AFTER_FLASHING")")"
    # printf "\n"
    
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
    # shellcheck disable=SC2015 # POSIX shでは `>` は常に成功するので `|| exit` は不要
    > "$tmpfile" # POSIX shでは `>` は常に成功するので `|| exit` は不要

    for section in $sections; do
        in_section=0
        # shellcheck disable=SC2162 # Ashでは read -r line が標準的
        while IFS= read -r line; do
            line="${line%"${line##*[!$'\r']}" }" # Trim trailing CR if present
            line="${line%"${line##*[! ]}" }" # Trim trailing space
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
                        # shellcheck disable=SC2076 # POSIX shでは文字列比較に "" を使う
                        if echo " $seen_cmds " | grep -q " $line "; then
                             continue
                        else
                            seen_cmds="$seen_cmds $line"
                            printf "%s\n" "$line" >> "$tmpfile"
                        fi
                    elif [ "$PARSE_DB_SKIP_MODE" = "PACKAGE" ]; then
                        # shellcheck disable=SC2086 # $line を意図的に分割
                        set -- $line # $line を意図的に分割
                        pkg="$2"
                        [ -z "$pkg" ] && continue
                        # shellcheck disable=SC2076 # POSIX shでは文字列比較に "" を使う
                        if echo " $seen_pkgs " | grep -q " $pkg "; then
                            continue
                        else
                            seen_pkgs="$seen_pkgs $pkg"
                            printf "%s\n" "$line" >> "$tmpfile"
                        fi
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
    # shellcheck disable=SC2162
    while IFS= read -r exec_line; do
        [ -z "$exec_line" ] && continue
        debug_log "DEBUG_PARSE_DB" "Raw line from tmpfile: [$exec_line]"

        # 引数を正しく分割するために eval を使用する
        # cmd と args に分離する
        local cmd_to_exec
        local args_to_exec
        cmd_to_exec=$(echo "$exec_line" | awk '{print $1}')
        args_to_exec=$(echo "$exec_line" | awk '{$1=""; printf "%s", $0}' | sed 's/^[[:space:]]*//') # コマンド部分を除去し、残りを引数とする

        if type "$cmd_to_exec" >/dev/null 2>&1; then
            debug_log "DEBUG_PARSE_DB" "Attempting to call: [$cmd_to_exec] with raw args string: [$args_to_exec]"
            # eval を使って、シェルに引数の解釈（引用符の処理など）を任せる
            # これにより "desc=some thing" が1つの引数として扱われることを期待
            eval "$cmd_to_exec $args_to_exec" < /dev/null
            local exit_status=$?
            debug_log "DEBUG_PARSE_DB" "Command [$cmd_to_exec] with args [$args_to_exec] exited with status: [$exit_status]"
        else
            echo "Unknown command: $cmd_to_exec (line: $exec_line)" >&2
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

confirm_package_lines() {
    local db_file="${BASE_DIR}/package.db";
    local os_version_id="";
    local usb_present="0"; # 0 for no, 1 for yes
    local lines_to_process="";

    # Check for package.db
    if [ ! -f "$db_file" ]; then
        debug_log "ERROR" "confirm_package_lines: $db_file not found. Cannot proceed.";
        return 1;
    fi;

    # Determine OS version for section name
    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        debug_log "DEBUG" "confirm_package_lines: OS version cache not found, using DEFAULT.";
        os_version_id="DEFAULT";
    else
        local os_ver_val;
        os_ver_val=$(cat "${CACHE_DIR}/osversion.ch");
        case "$os_ver_val" in
            19.*) os_version_id="RELEASE19" ;;
            *[Ss][Nn][Aa][Pp][Ss][Hh][Oo][Tt]*) os_version_id="SNAPSHOT" ;;
            *) os_version_id="DEFAULT" ;;
        esac;
    fi;
    debug_log "DEBUG" "confirm_package_lines: Determined OS version identifier: $os_version_id";

    # Check for USB device
    if [ -f "${CACHE_DIR}/usbdevice.ch" ] && [ "$(cat "${CACHE_DIR}/usbdevice.ch")" = "detected" ]; then
        debug_log "DEBUG" "confirm_package_lines: USB device detected.";
        usb_present="1";
    else
        debug_log "DEBUG" "confirm_package_lines: No USB device detected.";
    fi;

    lines_to_process=$(sed -e '1s/^\xEF\xBB\xBF//' -e 's/\r$//' "$db_file" | awk -v os_ver_id_awk="$os_version_id" -v usb_is_present_awk="$usb_present" '
        BEGIN {
            section_base_common_target = "[BASE_SYSTEM.COMMON]";
            section_base_version_target = "[BASE_SYSTEM." os_ver_id_awk "]";
            section_usb_common_target = "[USB.COMMON]";

            in_section_base_common = 0; count_base_common = 0;
            in_section_base_version = 0; count_base_version = 0;
            in_section_usb_common = 0; count_usb_common = 0;
        }
        {
            current_line_content = $0;
            if (current_line_content ~ /^[[:space:]]*$/) { next; }
            if (current_line_content ~ /^[[:space:]]*#/) { next; }

            if (current_line_content == section_base_common_target) {
                in_section_base_common = 1; in_section_base_version = 0; in_section_usb_common = 0; next;
            }
            if (current_line_content == section_base_version_target) {
                in_section_base_version = 1; in_section_base_common = 0; in_section_usb_common = 0; next;
            }
            if (usb_is_present_awk == "1" && current_line_content == section_usb_common_target) {
                in_section_usb_common = 1; in_section_base_common = 0; in_section_base_version = 0; next;
            }
            if (current_line_content ~ /^[[:space:]]*\[.*\][[:space:]]*$/) { # 他のセクションに移った場合
                in_section_base_common = 0; in_section_base_version = 0; in_section_usb_common = 0; next;
            }

            if (in_section_base_common == 1)  { array_base_common[count_base_common++] = current_line_content; }
            if (in_section_base_version == 1)  { array_base_version[count_base_version++] = current_line_content; }
            if (in_section_usb_common == 1 && usb_is_present_awk == "1") { array_usb_common[count_usb_common++] = current_line_content; }
        }
        END {
            for (idx = 0; idx < count_base_common; idx++) { print array_base_common[idx]; }
            for (idx = 0; idx < count_base_version; idx++) { print array_base_version[idx]; }
            if (usb_is_present_awk == "1") {
                for (idx = 0; idx < count_usb_common; idx++) { print array_usb_common[idx]; }
            }
        }
    ' | awk '!seen[$0]++');

    if [ -z "$lines_to_process" ]; then
        debug_log "INFO" "confirm_package_lines: No package-related commands are scheduled for execution.";
        return 1;
    fi;

    # Process each line: call print_section_header for headers, echo package names for others.
    echo "$lines_to_process" | while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            continue
        fi

        _command=$(echo "$line" | awk '{print $1}')
        
        _arg2_raw=$(echo "$line" | awk '{print $2}')
        _arg2=$(echo "$_arg2_raw" | sed 's/^"//;s/"$//')

        if [ "$_command" = "print_section_header" ]; then
            # print_section_header "$_arg2" 
            : # コメントアウトしたので何もしない (コロンで空のコマンドとしておく)
        elif [ "$_command" = "install_package" ]; then
            echo "$_arg2" 
        elif [ "$_command" = "feed_package" ]; then
            _arg5_raw=$(echo "$line" | awk '{print $5}')
            _arg5=$(echo "$_arg5_raw" | sed 's/^"//;s/"$//')
            echo "$_arg5" 
        elif [ "$_command" = "feed_package1" ]; then
            _arg3_raw=$(echo "$line" | awk '{print $3}')
            _arg3=$(echo "$_arg3_raw" | sed 's/^"//;s/"$//')
            echo "$_arg3" 
        fi
    done
}

get_predicted_install_size() {
    debug_log "DEBUG" "get_predicted_install_size: Calculating total predicted installation size."

    # Ensure essential variables/functions are available
    if [ -z "$BASE_DIR" ] || [ -z "$CACHE_DIR" ] || [ -z "$(type -t debug_log)" ] || \
       [ -z "$(type -t get_language_code)" ] || [ -z "$(type -t update_package_list)" ] || \
       [ -z "$(type -t package_pre_install)" ]; then
        echo "Error: Required variables or functions are not available. Ensure common scripts are sourced." >&2
        return 1
    fi

    # Determine package manager (assuming opkg for size info parsing)
    local current_package_manager=""
    if [ -f "${CACHE_DIR}/package_manager.ch" ]; then
        current_package_manager=$(cat "${CACHE_DIR}/package_manager.ch")
    else
        debug_log "ERROR" "get_predicted_install_size: Package manager cache not found."
        echo "Error: Package manager type not determined." >&2
        return 1
    fi

    if [ "$current_package_manager" != "opkg" ]; then
        debug_log "WARNING" "get_predicted_install_size: This function is optimized for opkg to get 'Installed-Size'. Support for '$current_package_manager' may be limited for size prediction."
        # For apk, 'apk info -s <pkg>' might be used, but the logic below is opkg specific.
        # echo "Notice: Package size prediction is currently best supported for opkg."
    fi

    local lang_code
    lang_code=$(get_language_code)

    local db_file="${BASE_DIR}/package.db"
    local os_version_id=""
    local usb_present="0"
    local all_potential_package_lines="" # Stores full lines from package.db

    if [ ! -f "$db_file" ]; then
        debug_log "ERROR" "get_predicted_install_size: $db_file not found."
        echo "Error: package.db not found." >&2
        return 1
    fi

    if [ ! -f "${CACHE_DIR}/osversion.ch" ]; then
        os_version_id="DEFAULT"
    else
        local os_ver_val
        os_ver_val=$(cat "${CACHE_DIR}/osversion.ch")
        case "$os_ver_val" in
            19.*) os_version_id="RELEASE19" ;;
            *[Ss][Nn][Aa][Pp][Ss][Hh][Oo][Tt]*) os_version_id="SNAPSHOT" ;;
            *) os_version_id="DEFAULT" ;;
        esac
    fi
    debug_log "DEBUG" "get_predicted_install_size: OS version ID for package.db: $os_version_id"

    if [ -f "${CACHE_DIR}/usbdevice.ch" ] && [ "$(cat "${CACHE_DIR}/usbdevice.ch")" = "detected" ]; then
        usb_present="1"
    fi
    debug_log "DEBUG" "get_predicted_install_size: USB device present: $usb_present"

    all_potential_package_lines=$(sed -e '1s/^\xEF\xBB\xBF//' -e 's/\r$//' "$db_file" | awk -v os_ver_id_awk="$os_version_id" -v usb_is_present_awk="$usb_present" '
        BEGIN {
            section_base_common_target = "[BASE_SYSTEM.COMMON]";
            section_base_version_target = "[BASE_SYSTEM." os_ver_id_awk "]";
            section_usb_common_target = "[USB.COMMON]";
            in_section_base_common = 0; count_base_common = 0;
            in_section_base_version = 0; count_base_version = 0;
            in_section_usb_common = 0; count_usb_common = 0;
        }
        {
            current_line_content = $0;
            if (current_line_content ~ /^[[:space:]]*$/) { next; }
            if (current_line_content ~ /^[[:space:]]*#/) { next; }
            if (current_line_content == section_base_common_target) { in_section_base_common = 1; in_section_base_version = 0; in_section_usb_common = 0; next; }
            if (current_line_content == section_base_version_target) { in_section_base_version = 1; in_section_base_common = 0; in_section_usb_common = 0; next; }
            if (usb_is_present_awk == "1" && current_line_content == section_usb_common_target) { in_section_usb_common = 1; in_section_base_common = 0; in_section_base_version = 0; next; }
            if (current_line_content ~ /^[[:space:]]*\[.*\][[:space:]]*$/) { in_section_base_common = 0; in_section_base_version = 0; in_section_usb_common = 0; next; }
            if (in_section_base_common == 1)  { array_base_common[count_base_common++] = current_line_content; }
            if (in_section_base_version == 1)  { array_base_version[count_base_version++] = current_line_content; }
            if (in_section_usb_common == 1 && usb_is_present_awk == "1") { array_usb_common[count_usb_common++] = current_line_content; }
        }
        END {
            for (idx = 0; idx < count_base_common; idx++) { print array_base_common[idx]; }
            for (idx = 0; idx < count_base_version; idx++) { print array_base_version[idx]; }
            if (usb_is_present_awk == "1") { for (idx = 0; idx < count_usb_common; idx++) { print array_usb_common[idx]; } }
        }
    ' | awk '!seen[$0]++')

    if [ -z "$all_potential_package_lines" ]; then
        debug_log "INFO" "get_predicted_install_size: No package-related command lines found in package.db."
        echo "Total predicted installation size: 0 KB"
        return 0
    fi

    local packages_to_check_size="" # Stores package names for size checking
    local temp_package_name_for_preinstall=""
    local main_pkg_name_for_local_db=""

    echo "$all_potential_package_lines" | while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then continue; fi

        local _command _package_arg
        _command=$(echo "$line" | awk '{print $1}')
        
        case "$_command" in
            "install_package") _package_arg=$(echo "$line" | awk '{print $2}') ;;
            "feed_package")    _package_arg=$(echo "$line" | awk '{print $5}') ;;
            "feed_package1")   _package_arg=$(echo "$line" | awk '{print $3}') ;;
            "print_section_header") continue ;;
            *) debug_log "DEBUG" "get_predicted_install_size: Skipping unknown command '$_command' from package.db line: $line"; continue ;;
        esac

        main_pkg_name_for_local_db="$_package_arg" # This is the key for package-local.db, without lang code
        temp_package_name_for_preinstall="$_package_arg"
        case "$_package_arg" in
            luci-i18n-*)
                temp_package_name_for_preinstall="${_package_arg}-${lang_code}"
                debug_log "DEBUG" "get_predicted_install_size: Resolved lang package from package.db: $temp_package_name_for_preinstall (from $_package_arg)"
            ;;
        esac
        
        package_pre_install "$temp_package_name_for_preinstall"
        local pre_status=$?
        if [ "$pre_status" -eq 0 ]; then # 0 means ready to install
            packages_to_check_size="${packages_to_check_size}${temp_package_name_for_preinstall}\n"
            debug_log "DEBUG" "get_predicted_install_size: Added to check list (from package.db): $temp_package_name_for_preinstall"

            # Check package-local.db for dependencies of the main_pkg_name_for_local_db
            local local_db_dep_cmds
            local_db_dep_cmds=$(awk -v pkg="$main_pkg_name_for_local_db" '
                $0 ~ "^\\[" pkg "\\]$" {found_section=1; next}
                $0 ~ "^\\[" {found_section=0}
                found_section && $1=="install_package" {print $2} # Print only the package name argument
            ' "${BASE_DIR}/package-local.db")

            echo "$local_db_dep_cmds" | while IFS= read -r dep_pkg_name || [ -n "$dep_pkg_name" ]; do
                if [ -z "$dep_pkg_name" ]; then continue; fi
                
                local dep_pkg_name_for_preinstall="$dep_pkg_name"
                case "$dep_pkg_name" in
                    luci-i18n-*)
                        dep_pkg_name_for_preinstall="${dep_pkg_name}-${lang_code}"
                        debug_log "DEBUG" "get_predicted_install_size: Resolved lang dependency from package-local.db: $dep_pkg_name_for_preinstall (from $dep_pkg_name)"
                    ;;
                esac

                package_pre_install "$dep_pkg_name_for_preinstall"
                local dep_pre_status=$?
                if [ "$dep_pre_status" -eq 0 ]; then
                    packages_to_check_size="${packages_to_check_size}${dep_pkg_name_for_preinstall}\n"
                    debug_log "DEBUG" "get_predicted_install_size: Added to check list (from package-local.db): $dep_pkg_name_for_preinstall"
                fi
            done
        fi
    done
    
    local unique_final_package_list
    unique_final_package_list=$(echo -e "$packages_to_check_size" | grep -v '^$' | awk '!seen[$0]++')

    if [ -z "$unique_final_package_list" ]; then
        debug_log "INFO" "get_predicted_install_size: No new packages identified for installation after all checks."
        echo "Total predicted installation size: 0 KB"
        return 0
    fi

    debug_log "DEBUG" "get_predicted_install_size: Final unique packages for size calculation:\n$unique_final_package_list"

    if ! update_package_list "yes"; then
        debug_log "ERROR" "get_predicted_install_size: Failed to update opkg package list."
        echo "Error: Failed to update package list. Size prediction may be inaccurate." >&2
        # Continue anayway, but sizes might be from outdated cache
    fi

    local total_kb=0
    local pkg_info_size_kb=""
    
    echo "$unique_final_package_list" | while IFS= read -r pkg_to_sum || [ -n "$pkg_to_sum" ]; do
        if [ -z "$pkg_to_sum" ]; then continue; fi
        
        pkg_info_size_kb="" # Reset for each package
        if [ "$current_package_manager" = "opkg" ]; then
            # Attempt to get Installed-Size. Fallback to Size if not found.
            local opkg_info_output
            opkg_info_output=$(opkg info "$pkg_to_sum" 2>/dev/null)

            pkg_info_size_kb=$(echo "$opkg_info_output" | grep -E "^Installed-Size: " | awk '{print $2}')
            if [ -z "$pkg_info_size_kb" ]; then # Fallback to "Size" if "Installed-Size" is not present
                 pkg_info_size_kb=$(echo "$opkg_info_output" | grep -E "^Size: " | awk '{print $2}')
                 if [ -n "$pkg_info_size_kb" ]; then
                    # "Size" for opkg is usually in bytes, convert to KB
                    # Use integer division, round up or handle precisely as needed. Simple integer division for now.
                    pkg_info_size_kb=$(( (pkg_info_size_kb + 1023) / 1024 )) # Convert bytes to KB, rounding up
                    debug_log "DEBUG" "get_predicted_install_size: Used 'Size' (archive size) for $pkg_to_sum, converted to $pkg_info_size_kb KB."
                 fi
            fi
        else
            # Placeholder for other package managers like apk
            debug_log "DEBUG" "get_predicted_install_size: Size retrieval for '$current_package_manager' not fully implemented here for $pkg_to_sum."
        fi
        
        if [ -n "$pkg_info_size_kb" ] && echo "$pkg_info_size_kb" | grep -qE '^[0-9]+$' && [ "$pkg_info_size_kb" -gt 0 ]; then
            total_kb=$((total_kb + pkg_info_size_kb))
            debug_log "DEBUG" "get_predicted_install_size: Added $pkg_info_size_kb KB for $pkg_to_sum. Cumulative total: $total_kb KB"
        else
            debug_log "WARNING" "get_predicted_install_size: Could not determine a valid Installed-Size (KB) for $pkg_to_sum. Value found: '$pkg_info_size_kb'"
        fi
    done
    
    echo "Total predicted installation size: ${total_kb} KB"
    return 0
}

# メイン処理
package_main() {
    debug_log "DEBUG" "package_main called. PACKAGE_INSTALL_MODE is currently: '$PACKAGE_INSTALL_MODE'"

    download "package.db"

    print_section_title

    confirm_package_lines
    local confirm_status=$? # MODIFIED: Store the return status of confirm_package_lines
    if [ "$confirm_status" -ne 0 ]; then # MODIFIED: Check if user cancelled in confirm_package_lines
        debug_log "DEBUG" "Package list confirmation cancelled by user. Exiting package_main."
        return 1 # MODIFIED: Exit package_main if confirmation was cancelled
    fi
    
    if [ "$PACKAGE_INSTALL_MODE" = "auto" ]; then
        printf "\n" 
        if ! confirm "MSG_CONFIRM_PACKAGE_OPERATION"; then
            debug_log "DEBUG" "User cancelled automatic package installation."
            # printf "\n%s\n" "$(color yellow "$(get_message "MSG_PACKAGE_INSTALL_CANCELLED")")"
            return 1 # 中断して終了
        fi
        debug_log "DEBUG" "User confirmed automatic package installation."
    fi
    
    # OSバージョンに基づいたパッケージインストール
    install_packages_version
    
    # USB関連パッケージのインストール
    install_usb_packages

    # インストール完了時のメッセージ
    printf "\n" 
    printf "\n%s\n" "$(color green "$(get_message "MSG_PACKAGE_INSTALL_COMPLETED")")"
    
    return 0 # 正常終了
}

# スクリプトの実行
# package_main "$@"
