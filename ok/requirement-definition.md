# AIOS 設計方針と要件定義  
**Last Update: 2025-02-15 14:06:00 (JST) 🚀**  
*"Precision in code, clarity in purpose. Every update refines the path."*  

---

## **⚠️ ChatGPT への追加ルール（最優先ルール）**  

### 🚨 **ChatGPT は以下のルールを厳守すること：**  

1. **AIOS に関わるすべてのスクリプトに適用すること。**
   - `common.sh`、`aios.sh`、各 `.db`、`.ch` など **すべてのスクリプトに対して適用** される。
   - 特定のスクリプトに依存せず、全体の整合性を確保すること。

2. **スクリプトに関する対応は OpenWrt に特化し、`ash` シェルで記述すること。**
   - `bash` は使用禁止 (`ash` で動作しないことがあるため)。
   - 記述の統一性を維持し、環境依存の記述を避けること。

3. **ユーザーがアップロードした最新のファイルを常に参照し、それを唯一の正とすること。**
   - `aios.sh`、`common.sh`、各 `.db` や `.ch` を含む **すべてのスクリプトを確認** すること。
   - **コードの変更・提案時には、必ず最新の要件を確認し、一貫性を確保すること。**
   - **アップロードされたファイルが最新かどうか `Last Update` を確認すること。**
   - **ただし、関数の上部に記載された `###` 内の要件が、より新しい日付・バージョンであれば、それを優先すること。**

4. **関数の追加・削除・変更を行う場合、必ずユーザーに通知し、承認を得ること。**
   - **関数の追加時:** `requirement-definition.md` に明記し、構造の変更点を記述すること。
   - **関数の削除時:** 影響範囲を明示し、代替手段があることを確認すること。
   - **関数の変更時:** 変更箇所の意図と影響範囲をユーザーに説明し、承認を得ること。

5. **スクリプトの全文変更時、必ず `Canmore` に書き出し、ユーザーと協議のうえ適用すること。**
   - 一部の関数のみ変更する場合も、`Canmore` を活用し、ユーザーとリアルタイムに調整すること。

6. **スクリプトを変更・更新する際は、必ず `Last Update` の日付を確認し、最新版であることを保証すること。**
   - 変更前に **`Last Update` の日時が最新かを必ずチェックすること。**
   - **関数の `###` 内の要件がスクリプトの `Last Update` より新しい場合は、関数の要件を優先すること。**
   - 古いバージョンのまま作業しないこと。

7. **要件に疑義が生じた場合、勝手に推測せず、必ずユーザーに確認を取ること。**
   - 不明点がある場合、決して独自の解釈を加えず、ユーザーに質問すること。
   - **「一見正しいが、過去の会話と矛盾する」場合は、最優先でユーザーに確認すること。**

8. **要件定義とスクリプトの仕様が矛盾する場合、要件定義を最優先し、ユーザーに報告すること。**
   - AIOS の全体構成 (`aios.sh`、`message.db`、`country.db` など) との整合性をチェックすること。
   - 矛盾が発生した場合、修正の提案を行い、ユーザーの承認を得ること。

---

##### **📌 `Last Update` 確認例**
✅ **スクリプトを変更する前に、最新の `Last Update` を確認すること**  
✅ **関数の `###` 内の要件が `Last Update` より新しい場合は、関数の要件を最優先すること**  
❌ **古い `Last Update` で作業しないこと**  

**例:**  
```sh
#########################################################################
# Last Update: 2025-02-12 14:35:26 (JST) 🚀
# "Precision in code, clarity in purpose. Every update refines the path."
#########################################################################

### sample_function
#########################################################################
# Last Update: 2025-02-13 10:15:42 (JST) 🚀
# "Functionality evolves, clarity remains. Keep refining."
#
# 【要件】
# 1. この関数は、特定の処理を行うために作られたもの。
# 2. この関数が最新の場合、スクリプト全体の `Last Update` よりもこの要件を優先すること。
# 3. 変更時には、影響範囲を精査し、依存関係を確認すること。
#########################################################################
sample_function() {
    echo "This is a sample function."
}
```

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

## 3. エントリー方法

### キャッシュフリー
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; sh /usr/bin/aios
```
### 日本語
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; sh /usr/bin/aios 日本語
```
### English
```sh
wget -q -O /usr/bin/aios "https://raw.githubusercontent.com/site-u2023/aios/main/aios?cache_bust=$(date +%s)"; sh /usr/bin/aios English
```

