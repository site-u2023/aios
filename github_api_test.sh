#!/bin/sh

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-03-12
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 19.07 and 24.10)
#
# 📢 NOTE: OpenWrt OS exclusively uses Almquist Shell (ash)
# =========================================================

# グローバル変数
JQ_AVAILABLE=0
WGET_AVAILABLE=0

# ユーティリティ関数
report() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "SUCCESS") echo -e "\033[1;32m[成功]\033[0m $message" ;;
        "PARTIAL") echo -e "\033[1;33m[一部成功]\033[0m $message" ;;
        "FAILURE") echo -e "\033[1;31m[失敗]\033[0m $message" ;;
        "INFO")    echo -e "\033[1;36m[情報]\033[0m $message" ;;
        *)         echo -e "\033[1;37m[$status]\033[0m $message" ;;
    esac
}

debug() {
    echo -e "\033[1;35m[DEBUG]\033[0m $1"
}

# トークンの取得
get_token() {
    local token_file="/etc/aios_token"
    
    if [ -f "$token_file" ] && [ -r "$token_file" ]; then
        cat "$token_file" | tr -d '\n\r' | head -1
        return 0
    fi
    
    # 環境変数からの取得
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN"
        return 0
    fi
    
    return 1
}

# システム診断
check_system() {
    report INFO "システム診断を実行中..."
    
    # wgetは必須ツール（OpenWrtの標準）
    if command -v wget >/dev/null 2>&1; then
        WGET_AVAILABLE=1
        report SUCCESS "wget: 使用可能です"
    else
        report FAILURE "wget: インストールされていません。テストを実行できません"
        exit 1
    fi
    
    if command -v jq >/dev/null 2>&1; then
        JQ_AVAILABLE=1
        report SUCCESS "jq: インストールされています（バージョン: $(jq --version 2>&1)）"
    else
        report PARTIAL "jq: インストールされていません。代替パース方式を使用します"
    fi
    
    report SUCCESS "ホスト名: $(hostname 2>/dev/null)"
    report SUCCESS "OS情報: $(uname -a 2>/dev/null)"
}

# ネットワーク接続状態の確認
check_network() {
    report INFO "ネットワーク接続状況の確認中..."
    
    # インターフェース一覧
    if command -v ip >/dev/null 2>&1; then
        local interfaces=$(ip -o -4 addr show | awk '{print $2}' | sort | uniq | tr '\n' ' ')
        report SUCCESS "ネットワークインターフェース: $interfaces"
    elif command -v ifconfig >/dev/null 2>&1; then
        local interfaces=$(ifconfig | grep -E "^[a-z]" | awk '{print $1}' | tr '\n' ' ')
        report SUCCESS "ネットワークインターフェース: $interfaces"
    fi
    
    # デフォルトゲートウェイ
    if command -v ip >/dev/null 2>&1; then
        local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
        if [ -n "$gateway" ]; then
            report SUCCESS "デフォルトゲートウェイ: $gateway"
        else
            report PARTIAL "デフォルトゲートウェイ: 見つかりません"
        fi
    elif command -v route >/dev/null 2>&1; then
        local gateway=$(route -n | grep '^0.0.0.0' | awk '{print $2}' | head -1)
        if [ -n "$gateway" ]; then
            report SUCCESS "デフォルトゲートウェイ: $gateway"
        else
            report PARTIAL "デフォルトゲートウェイ: 見つかりません"
        fi
    fi
    
    # DNSサーバー
    report SUCCESS "DNSサーバー:"
    if [ -f "/etc/resolv.conf" ]; then
        local nameservers=$(grep '^nameserver' /etc/resolv.conf | awk '{print "  - " $2}')
        echo "$nameservers"
    else
        echo "  - 設定が見つかりません"
    fi
}

