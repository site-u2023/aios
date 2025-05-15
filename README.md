# all in one scripts

New config software is being tested.

Dedicated configuration software for OpenWrt

January 25, 2025: version α

![2025-03-15 133725](https://github.com/user-attachments/assets/e3c7cef3-140d-4583-ae63-378e6e40d83d)

## Install
Release Build (opkg)
```sh
opkg install https://github.com/site-u2023/aios-package/releases/latest/download/aios.ipk
```

“snapshot” build (apk)
```sh

```

### How to use
Command from the console.
```sh
aios
```

### To specify a country code.
Example: JP
```sh
aios -JP
```

### Parallel Processing Test Data

| Device / Parallel | Download 1 (s) | Download 2 (s) | Download 3 (s) | Lang Gen 1 (s) | Lang Gen 2 (s) | Lang Gen 3 (s) |
|-------------------|---------------|---------------|---------------|---------------|---------------|---------------|
| コミュファ光: 1G  |               |               |               |               |               |               |
| [**Velop WRT Pro 7 (19.07)**](https://qiita.com/site_u/items/aa619d4330a4f206d16b) |               |               |               |               |               |               |
| MAX PARALLELE: 1  | 73            | 66            | 70            | 50            | 51            | 49            |
| MAX PARALLELE: 2  | 37            | 38            | 36            | 29            | 25            | 24            |
| MAX PARALLELE: 3  | 28            | 6             | 6             | 20            | 18            | 18            |
| MAX PARALLELE: 4  | 7             | 6             | 17            | 17            | 18            | 22            |
| MAX PARALLELE: 5  | 18            | 17            | 17            | 22            | 29            | 26            |
| create_language_db_19: 4 | 1             | 3            | 1            | 22            | 22            | 21             |
| **Radxa ZERO 3W (24.10)** |               |               |               | 
| create_language_db_all: 5 | 1            | 2            | 1             | 4             | 5            | 5            |
| [**NCP-HG100 (24.10)**](https://qiita.com/site_u/items/e07cd5b6326039e45fde) |               |               |               |               |               |               |
| フレッツ光: 1G  |               |               |               |               |               |               |
| MAX PARALLELE: 1  | 90            | 87            | 89            | 82            | 82            | 82            |
| MAX PARALLELE: 2  | 49            | 49            | 48            | 54            | 60            | 59            |
| MAX PARALLELE: 3  | 36            | 35            | 38            | 50            | 47            | 42            |
| MAX PARALLELE: 4  | 30            | 31            | 30            | 31            | 31            | 32            |
| MAX PARALLELE: 5  | 10            | 10            | 9             | 25            | 23            | 23            |
| create_language_db_all: 5 | 3            | 3            | 3             | 13            | 14            | 14            |
### 

```
+---------------------------------+      +-----------------------+      +--------------------------+
| create_language_db_parallel()   |----->| message_en.db (Input) |----->| awk | while read loop    | Reads DB line by line
| (Caller)                        |      +-----------------------+      +--------------------------+
+---------------------------------+                                           |
         |                                                                    | For each Line read:
         | Determines Max Tasks                                               |
         | (e.g., MAX_PARALLEL_TASKS)                                         | Launch Subshell (up to Max Tasks)
         |                                                                    |_________________________________
         |                                                                    |           |           |
         |                                                                    V           V           V
         |                                                            +-----------+ +-----------+ +-----------+
         |                                                            | Subshell  | | Subshell  | | Subshell  | ... (Many subshells, one per line)
         |                                                            | (Line 1)  | | (Line 2)  | | (Line M)  |
         |                                                            +-----------+ +-----------+ +-----------+
         |                                                                    |           |           |
         V                                                                    V           V           V
+---------------------------------+                                 +-----------+ +-----------+ +-----------+
| (Waits for Subshells using      |                                 | translate | | translate | | translate |
|  job control: wait -n or wait)  |<--------------------------------| _single_  | | _single_  | | _single_  |
+---------------------------------+                                 | line()    | | line()    | | line()    |
                                                                    +-----------+ +-----------+ +-----------+
                                                                         |           |           |
                                                                         | Got       | Got       | Got
                                                                         | Translated| Translated| Translated
                                                                         | Line      | Line      | Line
                                                                         V           V           V
                                                                    +-----------+ +-----------+ +-----------+
                                                                    | Write to  | | Write to  | | Write to  | NO LOCK NEEDED HERE
                                                                    | Temp File | | Temp File | | Temp File | Output Target: message_ja.db.partial_PIDNANOSEC
                                                                    | (*.part_1)| | (*.part_2)| | (*.part_M)|
                                                                    +-----------+ +-----------+ +-----------+
                                                                         |           |           |
                                                                      [Subshell 1 Finishes] ... [Subshell M Finishes]
                                                                         |___________________________|
                                                                         |
                                                                         V (After ALL lines processed and subshells waited for)
+---------------------------------+      +-------------------------------------------------+
| create_language_db_parallel()   |----->| Combine Partial Files (find/cat >> final_db)    | Combines *.partial_* into message_ja.db
| (Continues after loop/wait)     |      +-------------------------------------------------+
+---------------------------------+                                |
         |                                                         V
         |                               +-------------------------------------------------+
         |------------------------------>| Delete Partial Files (find/rm)                  | Removes *.partial_*
         |                               +-------------------------------------------------+
         V
+---------------------------------+
| Add Completion Marker           | Appends marker to message_ja.db (NO lock needed here)
| (No Lock Needed)                |
+---------------------------------+
         |
         V
       [End]
```

### 関数比較: `create_language_db_19` vs `create_language_db_all`

| 特徴             | `create_language_db_19` (チャンク方式)          | `create_language_db_all` (一時ファイル方式)     |
| ---------------- | --------------------------------------------- | --------------------------------------------- |
| 分割単位         | ファイル全体をチャンクに分割                   | 行ごとに処理                               |
| 並列単位         | チャンクごと                                  | 行ごと                                     |
| 中間ファイル     | チャンク入力ファイル (`*.tmp.in.*`)             | 多数の一時出力ファイル (`*.partial_*`)        |
| 書き込み先       | 直接最終ファイルへ                           | 一時ファイルへ書き込み、最後に結合           |
| ロック           | 最終ファイルへの書き込み時に必要 (`mkdir`/`rmdir`) | 並列処理中の書き込みには不要               |
| I/Oパターン      | 最初に分割I/O、並列中は最終ファイルへのロック競合/書き込み | 並列中は多数の一時ファイルへの書き込み、最後に結合/削除I/O |
| 複雑性           | ロック機構の実装                             | 一時ファイルの管理と結合処理                 |

## Requirement Document

