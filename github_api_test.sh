#!/bin/sh

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-12
# Version: 03
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 19.07 and 24.10)
# =========================================================

echo "VERSION 03"

# 🔵 aios関数チェック 🔵
if type debug_log >/dev/null 2>&1 && type get_github_token >/dev/null 2>&1; then
    USING_AIOS_FUNCTIONS=1
else
    USING_AIOS_FUNCTIONS=0
    
    # 最低限必要なフォールバック関数（単体実行時用）
    GITHUB_TOKEN_FILE="/etc/aios_token"
    
    debug_log() {
        local level="$1"
        local message="$2"
        echo "[$level] $message"
    }
    
    get_github_token() {
        if [ -f "$GITHUB_TOKEN_FILE" ] && [ -r "$GITHUB_TOKEN_FILE" ]; then
            cat "$GITHUB_TOKEN_FILE" | tr -d '\n\r' | head -1
            return 0
        fi
        return 1
    }
fi

# 🔵 テスト用ユーティリティ関数 🔵
report() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "SUCCESS") echo -e "\033[1;32m[Success]\033[0m $message" ;;
        "PARTIAL") echo -e "\033[1;33m[Partial]\033[0m $message" ;;
        "FAILURE") echo -e "\033[1;31m[Failure]\033[0m $message" ;;
        "INFO")    echo -e "\033[1;36m[Info]\033[0m $message" ;;
        "DEBUG")   echo -e "\033[1;35m[DEBUG]\033[0m $message" ;;
        *)         echo -e "\033[1;37m[$status]\033[0m $message" ;;
    esac
}

# 🔵 システム＆ネットワーク診断関数 🔵
check_system() {
    report INFO "System diagnostics running..."
    
    # jqチェック
    if command -v jq >/dev/null 2>&1; then
        report INFO "jq: Installed ($(jq --version 2>&1))"
    else
        report INFO "jq: Not installed. Using alternative parsing"
    fi
    
    report INFO "Hostname: $(hostname 2>/dev/null)"
    report INFO "OS: $(uname -a 2>/dev/null)"
}

check_network() {
    report INFO "Checking network connectivity..."
    
    # インターフェース一覧
    if command -v ip >/dev/null 2>&1; then
        local interfaces=$(ip -o -4 addr show 2>/dev/null | awk '{print $2}' | sort | uniq | tr '\n' ' ')
        report INFO "Network interfaces: $interfaces"
    elif command -v ifconfig >/dev/null 2>&1; then
        local interfaces=$(ifconfig 2>/dev/null | grep -E "^[a-z]" | awk '{print $1}' | tr '\n' ' ')
        report INFO "Network interfaces: $interfaces"
    fi
    
    # デフォルトゲートウェイ
    if command -v ip >/dev/null 2>&1; then
        local gateway=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
        if [ -n "$gateway" ]; then
            report INFO "Default gateway: $gateway"
        else
            report INFO "Default gateway: Not found"
        fi
    elif command -v route >/dev/null 2>&1; then
        local gateway=$(route -n 2>/dev/null | grep '^0.0.0.0' | awk '{print $2}' | head -1)
        if [ -n "$gateway" ]; then
            report INFO "Default gateway: $gateway"
        else
            report INFO "Default gateway: Not found"
        fi
    fi
    
    # DNSサーバー
    report INFO "DNS servers:"
    if [ -f "/etc/resolv.conf" ]; then
        grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print "  - " $2}'
    else
        echo "  - Not found"
    fi
}

