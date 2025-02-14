# all in one script

## ダウンロード

### キャッシュフリー
```sh
wget --quiet -O /tmp/aios.sh "https://raw.githubusercontent.com/site-u2023/aios/main/aios.sh?cache_bust=$(date +%s)"; sh /tmp/aios.sh
```

### デバッグ用

```sh
wget --quiet -O /tmp/aios.sh "https://raw.githubusercontent.com/site-u2023/aios/main/aios.sh?cache_bust=$(date +%s)"; sh /tmp/aios.sh -d
```

- 日本
```sh
wget --quiet -O /tmp/aios.sh "https://raw.githubusercontent.com/site-u2023/aios/main/aios.sh?cache_bust=$(date +%s)"; sh /tmp/aios.sh -d 日本
```

- us
```sh
wget --quiet -O /tmp/aios.sh "https://raw.githubusercontent.com/site-u2023/aios/main/aios.sh?cache_bust=$(date +%s)"; sh /tmp/aios.sh -d us
```

### 言語付

- JP
```sh
wget --quiet -O /tmp/aios.sh "https://raw.githubusercontent.com/site-u2023/aios/main/aios.sh?cache_bust=$(date +%s)"; sh /tmp/aios.sh JP
```

## 要件定義書

https://github.com/site-u2023/aios/blob/main/requirement-definition.md
