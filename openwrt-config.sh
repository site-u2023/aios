#!/bin/sh

# =========================================================
# 📌 OpenWrt 設定スクリプト for AIOS
# 🚀 最終更新: 2025-03-15 05:48
# 
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 互換性: OpenWrt >= 19.07
# =========================================================

SCRIPT_VERSION="2025.03.15-05:48"

# メニュー定義関数
menu_openwrt() {
"blue" "インターネット接続設定 (MAP-e, DS-LITE, PPPoE)" "internet-setup.sh" "chmod" "load"
"yellow" "システム初期設定 (ホスト名,パスワード,WiFi等)" "system-setup.sh" "chmod" "load"
"green" "推奨パッケージのインストール (自動または選択式)" "package-install.sh" "chmod" "load"
"magenta" "広告ブロッカーとDNS暗号化のインストール" "adblocker-dns.sh" "chmod" "load"
"red" "アクセスポイント接続設定 (ダム/ブリッジモード)" "accesspoint-setup.sh" "chmod" "load"
"cyan" "Home Assistantのインストール (v23.05のみ)" "homeassistant-install.sh" "chmod" "load"
"white" "その他: ボタン設定, IPERF3, SAMBA4, LBS, DFSチェック, ゲストWiFi" "other-utilities.sh" "chmod" "load"
"white_black" "終了 (スクリプトの削除有無)" "exit" "" ""
}

# メニューセレクター関数
show_menu_and_select() {
    local menu_func="$1"
    local menu_title="$2"
    local menu_data
    local menu_count=0
    
    debug_log "DEBUG" "Loading menu data from function: $menu_func"
    menu_data=$($menu_func)
    
    # メニュー項目数をカウント
    menu_count=$(echo "$menu_data" | grep -v "^$" | wc -l)
    debug_log "INFO" "Menu contains $menu_count items"
    
    clear
    echo_message "OPENWRT_CONFIG_HEADER" "$SCRIPT_VERSION"
    echo_message "OPENWRT_CONFIG_SEPARATOR"
    [ -n "$menu_title" ] && echo_message "OPENWRT_CONFIG_SECTION_TITLE" "$menu_title"
    echo_message "OPENWRT_CONFIG_SEPARATOR"
    
    # メニュー項目表示
    local i=1
    echo "$menu_data" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            # 行の要素を抽出
            local color_name=$(echo "$line" | cut -d '"' -f 2)
            local title=$(echo "$line" | cut -d '"' -f 4)
            
            printf " %s%s\n" "$(color "$color_name" "[$i]: ")" "$(color "$color_name" "$title")"
            i=$((i + 1))
        fi
    done
    
    echo_message "OPENWRT_CONFIG_SEPARATOR"
    echo_message "OPENWRT_CONFIG_SELECT_PROMPT" "$menu_count"
    
    # 選択を取得
    read -r choice
    debug_log "DEBUG" "User selected option: $choice"
    
    # 選択が有効かチェック
    if ! echo "$choice" | grep -q "^[0-9]\+$"; then
        debug_log "WARN" "Invalid input: Not a number"
        echo_message "OPENWRT_CONFIG_ERROR_NOT_NUMBER"
        sleep 1
        return 1
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        debug_log "WARN" "Invalid choice: $choice (valid range: 1-$menu_count)"
        echo_message "OPENWRT_CONFIG_ERROR_INVALID_NUMBER" "$menu_count"
        sleep 1
        return 1
    fi
    
    # 選択された行を抽出
    local selected_item=$(echo "$menu_data" | grep -v "^$" | sed -n "${choice}p")
    
    # 行の要素を解析
    local script=$(echo "$selected_item" | cut -d '"' -f 6)
    local opt1=$(echo "$selected_item" | cut -d '"' -f 8)
    local opt2=$(echo "$selected_item" | cut -d '"' -f 10)
    
    debug_log "INFO" "Processing selection: script=$script, options=$opt1 $opt2"
    
    # スクリプト実行
    if [ "$script" = "exit" ]; then
        debug_log "INFO" "Exit option selected"
        if confirm "OPENWRT_CONFIG_CONFIRM_DELETE"; then
            debug_log "INFO" "User confirmed script deletion"
            rm -f "$0"
            echo_message "OPENWRT_CONFIG_DELETE_CONFIRMED"
        else
            debug_log "INFO" "User chose not to delete script"
            echo_message "OPENWRT_CONFIG_DELETE_CANCELED"
        fi
        exit 0
    else
        # スクリプトをダウンロードして実行
        debug_log "INFO" "Downloading and executing $script"
        if [ -n "$opt1" ] && [ -n "$opt2" ]; then
            download "$script" "$opt1" "$opt2"
        elif [ -n "$opt1" ]; then
            download "$script" "$opt1"
        else
            download "$script"
        fi
    fi
    
    return 0
}

# メイン関数
main() {
    debug_log "INFO" "Starting OpenWrt Config script v$SCRIPT_VERSION"
    
    # メインループ
    while true; do
        show_menu_and_select menu_openwrt ""
    done
}

# スクリプト実行
main "$@"
