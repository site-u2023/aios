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

# @FUNCTION: feed_package_apk
# @DESCRIPTION: Fetches and installs a specific .ipk package from a GitHub repository's content API.
#               Adheres strictly to original source structure for prerequisite handling.
# @PARAM: $1 - repo_owner (string)
# @PARAM: $2 - repo_name (string)
# @PARAM: $3 - dir_path (string, can be empty for root, or "current" for specific handling)
# @PARAM: $4 - pkg_prefix (string) - Prefix of the .ipk file to download.
# @OPTIONS: (passed through to install_package_apk)
#   yn, nolang, force, notpack, disabled, hidden, silent, desc=
# @RETURNS:
#   0: Success (package installed or skipped appropriately by downstream functions).
#   1: Error (API error, download error, prerequisite install failed, or install_package_apk failed).
feed_package_apk() {
  local confirm_install="no"
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no" # Used for message suppression in this function
  local opts=""
  local args=""
  local desc_flag="no"
  local desc_value=""
  # local silent_mode_option_present="no" # This was my addition, removing to stick to original structure

  # 引数を処理 (元のロジックを維持)
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      nolang) opts="$opts nolang" ;; 
      force) opts="$opts force" ;;   
      notpack) skip_package_db="yes"; opts="$opts notpack" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;; # 'hidden' opt itself is collected
      silent) opts="$opts silent" ;; # 'silent' opt is collected and passed
      desc=*)
        desc_flag="yes"
        desc_value="${1#desc=}"
        ;;
      *)
        args="$args \"$1\"" 
        ;;
    esac
    shift
  done

  eval "set -- $args" 
  if [ "$#" -ne 4 ]; then
    debug_log "ERROR" "feed_package_apk: Usage: feed_package_apk [opts] REPO_OWNER REPO_NAME DIR_PATH PKG_PREFIX" # English log
    # 元のソースでは silent 時のメッセージ表示制御はなかったので、そのまま表示
    printf "%s\n" "$(color red "Usage: feed_package_apk [opts] REPO_OWNER REPO_NAME DIR_PATH PKG_PREFIX")" >&2
    return 1
  fi

  local repo_owner="$1"
  local repo_name="$2"
  local dir_path="$3" 
  local pkg_prefix="$4"

  # --- PACKAGE_EXTENSION のチェック (元のロジックとメッセージ構造を維持) ---
  local PKG_EXTENSION_FROM_CACHE # 元の変数名 PACKAGE_EXTENSION はグローバルかもしれないのでローカル化
  PKG_EXTENSION_FROM_CACHE=$(cat "${CACHE_DIR}/extension.ch" 2>/dev/null)

  if [ -z "$PKG_EXTENSION_FROM_CACHE" ]; then
      debug_log "ERROR" "feed_package_apk: Package extension cache file not found or empty: ${CACHE_DIR}/extension.ch" # English log
      # 元のソースにはこの特定のエラーメッセージはなかったが、デバッグログは適切
      # ユーザーへのメッセージは元の printf "%s\n" "$(color yellow "feed_package currently only supports .ipk")" に近い形にするか、
      # より汎用的なエラーメッセージにする。ここではキャッシュファイルエラーとして表示。
      printf "%s\n" "$(color red "Error: Package extension configuration missing or unreadable.")"
      return 1
  fi
  # 元のソースではグローバル変数 PACKAGE_EXTENSION を参照していた。ここではローカル変数を使用。
  if [ "$PKG_EXTENSION_FROM_CACHE" != "ipk" ]; then
      # メッセージは元のものを尊重
      # debug_log は現状維持
      debug_log "INFO" "feed_package_apk: Current package extension is '$PKG_EXTENSION_FROM_CACHE', this function supports 'ipk'." # English log
      # 元のソースのメッセージ
      if [ "$hidden" != "yes" ]; then # 'hidden' オプションで抑制
          printf "%s\n" "$(color yellow "feed_package currently only supports .ipk")"
      fi
      return 1 
  fi
  # --- End of PACKAGE_EXTENSION のチェック ---

  # --- 前提パッケージ (jq, ca-certificates) のインストール (元のロジックを完全に維持) ---
  debug_log "DEBUG" "feed_package_apk: Checking/Installing required packages: jq and ca-certificates via install_package_apk" # English log
  # 元のソースでは 'silent' オプションを渡していた
  if ! install_package_apk jq silent; then # ★★★ 元の呼び出しを維持 ★★★
      debug_log "ERROR" "feed_package_apk: Failed to install required package: jq (via install_package_apk)" # English log
      printf "%s\n" "$(color red "Error: Failed to install prerequisite jq.")" # 元のメッセージ
      return 1
  fi
  if ! install_package_apk ca-certificates silent; then # ★★★ 元の呼び出しを維持 ★★★
      debug_log "ERROR" "feed_package_apk: Failed to install required package: ca-certificates (via install_package_apk)" # English log
      printf "%s\n" "$(color red "Error: Failed to install prerequisite ca-certificates.")" # 元のメッセージ
      return 1
  fi

  # jq が実際に利用可能かのコマンドチェック (元のソースのものを維持)
  if ! command -v jq >/dev/null 2>&1; then
      debug_log "ERROR" "feed_package_apk: jq command not found or not executable after installation attempt." # English log
      printf "%s\n" "$(color red "Error: jq command is required but not available.")" # 元のメッセージ
      return 1
  fi
  # --- End of 前提パッケージのインストール ---

  # output_file は元の pkg_prefix ベースの名前に戻す (ダウンロードファイル名が異なる場合の問題は別途検討)
  local output_file="${FEED_DIR}/${pkg_prefix}.${PKG_EXTENSION_FROM_CACHE}"
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/contents"
  
  local effective_dir_path="$dir_path"
  if [ "$dir_path" = "current" ] || [ -z "$dir_path" ]; then
      effective_dir_path="" 
      debug_log "DEBUG" "feed_package_apk: dir_path is '$dir_path', targeting repository root." # English log
  fi

  if [ -n "$effective_dir_path" ]; then 
      api_url="${api_url}/${effective_dir_path}"
  fi

  debug_log "DEBUG" "feed_package_apk: Fetching package list from GitHub API: $api_url" # English log

  local JSON_RESPONSE
  JSON_RESPONSE=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$api_url") # 元の User-Agent "aios-pkg/1.0"
  local wget_status=$? 

  if [ $wget_status -ne 0 ] || [ -z "$JSON_RESPONSE" ]; then 
    debug_log "ERROR" "feed_package_apk: Could not retrieve data from API: $api_url (wget status: $wget_status)" # English log
    # メッセージは元のものを尊重
    printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: API connection error")"
    return 1
  fi

  # APIエラーメッセージのチェック (元のロジックに近い形に戻しつつ、jqでの抽出は維持)
  # 元のソースは "API rate limit exceeded" の grep と、jq -e '.[0]' での配列チェックのみだった。
  # ここでは、より汎用的なエラーメッセージ抽出を試みるが、元の構造を意識する。
  local is_json_object_error="no"
  if echo "$JSON_RESPONSE" | jq -e 'type=="object" and .message' > /dev/null 2>&1; then
    is_json_object_error="yes"
  fi

  if [ "$is_json_object_error" = "yes" ]; then
      local api_error_message
      api_error_message=$(echo "$JSON_RESPONSE" | jq -r '.message')
      debug_log "ERROR" "feed_package_apk: GitHub API error for $api_url: $api_error_message" # English log
      # 元のソースでは "API rate limit exceeded" の場合と、それ以外の "Unknown API error" / ".message" を表示していた。
      # ここでは抽出できた message をそのまま表示する。
      printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: $api_error_message")"
      return 1
  elif ! echo "$JSON_RESPONSE" | jq -e 'type=="array"' > /dev/null 2>&1; then # Not an object error, but also not an array
      debug_log "ERROR" "feed_package_apk: API response is not a JSON array as expected: $api_url." # English log
      printf "%s\n" "$(color red "Failed to retrieve package list for $pkg_prefix: Unexpected API response format")"
      return 1
  fi
  
  # ファイル検索 (元の grep と sort -V を使用する形に戻す)
  local pkg_file_found
  pkg_file_found=$(echo "$JSON_RESPONSE" | jq -r '.[].name' | grep "^${pkg_prefix}_.*\.${PKG_EXTENSION_FROM_CACHE}$" | sort -V | tail -n 1)

  if [ -z "$pkg_file_found" ]; then
    debug_log "DEBUG" "feed_package_apk: Package file matching prefix '$pkg_prefix' not found in $repo_owner/$repo_name/${effective_dir_path:-root}" # English log
    if [ "$hidden" != "yes" ]; then # 'hidden' オプションで抑制
        printf "%s\n" "$(color yellow "Package $pkg_prefix not found in feed repository.")" # 元のメッセージ
    fi
    return 0 
  fi

  debug_log "DEBUG" "feed_package_apk: Latest package file found: $pkg_file_found" # English log

  local download_url
  download_url=$(echo "$JSON_RESPONSE" | jq -r --arg PKG "$pkg_file_found" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then 
    debug_log "ERROR" "feed_package_apk: Failed to retrieve download URL for file: $pkg_file_found" # English log
    printf "%s\n" "$(color red "Failed to retrieve download URL for package $pkg_prefix")" # 元のメッセージ
    return 1
  fi

  debug_log "DEBUG" "feed_package_apk: Package download URL: $download_url" # English log
  # output_file は pkg_prefix ベースの名前に戻した。
  # もし pkg_file_found (実際のファイル名) を使いたい場合は、その旨指示が必要。
  debug_log "DEBUG" "feed_package_apk: Output file path: $output_file" # English log

  mkdir -p "$FEED_DIR"
  eval "$BASE_WGET" -O "\"$output_file\"" "\"$download_url\"" 
  local download_status=$?
  if [ $download_status -ne 0 ]; then
      debug_log "ERROR" "feed_package_apk: Failed to download package from $download_url (wget status: $download_status)" # English log
      printf "%s\n" "$(color red "Failed to download package $pkg_prefix")" # 元のメッセージ
      rm -f "$output_file" 2>/dev/null
      return 1
  fi
  # ダウンロード後の空ファイルチェックは有用なので維持
  if [ ! -s "$output_file" ]; then 
      debug_log "ERROR" "feed_package_apk: Downloaded package file is empty: $output_file" # English log
      printf "%s\n" "$(color red "Failed to download package $pkg_prefix (empty file)")"
      rm -f "$output_file" 2>/dev/null
      return 1
  fi

  debug_log "DEBUG" "feed_package_apk: Package downloaded successfully: $(ls -lh "$output_file" 2>/dev/null || echo "$output_file")" # English log

  local install_status=0
  local effective_opts=$(echo "$opts" | sed 's/desc=[^ ]* *//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

  if [ "$desc_flag" = "yes" ]; then 
    debug_log "DEBUG" "feed_package_apk: Calling install_package_apk for '$output_file' with opts '$effective_opts' and desc '$desc_value'" # English log
    install_package_apk "$output_file" $effective_opts "desc=$desc_value"
    install_status=$?
  else
    debug_log "DEBUG" "feed_package_apk: Calling install_package_apk for '$output_file' with opts '$effective_opts'" # English log
    install_package_apk "$output_file" $effective_opts
    install_status=$?
  fi

  debug_log "DEBUG" "feed_package_apk: install_package_apk finished for feed package $pkg_prefix with status: $install_status" # English log

  case $install_status in
      0|3)
          debug_log "DEBUG" "feed_package_apk: Completed successfully for $pkg_prefix (install_status: $install_status)" # English log
          return 0 
          ;;
      1|2)
          debug_log "INFO" "feed_package_apk: Failed or was cancelled for $pkg_prefix (install_status: $install_status)" # English log
          return 1 
          ;;
      *)
          debug_log "ERROR" "feed_package_apk: Unexpected status $install_status from install_package_apk for $pkg_prefix" # English log
          return 1 
          ;;
  esac
}

