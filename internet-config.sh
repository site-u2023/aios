#!/bin/sh

SCRIPT_VERSION="2025.03.18-01-00"

# メインメニューのセクション名を定義
MAIN_MENU="openwrt-config.sh"
# 現在のセレクターメニュー名を定義
SELECTOR_MENU="internet-config.sh"

# メイン関数
main() {
    # デバッグモードでmenu.dbの内容を確認
    if [ "$DEBUG_MODE" = "true" ]; then
        if [ -f "${BASE_DIR}/menu.db" ]; then
            echo "[DEBUG] Menu DB exists at ${BASE_DIR}/menu.db"
            echo "[DEBUG] First 10 lines of menu.db:"
            head -n 10 "${BASE_DIR}/menu.db" | while IFS= read -r line; do
                echo "[DEBUG] menu.db> $line"
            done
        else
            echo "[ERROR] Menu DB not found at ${BASE_DIR}/menu.db"
        fi
    fi
    
    # 引数があれば、それをSELECTOR_MENUに設定
    if [ $# -gt 0 ]; then
        SELECTOR_MENU="$1"
        [ "$DEBUG_MODE" = "true" ] && echo "[DEBUG] Setting menu from argument: $SELECTOR_MENU"
    fi
    
    # メニュー表示ループ
    while true; do
        selector
    done
}

main "$@"
