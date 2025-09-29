#!/bin/sh

SCRIPT_VERSION="2025.04.11-00-01"

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
  local skip_lang_pack="no"
  local force_install="no"
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""
  local args=""
  local desc_flag="no"
  local desc_value=""

  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;;
      force) force_install="yes"; opts="$opts force" ;;
      notpack) skip_package_db="yes"; opts="$opts notpack" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;;
      desc=*)
        desc_flag="yes"
        desc_value="${1#desc=}"
        ;;
      *)
        if [ "$desc_flag" = "yes" ]; then
          desc_value="$desc_value $1"
        else
          args="$args $1"
        fi
        ;;
    esac
    shift
  done

  set -- $args
  if [ "$#" -ne 4 ]; then
    debug_log "DEBUG" "Required arguments (REPO_OWNER, REPO_NAME, DIR_PATH, PKG_PREFIX) are missing." >&2
    return 1
  fi

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")
  if [ -n "$PACKAGE_EXTENSION" ]; then
      if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
          printf "%s\n" "$(color yellow "Currently not supported for apk.")"
          return 1
      fi
  else
      return 1
  fi

  install_package ca-certificates silent

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.${PACKAGE_EXTENSION}"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"

  if [ -z "$DIR_PATH" ]; then
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/"
  fi

  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$API_URL")

  if [ -z "$JSON" ]; then
    printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: API connection error")"
    return 0
  fi
  if echo "$JSON" | grep -q "API rate limit exceeded"; then
    printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: GitHub API rate limit exceeded")"
    return 0
  fi
  if echo "$JSON" | grep -q "Not Found"; then
    printf "%s\n" "$(color yellow "Failed to retrieve package $PKG_PREFIX: Repository or path not found")"
    return 0
  fi

  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jsonfilter -e '@[*].name' | grep "^${PKG_PREFIX}_" | sort | tail -n 1)

  if [ -z "$PKG_FILE" ]; then
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Package $PKG_PREFIX not found in repository")"
    return 0
  fi

  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jsonfilter -e "@[*][?(@.name==\"${PKG_FILE}\")].download_url")

  if [ -z "$DOWNLOAD_URL" ]; then
    printf "%s\n" "$(color yellow "Failed to retrieve download URL for package $PKG_PREFIX")"
    return 0
  fi

  eval "$BASE_WGET" -O "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0

  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    install_package "$OUTPUT_FILE" $opts "desc=$desc_value" || return 0
  else
    install_package "$OUTPUT_FILE" $opts || return 0
  fi

  return 0
}

#########################################################################
# Last Update: 2025-04-12 05:18:15 (UTC) 🚀
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
#   feed_package_release yn hidden lisaac luci-app-diskman
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
  local desc_flag="no"
  local desc_value=""

  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;;
      force) force_install="yes"; opts="$opts force" ;;
      notpack) skip_package_db="yes"; opts="$opts notpack" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;;
      desc=*)
        desc_flag="yes"
        desc_value="${1#desc=}"
        ;;
      *)
        if [ "$desc_flag" = "yes" ]; then
          desc_value="$desc_value $1"
        else
          args="$args $1"
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
      if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
          printf "%s\n" "$(color yellow "Currently not supported for apk.")"
          return 1
      fi
  else
      return 1
  fi

  install_package ca-certificates silent

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local PKG_PREFIX="${REPO_NAME}"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.${PACKAGE_EXTENSION}"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"

  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$API_URL")

  if [ -z "$JSON" ];then
    printf "%s\n" "$(color yellow "Could not retrieve data from API.")"
    return 0
  fi

  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jsonfilter -e '@[*].assets[*].name' | grep "^${PKG_PREFIX}" | sort | tail -n 1)

  if [ -z "$PKG_FILE" ];then
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "$PKG_PREFIX not found.")"
    return 0
  fi

  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jsonfilter -e "@[*].assets[*][?(@.name='${PKG_FILE}')].browser_download_url")

  if [ -z "$DOWNLOAD_URL" ];then
    printf "%s\n" "$(color yellow "Failed to retrieve package information.")"
    return 0
  fi

  eval "$BASE_WGET" -O "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0

  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    install_package "$OUTPUT_FILE" $opts "desc=$desc_value" || return 0
  else
    install_package "$OUTPUT_FILE" $opts || return 0
  fi

  return 0
}