install_package_apk() {
    if ! parse_package_options_apk "$@"; then 
        debug_log "ERROR" "install_package_apk: Failed to parse package options." # English log
        return 1 
    fi
    if [ "$PKG_OPTIONS_LIST" = "yes" ]; then
        if [ "$PKG_OPTIONS_SILENT" != "yes" ]; then
            check_install_list # check_install_list は既存と仮定
        fi
        return 0 
    fi

    local BASE_NAME="" 
    if [ -n "$PKG_OPTIONS_PACKAGE_NAME" ]; then
        BASE_NAME=$(basename "$PKG_OPTIONS_PACKAGE_NAME" .ipk)
        BASE_NAME=$(basename "$BASE_NAME" .apk) 
    fi
    local lang_code
    lang_code=$(get_language_code) # get_language_code は既存と仮定

    local process_status=0
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
    process_status=$? 

    debug_log "DEBUG" "install_package_apk: process_package finished for $BASE_NAME with status: $process_status" # English log

    case $process_status in
        0) 
           ;;
        1) 
           debug_log "ERROR" "install_package_apk: Error occurred during package processing for $BASE_NAME." # English log
           return 1 
           ;;
        2) 
           debug_log "DEBUG" "install_package_apk: User cancelled installation for $BASE_NAME." # English log
           return 2 
           ;;
        3) 
           debug_log "DEBUG" "install_package_apk: New installation successful for $BASE_NAME. Proceeding to service configuration." # English log
           if [ "$PKG_OPTIONS_DISABLED" != "yes" ]; then
               configure_service "$PKG_OPTIONS_PACKAGE_NAME" "$BASE_NAME" # configure_service は既存と仮定
           else
               debug_log "DEBUG" "install_package_apk: Skipping service handling for $BASE_NAME due to disabled option." # English log
           fi
           ;;
        *) 
           debug_log "ERROR" "install_package_apk: Unexpected status $process_status received from process_package for $BASE_NAME." # English log
           return 1 
           ;;
    esac

    return $process_status
}

