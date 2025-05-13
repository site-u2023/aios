#!/bin/sh

SCRIPT_VERSION="2025.05.13-00-00"

DEV_NULL="${DEV_NULL:-on}"
# Silent mode
# export DEV_NULL="on"
# Normal mode
# unset DEV_NULL

# Basic constants setup
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"

PACKAGE_EXTENSION="${PACKAGE_EXTENSION:-ipk}"

#########################################################################
# Last Update: 2025-04-12 05:18:15 (UTC) 🚀
# feed_package: コンテンツAPI用パッケージ取得関数
# 使用対象：通常のディレクトリ構造を持つリポジトリ（例：gSpotx2f/packages-openwrt）
#
# 必要引数：
#   $1 : リポジトリ所有者 (例: gSpotx2f)
#   $2 : リポジトリ名 (例: packages-openwrt)
#   $3 : ディレクトリパス (例: current)
#   $4 : パッケージ名のプレフィックス (例: luci-app-cpu-perf)
#
# オプション:
#   yn          - インストール前に確認ダイアログを表示
#   disabled    - サービスの自動設定をスキップ
#   hidden      - 一部の通知メッセージを表示しない
#   silent      - 進捗・通知メッセージを全て抑制
#   desc="説明" - パッケージの説明文を指定
#
# 使用例:
#   feed_package gSpotx2f packages-openwrt current luci-app-cpu-perf yn
#   feed_package yn hidden gSpotx2f packages-openwrt current luci-app-cpu-perf
#
# 機能:
#   1. 指定されたディレクトリパスが空の場合、リポジトリのトップディレクトリを探索
#   2. パッケージ名のプレフィックスに一致する最新のファイルを取得
#   3. 取得したファイルをダウンロードしてインストール
#########################################################################
feed_package() {
  local confirm_install="no"
  local skip_lang_pack="no"  # This option is parsed but not explicitly used later in the original logic
  local force_install="no"    # This option is parsed but not explicitly used later in the original logic
  local skip_package_db="no" # This option is parsed but not explicitly used later in the original logic
  local set_disabled="no"
  local hidden="no"
  local opts_buffer="" # Buffer for collected options like yn, disabled etc.
  local args_buffer=""   # Buffer for positional arguments
  local desc_flag="no"
  local desc_value=""

  # Argument parsing loop
  # Options can be interspersed with positional arguments in the original examples.
  # This loop tries to separate them.
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts_buffer="$opts_buffer yn" ;;
      nolang) skip_lang_pack="yes"; opts_buffer="$opts_buffer nolang" ;;
      force) force_install="yes"; opts_buffer="$opts_buffer force" ;;
      notpack) skip_package_db="yes"; opts_buffer="$opts_buffer notpack" ;;
      disabled) set_disabled="yes"; opts_buffer="$opts_buffer disabled" ;;
      hidden) hidden="yes"; opts_buffer="$opts_buffer hidden" ;;
      desc=*)
        desc_flag="yes"
        # Extract value after desc=, handling potential existing value and spaces
        current_desc_val="${1#desc=}"
        if [ -z "$desc_value" ]; then
          desc_value="$current_desc_val"
        else
          desc_value="$desc_value $current_desc_val"
        fi
        ;;
      *)
        # If desc_flag is active, append to desc_value
        if [ "$desc_flag" = "yes" ]; then
          if [ -z "$desc_value" ]; then # Should not happen if desc=* was matched
            desc_value="$1"
          else
            desc_value="$desc_value $1"
          fi
        else
          # Assume it's a positional argument, quote for safety
          if [ -z "$args_buffer" ]; then
            args_buffer=$(printf "%s" "$(echo "$1" | sed "s/'/'\\\\''/g;s/\$/'/;s/^/'/")")
          else
            args_buffer="$args_buffer $(printf "%s" "$(echo "$1" | sed "s/'/'\\\\''/g;s/\$/'/;s/^/'/")")"
          fi
        fi
        ;;
    esac
    shift
  done

  # Restore positional arguments from the buffer
  eval "set -- $args_buffer"

  # Check for the 4 required positional arguments
  if [ "$#" -ne 4 ]; then
    debug_log "DEBUG" "Required arguments (REPO_OWNER, REPO_NAME, DIR_PATH, PKG_PREFIX) are missing. Got $# args: $@" >&2
    return 1
  fi

  # PACKAGE_EXTENSION is typically loaded from ${CACHE_DIR}/extension.ch
  # Ensure this file exists and contains "ipk" for the script to proceed.
  if [ -f "${CACHE_DIR}/extension.ch" ]; then
    PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")
  else
    debug_log "DEBUG" "Cache file ${CACHE_DIR}/extension.ch not found. Using default PACKAGE_EXTENSION: $PACKAGE_EXTENSION"
    # If the file must exist, this should be an error:
    # return 1
  fi


  if [ -n "$PACKAGE_EXTENSION" ]; then
      debug_log "DEBUG" "Content of PACKAGE_EXTENSION: $PACKAGE_EXTENSION"
      
      # This check remains as per original script logic
      if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
          printf "%s\n" "$(color yellow "Currently not supported for apk.")"
          return 1
      fi
  else
      # This case implies PACKAGE_EXTENSION was empty even after trying to load/use default.
      debug_log "DEBUG" "PACKAGE_EXTENSION is empty. Cannot proceed."
      return 1
  fi

  # Install required packages
  debug_log "DEBUG" "Installing required packages: jq and ca-certificates"
  install_package jq silent || return 0 # Original script returns 0 on install_package failure
  install_package ca-certificates silent || return 0

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.${PACKAGE_EXTENSION}"
  # API URL construction for GitHub contents API
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"
  
  debug_log "DEBUG" "Fetching data from GitHub API: $API_URL"

  # Handle case where DIR_PATH might be empty, adjust API_URL accordingly
  if [ -z "$DIR_PATH" ]; then
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/"
    debug_log "DEBUG" "DIR_PATH not specified, exploring repository's top directory"
  fi

  # Fetch data from API. GitHub API requires a User-Agent.
  local JSON
  JSON=$($BASE_WGET -U "aios-pkg/1.0" -O- "$API_URL") # Use BASE_WGET, add User-Agent

  # Error handling for API response
  if [ -z "$JSON" ]; then
    debug_log "DEBUG" "Could not retrieve data from API for package: $PKG_PREFIX from $REPO_OWNER/$REPO_NAME"
    # Only print user message if not hidden
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: API connection error")"
    return 0
  fi

  if echo "$JSON" | grep -q "API rate limit exceeded"; then
    debug_log "DEBUG" "GitHub API rate limit exceeded when fetching package: $PKG_PREFIX"
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: GitHub API rate limit exceeded")"
    return 0
  fi

  if echo "$JSON" | grep -q "Not Found"; then
    debug_log "DEBUG" "Repository or path not found: $REPO_OWNER/$REPO_NAME/$DIR_PATH"
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: Repository or path not found")"
    return 0
  fi

  # Extract the latest package file name matching the prefix
  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r '.[].name' | grep "^${PKG_PREFIX}_" | sort | tail -n 1)

  if [ -z "$PKG_FILE" ]; then
    debug_log "DEBUG" "Package $PKG_PREFIX not found in repository $REPO_OWNER/$REPO_NAME"
    if [ "$hidden" != "yes" ]; then
      printf "%s\n" "$(color yellow "Package $PKG_PREFIX not found in repository")"
    else
      # Log for debugging when hidden, consistent with test script behavior
      debug_log "INFO" "Package $PKG_PREFIX not found, hidden=yes, so no user message printed."
    fi
    return 0
  fi

  debug_log "DEBUG" "NEW PACKAGE: $PKG_FILE"

  # Extract download URL for the selected package file
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$DOWNLOAD_URL" ]; then
    debug_log "DEBUG" "Failed to retrieve download URL for package: $PKG_PREFIX"
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Failed to retrieve download URL for package $PKG_PREFIX")"
    return 0
  fi

  debug_log "DEBUG" "OUTPUT FILE: $OUTPUT_FILE"
  debug_log "DEBUG" "DOWNLOAD URL: $DOWNLOAD_URL"

  # Download the package file using direct redirection
  # Use BASE_WGET which is "wget --no-check-certificate -q"
  # Add -U User-Agent and -O- for stdout, then redirect to file.
  if $BASE_WGET -U "aios-pkg/1.0" -O- "$DOWNLOAD_URL" > "$OUTPUT_FILE"; then
    # Check if the downloaded file is not empty
    if [ ! -s "$OUTPUT_FILE" ]; then
      debug_log "DEBUG" "Download command ($BASE_WGET > \$OUTPUT_FILE) resulted in an empty file for $DOWNLOAD_URL."
      # Original script returns 0 even if eval'd wget fails or file is empty.
      # Consider if this should be a harder failure (return 1). For now, match original behavior.
    fi
  else
    local cmd_exit_code=$?
    debug_log "DEBUG" "Download command ($BASE_WGET > \$OUTPUT_FILE) itself failed. Exit code: $cmd_exit_code. URL: $DOWNLOAD_URL"
    # Original script uses `|| return 0` after eval, so we maintain that behavior.
    return 0
  fi

  # Log file details after download attempt
  if [ -f "$OUTPUT_FILE" ]; then
    debug_log "DEBUG" "$(ls -lh "$OUTPUT_FILE")"
  else
    debug_log "DEBUG" "File $OUTPUT_FILE not found after download attempt."
    # If file not found, it's a failure, but original script might proceed due to `|| return 0`
    # For robustness, one might `return 1` here if file must exist.
  fi
  
  # Install the package
  # Reconstruct options for install_package, including desc if present
  local final_install_opts="$opts_buffer" # Start with yn, disabled etc.
  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    # Ensure desc_value is properly quoted if it contains spaces for the argument list
    # However, install_package itself would need to parse "desc=value with spaces"
    # For simplicity here, assume install_package handles `desc=value` as a single arg if passed that way.
    # The original script's `install_package "$OUTPUT_FILE" $opts "desc=$desc_value"`
    # would treat "desc=$desc_value" as one argument if $desc_value contains no internal unquoted spaces,
    # or multiple if it does. Test script passed it as separate args for `desc=`.
    # Let's ensure `desc=actual value` is passed as one token if possible.
    # A more robust way for install_package would be to take desc value separately.
    # Given current structure, we pass it as "desc=value".
    # If desc_value has spaces, it will be passed as "desc=val1 val2", which install_package must handle.
    # Or, we should quote it: "desc='${desc_value}'" but that depends on install_package.
    # Let's stick to the direct approach from the original script's intent.
    # The `opts_buffer` already has leading space if not empty.
    if [ -n "$final_install_opts" ]; then
      final_install_opts="$final_install_opts desc=$desc_value"
    else
      final_install_opts="desc=$desc_value"
    fi
    debug_log "DEBUG" "Installing package with description: $desc_value"
    install_package "$OUTPUT_FILE" $final_install_opts || return 0
  else
    debug_log "DEBUG" "Installing package without description"
    install_package "$OUTPUT_FILE" $final_install_opts || return 0
  fi
  
  return 0
}

