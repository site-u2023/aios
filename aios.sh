#!/bin/sh
# aios.sh (初期エントリースクリプト)
# License: CC0
AIOS_VERSION="2025.02.13-1"
echo -e "\033[7;40maios.sh Updated to version $AIOS_VERSION \033[0m"

# 定数設定
BASE_WGET="wget --quiet -O"
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"

# 初期化
mkdir -p "$BASE_DIR"

#################################
# 引数解析関数
#################################
arguments() {
    DEBUG_MODE=false
    RESET_CACHE=false
    SHOW_HELP=false
    INPUT_LANG=""

    for arg in "$@"; do
        case "$arg" in
            -d|--debug|-debug) DEBUG_MODE=true ;;
            -reset|--reset|-r) RESET_CACHE=true ;;
            -help|--help|-h) SHOW_HELP=true ;;
            *)
                # 言語コードとして処理（最初の未定義引数を言語コードとみなす）
                if [ -z "$INPUT_LANG" ]; then
                    INPUT_LANG="$arg"
                fi
                ;;
        esac
    done

    export DEBUG_MODE RESET_CACHE SHOW_HELP INPUT_LANG

    debug_log "Parsed arguments -> INPUT_LANG: '$INPUT_LANG', DEBUG_MODE: '$DEBUG_MODE', RESET_CACHE: '$RESET_CACHE', SHOW_HELP: '$SHOW_HELP'"
}

#################################
# デバッグログ出力関数
#################################
debug_log() {
    $DEBUG_MODE && echo "DEBUG: $*" | tee -a "$BASE_DIR/debug.log"
}

#################################
# 共通ファイルのダウンロードと読み込み
#################################
download_common() {
    if [ ! -f "${BASE_DIR}/common.sh" ]; then
        ${BASE_WGET} "${BASE_DIR}/common.sh" "${BASE_URL}/common.sh" || {
            echo "Failed to download common.sh"
            exit 1
        }
    fi
    . "${BASE_DIR}/common.sh" || {
        echo "Failed to load common.sh"
        exit 1
    }
}

#################################
# メイン処理
#################################
delete_aios() {
    rm -rf "${BASE_DIR}" /usr/bin/aios
    echo "Initialized aios"
}

#################################
# 実行処理
#################################
arguments "$@"  # 引数を解析
debug_log "aios.sh received INPUT_LANG: '$INPUT_LANG' and DEBUG_MODE: '$DEBUG_MODE'"

if $SHOW_HELP; then
    print_help
    exit 0
fi

if $RESET_CACHE; then
    reset_cache
fi

delete_aios
mkdir -p "$BASE_DIR"
download_common
check_common "full" "$INPUT_LANG"
