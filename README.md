# all in one scripts

New config software is being tested.

Dedicated configuration software for OpenWrt

January 25, 2025: version α

![2025-03-15 133725](https://github.com/user-attachments/assets/e3c7cef3-140d-4583-ae63-378e6e40d83d)

## ダウンロード

### WGET
```sh
wget -q -O /usr/bin/aios raw.githubusercontent.com/site-u2023/aios/main/aios; sh /usr/bin/aios
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

### GitHub Personal Access Token
```sh
aios -t
```

## 要件定義書

https://github.com/site-u2023/aios/blob/main/requirement-definition.md

## テストデータ

```
| Device / Parallel | Download 1    | Download 2    | Download 3    | Lang Gen 1    | Lang Gen 2    | Lang Gen 3    |
|-------------------|---------------|---------------|---------------|---------------|---------------|---------------|
| *WRT Pro 7        |               |               |               |               |               |               |
| MAX PARALLELE: 1  | 73            | 66            | 70            | 50            | 51            | 49            |
| MAX PARALLELE: 2  | 37            | 38            | 36            | 29            | 25            | 24            |
| MAX PARALLELE: 3  | 28            | 6             | 6             | 20            | 18            | 18            |
| MAX PARALLELE: 4  | 7             | 6             | 17            | 17            | 18            | 22            |
| MAX PARALLELE: 5  | 18            | 17            | 17            | 22            | 29            | 26            |
| *NCP-HG100        |               |               |               |               |               |               |
| MAX PARALLELE: 1  | 90            | 87            | 89            | 82            | 82            | 82            |
| MAX PARALLELE: 2  | 49            | 49            | 48            | 54            | 60            | 59            |
| MAX PARALLELE: 3  | 36            | 35            | 38            | 50            | 47            | 42            |
| MAX PARALLELE: 4  | 30            | 31            | 30            | 31            | 31            | 32            |
| MAX PARALLELE: 5  | 10            | 10            | 9             | 25            | 23            | 23            |
```
