#!/bin/sh

SCRIPT_VERSION="2025.05.09-00-01"

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
# feed_package 関数の修正案 (変更箇所に ★★★ を付与)
feed_package() {
  local confirm_install="no"
  # local skip_lang_pack="no" # Currently unused option in this context
  # local force_install="no"  # Passed via opts
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""
  local args=""
  local desc_flag="no"
  local desc_value=""

  # 引数を処理
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      nolang) opts="$opts nolang" ;; # Pass nolang if provided
      force) opts="$opts force" ;;   # Pass force if provided
      notpack) skip_package_db="yes"; opts="$opts notpack" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;;
      desc=*)
        desc_flag="yes"
        desc_value="${1#desc=}"
        # Ensure desc= value is properly passed to install_package later
        ;;
      *)
        # Collect positional arguments first
        args="$args $1"
        ;;
    esac
    shift
  done

  # Re-set positional arguments
  set -- $args
  if [ "$#" -ne 4 ]; then
    debug_log "ERROR" "Usage: feed_package [opts] REPO_OWNER REPO_NAME DIR_PATH PKG_PREFIX" >&2
    return 1
  fi

  local repo_owner="$1"
  local repo_name="$2"
  local dir_path="$3"
  local pkg_prefix="$4"

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")

  if [ -z "$PACKAGE_EXTENSION" ]; then
      debug_log "ERROR" "Package extension cache file not found or empty: ${CACHE_DIR}/extension.ch"
      return 1
  fi
  if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
      printf "%s\n" "$(color yellow "feed_package currently only supports .ipk")"
      return 1 # Not an error, just unsupported for now
  fi

  # Install prerequisites (jq, ca-certificates)
  debug_log "DEBUG" "Checking/Installing required packages: jq and ca-certificates"
  # Use 'test' option to avoid redundant checks if already installed
  # Use 'silent' to suppress output unless there's an error
  if ! install_package jq silent; then
      debug_log "ERROR" "Failed to install required package: jq"
      printf "%s\n" "$(color red "Error: Failed to install prerequisite jq.")"
      return 1
  fi
  if ! install_package ca-certificates silent; then
      debug_log "ERROR" "Failed to install required package: ca-certificates"
      printf "%s\n" "$(color red "Error: Failed to install prerequisite ca-certificates.")"
      return 1
  fi

  # Check if jq is actually available after installation attempt
  if ! command -v jq >/dev/null 2>&1; then
      debug_log "ERROR" "jq command not found or not executable after installation attempt."
      printf "%s\n" "$(color red "Error: jq command is required but not available.")"
      return 1
  fi

  local output_file="${FEED_DIR}/${pkg_prefix}.${PACKAGE_EXTENSION}"
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/contents"
  if [ -n "$dir_path" ]; then # Append dir_path only if it's not empty
      api_url="${api_url}/${dir_path}"
  fi

  debug_log "DEBUG" "Fetching package list from GitHub API: $api_url"

  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$api_url")

  if [ -z "$JSON" ]; then
    debug_log "ERROR" "Could not retrieve data from API: $api_url"
    printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: API connection error")"
    return 1
  fi

  if echo "$JSON" | grep -q "API rate limit exceeded"; then
    debug_log "ERROR" "GitHub API rate limit exceeded: $api_url"
    printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: GitHub API rate limit exceeded")"
    return 1
  fi

  # Check for "Not Found" or other potential JSON error messages
  # A simple "Not Found" string check might be too broad if the JSON itself contains it.
  # Check if the result is a valid JSON array using jq. If not, it's likely an error message.
  if ! echo "$JSON" | jq -e '.[0]' > /dev/null 2>&1; then
      local error_message=$(echo "$JSON" | jq -r '.message? // "Unknown API error"')
      debug_log "ERROR" "API Error for $api_url: $error_message"
      printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: $error_message")"
      return 1
  fi

  # Find the latest package file matching the prefix
  local pkg_file
  # Ensure grep handles pkg_prefix correctly, especially if it contains special regex chars
  # Using fixed string grep (-F) might be safer if pkg_prefix is literal
  # Sorting needs to handle version numbers correctly (-V if available and needed)
  pkg_file=$(echo "$JSON" | jq -r '.[].name' | grep "^${pkg_prefix}_.*\.${PACKAGE_EXTENSION}$" | sort -V | tail -n 1)

  if [ -z "$pkg_file" ]; then
    debug_log "DEBUG" "Package file matching prefix '$pkg_prefix' not found in $repo_owner/$repo_name/$dir_path"
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Package $pkg_prefix not found in feed repository.")"
    return 0 # Package not found in feed is not necessarily an error for the script flow
  fi

  debug_log "DEBUG" "Latest package file found: $pkg_file"

  local download_url
  download_url=$(echo "$JSON" | jq -r --arg PKG "$pkg_file" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then # Check for empty or literal "null"
    debug_log "ERROR" "Failed to retrieve download URL for file: $pkg_file"
    printf "%s\n" "$(color red "Failed to retrieve download URL for package $pkg_prefix")"
    return 1
  fi

  debug_log "DEBUG" "Package download URL: $download_url"
  debug_log "DEBUG" "Output file path: $output_file"

  # Ensure FEED_DIR exists
  mkdir -p "$FEED_DIR"

  # Download the package file
  # Use eval carefully, consider alternatives if possible, but might be needed for $BASE_WGET
  eval "$BASE_WGET" -O "$output_file" "$download_url"
  if [ $? -ne 0 ]; then
      debug_log "ERROR" "Failed to download package from $download_url"
      printf "%s\n" "$(color red "Failed to download package $pkg_prefix")"
      rm -f "$output_file" # Clean up partial download
      return 1
  fi

  debug_log "DEBUG" "Package downloaded successfully: $(ls -lh "$output_file")"

  # ★★★ install_package を呼び出し、戻り値を取得 ★★★
  local install_status=0
  # Pass collected opts and potentially desc= value
  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    debug_log "DEBUG" "Calling install_package for $output_file with opts '$opts' and desc '$desc_value'"
    install_package "$output_file" $opts "desc=$desc_value"
    install_status=$?
  else
    debug_log "DEBUG" "Calling install_package for $output_file with opts '$opts'"
    install_package "$output_file" $opts
    install_status=$?
  fi

  debug_log "DEBUG" "install_package finished for feed package $pkg_prefix with status: $install_status"

  # ★★★ local_package_db の呼び出しを削除 ★★★
  # The logic is now handled within install_package/process_package

  # ★★★ 最終的な戻り値を決定 ★★★
  # 0 (Skipped), 3 (New Install Success) -> Overall Success (0)
  # 1 (Error), 2 (User Cancelled) -> Overall Failure (1)
  case $install_status in
      0|3)
          debug_log "DEBUG" "feed_package completed successfully for $pkg_prefix (Status: $install_status)"
          return 0 # Overall success
          ;;
      1|2)
          debug_log "DEBUG" "feed_package failed or was cancelled for $pkg_prefix (Status: $install_status)"
          # Error/Cancellation message should have been displayed by install_package
          return 1 # Overall failure/cancellation
          ;;
      *)
          debug_log "ERROR" "Unexpected status $install_status from install_package for $pkg_prefix"
          return 1 # Treat unexpected as failure
          ;;
  esac
}

