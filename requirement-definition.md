# 要件定義 (AIOS - All in One Script)
**Last update:** 2025-02-06-6

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

## 4. 定数と環境変数の設定

**コモンファイル (`common.sh`) 内の基本定数:**

```sh
#!/bin/sh
# License: CC0
# OpenWrt >= 19.07

COMMON_VERSION="2025.02.05"
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

AIOS_VERSION="2025.02.05"
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

## 10.キャッシュファイルの定義
```
# キャッシュファイル定義

| キャッシュファイル名  | 説明                                           | 保存先                      |
|----------------------|--------------------------------|--------------------------|
| **openwrt.ch**      | OpenWrtバージョンのキャッシュ            | `${BASE_DIR}/openwrt.ch` |
| **country.ch**      | 選択されたカントリーのキャッシュ         | `${BASE_DIR}/country.ch` |
| **downloader.ch**   | パッケージマネージャー（apk / opkg）の判定キャッシュ | `${BASE_DIR}/downloader.ch` |
| **script.ch**       | スクリプトファイルバージョンのキャッシュ | `${BASE_DIR}/script.ch` |
```

## 11. 方針
- 関数はむやみに増やさず、コモン関数は可能な限り汎用的とし、役割に応じ階層的関数を別途用意する。
- 関数名の変更は、要件定義のアップデートと全スクリプトへの反映を伴う事を最大限留意する。
- 新規関数追加時も要件定義への追加が必須。
- 要件定義に対し不明また矛盾点は、すみやかに報告、連絡、相談、指摘する。

  ## 言語キャッシュの管理 (`language.ch` の導入)

### **1. 言語キャッシュ (`language.ch`) の新設**
- `language.ch` には、**スクリプトが参照する言語情報のみ** を保存する (`ja`, `en` など)。
- `country.ch` には、**選択した国情報** (`Japan 日本語 ja JP JST-9`) を保存し、言語コードも含めるが、スクリプトの言語参照には使わない。

### **2. `check_language()` の新設**
- `check_language()` では、**言語キャッシュ (`language.ch`) の存在を確認し、適切にセットする処理を行う。**
- `message.db` にその言語が存在しない場合でも、**`language.ch` には書き込まず、スクリプト内の変数 (`SELECTED_LANGUAGE`) で一時的に`en`を代用する。**

```sh
#########################################################################
# check_language: 言語キャッシュの確認および設定
# - `language.ch` に言語があるか確認し、無ければ `check_country()` を参照
# - `message.db` にその言語があるか確認し、無ければスクリプト内で `en` を代用
#########################################################################
check_language() {
    local language_cache="${BASE_DIR}/language.ch"
    local country_cache="${BASE_DIR}/country.ch"

    # 言語キャッシュがある場合はそれを使用
    if [ -f "$language_cache" ]; then
        SELECTED_LANGUAGE=$(cat "$language_cache")
        echo "$(color green "Using cached language: $SELECTED_LANGUAGE")"
    else
        # `country.ch` から言語コードを取得し、`language.ch` に保存
        if [ -f "$country_cache" ]; then
            SELECTED_LANGUAGE=$(awk '{print $3}' "$country_cache")
            echo "$SELECTED_LANGUAGE" > "$language_cache"
            echo "$(color green "Language set from country.ch: $SELECTED_LANGUAGE")"
        else
            SELECTED_LANGUAGE="en"
            echo "$SELECTED_LANGUAGE" > "$language_cache"
            echo "$(color yellow "No language found. Defaulting to 'en'.")"
        fi
    fi
}
```

### **3. `normalize_country()` の修正**
- `normalize_country()` は `language.ch` を変更しない。
- `message.db` に言語があるかどうかを確認し、無ければスクリプト変数 (`SELECTED_LANGUAGE`) に `en` を設定するだけ。

```sh
#########################################################################
# normalize_country: `message.db` に対応する言語があるか確認し、セット
# - `message.db` に `$SELECTED_LANGUAGE` があればそのまま使用
# - 無ければ **スクリプト内の `SELECTED_LANGUAGE` のみ** `en` にする（`language.ch` は変更しない）
#########################################################################
normalize_country() {
    local message_db="${BASE_DIR}/messages.db"
    local language_cache="${BASE_DIR}/language.ch"

    # `language.ch` から言語コードを取得
    if [ -f "$language_cache" ]; then
        SELECTED_LANGUAGE=$(cat "$language_cache")
        echo "DEBUG: Loaded language from language.ch -> $SELECTED_LANGUAGE"
    else
        SELECTED_LANGUAGE="en"
        echo "DEBUG: No language.ch found, defaulting to 'en'"
    fi

    # `message.db` に `SELECTED_LANGUAGE` があるか確認
    if grep -q "^$SELECTED_LANGUAGE|" "$message_db"; then
        echo "$(color green "Using message database language: $SELECTED_LANGUAGE")"
    else
        SELECTED_LANGUAGE="en"
        echo "$(color yellow "Language not found in messages.db. Using: en")"
    fi

    echo "DEBUG: Final language after normalization -> $SELECTED_LANGUAGE"
}
```

### **4. `check_country()` の修正**
- `check_country()` で `country.ch` を確認し、**選択した言語を `language.ch` にも保存**

```sh
#########################################################################
# check_country: 国情報の確認および設定
# - `country.ch` を参照し、無ければ `select_country()` で選択
# - 選択した言語を **`language.ch` にも保存**
#########################################################################
check_country() {
    local country_cache="${BASE_DIR}/country.ch"

    # `country.ch` が存在する場合
    if [ -f "$country_cache" ]; then
        echo "$(color green "Using cached country information.")"
        return
    fi

    # `select_country()` を実行して新しい `country.ch` を作成
    select_country

    # `country.ch` の言語を `language.ch` にも保存
    if [ -f "$country_cache" ]; then
        local lang_code=$(awk '{print $3}' "$country_cache")
        echo "$lang_code" > "${BASE_DIR}/language.ch"
        echo "$(color green "Language saved to language.ch: $lang_code")"
    fi
}
```

### **5. `check_common()` の修正**

```sh
#########################################################################
# check_common: 初期化処理
# - `full` モードでは `message.db` などをダウンロード
# - `light` モードでは最低限のチェックのみ
#########################################################################
check_common() {
    local mode="$1"
    shift

    case "$mode" in
        full)
            download_script messages.db
            download_script country.db
            download_script openwrt.db
            check_openwrt
            check_country
            check_language
            normalize_country  
            ;;
        light)
            check_openwrt
            check_country
            check_language
            normalize_country  
            ;;
        *)
            check_openwrt
            check_country
            check_language
            normalize_country  
            ;;
    esac
}
```

### **最終的な改善点まとめ**
✅ `language.ch` を新設し、**スクリプトの言語選択用** に使用。  
✅ `check_language()` を新設し、言語キャッシュの管理を専用化。  
✅ `normalize_country()` では `language.ch` を **変更せず**、スクリプト内で `en` にフォールバック。  
✅ `check_country()` で `country.ch` を確認し、**選択した言語を `language.ch` にも保存**。  

これにより、言語の処理が明確化され、`ja` を選択したのに `en` になる問題が解決される。