install_normal_package_apk() {
    local package_name="$1"        # Full path to the .ipk file
    local force_install="$2"       # See @PARAM description
    local silent_mode="$3"
    
    # 表示用の名前を作成（パスと拡張子を除去） - 元の関数の仕様を維持
    local display_name
    display_name=$(basename "$package_name")
    display_name=${display_name%.ipk}  # .ipk 拡張子を確実に除去 (元は display_name=${display_name%.*})

    debug_log "DEBUG" "Starting custom APK installation process for: $package_name" # English log
    debug_log "DEBUG" "Display name for messages: $display_name" # English log

    # silent モードが有効でない場合のみスピナーを開始 - 元の関数の仕様を維持
    if [ "$silent_mode" != "yes" ]; then
        start_spinner "$(color blue "$display_name $(get_message "MSG_INSTALLING_PACKAGE")")"
    fi

    # --- Custom IPK extraction and deployment logic ---
    local temp_deploy_dir
    temp_deploy_dir=$(mktemp -d -p "${AIOS_TMP_DIR:-/tmp}" "install_apk_${display_name}_XXXXXX")
    if [ $? -ne 0 ] || [ ! -d "$temp_deploy_dir" ]; then
        debug_log "ERROR" "install_normal_package_apk: Failed to create temporary directory." # English log
        if [ "$silent_mode" != "yes" ]; then
            stop_spinner "$(color red "Failed to install package $display_name")"
        else
            printf "%s\n" "$(color red "Failed to install package $display_name")"
        fi
        return 1
    fi
    trap "rm -rf \"$temp_deploy_dir\" 2>/dev/null; debug_log DEBUG \"install_normal_package_apk: Cleaned up temp directory: $temp_deploy_dir\"" EXIT INT TERM # English log

    local temp_extract_ipk_dir="${temp_deploy_dir}/extract_ipk"
    local temp_extract_data_dir="${temp_deploy_dir}/extract_data"
    mkdir -p "$temp_extract_ipk_dir" "$temp_extract_data_dir"

    local data_tar_gz_path="${temp_extract_ipk_dir}/data.tar.gz"
    local extraction_ok="no"

    debug_log "DEBUG" "install_normal_package_apk: Attempting to extract data.tar.gz using 'ar' from $package_name" # English log

    if ar p "$package_name" data.tar.gz > "$data_tar_gz_path" 2>/dev/null && [ -f "$data_tar_gz_path" ] && [ -s "$data_tar_gz_path" ]; then
        debug_log "DEBUG" "install_normal_package_apk: Successfully extracted data.tar.gz using 'ar p'." # English log
        extraction_ok="yes"
    elif ar x "$package_name" data.tar.gz --output="$temp_extract_ipk_dir" 2>/dev/null && [ -f "$data_tar_gz_path" ] && [ -s "$data_tar_gz_path" ]; then
        debug_log "DEBUG" "install_normal_package_apk: Successfully extracted data.tar.gz using 'ar x --output'." # English log
        extraction_ok="yes"
    else
        debug_log "DEBUG" "install_normal_package_apk: 'ar' extraction failed. Assuming .ipk is a direct tar.gz or contains data.tar.gz at top level." # English log
        if tar -xzf "$package_name" -C "$temp_extract_ipk_dir" ./data.tar.gz 2>/dev/null && [ -f "$data_tar_gz_path" ] && [ -s "$data_tar_gz_path" ]; then
            debug_log "DEBUG" "install_normal_package_apk: Successfully extracted data.tar.gz using 'tar' from .ipk top level." # English log
            extraction_ok="yes"
        else
            debug_log "DEBUG" "install_normal_package_apk: data.tar.gz not found at .ipk top level. Assuming .ipk IS the data.tar.gz equivalent." # English log
            cp "$package_name" "$data_tar_gz_path"
            if [ $? -eq 0 ] && [ -s "$data_tar_gz_path" ]; then
                debug_log "DEBUG" "install_normal_package_apk: Copied .ipk to be treated as data.tar.gz." # English log
                extraction_ok="yes"
            else
                debug_log "ERROR" "install_normal_package_apk: Failed to copy .ipk as data.tar.gz or copied file is empty." # English log
                if [ "$silent_mode" != "yes" ]; then
                    stop_spinner "$(color red "Failed to install package $display_name")"
                else
                    printf "%s\n" "$(color red "Failed to install package $display_name")"
                fi
                trap - EXIT INT TERM 
                rm -rf "$temp_deploy_dir" 2>/dev/null 
                return 1
            fi
        fi
    fi

    if [ "$extraction_ok" != "yes" ]; then 
        debug_log "ERROR" "install_normal_package_apk: data.tar.gz could not be found or extracted from $display_name." # English log
        if [ "$silent_mode" != "yes" ]; then
            stop_spinner "$(color red "Failed to install package $display_name")"
        else
            printf "%s\n" "$(color red "Failed to install package $display_name")"
        fi
        trap - EXIT INT TERM 
        rm -rf "$temp_deploy_dir" 2>/dev/null
        return 1
    fi

    debug_log "DEBUG" "install_normal_package_apk: Extracting content from $data_tar_gz_path to $temp_extract_data_dir" # English log
    if ! tar -xzf "$data_tar_gz_path" -C "$temp_extract_data_dir" 2>"${LOG_DIR}/install_apk_tar_err.log"; then
        debug_log "ERROR" "install_normal_package_apk: Failed to extract data.tar.gz. See ${LOG_DIR}/install_apk_tar_err.log" # English log
        if [ "$silent_mode" != "yes" ]; then
            stop_spinner "$(color red "Failed to install package $display_name")"
        else
            printf "%s\n" "$(color red "Failed to install package $display_name")"
        fi
        trap - EXIT INT TERM
        rm -rf "$temp_deploy_dir" 2>/dev/null
        return 1
    fi
    debug_log "DEBUG" "install_normal_package_apk: Content extracted to $temp_extract_data_dir" # English log

    if [ ! -d "$temp_extract_data_dir" ] || [ -z "$(ls -A "$temp_extract_data_dir")" ]; then
        debug_log "ERROR" "install_normal_package_apk: Extracted data directory is empty or does not exist: $temp_extract_data_dir" # English log
        if [ "$silent_mode" != "yes" ]; then
            stop_spinner "$(color red "Failed to install package $display_name")" 
        else
            printf "%s\n" "$(color red "Failed to install package $display_name")"
        fi
        trap - EXIT INT TERM
        rm -rf "$temp_deploy_dir" 2>/dev/null
        return 1
    fi

    debug_log "DEBUG" "install_normal_package_apk: Deploying files to root filesystem from $temp_extract_data_dir" # English log
    if ! cp -a "${temp_extract_data_dir}/." / 2>"${LOG_DIR}/install_apk_cp_err.log"; then
        debug_log "ERROR" "install_normal_package_apk: Failed to copy files to root filesystem. See ${LOG_DIR}/install_apk_cp_err.log" # English log
        if [ "$silent_mode" != "yes" ]; then
            stop_spinner "$(color red "Failed to install package $display_name")"
        else
            printf "%s\n" "$(color red "Failed to install package $display_name")"
        fi
        trap - EXIT INT TERM
        rm -rf "$temp_deploy_dir" 2>/dev/null
        return 1
    fi
    debug_log "DEBUG" "install_normal_package_apk: Files deployed successfully to root filesystem." # English log

    if [ -d /tmp/luci-indexcache ] || [ -d /tmp/luci-modulecache ]; then
        debug_log "DEBUG" "install_normal_package_apk: Clearing LuCI cache." # English log
        rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null 
    else
        debug_log "DEBUG" "install_normal_package_apk: LuCI cache paths not found, skipping clear." # English log
    fi

    if [ "$silent_mode" != "yes" ]; then
        stop_spinner "$(color green "$display_name $(get_message "MSG_INSTALL_SUCCESS")")"
    fi
    
    trap - EXIT INT TERM 
    rm -rf "$temp_deploy_dir" 2>/dev/null 
    return 0
}