#########################################################################
# Last Update: 2025-04-12 05:18:15 (UTC) 🚀
# feed_package1: リリースAPI用パッケージ取得関数
# 使用対象：リリースベースの構造を持つリポジトリ
#          （例：lisaac/luci-app-diskman, jerrykuku/luci-theme-argon）
#
# 必要引数：
#   $1 : リポジトリ所有者 (例: lisaac)
#   $2 : リポジトリ名 (例: luci-app-diskman)
#
# オプション:
#   yn          - インストール前に確認ダイアログを表示
#   disabled    - サービスの自動設定をスキップ
#   hidden      - 一部の通知メッセージを表示しない
#   silent      - 進捗・通知メッセージを全て抑制
#   desc="説明" - パッケージの説明文を指定
#
# 使用例:
#   feed_package1 lisaac luci-app-diskman yn disabled
#   feed_package1 yn hidden lisaac luci-app-diskman
#
# 機能:
#   1. リポジトリのリリース情報からパッケージファイルを検索
#   2. 最新のリリースからパッケージをダウンロード
#   3. ダウンロードしたパッケージをインストール
#########################################################################
feed_package1() {
  local confirm_install="no"
  local skip_lang_pack="no"
  local force_install="no"
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""
  local args=""
  local desc_flag="no"  # 説明文処理中フラグ
  local desc_value=""   # 説明文の値を保持

  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;;
      force) force_install="yes"; opts="$opts force" ;;
      notpack) skip_package_db="yes"; opts="$opts notpack" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;;
      desc=*)
        # desc=の検出時に説明文の処理を開始
        desc_flag="yes"
        desc_value="${1#desc=}"
        ;;
      *)
        if [ "$desc_flag" = "yes" ]; then
          # desc=が既に見つかっている場合、次の引数を説明文の続きとして扱う
          desc_value="$desc_value $1"
        else
          args="$args $1"  # 通常の引数として格納
        fi
        ;;
    esac
    shift
  done

  set -- $args
  if [ "$#" -lt 2 ]; then
    debug_log "DEBUG" "Required arguments (REPO_OWNER, REPO_NAME) are missing." >&2
    return 1
  fi

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")

  if [ -n "$PACKAGE_EXTENSION" ]; then
      debug_log "DEBUG" "Content of PACKAGE_EXTENSION: $PACKAGE_EXTENSION"
      
      # 将来的に削除される予定のルーチン
      if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
          printf "%s\n" "$(color yellow "Currently not supported for apk.")"
          return 1
      fi
  else
      debug_log "DEBUG" "File not found or empty: ${CACHE_DIR}/extension.ch"
      return 1
  fi

  # インストール
  debug_log "DEBUG" "Installing required packages: jq and ca-certificates"
  install_package jq silent
  install_package ca-certificates silent

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local PKG_PREFIX="${REPO_NAME}"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.${PACKAGE_EXTENSION}"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"
  
  debug_log "DEBUG" "Fetching data from GitHub API: $API_URL"

  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$API_URL")

  if [ -z "$JSON" ];then
    debug_log "DEBUG" "Could not retrieve data from API."
    printf "%s\n" "$(color yellow "Could not retrieve data from API.")"
    return 0
  fi

  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r --arg PKG_PREFIX "$PKG_PREFIX" '.[] | .assets[] | select(.name | startswith($PKG_PREFIX)) | .name' | sort | tail -n 1)

  if [ -z "$PKG_FILE" ];then
    debug_log "DEBUG" "$PKG_PREFIX not found."
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "$PKG_PREFIX not found.")"
    return 0
  fi

  debug_log "DEBUG" "NEW PACKAGE: $PKG_FILE"

  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | .assets[] | select(.name == $PKG) | .browser_download_url')

  if [ -z "$DOWNLOAD_URL" ];then
    debug_log "DEBUG" "Failed to retrieve package information."
    printf "%s\n" "$(color yellow "Failed to retrieve package information.")"
    return 0
  fi

  debug_log "DEBUG" "OUTPUT FILE: $OUTPUT_FILE"
  debug_log "DEBUG" "DOWNLOAD URL: $DOWNLOAD_URL"

  eval "$BASE_WGET" -O "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0

  debug_log "DEBUG" "$(ls -lh "$OUTPUT_FILE")"
  
  # 説明文がある場合はdesc=を追加してインストール
  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    debug_log "DEBUG" "Installing release package with description: $desc_value"
    install_package "$OUTPUT_FILE" $opts "desc=$desc_value" || return 0
  else
    debug_log "DEBUG" "Installing release package without description"
    install_package "$OUTPUT_FILE" $opts || return 0
  fi
  
  return 0
}
