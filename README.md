# all in one scripts

New config software is being tested.

Dedicated configuration software for OpenWrt

January 25, 2025: version α

![2025-03-15 133725](https://github.com/user-attachments/assets/e3c7cef3-140d-4583-ae63-378e6e40d83d)

## ダウンロード

### WGET
```sh
wget -q -O /usr/bin/aios https://raw.githubusercontent.com/site-u2023/aios/main/aios; sh /usr/bin/aios
```

### キャッシュフリー
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; sh /usr/bin/aios
```

### JP
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; sh /usr/bin/aios JP
```
### US
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; sh /usr/bin/aios US
```

### デバッグモード
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; sh /usr/bin/aios -d
```

### aios アップデート
```sh
aios -u
```

## 要件定義書

https://github.com/site-u2023/aios/blob/main/requirement-definition.md
