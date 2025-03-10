#!/bin/sh

# POSIX準拠のAPI接続テストスクリプト
# 保存先: /tmp/github_api_test.sh

# デバッグフラグ
DEBUG=1

# カラー出力関数
color() {
    case "$1" in
        red) echo -e "\033[1;31m$2\033[0m" ;;
        green) echo -e "\033[1;32m$2\033[0m" ;;
        yellow) echo -e "\033[1;33m$2\033[0m" ;;
        blue) echo -e "\033[1;34m$2\033[0m" ;;
        *) echo "$2" ;;
    esac
}

# デバッグ関数
debug() {
    [ "$DEBUG" -eq 1 ] && echo "$(color blue "[DEBUG]") $1"
}

# 結果表示関数
report() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        SUCCESS) echo "$(color green "[成功]") $message" ;;
        PARTIAL) echo "$(color yellow "[一部成功]") $message" ;;
        FAILURE) echo "$(color red "[失敗]") $message" ;;
        INFO) echo "$(color blue "[情報]") $message" ;;
        *) echo "[$status] $message" ;;
    esac
}

# トークン読み取り
get_token() {
    local token_file="/etc/aios_token"
    if [ -f "$token_file" ] && [ -r "$token_file" ]; then
        cat "$token_file" | tr -d '\n\r'
    else
        echo ""
    fi
}

# ネットワーク基本接続テスト
test_network_basic() {
    report INFO "基本ネットワーク接続テスト中..."
    
    # DNS解決テスト
    if nslookup api.github.com >/dev/null 2>&1; then
        report SUCCESS "DNS解決: api.github.com を解決できました"
    else
        report FAILURE "DNS解決: api.github.com を解決できません"
    fi
    
    # Pingテスト (可能であれば)
    if ping -c 1 -W 2 api.github.com >/dev/null 2>&1; then
        report SUCCESS "Ping: api.github.com に到達可能です"
    else
        report PARTIAL "Ping: api.github.com に到達できません (ファイアウォールで制限されている可能性あり)"
    fi
    
    # HTTPSテスト (wget でルート証明書チェック)
    if wget -q --spider https://api.github.com 2>/dev/null; then
        report SUCCESS "HTTPS: api.github.com へHTTPS接続可能です"
    else
        report FAILURE "HTTPS: api.github.com へHTTPS接続できません"
    fi
}

# API レート制限テスト (認証なし)
test_api_rate_limit_no_auth() {
    report INFO "API制限テスト (認証なし) 実行中..."
    
    local result=$(wget -qO- "https://api.github.com/rate_limit" 2>/dev/null)
    
    if [ -n "$result" ]; then
        local remaining=$(echo "$result" | sed -n 's/.*"remaining":\([0-9]*\).*/\1/p' | head -1)
        local limit=$(echo "$result" | sed -n 's/.*"limit":\([0-9]*\).*/\1/p' | head -1)
        
        if [ -n "$remaining" ] && [ -n "$limit" ]; then
            report SUCCESS "API制限 (認証なし): 残り $remaining/$limit リクエスト"
            return 0
        fi
    fi
    
    report FAILURE "API制限の取得に失敗しました (認証なし)"
    debug "レスポンス: ${result:0:100}..."
    return 1
}

# API レート制限テスト (トークン認証)
test_api_rate_limit_with_auth() {
    report INFO "API制限テスト (認証あり) 実行中..."
    
    local token=$(get_token)
    if [ -z "$token" ]; then
        report FAILURE "トークンが見つかりません。テストをスキップします。"
        return 1
    fi
    
    local result=$(wget -qO- --header="Authorization: token $token" "https://api.github.com/rate_limit" 2>/dev/null)
    
    if [ -n "$result" ]; then
        local remaining=$(echo "$result" | sed -n 's/.*"remaining":\([0-9]*\).*/\1/p' | head -1)
        local limit=$(echo "$result" | sed -n 's/.*"limit":\([0-9]*\).*/\1/p' | head -1)
        
        if [ -n "$remaining" ] && [ -n "$limit" ]; then
            report SUCCESS "API制限 (認証あり): 残り $remaining/$limit リクエスト"
            return 0
        fi
    fi
    
    report FAILURE "API制限の取得に失敗しました (認証あり)"
    debug "レスポンス: ${result:0:100}..."
    return 1
}

