#!/bin/sh
# Information provided by https://github.com/tinysun
# Vr.4.01
# License: CC0

SCRIPT_VERSION="2025.05.14-00-00"

# OpenWrt関数をロード
. /lib/functions/network.sh

mape_nuro_mold() {
    # グローバル変数としてNEW_IP6_PREFIXをここで定義
    local NET_IF6 NET_ADDR6
    network_flush_cache
    network_find_wan6 NET_IF6
    network_get_prefix6 NET_PFX6 "${NET_IF6}"

#set -e
export LANG=C
expr "$NET_PFX6" : '[[:xdigit:]:]\{2,\}$' >/dev/null
echo $NET_PFX6 |grep -sqEv '[[:xdigit:]]{5}|:::|::.*::'
cn=$(echo $NET_PFX6 |grep -o : |wc -l)
test $cn -ge 2 -a $cn -le 7
NET_PFX6=$(echo $NET_PFX6 |sed '
    s/^:/0000:/
    s/:$/:0000/
    s/.*/:&:/
    :add0
    s/:\([^:]\{1,3\}\):/:0\1:/g
    t add0
    s/:\(.*\):/\1/' )
if echo $NET_PFX6 |grep -sq :: ; then
    NET_PFX6=$(echo $NET_PFX6 |sed s/::/:$(echo -n :::::: |tail -c $((8-cn)) |sed 's/:/0000:/g')/ )
else
        test $cn -eq 7
fi
NURO_V6=`echo $NET_PFX6 |cut -b -11`

RULE_0=240d:000f:0
RULE_1=240d:000f:1
RULE_2=240d:000f:2
RULE_3=240d:000f:3
RULE_4=240d:000f:4
RULE_5=240d:000f:5
RULE_6=240d:000f:6
RULE_7=240d:000f:7
RULE_8=240d:000f:8
RULE_9=240d:000f:9
RULE_a=240d:000f:a # 小文字 a を使用
RULE_b=240d:000f:b # 小文字 b を使用
RULE_c=240d:000f:c # 小文字 c を使用
RULE_d=240d:000f:d # 小文字 d を使用
RULE_e=240d:000f:e # 小文字 e を使用
RULE_f=240d:000f:f # 小文字 f を使用
RULE_10_0=240d:0010:0 # 240d:0010 のパターン用
RULE_10_1=240d:0010:1 # 240d:0010 のパターン用

# アドレスパターン判定
if [ -z "${NURO_V6}" ]; then
    read -p "Could not retrieve IPv6 address. Press enter to exit."
    exit 0
else
    if [ "${NURO_V6}" = "${RULE_0}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:0000"
        IPV4_PREFIX="219.104.128.0"
        echo "Matched rule 0"
    elif [ "${NURO_V6}" = "${RULE_1}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:1000"
        IPV4_PREFIX="219.104.144.0"
        echo "Matched rule 1"
    elif [ "${NURO_V6}" = "${RULE_2}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:2000"
        IPV4_PREFIX="219.104.160.0"
        echo "Matched rule 2"
    elif [ "${NURO_V6}" = "${RULE_3}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:3000"
        IPV4_PREFIX="219.104.176.0"
        echo "Matched rule 3"
    elif [ "${NURO_V6}" = "${RULE_4}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:4000"
        IPV4_PREFIX="219.104.192.0"
        echo "Matched rule 4"
    elif [ "${NURO_V6}" = "${RULE_5}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:5000"
        IPV4_PREFIX="219.104.208.0"
        echo "Matched rule 5"
    elif [ "${NURO_V6}" = "${RULE_6}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:6000"
        IPV4_PREFIX="219.104.224.0"
        echo "Matched rule 6"
    elif [ "${NURO_V6}" = "${RULE_7}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:7000"
        IPV4_PREFIX="219.104.240.0"
        echo "Matched rule 7"
    elif [ "${NURO_V6}" = "${RULE_8}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:8000"
        IPV4_PREFIX="219.105.0.0"
        echo "Matched rule 8"
    elif [ "${NURO_V6}" = "${RULE_9}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:9000"
        IPV4_PREFIX="219.105.16.0"
        echo "Matched rule 9"
    elif [ "${NURO_V6}" = "${RULE_a}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:a000"
        IPV4_PREFIX="219.105.32.0"
        echo "Matched rule a"
    elif [ "${NURO_V6}" = "${RULE_b}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:b000"
        IPV4_PREFIX="219.105.48.0"
        echo "Matched rule b"
    elif [ "${NURO_V6}" = "${RULE_c}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:c000"
        IPV4_PREFIX="219.105.64.0"
        echo "Matched rule c"
    elif [ "${NURO_V6}" = "${RULE_d}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:d000"
        IPV4_PREFIX="219.105.80.0"
        echo "Matched rule d"
    elif [ "${NURO_V6}" = "${RULE_e}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:e000"
        IPV4_PREFIX="219.105.96.0"
        echo "Matched rule e"
    elif [ "${NURO_V6}" = "${RULE_f}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:000f:f000"
        IPV4_PREFIX="219.105.112.0"
        echo "Matched rule f"
    elif [ "${NURO_V6}" = "${RULE_10_0}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:0010:0000"
        IPV4_PREFIX="219.105.128.0"
        echo "Matched rule 10_0"
    elif [ "${NURO_V6}" = "${RULE_10_1}" ]; then
        BR_ADDR="2001:3b8:200:ff9::1"
        IPV6_PREFIX="240d:0010:1000"
        IPV4_PREFIX="219.105.144.0"
        echo "Matched rule 10_1"
    else
        echo "Unmatched NURO IPv6 prefix: ${NURO_V6}"
        read -p "Unsupported IPv6 address. Press enter to exit."
        exit 0
    fi
fi
}

mape_nuro_config() {

    # 設定のバックアップ作成
    debug_log "DEBUG" "Backing up configuration files..."
    cp /etc/config/network /etc/config/network.map-e-nuro.bak && debug_log "DEBUG" "network backup created." || debug_log "DEBUG" "Failed to backup network config."
    cp /etc/config/dhcp /etc/config/dhcp.map-e-nuro.bak && debug_log "DEBUG" "dhcp backup created." || debug_log "DEBUG" "Failed to backup dhcp config."
    cp /etc/config/firewall /etc/config/firewall.map-e-nuro.bak && debug_log "DEBUG" "firewall backup created." || debug_log "DEBUG" "Failed to backup firewall config."
    
# DHCP LAN
uci set dhcp.lan.ra='relay'
uci set dhcp.lan.dhcpv6='server'
uci set dhcp.lan.ndp='relay'
uci set dhcp.lan.force='1'
# WAN
uci set network.wan.auto='1'
# DHCP WAN6
uci set dhcp.wan6=dhcp
#uci set dhcp.wan6.ignore='1'
uci set dhcp.wan6.master='1'
uci set dhcp.wan6.ra='relay'
uci set dhcp.wan6.dhcpv6='relay'
uci set dhcp.wan6.ndp='relay'
# WANMAP
WANMAP='wanmap'
uci set network.${WANMAP}=interface
uci set network.${WANMAP}.proto='map'
uci set network.${WANMAP}.maptype='map-e'
uci set network.${WANMAP}.peeraddr=${BR_ADDR}
uci set network.${WANMAP}.ipaddr=${IPV4_PREFIX}
uci set network.${WANMAP}.ip4prefixlen='20'
uci set network.${WANMAP}.ip6prefix=${IPV6_PREFIX}::
uci set network.${WANMAP}.ip6prefixlen='36'
uci set network.${WANMAP}.ealen='20'
uci set network.${WANMAP}.psidlen='8'
uci set network.${WANMAP}.offset='4'
#uci set network.${WANMAP}.legacymap='1'
uci set network.${WANMAP}.mtu='1452'
uci set network.${WANMAP}.encaplimit='ignore'
#uci set network.${WANMAP}.tunlink='wan6'
# Version-specific settings
OPENWRT_RELEAS=$(grep 'DISTRIB_RELEASE' /etc/openwrt_release | cut -d"'" -f2 | cut -c 1-2)
if [[ "${OPENWRT_RELEAS}" = "SN" || "${OPENWRT_RELEAS}" = "24" || "${OPENWRT_RELEAS}" = "23" || "${OPENWRT_RELEAS}" = "22" || "${OPENWRT_RELEAS}" = "21" ]]; then
  #uci set dhcp.wan6.interface='wan6'
  uci set dhcp.wan6.ignore='1'
  uci set network.${WANMAP}.legacymap='1'
  uci set network.${WANMAP}.tunlink='wan6'
elif [[ "${OPENWRT_RELEAS}" = "19" ]]; then
  uci add_list network.${WANMAP}.tunlink='wan6'
fi
# FW
ZOON_NO='1'
uci del_list firewall.@zone[${ZOON_NO}].network='wan'
uci add_list firewall.@zone[${ZOON_NO}].network=${WANMAP}
# delete
uci -q delete dhcp.lan.dns
uci -q delete dhcp.lan.dhcp_option
# IPV4
uci add_list network.lan.dns='118.238.201.33' # dns1.nuro.jp
uci add_list network.lan.dns='152.165.245.17' # dns1.nuro.jp
#uci add_list network.lan.dns='118.238.201.49' # dns2.nuro.jp
#uci add_list network.lan.dns='152.165.245.1' # dns2.nuro.jp
uci add_list dhcp.lan.dhcp_option='6,1.1.1.1,8.8.8.8'
uci add_list dhcp.lan.dhcp_option='6,1.0.0.1,8.8.4.4'
# IPV6
uci add_list network.lan.dns='240d:0010:0004:0005::33'
uci add_list network.lan.dns='240d:12:4:1b01:152:165:245:17'
#uci add_list network.lan.dns='240d:0010:0004:0006::49'
#uci add_list network.lan.dns='240d:12:4:1b00:152:165:245:1'
uci add_list dhcp.lan.dns='2606:4700:4700::1111'
uci add_list dhcp.lan.dns='2001:4860:4860::8888'
uci add_list dhcp.lan.dns='2606:4700:4700::1001'
uci add_list dhcp.lan.dns='2001:4860:4860::8844'
uci commit
echo -e "\033[1;33m wan ipaddr6: ${NET_ADDR6}\033[0;33m"
echo -e "\033[1;32m ${WANMAP} peeraddr: \033[0;39m"${BR_ADDR}
echo -e "\033[1;32m ${WANMAP} ip4prefixlen: \033[0;39m"20
echo -e "\033[1;32m ${WANMAP} ip6pfx: \033[0;39m"${IPV6_PREFIX}::
echo -e "\033[1;32m ${WANMAP} ip6prefixlen: \033[0;39m"36
echo -e "\033[1;32m ${WANMAP} ealen: \033[0;39m"20
echo -e "\033[1;32m ${WANMAP} psidlen: \033[0;39m"8
echo -e "\033[1;32m ${WANMAP} offset: \033[0;39m"4
read -p " 何かキーを押してデバイスを再起動してください"
reboot
return 0
}


# MAP-E設定情報を表示する関数
mape_nuro_display() {

    printf "\n"
    printf "%s\n" "$(color blue "Prefix Information:")" # "プレフィックス情報:"
    printf "  IPv6 Prefix: %s\n" "$NEW_IP6_PREFIX" # "  IPv6プレフィックス: $NEW_IP6_PREFIX"
    printf "  CE IPv6 Address: %s\n" "$CE" # "  CE IPv6アドレス: $CE"
    printf "  IPv4 Address: %s\n" "$IPADDR" # "  IPv4アドレス: $IPADDR"
    printf "  PSID (Decimal): %s\n" "$PSID" # "  PSID値(10進数): $PSID"

    printf "\n"
    printf "%s\n" "$(color blue "OpenWrt Configuration Values:")" # "OpenWrt設定値:"
    printf "  option peeraddr '%s'\n" "$BR" # BRが空の場合もあるためクォート
    printf "  option ipaddr %s\n" "$IPV4"
    printf "  option ip4prefixlen '%s'\n" "$IP4PREFIXLEN"
    printf "  option ip6prefix '%s::'\n" "$IP6PFX" # IP6PFXが空の場合もあるためクォート
    printf "  option ip6prefixlen '%s'\n" "$IP6PREFIXLEN"
    printf "  option ealen '%s'\n" "$EALEN"
    printf "  option psidlen '%s'\n" "$PSIDLEN"
    printf "  option offset '%s'\n" "$OFFSET"
    printf "\n"
    printf "  export LEGACY=1\n"

    printf "\n"
    printf "%s\n" "$(color magenta "(config-softwire)# missing233")"
    printf "\n"
    printf "%s\n" "$(color green "$(get_message "MSG_MAPE_PARAMS_CALC_SUCCESS")")"
    printf "%s\n" "$(color yellow "$(get_message "MSG_MAPE_APPLY_SUCCESS")")"
    read -r -n 1 -s
    
    return 0
}

# MAP-E noro設定のバックアップを復元する関数
# 戻り値:
# 0: 1つ以上のバックアップが正常に復元され、再起動プロセス開始
# 1: 復元対象のバックアップファイルが1つも見つからなかった / またはその他のエラー
# 2: 1つ以上のファイルの復元に失敗したが、処理は継続し再起動プロセス開始
restore_mape_nuro() {
    local backup_files_restored_count=0
    local backup_files_not_found_count=0
    local restore_failed_count=0
    local total_files_to_check=0
    local overall_restore_status=1 # 初期値を「失敗または何もせず」に設定

    # 対象ファイルとバックアップファイルのマッピング
    # 構造: "オリジナルファイル名:バックアップファイル名"
    local files_to_restore="
        /etc/config/network:/etc/config/network.map-e-nuro.bak
        /etc/config/dhcp:/etc/config/dhcp.map-e-nuro.bak
        /etc/config/firewall:/etc/config/firewall.map-e-nuro.bak
    "

    debug_log "DEBUG" "Starting restore_mape function." # 関数名を修正

    # 各ファイルの復元処理
    for item in $files_to_restore; do
        total_files_to_check=$((total_files_to_check + 1))
        local original_file
        local backup_file
        original_file=$(echo "$item" | cut -d':' -f1)
        backup_file=$(echo "$item" | cut -d':' -f2)

        if [ -f "$backup_file" ]; then
            debug_log "DEBUG" "Attempting to restore '$original_file' from '$backup_file'."
            if cp "$backup_file" "$original_file"; then
                debug_log "DEBUG" "Successfully restored '$original_file' from '$backup_file'."
                backup_files_restored_count=$((backup_files_restored_count + 1))
            else
                debug_log "DEBUG" "Failed to copy '$backup_file' to '$original_file'."
                restore_failed_count=$((restore_failed_count + 1))
            fi
        else
            debug_log "DEBUG" "Backup file '$backup_file' not found. Skipping restore for '$original_file'."
            backup_files_not_found_count=$((backup_files_not_found_count + 1))
        fi
    done

    debug_log "DEBUG" "Restore process summary: Total checked=$total_files_to_check, Restored=$backup_files_restored_count, Not found=$backup_files_not_found_count, Failed=$restore_failed_count."

    if [ "$restore_failed_count" -gt 0 ]; then
        debug_log "DEBUG" "Restore completed with errors."
        overall_restore_status=2 # 1つ以上のファイルの復元に失敗
    elif [ "$backup_files_restored_count" -gt 0 ]; then
        debug_log "DEBUG" "Restore completed successfully for at least one file."
        overall_restore_status=0 # 1つ以上のバックアップが正常に復元された
    else
        # この分岐は backup_files_not_found_count == total_files_to_check と同義
        debug_log "DEBUG" "No backup files were found to restore."
        overall_restore_status=1 # 復元対象のバックアップファイルが1つも見つからなかった
    fi

    # overall_restore_status が 0 (成功) または 2 (一部失敗だが復元試行はあった) の場合に後続処理を実行
    if [ "$overall_restore_status" -eq 0 ] || [ "$overall_restore_status" -eq 2 ]; then
        debug_log "DEBUG" "Attempting to remove 'map' package as part of restore process."
        if opkg remove map >/dev/null 2>&1; then
            debug_log "DEBUG" "'map' package removed successfully."
        else
            debug_log "DEBUG" "Failed to remove 'map' package or package was not installed. Continuing."
        fi
        
        printf "\n%s\n" "$(color green "$(get_message "MSG_MAPE_RESTORE_COMPLETE")")"
        printf "%s\n" "$(color yellow "$(get_message "MSG_MAPE_APPLY_SUCCESS")")"
        read -r -n 1 -s
        printf "\n"
        
        debug_log "DEBUG" "Rebooting system after restore."
        reboot
        return 0 # reboot が呼ばれるので、ここには到達しないはずだが念のため
    elif [ "$overall_restore_status" -eq 1 ]; then
        # バックアップファイルが見つからなかった場合
        printf "\n%s\n" "$(color yellow "$(get_message "MSG_NO_BACKUP_FOUND")")"
        return 1 # 失敗として返す
    fi
    
    # 通常はここまで来ないはずだが、万が一のためのフォールバック
    return "$overall_restore_status"
}

internet_map_nuro_main() {

    print_section_title "MENU_INTERNET_MAPE"

    # MAP-Eパラメータ計算
    if ! mape_nuro_mold; then
        debug_log "DEBUG" "mape_mold function failed. Exiting script."
        return 1
    fi
    
    install_package map hidden
    
    replace_map_sh

    mape_nuro_config
    
    mape_nuro_display
    
    reboot

    return 0 # Explicitly exit with success status
}

# internet_map_nuro_main
