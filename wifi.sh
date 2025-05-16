#!/bin/sh

SCRIPT_VERSION="2025.05.16-00-00"

DEV_NULL="${DEV_NULL:-on}"
# サイレントモード
# export DEV_NULL="on"
# 通常モード
# unset DEV_NULL

# 基本定数の設定
BASE_WGET="wget --no-check-certificate -q"
# BASE_WGET="wget -O"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-$BASE_DIR/cache}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
FEED_DIR="${FEED_DIR:-$BASE_DIR/feed}"
DEBUG_MODE="${DEBUG_MODE:-false}"

# setup_wifi_ssid_password: Wi-Fi の SSID とパスワードを設定する
setup_wifi_ssid_password() {
    local devices wifi_country_code
    # 固定のキャッシュファイルパスを定義
    local interfaces_log_file="${CACHE_DIR}/wifi_interfaces.log"
    local status_key_file="${CACHE_DIR}/wifi_status.key"
    local final_status_key="MSG_ERROR" # デフォルトは汎用エラー
    local final_status_param="message=Wi-Fi setup failed due to an unknown error." # MSG_ERROR用
    local interfaces_configured_count=0

    # 実行前に一時ファイルをクリア
    rm -f "$interfaces_log_file" "$status_key_file" 2>/dev/null

    wifi_country_code=$(cat "${CACHE_DIR}/language.ch" 2>/dev/null)

    if [ -z "$wifi_country_code" ]; then
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_NO_COUNTRY_CODE")")"
        final_status_key="MSG_ERROR_NO_COUNTRY_CODE"
        final_status_param=""
        echo "$final_status_key:$final_status_param" > "$status_key_file"
        return 1 # 致命的エラーなのでここで終了
    fi

    devices=$(uci -q show wireless | awk -F'.' '/\.type=wifi-device$/{print $2}' | sort -u)

    if [ -z "$devices" ]; then
        printf "%s\n" "$(color red "$(get_message "MSG_NO_WIFI_DEVICES")")"
        final_status_key="MSG_NO_WIFI_DEVICES"
        final_status_param=""
        echo "$final_status_key:$final_status_param" > "$status_key_file"
        return 1 # これも処理継続不可のエラーとして扱う
    fi

    for device in $devices; do
        # config_wifi_device は内部で固定パスの $interfaces_log_file に書き込む
        if config_wifi_device "$device" "$wifi_country_code"; then
            interfaces_configured_count=$((interfaces_configured_count + 1))
        fi
    done

    if ! uci commit wireless; then
        printf "%s\n" "$(color red "$(get_message "MSG_COMMIT_FAILED_WIFI")")"
        final_status_key="MSG_COMMIT_FAILED_WIFI"
        final_status_param=""
        echo "$final_status_key:$final_status_param" > "$status_key_file"
        return 1 # uci commit 失敗
    fi

    /etc/init.d/network reload # network reload の成否はここではチェックしない (元ソースに倣う)

    # 最終的なステータスを決定
    if [ "$interfaces_configured_count" -gt 0 ]; then
        final_status_key="MSG_WIFI_SETTINGS_UPDATED"
        final_status_param="device=Wi-Fi interfaces" # 元キーの引数を模倣
    else
        # ユーザーが何も有効にしなかった場合
        final_status_key="MSG_NO_WIFI_DEVICES" # 「有効なデバイス設定なし」の意味で流用
        final_status_param=""
    fi

    echo "$final_status_key:$final_status_param" > "$status_key_file"
    return 0 # 処理完了 (成功)
}

