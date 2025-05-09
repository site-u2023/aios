#!/bin/sh

SCRIPT_VERSION="2025.05.09-00-00"

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

# @FUNCTION: feed_package_apk
# @DESCRIPTION: Downloads an .ipk package from a GitHub repository, extracts its contents (data.tar.gz),
#               and deploys them to the root filesystem. Intended for apk-based systems
#               as a temporary measure until official apk packages are available.
#               This function does NOT register the package with the system's package manager.
# @PARAM: $1 - repo_owner (string) - GitHub repository owner.
# @PARAM: $2 - repo_name (string) - GitHub repository name.
# @PARAM: $3 - pkg_admin_name (string) - Administrative name for the package (used for cache file, etc.).
# @PARAM: $4 - dir_path (string, optional) - Directory path within the repository where .ipk files are located. Defaults to root.
# @PARAM: $5 - ipk_filename_prefix (string, optional) - Prefix to identify the .ipk file. Defaults to pkg_admin_name.
# @OPTIONS:
#   yn          - Prompt for confirmation before deployment.
#   force       - Force deployment even if already deployed (cache exists).
#   disabled    - Skip LuCI cache clearing.
#   hidden      - Suppress some non-critical messages.
#   silent      - Suppress all progress and non-error messages.
# @RETURNS:
#   0: Success (or skipped if already deployed and not forced).
#   1: Error (download failed, extraction failed, deployment failed, prerequisite missing, etc.).
#   2: User cancelled deployment at 'yn' prompt.
OK_feed_package_apk() {
  local repo_owner=""
  local repo_name=""
  local pkg_admin_name=""
  local dir_path=""
  local ipk_filename_prefix=""
  local pkg_description=""

  # --- Option and Argument Parsing ---
  local confirm_install="no"
  local force_deploy="no"
  local set_disabled="no"
  local hidden_msg="no"
  local silent_mode="no"
  local opts_for_install_package="" # For options passed to install_package
  local args="" # For collecting positional arguments

  debug_log "DEBUG" "feed_package_apk: Received arguments ($#): $*"

  # MODIFIED: Argument parsing method
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes" ;;
      force) force_deploy="yes" ;;
      disabled) set_disabled="yes" ;;
      hidden) hidden_msg="yes" ;;
      silent) silent_mode="yes" ;;
      desc=*)
        if [ -z "$pkg_description" ]; then # Capture first description only
            pkg_description="${1#desc=}"
            debug_log "DEBUG" "feed_package_apk: Package description captured: $pkg_description"
        else
            debug_log "WARNING" "feed_package_apk: Multiple 'desc=' arguments found. Using first: '$pkg_description'. Ignoring: '$1'"
        fi
        ;;
      *)
        args="$args \"$1\"" # Collect positional arguments, quoting to handle spaces
        ;;
    esac
    shift
  done

  # Restore positional arguments from collected args
  if [ -n "$args" ]; then
    eval "set -- $args"
  else
    set -- # Clear positional arguments if none were collected
  fi

  # Assign positional arguments
  # Expected: REPO_OWNER REPO_NAME (PKG_ADMIN_NAME_OR_CURRENT) (ACTUAL_PKG_NAME_OR_DIR_PATH) [IPK_FILENAME_PREFIX]
  if [ "$#" -lt 3 ]; then # Need at least owner, repo, and (current | pkg_name)
    debug_log "ERROR" "feed_package_apk: Missing required positional arguments. Expected at least REPO_OWNER REPO_NAME PKG_ADMIN_NAME_OR_CURRENT."
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Usage: feed_package_apk [opts] REPO_OWNER REPO_NAME (PKG_ADMIN_NAME | 'current') [ACTUAL_PKG_NAME_IF_CURRENT | DIR_PATH] [IPK_PREFIX]")" >&2
    return 1
  fi

  repo_owner="$1"
  repo_name="$2"
  local third_arg="$3"
  local fourth_arg="$4" # Optional, depends on third_arg and total arg count
  local fifth_arg="$5"  # Optional, for ipk_filename_prefix

  if [ "$third_arg" = "current" ]; then
    if [ -z "$fourth_arg" ]; then
        debug_log "ERROR" "feed_package_apk: Missing ACTUAL_PKG_NAME when 3rd argument is 'current'."
        [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Usage: feed_package_apk [opts] REPO_OWNER REPO_NAME 'current' ACTUAL_PKG_NAME [IPK_PREFIX]")" >&2
        return 1
    fi
    pkg_admin_name="$fourth_arg"
    dir_path="" # dir_path is not used in this calling convention
    debug_log "DEBUG" "feed_package_apk: Adjusted: pkg_admin_name set to '$pkg_admin_name' (from 4th arg as 3rd was 'current'). dir_path reset."
  else
    pkg_admin_name="$third_arg"
    dir_path="$fourth_arg" # Can be empty if only 3 positional args were given
    debug_log "DEBUG" "feed_package_apk: pkg_admin_name set to '$pkg_admin_name' (from 3rd arg). dir_path set to '$dir_path' (from 4th arg)."
  fi

  # Set ipk_filename_prefix
  if [ -n "$fifth_arg" ]; then
    ipk_filename_prefix="$fifth_arg"
  else
    ipk_filename_prefix="$pkg_admin_name" # Default to pkg_admin_name
  fi
  debug_log "DEBUG" "feed_package_apk: ipk_filename_prefix set to '$ipk_filename_prefix'."


  # Construct opts_for_install_package (for `install_package` function)
  if [ "$hidden_msg" = "yes" ]; then
    opts_for_install_package="$opts_for_install_package hidden"
  fi
  if [ "$silent_mode" = "yes" ]; then
    opts_for_install_package="$opts_for_install_package silent"
  fi
  opts_for_install_package=$(echo "$opts_for_install_package" | sed 's/^ *//;s/ *$//') # Trim leading/trailing spaces

  # Check for essential parsed arguments
  if [ -z "$repo_owner" ] || [ -z "$repo_name" ] || [ -z "$pkg_admin_name" ]; then
    debug_log "ERROR" "feed_package_apk: Essential arguments REPO_OWNER, REPO_NAME, or PKG_ADMIN_NAME are missing after parsing."
    # Usage message already printed if arg count was too low, or print a generic one
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: Missing one or more required arguments (owner, repo, package name).")" >&2
    return 1
  fi
  # End of MODIFIED argument parsing section

  debug_log "DEBUG" "feed_package_apk: Parsed - Owner: $repo_owner, Repo: $repo_name, PkgAdmin: $pkg_admin_name, Path: $dir_path, Prefix: $ipk_filename_prefix, Desc: $pkg_description"
  debug_log "DEBUG" "feed_package_apk: Options - Confirm: $confirm_install, Force: $force_deploy, Disabled: $set_disabled, Hidden: $hidden_msg, Silent: $silent_mode, OptsForInstall: $opts_for_install_package"

  # --- Prerequisite Installation (jq, ca-certificates) ---
  # Pass $opts_for_install_package which should contain "silent" if silent_mode is "yes"
  if ! install_package jq $opts_for_install_package; then # MODIFIED: Removed explicit "silent" here
      debug_log "ERROR" "feed_package_apk: Failed to install prerequisite: jq"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: Failed to install prerequisite jq.")"
      return 1
  fi
  if ! install_package ca-certificates $opts_for_install_package; then # MODIFIED: Removed explicit "silent" here
      debug_log "ERROR" "feed_package_apk: Failed to install prerequisite: ca-certificates"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: Failed to install prerequisite ca-certificates.")"
      return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
      debug_log "ERROR" "feed_package_apk: jq command not found after installation attempt."
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: jq command is required but not available.")"
      return 1
  fi

  # --- Check if Already Deployed (via cache file) ---
  local deployed_cache_file="${CACHE_DIR}/${pkg_admin_name}_apk_deployed.ch"
  if [ -f "$deployed_cache_file" ] && [ "$force_deploy" != "yes" ]; then
    debug_log "DEBUG" "feed_package_apk: Package '$pkg_admin_name' already deployed (cache exists). Skipping."
    if [ "$hidden_msg" != "yes" ]; then
        printf "%s\n" "$(color green "$pkg_admin_name is already deployed (apk source). Use 'force' to redeploy.")"
    fi
    return 0
  fi

  # --- Confirmation Prompt (if 'yn' is set) ---
  if [ "$confirm_install" = "yes" ] && [ "$silent_mode" != "yes" ]; then
    local caution_message
    caution_message=$(get_message "MSG_APK_DEPLOY_CAUTION" "pkg=$pkg_admin_name") 
    printf "\n%s\n" "$(color red "$caution_message")"

    if [ -n "$pkg_description" ]; then
      if ! confirm "MSG_CONFIRM_INSTALL_WITH_DESC" "pkg=$(color blue "$pkg_admin_name")" "desc=$(color none "$pkg_description")"; then
        debug_log "DEBUG" "feed_package_apk: User declined deployment of $pkg_admin_name."
        return 2
      fi
    else
      if ! confirm "MSG_CONFIRM_INSTALL" "pkg=$(color blue "$pkg_admin_name")"; then
        debug_log "DEBUG" "feed_package_apk: User declined deployment of $pkg_admin_name."
        return 2
      fi
    fi
  fi
  
  # --- Temporary Directory Setup ---
  local temp_deploy_dir
  temp_deploy_dir=$(mktemp -d -p "${AIOS_TMP_DIR:-/tmp}" "feed_apk_deploy_${pkg_admin_name}_XXXXXX")
  if [ $? -ne 0 ] || [ ! -d "$temp_deploy_dir" ]; then
    debug_log "ERROR" "feed_package_apk: Failed to create temporary directory."
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: Could not create temporary directory.")"
    return 1
  fi
  trap "rm -rf \"$temp_deploy_dir\" 2>/dev/null; debug_log DEBUG \"feed_package_apk: Cleaned up temp directory: $temp_deploy_dir\"" EXIT INT TERM

  local temp_download_dir="${temp_deploy_dir}/download"
  local temp_extract_ipk_dir="${temp_deploy_dir}/extract_ipk"
  local temp_extract_data_dir="${temp_deploy_dir}/extract_data"
  mkdir -p "$temp_download_dir" "$temp_extract_ipk_dir" "$temp_extract_data_dir"

  # --- Get .ipk Download URL from GitHub API (Contents API) ---
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/contents"
  if [ -n "$dir_path" ] && [ "$dir_path" != "/" ]; then # dir_path can be empty if "current" was used
      api_url="${api_url}/${dir_path}"
  fi

  if [ "$silent_mode" != "yes" ]; then
    start_spinner "$(color blue "Fetching $ipk_filename_prefix.ipk info from $repo_owner/$repo_name...")"
  fi

  debug_log "DEBUG" "feed_package_apk: Fetching .ipk list from GitHub API: $api_url"
  local JSON_RESPONSE
  JSON_RESPONSE=$(wget --no-check-certificate -q -U "aios-feed-apk/1.0" -O- "$api_url")
  local wget_status=$?

  if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi

  if [ $wget_status -ne 0 ] || [ -z "$JSON_RESPONSE" ]; then
    debug_log "ERROR" "feed_package_apk: Could not retrieve data from API: $api_url (wget status: $wget_status)"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to retrieve package list for $ipk_filename_prefix: API connection error")"
    return 1
  fi

  if echo "$JSON_RESPONSE" | jq -e 'if type=="object" and (.message | test("API rate limit exceeded")) then true else false end' > /dev/null 2>&1; then
    debug_log "ERROR" "feed_package_apk: GitHub API rate limit exceeded: $api_url"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to retrieve package list for $ipk_filename_prefix: GitHub API rate limit exceeded")"
    return 1
  fi

  if ! echo "$JSON_RESPONSE" | jq -e 'if type=="array" then .[0]? else .message? end' > /dev/null 2>&1; then
      local error_message
      error_message=$(echo "$JSON_RESPONSE" | jq -r '.message? // "Unknown API error or not found"')
      debug_log "ERROR" "feed_package_apk: API Error for $api_url: $error_message"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to retrieve package list for $ipk_filename_prefix: $error_message")"
      return 1
  fi
  
  local ipk_filename
  ipk_filename=$(echo "$JSON_RESPONSE" | jq -r --arg PFX "$ipk_filename_prefix" '.[] | select(.type == "file" and .name? and (.name | startswith($PFX)) and (.name | endswith(".ipk"))) | .name' | sort -V | tail -n 1)

  if [ -z "$ipk_filename" ]; then
    debug_log "DEBUG" "feed_package_apk: .ipk file matching prefix '$ipk_filename_prefix' not found in $repo_owner/$repo_name/${dir_path:-root}"
    if [ "$hidden_msg" != "yes" ]; then
        printf "%s\n" "$(color yellow "Package $ipk_filename_prefix (.ipk) not found in feed repository.")"
    fi
    return 1 
  fi
  debug_log "DEBUG" "feed_package_apk: Latest .ipk file found: $ipk_filename"

  local ipk_download_url
  ipk_download_url=$(echo "$JSON_RESPONSE" | jq -r --arg IPK_FILE "$ipk_filename" '.[] | select(.name == $IPK_FILE) | .download_url')

  if [ -z "$ipk_download_url" ] || [ "$ipk_download_url" = "null" ]; then
    debug_log "ERROR" "feed_package_apk: Failed to retrieve download URL for .ipk file: $ipk_filename"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to get download URL for $ipk_filename")"
    return 1
  fi
  debug_log "DEBUG" "feed_package_apk: .ipk download URL: $ipk_download_url"

  local downloaded_ipk_path="${temp_download_dir}/${ipk_filename}"
  if [ "$silent_mode" != "yes" ]; then
    start_spinner "$(color blue "Downloading $ipk_filename...")"
  fi

  eval "$BASE_WGET" -O "$downloaded_ipk_path" "\"$ipk_download_url\"" 
  local download_status=$?

  if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi

  if [ $download_status -ne 0 ]; then
      debug_log "ERROR" "feed_package_apk: Failed to download .ipk from $ipk_download_url (wget status: $download_status)"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to download $ipk_filename")"
      return 1
  fi
  if [ ! -s "$downloaded_ipk_path" ]; then 
      debug_log "ERROR" "feed_package_apk: Downloaded .ipk file is empty: $downloaded_ipk_path"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Downloaded $ipk_filename is empty")"
      return 1
  fi
  debug_log "DEBUG" "feed_package_apk: .ipk downloaded successfully: $downloaded_ipk_path"

  if [ "$silent_mode" != "yes" ]; then
    start_spinner "$(color blue "Extracting $ipk_filename...")"
  fi
  
  local data_tar_gz_path="${temp_extract_ipk_dir}/data.tar.gz"

  debug_log "DEBUG" "feed_package_apk: Attempting to extract data.tar.gz using 'ar' from $downloaded_ipk_path"
  if ar x "$downloaded_ipk_path" data.tar.gz -o "$temp_extract_ipk_dir" 2>/dev/null && [ -f "$data_tar_gz_path" ]; then
    debug_log "DEBUG" "feed_package_apk: Successfully extracted data.tar.gz using 'ar'."
  else
    debug_log "DEBUG" "feed_package_apk: 'ar' extraction failed or data.tar.gz not found. Assuming .ipk is a direct tar.gz of content or contains data.tar.gz at top level."
    if tar -xzf "$downloaded_ipk_path" -C "$temp_extract_ipk_dir" ./data.tar.gz 2>/dev/null && [ -f "$data_tar_gz_path" ]; then
        debug_log "DEBUG" "feed_package_apk: Successfully extracted data.tar.gz using 'tar' from .ipk top level."
    else
        debug_log "DEBUG" "feed_package_apk: data.tar.gz not found at .ipk top level. Assuming .ipk IS the data.tar.gz equivalent (direct content)."
        cp "$downloaded_ipk_path" "$data_tar_gz_path"
        if [ $? -ne 0 ]; then
            if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
            debug_log "ERROR" "feed_package_apk: Failed to copy .ipk as data.tar.gz for extraction."
            [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error preparing .ipk for content extraction.")"
            return 1
        fi
        debug_log "DEBUG" "feed_package_apk: Copied .ipk to be treated as data.tar.gz."
    fi
  fi

  if [ ! -f "$data_tar_gz_path" ]; then
    if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
    debug_log "ERROR" "feed_package_apk: data.tar.gz could not be found or extracted from $ipk_filename."
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Could not find data.tar.gz in $ipk_filename")"
    return 1
  fi

  if ! tar -xzf "$data_tar_gz_path" -C "$temp_extract_data_dir" 2>"${LOG_DIR}/feed_apk_deploy_tar_err.log"; then
    if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
    debug_log "ERROR" "feed_package_apk: Failed to extract data.tar.gz from $ipk_filename. See ${LOG_DIR}/feed_apk_deploy_tar_err.log"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to extract content from $ipk_filename")"
    return 1
  fi
  if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
  debug_log "DEBUG" "feed_package_apk: Content extracted to $temp_extract_data_dir"

  if [ ! -d "$temp_extract_data_dir" ] || [ -z "$(ls -A "$temp_extract_data_dir")" ]; then
    debug_log "ERROR" "feed_package_apk: Extracted data directory is empty or does not exist: $temp_extract_data_dir"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "No content found after extraction for $pkg_admin_name")"
    return 1
  fi

  if [ "$silent_mode" != "yes" ]; then
    start_spinner "$(color blue "Deploying files for $pkg_admin_name...")"
  fi

  if ! cp -a "${temp_extract_data_dir}/." / 2>"${LOG_DIR}/feed_apk_deploy_cp_err.log"; then
    if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
    debug_log "ERROR" "feed_package_apk: Failed to copy files to root filesystem. See ${LOG_DIR}/feed_apk_deploy_cp_err.log"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error deploying files for $pkg_admin_name")"
    return 1
  fi
  if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
  debug_log "DEBUG" "feed_package_apk: Files deployed successfully to root filesystem."

  mkdir -p "$CACHE_DIR"
  if ! touch "$deployed_cache_file"; then
    debug_log "WARNING" "feed_package_apk: Failed to create or update deployment cache file: $deployed_cache_file"
  else
    debug_log "DEBUG" "feed_package_apk: Deployment cache file created/updated: $deployed_cache_file"
  fi

  if [ "$set_disabled" != "yes" ]; then
    if [ -d /tmp/luci-* ]; then 
        debug_log "DEBUG" "feed_package_apk: Clearing LuCI cache."
        rm -rf /tmp/luci-* 2>/dev/null
    else
        debug_log "DEBUG" "feed_package_apk: LuCI cache not found, skipping clear."
    fi
  else
    debug_log "DEBUG" "feed_package_apk: LuCI cache clearing skipped due to 'disabled' option."
  fi

  if [ "$silent_mode" != "yes" ]; then
    printf "%s\n" "$(color green "$pkg_admin_name deployed successfully (apk source).")"
    if [ "$confirm_install" != "yes" ] && [ "$hidden_msg" != "yes" ]; then
        local note_message
        note_message=$(get_message "MSG_APK_DEPLOY_CAUTION" "pkg=$(color blue "$pkg_admin_name")")
        printf "\n%s\n" "$(color yellow "$note_message")"
    fi
  fi
  
  return 0
}

