# all in one scripts

Supported since version 19.07~ (snapshot compatible)

New config software is being tested

Dedicated configuration software for OpenWrt

May 15, 2025: version β

![aios](https://github.com/user-attachments/assets/5905387c-4117-48bd-afbf-eaacf70d1a1c)

## Install
Release Build (opkg)
```sh
opkg install https://github.com/site-u2023/aios-package/releases/download/ipk0.0/aios_all.ipk
```

<details><summary>If your environment is IPv6-only (before MAP tunnel setup), use the following via Cloudflare Workers proxy:</summary>

```sh
opkg install "https://proxy.site-u.workers.dev/proxy?url=https://github.com/site-u2023/aios-package/releases/download/ipk0.0/aios_all.ipk"
```
---
</details>

<details><summary>For version 21.02</summary>

```sh
wget -O /tmp/aios_all.ipk "https://github.com/site-u2023/aios-package/releases/download/ipk0.0/aios_all.ipk"; opkg install /tmp/aios_all.ipk
```
---
</details>

“Snapshot” build (apk)
```sh
wget -O /tmp/aios.apk "https://github.com/site-u2023/aios-package/releases/download/apk0.1/aios.apk"; apk add --allow-untrusted /tmp/aios.apk
```

<details><summary>If your environment is IPv6-only (before MAP tunnel setup), use the following via Cloudflare Workers proxy:</summary>

```sh
wget -O /tmp/aios.apk "https://proxy.site-u.workers.dev/proxy?url=https://github.com/site-u2023/aios-package/releases/download/apk0.1/aios.apk"
apk add --allow-untrusted /tmp/aios.apk
```
---
</details>

### How to use
Run from the console” or “Usage from the console
```sh
aios
```

### Specify country code
Example: JP
```sh
aios JP
```

### location-api-worker
```
https://location-api-worker.site-u.workers.dev/
```

### map-api-worker
```
https://map-api-worker.site-u.workers.dev/map-rule?user_prefix=<IPv6_PREFIX>
```

### Qiita
Japanese article

https://qiita.com/site_u/items/bd331296ce535ed7a69e