# OpenWrt 19.07に対応したより堅牢なタイムスタンプフォーマット関数
format_timestamp() {
    # 入力値が空の場合の保護
    if [ -z "$1" ]; then
        echo "不明"
        return 0
    fi
    
    local unix_time="$1"
    # 数値チェック（OpenWrt 19.07のashでも動作する方法）
    case "$unix_time" in
        ''|*[!0-9]*) 
            echo "不明"
            return 0
            ;;
    esac
    
    # 現在時刻を取得
    local now=$(date +%s)
    case "$now" in
        ''|*[!0-9]*) 
            echo "不明"
            return 0
            ;;
    esac
    
    # 文字列から数値への安全な変換（OpenWrtのashでも動作）
    local diff=0
    if [ "$unix_time" -gt "$now" ]; then
        # exprの結果が0より小さくならないことを保証
        diff=$(expr "$unix_time" - "$now")
    fi
    
    if [ "$diff" -eq 0 ]; then
        echo "0分後"
    elif [ "$diff" -lt 60 ]; then
        echo "1分未満"
    elif [ "$diff" -lt 3600 ]; then
        # OpenWrt 19.07のashでも動作
        local mins=$(expr "$diff" / 60)
        echo "${mins}分後"
    else
        # OpenWrt 19.07のashでも動作
        local hours=$(expr "$diff" / 3600)
        local mins=$(expr "$diff" % 3600 / 60)
        echo "${hours}時間${mins}分後"
    fi
}

# 基本接続テスト
test_network_basic() {
    report INFO "基本ネットワーク接続テスト中..."
    
    # DNS解決テスト
    local resolved_ip=""
    if command -v dig >/dev/null 2>&1; then
        resolved_ip=$(dig +short api.github.com | head -1)
    elif command -v nslookup >/dev/null 2>&1; then
        resolved_ip=$(nslookup api.github.com 2>/dev/null | grep -A2 'Name:' | grep 'Address:' | head -1 | awk '{print $2}')
    elif command -v getent >/dev/null 2>&1; then
        resolved_ip=$(getent hosts api.github.com | awk '{print $1}' | head -1)
    else
        # 単純なpingコマンドからIPアドレスを抽出
        resolved_ip=$(ping -c 1 api.github.com 2>/dev/null | grep PING | head -1 | sed -e 's/.*(\([0-9.]*\)).*/\1/')
    fi
    
    if [ -n "$resolved_ip" ]; then
        report SUCCESS "DNS解決: api.github.com を解決できました"
        debug "DNS解決結果: $resolved_ip"
    else
        report FAILURE "DNS解決: api.github.com を解決できません"
        return 1
    fi
    
    # Pingテスト
    if ping -c 1 -W 2 api.github.com >/dev/null 2>&1; then
        local ping_time=$(ping -c 1 -W 2 api.github.com 2>/dev/null | grep "time=" | awk -F "time=" '{print $2}' | awk '{print $1}')
        report SUCCESS "Ping: api.github.com に到達可能です (時間: $ping_time)"
    else
        report PARTIAL "Ping: api.github.com に到達できません (ファイアウォールで制限されている可能性あり)"
    fi
    
    # HTTPS接続テスト（wgetのみ使用）
    wget -q --spider https://api.github.com
    local https_result=$?
    
    if [ "$https_result" -eq 0 ]; then
        report SUCCESS "HTTPS: api.github.com へHTTPS接続可能です"
    else
        report FAILURE "HTTPS: api.github.com へHTTPS接続できません"
        return 1
    fi
    
    return 0
}