## 4. スクリプト構成

```
aios.sh                           ← 初回エントリーポイント  <<< 廃止（2025年2月16日19:36）
  └── aios(/usr/bin)              ← メインエントリーポイント
    ├── common.sh                 ← 共通関数
    ├── country.db                ← 国名、言語、短縮国名、ゾーンネーム、タイムゾーンデータベース
    ├── message.db                ← 多言語データベース
    ├── openwrt.db                ← OpenWrバージョンデータベース
    ├── package.db                ← パッケージデータベース   
    ├── country.ch                ← カントリーコードキャッシュ
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

## 5. 定数と環境変数の設定

**コモンファイル (`common.sh`) 内の基本定数:**

```sh
#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important!　OpenWrt OS only works with Almquist Shell, not Bourne-again shell.

COMMON_VERSION="2025.02.05"
echo "comon Last update: $COMMON_VERSION"

# 基本定数の設定
# BASE_WGET="${BASE_WGET:-wget -O}" # テスト用
BASE_WGET="${BASE_WGET:-"wget --quiet -O}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/site-u2023/aios/main}"
BASE_DIR="${BASE_DIR:-/tmp/aios}"
CACHE_DIR="${CACHE_DIR:-${BASE_DIR}/cache}"; mkdir -p "$CACHE_DIR"
LOG_DIR="${LOG_DIR:-${BASE_DIR}/logs}"; mkdir -p "$LOG_DIR"
SUPPORTED_VERSIONS="${SUPPORTED_VERSIONS:-19 21 22 23 24 SN}"
SUPPORTED_LANGUAGES="${SUPPORTED_LANGUAGES:-en}"
```

**各スクリプト内の定数設定（個別に異なる場合あり）:**

```sh
#!/bin/sh
# License: CC0
# OpenWrt >= 19.07, Compatible with 24.10.0
# Important!　OpenWrt OS only works with Almquist Shell, not Bourne-again shell.

AIOS_VERSION="2025.02.05"
echo "aios Last update: $AIOS_VERSION"

# BASE_WGET="wget -O"
BASE_WGET="wget --quiet -O"
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"
CASHE_DIR="${BASE_DIR}/cache"; mkdir -p "$CACHE_DIR"
LOG_DIR="${BASE_DIR}/logs"; mkdir -p "$LOG_DIR"
SUPPORTED_VERSIONS="19 21 22 23 24 SN"  # ファイルごとに異なる可能性あり
SUPPORTED_LANGUAGES="en ja zh-cn zh-tw id ko de ru"  # ファイルごとに異なる可能性あり
INPUT_LANG="$1"
```

---

## 6. スクリプト動作要件

- **各スクリプトは、AIOS メニューからの利用と単独実行（コモンファイルは利用）の両方をサポート。**
- **カントリー、バージョン、ダウンローダのチェックは常に `common.sh` で共通化。**
- **~~個別の echo メッセージはスクリプト単位で管理~~、共通の echo はデータベースで管理。**
- **言語対応は LuCI パッケージ全言語を考慮。言語DB分のみ対応し、未翻訳言語はデフォルトで `en` を使用。**

---

## 7. 各スクリプトの役割

~~### **`aios.sh`:**~~
- 初回設定用。最小限の依存関係で実行し、バージョンチェックを行う迄（`common.sh` を使用しない）。  
- `$1` で言語をチェック。指定がない場合はデータベースからカントリーを選択、もしくはキャッシュを利用（DBから完全一致後、曖昧検索で判定）。  
- カントリー決定後、キャッシュに保存。
- 
  
### **`aios` (メインスクリプト):**  
- スクリプト群のダウンロードと実行を担当。リンクファイルはファイルバージョンチェックで常に最新をダウンロード（バージョンミスマッチでも続行）。  
- スクリプトファイルバージョンチェック、カントリーチェック、OpenWrtバージョンチェック、ダウンローダーチェック（`opkg` と `apk` ）後、キャッシュに保存。
- aios.shの機能を引き継ぐ

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

## 8. 命名規則
関数名は機能ごとにプレフィックスを付け、役割を明確にします。

```
- `check_`: 状態確認系の関数（例: `check_version_common`, `check_language_common`）
- `download_`: ファイルダウンロード系の関数（例: `download_common_functions`, `download_country_zone`）
- `handle_`: エラー処理および制御系の関数（例: `handle_error`, `handle_exit`）
- `configure_`: 設定変更系の関数（例: `configure_ttyd`, `configure_network`）
- `print_`: 表示・出力系の関数（例: `print_banner`, `print_help`, `print_colored_message`）
```



## 9. 関数一覧

### ディレクトリ定義

```
BASE_DIR="/tmp/aios"
CACHE_DIR="${BASE_DIR}/cache"
LOG_DIR="${BASE_DIR}/logs"
mkdir -p "$CACHE_DIR" "$LOG_DIR"
```

### 共通関数: common.sh

```
| **関数名**         | **説明**                                                                 | **呼び出し元スクリプト**             |
|--------------------|--------------------------------------------------------------------------|--------------------------------------|
| **color**          | カラーコードを使用してメッセージを表示します。                           | 全スクリプト
| **color_code_map**          | カラーコードを使用してメッセージを表示します。                  | 全スクリプト
| **handle_error**   | エラーメッセージを表示し、スクリプトを終了します。                       | 全スクリプト                         |
| **download_script**        | 指定されたスクリプト・データベースのバージョン確認とダウンロード                        | 全スクリプト                         |