parse_package_options_apk() {
    # 変数初期化（既存の変数）
    PKG_OPTIONS_CONFIRM="no"
    PKG_OPTIONS_SKIP_LANG="no"
    PKG_OPTIONS_FORCE="no"
    PKG_OPTIONS_SKIP_PACKAGE_DB="no"
    PKG_OPTIONS_DISABLED="no"
    PKG_OPTIONS_HIDDEN="no"
    PKG_OPTIONS_TEST="no"
    # PKG_OPTIONS_UPDATE="no" # ★★★ Removed: update option is not used for APK feed
    PKG_OPTIONS_UNFORCE="no"
    PKG_OPTIONS_LIST="no"
    PKG_OPTIONS_PACKAGE_NAME=""
    PKG_OPTIONS_SILENT="no"
    
    # 変数初期化：説明文用
    PKG_OPTIONS_DESCRIPTION=""
    # PKG_OPTIONS_PACKAGE_UPDATE="" # ★★★ Removed: related to update option

    # 引数のデバッグ出力
    debug_log "DEBUG" "parse_package_options_apk: Received arguments ($#): $*" # English log
    
    # オプション解析
    while [ $# -gt 0 ]; do
        # 現在処理中の引数をデバッグ出力
        debug_log "DEBUG" "parse_package_options_apk: Processing argument: $1" # English log
        
        case "$1" in
            yn) PKG_OPTIONS_CONFIRM="yes"; debug_log "DEBUG" "Option: confirm=yes" ;;
            nolang) PKG_OPTIONS_SKIP_LANG="yes"; debug_log "DEBUG" "Option: skip_lang=yes" ;;
            force) PKG_OPTIONS_FORCE="yes"; debug_log "DEBUG" "Option: force=yes" ;;
            notpack) PKG_OPTIONS_SKIP_PACKAGE_DB="yes"; debug_log "DEBUG" "Option: skip_package_db=yes" ;;
            disabled) PKG_OPTIONS_DISABLED="yes"; debug_log "DEBUG" "Option: disabled=yes" ;;
            hidden) PKG_OPTIONS_HIDDEN="yes"; debug_log "DEBUG" "Option: hidden=yes" ;;
            test) PKG_OPTIONS_TEST="yes"; debug_log "DEBUG" "Option: test=yes" ;;
            silent) PKG_OPTIONS_SILENT="yes"; debug_log "DEBUG" "Option: silent=yes" ;;
            desc=*) 
                PKG_OPTIONS_DESCRIPTION="${1#desc=}"
                debug_log "DEBUG" "Option: description=$PKG_OPTIONS_DESCRIPTION" 
                ;;
            unforce) PKG_OPTIONS_UNFORCE="yes"; debug_log "DEBUG" "Option: unforce=yes" ;;
            list) PKG_OPTIONS_LIST="yes"; debug_log "DEBUG" "Option: list=yes" ;;
            -*) 
                debug_log "ERROR" "parse_package_options_apk: Unknown option: $1" # English log
                return 1 
                ;;
            *)
                if [ -z "$PKG_OPTIONS_PACKAGE_NAME" ]; then
                    PKG_OPTIONS_PACKAGE_NAME="$1"
                    debug_log "DEBUG" "Package name: $PKG_OPTIONS_PACKAGE_NAME"
                else
                    if [ -z "$PKG_OPTIONS_DESCRIPTION" ]; then # desc= で設定されていなければ
                        debug_log "DEBUG" "Additional argument treated as description: $1" # English log
                        PKG_OPTIONS_DESCRIPTION="$1"
                    else
                        debug_log "DEBUG" "Additional argument ignored as description already set by desc=: $1" # English log
                    fi
                fi
                ;;
        esac
        shift
    done
    
    # パッケージ名が指定されていない場合の処理
    # ★★★ Removed: PKG_OPTIONS_UPDATE condition from here ★★★
    if [ -z "$PKG_OPTIONS_PACKAGE_NAME" ] && [ "$PKG_OPTIONS_LIST" != "yes" ]; then
        debug_log "ERROR" "parse_package_options_apk: No package name specified and not in list mode." # English log
        return 1
    fi
    
    # オプションに関する情報を出力
    debug_log "DEBUG" "parse_package_options_apk: Options parsed: confirm=$PKG_OPTIONS_CONFIRM, force=$PKG_OPTIONS_FORCE, silent=$PKG_OPTIONS_SILENT, description='$PKG_OPTIONS_DESCRIPTION', package_name='$PKG_OPTIONS_PACKAGE_NAME'" # English log
    
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