# feed_package_release 関数の修正案 (変更箇所に ★★★ を付与)
feed_package_release() {
  local confirm_install="no"
  # local skip_lang_pack="no" # Currently unused option in this context
  # local force_install="no"  # Passed via opts
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""
  local args=""
  local desc_flag="no"
  local desc_value=""

  # 引数を処理
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      nolang) opts="$opts nolang" ;; # Pass nolang if provided
      force) opts="$opts force" ;;   # Pass force if provided
      notpack) skip_package_db="yes"; opts="$opts notpack" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;;
      desc=*)
        desc_flag="yes"
        desc_value="${1#desc=}"
        # Ensure desc= value is properly passed to install_package later
        ;;
      *)
        # Collect positional arguments first
        args="$args $1"
        ;;
    esac
    shift
  done

  # Re-set positional arguments
  set -- $args
  if [ "$#" -lt 2 ]; then
    debug_log "ERROR" "Usage: feed_package_release [opts] REPO_OWNER REPO_NAME [PKG_PREFIX]" >&2
    return 1
  fi

  local repo_owner="$1"
  local repo_name="$2"
  # Use third argument as pkg_prefix if provided, otherwise default to repo_name
  local pkg_prefix="${3:-$repo_name}"

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")

  if [ -z "$PACKAGE_EXTENSION" ]; then
      debug_log "ERROR" "Package extension cache file not found or empty: ${CACHE_DIR}/extension.ch"
      return 1
  fi
  if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
      printf "%s\n" "$(color yellow "feed_package_release currently only supports .ipk")"
      return 1 # Not an error, just unsupported for now
  fi

  # Install prerequisites (jq, ca-certificates)
  debug_log "DEBUG" "Checking/Installing required packages: jq and ca-certificates"
  if ! install_package jq silent; then
      debug_log "ERROR" "Failed to install required package: jq"
      printf "%s\n" "$(color red "Error: Failed to install prerequisite jq.")"
      return 1
  fi
  if ! install_package ca-certificates silent; then
      debug_log "ERROR" "Failed to install required package: ca-certificates"
      printf "%s\n" "$(color red "Error: Failed to install prerequisite ca-certificates.")"
      return 1
  fi

  # Check if jq is actually available after installation attempt
  if ! command -v jq >/dev/null 2>&1; then
      debug_log "ERROR" "jq command not found or not executable after installation attempt."
      printf "%s\n" "$(color red "Error: jq command is required but not available.")"
      return 1
  fi

  local output_file="${FEED_DIR}/${pkg_prefix}.${PACKAGE_EXTENSION}"
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/releases"

  debug_log "DEBUG" "Fetching release list from GitHub API: $api_url"

  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$api_url")

  if [ -z "$JSON" ];then
    debug_log "ERROR" "Could not retrieve data from API: $api_url"
    printf "%s\n" "$(color red "Could not retrieve release data for $repo_owner/$repo_name: API connection error.")"
    return 1
  fi

  if echo "$JSON" | grep -q "API rate limit exceeded"; then
    debug_log "ERROR" "GitHub API rate limit exceeded: $api_url"
    printf "%s\n" "$(color red "Failed to retrieve releases for $repo_owner/$repo_name: GitHub API rate limit exceeded")"
    return 1
  fi

  # Check for "Not Found" or other potential JSON error messages
  if ! echo "$JSON" | jq -e '.[0]' > /dev/null 2>&1; then
      # Handle case where there are no releases (empty array '[]'), which is valid JSON but means no assets
      if [ "$(echo "$JSON" | jq -r 'length')" = "0" ]; then
          debug_log "DEBUG" "No releases found for $repo_owner/$repo_name."
          [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "No releases found for $repo_owner/$repo_name.")"
          return 0 # No releases is not an error
      else
          local error_message=$(echo "$JSON" | jq -r '.message? // "Unknown API error"')
          debug_log "ERROR" "API Error for $api_url: $error_message"
          printf "%s\n" "$(color red "Failed to retrieve releases for $repo_owner/$repo_name: $error_message")"
          return 1
      fi
  fi

  # Find the latest package file from assets across all releases
  local pkg_file
  pkg_file=$(echo "$JSON" | jq -r --arg PKG_PREFIX "$pkg_prefix" --arg EXT ".${PACKAGE_EXTENSION}" \
    '.[] | .assets[]? | select(.name? | startswith($PKG_PREFIX) and endswith($EXT)) | .name' \
    | sort -V | tail -n 1)

  if [ -z "$pkg_file" ];then
    debug_log "DEBUG" "Package file matching prefix '$pkg_prefix' and extension '.$PACKAGE_EXTENSION' not found in releases for $repo_owner/$repo_name."
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Package $pkg_prefix not found in releases.")"
    return 0 # Package not found in releases is not an error
  fi

  debug_log "DEBUG" "Latest package file found in releases: $pkg_file"

  local download_url
  # Find the download URL for the specific pkg_file across all assets
  download_url=$(echo "$JSON" | jq -r --arg PKG "$pkg_file" \
      '.[] | .assets[]? | select(.name == $PKG) | .browser_download_url' | head -n 1) # Use head -n 1 just in case of duplicates

  if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
    debug_log "ERROR" "Failed to retrieve download URL for file: $pkg_file"
    printf "%s\n" "$(color red "Failed to retrieve download URL for package $pkg_prefix")"
    return 1
  fi

  debug_log "DEBUG" "Package download URL: $download_url"
  debug_log "DEBUG" "Output file path: $output_file"

  # Ensure FEED_DIR exists
  mkdir -p "$FEED_DIR"

  # Download the package file
  eval "$BASE_WGET" -O "$output_file" "$download_url"
  if [ $? -ne 0 ]; then
      debug_log "ERROR" "Failed to download package from $download_url"
      printf "%s\n" "$(color red "Failed to download package $pkg_prefix")"
      rm -f "$output_file" # Clean up partial download
      return 1
  fi

  debug_log "DEBUG" "Package downloaded successfully: $(ls -lh "$output_file")"

  # ★★★ install_package を呼び出し、戻り値を取得 ★★★
  local install_status=0
  # Pass collected opts and potentially desc= value
  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    debug_log "DEBUG" "Calling install_package for $output_file with opts '$opts' and desc '$desc_value'"
    install_package "$output_file" $opts "desc=$desc_value"
    install_status=$?
  else
    debug_log "DEBUG" "Calling install_package for $output_file with opts '$opts'"
    install_package "$output_file" $opts
    install_status=$?
  fi

  debug_log "DEBUG" "install_package finished for release package $pkg_prefix with status: $install_status"

  # ★★★ local_package_db の呼び出しを削除 ★★★
  # The logic is now handled within install_package/process_package

  # ★★★ 最終的な戻り値を決定 ★★★
  # 0 (Skipped), 3 (New Install Success) -> Overall Success (0)
  # 1 (Error), 2 (User Cancelled) -> Overall Failure (1)
  case $install_status in
      0|3)
          debug_log "DEBUG" "feed_package_release completed successfully for $pkg_prefix (Status: $install_status)"
          return 0 # Overall success
          ;;
      1|2)
          debug_log "DEBUG" "feed_package_release failed or was cancelled for $pkg_prefix (Status: $install_status)"
          # Error/Cancellation message should have been displayed by install_package
          return 1 # Overall failure/cancellation
          ;;
      *)
          debug_log "ERROR" "Unexpected status $install_status from install_package for $pkg_prefix"
          return 1 # Treat unexpected as failure
          ;;
  esac
}

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
# feed_package 関数の修正案 (変更箇所に ★★★ を付与)
feed_package_apk() {
  local confirm_install="no"
  # local skip_lang_pack="no" # Currently unused option in this context
  # local force_install="no"  # Passed via opts
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""
  local args=""
  local desc_flag="no"
  local desc_value=""

  # 引数を処理
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      nolang) opts="$opts nolang" ;; # Pass nolang if provided
      force) opts="$opts force" ;;   # Pass force if provided
      notpack) skip_package_db="yes"; opts="$opts notpack" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;;
      desc=*)
        desc_flag="yes"
        desc_value="${1#desc=}"
        # Ensure desc= value is properly passed to install_package_apk later
        ;;
      *)
        # Collect positional arguments first
        args="$args $1"
        ;;
    esac
    shift
  done

  # Re-set positional arguments
  set -- $args
  if [ "$#" -ne 4 ]; then
    debug_log "ERROR" "Usage: feed_package [opts] REPO_OWNER REPO_NAME DIR_PATH PKG_PREFIX" >&2
    return 1
  fi

  local repo_owner="$1"
  local repo_name="$2"
  local dir_path="$3"
  local pkg_prefix="$4"

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")

  if [ -z "$PACKAGE_EXTENSION" ]; then
      debug_log "ERROR" "Package extension cache file not found or empty: ${CACHE_DIR}/extension.ch"
      return 1
  fi
  if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
      printf "%s\n" "$(color yellow "feed_package currently only supports .ipk")"
      return 1 # Not an error, just unsupported for now
  fi

  # Install prerequisites (jq, ca-certificates)
  debug_log "DEBUG" "Checking/Installing required packages: jq and ca-certificates"
  # Use 'test' option to avoid redundant checks if already installed
  # Use 'silent' to suppress output unless there's an error
  if ! install_package_apk jq silent; then
      debug_log "ERROR" "Failed to install required package: jq"
      printf "%s\n" "$(color red "Error: Failed to install prerequisite jq.")"
      return 1
  fi
  if ! install_package_apk ca-certificates silent; then
      debug_log "ERROR" "Failed to install required package: ca-certificates"
      printf "%s\n" "$(color red "Error: Failed to install prerequisite ca-certificates.")"
      return 1
  fi

  # Check if jq is actually available after installation attempt
  if ! command -v jq >/dev/null 2>&1; then
      debug_log "ERROR" "jq command not found or not executable after installation attempt."
      printf "%s\n" "$(color red "Error: jq command is required but not available.")"
      return 1
  fi

  local output_file="${FEED_DIR}/${pkg_prefix}.${PACKAGE_EXTENSION}"
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/contents"
  if [ -n "$dir_path" ]; then # Append dir_path only if it's not empty
      api_url="${api_url}/${dir_path}"
  fi

  debug_log "DEBUG" "Fetching package list from GitHub API: $api_url"

  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$api_url")

  if [ -z "$JSON" ]; then
    debug_log "ERROR" "Could not retrieve data from API: $api_url"
    printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: API connection error")"
    return 1
  fi

  if echo "$JSON" | grep -q "API rate limit exceeded"; then
    debug_log "ERROR" "GitHub API rate limit exceeded: $api_url"
    printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: GitHub API rate limit exceeded")"
    return 1
  fi

  # Check for "Not Found" or other potential JSON error messages
  # A simple "Not Found" string check might be too broad if the JSON itself contains it.
  # Check if the result is a valid JSON array using jq. If not, it's likely an error message.
  if ! echo "$JSON" | jq -e '.[0]' > /dev/null 2>&1; then
      local error_message=$(echo "$JSON" | jq -r '.message? // "Unknown API error"')
      debug_log "ERROR" "API Error for $api_url: $error_message"
      printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: $error_message")"
      return 1
  fi

  # Find the latest package file matching the prefix
  local pkg_file
  # Ensure grep handles pkg_prefix correctly, especially if it contains special regex chars
  # Using fixed string grep (-F) might be safer if pkg_prefix is literal
  # Sorting needs to handle version numbers correctly (-V if available and needed)
  pkg_file=$(echo "$JSON" | jq -r '.[].name' | grep "^${pkg_prefix}_.*\.${PACKAGE_EXTENSION}$" | sort -V | tail -n 1)

  if [ -z "$pkg_file" ]; then
    debug_log "DEBUG" "Package file matching prefix '$pkg_prefix' not found in $repo_owner/$repo_name/$dir_path"
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Package $pkg_prefix not found in feed repository.")"
    return 0 # Package not found in feed is not necessarily an error for the script flow
  fi

  debug_log "DEBUG" "Latest package file found: $pkg_file"

  local download_url
  download_url=$(echo "$JSON" | jq -r --arg PKG "$pkg_file" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then # Check for empty or literal "null"
    debug_log "ERROR" "Failed to retrieve download URL for file: $pkg_file"
    printf "%s\n" "$(color red "Failed to retrieve download URL for package $pkg_prefix")"
    return 1
  fi

  debug_log "DEBUG" "Package download URL: $download_url"
  debug_log "DEBUG" "Output file path: $output_file"

  # Ensure FEED_DIR exists
  mkdir -p "$FEED_DIR"

  # Download the package file
  # Use eval carefully, consider alternatives if possible, but might be needed for $BASE_WGET
  eval "$BASE_WGET" -O "$output_file" "$download_url"
  if [ $? -ne 0 ]; then
      debug_log "ERROR" "Failed to download package from $download_url"
      printf "%s\n" "$(color red "Failed to download package $pkg_prefix")"
      rm -f "$output_file" # Clean up partial download
      return 1
  fi

  debug_log "DEBUG" "Package downloaded successfully: $(ls -lh "$output_file")"

  # ★★★ install_package_apk を呼び出し、戻り値を取得 ★★★
  local install_status=0
  # Pass collected opts and potentially desc= value
  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    debug_log "DEBUG" "Calling install_package_apk for $output_file with opts '$opts' and desc '$desc_value'"
    install_package_apk "$output_file" $opts "desc=$desc_value"
    install_status=$?
  else
    debug_log "DEBUG" "Calling install_package_apk for $output_file with opts '$opts'"
    install_package_apk "$output_file" $opts
    install_status=$?
  fi

  debug_log "DEBUG" "install_package_apk finished for feed package $pkg_prefix with status: $install_status"

  # ★★★ local_package_db の呼び出しを削除 ★★★
  # The logic is now handled within install_package_apk/process_package

  # ★★★ 最終的な戻り値を決定 ★★★
  # 0 (Skipped), 3 (New Install Success) -> Overall Success (0)
  # 1 (Error), 2 (User Cancelled) -> Overall Failure (1)
  case $install_status in
      0|3)
          debug_log "DEBUG" "feed_package completed successfully for $pkg_prefix (Status: $install_status)"
          return 0 # Overall success
          ;;
      1|2)
          debug_log "DEBUG" "feed_package failed or was cancelled for $pkg_prefix (Status: $install_status)"
          # Error/Cancellation message should have been displayed by install_package_apk
          return 1 # Overall failure/cancellation
          ;;
      *)
          debug_log "ERROR" "Unexpected status $install_status from install_package_apk for $pkg_prefix"
          return 1 # Treat unexpected as failure
          ;;
  esac
}

