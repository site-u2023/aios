# all in one scripts

New config software is being tested.

Dedicated configuration software for OpenWrt

January 25, 2025: version α

![main](https://github.com/user-attachments/assets/ebfc8ca2-a42e-470c-9a89-9b5e3eb4ccb8)


## ダウンロード

### WGET
```sh
wget -q -O /usr/bin/aios https://raw.githubusercontent.com/site-u2023/aios/main/aios; aios
```

### キャッシュフリー
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; aios
```

### 日本語
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; aios 日本
```
### English
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; aios English
```

### デバッグモード
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; aios -d
```

## 要件定義書

https://github.com/site-u2023/aios/blob/main/requirement-definition.md
