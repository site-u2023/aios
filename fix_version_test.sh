#!/bin/sh
# /tmp/fix_version_test.sh

# 環境設定
GITHUB_TOKEN_FILE="/etc/aios_token"
DEBUG_MODE="true"
CACHE_DIR="/tmp/test_cache"
mkdir -p "$CACHE_DIR"

# カラー出力用関数
color() {
    local color_code=""
    case "$1" in
        "green") color_code="\033[1;32m" ;;
        *) color_code="\033[0m" ;;
    esac
    shift
    echo -e "${color_code}$*\033[0m"
}

# デバッグ出力
debug_log() {
    echo "[$1] $2"
}

# トークン取得関数
get_github_token() {
    if [ -f "$GITHUB_TOKEN_FILE" ] && [ -r "$GITHUB_TOKEN_FILE" ]; then
        token=$(cat "$GITHUB_TOKEN_FILE" | tr -d '\n\r')
        if [ -n "$token" ]; then
            echo "$token"
            return 0
        fi
    fi
    return 1
}

# 修正版get_commit_version関数
get_commit_version() {
    local file_path="$1"
    
    # リポジトリ情報を明示的に設定
    local repo_owner="site-u2023"
    local repo_name="aios"
    local api_url="repos/${repo_owner}/${repo_name}/commits?path=${file_path}&per_page=1"
    local commit_info=""
    local auth_method="direct"
    
    echo "Testing commit version for: $file_path"
    echo "API URL: $api_url"
    
    # トークンによるAPI認証
    local token=$(get_github_token)
    if [ -n "$token" ]; then
        echo "Using token authentication"
        commit_info=$(wget -qO- --header="Authorization: token $token" \
            "https://api.github.com/$api_url" 2>/dev/null)
        auth_method="token"
    else
        echo "Using standard authentication"
        commit_info=$(wget -qO- "https://api.github.com/$api_url" 2>/dev/null)
        auth_method="standard"
    fi
    
    if [ -n "$commit_info" ]; then
        echo "API response received (truncated):"
        echo "${commit_info:0:100}..."
        
        # より単純な方法でJSONから日付とSHAを抽出
        local commit_date=$(echo "$commit_info" | grep -o '"date": *"[^"]*"' | head -1 | sed 's/.*"date": *"\([^"]*\)".*/\1/')
        local commit_sha=$(echo "$commit_info" | grep -o '"sha": *"[^"]*"' | head -1 | sed 's/.*"sha": *"\([^"]*\)".*/\1/' | cut -c 1-7)
        
        echo "Extracted date: $commit_date"
        echo "Extracted SHA: $commit_sha"
        
        if [ -n "$commit_date" ] && [ -n "$commit_sha" ]; then
            # YYYY.MM.DD-SHA 形式に変換
            local formatted_date=$(echo "$commit_date" | sed 's/T.*Z//g;s/-/./g')
            echo "Formatted version: ${formatted_date}-${commit_sha}"
            # 改行を含まない単一の文字列として返す
            printf "%s %s" "${formatted_date}-${commit_sha}" "${auth_method}"
            return 0
        fi
        echo "Failed to extract commit info"
    else
        echo "No API response received"
    fi
    
    # API取得失敗時は現在時刻を使用
    printf "%s %s" "$(date +%Y.%m.%d)-unknown" "direct"
    return 1
}

# バージョン情報更新のテスト
test_version_update() {
    local file_name="test_file.sh"
    local remote_version="2025.03.10-abcdef1"
    local script_file="$CACHE_DIR/script.ch"
    
    echo "Testing version update..."
    
    # テストファイル作成
    if [ ! -f "$script_file" ]; then
        echo "Creating new script file"
        printf "%s=%s\n" "another_file.sh" "2025.03.09-123456" > "$script_file"
    fi
    
    echo "Current script file contents:"
    cat "$script_file"
    
    echo "Updating version information..."
    if grep -q "^${file_name}=" "$script_file"; then
        # エスケープ処理を改良
        escaped_file=$(echo "$file_name" | sed 's/[\/&]/\\&/g')
        escaped_version=$(echo "$remote_version" | sed 's/[\/&]/\\&/g')
        sed -i "s/^${escaped_file}=.*/${escaped_file}=${escaped_version}/" "$script_file"
    else
        printf "%s=%s\n" "${file_name}" "${remote_version}" >> "$script_file"
    fi
    
    echo "Updated script file contents:"
    cat "$script_file"
}

# テスト実行
echo "=== GitHub API Version Test ==="
result=$(get_commit_version "country.db")
echo "Function return value: $result"

echo ""
echo "=== Version Update Test ==="
test_version_update
echo "=== Test complete ==="