# リポジトリ情報テスト
test_repo_info() {
    report INFO "リポジトリ情報テスト実行中..."
    
    local repo="site-u2023/aios"
    local token=$(get_token)
    local auth_header=""
    [ -n "$token" ] && auth_header="--header=\"Authorization: token $token\""
    
    local cmd="wget -qO- $auth_header \"https://api.github.com/repos/$repo\""
    debug "実行コマンド: $cmd"
    
    local result=$(eval $cmd 2>/dev/null)
    
    if [ -n "$result" ]; then
        local name=$(echo "$result" | sed -n 's/.*"name":\s*"\([^"]*\)".*/\1/p' | head -1)
        local default_branch=$(echo "$result" | sed -n 's/.*"default_branch":\s*"\([^"]*\)".*/\1/p' | head -1)
        
        if [ -n "$name" ] && [ -n "$default_branch" ]; then
            report SUCCESS "リポジトリ情報: 名前=$name, デフォルトブランチ=$default_branch"
            return 0
        fi
    fi
    
    report FAILURE "リポジトリ情報の取得に失敗しました"
    debug "レスポンス: ${result:0:100}..."
    return 1
}

# コンテンツ検証テスト
test_contents() {
    report INFO "リポジトリコンテンツテスト実行中..."
    
    local repo="site-u2023/aios"
    local token=$(get_token)
    local auth_header=""
    [ -n "$token" ] && auth_header="--header=\"Authorization: token $token\""
    
    local cmd="wget -qO- $auth_header \"https://api.github.com/repos/$repo/contents\""
    debug "実行コマンド: $cmd"
    
    local result=$(eval $cmd 2>/dev/null)
    
    if [ -n "$result" ]; then
        # ファイル数をカウント (オブジェクト数をカウント)
        local file_count=$(echo "$result" | grep -o '"name"' | wc -l)
        
        if [ "$file_count" -gt 0 ]; then
            report SUCCESS "リポジトリコンテンツ: $file_count 個のファイルを検出"
            # 最初の5つのファイル名を表示
            echo "$result" | sed -n 's/.*"name":\s*"\([^"]*\)".*/\1/p' | head -5 | \
                while read file; do echo "  - $file"; done
            return 0
        fi
    fi
    
    report FAILURE "リポジトリコンテンツの取得に失敗しました"
    debug "レスポンス: ${result:0:100}..."
    return 1
}

# 特定ファイルのコミット履歴テスト
test_file_commit() {
    report INFO "ファイルコミット履歴テスト実行中..."
    
    local repo="site-u2023/aios"
    local file="country.db"
    local token=$(get_token)
    local branch="main"  # デフォルトブランチ名
    local auth_header=""
    [ -n "$token" ] && auth_header="--header=\"Authorization: token $token\""
    
    local cmd="wget -qO- $auth_header \"https://api.github.com/repos/$repo/commits?path=$file&sha=$branch\""
    debug "実行コマンド: $cmd"
    
    local result=$(eval $cmd 2>/dev/null)
    
    if [ -n "$result" ]; then
        # コミット数をカウント
        local commit_count=$(echo "$result" | grep -o '"sha"' | wc -l)
        
        if [ "$commit_count" -gt 0 ]; then
            report SUCCESS "ファイルコミット履歴: $file に対して $commit_count 件のコミットを検出"
            # 最新のコミットハッシュとメッセージを表示
            local latest_sha=$(echo "$result" | sed -n 's/.*"sha":\s*"\([^"]*\)".*/\1/p' | head -1)
            local latest_date=$(echo "$result" | sed -n 's/.*"date":\s*"\([^"]*\)".*/\1/p' | head -1)
            echo "  - 最新コミット: ${latest_sha:0:7} (日付: $latest_date)"
            return 0
        fi
    fi
    
    report FAILURE "ファイルコミット履歴の取得に失敗しました"
    debug "レスポンス: ${result:0:100}..."
    return 1
}

# ファイルの直接ダウンロードテスト
test_file_download() {
    report INFO "ファイルダウンロードテスト実行中..."
    
    local base_url="https://raw.githubusercontent.com/site-u2023/aios/main"
    local file="country.db"
    
    # 一時ファイルパス
    local temp_file="/tmp/github_test_download"
    
    if wget -q -O "$temp_file" "$base_url/$file"; then
        local file_size=$(wc -c < "$temp_file")
        if [ "$file_size" -gt 0 ]; then
            report SUCCESS "ファイルダウンロード: $file (サイズ: $file_size バイト)"
            # ファイルの先頭10行を表示
            echo "ファイル内容のサンプル:"
            head -5 "$temp_file" | while read line; do echo "  > $line"; done
            rm -f "$temp_file"
            return 0
        else
            report FAILURE "ファイルダウンロード: ファイルサイズが0バイトです"
        fi
    else
        report FAILURE "ファイルダウンロードに失敗しました"
    fi
    
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# すべてのテストの実行
run_all_tests() {
    echo "=================================================="
    echo "GitHub API接続テスト - $(date)"
    echo "=================================================="
    
    test_network_basic
    echo ""
    test_api_rate_limit_no_auth
    echo ""
    test_api_rate_limit_with_auth
    echo ""
    test_repo_info
    echo ""
    test_contents
    echo ""
    test_file_commit
    echo ""
    test_file_download
    echo ""
    
    echo "=================================================="
    echo "テスト完了 - $(date)"
    echo "=================================================="
}

# メイン実行
run_all_tests
