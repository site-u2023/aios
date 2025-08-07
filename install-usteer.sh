#!/bin/sh
SSID='openwrt'
WIFI_KEY='password'
COUNTRY='JP'
MOBILITY_DOMAIN='1234'
BANDS="2g 5g 6g"
HTMODES="HE20 HE80 HE160"
TXPOWERS="'' '' ''"
CHANNELS="1 auto auto"
NASIDS="ap1-2g ap1-5g ap1-6g"
SNR="30 15 5"

opkg list-installed | grep -q "luci-app-usteer" || { opkg update && opkg install luci-app-usteer; }
cp /etc/config/wireless /etc/config/wireless.usteer.bak
rm /etc/config/wireless
wifi config

NUM_IFACES=$(grep -c "^config wifi-device" /etc/config/wireless)
i=0
while [ $i -lt $NUM_IFACES ]; do
    iface="default_radio${i}"
    radio="radio${i}"
    band=$(echo $BANDS | awk -v n=$((i+1)) '{print $n}')
    htmode=$(echo $HTMODES | awk -v n=$((i+1)) '{print $n}')
    txpower=$(echo $TXPOWERS | awk -v n=$((i+1)) '{print $n}')
    nasid=$(echo $NASIDS | awk -v n=$((i+1)) '{print $n}')
    min_snr=$(echo $SNR | awk -v n=$((i+1)) '{print $n}')
    channel=$(echo $CHANNELS | awk -v n=$((i+1)) '{print $n}')
    
    uci set wireless.$radio.band="$band"
    uci set wireless.$radio.channel="$channel"
    uci set wireless.$radio.htmode="$htmode"
    uci set wireless.$radio.country="$COUNTRY"
    [ -n "$txpower" ] && uci set wireless.$radio.txpower="$txpower"
    uci set wireless.$radio.disabled='0'
    
    uci set wireless.$iface.device="$radio"
    uci set wireless.$iface.network='lan'
    uci set wireless.$iface.mode='ap'
    uci set wireless.$iface.ssid="$SSID"
    uci set wireless.$iface.encryption='sae'
    uci set wireless.$iface.key="$WIFI_KEY"
    uci set wireless.$iface.isolate='1'
    uci set wireless.$iface.ocv='1'
    uci set wireless.$iface.ieee80211r='1'
    uci set wireless.$iface.mobility_domain="$MOBILITY_DOMAIN"
    uci set wireless.$iface.ft_over_ds='1'
    uci set wireless.$iface.nasid="$nasid"
    uci set wireless.$iface.usteer_min_snr="$min_snr"
    uci set wireless.$iface.ieee80211k='1'
    uci set wireless.$iface.ieee80211v='1'
    uci set wireless.$iface.disabled='0'
    
    # DFS (BPI-R4固有設定)
    [ "$band" = "5g" ] && uci set wireless.$iface.background_radar='1' && uci set wireless.$iface.ft_psk_generate_local='1'
    
    i=$((i+1))
done

uci set usteer.@usteer[0].band_steering='1'
uci set usteer.@usteer[0].load_balancing='1'
uci set usteer.@usteer[0].sta_block_timeout='300'
uci set usteer.@usteer[0].min_snr='20'
uci set usteer.@usteer[0].max_snr='80'
uci set usteer.@usteer[0].signal_diff_threshold='10'
uci set wireless.default_radio1.background_radar=1

uci commit
/etc/init.d/usteer enable
/etc/init.d/usteer start
wifi reload
