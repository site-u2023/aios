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

RULE_PREFIX31="
hex_240b0010=106,72
hex_240b0012=14,8
hex_240b0250=14,10
hex_240b0252=14,12
hex_24047a80=133,200
hex_24047a84=133,206
"

# ruleprefix38 をリスト形式で定義 (0x を hex_ に変換)
RULE_PREFIX38="
hex_24047a8200=125,196,208
hex_24047a8204=125,196,212
hex_24047a8208=125,198,140
hex_24047a820c=125,198,144
hex_24047a8210=125,198,212
hex_24047a8214=125,198,244
hex_24047a8218=122,131,104
hex_24047a821c=125,195,20
hex_24047a8220=133,203,160
hex_24047a8224=133,203,164
hex_24047a8228=133,203,168
hex_24047a822c=133,203,172
hex_24047a8230=133,203,176
hex_24047a8234=133,203,180
hex_24047a8238=133,203,184
hex_24047a823c=133,203,188
hex_24047a8240=133,209,0
hex_24047a8244=133,209,4
hex_24047a8248=133,209,8
hex_24047a824c=133,209,12
hex_24047a8250=133,209,16
hex_24047a8254=133,209,20
hex_24047a8258=133,209,24
hex_24047a825c=133,209,28
hex_24047a8260=133,204,192
hex_24047a8264=133,204,196
hex_24047a8268=133,204,200
hex_24047a826c=133,204,204
hex_24047a8270=133,204,208
hex_24047a8274=133,204,212
hex_24047a8278=133,204,216
hex_24047a827c=133,204,220
hex_24047a8280=133,203,224
hex_24047a8284=133,203,228
hex_24047a8288=133,203,232
hex_24047a828c=133,203,236
hex_24047a8290=133,203,240
hex_24047a8294=133,203,244
hex_24047a8298=133,203,248
hex_24047a829c=133,203,252
hex_24047a82a0=125,194,192
hex_24047a82a4=125,194,196
hex_24047a82a8=125,194,200
hex_24047a82ac=125,194,204
hex_24047a82b0=119,239,128
hex_24047a82b4=119,239,132
hex_24047a82b8=119,239,136
hex_24047a82bc=119,239,140
hex_24047a82c0=125,194,32
hex_24047a82c4=125,194,36
hex_24047a82c8=125,194,40
hex_24047a82cc=125,194,44
hex_24047a82d0=125,195,24
hex_24047a82d4=125,195,28
hex_24047a82d8=122,130,192
hex_24047a82dc=122,130,196
hex_24047a82e0=122,135,64
hex_24047a82e4=122,135,68
hex_24047a82e8=125,192,240
hex_24047a82ec=125,192,244
hex_24047a82f0=125,193,176
hex_24047a82f4=125,193,180
hex_24047a82f8=122,130,176
hex_24047a82fc=122,130,180
hex_24047a8300=122,131,24
hex_24047a8304=122,131,28
hex_24047a8308=122,131,32
hex_24047a830c=122,131,36
hex_24047a8310=119,243,112
hex_24047a8314=119,243,116
hex_24047a8318=219,107,136
hex_24047a831c=219,107,140
hex_24047a8320=220,144,224
hex_24047a8324=220,144,228
hex_24047a8328=125,194,64
hex_24047a832c=125,194,68
hex_24047a8330=221,171,40
hex_24047a8334=221,171,44
hex_24047a8338=110,233,80
hex_24047a833c=110,233,84
hex_24047a8340=119,241,184
hex_24047a8344=119,241,188
hex_24047a8348=119,243,56
hex_24047a834c=119,243,60
"

# ruleprefix38_20 をリスト形式で定義 (0x を hex_ に変換)
RULE_PREFIX38_20="
hex_2400405000=153,240,0
hex_2400405004=153,240,16
hex_2400405008=153,240,32
hex_240040500c=153,240,48
hex_2400405010=153,240,64
hex_2400405014=153,240,80
hex_2400405018=153,240,96
hex_240040501c=153,240,112
hex_2400405020=153,240,128
hex_2400405024=153,240,144
hex_2400405028=153,240,160
hex_240040502c=153,240,176
hex_2400405030=153,240,192
hex_2400405034=153,240,208
hex_2400405038=153,240,224
hex_240040503c=153,240,240
hex_2400405040=153,241,0
hex_2400405044=153,241,16
hex_2400405048=153,241,32
hex_240040504c=153,241,48
hex_2400405050=153,241,64
hex_2400405054=153,241,80
hex_2400405058=153,241,96
hex_240040505c=153,241,112
hex_2400405060=153,241,128
hex_2400405064=153,241,144
hex_2400405068=153,241,160
hex_240040506c=153,241,176
hex_2400405070=153,241,192
hex_2400405074=153,241,208
hex_2400405078=153,241,224
hex_240040507c=153,241,240
hex_2400405080=153,242,0
hex_2400405084=153,242,16
hex_2400405088=153,242,32
hex_240040508c=153,242,48
hex_2400405090=153,242,64
hex_2400405094=153,242,80
hex_2400405098=153,242,96
hex_240040509c=153,242,112
hex_24004050a0=153,242,128
hex_24004050a4=153,242,144
hex_24004050a8=153,242,160
hex_24004050ac=153,242,176
hex_24004050b0=153,242,192
hex_24004050b4=153,242,208
hex_24004050b8=153,242,224
hex_24004050bc=153,242,240
hex_24004050c0=153,243,0
hex_24004050c4=153,243,16
hex_24004050c8=153,243,32
hex_24004050cc=153,243,48
hex_24004050d0=153,243,64
hex_24004050d4=153,243,80
hex_24004050d8=153,243,96
hex_24004050dc=153,243,112
hex_24004050e0=153,243,128
hex_24004050e4=153,243,144
hex_24004050e8=153,243,160
hex_24004050ec=153,243,176
hex_24004050f0=153,243,192
hex_24004050f4=153,243,208
hex_24004050f8=153,243,224
hex_24004050fc=153,243,240
hex_2400405100=122,26,0
hex_2400405104=122,26,16
hex_2400405108=122,26,32
hex_240040510c=122,26,48
hex_2400405110=122,26,64
hex_2400405114=122,26,80
hex_2400405118=122,26,96
hex_240040511c=122,26,112
hex_2400405120=114,146,64
hex_2400405124=114,146,80
hex_2400405128=114,146,96
hex_240040512c=114,146,112
hex_2400405130=114,148,192
hex_2400405134=114,148,208
hex_2400405138=114,148,224
hex_240040513c=114,148,240
"




##########################################################################
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