install_package_apk() {
    # オプション解析
    if ! parse_package_options "$@"; then # parse_package_options は既存と仮定
        debug_log "ERROR" "Failed to parse package options."
        return 1 # Return 1 on option parsing failure
    fi

    # インストール一覧表示モード
    if [ "$PKG_OPTIONS_LIST" = "yes" ]; then
        if [ "$PKG_OPTIONS_SILENT" != "yes" ]; then
            check_install_list # check_install_list は既存と仮定
        fi
        return 0 # list is considered a success
    fi

    # ベースネームを取得
    local BASE_NAME="" # Initialize BASE_NAME
    if [ -n "$PKG_OPTIONS_PACKAGE_NAME" ]; then
        BASE_NAME=$(basename "$PKG_OPTIONS_PACKAGE_NAME" .ipk)
        BASE_NAME=$(basename "$BASE_NAME" .apk)
    fi

    # update オプション処理
    if [ "$PKG_OPTIONS_UPDATE" = "yes" ]; then
        debug_log "DEBUG" "Executing package list update"
        update_package_list "$PKG_OPTIONS_SILENT" # update_package_list は既存と仮定
        return $?
    fi

    # パッケージマネージャー確認
    if ! verify_package_manager; then # verify_package_manager は既存と仮定
        debug_log "ERROR" "Failed to verify package manager."
        return 1 # Return 1 if verification fails
    fi

    # パッケージリスト更新 (エラー時は 1 を返す)
    if ! update_package_list "$PKG_OPTIONS_SILENT"; then # update_package_list は既存と仮定
         debug_log "ERROR" "Failed to update package list."
         return 1 # Return 1 if update fails
    fi

    # 言語コード取得
    local lang_code
    lang_code=$(get_language_code) # get_language_code は既存と仮定

    # パッケージ処理と戻り値の取得
    local process_status=0
    # --- PKG_OPTIONS_CONFIRM をそのまま process_package に渡す ---
    # process_package 内部で PACKAGE_INSTALL_MODE を見て最終的な確認有無を決定する
    process_package \
            "$PKG_OPTIONS_PACKAGE_NAME" \
            "$BASE_NAME" \
            "$PKG_OPTIONS_CONFIRM" \
            "$PKG_OPTIONS_FORCE" \
            "$PKG_OPTIONS_SKIP_PACKAGE_DB" \
            "$PKG_OPTIONS_DISABLED" \
            "$PKG_OPTIONS_TEST" \
            "$lang_code" \
            "$PKG_OPTIONS_DESCRIPTION" \
            "$PKG_OPTIONS_SILENT"
    process_status=$? # process_package の戻り値を取得

    debug_log "DEBUG" "process_package finished for $BASE_NAME with status: $process_status"

    # process_package の戻り値に基づく後処理
    case $process_status in
        0) # Success (Skipped, DB failed/skipped) or handled internally
           ;;
        1) # Error during processing
           debug_log "ERROR" "Error occurred during package processing for $BASE_NAME."
           return 1 # Propagate error
           ;;
        2) # User cancelled
           debug_log "DEBUG" "User cancelled installation for $BASE_NAME."
           return 2 # Propagate user cancellation
           ;;
        3) # New install success
           debug_log "DEBUG" "New installation successful for $BASE_NAME. Proceeding to service configuration."
           if [ "$PKG_OPTIONS_DISABLED" != "yes" ]; then
               configure_service "$PKG_OPTIONS_PACKAGE_NAME" "$BASE_NAME" # configure_service は既存と仮定
           else
               debug_log "DEBUG" "Skipping service handling for $BASE_NAME due to disabled option."
           fi
           ;;
        *) # Unexpected status from process_package
           debug_log "ERROR" "Unexpected status $process_status received from process_package for $BASE_NAME."
           return 1 # Treat unexpected as error
           ;;
    esac

    return $process_status
}

