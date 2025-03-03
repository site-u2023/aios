#!/bin/sh

SCRIPT_VERSION="2025.03.03-01-03"

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

echo -e "\033[7;40mUpdated to version $SCRIPT_VERSION feed-package-common.sh \033[0m"

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定 
BASE_WGET="${BASE_WGET:-wget -q -O}"
# BASE_WGET="${BASE_WGET:-wget -O}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
BUILD_DIR="${BUILD_DIR:-$BASE_DIR/build}"
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BUILD_DIR"
DEBUG_MODE="${DEBUG_MODE:-false}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
#########################################################################
# Last Update: 2025-03-02 14:00:00 (JST) 🚀
# install_build: パッケージのビルド処理 (OpenWrt / Alpine Linux)
# GitHub API を利用して指定パッケージの最新ファイルを取得するスクリプト
# 関数: feed_package
# 説明:
#   GitHub API を用いて、指定されたリポジトリの特定ディレクトリ内から、
#   パッケージ名のプレフィックスに合致するファイル一覧を取得し、アルファベット順で最後のもの（＝最新と仮定）を
#   ダウンロード先に保存する。
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
#########################################################################
gSpotx2f_package() {
  local opts=""
  local args=""

  # すべての引数を走査し、オプション (yn, hidden) と通常引数を分離する
  while [ $# -gt 0 ]; do
    case "$1" in
      yn|hidden)
        opts="$opts $1"
        ;;
      *)
        args="$args $1"
        ;;
    esac
    shift
  done

  # 必須引数が4つあるかチェック
  set -- $args
  if [ "$#" -ne 4 ]; then
    echo "エラー: 必要な引数 (REPO_OWNER, REPO_NAME, DIR_PATH, PKG_PREFIX) が不足しています。" >&2
    return 1
  fi

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"
  local PKG_VERSION="${PKG_PREFIX}_.*"
  local orig_DIR_PATH="$DIR_PATH"  # 元の引数を保持

  debug_log "DEBUG" "PKG_PREFIX: $PKG_PREFIX"
  debug_log "DEBUG" "PKG_VERSION: $PKG_VERSION"
  debug_log "DEBUG" "DIR_PATH: $DIR_PATH"
  
  # バージョン情報の取得
  local version_file="${CACHE_DIR}/openwrt.ch"
  if [ ! -f "$version_file" ]; then
    echo "エラー: OpenWrt バージョン情報がありません。" >&2
    return 1
  fi
  local openwrt_version
  openwrt_version=$(cut -d'.' -f1,2 < "$version_file" | tr -d ' \t\r\n')
  debug_log "DEBUG" "openwrt_version: $openwrt_version"
  
  if [ "$openwrt_version" = "19.07" ]; then   
    DIR_PATH="19.07"
  else
    DIR_PATH="current"
  fi
  debug_log "DEBUG" "openwrt_version -> DIR_PATH: $DIR_PATH"
  
  if [ "$DIR_PATH" = "19.07" ]; then
    local PKG_FILE
    PKG_FILE=$(wget --no-check-certificate -qO- "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}" | jq -r '.[] | .name' | grep "^${PKG_VERSION}" | sort | tail -n 1)
    debug_log "DEBUG" "PKG_FILE: $PKG_FILE"
    
    if [ -n "$PKG_FILE" ]; then
      echo "バージョンは${DIR_PASH}です。"
    else
      echo "バージョンは${DIR_PASH}です。"
    fi
  fi

  debug_log "DEBUG" "パッケージ: $PKG_FILE"
  debug_log "DEBUG" "オプション: $opts $REPO_OWNER $REPO_NAME $DIR_PATH $PKG_PREFIX"
  # opts は文字列（例: "yn hidden"）なので、feed_packageに展開すれば各単語に分割される
  feed_package $opts "$REPO_OWNER" "$REPO_NAME" "$DIR_PATH" "$PKG_PREFIX"
}

feed_package() {
  local ask_yn=false
  local hidden=false

  while [ $# -gt 0 ]; do
    case "$1" in
      yn) ask_yn=true; shift ;;
      hidden) hidden=true; shift ;;
      *) break ;;
    esac
  done

  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"

  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.ipk"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"

  debug_log "DEBUG" "GitHub API からデータを取得中: $API_URL"

  local JSON
  JSON=$(wget --no-check-certificate -qO- "$API_URL")

  if [ -z "$JSON" ]; then
    debug_log "DEBUG" "APIからデータを取得できませんでした。"
    echo "APIからデータを取得できませんでした。"
    return 1
  fi

  debug_log "DEBUG" "取得したJSON: $JSON"

  local PKG_FILE
  PKG_FILE=$(echo "$JSON" | jq -r '.[].name' | grep "^${PKG_PREFIX}_" | sort | tail -n 1)

  if [ -z "$PKG_FILE" ]; then
    debug_log "DEBUG" "$PKG_PREFIX が見つかりません。"
    echo "$PKG_PREFIX が見つかりません。"
    return 1
  fi

  debug_log "DEBUG" "最新のパッケージ: $PKG_FILE"

  local DOWNLOAD_URL
  DOWNLOAD_URL=$(echo "$JSON" | jq -r --arg PKG "$PKG_FILE" '.[] | select(.name == $PKG) | .download_url')

  if [ -z "$DOWNLOAD_URL" ]; then
    debug_log "DEBUG" "パッケージ情報の取得に失敗しました。"
    echo "パッケージ情報の取得に失敗しました。"
    return 1
  fi

  debug_log "DEBUG" "ダウンロードURL: $DOWNLOAD_URL"

  local INSTALLED_VERSION
  INSTALLED_VERSION=$(opkg info "$PKG_PREFIX" 2>/dev/null | grep Version | awk '{print $2}')

  local NEW_VERSION
  NEW_VERSION=$(echo "$PKG_FILE" | sed -E "s/^${PKG_PREFIX}_([0-9\.\-r]+)_.*\.ipk/\1/")

  if [ "$INSTALLED_VERSION" = "$NEW_VERSION" ]; then
    if [ "$hidden" = true ]; then
      return 0
    fi
    debug_log "DEBUG" "既に最新バージョン（$NEW_VERSION）がインストール済みです。"
    echo "✅ 既に最新バージョン（$NEW_VERSION）がインストール済みです。"
    return 0
  fi

  if [ "$ask_yn" = true ]; then
    echo "新しいバージョン $NEW_VERSION をインストールしますか？ [y/N]"
    read -r yn
    case "$yn" in
      y|Y) debug_log "DEBUG" "インストールを続行..."; echo "✅ インストールを続行..." ;;
      *) debug_log "DEBUG" "インストールをキャンセルしました。"; echo "🚫 インストールをキャンセルしました。"; return 1 ;;
    esac
  fi

  echo "⏳ パッケージをダウンロード中..."
  wget --no-check-certificate -O "$OUTPUT_FILE" "$DOWNLOAD_URL" || return 1

  echo "📦 パッケージをインストール中..."
  opkg install "$OUTPUT_FILE" || return 1

  echo "🔄 サービスを再起動..."
  /etc/init.d/rpcd restart
  /etc/init.d/"$PKG_PREFIX" start

  echo "✅ インストール完了: $PKG_PREFIX ($NEW_VERSION)"

  return 0
}