| **check_openwrt**  | OpenWrtのバージョンを確認し、サポートされているか検証します。            | `aios.sh` , 他全て                   |
| **check_country**  | 指定された言語がサポートされているか確認し、デフォルト言語を設定します。 | `aios.sh` , 他全て                   |
| **normalize_country**  |言語コードがサポート対象か検証し、サポート外なら `en` に変更 | `aios.sh` , 他全て                   |
| **download_common**| `common.sh` をダウンロードし、読み込みます。                             | `aios.sh`, 他全て                    |
| **download_country**| `country.sh` をダウンロードし、読み込みます。                           | `aios.sh`, `system-config.sh`        |
| **handle_exit**    | 正常終了時の処理を行います。                                             | 全スクリプト                         |
| **download_openwrt.db**        | バージョンデータベースのダウンロード                      | 全スクリプト                         |
| **check_openwrt**        | バージョン確認とパッケージマネージャーの取得関数                      | 全スクリプト                         |
| **check_country**        | 言語キャッシュの確認および設定                        | 全スクリプト                         |
| **openwrt_db**        | バージョンデータベースのダウンロード                       | 全スクリプト                         |
| **messages_db**        | 選択された言語のメッセージファイルをダウンロード                     | 全スクリプト                         |
| **packages_db**        | 選択されたパッケージファイルをダウンロード                    | 全スクリプト                         |
| **confirm**        | ファイルの存在確認と自動ダウンロード（警告対応）                        | 全スクリプト                         |
| **download**        | ファイルの存在確認と自動ダウンロード（警告対応）                        | 全スクリプト                         |
| **select_country**        | 国とタイムゾーンの選択                      | 全スクリプト                         |
| **country_info**        | 選択された国と言語の詳細情報を表示                      | 全スクリプト                         |
| **get_package_manager**        | パッケージマネージャー判定関数（apk / opkg 対応）                     | 全スクリプト                         |
| **get_message**        | 多言語対応メッセージ取得関数                 | 全スクリプト                         |
| **handle_exit**        | exit                         | 全スクリプト                         |
| **install_packages**        | パッケージをインストールし、言語パックも適用                       | 全スクリプト                         |
| **attempt_package_install**        | 個別パッケージのインストールおよび言語パック適用                    | 全スクリプト                         |
| **install_language_pack**        | 言語パッケージの存在確認とインストール                 | 全スクリプト                         |
| **check_common**        | 初期化処理                           | 全スクリプト                         |
| **update_country_cache**        |                          | 全スクリプト                         |
```

### ローカル関数

#### ローカル共通

```
| **関数名**         | **説明**                                                                 | **呼び出し元スクリプト**             |
|--------------------|--------------------------------------------------------------------------|--------------------------------------|
| **make_directory**        | 必要なディレクトリ (BASE_DIR) を作成する # 必要に応じて                         | 全スクリプト                         |
| **download_common**        | 共通ファイルのダウンロードと読み込み                           | 全スクリプト                         |
| **packages**        | 共通ファイルのダウンロードと読み込み # 必要に応じて                          | 全スクリプト                         |
```

#### aios.sh

```
| **関数名**         | **説明**                                                                 | **呼び出し元スクリプト**             |
|--------------------|--------------------------------------------------------------------------|--------------------------------------|
| **delete_aios**        | 既存の aios 関連ファイルおよびディレクトリを削除して初期化する                           | aios.sh                    |
| **make_directory**        |                        | aios.sh                    |
| **download_common**        |                       | aios.sh                    |
| **check_common full**        |                      | aios.sh                    | 
| **packages**        |                       | aios.sh                    | 
| **download_file aios**        |                        | aios.sh                    | 
```

#### aios

```
| **関数名**         | **説明**                                                                 | **呼び出し元スクリプト**             |
|--------------------|--------------------------------------------------------------------------|--------------------------------------|
| **make_directory**   |                                       | `aios.sh`,      |　
| **download_common**   |                                          | `aios.sh`,      |　
| **print_banner**   | 多言語対応のバナーを表示します。                                         | `aios.sh`,      |　
| **packages**   |                                         | `aios.sh`,      |　
| **download_script openwrt-config.sh**   |                                          | `aios.sh`,      |　
```

#### openwrt-config.sh

```
| **関数名**         | **説明**                                                                 | **呼び出し元スクリプト**             |
|--------------------|--------------------------------------------------------------------------|--------------------------------------|
| **handle_exit**        | ファイルの存在確認と自動ダウンロード（警告対応）                        | openwrt-config.sh                 |※common.shからローカルに移行予定
```

## 9. データベースの定義

```
| **データベース名**          | **形式**                                            | **保存先**                   |
|----------------------------|-----------------------------------------------------|------------------------------|
| **country.db **            | Russia Русский ru RU Europe/Moscow,Asia/Krasnoyarsk,Asia/Yekaterinburg,Asia/Irkutsk,Asia/Vladivostok;MSK-3,SAMT-4,YEKT-5,OMST-6,KRAT-7,IRKT-8,YAKT-9,VLAT-10,MAGT-11 |  `${BASE_DIR}/country.db`  |
| **message.db**             | ja|MSG_INSTALL_PROMPT_PKG={pkg}                     | ${BASE_DIR}/message.db`      |
| **openwrt.db**             | 24.10.0=opkg|stable                                 | ${BASE_DIR}/openwrt.db`      |
| **package.db**             | [ttyd]                                | ${BASE_DIR}/package.db`      |
```

