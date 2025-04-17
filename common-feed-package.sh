#!/bin/sh

SCRIPT_VERSION="2025.04.17-00-00"

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
# feed_package 関数の修正案 (変更箇所に ★★★ を付与)
feed_package() {
  local confirm_install="no"
  local skip_lang_pack="no"
  local force_install="no"
  local skip_package_db="no" # ★★★ notpack オプションを判定するために必要
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
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;;
      force) force_install="yes"; opts="$opts force" ;;
      notpack) skip_package_db="yes"; opts="$opts notpack" ;; # ★★★ notpack を opts に追加
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

  # ★★★ 変数名を明確化 ★★★
  local repo_owner="$1"
  local repo_name="$2"
  local dir_path="$3"
  local pkg_prefix="$4" # ★★★ local_package_db で使用するキー

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")

  if [ -z "$PACKAGE_EXTENSION" ]; then
      debug_log "DEBUG" "File not found or empty: ${CACHE_DIR}/extension.ch"
      return 1
  fi
  # 将来的に削除される予定のルーチン
  if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
      printf "%s\n" "$(color yellow "Currently not supported for apk.")"
      return 1
  fi

  debug_log "DEBUG" "Installing required packages: jq and ca-certificates"
  install_package jq silent
  install_package ca-certificates silent

  local output_file="${FEED_DIR}/${pkg_prefix}.${PACKAGE_EXTENSION}" # ★★★ 変数名修正
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/contents/${dir_path}" # ★★★ 変数名修正

  debug_log "DEBUG" "Fetching data from GitHub API: $api_url" # ★★★ 変数名修正

  if [ -z "$dir_path" ]; then # ★★★ 変数名修正
    api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/contents/" # ★★★ 変数名修正
    debug_log "DEBUG" "DIR_PATH not specified, exploring repository's top directory"
  fi

  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$api_url") # ★★★ 変数名修正

  if [ -z "$JSON" ]; then
    debug_log "DEBUG" "Could not retrieve data from API for package: $pkg_prefix from $repo_owner/$repo_name" # ★★★ 変数名修正
    printf "%s\n" "$(color yellow "Failed to retrieve package $pkg_prefix: API connection error")" # ★★★ 変数名修正
    return 1 # ★★★ エラー時は 1 を返すように変更
  fi

  if echo "$JSON" | grep -q "API rate limit exceeded"; then
    debug_log "DEBUG" "GitHub API rate limit exceeded when fetching package: $pkg_prefix" # ★★★ 変数名修正
    printf "%s\n" "$(color yellow "Failed to retrieve package $pkg_prefix: GitHub API rate limit exceeded")" # ★★★ 変数名修正
    return 1 # ★★★ エラー時は 1 を返すように変更
  fi

  if echo "$JSON" | grep -q "Not Found"; then
    debug_log "DEBUG" "Repository or path not found: $repo_owner/$repo_name/$dir_path" # ★★★ 変数名修正
    printf "%s\n" "$(color yellow "Failed to retrieve package $pkg_prefix: Repository or path not found")" # ★★★ 変数名修正
    return 1 # ★★★ エラー時は 1 を返すように変更
  fi

  local pkg_file # ★★★ 変数名修正
  pkg_file=$(echo "$JSON" | jq -r '.[].name' | grep "^${pkg_prefix}_" | sort | tail -n 1) # ★★★ 変数名修正

  if [ -z "$pkg_file" ]; then # ★★★ 変数名修正
    debug_log "DEBUG" "Package $pkg_prefix not found in repository $repo_owner/$repo_name" # ★★★ 変数名修正
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Package $pkg_prefix not found in repository")" # ★★★ 変数名修正
    return 1 # ★★★ パッケージが見つからない場合もエラーとして 1 を返す
  fi

  debug_log "DEBUG" "NEW PACKAGE: $pkg_file" # ★★★ 変数名修正

  local download_url # ★★★ 変数名修正
  download_url=$(echo "$JSON" | jq -r --arg PKG "$pkg_file" '.[] | select(.name == $PKG) | .download_url') # ★★★ 変数名修正

  if [ -z "$download_url" ]; then # ★★★ 変数名修正
    debug_log "DEBUG" "Failed to retrieve download URL for package: $pkg_prefix" # ★★★ 変数名修正
    printf "%s\n" "$(color yellow "Failed to retrieve download URL for package $pkg_prefix")" # ★★★ 変数名修正
    return 1 # ★★★ エラー時は 1 を返すように変更
  fi

  debug_log "DEBUG" "OUTPUT FILE: $output_file" # ★★★ 変数名修正
  debug_log "DEBUG" "DOWNLOAD URL: $download_url" # ★★★ 変数名修正

  eval "$BASE_WGET" -O "$output_file" "$download_url" || return 1 # ★★★ wget失敗時も 1 を返す

  debug_log "DEBUG" "$(ls -lh "$output_file")" # ★★★ 変数名修正

  local install_success="no"
  # 説明文がある場合はdesc=を追加してインストール
  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    debug_log "DEBUG" "Installing package $output_file with description: $desc_value" # ★★★ 変数名修正
    if install_package "$output_file" $opts "desc=$desc_value"; then # ★★★ 変数名修正
      install_success="yes"
    fi
  else
    debug_log "DEBUG" "Installing package $output_file without description" # ★★★ 変数名修正
    if install_package "$output_file" $opts; then # ★★★ 変数名修正
      install_success="yes"
    fi
  fi

  # ★★★ 修正箇所: インストール成功後に local_package_db を呼び出す ★★★
  if [ "$install_success" = "yes" ] && [ "$skip_package_db" != "yes" ]; then
    # common-package.sh の local_package_db 関数が存在するか確認
    if type local_package_db >/dev/null 2>&1; then
        debug_log "DEBUG" "Applying local-package.db settings for $pkg_prefix" # ★★★ 変数名修正
        # pkg_prefix を引数として local_package_db を呼び出す
        local_package_db "$pkg_prefix" # ★★★ 変数名修正
    else
        debug_log "WARNING" "local_package_db function not found. Cannot apply settings for $pkg_prefix." # ★★★ 変数名修正
    fi
  elif [ "$install_success" = "yes" ] && [ "$skip_package_db" = "yes" ]; then
    debug_log "DEBUG" "Skipping local-package.db application for $pkg_prefix due to notpack option." # ★★★ 変数名修正
  fi
  # ★★★ 修正箇所ここまで ★★★

  if [ "$install_success" = "yes" ]; then
      return 0
  else
      # インストール失敗メッセージは install_package 内で表示される想定
      debug_log "DEBUG" "Installation or post-install step failed for $pkg_prefix" # ★★★ 変数名修正
      return 1
  fi
}