# 通常パッケージのインストール処理
install_normal_package_apk() {
    local package_name="$1"
    local force_install="$2"
    local silent_mode="$3"
    
    # 表示用の名前を作成（パスと拡張子を除去）
    local display_name
    display_name=$(basename "$package_name")
    display_name=${display_name%.*}  # 拡張子を除去

    debug_log "DEBUG" "Starting installation process for: $package_name"
    debug_log "DEBUG" "Display name for messages: $display_name"

    # silent モードが有効でない場合のみスピナーを開始
    if [ "$silent_mode" != "yes" ]; then
        start_spinner "$(color blue "$display_name $(get_message "MSG_INSTALLING_PACKAGE")")"
    fi

    if [ "$force_install" = "yes" ]; then
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install --force-reinstall "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add --force-reinstall "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        fi
    else
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        fi
    fi

    # silent モードが有効でない場合のみスピナーを停止
    if [ "$silent_mode" != "yes" ]; then
        stop_spinner "$(color green "$display_name $(get_message "MSG_INSTALL_SUCCESS")")"
    fi
    
    return 0
}

# オプション解析
parse_package_options_apk() {
    # 変数初期化（既存の変数）
    PKG_OPTIONS_CONFIRM="no"
    PKG_OPTIONS_SKIP_LANG="no"
    PKG_OPTIONS_FORCE="no"
    PKG_OPTIONS_SKIP_PACKAGE_DB="no"
    PKG_OPTIONS_DISABLED="no"
    PKG_OPTIONS_HIDDEN="no"
    PKG_OPTIONS_TEST="no"
    PKG_OPTIONS_UPDATE="no"
    PKG_OPTIONS_UNFORCE="no"
    PKG_OPTIONS_LIST="no"
    PKG_OPTIONS_PACKAGE_NAME=""
    PKG_OPTIONS_SILENT="no"
    
    # 変数初期化：説明文用
    PKG_OPTIONS_DESCRIPTION=""

    # 引数のデバッグ出力
    debug_log "DEBUG" "parse_package_options: 受け取った引数 ($#): $*"
    
    # オプション解析
    while [ $# -gt 0 ]; do
        # 現在処理中の引数をデバッグ出力
        debug_log "DEBUG" "parse_package_options: 処理中の引数: $1"
        
        case "$1" in
            yn) PKG_OPTIONS_CONFIRM="yes"; debug_log "DEBUG" "Option: confirm=yes" ;;
            nolang) PKG_OPTIONS_SKIP_LANG="yes"; debug_log "DEBUG" "Option: skip_lang=yes" ;;
            force) PKG_OPTIONS_FORCE="yes"; debug_log "DEBUG" "Option: force=yes" ;;
            notpack) PKG_OPTIONS_SKIP_PACKAGE_DB="yes"; debug_log "DEBUG" "Option: skip_package_db=yes" ;;
            disabled) PKG_OPTIONS_DISABLED="yes"; debug_log "DEBUG" "Option: disabled=yes" ;;
            hidden) PKG_OPTIONS_HIDDEN="yes"; debug_log "DEBUG" "Option: hidden=yes" ;;
            test) PKG_OPTIONS_TEST="yes"; debug_log "DEBUG" "Option: test=yes" ;;
            silent) PKG_OPTIONS_SILENT="yes"; debug_log "DEBUG" "Option: silent=yes" ;;  # silent オプションの追加
            desc=*) 
                # 説明文オプション処理 - "desc=" 以降の文字列を取得
                PKG_OPTIONS_DESCRIPTION="${1#desc=}"
                debug_log "DEBUG" "Option: description=$PKG_OPTIONS_DESCRIPTION" 
                ;;
            update)
                PKG_OPTIONS_UPDATE="yes"
                debug_log "DEBUG" "Option: update=yes"
                shift
                if [ $# -gt 0 ]; then
                    PKG_OPTIONS_PACKAGE_UPDATE="$1"
                    debug_log "DEBUG" "Package update: $PKG_OPTIONS_PACKAGE_UPDATE"
                    shift
                fi
                continue
                ;;
            unforce) PKG_OPTIONS_UNFORCE="yes"; debug_log "DEBUG" "Option: unforce=yes" ;;
            list) PKG_OPTIONS_LIST="yes"; debug_log "DEBUG" "Option: list=yes" ;;
            -*) 
                debug_log "DEBUG" "Unknown option: $1"
                return 1 
                ;;
            *)
                if [ -z "$PKG_OPTIONS_PACKAGE_NAME" ]; then
                    PKG_OPTIONS_PACKAGE_NAME="$1"
                    debug_log "DEBUG" "Package name: $PKG_OPTIONS_PACKAGE_NAME"
                else
                    debug_log "DEBUG" "Additional argument after package name: $1"
                    # 既に説明文が設定されている場合は追加の引数として処理しない
                    if [ -n "$PKG_OPTIONS_DESCRIPTION" ]; then
                        debug_log "DEBUG" "Description already set, ignoring: $1"
                    else
                        # 追加の引数を説明文として扱う（旧動作との互換性のため）
                        debug_log "DEBUG" "Additional argument will be treated as description: $1"
                        PKG_OPTIONS_DESCRIPTION="$1"
                    fi
                fi
                ;;
        esac
        shift
    done
    
    # パッケージ名が指定されていない場合の処理
    if [ -z "$PKG_OPTIONS_PACKAGE_NAME" ] && [ "$PKG_OPTIONS_LIST" != "yes" ] && [ "$PKG_OPTIONS_UPDATE" != "yes" ]; then
        debug_log "DEBUG" "No package name specified"
        return 1
    fi
    
    # オプションに関する情報を出力
    debug_log "DEBUG" "Options parsed: confirm=$PKG_OPTIONS_CONFIRM, force=$PKG_OPTIONS_FORCE, silent=$PKG_OPTIONS_SILENT, description='$PKG_OPTIONS_DESCRIPTION', package=$PKG_OPTIONS_PACKAGE_NAME"
    
    return 0
}

