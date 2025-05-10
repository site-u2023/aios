# Radxa ZERO 3E and 3W OpenWrt

OpenWrt >= SNAPSHOT

## luci-app-cpu-perf
```
wget --no-check-certificate -O /tmp/luci-app-cpu-perf-0.4.1-r1.apk https://github.com/site-u2023/aios/raw/refs/heads/main/apk/luci-app-cpu-perf-0.4.1-r1.apk
apk add --allow-untrusted /tmp/luci-app-cpu-status-0.6.1-r1.apk
rm /tmp/luci-app-cpu-perf_0.4.1-r1_all.ipk
/etc/init.d/rpcd restart
/etc/init.d/cpu-perf start
```

## luci-app-cpu-status

```
wget --no-check-certificate -O /tmp/luci-app-cpu-status-0.6.1-r1.apk https://github.com/site-u2023/aios/raw/refs/heads/main/apk/luci-app-cpu-status-0.6.1-r1.apk
apk add --allow-untrusted /tmp/luci-app-cpu-perf-0.4.1-r1.apk
rm /tmp/luci-app-cpu-status_0.6.1-r1_all.ipk
/etc/init.d/rpcd reload
```

## luci-app-temp-status
```
wget --no-check-certificate -O /tmp/luci-app-temp-status-0.5.6-r2.apk https://github.com/site-u2023/aios/raw/refs/heads/main/apk/luci-app-temp-status-0.5.6-r2.apk
apk add --allow-untrusted /tmp/luci-app-temp-status-0.5.6-r2.apk
rm /tmp/luci-app-temp-status_0.5.6-r2_all.ipk
/etc/init.d/rpcd reload
```

this script based https://github.com/gSpotx2f
