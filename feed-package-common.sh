#!/bin/sh

SCRIPT_VERSION="2025.03.02-00-00"

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
#########################################################################
feed_package() {
  REPO_OWNER="$1"
  REPO_NAME="$2"
  DIR_PATH="$3"
  PKG_PREFIX="$4"
  
  # 保存先ディレクトリ設定
  OUTPUT_DIR="${FEED_DIR}/${PKG_PREFIX}"
  mkdir -p "$OUTPUT_DIR"
  
  # 出力ファイルパス
  OUTPUT_FILE="${OUTPUT_DIR}/${PKG_PREFIX}.ipk"

  API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"
  echo "GitHub API からデータを取得中: $API_URL"

  # APIからJSONを取得
  JSON=$(wget --no-check-certificate -qO- "$API_URL")
  if [ $? -ne 0 ] || [ -z "$JSON" ]; then
    echo "APIからデータを取得できませんでした。"
    return 1
  fi

  # JSONを1行に変換し、パッケージ名で絞り込み、最新のパッケージを抽出
  ENTRY=$(echo "$JSON" | tr '\n' ' ' | sed 's/},{/}\n{/g' | grep "\"name\": *\"${PKG_PREFIX}" | tail -n 1)
  if [ -z "$ENTRY" ]; then
    echo "パッケージ名に合致するエントリが見つかりませんでした。"
    return 1
  fi

  # ENTRYからdownload_urlを抽出
  DOWNLOAD_URL=$(echo "$ENTRY" | sed -n 's/.*"download_url": *"\([^"]*\)".*/\1/p')
  if [ -z "$DOWNLOAD_URL" ]; then
    echo "download_url の抽出に失敗しました。"
    return 1
  fi

  echo "最新のパッケージURL: $DOWNLOAD_URL"
  echo "ダウンロードを開始します..."
  
  # パッケージをダウンロード
  wget --no-check-certificate -O "$OUTPUT_FILE" "$DOWNLOAD_URL"
  if [ $? -ne 0 ]; then
    echo "パッケージのダウンロードに失敗しました。"
    return 1
  fi

  # ダウンロードが成功した場合
  echo "パッケージを $OUTPUT_FILE にダウンロードしました。"
  
  # インストール開始
  echo "パッケージをインストール中..."
  opkg install "$OUTPUT_FILE"
  if [ $? -ne 0 ]; then
    echo "パッケージのインストールに失敗しました。"
    return 1
  fi

  # インストール成功
  echo "パッケージのインストールに成功しました。"
  
  # パッケージが正常にインストールされたか確認
  if ! opkg list-installed | grep -q "$PKG_PREFIX"; then
    echo "インストール後、パッケージが見つかりません。"
    return 1
  fi
  
  echo "パッケージ $PKG_PREFIX は正常にインストールされ、動作しています。"
  return 0
}


# ===== サンプル使用例 =====
# 以下のようにして呼び出してください。
# feed_package "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf"