# WiFiデバイス個別設定
# 引数1: デバイス名
# 引数2: 国コード
config_wifi_device() {
    local device="$1"
    local wifi_country_code="$2"
    # 固定のキャッシュファイルパスを定義
    local interfaces_log_file="${CACHE_DIR}/wifi_interfaces.log"
    local band htmode ssid password enable_band confirm iface_name
    local default_ssid=""
    local band_type=""

    # (SSIDやパスワードの入力、HTモードの決定などの処理は前回の提案と同じ)
    band=$(uci -q get wireless."$device".band 2>/dev/null)
    htmode=$(uci -q get wireless."$device".htmode 2>/dev/null)

    case "$band" in
        "2g"|"2G") band_type="2.4GHz" ;;
        "5g"|"5G") band_type="5GHz" ;;
        "6g"|"6G") band_type="6GHz" ;;
        *) band_type="$band" ;;
    esac

    printf "%s\n" "$(color green "$(get_message "MSG_WIFI_DEVICE_BAND" "device=$device" "band=$band_type")")"

    if ! confirm "MSG_ENABLE_BAND" "yn" "device=$device" "band=$band_type"; then
        return 1 # ユーザーがNoを選択
    fi

    iface_name="aios$(echo "$device" | sed 's/[^0-9]//g')"
    if [ -z "$(echo "$device" | sed 's/[^0-9]//g')" ]; then
        local num_ifaces=$(uci show wireless | grep "\.type=wifi-iface" | grep "\.mode=ap" | wc -l)
        iface_name="aios${num_ifaces}"
    fi
    default_ssid="aios_${band_type}"

    while true; do
        printf "%s" "$(color yellow "$(get_message "MSG_ENTER_SSID")") [${default_ssid}]: "
        read ssid
        printf "\n"
        [ -z "$ssid" ] && ssid="$default_ssid"
        [ -n "$ssid" ] && break
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR_EMPTY_SSID")")"
    done

    while true; do
        printf "%s" "$(color yellow "$(get_message "MSG_ENTER_WIFI_PASSWORD")")"
        read -s password
        printf "\n\n"
        [ ${#password} -ge 8 ] && break
        printf "%s\n" "$(color red "$(get_message "MSG_PASSWORD_TOO_SHORT")")"
    done

    case "$band" in
        "2g"|"2G") [ -z "$htmode" ] && htmode="HT20" ;;
        "5g"|"5G") [ -z "$htmode" ] && htmode="VHT80" ;;
        "6g"|"6G") [ -z "$htmode" ] && htmode="HE80" ;;
    esac

    while true; do
        printf "%s\n" "$(color yellow "$(get_message "MSG_WIFI_CONFIG_PREVIEW")")"
        printf "%s\n" "$(color green "$(get_message "MSG_WIFI_BAND_INFO" "band=$band_type")")"
        printf "%s\n" "$(color green "$(get_message "MSG_WIFI_HTMODE_INFO" "mode=$htmode")")"

        if confirm "MSG_CONFIRM_WIFI_SETTINGS" "yn" "ssid=$ssid" "password=$password"; then
            break
        else
            printf "%s\n" "$(color yellow "$(get_message "MSG_REENTER_INFO")")"
            return 1 # 設定をキャンセル
        fi
    done

    if setup_wifi_interface "$device" "$iface_name" "$ssid" "$password" "$wifi_country_code" "$htmode"; then
        # 成功した場合、固定パスのインターフェースログファイルに情報を書き込む
        echo "$device $band_type $ssid" >> "$interfaces_log_file"
        return 0 # 成功
    else
        # setup_wifi_interface が失敗した場合
        printf "%s\n" "$(color red "$(get_message "MSG_ERROR" "message=Failed to setup Wi-Fi interface $iface_name for device $device.")")"
        return 1 # 失敗
    fi
}

# WiFiインターフェース設定
setup_wifi_interface() {
    local device="$1" iface_name="$2" ssid="$3" password="$4" country="$5" htmode="$6"

    uci -q delete wireless."$iface_name" # 既存の設定があれば一度削除

    uci set wireless."$iface_name"="wifi-iface"
    uci set wireless."$iface_name".device="$device"
    uci set wireless."$iface_name".mode='ap'
    uci set wireless."$iface_name".ssid="$ssid"
    uci set wireless."$iface_name".key="$password"
    # WPA3 (sae-mixed) をデフォルトとし、より安全な設定を推奨
    # WPA2/WPA3混在モード: sae-mixed
    # WPA2のみ: psk2
    # OpenWrtのバージョンによっては sae-mixed が利用できない場合もあるので注意
    uci set wireless."$iface_name".encryption='sae-mixed' # WPA3/WPA2 Mixed Mode
    # uci set wireless."$iface_name".encryption='psk2+ccmp' # WPA2-PSK
    uci set wireless."$iface_name".network='lan' # 通常はlanブリッジに接続

    uci set wireless."$device".country="$country"
    [ -n "$htmode" ] && uci set wireless."$device".htmode="$htmode"
    uci -q delete wireless."$device".disabled # 無効化設定があれば削除（有効化）
}

