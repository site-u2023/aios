# all in one scripts

Supported since version 19.07

New config software is being tested

Dedicated configuration software for OpenWrt

May 15, 2025: version β

![aios](https://github.com/user-attachments/assets/5905387c-4117-48bd-afbf-eaacf70d1a1c)

## Install
Release Build (opkg)
```sh
opkg install https://github.com/site-u2023/aios-package/releases/download/ipk0.0/aios_all.ipk
```

<details><summary>For version 19.07</summary>

```sh
wget -O /tmp/aios_all.ipk "https://github.com/site-u2023/aios-package/releases/download/ipk0.0/aios_all.ipk"; opkg install /tmp/aios_all.ipk
```
---
</details>

“snapshot” build (apk)
```sh
wget -O /tmp/aios.apk "https://github.com/site-u2023/aios-package/releases/download/apk0.1/aios.apk"; apk add --allow-untrusted /tmp/aios.apk
```

### How to use
Command from the console
```sh
aios
```

### Specify country code
Example: JP
```sh
aios JP
```

### Location Information
```
https://location-api-worker.site-u.workers.dev/
```
