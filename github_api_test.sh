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

# jqの有無を診断する関数
check_jq() {
    report INFO "システム診断を実行中..."
    
    if command -v jq >/dev/null 2>&1; then
        report SUCCESS "jq: インストールされています（バージョン: $(jq --version 2>/dev/null)）"
        JQ_AVAILABLE=1
    else
        report PARTIAL "jq: インストールされていません。代替パース方式を使用します"
        JQ_AVAILABLE=0
    fi
    
    # curlまたはwgetの確認
    if command -v curl >/dev/null 2>&1; then
        report SUCCESS "curl: インストールされています（バージョン: $(curl --version 2>/dev/null | head -n 1)）"
        CURL_AVAILABLE=1
    else
        CURL_AVAILABLE=0
        if command -v wget >/dev/null 2>&1; then
            report SUCCESS "wget: インストールされています（バージョン: $(wget --version 2>/dev/null | head -n 1)）"
            WGET_AVAILABLE=1
        else
            report FAILURE "curl/wget: どちらもインストールされていません。HTTPリクエストができません"
            WGET_AVAILABLE=0
            return 1
        fi
    fi
    
    # システム情報
    report SUCCESS "ホスト名: $(hostname 2>/dev/null)"
    report SUCCESS "OS情報: $(uname -a 2>/dev/null)"
    
    return 0
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

# シンプルなJSON解析関数（jqがない場合用）
extract_json_value() {
    local json_file="$1"
    local key_path="$2"
    local result=""
    
    # key_pathが階層的なパスの場合（例："core.remaining"）
    if echo "$key_path" | grep -q "\."; then
        local parent_key=$(echo "$key_path" | cut -d '.' -f1)
        local child_key=$(echo "$key_path" | cut -d '.' -f2)
        
        # 親キーのブロックを抽出
        local block_start=$(grep -n "\"$parent_key\"" "$json_file" | head -1 | cut -d':' -f1)
        
        if [ -n "$block_start" ]; then
            # 親ブロックから子キーの値を抽出
            result=$(tail -n +$block_start "$json_file" | grep -m 1 "\"$child_key\"" | sed 's/.*: *\([0-9]\+\).*/\1/')
        fi
    else
        # 単一キーの場合は直接抽出
        result=$(grep "\"$key_path\"" "$json_file" | head -1 | sed 's/.*: *\([^,"]*\).*/\1/' | sed 's/"//g')
    fi
    
    echo "$result"
}

# UNIXタイムスタンプを人間可読な形式に変換
format_timestamp() {
    local timestamp=$1
    local now=$(date +%s)
    
    # 現在時刻との差分を計算（秒）
    local diff=$((timestamp - now))
    
    if [ $diff -le 0 ]; then
        echo "すぐに"
    elif [ $diff -lt 60 ]; then
        echo "${diff}秒後"
    elif [ $diff -lt 3600 ]; then
        local minutes=$((diff / 60))
        echo "${minutes}分後"
    else
        local hours=$((diff / 3600))
        local minutes=$(((diff % 3600) / 60))
        echo "${hours}時間${minutes}分後"
    fi
}

# ネットワーク基本接続テスト
test_network_basic() {
    report INFO "基本ネットワーク接続テスト中..."
    
    # DNS解決テスト
    if nslookup api.github.com >/dev/null 2>&1; then
        report SUCCESS "DNS解決: api.github.com を解決できました"
        # 可能であればIPアドレスを表示
        local ip_addr=$(nslookup api.github.com 2>/dev/null | grep -A1 "Name:" | grep "Address:" | head -1 | awk '{print $2}')
        if [ -n "$ip_addr" ]; then
            debug "DNS解決結果: $ip_addr"
        fi
    else
        report FAILURE "DNS解決: api.github.com を解決できません"
    fi
    
    # Pingテスト (可能であれば)
    if ping -c 1 -W 2 api.github.com >/dev/null 2>&1; then
        local ping_time=$(ping -c 1 -W 2 api.github.com 2>/dev/null | grep "time=" | awk -F "time=" '{print $2}' | awk '{print $1}')
        report SUCCESS "Ping: api.github.com に到達可能です (時間: $ping_time)"
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
    
    # 一時ファイルを使用
    local temp_file="/tmp/github_api_limit_noauth.tmp"
    wget -q -O "$temp_file" "https://api.github.com/rate_limit" 2>/dev/null
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        # jqがインストールされている場合
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            local remaining=$(jq -r '.resources.core.remaining' "$temp_file" 2>/dev/null)
            local limit=$(jq -r '.resources.core.limit' "$temp_file" 2>/dev/null)
            local reset=$(jq -r '.resources.core.reset' "$temp_file" 2>/dev/null)
            
            if [ -n "$remaining" ] && [ -n "$limit" ] && [ -n "$reset" ]; then
                local reset_time=$(format_timestamp "$reset")
                report SUCCESS "API制限 (認証なし): 残り $remaining/$limit リクエスト (回復: $reset_time)"
                rm -f "$temp_file"
                return 0
            fi
        else
            # jqがない場合は改良版パーサーを使用
            local limit=""
            local remaining=""
            local reset=""
            
            # coreセクションを見つけて解析
            if grep -q '"core"' "$temp_file"; then
                remaining=$(extract_json_value "$temp_file" "core.remaining")
                limit=$(extract_json_value "$temp_file" "core.limit")
                reset=$(extract_json_value "$temp_file" "core.reset")
                
                if [ -n "$remaining" ] && [ -n "$limit" ] && [ -n "$reset" ]; then
                    local reset_time=$(format_timestamp "$reset")
                    report SUCCESS "API制限 (認証なし): 残り $remaining/$limit リクエスト (回復: $reset_time)"
                    rm -f "$temp_file"
                    return 0
                fi
            fi
        fi
    fi
    
    report FAILURE "API制限の取得に失敗しました (認証なし)"
    [ -f "$temp_file" ] && debug "レスポンスサイズ: $(wc -c < "$temp_file") バイト"
    rm -f "$temp_file" 2>/dev/null
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
    
    # 一時ファイルを使用
    local temp_file="/tmp/github_api_limit_auth.tmp"
    wget -q -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/rate_limit" 2>/dev/null
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        # jqがインストールされている場合
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            local remaining=$(jq -r '.resources.core.remaining' "$temp_file" 2>/dev/null)
            local limit=$(jq -r '.resources.core.limit' "$temp_file" 2>/dev/null)
            local reset=$(jq -r '.resources.core.reset' "$temp_file" 2>/dev/null)
            
            if [ -n "$remaining" ] && [ -n "$limit" ] && [ -n "$reset" ]; then
                local reset_time=$(format_timestamp "$reset")
                report SUCCESS "API制限 (認証あり): 残り $remaining/$limit リクエスト (回復: $reset_time)"
                rm -f "$temp_file"
                return 0
            fi
        else
            # jqがない場合は改良版パーサーを使用
            local limit=""
            local remaining=""
            local reset=""
            
            # coreセクションを見つけて解析
            if grep -q '"core"' "$temp_file"; then
                remaining=$(extract_json_value "$temp_file" "core.remaining")
                limit=$(extract_json_value "$temp_file" "core.limit")
                reset=$(extract_json_value "$temp_file" "core.reset")
                
                if [ -n "$remaining" ] && [ -n "$limit" ] && [ -n "$reset" ]; then
                    local reset_time=$(format_timestamp "$reset")
                    report SUCCESS "API制限 (認証あり): 残り $remaining/$limit リクエスト (回復: $reset_time)"
                    rm -f "$temp_file"
                    return 0
                fi
            fi
        fi
    fi
    
    report FAILURE "API制限の取得に失敗しました (認証あり)"
    [ -f "$temp_file" ] && debug "レスポンスサイズ: $(wc -c < "$temp_file") バイト"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# リポジトリ情報テスト
test_repo_info() {
    report INFO "リポジトリ情報テスト実行中..."
    
    local repo="site-u2023/aios"
    local token=$(get_token)
    local temp_file="/tmp/github_repo_info.tmp"
    
    # 認証ヘッダーの有無で分岐
    if [ -n "$token" ]; then
        wget -q -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/repos/$repo" 2>/dev/null
    else
        wget -q -O "$temp_file" "https://api.github.com/repos/$repo" 2>/dev/null
    fi
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            local name=$(jq -r '.name' "$temp_file" 2>/dev/null)
            local default_branch=$(jq -r '.default_branch' "$temp_file" 2>/dev/null)
            
            if [ -n "$name" ] && [ -n "$default_branch" ]; then
                report SUCCESS "リポジトリ情報: 名前=$name, デフォルトブランチ=$default_branch"
                rm -f "$temp_file"
                return 0
            fi
        else
            # 改良版パーサーを使用
            local name=$(grep '"name":' "$temp_file" | head -1 | sed 's/.*"name": *"\([^"]*\)".*/\1/')
            local default_branch=$(grep '"default_branch":' "$temp_file" | head -1 | sed 's/.*"default_branch": *"\([^"]*\)".*/\1/')
            
            if [ -n "$name" ] && [ -n "$default_branch" ]; then
                report SUCCESS "リポジトリ情報: 名前=$name, デフォルトブランチ=$default_branch"
                rm -f "$temp_file"
                return 0
            fi
        fi
    fi
    
    report FAILURE "リポジトリ情報の取得に失敗しました"
    [ -f "$temp_file" ] && debug "レスポンスサイズ: $(wc -c < "$temp_file") バイト"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# コンテンツ検証テスト
test_contents() {
    report INFO "リポジトリコンテンツテスト実行中..."
    
    local repo="site-u2023/aios"
    local token=$(get_token)
    local temp_file="/tmp/github_contents.tmp"
    
    # 認証ヘッダーの有無で分岐
    if [ -n "$token" ]; then
        wget -q -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/repos/$repo/contents" 2>/dev/null
    else
        wget -q -O "$temp_file" "https://api.github.com/repos/$repo/contents" 2>/dev/null
    fi
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        # ファイル数をカウント
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            local file_count=$(jq '. | length' "$temp_file" 2>/dev/null)
            
            if [ -n "$file_count" ] && [ "$file_count" -gt 0 ]; then
                report SUCCESS "リポジトリコンテンツ: $file_count 個のファイルを検出"
                echo "最初の5つのファイル:"
                jq -r '.[0:5] | .[] | .name' "$temp_file" 2>/dev/null | while read file; do 
                    echo "  - $file"; 
                done
                rm -f "$temp_file"
                return 0
            fi
        else
            # 改良版ファイル検出方法
            local file_count=$(grep -c '"name":' "$temp_file")
            
            if [ "$file_count" -gt 0 ]; then
                report SUCCESS "リポジトリコンテンツ: $file_count 個のファイルを検出"
                echo "最初の5つのファイル:"
                grep '"name":' "$temp_file" | head -5 | sed 's/.*"name": *"\([^"]*\)".*/\1/' | while read file; do
                    echo "  - $file"
                done
                rm -f "$temp_file"
                return 0
            fi
        fi
    fi
    
    report FAILURE "リポジトリコンテンツの取得に失敗しました"
    [ -f "$temp_file" ] && debug "レスポンスサイズ: $(wc -c < "$temp_file") バイト"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# 特定ファイルのコミット履歴テスト
test_file_commit() {
    report INFO "ファイルコミット履歴テスト実行中..."
    
    local repo="site-u2023/aios"
    local file="country.db"
    local token=$(get_token)
    local branch="main"  # デフォルトブランチ名
    local temp_file="/tmp/github_file_commit.tmp"
    
    # 認証ヘッダーの有無で分岐
    if [ -n "$token" ]; then
        wget -q -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/repos/$repo/commits?path=$file&sha=$branch" 2>/dev/null
    else
        wget -q -O "$temp_file" "https://api.github.com/repos/$repo/commits?path=$file&sha=$branch" 2>/dev/null
    fi
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            local commit_count=$(jq '. | length' "$temp_file" 2>/dev/null)
            
            if [ -n "$commit_count" ] && [ "$commit_count" -gt 0 ]; then
                report SUCCESS "ファイルコミット履歴: $file に対して $commit_count 件のコミットを検出"
                local latest_sha=$(jq -r '.[0].sha' "$temp_file" 2>/dev/null)
                local latest_date=$(jq -r '.[0].commit.committer.date' "$temp_file" 2>/dev/null)
                echo "  - 最新コミット: ${latest_sha:0:7} (日付: $latest_date)"
                rm -f "$temp_file"
                return 0
            fi
        else
            # 改良版コミット履歴検出方法
            local commit_count=$(grep -c '"sha":' "$temp_file")
            
            if [ "$commit_count" -gt 0 ]; then
                report SUCCESS "ファイルコミット履歴: $file に対して $commit_count 件のコミットを検出"
                
                # 最新のコミットSHAを取得（最初のshaエントリ）
                local latest_sha=$(grep '"sha":' "$temp_file" | head -1 | sed 's/.*"sha": *"\([^"]*\)".*/\1/')
                
                # 日付の取得（少し複雑だが、パターンマッチングで対応）
                local latest_date=""
                # commitセクションを見つけて解析
                local section_start=$(grep -n '"commit":' "$temp_file" | head -1 | cut -d':' -f1)
                if [ -n "$section_start" ]; then
                    latest_date=$(tail -n +$section_start "$temp_file" | grep -m 1 '"date":' | sed 's/.*"date": *"\([^"]*\)".*/\1/')
                fi
                
                echo "  - 最新コミット: ${latest_sha:0:7} (日付: $latest_date)"
                rm -f "$temp_file"
                return 0
            fi
        fi
    fi
    
    report FAILURE "ファイルコミット履歴の取得に失敗しました"
    [ -f "$temp_file" ] && debug "レスポンスサイズ: $(wc -c < "$temp_file") バイト"
    rm -f "$temp_file" 2>/dev/null
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
            # ファイルの先頭5行を表示
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

# ネットワーク接続状況のチェック
test_network_status() {
    report INFO "ネットワーク接続状況の確認中..."
    
    # インターフェース情報の取得
    if command -v ip >/dev/null 2>&1; then
        report SUCCESS "ネットワークインターフェース:"
        ip -4 addr | grep -v 'lo' | grep 'inet' | awk '{print "  - " $NF ": " $2}'
    elif command -v ifconfig >/dev/null 2>&1; then
        report SUCCESS "ネットワークインターフェース:"
        ifconfig | grep -E '(^[a-z]|inet addr)' | grep -v 'lo' | awk '{if($1 ~ /^[a-z]/) {printf "  - %s: ", $1} else if($0 ~ /inet/) {print $2}}' | sed 's/addr://'
    else
        report PARTIAL "ネットワークインターフェース情報を取得できません (ip/ifconfigコマンドがありません)"
    fi
    
    # デフォルトゲートウェイの確認
    if command -v ip >/dev/null 2>&1; then
        local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
        if [ -n "$gateway" ]; then
            report SUCCESS "デフォルトゲートウェイ: $gateway"
        else
            report PARTIAL "デフォルトゲートウェイが見つかりません"
        fi
    elif command -v route >/dev/null 2>&1; then
        local gateway=$(route -n | grep '^0.0.0.0' | awk '{print $2}' | head -1)
        if [ -n "$gateway" ]; then
            report SUCCESS "デフォルトゲートウェイ: $gateway"
        else
            report PARTIAL "デフォルトゲートウェイが見つかりません"
        fi
    else
        report PARTIAL "ルーティング情報を取得できません (ip/routeコマンドがありません)"
    fi
    
    # DNSサーバーの確認
    if [ -f "/etc/resolv.conf" ]; then
        local dns_servers=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}')
        if [ -n "$dns_servers" ]; then
            report SUCCESS "DNSサーバー:"
            echo "$dns_servers" | while read server; do
                echo "  - $server"
            done
        else
            report PARTIAL "DNSサーバーが設定されていません"
        fi
    else
        report PARTIAL "DNSサーバー情報を取得できません (/etc/resolv.conf がありません)"
    fi
    
    echo ""
}

# すべてのテストの実行
run_all_tests() {
    echo "=================================================="
    echo "GitHub API接続テスト - $(date)"
    echo "=================================================="
    
    # グローバル変数の初期化
    JQ_AVAILABLE=0
    CURL_AVAILABLE=0
    WGET_AVAILABLE=0
    
    # システム診断
    check_jq
    echo ""
    
    # ネットワーク状態確認
    test_network_status
    
    # 基本接続テスト
    test_network_basic
    echo ""
    
    # API制限テスト
    test_api_rate_limit_no_auth
    echo ""
    test_api_rate_limit_with_auth
    echo ""
    
    # リポジトリ情報テスト
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
