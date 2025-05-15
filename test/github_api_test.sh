#!/bin/sh

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-12
# Version: 07
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 19.07 and 24.10)
# =========================================================

echo "VERSION 09"

# スクリプト先頭部分に追加
# デバッグモードの検出（aios から渡される場合に対応）
if [ -z "$DEBUG_MODE" ]; then
    if echo "$@" | grep -q "\-d"; then
        DEBUG_MODE="true"
    else
        DEBUG_MODE="false"
    fi
fi

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

# 🔵 JSON値抽出ユーティリティ（jq不要、シンプル化） 🔵
json_get_value() {
    local file="$1"
    local key="$2"
    
    # シンプルに直接キーの値を取得（階層対応）
    if [ -f "$file" ]; then
        if echo "$key" | grep -q "\." 2>/dev/null; then
            # 階層キーの場合
            local parts=$(echo "$key" | tr '.' ' ')
            local key1=$(echo "$parts" | awk '{print $1}')
            local key2=$(echo "$parts" | awk '{print $2}')
            local key3=$(echo "$parts" | awk '{print $3}')
            
            # key1.key2.key3 の場合
            if [ -n "$key3" ]; then
                grep -o "\"$key3\"[[:space:]]*:[[:space:]]*[0-9]\\+" "$file" | head -1 | grep -o "[0-9]\\+"
            # key1.key2 の場合
            elif [ -n "$key2" ]; then
                grep -o "\"$key2\"[[:space:]]*:[[:space:]]*[0-9]\\+" "$file" | head -1 | grep -o "[0-9]\\+"
            fi
        else
            # 単一キーの場合
            grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}\"]\\+" "$file" | head -1 | sed 's/.*:[[:space:]]*//; s/[[:space:]]*$//'
        fi
    fi
}

