#!/bin/sh

# =========================================================
# 📌 OpenWrt 設定スクリプト for AIOS
# 🚀 最終更新: 2025-03-15 05:43
# 
# 🏷️ ライセンス: CC0 (パブリックドメイン)
# 🎯 互換性: OpenWrt >= 19.07
# =========================================================

SCRIPT_VERSION="2025.03.15-05:43"

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
selector() {
    local menu_title="$1"
    local menu_func="$2"
    local menu_data=""
    local menu_count=0
    
    # メニュー関数から内容を取得
    menu_data=$($menu_func)
    
    # メニュー項目数をカウント
    menu_count=$(echo "$menu_data" | wc -l)
    debug_log "DEBUG" "Menu has $menu_count items"
    
    clear
    printf "%s\n" "$(color yellow "OpenWrt 設定スクリプト v$SCRIPT_VERSION")"
    printf "%s\n" "$(color white "-----------------------------------------------------")"
    [ -n "$menu_title" ] && printf "%s\n" "$(color cyan "$menu_title")"
    printf "%s\n" "$(color white "-----------------------------------------------------")"
    
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
    
    printf "%s\n" "$(color white "-----------------------------------------------------")"
    printf "%s " "$(color cyan "番号を選択してください (1-$menu_count): ")"
    
    # 選択を取得
    read -r choice
    
    # 選択が有効かチェック
    if ! echo "$choice" | grep -q "^[0-9]\+$"; then
        debug_log "WARN" "Invalid input: Not a number"
        printf "%s\n" "$(color red "数字を入力してください。")"
        sleep 1
        return 1
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$menu_count" ]; then
        debug_log "WARN" "Invalid choice: $choice (valid range: 1-$menu_count)"
        printf "%s\n" "$(color red "無効な選択です。1から${menu_count}までの番号を入力してください。")"
        sleep 1
        return 1
    fi
    
    # 選択された行を抽出
    local selected_item=$(echo "$menu_data" | sed -n "${choice}p")
    
    # 行の要素を解析
    local script=$(echo "$selected_item" | cut -d '"' -f 6)
    local opt1=$(echo "$selected_item" | cut -d '"' -f 8)
    local opt2=$(echo "$selected_item" | cut -d '"' -f 10)
    
    debug_log "INFO" "Selected: $choice - Script: $script, Options: $opt1 $opt2"
    
    # スクリプト実行
    if [ "$script" = "exit" ]; then
        if confirm "スクリプトを削除しますか？"; then
            debug_log "INFO" "User confirmed script deletion"
            rm -f "$0"
            printf "%s\n" "$(color green "スクリプトを削除しました。さようなら！")"
        else
            debug_log "INFO" "User chose not to delete the script"
            printf "%s\n" "$(color green "スクリプトは保持されます。さようなら！")"
        fi
        exit 0
    else
        # スクリプトをダウンロードして実行
        debug_log "INFO" "Downloading and executing $script with options: $opt1 $opt2"
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
        selector "OpenWrt 設定メニュー" menu_openwrt
    done
}

# スクリプト実行
main "$@"