# @FUNCTION: feed_package_apk
# @DESCRIPTION: Downloads an .ipk package from a GitHub repository, extracts its contents (data.tar.gz),
#               and deploys them to the root filesystem. Intended for apk-based systems
#               as a temporary measure until official apk packages are available.
#               This function does NOT register the package with the system's package manager.
# @PARAM: $1 - repo_owner (string) - GitHub repository owner.
# @PARAM: $2 - repo_name (string) - GitHub repository name.
# @PARAM: $3 - pkg_admin_name_or_current (string) - Administrative name for the package, or "current".
# @PARAM: $4 - actual_pkg_name_if_current_or_dir_path (string, optional) - Actual package name if $3 is "current", otherwise directory path.
# @PARAM: $5 - ipk_filename_prefix (string, optional) - Prefix to identify the .ipk file. Defaults to pkg_admin_name.
# @OPTIONS:
#   yn          - Prompt for confirmation before deployment.
#   force       - Force deployment even if already deployed (cache exists).
#   disabled    - Skip LuCI cache clearing.
#   hidden      - Suppress some non-critical messages.
#   silent      - Suppress all progress and non-error messages.
#   desc="description" - Package description.
# @RETURNS:
#   0: Success (or skipped if already deployed and not forced).
#   1: Error (download failed, extraction failed, deployment failed, prerequisite missing, etc.).
#   2: User cancelled deployment at 'yn' prompt.
feed_package_apk() {
  local repo_owner=""
  local repo_name=""
  local pkg_admin_name="" # This will be the final administrative name
  local dir_path=""       # Path in repo, can be empty if "current" is used
  local ipk_filename_prefix="" # Prefix for the .ipk file, defaults to pkg_admin_name
  local pkg_description=""

  # --- Option and Argument Parsing (Common structure similar to feed_package) ---
  local confirm_install="no"
  local force_deploy="no"
  local set_disabled="no"
  local hidden_msg="no"
  local silent_mode="no"
  local opts_for_prereq_install="" # For "silent" or "hidden silent" for prerequisite install_package calls
  local args="" # For collecting positional arguments

  debug_log "DEBUG" "feed_package_apk: Received arguments ($#): $*"

  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes" ;;
      force) force_deploy="yes" ;;
      disabled) set_disabled="yes" ;;
      hidden) hidden_msg="yes" ;;
      silent) silent_mode="yes" ;;
      desc=*)
        if [ -z "$pkg_description" ]; then
            pkg_description="${1#desc=}"
            debug_log "DEBUG" "feed_package_apk: Package description captured: '$pkg_description'"
        else
            debug_log "WARNING" "feed_package_apk: Multiple 'desc=' arguments found. Using first: '$pkg_description'. Ignoring: '$1'"
        fi
        ;;
      *)
        args="$args \"$1\"" # Collect positional arguments
        ;;
    esac
    shift
  done

  # Restore positional arguments
  if [ -n "$args" ]; then
    eval "set -- $args"
  else
    set --
  fi

  # --- Positional Argument Assignment for feed_package_apk ---
  if [ "$#" -lt 3 ]; then
    debug_log "ERROR" "feed_package_apk: Missing required positional arguments. Expected: REPO_OWNER REPO_NAME PKG_ADMIN_NAME_OR_CURRENT [ACTUAL_PKG_NAME_OR_DIR_PATH] [IPK_PREFIX]"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Usage: feed_package_apk [opts] REPO_OWNER REPO_NAME (PKG_ADMIN_NAME | 'current') [ACTUAL_PKG_NAME_IF_CURRENT | DIR_PATH] [IPK_PREFIX]")" >&2
    return 1
  fi

  repo_owner="$1"
  repo_name="$2"
  local arg3_pkg_admin_or_current="$3"
  local arg4_actual_pkg_or_dir="$4" # Optional
  local arg5_ipk_prefix="$5"        # Optional

  if [ "$arg3_pkg_admin_or_current" = "current" ]; then
    if [ -z "$arg4_actual_pkg_or_dir" ]; then
      debug_log "ERROR" "feed_package_apk: ACTUAL_PKG_NAME (4th argument) is required when 3rd argument is 'current'."
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: Missing ACTUAL_PKG_NAME for 'current' mode.")" >&2
      return 1
    fi
    pkg_admin_name="$arg4_actual_pkg_or_dir"
    dir_path="" # dir_path is not applicable in 'current' mode for apk
    ipk_filename_prefix="${arg5_ipk_prefix:-$pkg_admin_name}"
    debug_log "DEBUG" "feed_package_apk: 'current' mode. pkg_admin_name='$pkg_admin_name', dir_path='(not used)', ipk_filename_prefix='$ipk_filename_prefix'"
  else
    pkg_admin_name="$arg3_pkg_admin_or_current"
    dir_path="$arg4_actual_pkg_or_dir" # This is dir_path, can be empty if not provided
    ipk_filename_prefix="${arg5_ipk_prefix:-$pkg_admin_name}"
    debug_log "DEBUG" "feed_package_apk: Standard mode. pkg_admin_name='$pkg_admin_name', dir_path='$dir_path', ipk_filename_prefix='$ipk_filename_prefix'"
  fi
  # --- End of Argument Parsing ---

  # Construct options for prerequisite install_package calls
  if [ "$hidden_msg" = "yes" ]; then opts_for_prereq_install="$opts_for_prereq_install hidden"; fi
  if [ "$silent_mode" = "yes" ]; then opts_for_prereq_install="$opts_for_prereq_install silent"; fi
  opts_for_prereq_install=$(echo "$opts_for_prereq_install" | sed 's/^ *//;s/ *$//')


  debug_log "DEBUG" "feed_package_apk: Final Parsed - Owner: $repo_owner, Repo: $repo_name, PkgAdmin: $pkg_admin_name, Path: $dir_path, Prefix: $ipk_filename_prefix, Desc: '$pkg_description'"
  debug_log "DEBUG" "feed_package_apk: Options - Confirm: $confirm_install, Force: $force_deploy, Disabled: $set_disabled, Hidden: $hidden_msg, Silent: $silent_mode"

  # --- Prerequisite Installation (jq, ca-certificates) (Common with feed_package) ---
  if ! install_package jq $opts_for_prereq_install; then
      debug_log "ERROR" "feed_package_apk: Failed to install prerequisite: jq"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: Failed to install prerequisite jq.")"
      return 1
  fi
  if ! install_package ca-certificates $opts_for_prereq_install; then
      debug_log "ERROR" "feed_package_apk: Failed to install prerequisite: ca-certificates"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: Failed to install prerequisite ca-certificates.")"
      return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
      debug_log "ERROR" "feed_package_apk: jq command not found after installation attempt."
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: jq command is required but not available.")"
      return 1
  fi

  # --- Check if Already Deployed (via cache file) ---
  local deployed_cache_file="${CACHE_DIR}/${pkg_admin_name}_apk_deployed.ch"
  if [ -f "$deployed_cache_file" ] && [ "$force_deploy" != "yes" ]; then
    debug_log "DEBUG" "feed_package_apk: Package '$pkg_admin_name' already deployed (cache exists). Skipping."
    if [ "$hidden_msg" != "yes" ]; then
        printf "%s\n" "$(color green "$pkg_admin_name is already deployed (apk source). Use 'force' to redeploy.")"
    fi
    return 0
  fi

  # --- GitHub API Interaction & Download (Common structure with feed_package) ---
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/contents"
  # dir_path might be empty if 'current' mode was used, or if user didn't provide it.
  # If dir_path is empty, API URL targets repo root. If not, it's appended.
  if [ -n "$dir_path" ] && [ "$dir_path" != "/" ]; then
      local cleaned_dir_path=$(echo "$dir_path" | sed 's#^/*##;s#/*$##') # Clean slashes
      if [ -n "$cleaned_dir_path" ]; then
        api_url="${api_url}/${cleaned_dir_path}"
      fi
  fi

  if [ "$silent_mode" != "yes" ]; then
    start_spinner "$(color blue "Fetching $ipk_filename_prefix.ipk info from $repo_owner/$repo_name...")"
  fi

  debug_log "DEBUG" "feed_package_apk: Fetching .ipk list from GitHub API: $api_url"
  local JSON_RESPONSE
  JSON_RESPONSE=$(wget --no-check-certificate -q -U "aios-feed-apk/1.0 $(uname -a)" -O- "$api_url")
  local wget_status=$?

  if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi

  if [ $wget_status -ne 0 ] || [ -z "$JSON_RESPONSE" ]; then
    debug_log "ERROR" "feed_package_apk: Could not retrieve data from API: $api_url (wget status: $wget_status)"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to retrieve package list for $ipk_filename_prefix: API connection error")"
    return 1
  fi

  local api_error_message
  if echo "$JSON_RESPONSE" | jq -e 'type=="object" and .message' > /dev/null 2>&1; then
    api_error_message=$(echo "$JSON_RESPONSE" | jq -r '.message')
  else
    api_error_message="" 
  fi

  if [ -n "$api_error_message" ]; then
      if echo "$api_error_message" | grep -q "API rate limit exceeded"; then
          debug_log "ERROR" "feed_package_apk: GitHub API rate limit exceeded: $api_url"
          [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to retrieve package list for $ipk_filename_prefix: GitHub API rate limit exceeded")"
      elif echo "$api_error_message" | grep -q "Not Found"; then
          debug_log "ERROR" "feed_package_apk: GitHub API resource not found: $api_url"
          [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to retrieve package list for $ipk_filename_prefix: Resource not found (check repo/path)")"
      else
          debug_log "ERROR" "feed_package_apk: GitHub API error for $api_url: $api_error_message"
          [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to retrieve package list for $ipk_filename_prefix: $api_error_message")"
      fi
      return 1
  fi
  
  if ! echo "$JSON_RESPONSE" | jq -e 'if type=="array" then true else false end' > /dev/null 2>&1; then
      debug_log "ERROR" "feed_package_apk: API response is not a JSON array as expected: $api_url. Response: $JSON_RESPONSE"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to parse package list for $ipk_filename_prefix: Unexpected API response format")"
      return 1
  fi
  
  local ipk_filename # Actual filename of the .ipk to download
  ipk_filename=$(echo "$JSON_RESPONSE" | jq -r --arg PFX "$ipk_filename_prefix" '.[] | select(.type == "file" and .name? and (.name | startswith($PFX)) and (.name | endswith(".ipk"))) | .name' | sort -V | tail -n 1)

  if [ -z "$ipk_filename" ]; then
    debug_log "DEBUG" "feed_package_apk: .ipk file matching prefix '$ipk_filename_prefix' not found in $repo_owner/$repo_name/${dir_path:-root}"
    if [ "$hidden_msg" != "yes" ]; then
        printf "%s\n" "$(color yellow "Package $ipk_filename_prefix (.ipk) not found in feed repository.")"
    fi
    return 1 
  fi
  debug_log "DEBUG" "feed_package_apk: Latest .ipk file found: $ipk_filename"

  local ipk_download_url
  ipk_download_url=$(echo "$JSON_RESPONSE" | jq -r --arg IPK_FILE "$ipk_filename" '.[] | select(.name == $IPK_FILE and .download_url?) | .download_url')

  if [ -z "$ipk_download_url" ] || [ "$ipk_download_url" = "null" ]; then
    debug_log "ERROR" "feed_package_apk: Failed to retrieve download URL for .ipk file: $ipk_filename"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to get download URL for $ipk_filename")"
    return 1
  fi
  debug_log "DEBUG" "feed_package_apk: .ipk download URL: $ipk_download_url"

  # --- Temporary Directory Setup for APK deployment ---
  local temp_deploy_dir
  temp_deploy_dir=$(mktemp -d -p "${AIOS_TMP_DIR:-/tmp}" "feed_apk_deploy_${pkg_admin_name}_XXXXXX")
  if [ $? -ne 0 ] || [ ! -d "$temp_deploy_dir" ]; then
    debug_log "ERROR" "feed_package_apk: Failed to create temporary directory."
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error: Could not create temporary directory.")"
    # No trap needed here yet as it's set after successful creation
    return 1
  fi
  # Set trap AFTER successful creation of temp_deploy_dir
  trap "rm -rf \"$temp_deploy_dir\" 2>/dev/null; debug_log DEBUG \"feed_package_apk: Cleaned up temp directory: $temp_deploy_dir\"" EXIT INT TERM

  local temp_download_dir="${temp_deploy_dir}/download"
  local temp_extract_ipk_dir="${temp_deploy_dir}/extract_ipk"
  local temp_extract_data_dir="${temp_deploy_dir}/extract_data"
  mkdir -p "$temp_download_dir" "$temp_extract_ipk_dir" "$temp_extract_data_dir"

  local downloaded_ipk_path="${temp_download_dir}/${ipk_filename}" # Download to temp dir
  
  if [ "$silent_mode" != "yes" ]; then
    start_spinner "$(color blue "Downloading $ipk_filename...")"
  fi

  if [ -z "$BASE_WGET" ]; then # Ensure BASE_WGET is defined
      debug_log "CRITICAL" "feed_package_apk: BASE_WGET is not defined!"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Critical error: Download command base not set.")"
      if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
      return 1
  fi
  
  eval "$BASE_WGET" -O "\"$downloaded_ipk_path\"" "\"$ipk_download_url\"" 
  local download_status=$?

  if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi

  if [ $download_status -ne 0 ]; then
      debug_log "ERROR" "feed_package_apk: Failed to download .ipk from $ipk_download_url (wget status: $download_status)"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to download $ipk_filename")"
      return 1
  fi
  if [ ! -s "$downloaded_ipk_path" ]; then 
      debug_log "ERROR" "feed_package_apk: Downloaded .ipk file is empty: $downloaded_ipk_path"
      [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Downloaded $ipk_filename is empty")"
      return 1
  fi
  debug_log "DEBUG" "feed_package_apk: .ipk downloaded successfully to: $downloaded_ipk_path"

  # --- Start of APK-specific deployment logic (replaces install_package call) ---

  # Confirmation Prompt (moved here, after download, before extraction/deployment)
  if [ "$confirm_install" = "yes" ] && [ "$silent_mode" != "yes" ]; then
    local caution_message
    caution_message=$(get_message "MSG_APK_DEPLOY_CAUTION" "pkg=$pkg_admin_name") 
    printf "\n%s\n" "$(color red "$caution_message")"

    if [ -n "$pkg_description" ]; then
      if ! confirm "MSG_CONFIRM_INSTALL_WITH_DESC" "pkg=$(color blue "$pkg_admin_name")" "desc=$(color none "$pkg_description")"; then
        debug_log "DEBUG" "feed_package_apk: User declined deployment of $pkg_admin_name."
        return 2 # User cancelled
      fi
    else
      if ! confirm "MSG_CONFIRM_INSTALL" "pkg=$(color blue "$pkg_admin_name")"; then
        debug_log "DEBUG" "feed_package_apk: User declined deployment of $pkg_admin_name."
        return 2 # User cancelled
      fi
    fi
  fi
  
  # Extraction and Deployment
  if [ "$silent_mode" != "yes" ]; then
    start_spinner "$(color blue "Extracting $ipk_filename...")"
  fi
  
  local data_tar_gz_path="${temp_extract_ipk_dir}/data.tar.gz"

  debug_log "DEBUG" "feed_package_apk: Attempting to extract data.tar.gz using 'ar' from $downloaded_ipk_path"
  if ar p "$downloaded_ipk_path" data.tar.gz > "$data_tar_gz_path" 2>/dev/null && [ -s "$data_tar_gz_path" ]; then
    debug_log "DEBUG" "feed_package_apk: Successfully extracted data.tar.gz using 'ar p'."
  elif ar x "$downloaded_ipk_path" data.tar.gz --output="$temp_extract_ipk_dir" 2>/dev/null && [ -s "$data_tar_gz_path" ]; then
    debug_log "DEBUG" "feed_package_apk: Successfully extracted data.tar.gz using 'ar x --output'."
  else
    debug_log "DEBUG" "feed_package_apk: 'ar' extraction failed or data.tar.gz not found/empty. Assuming .ipk is a direct tar.gz or contains data.tar.gz at top level."
    if tar -xzf "$downloaded_ipk_path" -C "$temp_extract_ipk_dir" ./data.tar.gz 2>/dev/null && [ -s "$data_tar_gz_path" ]; then
        debug_log "DEBUG" "feed_package_apk: Successfully extracted data.tar.gz using 'tar' from .ipk top level."
    else
        debug_log "DEBUG" "feed_package_apk: data.tar.gz not found at .ipk top level. Assuming .ipk IS the data.tar.gz equivalent (direct content)."
        cp "$downloaded_ipk_path" "$data_tar_gz_path"
        if [ $? -ne 0 ] || [ ! -s "$data_tar_gz_path" ]; then
            if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
            debug_log "ERROR" "feed_package_apk: Failed to copy .ipk as data.tar.gz for extraction or copied file is empty."
            [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error preparing .ipk for content extraction.")"
            return 1
        fi
        debug_log "DEBUG" "feed_package_apk: Copied .ipk to be treated as data.tar.gz."
    fi
  fi

  if [ ! -s "$data_tar_gz_path" ]; then
    if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
    debug_log "ERROR" "feed_package_apk: data.tar.gz could not be found or extracted, or is empty from $ipk_filename."
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Could not find or extract data.tar.gz in $ipk_filename, or it is empty.")"
    return 1
  fi

  if ! tar -xzf "$data_tar_gz_path" -C "$temp_extract_data_dir" 2>"${LOG_DIR}/feed_apk_deploy_tar_err.log"; then
    if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
    debug_log "ERROR" "feed_package_apk: Failed to extract data.tar.gz from $ipk_filename. See ${LOG_DIR}/feed_apk_deploy_tar_err.log"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Failed to extract content from $ipk_filename")"
    return 1
  fi
  if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
  debug_log "DEBUG" "feed_package_apk: Content extracted to $temp_extract_data_dir"

  if [ ! -d "$temp_extract_data_dir" ] || [ -z "$(ls -A "$temp_extract_data_dir")" ]; then
    debug_log "ERROR" "feed_package_apk: Extracted data directory is empty or does not exist: $temp_extract_data_dir"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "No content found after extraction for $pkg_admin_name")"
    return 1
  fi

  if [ "$silent_mode" != "yes" ]; then
    start_spinner "$(color blue "Deploying files for $pkg_admin_name...")"
  fi

  if ! cp -a "${temp_extract_data_dir}/." / 2>"${LOG_DIR}/feed_apk_deploy_cp_err.log"; then
    if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
    debug_log "ERROR" "feed_package_apk: Failed to copy files to root filesystem. See ${LOG_DIR}/feed_apk_deploy_cp_err.log"
    [ "$silent_mode" != "yes" ] && printf "%s\n" "$(color red "Error deploying files for $pkg_admin_name")"
    return 1
  fi
  if [ "$silent_mode" != "yes" ]; then stop_spinner_no_msg; fi
  debug_log "DEBUG" "feed_package_apk: Files deployed successfully to root filesystem."

  mkdir -p "$CACHE_DIR"
  if ! touch "$deployed_cache_file"; then
    debug_log "WARNING" "feed_package_apk: Failed to create or update deployment cache file: $deployed_cache_file"
  else
    debug_log "DEBUG" "feed_package_apk: Deployment cache file created/updated: $deployed_cache_file"
  fi

  if [ "$set_disabled" != "yes" ]; then
    if [ -d /tmp/luci-indexcache ] || [ -d /tmp/luci-modulecache ]; then
        debug_log "DEBUG" "feed_package_apk: Clearing LuCI cache."
        rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
    else
        debug_log "DEBUG" "feed_package_apk: LuCI cache paths not found, skipping clear."
    fi
  else
    debug_log "DEBUG" "feed_package_apk: LuCI cache clearing skipped due to 'disabled' option."
  fi

  if [ "$silent_mode" != "yes" ]; then
    printf "%s\n" "$(color green "$pkg_admin_name deployed successfully (apk source).")"
    if [ "$confirm_install" != "yes" ] && [ "$hidden_msg" != "yes" ]; then
        local note_message
        note_message=$(get_message "MSG_APK_DEPLOY_CAUTION" "pkg=$pkg_admin_name") # pkg_admin_name should not be colored here
        printf "\n%s\n" "$(color yellow "$note_message")"
    fi
  fi
  
  # Trap will clean up temp_deploy_dir on exit
  return 0
}