# feed_package_release 関数の修正案 (変更箇所に ★★★ を付与)
feed_package_release() {
  local confirm_install="no"
  local skip_lang_pack="no"
  local force_install="no"
  local skip_package_db="no" # ★★★ notpack オプションを判定するために必要
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
      notpack) skip_package_db="yes"; opts="$opts notpack" ;; # ★★★ notpack を opts に追加
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

  # ★★★ 変数名を明確化 ★★★
  local repo_owner="$1"
  local repo_name="$2"
  local pkg_prefix="${repo_name}" # ★★★ local_package_db で使用するキー

  PACKAGE_EXTENSION=$(cat "${CACHE_DIR}/extension.ch")

  if [ -z "$PACKAGE_EXTENSION" ]; then
      debug_log "DEBUG" "File not found or empty: ${CACHE_DIR}/extension.ch"
      return 1
  fi
  # 将来的に削除される予定のルーチン
  if [ "$PACKAGE_EXTENSION" != "ipk" ]; then
      printf "%s\n" "$(color yellow "Currently not supported for apk.")"
      return 1
  fi

  debug_log "DEBUG" "Installing required packages: jq and ca-certificates"
  install_package jq silent
  install_package ca-certificates silent

  local output_file="${FEED_DIR}/${pkg_prefix}.${PACKAGE_EXTENSION}" # ★★★ 変数名修正
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/releases" # ★★★ 変数名修正

  debug_log "DEBUG" "Fetching data from GitHub API: $api_url" # ★★★ 変数名修正

  local JSON
  JSON=$(wget --no-check-certificate -q -U "aios-pkg/1.0" -O- "$api_url") # ★★★ 変数名修正

  if [ -z "$JSON" ];then
    debug_log "DEBUG" "Could not retrieve data from API for release: $repo_owner/$repo_name" # ★★★ 変数名修正
    printf "%s\n" "$(color yellow "Could not retrieve release data from API.")"
    return 1 # ★★★ エラー時は 1 を返すように変更
  fi

  # ★★★ レート制限と Not Found のチェックを追加 ★★★
  if echo "$JSON" | grep -q "API rate limit exceeded"; then
    debug_log "DEBUG" "GitHub API rate limit exceeded when fetching release: $repo_owner/$repo_name" # ★★★ 変数名修正
    printf "%s\n" "$(color yellow "Failed to retrieve release $repo_owner/$repo_name: GitHub API rate limit exceeded")" # ★★★ 変数名修正
    return 1
  fi
  if echo "$JSON" | grep -q "Not Found"; then
      # 404の場合、リリースがない可能性もあるので、警告にとどめるか要検討
      debug_log "DEBUG" "Repository or releases not found: $repo_owner/$repo_name" # ★★★ 変数名修正
      printf "%s\n" "$(color yellow "Failed to retrieve release $repo_owner/$repo_name: Repository or releases not found")" # ★★★ 変数名修正
      return 1
  fi

  local pkg_file # ★★★ 変数名修正
  # ★★★ .ipk 拡張子でフィルタリングを追加 ★★★
  pkg_file=$(echo "$JSON" | jq -r --arg PKG_PREFIX "$pkg_prefix" --arg EXT ".${PACKAGE_EXTENSION}" \
    '.[] | .assets[]? | select(.name? | startswith($PKG_PREFIX) and endswith($EXT)) | .name' \
    | sort -V | tail -n 1) # ★★★ jq のエラー抑制(?)とバージョンソート(-V)を追加

  if [ -z "$pkg_file" ];then # ★★★ 変数名修正
    debug_log "DEBUG" "Package file with prefix $pkg_prefix and extension .$PACKAGE_EXTENSION not found in releases for $repo_owner/$repo_name." # ★★★ 変数名修正
    [ "$hidden" != "yes" ] && printf "%s\n" "$(color yellow "Package $pkg_prefix not found in releases.")" # ★★★ 変数名修正
    return 1 # ★★★ パッケージが見つからない場合もエラーとして 1 を返す
  fi

  debug_log "DEBUG" "NEW PACKAGE: $pkg_file" # ★★★ 変数名修正

  local download_url # ★★★ 変数名修正
  download_url=$(echo "$JSON" | jq -r --arg PKG "$pkg_file" '.[] | .assets[]? | select(.name == $PKG) | .browser_download_url') # ★★★ jq のエラー抑制(?)を追加

  if [ -z "$download_url" ];then # ★★★ 変数名修正
    debug_log "DEBUG" "Failed to retrieve download URL for package: $pkg_file" # ★★★ 変数名修正
    printf "%s\n" "$(color yellow "Failed to retrieve download URL for package $pkg_file")" # ★★★ 変数名修正
    return 1 # ★★★ エラー時は 1 を返すように変更
  fi

  debug_log "DEBUG" "OUTPUT FILE: $output_file" # ★★★ 変数名修正
  debug_log "DEBUG" "DOWNLOAD URL: $download_url" # ★★★ 変数名修正

  eval "$BASE_WGET" -O "$output_file" "$download_url" || return 1 # ★★★ wget失敗時も 1 を返す

  debug_log "DEBUG" "$(ls -lh "$output_file")" # ★★★ 変数名修正

  local install_success="no"
  # 説明文がある場合はdesc=を追加してインストール
  if [ "$desc_flag" = "yes" ] && [ -n "$desc_value" ]; then
    debug_log "DEBUG" "Installing release package $output_file with description: $desc_value" # ★★★ 変数名修正
    if install_package "$output_file" $opts "desc=$desc_value"; then # ★★★ 変数名修正
      install_success="yes"
    fi
  else
    debug_log "DEBUG" "Installing release package $output_file without description" # ★★★ 変数名修正
    if install_package "$output_file" $opts; then # ★★★ 変数名修正
      install_success="yes"
    fi
  fi

  # ★★★ 修正箇所: インストール成功後に local_package_db を呼び出す ★★★
  if [ "$install_success" = "yes" ] && [ "$skip_package_db" != "yes" ]; then
    # common-package.sh の local_package_db 関数が存在するか確認
    if type local_package_db >/dev/null 2>&1; then
        debug_log "DEBUG" "Applying local-package.db settings for $pkg_prefix" # ★★★ 変数名修正
        # pkg_prefix を引数として local_package_db を呼び出す
        local_package_db "$pkg_prefix" # ★★★ 変数名修正
    else
        debug_log "WARNING" "local_package_db function not found. Cannot apply settings for $pkg_prefix." # ★★★ 変数名修正
    fi
  elif [ "$install_success" = "yes" ] && [ "$skip_package_db" = "yes" ]; then
      debug_log "DEBUG" "Skipping local-package.db application for $pkg_prefix due to notpack option." # ★★★ 変数名修正
  fi
  # ★★★ 修正箇所ここまで ★★★

  if [ "$install_success" = "yes" ]; then
      return 0
  else
      debug_log "DEBUG" "Installation or post-install step failed for $pkg_prefix" # ★★★ 変数名修正
      return 1
  fi
}