# display_detected_wifi: Wi-Fi設定のサマリーを表示する
display_detected_wifi() {
    # 固定のキャッシュファイルパスを定義
    local interfaces_log_file="${CACHE_DIR}/wifi_interfaces.log"
    local status_key_file="${CACHE_DIR}/wifi_status.key"

    local device_name band_type network_ssid line_counter
    local status_key_line status_key status_param status_message

    debug_log "DEBUG" "Displaying Wi-Fi summary using display_detected_wifi. Interfaces file: $interfaces_log_file, Status file: $status_key_file"
    printf "\n"

    # ヘッダー: 既存のMSG_USE_DETECTED_INFORMATIONを流用
    printf "%s\n" "$(color white "$(get_message "MSG_USE_DETECTED_INFORMATION" "i=Wi-Fi Setup Status")")"

    # --- 設定されたインターフェースの詳細表示 ---
    if [ -f "$interfaces_log_file" ] && [ -s "$interfaces_log_file" ]; then # ファイルが存在し、かつ空でない場合
        line_counter=0
        while IFS= read -r line_data; do
            device_name=$(echo "$line_data" | awk '{print $1}')
            band_type=$(echo "$line_data" | awk '{print $2}')
            network_ssid=$(echo "$line_data" | awk '{for(i=3; i<=NF; i++) printf "%s%s", $i, (i==NF ? "" : " ")}')

            if [ -n "$device_name" ] && [ -n "$band_type" ] && [ -n "$network_ssid" ]; then
                local device_band_info
                device_band_info=$(get_message "MSG_WIFI_DEVICE_BAND" "device=$device_name" "band=$band_type")
                printf "%s %s [%s]\n" "$(color green "$device_band_info")" "$(color white "SSID:")" "$(color green "$network_ssid")"
                line_counter=$((line_counter + 1))
            fi
        done < "$interfaces_log_file"
    elif [ -f "$interfaces_log_file" ]; then
        line_counter=0
    else
        line_counter=0
    fi

    # --- 全体的な完了/ステータスメッセージ ---
    if [ -f "$status_key_file" ] && [ -s "$status_key_file" ]; then
        status_key_line=$(cat "$status_key_file")
        status_key=$(echo "$status_key_line" | cut -d':' -f1)
        status_param=$(echo "$status_key_line" | cut -d':' -f2-)

        if [ -n "$status_key" ]; then
            if [ -n "$status_param" ]; then
                status_message=$(get_message "$status_key" "$status_param")
            else
                status_message=$(get_message "$status_key")
            fi

            case "$status_key" in
                "MSG_WIFI_SETTINGS_UPDATED")
                    printf "%s\n" "$(color green "$status_message")"
                    ;;
                "MSG_NO_WIFI_DEVICES"|"MSG_ERROR_NO_COUNTRY_CODE")
                    printf "%s\n" "$(color yellow "$status_message")"
                    ;;
                "MSG_COMMIT_FAILED_WIFI"|"MSG_ERROR")
                    printf "%s\n" "$(color red "$status_message")"
                    ;;
                *)
                    printf "%s\n" "$(color white "$status_message")"
                    ;;
            esac
        fi
    elif [ "$line_counter" -gt 0 ]; then # ステータスファイルはないが、何かしら設定された場合 (フォールバック)
        printf "%s\n" "$(color green "$(get_message "MSG_WIFI_SETTINGS_UPDATED" "device=Wi-Fi interfaces")")"
    elif [ "$line_counter" -eq 0 ]; then # ステータスファイルもインターフェースログも実質空の場合
        printf "%s\n" "$(color yellow "$(get_message "MSG_NO_WIFI_DEVICES")")" # フォールバック
    fi

    printf "\n"
    debug_log "DEBUG" "Wi-Fi summary display finished. Cleaning up temporary log files."
    rm -f "$interfaces_log_file" "$status_key_file" 2>/dev/null
}

# SSH設定 (このスクリプトでは呼び出されない)
config_ssh() {
    # SSH設定例 (必要に応じてコメントアウト解除)
    # uci set dropbear.@dropbear[0].PasswordAuth='on'
    # uci set dropbear.@dropbear[0].RootPasswordAuth='on'
    # uci set dropbear.@dropbear[0].Port='22'
    # uci commit dropbear
    # /etc/init.d/dropbear restart
    : # 何もしないプレースホルダー
}

# システム基本設定 (このスクリプトでは呼び出されない)
config_system() {
    # ホスト名設定例
    # uci set system.@system[0].hostname='MyOpenWrt'
    # uci commit system
    : # 何もしないプレースホルダー
}

# ネットワーク設定 (このスクリプトでは呼び出されない)
config_network() {
    # ファイアウォール設定
    uci set firewall.@defaults[0].flow_offloading='1'

    # Mediatek検出とハードウェアオフロード設定
    if grep -q 'mediatek' /etc/openwrt_release; then # /etc/os-release や /etc/openwrt_version も参照可能
        uci set firewall.@defaults[0].flow_offloading_hw='1'
    fi

    uci commit firewall

    # パケットステアリング設定
    uci set network.globals.packet_steering='1'
    uci commit network
}

# DNS設定 (このスクリプトでは呼び出されない)
config_dns() {
    # 既存のDNS設定をクリア
    uci -q delete dhcp.lan.dhcp_option # 古い形式のDNS指定を削除
    uci -q delete dhcp.lan.dns         # 新しいリスト形式のDNS指定を削除

    # IPv4 DNS設定 (Cloudflare と Google)
    uci add_list dhcp.lan.dhcp_option="6,1.1.1.1,8.8.8.8" # プライマリDNS
    uci add_list dhcp.lan.dhcp_option="6,1.0.0.1,8.8.4.4" # セカンダリDNS

    # IPv6 DNS設定 (Cloudflare と Google)
    uci add_list dhcp.lan.dns="2606:4700:4700::1111"
    uci add_list dhcp.lan.dns="2001:4860:4860::8888"
    uci add_list dhcp.lan.dns="2606:4700:4700::1001"
    uci add_list dhcp.lan.dns="2001:4860:4860::8844"

    # その他のDHCP設定
    uci set dhcp.@dnsmasq[0].cachesize='2000'
    uci set dhcp.lan.leasetime='24h'
    uci commit dhcp
}

# メイン処理
wifi_main() {
    # 必要な common スクリプトが source されている前提
    # 例: common-color.sh, common-message.sh (get_message, colorのため)
    # main aios スクリプトから呼び出される場合は通常問題ない

    setup_wifi_ssid_password

    display_detected_wifi
    
    # `packages` 関数の呼び出しは削除しました
}

# スクリプトの実行 (引数は現状利用していません)
wifi_main "$@"
