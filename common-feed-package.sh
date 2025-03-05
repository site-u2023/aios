#!/bin/sh

SCRIPT_VERSION="2025.03.03-07-01"

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
# ✅ Use `$(command)` instead of backticks `` `command` ``
# ✅ Use `$(( ))` for arithmetic instead of `let`
# ✅ Define functions as `func_name() {}` (no `function` keyword)
# ✅ No associative arrays (`declare -A` is NOT supported)
# ✅ No here-strings (`<<<` is NOT supported)
# ✅ No `-v` flag in `test` or `[[`
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
# =========================================================
### =========================================================
### 📌 AI Assistance Request: Bug Fixing Procedure
### 
### When debugging or fixing errors in this script, follow these steps:
### 
### 1️⃣ Create a minimal test script to identify the bug.
### 2️⃣ Execute the test and verify the reproducibility of the error.
### 3️⃣ Fix the error and re-run the test to confirm the solution.
### 4️⃣ Apply the corrected code to the production environment.
### 
### ⚠️ DO NOT modify the main script without first confirming the fix 
###     through a dedicated test script.
### 
### 🛠️ Keep the debugging process structured, efficient, and reliable.
### =========================================================

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="${BASE_WGET:-wget --no-check-certificate -q -O}"
# BASE_WGET="${BASE_WGET:-wget -O}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
BUILD_DIR="${BUILD_DIR:-$BASE_DIR/build}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BUILD_DIR" "$FEED_DIR"
#########################################################################
# Last Update: 2025-03-04 10:00:00 (JST) 🚀
# install_build: パッケージのビルド処理 (OpenWrt / Alpine Linux)
# GitHub API を利用して指定パッケージの最新ファイルを取得するスクリプト
# 関数: feed_package
# 説明:
#   GitHub API を用いて、指定されたリポジトリの特定ディレクトリ内から、
#   パッケージ名のプレフィックスに合致するファイル一覧を取得し、アルファベット順で最後のもの（＝最新と仮定）を
#   ダウンロード先に保存する。
#   また、DIR_PATHが指定されていない場合、自動的にリポジトリのトップディレクトリを探索し、
#   該当するディレクトリを自動的に選択する。
#
# 引数:
#   $1 : リポジトリのオーナー（例: gSpotx2f）
#   $2 : リポジトリ名（例: packages-openwrt）
#   $3 : ディレクトリパス（例: current）
#   $4 : パッケージ名のプレフィックス（例: luci-app-cpu-perf）
#   $5 : ダウンロード後の出力先ファイル（例: /tmp/luci-app-cpu-perf_all.ipk）
#
# 使い方
# feed_package ["yn"] ["hidden"] "リポジトリオーナー" "リポジトリ名" "ディレクトリ" "パッケージ名"
# 例: デフォルト（確認なしでインストール）
# feed_package "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
# 例: 確認を取ってインストール
# feed_package "yn" "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
# 例: インストール済みならメッセージなし
# feed_package "hidden" "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
# 例: `yn` と `hidden` を順不同で指定
# feed_package "hidden" "yn" "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
#
# 新仕様:
# 1. DIR_PATHが空の場合、リポジトリのトップディレクトリを探索し、最適なディレクトリを自動選択。
# 2. オプション（yn, hidden, force, disabled等）の引数を追加で処理できるように対応。
# 3. GitHub APIから最新のパッケージ情報を取得し、ダウンロードとインストールを行う。
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

  # 引数を走査し、オプションと通常引数を分離する
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;   # ynオプション
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;; # nolangオプション
      force) force_install="yes"; opts="$opts force" ;;   # forceオプション
      notpack) skip_package_db="yes"; opts="$opts notpack" ;; # notpackオプション
      disabled) set_disabled="yes"; opts="$opts disabled" ;; # disabledオプション
      hidden) hidden="yes"; opts="$opts hidden" ;; # hiddenオプション
      *) args="$args $1" ;;        # 通常引数を格納
    esac
    shift
  done

  # 必須引数が4つあるかチェック
  set -- $args
  if [ "$#" -ne 4 ]; then
    debug_log "DEBUG" "必要な引数 (REPO_OWNER, REPO_NAME, DIR_PATH, PKG_PREFIX) が不足しています。" >&2
    return 1
  fi

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.ipk"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"

  debug_log "DEBUG" "GitHub API からデータを取得中: $API_URL"

  # DIR_PATHが指定されていない場合、自動補完
  if [ -z "$DIR_PATH" ]; then
    # ディレクトリが空ならリポジトリのトップディレクトリを探索
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/"
    debug_log "DEBUG" "DIR_PATHが指定されていないため、リポジトリのトップディレクトリを探索"
  fi

  # APIからデータを取得
  local JSON
  JSON=$(wget --no-check-certificate -qO- "$API_URL")

  if [ -z "$JSON" ]; then
    debug_log "DEBUG" "APIからデータを取得できませんでした。"
    echo "APIからデータを取得できませんでした。"
    return 0  # エラーが発生しても処理を継続
  fi

  # 最新パッケージファイルの取得
  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r '.[].name' | grep "^${PKG_PREFIX}_" | sort | tail -n 1)

  if [ -z "$PKG_FILE" ]; then
    debug_log "DEBUG" "$PKG_PREFIX が見つかりません。"
    [ "$hidden" != "yes" ] && echo "$PKG_PREFIX が見つかりません。"
    return 0  # エラーが発生しても処理を継続
  fi

  debug_log "DEBUG" "NEW PACKAGE: $PKG_FILE"

  # ダウンロードURLの取得
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$DOWNLOAD_URL" ]; then
    debug_log "DEBUG" "パッケージ情報の取得に失敗しました。"
    echo "パッケージ情報の取得に失敗しました。"
    return 0  # エラーが発生しても処理を継続
  fi

  debug_log "DEBUG" "OUTPUT FILE: $OUTPUT_FILE"
  debug_log "DEBUG" "DOWNLOAD URL: $DOWNLOAD_URL"

  ${BASE_WGET} "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0  # エラーが発生しても処理を継続

  debug_log "DEBUG" "$(ls -lh "$OUTPUT_FILE")"
  
  # opts に格納されたオプションを展開して渡す
  install_package "$OUTPUT_FILE" $opts || return 0  # エラーが発生しても処理を継続
  
  return 0
}

