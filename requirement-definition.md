# 要件定義 (AIOS - All in One Script)
**Last update:** 2025-02-06-1

---

## 1. プロジェクト概要

**プロジェクト名:**  
**All in One Script (AIOS)**

**概要:**  
OpenWrt 環境向けの統合管理スクリプト群。初期設定からデバイス管理、ネットワーク設定、推奨パッケージインストール、DNSフィルタリング、他までを一元管理。各スクリプトは個別でも利用可能で、共通関数による多言語対応を実装。軽量かつ柔軟な構成を特徴とし、保守性と拡張性を両立。

---

## 2. 参照リンク

**新スクリプト群 (AIOS):**  
- [GitHub - aios](https://github.com/site-u2023/aios/blob/main/)  
- [README.md - aios](https://github.com/site-u2023/aios/blob/main/README.md)

**旧スクリプト群 (config-software):**  
- [GitHub - config-software](https://github.com/site-u2023/config-software)  
- [README.md - config-software](https://github.com/site-u2023/config-software/blob/main/README.md)

**Qiita 記事:**  
- [Qiita - AIOS 解説](https://qiita.com/site_u/items/c6a50aa6dea965b5a774)

---

## 3. スクリプト構成

```
aios.sh                           ← 初回エントリーポイント
  |── ttyd.sh                     ← コンソールUI(オプションスクリプト)
  └── aios(/usr/bin)              ← メインエントリーポイント
    ├── common.sh                 ← 共通関数
    ├── country.db                ← 国名、言語、短縮国名、ゾーンネーム、タイムゾーンデータベース
    ├── message.db                ← 多言語データベース
    ├── openwrt.db                ← OpenWrバージョンデータベース
    ├── country.cache             ← カントリーコードキャッシュ
    ├── openwrt.ch                ← OpenWrtバージョンキャッシュ
    ├── downloader.ch             ← ダウンローダータイプキャッシュ
    ├── script.ch                 ← スクリプトファイルバージョンキャッシュ
    └── openwrt-config.sh         ← メインメニュー（各種設定スクリプトへのリンク）
      ├── internet-config.sh      ← インターネット回線設定
      |  |── map-e.sh
      |  |── map-e-nuro.sh
      |  |── ds-lite.sh
      |  └── pppoe.sh
      ├── access-point-config.sh  ← アクセスポイント設定
      ├── system-config.sh        ← デバイス、WiFi設定
      ├── package-config.sh       ← パッケージインストール
      ├── dns-adblocker.sh        ← DNS＆広告ブロッカーインストール設定
      |  |── adguard-config.sh
      |  |── adblock-config.sh
      |── etc-config.sh             ← その他・・・
      |  |── ・・・
      |  |── ・・・
      |── exit
      └─── delete & exit
```

---

## 4. 定数と環境変数の設定

**コモンファイル (`common.sh`) 内の基本定数:**

```sh
#!/bin/sh
# License: CC0
# OpenWrt >= 19.07

COMMON_VERSION="2025.02.05-rc1"
echo "comon Last update: $COMMON_VERSION"

# 基本定数の設定
# BASE_WGET="${BASE_WGET:-wget -O}" # テスト用
BASE_WGET="${BASE_WGET:-"wget --quiet -O}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
SUPPORTED_VERSIONS="${SUPPORTED_VERSIONS:-19 21 22 23 24 SN}"
SUPPORTED_LANGUAGES="${SUPPORTED_LANGUAGES:-en}"
```

**各スクリプト内の定数設定（個別に異なる場合あり）:**

```sh
#!/bin/sh
# License: CC0
# OpenWrt >= 19.07

AIOS_VERSION="2025.02.05-rc1"
echo "aios Last update: $AIOS_VERSION"

# BASE_WGET="wget -O"
BASE_WGET="wget --quiet -O"
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"
SUPPORTED_VERSIONS="19 21 22 23 24 SN"  # ファイルごとに異なる可能性あり
SUPPORTED_LANGUAGES="en ja zh-cn zh-tw id ko de ru"  # ファイルごとに異なる可能性あり
INPUT_LANG="$1"
```

---

## 5. スクリプト動作要件

- **各スクリプトは、AIOS メニューからの利用と単独実行（コモンファイルは利用）の両方をサポート。**
- **カントリー、バージョン、ダウンローダのチェックは常に `common.sh` で共通化。**
- **~~個別の echo メッセージはスクリプト単位で管理~~、共通の echo はデータベースで管理。**
- **言語対応は LuCI パッケージ全言語を考慮。言語DB分のみ対応し、未翻訳言語はデフォルトで `en` を使用。**

---

## 6. 各スクリプトの役割

### **`aios.sh`:**  
- 初回設定用。最小限の依存関係で実行し、バージョンチェックを行う迄（`common.sh` を使用しない）。  
- `$1` で言語をチェック。指定がない場合はデータベースからカントリーを選択、もしくはキャッシュを利用（DBから完全一致後、曖昧検索で判定）。  
- カントリー決定後、キャッシュに保存。
- 

### **`ttyd.sh`:**  
- `aios` をクライアントのコンソール UI として利用するオプションスクリプト。
- YN判定でインストール可否
  
### **`aios` (メインスクリプト):**  
- スクリプト群のダウンロードと実行を担当。リンクファイルはファイルバージョンチェックで常に最新をダウンロード（バージョンミスマッチでも続行）。  
- スクリプトファイルバージョンチェック、カントリーチェック、OpenWrtバージョンチェック、ダウンローダーチェック（`opkg` と `apk` ）後、キャッシュに保存。

### **`common.sh`:**  
- **共通関数（メッセージ出力、YN 判定、ファイルダウンロードなど）を提供。**  

### **`country.db`:**  
- 国名、母国語（LuCI 言語識別）、短縮国名（WiFi 設定）、ゾーンネーム（デバイス設定）、タイムゾーンのデータベース。

### **`message.db`:**  
- 多言語メッセージのデータベース

### **`****.ch`:** 
- 各種データキャッシュ

### **`openwrt-config.sh`:**  
- メインメニュー。各種設定スクリプトへのリンク。

### **その他スクリプト:**
- **`system-config.sh`**: デバイス、WiFi 初期設定  
- **`internet-config.sh`**: 各種インターネット回線自動設定  
- **`dns-adblocker.sh`**: DNS フィルタリングと広告ブロッカー設定  

---

## 7. 命名規則
関数名は機能ごとにプレフィックスを付け、役割を明確にします。

```
- `check_`: 状態確認系の関数（例: `check_version_common`, `check_language_common`）
- `download_`: ファイルダウンロード系の関数（例: `download_common_functions`, `download_country_zone`）
- `handle_`: エラー処理および制御系の関数（例: `handle_error`, `handle_exit`）
- `configure_`: 設定変更系の関数（例: `configure_ttyd`, `configure_network`）
- `print_`: 表示・出力系の関数（例: `print_banner`, `print_help`, `print_colored_message`）
```

## 8. 関数一覧

```
| **関数名**         | **説明**                                                                 | **呼び出し元スクリプト**             |
|--------------------|--------------------------------------------------------------------------|--------------------------------------|
| **check_openwrt**  | OpenWrtのバージョンを確認し、サポートされているか検証します。            | `aios.sh` , 他全て                   |
| **check_country**  | 指定された言語がサポートされているか確認し、デフォルト言語を設定します。 | `aios.sh` , 他全て                   |
| **download_common**| `common.sh` をダウンロードし、読み込みます。                             | `aios.sh`, 他全て                    |
| **download_country**| `country.sh` をダウンロードし、読み込みます。                           | `aios.sh`, `system-config.sh`        |
| **handle_error**   | エラーメッセージを表示し、スクリプトを終了します。                       | 全スクリプト                         |
| **handle_exit**    | 正常終了時の処理を行います。                                             | 全スクリプト                         |
| **print_banner**   | 多言語対応のバナーを表示します。                                         | `aios.sh`, `openwrt-config.sh`       |
| **color**          | カラーコードを使用してメッセージを表示します。                           | 全スクリプト                         |
```

## 9. データベースの定義

```
| **データベース名**          | **形式**                                            | **保存先**                   |
|----------------------------|-----------------------------------------------------|------------------------------|
| **country.db **            | Russia Русский ru RU Europe/Moscow,Asia/Krasnoyarsk,Asia/Yekaterinburg,Asia/Irkutsk,Asia/Vladivostok;MSK-3,SAMT-4,YEKT-5,OMST-6,KRAT-7,IRKT-8,YAKT-9,VLAT-10,MAGT-11 |  `${BASE_DIR}/country.db`  |
| **message.db**             | ja|MSG_INSTALL_PROMPT_PKG={pkg}                     | ${BASE_DIR}/message.db`      |
| **openwrt.db**             | 24.10.0=opkg|stable                                 | ${BASE_DIR}/message.db`      |
```

## 10.キャッシュファイルの定義
```
| **キャッシュファイル名**   | **説明**                                            | **保存先**                   |
|----------------------------|-----------------------------------------------------|------------------------------|
| **openwrt.ch**     | OpenWrtバージョンキャッシュ。                        | `${BASE_DIR}/country.ch`  |
| **country.ch**          | 選択されたカントリーのキャッシュ。                    | `${BASE_DIR}/openwrt.ch` |
| **downloader.ch**          | パッケージマネージャー（apk / opkg）の判定キャッシュ。 | `${BASE_DIR}/downloader.ch` |
| **script.ch**      | スクリプトファイルバージョンのキャッシュ               | `${BASE_DIR}/script.ch` |
```

## 11. 方針
- 関数はむやみに増やさず、コモン関数は可能な限り汎用的とし、役割に応じ階層的関数を別途用意する。
- 関数名の変更は、要件定義のアップデートと全スクリプトへの反映を伴う事を最大限留意する。
- 新規関数追加時も要件定義への追加が必須。
- 要件定義に対し不明また矛盾点は、すみやかに報告、連絡、相談、指摘する。