# 🔵 基本的なネットワーク接続テスト 🔵
test_network_basic() {
    report INFO "Basic network connectivity test..."
    
    # DNS解決テスト
    local resolved_ip=""
    if command -v dig >/dev/null 2>&1; then
        resolved_ip=$(dig +short api.github.com 2>/dev/null | head -1)
    elif command -v nslookup >/dev/null 2>&1; then
        resolved_ip=$(nslookup api.github.com 2>/dev/null | grep -A2 'Name:' | grep 'Address:' | head -1 | awk '{print $2}')
    elif command -v getent >/dev/null 2>&1; then
        resolved_ip=$(getent hosts api.github.com 2>/dev/null | awk '{print $1}' | head -1)
    else
        # pingからIPアドレスを抽出
        resolved_ip=$(ping -c 1 api.github.com 2>/dev/null | grep PING | head -1 | sed -e 's/.*(\([0-9.]*\)).*/\1/')
    fi
    
    if [ -n "$resolved_ip" ]; then
        report SUCCESS "DNS resolution: api.github.com resolved successfully"
        report DEBUG "DNS result: $resolved_ip"
    else
        report FAILURE "DNS resolution: Unable to resolve api.github.com"
        return 1
    fi
    
    # Pingテスト
    if ping -c 1 -W 2 api.github.com >/dev/null 2>&1; then
        local ping_time=$(ping -c 1 -W 2 api.github.com 2>/dev/null | grep "time=" | awk -F "time=" '{print $2}' | awk '{print $1}')
        report SUCCESS "Ping: api.github.com is reachable (time: $ping_time)"
    else
        report PARTIAL "Ping: api.github.com is not reachable (possibly blocked by firewall)"
    fi
    
    # HTTPS接続テスト - OpenWrt 19.07での問題を回避
    wget -q --no-check-certificate --spider https://api.github.com >/dev/null 2>&1
    local https_result=$?
    
    if [ "$https_result" -eq 0 ]; then
        report SUCCESS "HTTPS: Connection to api.github.com succeeded"
    else
        report FAILURE "HTTPS: Connection to api.github.com failed"
        return 1
    fi
    
    return 0
}

