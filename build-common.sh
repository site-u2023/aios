#!/bin/sh
# GitHub API を利用して指定パッケージの最新ファイルを取得するスクリプト

# 関数: latest_package
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
latest_package() {
  REPO_OWNER="$1"
  REPO_NAME="$2"
  DIR_PATH="$3"
  PKG_PREFIX="$4"
  OUTPUT_FILE="$5"

  API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${DIR_PATH}"
  echo "GitHub API からデータを取得中: $API_URL"

  JSON=$(wget --no-check-certificate -qO- "$API_URL")
  if [ $? -ne 0 ] || [ -z "$JSON" ]; then
    echo "APIからデータを取得できませんでした。"
    return 1
  fi

  # JSON は配列形式で返されるので、各エントリを1行にして "name" と "download_url" を抽出する
  ENTRY=$(echo "$JSON" | tr '\n' ' ' | sed 's/},{/}\n{/g' | grep "\"name\": *\"${PKG_PREFIX}" | tail -n 1)
  if [ -z "$ENTRY" ]; then
    echo "パッケージ名に合致するエントリが見つかりませんでした。"
    return 1
  fi

  # ENTRY から download_url を抽出
  DOWNLOAD_URL=$(echo "$ENTRY" | sed -n 's/.*"download_url": *"\([^"]*\)".*/\1/p')
  if [ -z "$DOWNLOAD_URL" ]; then
    echo "download_url の抽出に失敗しました。"
    return 1
  fi

  echo "最新のパッケージURL: $DOWNLOAD_URL"
  echo "ダウンロードを開始します..."

  wget --no-check-certificate -O "$OUTPUT_FILE" "$DOWNLOAD_URL"
  if [ $? -ne 0 ]; then
    echo "パッケージのダウンロードに失敗しました。"
    return 1
  fi

  echo "パッケージを $OUTPUT_FILE にダウンロードしました。"
  return 0
}

# ===== サンプル使用例 =====
# 以下は、luci-app-cpu-perf の最新パッケージを取得する例です。
# ※実際の運用では、引数を変更することで他のパッケージにも対応可能です。
latest_package "gSpotx2f" "packages-openwrt" "current" "luci-app-cpu-perf" "/tmp/luci-app-cpu-perf_all.ipk"
if [ $? -eq 0 ]; then
  echo "パッケージのダウンロードに成功しました。"
else
  echo "パッケージのダウンロードに失敗しました。"
fi