install_normal_package_apk() {
    local package_name="$1"
    local force_install="$2"
    local silent_mode="$3"
    
    # 表示用の名前を作成（パスと拡張子を除去）
    local display_name
    display_name=$(basename "$package_name")
    display_name=${display_name%.*}  # 拡張子を除去

    debug_log "DEBUG" "Starting installation process for: $package_name"
    debug_log "DEBUG" "Display name for messages: $display_name"

    # silent モードが有効でない場合のみスピナーを開始
    if [ "$silent_mode" != "yes" ]; then
        start_spinner "$(color blue "$display_name $(get_message "MSG_INSTALLING_PACKAGE")")"
    fi

    if [ "$force_install" = "yes" ]; then
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install --force-reinstall "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add --force-reinstall "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        fi
    else
        if [ "$PACKAGE_MANAGER" = "opkg" ]; then
            opkg install "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        elif [ "$PACKAGE_MANAGER" = "apk" ]; then
            apk add "$package_name" > /dev/null 2>&1 || {
                # エラーの場合はsilentモードでもメッセージを表示
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                return 1
            }
        fi
    fi

    # silent モードが有効でない場合のみスピナーを停止
    if [ "$silent_mode" != "yes" ]; then
        stop_spinner "$(color green "$display_name $(get_message "MSG_INSTALL_SUCCESS")")"
    fi
    
    return 0
}