# 🔵 トークン状態テスト 🔵
test_token_status() {
    report INFO "Checking GitHub token status..."
    local token_file="/etc/aios_token"
    local token=""
    
    # トークンファイルの存在確認
    if [ -f "$token_file" ]; then
        report SUCCESS "Token file: $token_file (exists)"
        
        # 権限チェック
        local perms=$(ls -l "$token_file" | awk '{print $1}')
        report INFO "  File permissions: $perms"
        
        # トークン取得
        token=$(get_github_token)
        if [ -n "$token" ]; then
            # トークンの先頭部分だけを表示（セキュリティ対策）
            if [ "${#token}" -gt 5 ]; then
                local token_preview="${token:0:5}..."
                report INFO "  Token prefix: $token_preview"
            else
                report INFO "  Token: Valid (details hidden)"
            fi
            
            # トークン認証チェック
            local temp_file="/tmp/github_token_check.tmp"
            
            # OpenWrt 19.07の問題を回避
            wget -q --no-check-certificate -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/user" 2>/dev/null
            
            # 認証状態の確認
            if [ -s "$temp_file" ]; then
                if grep -q "login" "$temp_file" 2>/dev/null; then
                    # ユーザー名抽出
                    local login=""
                    if command -v jq >/dev/null 2>&1; then
                        login=$(jq -r '.login' "$temp_file" 2>/dev/null)
                    else
                        login=$(grep -o '"login"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" 2>/dev/null | sed 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
                    fi
                    
                    if [ -n "$login" ]; then
                        report SUCCESS "  Authentication: ✅ Valid (user: $login)"
                    else
                        report SUCCESS "  Authentication: ✅ Valid (username extraction failed)"
                    fi
                else
                    report FAILURE "  Authentication: ❌ Invalid (response doesn't contain user info)"
                fi
            else
                report FAILURE "  Authentication: ❌ Invalid (empty response)"
            fi
            
            rm -f "$temp_file" 2>/dev/null
        else
            report FAILURE "  Failed to read token"
        fi
    else
        report PARTIAL "Token file: $token_file (doesn't exist)"
        report INFO "  Use `aios -t` command to set a token"
    fi
}

# 🔵 API制限テスト 🔵
test_api_rate_limit_no_auth() {
    report INFO "API rate limit test (unauthenticated)..."
    local temp_file="/tmp/github_ratelimit_noauth.tmp"
    
    # OpenWrt 19.07の問題を回避
    wget -q --no-check-certificate -O "$temp_file" "https://api.github.com/rate_limit" 2>/dev/null
    
    # レスポンスチェック
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        local remaining limit reset_time
        
        # JSONデータを安全に抽出
        if command -v jq >/dev/null 2>&1; then
            # jqによるパース
            remaining=$(jq -r '.resources.core.remaining' "$temp_file" 2>/dev/null)
            limit=$(jq -r '.resources.core.limit' "$temp_file" 2>/dev/null)
            reset_time=$(jq -r '.resources.core.reset' "$temp_file" 2>/dev/null)
        else
            # サイレント出力でパース
            remaining=$(grep -A3 '"core"' "$temp_file" 2>/dev/null | grep '"remaining"' 2>/dev/null | head -1 | grep -o '[0-9]\+' 2>/dev/null | head -1)
            limit=$(grep -A3 '"core"' "$temp_file" 2>/dev/null | grep '"limit"' 2>/dev/null | head -1 | grep -o '[0-9]\+' 2>/dev/null | head -1)
            reset_time=$(grep -A3 '"core"' "$temp_file" 2>/dev/null | grep '"reset"' 2>/dev/null | head -1 | grep -o '[0-9]\+' 2>/dev/null | head -1)
        fi
        
        # 結果表示
        if [ -n "$remaining" ] && [ -n "$limit" ]; then
            # 残り時間計算（可能なら）
            local reset_msg="unknown"
            if [ -n "$reset_time" ] && [ "$USING_AIOS_FUNCTIONS" -eq 1 ] && type format_timestamp >/dev/null 2>&1; then
                reset_msg=$(format_timestamp "$reset_time")
            fi
            
            report SUCCESS "API rate limit (unauthenticated): $remaining/$limit requests remaining (resets in: $reset_msg)"
            rm -f "$temp_file" 2>/dev/null
            return 0
        fi
    fi
    
    report FAILURE "Failed to get API rate limit information"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

test_api_rate_limit_with_auth() {
    report INFO "API rate limit test (authenticated)..."
    
    # トークン取得
    local token=$(get_github_token)
    if [ -z "$token" ]; then
        report PARTIAL "No token available, skipping authenticated API rate limit test"
        return 0
    fi
    
    # API呼び出し
    local temp_file="/tmp/github_ratelimit_auth.tmp"
    wget -q --no-check-certificate -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/rate_limit" 2>/dev/null
    
    # レスポンスチェック
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        # 認証エラーチェック
        if grep -q "Bad credentials" "$temp_file" 2>/dev/null; then
            report FAILURE "API rate limit test: Invalid token"
            rm -f "$temp_file" 2>/dev/null
            return 1
        fi
        
        # APIレスポンスパース
        local remaining limit reset_time
        
        if command -v jq >/dev/null 2>&1; then
            # jqによるパース
            remaining=$(jq -r '.resources.core.remaining' "$temp_file" 2>/dev/null)
            limit=$(jq -r '.resources.core.limit' "$temp_file" 2>/dev/null)
            reset_time=$(jq -r '.resources.core.reset' "$temp_file" 2>/dev/null)
        else
            # サイレント出力でパース
            remaining=$(grep -A3 '"core"' "$temp_file" 2>/dev/null | grep '"remaining"' 2>/dev/null | head -1 | grep -o '[0-9]\+' 2>/dev/null | head -1)
            limit=$(grep -A3 '"core"' "$temp_file" 2>/dev/null | grep '"limit"' 2>/dev/null | head -1 | grep -o '[0-9]\+' 2>/dev/null | head -1)
            reset_time=$(grep -A3 '"core"' "$temp_file" 2>/dev/null | grep '"reset"' 2>/dev/null | head -1 | grep -o '[0-9]\+' 2>/dev/null | head -1)
        fi
        
        # 結果表示
        if [ -n "$remaining" ] && [ -n "$limit" ]; then
                # 残り時間計算（可能なら）
            local reset_msg="unknown"
            if [ -n "$reset_time" ] && [ "$USING_AIOS_FUNCTIONS" -eq 1 ] && type format_timestamp >/dev/null 2>&1; then
                reset_msg=$(format_timestamp "$reset_time")
            fi
            
            report SUCCESS "API rate limit (authenticated): $remaining/$limit requests remaining (resets in: $reset_msg)"
            rm -f "$temp_file" 2>/dev/null
            return 0
        fi
    fi
    
    report FAILURE "Failed to get authenticated API rate limit information"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# 🔵 リポジトリ情報テスト 🔵
test_repo_info() {
    report INFO "Repository information test running..."
    
    local repo_owner="site-u2023"
    local repo_name="aios"
    local temp_file="/tmp/github_repo_info.tmp"
    
    # トークン取得
    local token=$(get_github_token)
    local auth_header=""
    if [ -n "$token" ]; then
        auth_header="Authorization: token $token"
    fi
    
    # API呼び出し
    if [ -n "$auth_header" ]; then
        wget -q --no-check-certificate -O "$temp_file" --header="$auth_header" "https://api.github.com/repos/$repo_owner/$repo_name" 2>/dev/null
    else
        wget -q --no-check-certificate -O "$temp_file" "https://api.github.com/repos/$repo_owner/$repo_name" 2>/dev/null
    fi
    
    # レスポンスチェック
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        # レポジトリ情報抽出
        local repo_full_name repo_description repo_stars repo_forks
        
        if command -v jq >/dev/null 2>&1; then
            # jqによるパース
            repo_full_name=$(jq -r '.full_name' "$temp_file" 2>/dev/null)
            repo_description=$(jq -r '.description // "No description"' "$temp_file" 2>/dev/null)
            repo_stars=$(jq -r '.stargazers_count' "$temp_file" 2>/dev/null)
            repo_forks=$(jq -r '.forks_count' "$temp_file" 2>/dev/null)
        else
            # サイレント出力でパース
            repo_full_name=$(grep -o '"full_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" 2>/dev/null | sed 's/.*"full_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
            repo_description=$(grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" 2>/dev/null | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
            repo_stars=$(grep -o '"stargazers_count"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" 2>/dev/null | grep -o '[0-9]\+' 2>/dev/null)
            repo_forks=$(grep -o '"forks_count"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" 2>/dev/null | grep -o '[0-9]\+' 2>/dev/null)
            
            # 説明がない場合
            if [ -z "$repo_description" ]; then
                repo_description="No description"
            fi
        fi
        
        if [ -n "$repo_full_name" ]; then
            report SUCCESS "Repository information:"
            echo "  - Name: $repo_full_name"
            echo "  - Description: $repo_description"
            echo "  - Stars: $repo_stars"
            echo "  - Forks: $repo_forks"
            rm -f "$temp_file" 2>/dev/null
            return 0
        fi
    fi
    
    report FAILURE "Failed to get repository information"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# 🔵 コミット履歴テスト 🔵
test_commit_history() {
    report INFO "Latest commit information test running..."
    
    local repo_owner="site-u2023"
    local repo_name="aios"
    local temp_file="/tmp/github_commit_history.tmp"
    
    # トークン取得
    local token=$(get_github_token)
    local auth_header=""
    if [ -n "$token" ]; then
        auth_header="Authorization: token $token"
    fi
    
    # API呼び出し
    if [ -n "$auth_header" ]; then
        wget -q --no-check-certificate -O "$temp_file" --header="$auth_header" "https://api.github.com/repos/$repo_owner/$repo_name/commits?per_page=3" 2>/dev/null
    else
        wget -q --no-check-certificate -O "$temp_file" "https://api.github.com/repos/$repo_owner/$repo_name/commits?per_page=3" 2>/dev/null
    fi
    
    # レスポンスチェック
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        report SUCCESS "Latest commit information:"
        
        if command -v jq >/dev/null 2>&1; then
            # jqによるパース
            for i in 0 1 2; do
                local sha=$(jq -r ".[$i].sha" "$temp_file" 2>/dev/null | cut -c1-7)
                local message=$(jq -r ".[$i].commit.message" "$temp_file" 2>/dev/null | head -1)
                
                if [ "$sha" = "null" ] || [ -z "$sha" ]; then
                    continue
                fi
                
                echo "  - Commit ID: $sha"
                echo "    Message: $message"
            done
        else
            # サイレント出力でパース
            for i in 1 2 3; do
                # パターンマッチでSHA抽出
                local sha=$(grep -o '"sha"[[:space:]]*:[[:space:]]*"[a-f0-9]\{7,40\}"' "$temp_file" 2>/dev/null | sed -n "${i}p" | sed 's/.*"sha"[[:space:]]*:[[:space:]]*"\([a-f0-9]\{7\}\).*/\1/' 2>/dev/null)
                
                if [ -n "$sha" ]; then
                    echo "  - Commit ID: $sha"
                    
                    # パターンマッチでメッセージ抽出
                    local message=$(grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" 2>/dev/null | sed -n "${i}p" | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/    Message: \1/' 2>/dev/null)
                    if [ -n "$message" ]; then
                        echo "$message"
                    fi
                fi
            done
        fi
        
        rm -f "$temp_file" 2>/dev/null
        return 0
    fi
    
    report FAILURE "Failed to retrieve commit history"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# 🔵 ファイルダウンロードテスト 🔵
test_file_download() {
    report INFO "File download test running..."
    
    local repo_owner="site-u2023"
    local repo_name="aios"
    local file_path="aios"
    local temp_file="/tmp/github_file_test.tmp"
    
    # 直接ダウンロード 
    wget -q --no-check-certificate -O "$temp_file" "https://raw.githubusercontent.com/$repo_owner/$repo_name/main/$file_path" 2>/dev/null
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        local file_size=$(wc -c < "$temp_file")
        local file_version=$(grep -o 'SCRIPT_VERSION="[^"]*"' "$temp_file" 2>/dev/null | head -1 | cut -d'"' -f2)
        
        report SUCCESS "File 'aios' download successful"
        echo "  - Size: $file_size bytes"
        echo "  - Version: $file_version"
        
        rm -f "$temp_file"
        return 0
    fi
    
    report FAILURE "Failed to download file"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# 🔵 総合テスト実行 🔵
run_all_tests() {
    echo "VERSION 03"
    echo "==========================================================="
    echo "📊 GitHub API Connection Test (aios)"
    echo "🕒 Execution time: $(date +'%Y-%m-%d %H:%M:%S')"
    echo "==========================================================="
    
    # システム情報確認
    check_system
    check_network
    
    echo "==========================================================="
    echo "🔍 Connection Test"
    echo "==========================================================="
    test_network_basic
    
    echo "==========================================================="
    echo "🔑 Token Status"
    echo "==========================================================="
    test_token_status
    
    echo "==========================================================="
    echo "📈 API Rate Limit Information"
    echo "==========================================================="
    test_api_rate_limit_no_auth
    test_api_rate_limit_with_auth
    
    echo "==========================================================="
    echo "📁 Repository Access"
    echo "==========================================================="
    test_repo_info
    test_commit_history
    test_file_download
    
    echo "==========================================================="
    echo "📝 Test Results Summary"
    echo "==========================================================="
    report INFO "Test completed"
    report INFO "Check the above results for GitHub API connection status"
    report INFO "If authentication errors occur, use 'aios -t' to set a new token"
    echo "==========================================================="
}

# メイン実行
run_all_tests
exit 0
