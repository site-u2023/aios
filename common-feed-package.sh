#!/bin/sh

SCRIPT_VERSION="2025.04.11-00-01"

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
#########################################################################
# Last Update: 2025-04-12 05:16:23 (UTC) 🚀
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
#########################################################################
feed_package() {
  local confirm_install="no"
  local skip_lang_pack="no"
  local force_install="no"
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""   # オプションを格納する変数
  local args=""   # 通常引数を格納する変数
  local desc_flag="no"  # 説明文処理中フラグ
  local desc_value=""   # 説明文の値を保持

  # 引数を処理
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;   # yn オプション
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;; # nolang オプション
      force) force_install="yes"; opts="$opts force" ;;   # force オプション
      notpack) skip_package_db="yes"; opts="$opts notpack" ;; # notpack オプション
      disabled) set_disabled="yes"; opts="$opts disabled" ;; # disabled オプション
      hidden) hidden="yes"; opts="$opts hidden" ;; # hidden オプション
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

  # 必須引数が揃っているかチェック
  set -- $args
  if [ "$#" -ne 4 ]; then
    debug_log "DEBUG" "Required arguments (REPO_OWNER, REPO_NAME, DIR_PATH, PKG_PREFIX) are missing." >&2
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
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.${PACKAGE_EXTENSION}"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"
  
  debug_log "DEBUG" "Fetching data from GitHub API: $API_URL"

  # DIR_PATHが指定されていない場合、自動補完
  if [ -z "$DIR_PATH" ]; then
    # ディレクトリが空の場合、リポジトリのトップディレクトリを探索
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/"
    debug_log "DEBUG" "DIR_PATH not specified, exploring repository's top directory"
  fi

  # APIからデータを取得 - GitHubはUser-Agentが必須
  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$API_URL")

  # *** ここからエラー処理の改善部分 ***
  if [ -z "$JSON" ]; then
    debug_log "DEBUG" "Could not retrieve data from API for package: $PKG_PREFIX from $REPO_OWNER/$REPO_NAME"
    printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: API connection error")"
    return 0
  fi

  # APIレート制限エラーを検出
  if echo "$JSON" | grep -q "API rate limit exceeded"; then
    debug_log "DEBUG" "GitHub API rate limit exceeded when fetching package: $PKG_PREFIX"
    printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: GitHub API rate limit exceeded")"
    return 0
  fi

  # 404エラー（リポジトリやパスが見つからない）を検出
  if echo "$JSON" | grep -q "Not Found"; then
    debug_log "DEBUG" "Repository or path not found: $REPO_OWNER/$REPO_NAME/$DIR_PATH"
    printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: Repository or path not found")"
    return 0
  fi

  # 最新のパッケージファイルを取得
  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r '.[].name' | grep "^${PKG_PREFIX}_" | sort | tail -n 1)

  if [ -z "$PKG_FILE" ]; then
    debug_log "DEBUG" "Package $PKG_PREFIX not found in repository $REPO_OWNER/$REPO_NAME"
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Package $PKG_PREFIX not found in repository")"
    return 0
  fi

  debug_log "DEBUG" "NEW PACKAGE: $PKG_FILE"

  # ダウンロードURLを取得
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$DOWNLOAD_URL" ]; then
    debug_log "DEBUG" "Failed to retrieve download URL for package: $PKG_PREFIX"
    printf "%s\n" "$(color yellow "Failed to retrieve download URL for package $PKG_PREFIX")"
    return 0
  fi
  # *** エラー処理の改善部分ここまで ***

  debug_log "DEBUG" "OUTPUT FILE: $OUTPUT_FILE"
  debug_log "DEBUG" "DOWNLOAD URL: $DOWNLOAD_URL"

  eval "$BASE_WGET" -O "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0

  debug_log "DEBUG" "$(ls -lh "$OUTPUT_FILE")"
  
  # 説明文がある場合はdesc=を追加してインストール
  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    debug_log "DEBUG" "Installing package with description: $desc_value"
    install_package "$OUTPUT_FILE" $opts "desc=$desc_value" || return 0
  else
    debug_log "DEBUG" "Installing package without description"
    install_package "$OUTPUT_FILE" $opts || return 0
  fi
  
  return 0
}

#########################################################################
# Last Update: 2025-04-12 05:16:23 (UTC) 🚀
# feed_package_release: リリースAPI用パッケージ取得関数
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
#   feed_package_release lisaac luci-app-diskman yn disabled
#########################################################################
feed_package_release() {
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