feed_package2() {
  local confirm_install="no"
  local skip_lang_pack="no"
  local force_install="no"
  local skip_package_db="no"
  local set_disabled="no"
  local hidden="no"
  local opts=""   # オプションを格納する変数
  local args=""   # 通常引数を格納する変数

  # 引数を走査し、オプションと通常引数を分離する
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;   # ynオプション
      nolang) skip_lang_pack="yes"; opts="$opts nolang" ;; # nolangオプション
      force) force_install="yes"; opts="$opts force" ;;   # forceオプション
      notpack) skip_package_db="yes"; opts="$opts notpack" ;; # notpackオプション
      disabled) set_disabled="yes"; opts="$opts disabled" ;; # disabledオプション
      hidden) hidden="yes"; opts="$opts hidden" ;; # hiddenオプション
      *) args="$args $1" ;;        # 通常引数を格納
    esac
    shift
  done

  # 必須引数が4つあるかチェック
  set -- $args
  if [ "$#" -lt 4 ]; then
    debug_log "DEBUG" "必要な引数 (REPO_OWNER, REPO_NAME, DIR_PATH, PKG_PREFIX) が不足しています。" >&2
    return 1
  fi

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.ipk"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"

  debug_log "DEBUG" "GitHub API からデータを取得中: $API_URL"

  # DIR_PATHが指定されていない場合、自動補完
  if [ -z "$DIR_PATH" ];then
    # ディレクトリが空ならリポジトリのトップディレクトリを探索
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/"
    debug_log "DEBUG" "DIR_PATHが指定されていないため、リポジトリのトップディレクトリを探索"
  fi

  # APIからデータを取得
  local JSON
  JSON=$(wget --no-check-certificate -qO- "$API_URL")

  if [ -z "$JSON" ];then
    debug_log "DEBUG" "APIからデータを取得できませんでした。"
    echo "APIからデータを取得できませんでした。"
    return 0  # エラーが発生しても処理を継続
  fi

  # 最新パッケージファイルの取得
  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r '.[].name' | grep "^${PKG_PREFIX}_" | sort | tail -n 1)

  if [ -z "$PKG_FILE" ];then
    debug_log "DEBUG" "$PKG_PREFIX が見つかりません。"
    [ "$hidden" != "yes" ] && echo "$PKG_PREFIX が見つかりません。"
    return 0  # エラーが発生しても処理を継続
  fi

  debug_log "DEBUG" "NEW PACKAGE: $PKG_FILE"

  # ダウンロードURLの取得
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$DOWNLOAD_URL" ];then
    debug_log "DEBUG" "パッケージ情報の取得に失敗しました。"
    echo "パッケージ情報の取得に失敗しました。"
    return 0  # エラーが発生しても処理を継続
  fi

  debug_log "DEBUG" "OUTPUT FILE: $OUTPUT_FILE"
  debug_log "DEBUG" "DOWNLOAD URL: $DOWNLOAD_URL"

  ${BASE_WGET} "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0  # エラーが発生しても処理を継続

  debug_log "DEBUG" "$(ls -lh "$OUTPUT_FILE")"
  
  # opts に格納されたオプションを展開して渡す
  install_package "$OUTPUT_FILE" $opts || return 0  # エラーが発生しても処理を継続
  
  return 0
}
