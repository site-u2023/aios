#!/bin/sh

SCRIPT_VERSION="2025.03.02-01-00"

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
#!/bin/sh

check_version_feed() {
    local repo_owner="$1"  # 例: "gSpotx2f"
    local repo_name="$2"   # 例: "packages-openwrt"
    local package_prefix="$3" # 例: "luci-app-cpu-perf"

    # OpenWrt のバージョンをキャッシュから取得
    local version_file="${CACHE_DIR}/openwrt.ch"
    if [ ! -f "$version_file" ]; then
        echo "エラー: OpenWrt バージョン情報がありません。" >&2
        return 1
    fi
    local openwrt_version=$(cat "$version_file" | cut -d'.' -f1,2)

    # GitHub API でリポジトリのルートディレクトリを取得
    local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/contents/"
    echo "GitHub API からディレクトリ情報を取得: $api_url"
    
    local json=$(wget --no-check-certificate -qO- "$api_url")
    if [ -z "$json" ]; then
        echo "エラー: GitHub API からデータを取得できませんでした。" >&2
        return 1
    fi

    # JSON からディレクトリリストを抽出
    local available_versions=$(echo "$json" | grep -o '"name": "[^"]*' | cut -d'"' -f4)

    # 該当バージョンのフォルダがあるかチェック
    local selected_path="current" # デフォルトは "current"
    for dir in $available_versions; do
        if echo "$dir" | grep -qE "^(openwrt-|)$openwrt_version"; then
            selected_path="$dir"
            break
        fi
    done

    echo "選択されたパッケージディレクトリ: $selected_path"

    # feed_package() に渡すコマンドを生成
    echo "feed_package \"$repo_owner\" \"$repo_name\" \"$selected_path\" \"$package_prefix\""
}

feed_package() {
  local ask_yn=false
  local hidden=false

  # オプションを処理する
  while [ $# -gt 0 ]; do
    case "$1" in
      yn)
        ask_yn=true
        shift
        ;;
      hidden)
        hidden=true
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  # 残りの引数を変数に格納
  local REPO_OWNER="$1"
  local REPO_NAME="$2"
  local DIR_PATH="$3"
  local PKG_PREFIX="$4"

  # 以下、残りの処理...
  local OUTPUT_FILE="${FEED_DIR}/${PKG_PREFIX}.ipk"
  local API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"

  echo "GitHub API からデータを取得中: $API_URL"
  local JSON=$(wget --no-check-certificate -qO- "$API_URL")
  if [ -z "$JSON" ]; then
    echo "APIからデータを取得できませんでした。"
    return 1
  fi

  local ENTRY=$(echo "$JSON" | tr '\n' ' ' | sed 's/},{/}\n{/g' | grep "\"name\": *\"${PKG_PREFIX}" | tail -n 1)
  if [ -z "$ENTRY" ]; then
    echo "パッケージが見つかりません。"
    return 1
  fi

  local PKG_FILE=$(echo "$ENTRY" | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p')
  local DOWNLOAD_URL=$(echo "$ENTRY" | sed -n 's/.*"download_url": *"\([^"]*\)".*/\1/p')

  if [ -z "$PKG_FILE" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "パッケージ情報の取得に失敗しました。"
    return 1
  fi

  echo "最新のパッケージ: $PKG_FILE"
  echo "ダウンロードURL: $DOWNLOAD_URL"

  local INSTALLED_VERSION=$(opkg info "$PKG_PREFIX" 2>/dev/null | grep Version | awk '{print $2}')
  local NEW_VERSION=$(echo "$PKG_FILE" | sed -E "s/^${PKG_PREFIX}_([0-9\.\-r]+)_.*\.ipk/\1/")

  if [ "$INSTALLED_VERSION" = "$NEW_VERSION" ]; then
    if [ "$hidden" = true ]; then
      return 0  # メッセージなしで終了
    fi
    echo "✅ 既に最新バージョン（$NEW_VERSION）がインストール済みです。"
    return 0
  fi

  if [ "$ask_yn" = true ]; then
    echo "新しいバージョン $NEW_VERSION をインストールしますか？ [y/N]"
    read -r yn
    case "$yn" in
      y|Y) echo "✅ インストールを続行..." ;;
      *) echo "🚫 インストールをキャンセルしました。"; return 1 ;;
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
