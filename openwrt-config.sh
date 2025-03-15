#!/bin/sh

# =========================================================
# 📌 OpenWrt 設定スクリプト for AIOS
# 🚀 最終更新: 2025-03-15 06:07
# 
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 互換性: OpenWrt >= 19.07
# =========================================================

SCRIPT_VERSION="2025.03.15-06:07"

# メニュー表示用データ
menyu_selector() (
"1" "red" "インターネット接続設定 (MAP-e, DS-LITE, PPPoE)" 
"2" "blue" "システム初期設定 (ホスト名,パスワード,WiFi等)"
"3" "green" "推奨パッケージのインストール (自動または選択式)"
"4" "magenta" "広告ブロッカーとDNS暗号化のインストール"
"5" "cyan" "アクセスポイント接続設定 (ダム/ブリッジモード)"
"6" "yellow" "Home Assistantのインストール (v23.05のみ)"
"7" "white" "その他: ボタン設定, IPERF3, SAMBA4, LBS, DFSチェック, ゲストWiFi"
"8" "white_black" "終了 (スクリプトの削除有無)"
)

# ダウンロード用データ
menu_download() (
"1" "internet-setup.sh" "chmod" "load"
"2" "system-setup.sh" "chmod" "load"
"3" "package-install.sh" "chmod" "load"
"4" "adblocker-dns.sh" "chmod" "load"
"5" "accesspoint-setup.sh" "chmod" "load"
"6" "homeassistant-install.sh" "chmod" "load"
"7" "other-utilities.sh" "chmod" "load"
"8" "exit" "" ""
)

# メニューセレクター関数
selector() {
    local menu_title="$1"
    local selector_data=""
    local download_data=""
    local menu_count=0
    
    debug_log "DEBUG" "Loading menu display data"
    selector_data=$(menyu_selector)
    
    debug_log "DEBUG" "Loading menu download data"
    download_data=$(menu_download)
    
    # メニュー項目数をカウント
    menu_count=$(echo "$selector_data" | wc -l)
    debug_log "INFO" "Menu contains $menu_count items"
    
    clear
    echo_message "OPENWRT_CONFIG_HEADER" "$SCRIPT_VERSION"
    echo_message "OPENWRT_CONFIG_SEPARATOR"
    [ -n "$menu_title" ] && echo_message "OPENWRT_CONFIG_SECTION_TITLE" "$menu_title"
    echo_message "OPENWRT_CONFIG_SEPARATOR"
    
    # メニュー項目表示
    echo "$selector_data" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            # 行の要素を抽出
            local num=$(echo "$line" | cut -d '"' -f 2)
            local color_name=$(echo "$line" | cut -d '"' -f 4)
            local title=$(echo "$line" | cut -d '"' -f 6)
            
            printf " %s%s\n" "$(color "$color_name" "[$num]: ")" "$(color "$color_name" "$title")"
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
    
    # 選択に対応するダウンロードデータを取得
    local selected_item=$(echo "$download_data" | grep -v "^$" | grep "^\"$choice\"")
    debug_log "INFO" "Selected item data: $selected_item"
    
    # 行の要素を解析
    local script=$(echo "$selected_item" | cut -d '"' -f 4)
    local opt1=$(echo "$selected_item" | cut -d '"' -f 6)
    local opt2=$(echo "$selected_item" | cut -d '"' -f 8)
    
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
        echo_message "OPENWRT_CONFIG_DOWNLOADING" "$script"
        
        if [ -n "$opt1" ] && [ -n "$opt2" ]; then
            download "$script" "$opt1" "$opt2"
        elif [ -n "$opt1" ]; then
            download "$script" "$opt1"
        else
            download "$script"
        fi
        
        if [ $? -ne 0 ]; then
            debug_log "ERROR" "Failed to download or execute $script"
            echo_message "OPENWRT_CONFIG_DOWNLOAD_FAILED" "$script"
            sleep 2
        fi
    fi
    
    return 0
}

# メイン関数
main() {
    debug_log "INFO" "Starting OpenWrt Config script v$SCRIPT_VERSION"
    
    # メインループ
    while true; do
        selector "OpenWrt 設定メニュー"
    done
}

# スクリプト実行
main "$@"