# @FUNCTION: process_package
# @DESCRIPTION: Main package processing logic. Aggressively slimmed for APK feed.
#               Calls install_normal_package_apk for actual deployment.
#               Removes language pack handling, pre-install checks, and local_package_db.
# @PARAM: $1 - package_name (string) - Full path to the .ipk package file.
# @PARAM: $2 - base_name (string) - Base name of the package.
# @PARAM: $3 - confirm_install_option (string "yes"|"no") - Original 'yn' option.
# @PARAM: $4 - force_install (string "yes"|"no") - Force installation.
# @PARAM: $5 - skip_package_db (string "yes"|"no") - No longer used as local_package_db is removed. Kept for signature compatibility if needed by caller.
# @PARAM: $6 - set_disabled (string "yes"|"no") - Option to disable services.
# @PARAM: $7 - test_mode (string "yes"|"no") - No longer has significant effect as pre-install is removed. Kept for signature.
# @PARAM: $8 - lang_code (string) - No longer used as i18n logic is removed. Kept for signature.
# @PARAM: $9 - description (string) - Package description for confirmation.
# @PARAM: ${10} - silent_mode (string "yes"|"no") - Suppress messages.
# @RETURNS:
#   0: Success (User declined non-critical step OR if legacy meaning of 0 from local_package_db failure was intended for some skips).
#      For APK feed, typically means install attempt was made and either succeeded or user cancelled.
#      If install_normal_package_apk succeeds, it will proceed to return 3 (new install).
#   1: Error (Installation failed via install_normal_package_apk).
#   2: User cancelled (Declined 'yn' prompt for installation).
#   3: New install success (Package installed successfully).
process_package() {
    local package_name="$1"
    local base_name="$2"
    local confirm_install_option="$3"
    local force_install="$4"
    # local skip_package_db="$5" # ★★★ No longer used internally, local_package_db removed ★★★
    local set_disabled="$6"
    # local test_mode="$7"       # ★★★ No longer used internally, package_pre_install removed ★★★
    # local lang_code="$8"       # ★★★ No longer used internally, i18n logic removed ★★★
    local description="$9"
    local silent_mode="${10}"

    # --- PACKAGE_INSTALL_MODE による確認処理の変更 (元のロジック維持) ---
    local current_install_mode="${PACKAGE_INSTALL_MODE:-manual}"
    local actual_confirm_install="$confirm_install_option" 

    if [ "$current_install_mode" = "auto" ]; then
        debug_log "DEBUG" "process_package: PACKAGE_INSTALL_MODE is 'auto'. Overriding confirm_install to 'no'." # English log
        actual_confirm_install="no" 
    fi
    # --- ここまで ---

    # YN確認 (元のロジック維持、actual_confirm_install を使用)
    if [ "$actual_confirm_install" = "yes" ] && [ "$silent_mode" != "yes" ]; then
        local display_name_confirm
        display_name_confirm="$base_name" # base_name を表示に使う
        
        debug_log "DEBUG" "process_package: Confirming installation for display name: $display_name_confirm" # English log

        # 説明文の取得ロジックは維持 (desc= オプションまたは get_package_description)
        # get_package_description がAPKの .ipk ファイルから説明を抽出できるか、
        # あるいは feed_package_apk が desc= で渡すことが前提となる。
        if [ -z "$description" ]; then
            description=$(get_package_description "$package_name") 
            debug_log "DEBUG" "process_package: Using repository description: $description" # English log
        else
            debug_log "DEBUG" "process_package: Using provided description: $description" # English log
        fi

        local colored_name_confirm
        colored_name_confirm=$(color blue "$display_name_confirm") 

        local confirm_result=0
        if [ -n "$description" ]; then
            if ! confirm "MSG_CONFIRM_INSTALL_WITH_DESC" "pkg=$colored_name_confirm" "desc=$description"; then 
                confirm_result=1
            fi
        else
            if ! confirm "MSG_CONFIRM_INSTALL" "pkg=$colored_name_confirm"; then 
                confirm_result=1
            fi
        fi

        if [ $confirm_result -ne 0 ]; then
            debug_log "DEBUG" "process_package: User declined installation of $display_name_confirm" # English log
            return 2 
        fi
    elif [ "$actual_confirm_install" = "yes" ] && [ "$silent_mode" = "yes" ]; then
        debug_log "DEBUG" "process_package: Silent mode enabled, skipping confirmation for $package_name (original yn was 'yes')" # English log
    elif [ "$confirm_install_option" = "yes" ] && [ "$current_install_mode" = "auto" ]; then
        debug_log "DEBUG" "process_package: Auto mode: Confirmation for $package_name skipped (original yn was 'yes')." # English log
    fi
    
    # パッケージのインストール: install_normal_package_apk を呼び出す
    if ! install_normal_package_apk "$package_name" "$force_install" "$silent_mode"; then 
        debug_log "ERROR" "process_package: Failed to install package using install_normal_package_apk: $package_name" # English log
        return 1 
    fi

    # サービス設定の呼び出し (install_normal_package_apk 成功後)
    if [ "$set_disabled" != "yes" ]; then
        debug_log "DEBUG" "process_package: Attempting to configure service for $base_name." # English log
        configure_service "$package_name" "$base_name" # configure_service は既存と仮定
    else
        debug_log "DEBUG" "process_package: Skipping service configuration for $base_name due to disabled option." # English log
    fi

    debug_log "DEBUG" "process_package: Package $package_name processed successfully (New Install)." # English log
    return 3 
}
