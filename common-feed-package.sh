#!/bin/sh

SCRIPT_VERSION="2025.04.10-00-00"

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
# ✅ Use command -v instead of which or type for command existence check
# ✅ Keep scripts modular with small, focused functions
# ✅ Use simple error handling instead of complex traps
# ✅ Test scripts with ash/dash explicitly, not just bash
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
### =========================================================

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
# Last Update: 2025-03-04 10:00:00 (JST) 🚀
# install_build: Package build processing (OpenWrt / Alpine Linux)
# Script to retrieve the latest files for a specified package using the GitHub API
# Function: feed_package
# Description:
#   Uses the GitHub API to retrieve a list of files from a specific directory in a specified repository,
#   matching the package name prefix, and saves the alphabetically last one (assumed to be the latest)
#   to the download destination.
#   If DIR_PATH is not specified, it automatically explores the repository's top directory,
#   and automatically selects the appropriate directory.
#
# Arguments:
#   $1 : Repository owner (e.g., gSpotx2f)
#   $2 : Repository name (e.g., packages-openwrt)
#   $3 : Directory path (e.g., current)
#   $4 : Package name prefix (e.g., luci-app-cpu-perf)
#   $5 : Output file after download (e.g., /tmp/luci-app-cpu-perf_all.ipk)
#
# Usage:
# feed_package ["yn"] ["hidden"] "repository_owner" "repository_name" "directory" "package_name"
# Example: Default (install without confirmation)
# feed_package "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
# Example: Install with confirmation
# feed_package "yn" "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
# Example: No message if already installed
# feed_package "hidden" "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
# Example: Specify `yn` and `hidden` in any order
# feed_package "hidden" "yn" "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
#
# New specifications:
# 1. If DIR_PATH is empty, explore the repository's top directory and automatically select the optimal directory.
# 2. Handle additional arguments for options (yn, hidden, force, disabled, etc.).
# 3. Retrieve the latest package information from GitHub API, download and install.
#########################################################################
feed_package() {
  local confirm_install="no"
  local skip_lang_pack="no"
  local force_install="no"
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""   # Variable to store options
  local args=""   # Variable to store regular arguments

  # Scan arguments and separate options and regular arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;   # yn option
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;; # nolang option
      force) force_install="yes"; opts="$opts force" ;;   # force option
      notpack) skip_package_db="yes"; opts="$opts notpack" ;; # notpack option
      disabled) set_disabled="yes"; opts="$opts disabled" ;; # disabled option
      hidden) hidden="yes"; opts="$opts hidden" ;; # hidden option
      desc=*) opts="$opts $1" ;;   # 説明オプション処理を追加
      *) args="$args $1" ;;        # Store regular arguments
    esac
    shift
  done

  # Check if there are 4 required arguments
  set -- $args
  if [ "$#" -ne 4 ]; then
    debug_log "DEBUG" "Required arguments (REPO_OWNER, REPO_NAME, DIR_PATH, PKG_PREFIX) are missing." >&2
    return 1
  fi

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")

  if [ -n "$PACKAGE_EXTENSION" ]; then
      debug_log "DEBUG" "Content of PACKAGE_EXTENSION: $PACKAGE_EXTENSION"
      
      # Routine to be removed in the future
      if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
          printf "%s\n" "$(color yellow "Currently not supported for apk.")"
          return 1
      fi
  else
      debug_log "DEBUG" "File not found or empty: ${CACHE_DIR}/extension.ch"
      return 1
  fi

  debug_log "DEBUG" "Installing required package: jq"
  install_package jq hidden

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.${PACKAGE_EXTENSION}"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"
  
  debug_log "DEBUG" "Fetching data from GitHub API: $API_URL"

  # If DIR_PATH is not specified, auto-completion
  if [ -z "$DIR_PATH" ]; then
    # If directory is empty, explore the repository's top directory
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/"
    debug_log "DEBUG" "DIR_PATH not specified, exploring repository's top directory"
  fi

  # Retrieve data from API
  local JSON
  JSON=$(wget --no-check-certificate -qO- "$API_URL")

  if [ -z "$JSON" ]; then
    debug_log "DEBUG" "Could not retrieve data from API."
    printf "%s\n" "$(color white "Could not retrieve data from API.")"
    return 0  # Continue processing even if an error occurs
  fi

  # Get the latest package file
  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r '.[].name' | grep "^${PKG_PREFIX}_" | sort | tail -n 1)

  if [ -z "$PKG_FILE" ]; then
    debug_log "DEBUG" "$PKG_PREFIX not found."
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color white "$PKG_PREFIX not found.")"
    return 0  # Continue processing even if an error occurs
  fi

  debug_log "DEBUG" "NEW PACKAGE: $PKG_FILE"

  # Get download URL
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$DOWNLOAD_URL" ]; then
    debug_log "DEBUG" "Failed to retrieve package information."
    printf "%s\n" "$(color white "Failed to retrieve package information.")"
    return 0  # Continue processing even if an error occurs
  fi

  debug_log "DEBUG" "OUTPUT FILE: $OUTPUT_FILE"
  debug_log "DEBUG" "DOWNLOAD URL: $DOWNLOAD_URL"

  eval "$BASE_WGET" -O "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0  # Continue processing even if an error occurs

  debug_log "DEBUG" "$(ls -lh "$OUTPUT_FILE")"
  debug_log "DEBUG" "Attempting to install package: $PKG_PREFIX with options: $opts"

  # evalを使わずに直接呼び出し
  install_package "$OUTPUT_FILE" $opts || return 0
  
  return 0
}