# 🔵 システム＆ネットワーク診断関数 🔵
check_system() {
    report INFO "System diagnostics running..."
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
    
    # HTTPS接続テスト
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

# 🔵 トークン接頭辞表示 🔵
get_token_prefix() {
    local token="$1"
    local prefix=""
    
    if [ -n "$token" ] && [ ${#token} -gt 5 ]; then
        # POSIXシェル互換の方法でトークンの最初の5文字を抽出
        prefix=$(printf "%s" "$token" | cut -c1-5)"..."
    else
        prefix="???.."
    fi
    
    printf "%s" "$prefix"
}

# 🔵 トークン状態テスト 🔵
test_token_status() {
    report INFO "Checking GitHub token status..."
    local token_file="/etc/aios_token"
    
    # トークンファイルがない場合は早期リターン
    if [ ! -f "$token_file" ]; then
        report PARTIAL "Token file: $token_file (doesn't exist)"
        report INFO "  Use 'aios -t' command to set a token"
        return 0
    fi
    
    # 以下はファイルが存在する場合の処理
    report SUCCESS "Token file: $token_file (exists)"
    
    # 権限チェック
    local perms=$(ls -l "$token_file" | awk '{print $1}')
    report INFO "  File permissions: $perms"
    
    # トークン取得
    local token=$(get_github_token)
    if [ -z "$token" ]; then
        report FAILURE "  Failed to read token"
        return 1
    fi
    
    # トークンの先頭部分だけを表示（セキュリティ対策）
    local token_preview=$(get_token_prefix "$token")
    report INFO "  Token prefix: $token_preview"
    
    # トークン認証チェック
    local temp_file="/tmp/github_token_check.tmp"
    wget -q --no-check-certificate -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/user" 2>/dev/null
    
    # 認証状態の確認
    if [ -s "$temp_file" ]; then
        if grep -q "login" "$temp_file" 2>/dev/null; then
            # ユーザー名抽出
            local login=$(grep -o '"login"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" 2>/dev/null | \
                sed 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
            
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
    return 0
}

# 🔵 API制限テスト（非認証） 🔵
test_api_rate_limit_no_auth() {
    report INFO "API rate limit test (unauthenticated)..."
    local temp_file="/tmp/github_ratelimit_noauth.tmp"
    
    # API呼び出し
    wget -q --no-check-certificate -O "$temp_file" "https://api.github.com/rate_limit" 2>/dev/null
    
    # レスポンスチェック
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        report FAILURE "Failed to get API rate limit information"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    # デバッグモードの場合はレスポンスを表示
    if [ "$DEBUG_MODE" = "true" ]; then
        report DEBUG "API Response (unauthenticated):"
        echo "----------------------------------------"
        cat "$temp_file" | head -30
        echo "----------------------------------------"
    fi
    
    # 直接grepで値を抽出（より堅牢な方法）
    local core_remaining=$(grep -o '"remaining"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
    local core_limit=$(grep -o '"limit"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
    local reset_time=$(grep -o '"reset"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
    
    # 結果表示
    if [ -n "$core_remaining" ] && [ -n "$core_limit" ]; then
        report SUCCESS "API rate limit (unauthenticated): $core_remaining/$core_limit requests remaining"
    else
        report FAILURE "Failed to parse API rate limit information"
    fi
    
    rm -f "$temp_file" 2>/dev/null
    return 0
}

# 🔵 API制限テスト（認証あり） 🔵
test_api_rate_limit_with_auth() {
    report INFO "API rate limit test (authenticated)..."
    
    # トークンファイルの存在確認（早期リターン）
    if [ ! -f "/etc/aios_token" ]; then
        report INFO "Skipping authenticated API rate limit test (token file not found)"
        return 0
    fi
    
    # トークン取得
    local token=$(get_github_token)
    if [ -z "$token" ]; then
        report INFO "Skipping authenticated API rate limit test (token not available)"
        return 0
    fi
    
    # API呼び出し
    local temp_file="/tmp/github_ratelimit_auth.tmp"
    wget -q --no-check-certificate -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/rate_limit" 2>/dev/null
    
    # レスポンスチェック
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        report FAILURE "Failed to get authenticated API rate limit information"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    # デバッグモードの場合はレスポンスを表示
    if [ "$DEBUG_MODE" = "true" ]; then
        report DEBUG "API Response (authenticated):"
        echo "----------------------------------------"
        cat "$temp_file" | head -30
        echo "----------------------------------------"
    fi
    
    # 認証エラーチェック
    if grep -q "Bad credentials" "$temp_file" 2>/dev/null; then
        report FAILURE "API rate limit test: Invalid token"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    # 直接grepで値を抽出
    local core_remaining=$(grep -o '"remaining"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
    local core_limit=$(grep -o '"limit"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
    local reset_time=$(grep -o '"reset"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
    
    # 結果表示
    if [ -n "$core_remaining" ] && [ -n "$core_limit" ]; then
        report SUCCESS "API rate limit (authenticated): $core_remaining/$core_limit requests remaining"
    else
        report FAILURE "Failed to parse authenticated API rate limit information"
    fi
    
    rm -f "$temp_file" 2>/dev/null
    return 0
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
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        report FAILURE "Failed to get repository information (empty response)"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    # デバッグモードの場合はレスポンスを表示
    if [ "$DEBUG_MODE" = "true" ]; then
        report DEBUG "API Response (repository info):"
        echo "----------------------------------------"
        cat "$temp_file" | head -30
        echo "----------------------------------------"
    fi
    
    # 単純なgrepを使用して値を直接抽出
    local repo_full_name=$(grep -o '"full_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" | head -1 | sed 's/.*"full_name"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
    local repo_description=$(grep -o '"description"[[:space:]]*:[[:space:]]*[^,}]*' "$temp_file" | head -1 | sed 's/.*://;s/^[[:space:]]*//;s/null//')
    local repo_stars=$(grep -o '"stargazers_count"[[:space:]]*:[[:space:]]*[0-9]*' "$temp_file" | head -1 | grep -o '[0-9]*')
    local repo_forks=$(grep -o '"forks_count"[[:space:]]*:[[:space:]]*[0-9]*' "$temp_file" | head -1 | grep -o '[0-9]*')
    
    # 説明がない場合のデフォルト値
    if [ -z "$repo_description" ]; then
        repo_description="No description"
    fi
    
    if [ -n "$repo_full_name" ]; then
        report SUCCESS "Repository information:"
        echo "  - Name: $repo_full_name"
        echo "  - Description: $repo_description"
        echo "  - Stars: $repo_stars"
        echo "  - Forks: $repo_forks"
    else
        report FAILURE "Failed to parse repository information"
        
        # デバッグモードでさらに詳細な情報を表示
        if [ "$DEBUG_MODE" = "true" ]; then
            report DEBUG "Parser debug information:"
            echo "Full name extraction attempt: $(grep -o '"full_name"' "$temp_file" | wc -l) matches"
            echo "First 3 lines of file:"
            head -3 "$temp_file"
        fi
    fi
    
    rm -f "$temp_file" 2>/dev/null
    return 0
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
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        report FAILURE "Failed to retrieve commit history (empty response)"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    report SUCCESS "Latest commit information:"
    
    # コミット情報抽出
    # POSIXシェルでの配列処理は限られているため、パターンマッチでコミットを抽出
    local commit_count=$(grep -c '"sha"' "$temp_file" 2>/dev/null)
    local i=1
    
    while [ $i -le 3 ] && [ $i -le "$commit_count" ]; do
        # SHA抽出
        local sha_pattern=$(grep -o '"sha"[[:space:]]*:[[:space:]]*"[a-f0-9]\{7,40\}"' "$temp_file" 2>/dev/null | sed -n "${i}p")
        if [ -z "$sha_pattern" ]; then
            break
        fi
        
        local sha=$(echo "$sha_pattern" | sed 's/.*"sha"[[:space:]]*:[[:space:]]*"\([a-f0-9]\{7,40\}\)".*/\1/' 2>/dev/null | cut -c1-7)
        
        if [ -n "$sha" ]; then
            echo "  - Commit ID: $sha"
            
            # メッセージ抽出 - より堅牢なパターンマッチング
            # コミットマーカーから次のコミットまでの範囲を一時的に抽出
            local commit_block=$(sed -n "/\"sha\"[[:space:]]*:[[:space:]]*\"$sha/,/\"sha\"[[:space:]]*:/p" "$temp_file" 2>/dev/null | head -n -1)
            
            # ブロック内からメッセージを抽出
            local message=$(echo "$commit_block" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | 
                            sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
            
            if [ -n "$message" ]; then
                echo "    Message: $message"
            else
                echo "    Message: (no message)"
            fi
        fi
        
        i=$((i + 1))
    done
    
    rm -f "$temp_file" 2>/dev/null
    return 0
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
    
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        report FAILURE "Failed to download file (empty response)"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    local file_size=$(wc -c < "$temp_file")
    local file_version=$(grep -o 'SCRIPT_VERSION="[^"]*"' "$temp_file" 2>/dev/null | head -1 | cut -d'"' -f2)
    
    if [ -n "$file_size" ]; then
        report SUCCESS "File 'aios' download successful"
        echo "  - Size: $file_size bytes"
        if [ -n "$file_version" ]; then
            echo "  - Version: $file_version"
        else
            echo "  - Version: Unknown"
        fi
    else
        report FAILURE "Failed to get file information"
    fi
    
    rm -f "$temp_file" 2>/dev/null
    return 0
}

# 🔵 総合テスト実行 🔵
run_all_tests() {
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
    report INFO "If authentication errors occur, use 'aios -t' to set a token"
    echo "==========================================================="
}

# メイン実行
run_all_tests
exit 0
