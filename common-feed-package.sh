#!/bin/sh

SCRIPT_VERSION="2025.03.05-00-10"

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
  local opts=""
  local args=""
  local pattern=""

  # 引数を走査し、オプションと通常引数を分離する
  while [ $# -gt 0 ]; do
    case "$1" in
      yn) confirm_install="yes"; opts="$opts yn" ;;
      hidden) hidden="yes"; opts="$opts hidden" ;;
      disabled) set_disabled="yes"; opts="$opts disabled" ;;
      *) args="$args $1" ;;
    esac
    shift
  done

  # 必須引数をチェック
  set -- $args
  if [ "$#" -lt 4 ]; then
    debug_log "DEBUG" "必要な引数 (REPO_OWNER, REPO_NAME, DIR_PATH, PKG_PREFIX) が不足しています。" >&2
    return 0
  fi

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.ipk"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"

  debug_log "DEBUG" "GitHub API からデータを取得中: $API_URL"

  # パターン解析
  case "$REPO_OWNER" in
    kiddin9 | Leo-Jo-My | lisaac | jerrykuku)
      pattern="A"
      ;;
    gSpotx2f)
      case "$PKG_PREFIX" in
        luci-app-cpu-perf | luci-app-cpu-status | luci-app-temp-status | luci-app-log-viewer | luci-app-log | internet-detector)
          pattern="A-Github"
          ;;
        *)
          pattern="A-Package名"
          ;;
      esac
      ;;
    *)
      pattern="デフォルト"
      ;;
  esac

  # パターンに基づく処理
  case "$pattern" in
    "A")
      process_pattern_A "$REPO_OWNER" "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
      ;;
    "A-Github")
      process_pattern_A_github "$REPO_OWNER" "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
      ;;
    "A-Package名")
      process_pattern_A_package "$REPO_OWNER" "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
      ;;
    "デフォルト")
      default_package "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
      ;;
    *)
      default_package "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
      ;;
  esac

  debug_log "DEBUG" "OUTPUT FILE: $OUTPUT_FILE"
  debug_log "DEBUG" "DOWNLOAD URL: $DOWNLOAD_URL"

  ${BASE_WGET} "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 0

  debug_log "DEBUG" "$(ls -lh "$OUTPUT_FILE")"
  
  # opts に格納されたオプションを展開して渡す
  install_package "$OUTPUT_FILE" $opts || return 0
  
  return 0
}

default_package() {
  local REPO_NAME="$1"
  local DIR_PATH="$2"
  local PKG_PREFIX="$3"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"

  local JSON
  JSON=$(wget --no-check-certificate -qO- "$API_URL")

  if [ -z "$JSON" ];then
    debug_log "DEBUG" "APIからデータを取得できませんでした。"
    return 0
  fi

  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r '[.[] | select(.type == "file" and .name | test("^'${PKG_PREFIX}'_"))] | sort_by(.name) | last | .name')

  if [ -z "$PKG_FILE" ];then
    debug_log "DEBUG" "$PKG_PREFIX が見つかりません。"
    return 0
  fi

  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | select(.name == $PKG) | .download_url')
}

process_pattern_A() {
  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  # パターンAの処理
  default_package "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
}

process_pattern_A_github() {
  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  # パターンA-Githubの処理
  default_package "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
}

process_pattern_A_package() {
  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  # パターンA-Package名の処理
  default_package "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
}