### キャッシュファイルの定義

```plaintext
| キャッシュファイル名      | 説明                                                   | 保存先                       |
|----------------------|--------------------------------------------------|--------------------------|
| **openwrt.ch**      | OpenWrtバージョンのキャッシュ （OpenWrtバージョン）※削除しない | `${CACHE_DIR}/openwrt.ch` |
| **language.ch**     | 最終選択した短縮国名（短縮国名：country.dbの$5） ※削除しない | `${CACHE_DIR}/language.ch` |
| **luci.ch**         | LUI 言語キャッシュ (luci言語：country.dbの$4)※削除しない | `${CACHE_DIR}/luci.ch` |
| **country.ch**      | 選択されたカントリーのキャッシュ（国名、母国語、言語パッケージ、短縮国名、ゾーンネーム、タイムゾーン:country.dbの該当行$の全て）※削除しない | `${CACHE_DIR}/country.ch` |
| **zone.ch**         | 最終選択したゾーン (ゾーンネーム、タイムゾーン：country.dbの$6～全て) ※削除しない | `${CACHE_DIR}/zone.ch` |
| **downloader.ch**   | パッケージマネージャー（apk、opkg）※削除しない | `${CACHE_DIR}/downloader.ch` |
| **script.ch**       | スクリプトファイルバージョンのキャッシュ ※削除しない | `${CACHE_DIR}/script.ch` |
| **country_tmp.ch**  | 検索時の一時国リスト（スクリプト終了時削除） | `${CACHE_DIR}/country_tmp.ch` |
| **zone_tmp.ch**     | 検索時の一時ゾーンリスト（スクリプト終了時削除） | `${CACHE_DIR}/zone_tmp.ch` |
| **language_tmp.ch** | 言語キャッシュ（スクリプト終了時削除） | `${CACHE_DIR}/language_tmp.ch` |
| **code_tmp.ch**     | 国コードキャッシュ（スクリプト終了時削除） | `${CACHE_DIR}/code_tmp.ch` |
```