# トークン状態詳細チェック（旧-ts機能）
test_token_status() {
    report INFO "GitHub トークン状態確認中..."
    local token_file="/etc/aios_token"
    local token=""
    
    # トークンファイルの存在確認
    if [ -f "$token_file" ]; then
        report SUCCESS "トークンファイル: $token_file (存在します)"
        
        # 権限チェック
        local perms=$(ls -l "$token_file" | awk '{print $1}')
        report INFO "  ファイル権限: $perms"
        
        # トークン取得
        token=$(get_token)
        if [ -n "$token" ]; then
            local token_preview="${token:0:5}..."
            report INFO "  トークン先頭: $token_preview"
            
            # トークン認証チェック
            local temp_file="/tmp/github_token_check.tmp"
            wget -q -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/user" 2>/dev/null
            
            # 認証状態の確認
            if [ -s "$temp_file" ]; then
                if grep -q "login" "$temp_file"; then
                    local login=""
                    if [ "$JQ_AVAILABLE" -eq 1 ]; then
                        login=$(jq -r '.login' "$temp_file" 2>/dev/null)
                    else
                        login=$(grep -o '"login"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" | sed 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                    fi
                    
                    if [ -n "$login" ]; then
                        report SUCCESS "  認証状態: ✅ 有効（ユーザー: $login）"
                    else
                        report SUCCESS "  認証状態: ✅ 有効（ユーザー名取得失敗）"
                    fi
                else
                    report FAILURE "  認証状態: ❌ 無効（応答にユーザー情報がありません）"
                fi
            else
                report FAILURE "  認証状態: ❌ 無効（応答が空です）"
            fi
            
            rm -f "$temp_file" 2>/dev/null
        else
            report FAILURE "  トークン読み取り失敗"
        fi
    else
        report PARTIAL "トークンファイル: $token_file (存在しません)"
        report INFO "  `aios -t` コマンドでトークンを設定できます"
    fi
}

# 認証なしでのAPI制限テスト
test_api_rate_limit_no_auth() {
    report INFO "API制限テスト (認証なし) 実行中..."
    local temp_file="/tmp/github_ratelimit_noauth.tmp"
    
    # wgetを使用（OpenWrtの標準）
    wget -q -O "$temp_file" "https://api.github.com/rate_limit" 2>/dev/null
    
    # レスポンスチェック
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        local remaining=""
        local limit=""
        local reset_time=""
        
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            remaining=$(jq -r '.resources.core.remaining' "$temp_file" 2>/dev/null)
            limit=$(jq -r '.resources.core.limit' "$temp_file" 2>/dev/null)
            reset_time=$(jq -r '.resources.core.reset' "$temp_file" 2>/dev/null)
        else
            # 代替パース方法
            remaining=$(grep -A3 '"core"' "$temp_file" | grep '"remaining"' | head -1 | grep -o '[0-9]\+')
            limit=$(grep -A3 '"core"' "$temp_file" | grep '"limit"' | head -1 | grep -o '[0-9]\+')
            reset_time=$(grep -A3 '"core"' "$temp_file" | grep '"reset"' | head -1 | grep -o '[0-9]\+')
        fi
            
        if [ -n "$remaining" ] && [ -n "$limit" ]; then
            local reset_formatted=""
            if [ -n "$reset_time" ]; then
                reset_formatted=$(format_timestamp "$reset_time")
                report SUCCESS "API制限 (認証なし): 残り $remaining/$limit リクエスト (回復: $reset_formatted)"
            else
                report SUCCESS "API制限 (認証なし): 残り $remaining/$limit リクエスト"
            fi
            rm -f "$temp_file"
            return 0
        fi
    fi
    
    report FAILURE "API制限情報を取得できませんでした"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# 認証ありでのAPI制限テスト
test_api_rate_limit_with_auth() {
    report INFO "API制限テスト (認証あり) 実行中..."
    
    local token=$(get_token)
    if [ -z "$token" ]; then
        report PARTIAL "トークンが設定されていないため、認証ありのAPI制限テストはスキップします"
        return 0
    fi
    
    local temp_file="/tmp/github_ratelimit_auth.tmp"
    
    # wgetを使用（OpenWrtの標準）
    wget -q -O "$temp_file" --header="Authorization: token $token" "https://api.github.com/rate_limit" 2>/dev/null
    
    # レスポンスチェック
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        # 認証エラーをチェック
        if grep -q "Bad credentials" "$temp_file"; then
            report FAILURE "API制限テスト: 無効なトークンです"
            rm -f "$temp_file"
            return 1
        fi
        
        local remaining=""
        local limit=""
        local reset_time=""
        
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            remaining=$(jq -r '.resources.core.remaining' "$temp_file" 2>/dev/null)
            limit=$(jq -r '.resources.core.limit' "$temp_file" 2>/dev/null)
            reset_time=$(jq -r '.resources.core.reset' "$temp_file" 2>/dev/null)
        else
            # 代替パース方法
            remaining=$(grep -A3 '"core"' "$temp_file" | grep '"remaining"' | head -1 | grep -o '[0-9]\+')
            limit=$(grep -A3 '"core"' "$temp_file" | grep '"limit"' | head -1 | grep -o '[0-9]\+')
            reset_time=$(grep -A3 '"core"' "$temp_file" | grep '"reset"' | head -1 | grep -o '[0-9]\+')
        fi
        
        if [ -n "$remaining" ] && [ -n "$limit" ]; then
            local reset_formatted=""
            if [ -n "$reset_time" ]; then
                reset_formatted=$(format_timestamp "$reset_time")
                report SUCCESS "API制限 (認証あり): 残り $remaining/$limit リクエスト (回復: $reset_formatted)"
            else
                report SUCCESS "API制限 (認証あり): 残り $remaining/$limit リクエスト"
            fi
            rm -f "$temp_file"
            return 0
        fi
    fi
    
    report FAILURE "API制限情報を取得できませんでした"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# リポジトリ情報テスト
test_repo_info() {
    report INFO "リポジトリ情報取得テスト実行中..."
    
    local repo_owner="site-u2023"
    local repo_name="aios"
    local temp_file="/tmp/github_repo_info.tmp"
    
    # トークンの取得
    local token=$(get_token)
    local auth_header=""
    if [ -n "$token" ]; then
        auth_header="Authorization: token $token"
    fi
    
    # API呼び出し
    if [ -n "$auth_header" ]; then
        wget -q -O "$temp_file" --header="$auth_header" "https://api.github.com/repos/$repo_owner/$repo_name" 2>/dev/null
    else
        wget -q -O "$temp_file" "https://api.github.com/repos/$repo_owner/$repo_name" 2>/dev/null
    fi
    
    # レスポンスチェック
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        local repo_full_name=""
        local repo_description=""
        local repo_stars=""
        local repo_forks=""
        
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            repo_full_name=$(jq -r '.full_name' "$temp_file" 2>/dev/null)
            repo_description=$(jq -r '.description // "説明なし"' "$temp_file" 2>/dev/null)
            repo_stars=$(jq -r '.stargazers_count' "$temp_file" 2>/dev/null)
            repo_forks=$(jq -r '.forks_count' "$temp_file" 2>/dev/null)
        else
            # 代替パース方法
            repo_full_name=$(grep -o '"full_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" | head -1 | sed 's/.*"full_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            repo_description=$(grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" | head -1 | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            repo_stars=$(grep -o '"stargazers_count"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
            repo_forks=$(grep -o '"forks_count"[[:space:]]*:[[:space:]]*[0-9]\+' "$temp_file" | head -1 | grep -o '[0-9]\+')
            
            if [ -z "$repo_description" ]; then
                repo_description="説明なし"
            fi
        fi
        
        if [ -n "$repo_full_name" ]; then
            report SUCCESS "リポジトリ情報:"
            echo "  - 名前: $repo_full_name"
            echo "  - 説明: $repo_description"
            echo "  - スター数: $repo_stars"
            echo "  - フォーク数: $repo_forks"
            rm -f "$temp_file"
            return 0
        fi
    fi
    
    report FAILURE "リポジトリ情報を取得できませんでした"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# コミット履歴テスト
test_commit_history() {
    report INFO "最新コミット情報取得テスト実行中..."
    
    local repo_owner="site-u2023"
    local repo_name="aios"
    local temp_file="/tmp/github_commit_history.tmp"
    
    # トークンの取得
    local token=$(get_token)
    local auth_header=""
    if [ -n "$token" ]; then
        auth_header="Authorization: token $token"
    fi
    
    # API呼び出し
    if [ -n "$auth_header" ]; then
        wget -q -O "$temp_file" --header="$auth_header" "https://api.github.com/repos/$repo_owner/$repo_name/commits?per_page=3" 2>/dev/null
    else
        wget -q -O "$temp_file" "https://api.github.com/repos/$repo_owner/$repo_name/commits?per_page=3" 2>/dev/null
    fi
    
    # レスポンスチェック
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        report SUCCESS "最新コミット情報:"
        
        if [ "$JQ_AVAILABLE" -eq 1 ]; then
            local i=0
            while [ $i -lt 3 ]; do
                local sha=$(jq -r ".[$i].sha" "$temp_file" 2>/dev/null | cut -c1-7)
                local date=$(jq -r ".[$i].commit.author.date" "$temp_file" 2>/dev/null | sed 's/T/ /; s/Z//')
                local message=$(jq -r ".[$i].commit.message" "$temp_file" 2>/dev/null | head -1)
                local author=$(jq -r ".[$i].commit.author.name" "$temp_file" 2>/dev/null)
                
                if [ "$sha" = "null" ] || [ -z "$sha" ]; then
                    break
                fi
                
                echo "  - コミット: [$sha] $date - $author"
                echo "    メッセージ: $message"
                i=$(expr $i + 1)
            done
        else
            # 代替パース方法（より堅牢なgrep方式）
            grep -o '"sha"[[:space:]]*:[[:space:]]*"[a-f0-9]\{7,40\}"' "$temp_file" | head -3 | sed 's/.*"sha"[[:space:]]*:[[:space:]]*"\([a-f0-9]\{7\}\).*/  - コミットID: \1/' | head -3
            grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_file" | head -3 | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/    メッセージ: \1/'
        fi
        
        rm -f "$temp_file"
        return 0
    fi
    
    report FAILURE "コミット履歴を取得できませんでした"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# ファイルダウンロードテスト
test_file_download() {
    report INFO "ファイルダウンロードテスト実行中..."
    
    local repo_owner="site-u2023"
    local repo_name="aios"
    local file_path="aios"
    local temp_file="/tmp/github_file_test.tmp"
    
    # 直接ダウンロード
    wget -q -O "$temp_file" "https://raw.githubusercontent.com/$repo_owner/$repo_name/main/$file_path" 2>/dev/null
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        local file_size=$(wc -c < "$temp_file")
        local file_version=$(grep -o 'SCRIPT_VERSION="[^"]*"' "$temp_file" | head -1 | cut -d'"' -f2)
        
        report SUCCESS "ファイル 'aios' ダウンロード成功"
        echo "  - サイズ: $file_size バイト"
        echo "  - バージョン: $file_version"
        
        rm -f "$temp_file"
        return 0
    fi
    
    report FAILURE "ファイルをダウンロードできませんでした"
    rm -f "$temp_file" 2>/dev/null
    return 1
}

# 総合テスト実行
run_all_tests() {
    echo "==========================================================="
    echo "📊 GitHub API接続テスト (aios)"
    echo "🕒 実行時間: $(date +'%Y-%m-%d %H:%M:%S')"
    echo "==========================================================="
    
    # システム情報確認
    check_system
    check_network
    
    echo "==========================================================="
    echo "🔍 接続テスト"
    echo "==========================================================="
    test_network_basic
    
    echo "==========================================================="
    echo "🔑 トークン状態"
    echo "==========================================================="
    test_token_status
    
    echo "==========================================================="
    echo "📈 API制限情報"
    echo "==========================================================="
    test_api_rate_limit_no_auth
    test_api_rate_limit_with_auth
    
    echo "==========================================================="
    echo "📁 リポジトリアクセス"
    echo "==========================================================="
    test_repo_info
    test_commit_history
    test_file_download
    
    echo "==========================================================="
    echo "📝 テスト結果概要"
    echo "==========================================================="
    report INFO "テスト完了"
    report INFO "GitHub API接続テストの結果を上記で確認してください"
    report INFO "認証エラーが発生する場合は 'aios -t' で新しいトークンを設定してください"
    echo "==========================================================="
}

# メイン実行
run_all_tests
exit 0
