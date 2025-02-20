#!/bin/sh

# Map-E (MAP-E) 自動設定スクリプト
# OpenWrt の BusyBox Ash 互換
# Last Updated: 2025-02-21

# ** 設定変数 **
CONFIG_FILE="/etc/config/network"
WAN_INTERFACE="wan"
MAP_E_SECTION="map-e"
MAP_E_CONFIG="/etc/config/map-e"
MAP_E_TUNNEL_INTERFACE="map-e0"
MAP_E_RULE="map-rule"

# ** ルールデータ（ruleprefix31, ruleprefix38）を定義 **
RULE_PREFIX31="
0x240b0010=106,72
0x240b0012=14,8
0x240b0250=14,10
0x240b0252=14,12
0x24047a80=133,200
0x24047a84=133,206
"

RULE_PREFIX38="
0x24047a8200=125,196,208
0x24047a8204=125,196,212
0x24047a8208=125,198,140
0x24047a820c=125,198,144
0x24047a8210=125,198,212
0x24047a8214=125,198,244
0x24047a8218=122,131,104
0x24047a821c=125,195,20
0x24047a8220=133,203,160
0x24047a8224=133,203,164
0x24047a8228=133,203,168
0x24047a822c=133,203,172
0x24047a8230=133,203,176
0x24047a8234=133,203,180
0x24047a8238=133,203,184
0x24047a823c=133,203,188
0x24047a8240=133,209,0
0x24047a8244=133,209,4
0x24047a8248=133,209,8
0x24047a824c=133,209,12
0x24047a8250=133,209,16
0x24047a8254=133,209,20
0x24047a8258=133,209,24
0x24047a825c=133,209,28
0x24047a8260=133,204,192
0x24047a8264=133,204,196
0x24047a8268=133,204,200
0x24047a826c=133,204,204
0x24047a8270=133,204,208
0x24047a8274=133,204,212
0x24047a8278=133,204,216
0x24047a827c=133,204,220
0x24047a8280=133,203,224
0x24047a8284=133,203,228
0x24047a8288=133,203,232
0x24047a828c=133,203,236
0x24047a8290=133,203,240
0x24047a8294=133,203,244
0x24047a8298=133,203,248
0x24047a829c=133,203,252
0x24047a82a0=125,194,192
0x24047a82a4=125,194,196
0x24047a82a8=125,194,200
0x24047a82ac=125,194,204
0x24047a82b0=119,239,128
0x24047a82b4=119,239,132
0x24047a82b8=119,239,136
0x24047a82bc=119,239,140
0x24047a82c0=125,194,32
0x24047a82c4=125,194,36
0x24047a82c8=125,194,40
0x24047a82cc=125,194,44
0x24047a82d0=125,195,24
0x24047a82d4=125,195,28
0x24047a82d8=122,130,192
0x24047a82dc=122,130,196
0x24047a82e0=122,135,64
0x24047a82e4=122,135,68
0x24047a82e8=125,192,240
0x24047a82ec=125,192,244
0x24047a82f0=125,193,176
0x24047a82f4=125,193,180
"

RULE_PREFIX38_20="
0x2400405000=153,240,0
0x2400405004=153,240,16
0x2400405008=153,240,32
0x240040500c=153,240,48
0x2400405010=153,240,64
0x2400405014=153,240,80
0x2400405018=153,240,96
0x240040501c=153,240,112
0x2400405020=153,240,128
0x2400405024=153,240,144
0x2400405028=153,240,160
0x240040502c=153,240,176
0x2400405030=153,240,192
0x2400405034=153,240,208
0x2400405038=153,240,224
0x240040503c=153,240,240
0x2400405040=153,241,0
0x2400405044=153,241,16
0x2400405048=153,241,32
0x240040504c=153,241,48
0x2400405050=153,241,64
0x2400405054=153,241,80
0x2400405058=153,241,96
0x240040505c=153,241,112
0x2400405060=153,241,128
0x2400405064=153,241,144
0x2400405068=153,241,160
0x240040506c=153,241,176
0x2400405070=153,241,192
0x2400405074=153,241,208
0x2400405078=153,241,224
0x240040507c=153,241,240
0x2400405080=153,242,0
0x2400405084=153,242,16
0x2400405088=153,242,32
0x240040508c=153,242,48
0x2400405090=153,242,64
0x2400405094=153,242,80
0x2400405098=153,242,96
0x240040509c=153,242,112
0x24004050a0=153,242,128
0x24004050a4=153,242,144
0x24004050a8=153,242,160
0x24004050ac=153,242,176
0x24004050b0=153,242,192
0x24004050b4=153,242,208
0x24004050b8=153,242,224
0x24004050bc=153,242,240
"

# ** デバッグ出力（必要なら "1" にする）**
DEBUG=0

debug_log() {
    [ "$DEBUG" -eq 1 ] && echo "[DEBUG] $1"
}

# ** 設定を保存する関数 **
save_config() {
    uci commit network
}

# ** 設定をリロードする関数 **
reload_network() {
    /etc/init.d/network restart
}

# ** 既存の MAP-E 設定を削除する関数 **
remove_map_e_config() {
    uci delete network.$MAP_E_SECTION 2>/dev/null
    uci delete network.$MAP_E_TUNNEL_INTERFACE 2>/dev/null
    uci delete firewall.$MAP_E_RULE 2>/dev/null
    save_config
}

# ** MAP-E の設定を追加する関数 **
add_map_e_config() {
    debug_log "MAP-E 設定を追加します..."

    uci set network.$MAP_E_SECTION="interface"
    uci set network.$MAP_E_SECTION.proto="map-e"
    uci set network.$MAP_E_SECTION.ifname="$MAP_E_TUNNEL_INTERFACE"
    uci set network.$MAP_E_SECTION.peerdns="0"
    uci set network.$MAP_E_SECTION.delegate="0"

    uci set network.$MAP_E_TUNNEL_INTERFACE="interface"
    uci set network.$MAP_E_TUNNEL_INTERFACE.proto="map-e"
    uci set network.$MAP_E_TUNNEL_INTERFACE.peerdns="0"

    uci set firewall.$MAP_E_RULE="rule"
    uci set firewall.$MAP_E_RULE.src="wan"
    uci set firewall.$MAP_E_RULE.proto="all"
    uci set firewall.$MAP_E_RULE.target="ACCEPT"

    save_config
    debug_log "MAP-E 設定が完了しました。"
}

# ** ルールを適用する関数（ruleprefix31, ruleprefix38）**
apply_rules() {
    debug_log "Applying ruleprefix31..."
    echo "$RULE_PREFIX31" | while IFS="=" read -r key value; do
        debug_log "Setting rule: $key → $value"
        uci set network.$MAP_E_SECTION.ruleprefix31_$key="$value"
    done

    debug_log "Applying ruleprefix38..."
    echo "$RULE_PREFIX38" | while IFS="=" read -r key value; do
        debug_log "Setting rule: $key → $value"
        uci set network.$MAP_E_SECTION.ruleprefix38_$key="$value"
    done

    save_config
}

# ** WAN インターフェースのチェック **
check_wan_interface() {
    if ! uci get network.$WAN_INTERFACE >/dev/null 2>&1; then
        echo "WAN インターフェースが設定されていません。" >&2
        exit 1
    fi
}

# ** スクリプトの実行 **
main() {
    check_wan_interface
    remove_map_e_config
    add_map_e_config
    apply_rules
    reload_network
    echo "MAP-E 設定が完了しました。"
}

main