feed_package_release() {
  local confirm_install="no"
  local skip_lang_pack="no"
  local force_install="no"
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""
  local args=""

  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;;
      force) force_install="yes"; opts="$opts force" ;;
      notpack) skip_package_db="yes"; opts="$opts notpack" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;;
      desc=*) opts="$opts $1" ;;
      *) args="$args $1" ;;
    esac
    shift
  done

  set -- $args
  if [ "$#" -lt 2 ]; then
    debug_log "DEBUG" "Required arguments (REPO_OWNER, REPO_NAME, PKG_PREFIX) are missing." >&2
    return 1
  fi

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")

  if [ -n "$PACKAGE_EXTENSION" ]; then
      debug_log "DEBUG" "Content of PACKAGE_EXTENSION: $PACKAGE_EXTENSION"
      
      # Routine to be removed in the future
      if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
          printf "%s\n" "$(color yellow "Currently not supported for apk.")"
          return 1
      fi
  else
      debug_log "DEBUG" "File not found or empty: ${CACHE_DIR}/extension.ch"
      return 1
  fi
  
  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local PKG_PREFIX="${REPO_NAME}"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.${PACKAGE_EXTENSION}"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"
  
  debug_log "DEBUG" "Fetching data from GitHub API: $API_URL"

  local JSON
  JSON=$(wget --no-check-certificate -qO- "$API_URL")

  if [ -z "$JSON" ];then
    debug_log "DEBUG" "Could not retrieve data from API."
    printf "%s\n" "$(color white "Could not retrieve data from API.")"
    return 0
  fi

  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r --arg PKG_PREFIX "$PKG_PREFIX" '.[] | .assets[] | select(.name | startswith($PKG_PREFIX)) | .name' | sort | tail -n 1)

  if [ -z "$PKG_FILE" ];then
    debug_log "DEBUG" "$PKG_PREFIX not found."
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color white "$PKG_PREFIX not found.")"
    return 0
  fi

  debug_log "DEBUG" "NEW PACKAGE: $PKG_FILE"

  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | .assets[] | select(.name == $PKG) | .browser_download_url')

  if [ -z "$DOWNLOAD_URL" ];then
    debug_log "DEBUG" "Failed to retrieve package information."
    printf "%s\n" "$(color white "Failed to retrieve package information.")"
    return 0
  fi

  debug_log "DEBUG" "OUTPUT FILE: $OUTPUT_FILE"
  debug_log "DEBUG" "DOWNLOAD URL: $DOWNLOAD_URL"

  eval "$BASE_WGET" -O "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0  # Continue processing even if an error occurs

  debug_log "DEBUG" "$(ls -lh "$OUTPUT_FILE")"
  debug_log "DEBUG" "Attempting to install package: $PKG_PREFIX"

  install_package "$OUTPUT_FILE" $opts || return 0
  
  return 0
}
