#!/bin/sh
# aios.sh (エントリースクリプト)
# License: CC0
AIOS_VERSION="2025.02.15-5"
echo -e "\033[7;40maios.sh Updated to version $AIOS_VERSION \033[0m"

DEBUG_MODE=false
INPUT_LANG="${1:-}"

# ✅ `common.sh` をダウンロード
download_common() {
    download_script common.sh || {
        echo "❌ Failed to download common.sh"
        exit 1
    }
    . "${BASE_DIR}/common.sh" || {
        echo "❌ Failed to load common.sh"
        exit 1
    }
}

# ✅ `aios` を `/usr/bin/aios` に配置
install_aios() {
    local aios_path="/usr/bin/aios"
    local script_path="${BASE_DIR}/aios"

    cp "$script_path" "$aios_path"
    chmod +x "$aios_path"

    if [ -f "$aios_path" ] && [ -x "$aios_path" ]; then
        echo "✅ aios installed successfully at $aios_path"
    else
        echo "❌ Failed to install aios. Check permissions."
    fi
}

# ✅ `packages.db` からパッケージを読み込んでインストール
install_from_db() {
    local db_file="${BASE_DIR}/packages.db"

    # ✅ `packages.db` が存在しない場合はスキップ
    if [ ! -f "$db_file" ]; then
        echo "❌ packages.db not found. Skipping package installation."
        return
    fi

    # ✅ `packages.db` のリストを取得し、インストール確認
    while IFS= read -r package_name; do
        if confirm "MSG_INSTALL_PROMPT_PKG" "$package_name"; then
            echo "Installing $package_name..."
            install_packages "$package_name" || {
                echo "❌ Failed to install $package_name."
                exit 1
            }

            # ✅ 言語パックもインストール
            install_language_pack "$package_name"
        else
            echo "Skipping $package_name installation."
        fi
    done < "$db_file"

    echo "✅ All requested packages have been processed!"
}

# ✅ `aios` の初期化関数
delete_aios() {
    rm -rf "${BASE_DIR}" /usr/bin/aios
    echo "Initialized aios"
}

# ✅ `aios` のディレクトリ作成
mkdir_aios() {
    mkdir -p "$BASE_DIR"
}

# ✅ `common.sh` のダウンロードを実行
download_common

# ✅ `パッケージマネージャー` を確認
get_package_manager

# ✅ `aios` コマンドのセットアップ
install_aios

# ✅ `packages.db` に基づいてパッケージをインストール
install_from_db

# ✅ `check_common()` を実行
check_common "$INPUT_LANG"