### ログディレクトリの定義
```
| **ログ名**          | **用途**                        | **保存先**                     |
|----------------------------|--------------------------------|------------------------------|
| **debug.log**       | デバッグ情報を保存              | `${LOG_DIR}/debug.log`  |
```

## 10. 方針
- 関数はむやみに増やさず、コモン関数は可能な限り汎用的とし、役割に応じ階層的関数を別途用意する。
- 関数名の変更は、要件定義のアップデートと全スクリプトへの反映を伴う事を最大限留意する。
- 新規関数追加時も要件定義への追加が必須。
- 要件定義に対し不明また矛盾点は、すみやかに報告、連絡、相談、指摘する。

## 11.検索エンジン

### 具体的な動作フロー

検索ワードを入力

何でも受け付ける（例: tokyo, asia, 日, us, en, JP, america など）
/, ,, _ を除外して処理
大文字・小文字を区別せずに処理
検索の流れ

完全一致検索（最優先で処理）
前方一致検索
後方一致検索
部分一致検索
すべてのフィールドを対象に検索
結果がない場合は、再入力を促す
検索結果が多すぎる場合は、上限数を設定して通知
検索結果の表示

[1] [2] という 番号付きリスト形式
1件しかなくても 番号付きで表示し、選択を統一
検索結果が大量 にある場合は「上限オーバー」として一部を表示
選択の流れ

ユーザーが [番号] を入力
[Y/n] で確認（番号選択→確認）
ヒットしたデータから country.ch, luci.ch（言語コード）, zone.ch（ゾーン情報） に保存
タイムゾーン検索

国選択後 に zone.ch を作成
国のデータから該当するタイムゾーンを抽出
同じ流れ（番号選択→確認） で設定
1件だけでもリスト形式で表示し統一
最終保存

country.ch に選択された国情報を保存
luci.ch に $4（言語コード）を保存
zone.ch に $6 以降（ゾーン情報）を保存

### 利点
どんな入力でも何かしらヒットする
ヒットしたものを統一フォーマットで表示
一貫性のある操作性（番号選択→YN確認）
バグを減らし、メンテナンスが容易
ユーザーの誤入力にも対応しやすい

### 実装方針

#### 検索の流れ

```
1. 完全一致検索（最優先）
2. 前方一致検索
3. 後方一致検索
4. 部分一致検索（全フィールド対象）
5. 類似検索（オプション）
```

- 番号選択・Y/n で決定
- 1件だけのヒットでも必ず確認
- 「キャンセル/戻る/履歴から選択」オプション追加
- ヒット数が多い場合は、スクロール or 「more」で追加表示

#### 入力の正規化
/, ,, _, . などの記号をスペースに統一
ひらがな → カタカナ, 全角 → 半角, 小文字 → 大文字
JP = Japan = Nihon （統一リストで対応）
US = United_States （揺れを吸収）
typo補正（Japn → Japan）（できる範囲で）

#### インタラクティブなUI
リアルタイムフィルタ（入力するごとに検索）
検索結果が多すぎる場合の対応
最大 10 件表示（「more」で続きを表示）
「条件を追加してください（例: 'japan tokyo'）」
フィールド（国名 / 言語 / タイムゾーン）を指定可能
過去の履歴から選択
前回の選択を記憶
最も頻繁に使用された国・言語を上位表示

#### タイムゾーン検索
国を選んだらデフォルトのタイムゾーンを自動選択
複数のタイムゾーンがある場合はリスト選択
主要なゾーンと全ゾーンを分けて表示
「このタイムゾーンでOK？（Y/n）」を表示

#### 高速化
country.db のキャッシュ化
検索結果を一時保存し、次回検索を高速化
人気の検索結果を事前にロード
grep よりも awk を活用
awk なら「複数フィールドの部分一致」が可能
「前方・後方一致」も awk で処理
キャッシュディレクトリ /tmp/aios/cache/ の有効活用
検索結果を一時保存
タイムゾーン検索もキャッシュに入れる

---

