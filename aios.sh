#!/bin/sh
# aios.sh (初期エントリースクリプト)
# License: CC0
AIOS_VERSION="2025.02.15-1"
echo -e "\033[7;40maios.sh Updated to version $AIOS_VERSION \033[0m"

INPUT_LANG="${1:-}"

BASE_WGET="wget --quiet -O"
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"
COMMON_SH="$BASE_DIR/common.sh"
BIN_PATH="/usr/bin/aios"
CACHE_DIR="$BASE_DIR/cache"
LOG_DIR="$BASE_DIR/logs"

rm -rf "${BASE_DIR}" "$BIN_PATH"
echo "Initialized aios"

mkdir -p "$BASE_DIR" "$CACHE_DIR" "$LOG_DIR"

# `common.sh` のダウンロード
echo "Downloading latest version of common.sh"
${BASE_WGET} "$COMMON_SH" "$BASE_URL/common.sh"

# 環境変数の確認
if [ -f "$COMMON_SH" ]; then
    . "$COMMON_SH"
else
    echo "ERROR: Failed to load common.sh"
    exit 1
fi

# `check_common` の実行
check_common "$INPUT_LANG"

debug_log "INFO" "aios.sh received INPUT_LANG: '$INPUT_LANG' and DEBUG_MODE: '$DEBUG_MODE'"

# ttyd
install_package ttyd yn 
install_package luci-app-ttyd

# openssh-sftp-server
install_package openssh-sftp-server yn 

# `aios` を /usr/bin に配置
echo "Installing aios command to /usr/bin/aios"
${BASE_WGET} "$BIN_PATH" "$BASE_URL/aios"  # aios をダウンロード
chmod +x "$BIN_PATH"  # aios に実行権限を付与

# aios を実行 (必要な場合)
echo "Running aios..."
/usr/bin/aios  # ダウンロードした aios を実行
