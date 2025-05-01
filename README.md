# all in one scripts

New config software is being tested.

Dedicated configuration software for OpenWrt

January 25, 2025: version α

![2025-03-15 133725](https://github.com/user-attachments/assets/e3c7cef3-140d-4583-ae63-378e6e40d83d)

### aios アップデート
```sh
aios -u
```

### GitHub Personal Access Token
```sh
aios -t
```

### 並列処理 テストデータ

| Device / Parallel | Download 1 (s) | Download 2 (s) | Download 3 (s) | Lang Gen 1 (s) | Lang Gen 2 (s) | Lang Gen 3 (s) |
|-------------------|---------------|---------------|---------------|---------------|---------------|---------------|
| [**Velop WRT Pro 7 19.07**](https://qiita.com/site_u/items/aa619d4330a4f206d16b) |               |               |               |               |               |               |
| MAX PARALLELE: 1  | 73            | 66            | 70            | 50            | 51            | 49            |
| MAX PARALLELE: 2  | 37            | 38            | 36            | 29            | 25            | 24            |
| MAX PARALLELE: 3  | 28            | 6             | 6             | 20            | 18            | 18            |
| MAX PARALLELE: 4  | 7             | 6             | 17            | 17            | 18            | 22            |
| MAX PARALLELE: 5  | 18            | 17            | 17            | 22            | 29            | 26            |
| Current Specifications: 4 | 3             | 11            | 18            | 21            | 21            | 18            |
| [**NCP-HG100 24.10**](https://qiita.com/site_u/items/e07cd5b6326039e45fde) |               |               |               |               |               |               |
| MAX PARALLELE: 1  | 90            | 87            | 89            | 82            | 82            | 82            |
| MAX PARALLELE: 2  | 49            | 49            | 48            | 54            | 60            | 59            |
| MAX PARALLELE: 3  | 36            | 35            | 38            | 50            | 47            | 42            |
| MAX PARALLELE: 4  | 30            | 31            | 30            | 31            | 31            | 32            |
| MAX PARALLELE: 5  | 10            | 10            | 9             | 25            | 23            | 23            |
| Current Specifications: 5 | 11            | 19            | 25            | 12            | 12            | 13            |

## 要件定義書

https://github.com/site-u2023/aios/blob/main/requirement-definition.md