## **📌 設計方針**  
### **1. 言語処理の一貫性**  
✅ `language.ch` はデバイス設定用として **一度書いたら変更しない**  
✅ `message.ch` はシステムメッセージ用として **フォールバック可能**  
✅ 言語の選択 (`select_country()`) → 言語の確定 (`normalize_country()`) → メッセージ取得 (`get_message()`) の **流れを厳守**

### **2. フォールバック処理の限定**  
✅ `normalize_country()` **以外では言語フォールバックを行わない**  
✅ `get_message()` は `message.ch` を最優先し、`language.ch` には影響を与えない  
✅ `message.ch` が無い場合のみ、システムメッセージのデフォルト (`en`) を使用  

### **3. 言語処理の分離**  
✅ `language.ch` (デバイス設定) と `message.ch` (メッセージ言語) は完全に分離  
✅ `normalize_country()` でのみ `message.ch` を設定し、他の関数は `message.ch` を参照する  

### **4. キャッシュ管理の統一**  
✅ `select_country()` は **キャッシュ (`language.ch`) の存在を最優先で確認** し、変更しない  
✅ `normalize_country()` は `message.ch` を管理し、フォールバック適用  
✅ `get_message()` は `message.ch` のみを参照し、`language.ch` には影響を与えない  

# **install_package: パッケージインストール関数 (OpenWrt / Alpine Linux)**

## **📌 概要**
この関数は OpenWrt (opkg) / Alpine Linux (apk) のパッケージをインストールし、  
オプションに応じて言語パック適用や `package.db` の設定適用を行う。  
また、システムのパッケージリストを更新する機能 (`update`) もサポート。

---

## **🚀 フロー**
1. `install_package update` を実行すると `opkg update` または `apk update` を実行
2. デバイスにパッケージがインストール済みか確認
3. パッケージがリポジトリに存在するか確認
4. インストール確認 (`yn` オプションが指定された場合)
5. パッケージをインストール
6. 言語パッケージの適用 (`dont` オプションがない場合)
7. `package.db` の設定適用 (`notset` オプションがない場合)
8. 設定の有効化 (デフォルト `enabled`、`disabled` オプションで無効化)

---

## **⚙️ オプション**
| オプション  | 説明 | デフォルト動作 |
|------------|----------------------------------------|----------------|
| `yn`       | インストール前に確認を求める          | **確認なし**  |
| `dont`     | 言語パッケージの適用をスキップ        | **適用する**  |
| `notset`   | `package.db` の適用をスキップ         | **適用する**  |
| `disabled` | 設定を `disabled` にする              | **enabled**  |
| `update`   | `opkg update` または `apk update` を実行 | **他では実行しない** |

---

## **📌 仕様**
- `downloader_ch` から `opkg` または `apk` を取得し、適切なパッケージ管理ツールを使用する。
- `messages.db` を参照し、すべてのメッセージを取得 (`JP/US` の言語対応)。
- `package.db` の設定がある場合、`uci set` を実行して適用 (`notset` オプションでスキップ可能)。
- 言語パッケージは `luci-app-xxx` 形式を対象に適用 (`dont` オプションでスキップ可能)。
- 設定の有効化は **デフォルト `enabled`**、`disabled` オプション指定時のみ `disabled` にする。
- `update` は **`install_package update` で明示的に実行** (パッケージインストール時には自動実行しない)。

---

## **🛠 使用例**
| コマンド | 説明 |
|---------|------|
| `install_package update` | パッケージリストを更新 |
| `install_package ttyd` | `ttyd` をインストール（確認なし、`package.db` 適用、言語パック適用） |
| `install_package ttyd yn` | `ttyd` をインストール（確認あり） |
| `install_package ttyd dont` | `ttyd` をインストール（言語パック適用なし） |
| `install_package ttyd notset` | `ttyd` をインストール（`package.db` の適用なし） |
| `install_package ttyd disabled` | `ttyd` をインストール（設定を `disabled` にする） |
| `install_package ttyd yn dont disabled` | `ttyd` をインストール（確認あり、言語パックなし、設定を `disabled` にする） |

---

## **📜 備考**
- **`update` を実行する場合、必ず `install_package update` を最初に記述すること。**
- **オプションは順不同で指定可能。**
- **すべての `echo` メッセージは `messages.db` から取得するため、国際化対応が可能。**




