#!/bin/sh
set -e

CONFIG_FILE="/etc/sysctl.d/99-network-optimization-auto.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
log_highlight() { printf "${CYAN}[HIGHLIGHT]${NC} %s\n" "$1"; }

detect_memory() {
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    printf '%s\n' "$((mem_kb / 1024))"
}

detect_cpu_cores() {
    grep -c ^processor /proc/cpuinfo
}

get_current_connections() {
    if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then
        cat /proc/sys/net/netfilter/nf_conntrack_count
    else
        printf '%s\n' "0"
    fi
}

get_best_congestion_control() {
    local available
    available=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)
    for algo in bbr cubic reno; do
        if printf '%s\n' "$available" | grep -q "$algo"; then
            printf '%s\n' "$algo"
            return
        fi
    done
    printf '%s\n' "$(printf '%s\n' "$available" | awk '{print $1}')"
}

# Get current value dynamically - this is the key fix
get_current_value() {
    local setting="$1"
    case "$setting" in
        "rmem_max")
            cat /proc/sys/net/core/rmem_max 2>/dev/null || printf "%s" "unknown"
            ;;
        "wmem_max")
            cat /proc/sys/net/core/wmem_max 2>/dev/null || printf "%s" "unknown"
            ;;
        "tcp_rmem")
            cat /proc/sys/net/ipv4/tcp_rmem 2>/dev/null | tr -s '\t' ' ' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' || printf "%s" "unknown"
            ;;
        "tcp_wmem")
            cat /proc/sys/net/ipv4/tcp_wmem 2>/dev/null | tr -s '\t' ' ' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' || printf "%s" "unknown"
            ;;
        "tcp_congestion_control")
            cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || printf "%s" "unknown"
            ;;
        "nf_conntrack_max")
            cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || printf "%s" "unknown"
            ;;
        "netdev_max_backlog")
            cat /proc/sys/net/core/netdev_max_backlog 2>/dev/null || printf "%s" "unknown"
            ;;
        "somaxconn")
            cat /proc/sys/net/core/somaxconn 2>/dev/null || printf "%s" "unknown"
            ;;
        "active_connections")
            get_current_connections
            ;;
        *)
            printf "%s" "unknown"
            ;;
    esac
}

calculate_buffer_sizes() {
    local mem_mb=$1
    local cores=$2
    
    if [ "$mem_mb" -ge 3072 ]; then
        rmem_max=16777216; wmem_max=16777216
        tcp_rmem="4096 262144 16777216"; tcp_wmem="4096 262144 16777216"
        conntrack_max=262144; netdev_backlog=5000; somaxconn=16384
    elif [ "$mem_mb" -ge 1536 ]; then
        rmem_max=8388608; wmem_max=8388608
        tcp_rmem="4096 131072 8388608"; tcp_wmem="4096 131072 8388608"
        conntrack_max=131072; netdev_backlog=2500; somaxconn=8192
    elif [ "$mem_mb" -ge 512 ]; then
        rmem_max=4194304; wmem_max=4194304
        tcp_rmem="4096 65536 4194304"; tcp_wmem="4096 65536 4194304"
        conntrack_max=65536; netdev_backlog=1000; somaxconn=4096
    else
        rmem_max=1048576; wmem_max=1048576
        tcp_rmem="4096 32768 1048576"; tcp_wmem="4096 32768 1048576"
        conntrack_max=32768; netdev_backlog=500; somaxconn=2048
    fi
    
    if [ "$cores" -gt 4 ]; then
        netdev_backlog=$((netdev_backlog * 2))
        somaxconn=$((somaxconn * 2))
    elif [ "$cores" -gt 2 ]; then
        netdev_backlog=$((netdev_backlog + netdev_backlog / 2))
        somaxconn=$((somaxconn + somaxconn / 2))
    fi
}

format_bytes() {
    local bytes=$1
    if [ "$bytes" = "unknown" ]; then
        printf '%s' "unknown"
        return
    fi
    if [ "$bytes" -ge 1048576 ]; then
        printf '%s' "$((bytes / 1048576))MB"
    elif [ "$bytes" -ge 1024 ]; then
        printf '%s' "$((bytes / 1024))KB"
    else
        printf '%s' "${bytes}B"
    fi
}

values_equal() {
    local current="$1"
    local new="$2"
    
    if [ "$current" = "unknown" ] || [ "$new" = "unknown" ]; then
        return 1
    fi
    
    local norm_current=$(printf '%s\n' "$current" | tr -s ' \t' ' ' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    local norm_new=$(printf '%s\n' "$new" | tr -s ' \t' ' ' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    [ "$norm_current" = "$norm_new" ]
}

show_comparison() {
    printf '\n'
    printf "BEFORE vs AFTER COMPARISON\n"
    printf '\n'

    local max_setting=7
    local max_value=6
    local status_width=11

    local single_settings="rmem_max wmem_max tcp_congestion_control nf_conntrack_max netdev_max_backlog somaxconn"

    for setting in $single_settings; do
        [ ${#setting} -gt $max_setting ] && max_setting=${#setting}
    done

    local tcp_items="tcp_rmem (min) tcp_rmem (default) tcp_rmem (max) tcp_wmem (min) tcp_wmem (default) tcp_wmem (max)"
    for item in $tcp_items; do
        [ ${#item} -gt $max_setting ] && max_setting=${#item}
    done

    for setting in $single_settings; do
        local current_value=$(get_current_value "$setting")
        local new_value
        case "$setting" in
            "rmem_max") new_value="$rmem_max" ;;
            "wmem_max") new_value="$wmem_max" ;;
            "tcp_congestion_control") new_value="$best_congestion" ;;
            "nf_conntrack_max") new_value="$conntrack_max" ;;
            "netdev_max_backlog") new_value="$netdev_backlog" ;;
            "somaxconn") new_value="$somaxconn" ;;
        esac
        local display_current display_new
        case "$setting" in
            "rmem_max"|"wmem_max")
                display_current="$(format_bytes "$current_value")"
                display_new="$(format_bytes "$new_value")"
                ;;
            *)
                display_current="$current_value"
                display_new="$new_value"
                ;;
        esac
        [ ${#display_current} -gt $max_value ] && max_value=${#display_current}
        [ ${#display_new}     -gt $max_value ] && max_value=${#display_new}
    done

    for proto in rmem tcp_wmem; do
        local cur=$(get_current_value "${proto/tcp_/tcp_}")
        local new=$(eval echo "\$tcp_${proto/tcp_}")
        if [ "$cur" != "unknown" ]; then
            for val in $(echo "$cur") $(echo "$new"); do
                [ ${#val} -gt $max_value ] && max_value=${#val}
            done
        fi
    done

    max_setting=$((max_setting + 1))
    max_value=$((max_value + 1))

    local sep_setting sep_value sep_status
    sep_setting=$(printf '%*s' "$max_setting" '' | tr ' ' '-')
    sep_value=$(printf '%*s' "$max_value" '' | tr ' ' '-')
    sep_status=$(printf '%*s' "$status_width" '' | tr ' ' '-')

    printf "%-${max_setting}s| %-${max_value}s| %-${max_value}s| %-${status_width}s\n" "Setting" "Before" "After" "Status"

    printf "%s+-%s+-%s+-%s\n" "$sep_setting" "$sep_value" "$sep_value" "$sep_status"

    print_row() {
        local setting="$1" current_val="$2" new_val="$3" status="$4"
        printf "%-${max_setting}s| %-${max_value}s| %-${max_value}s| %s\n" "$setting" "$current_val" "$new_val" "$status"
    }

    for setting in $single_settings; do
        local current_value=$(get_current_value "$setting")
        local new_value status
        case "$setting" in
            "rmem_max") new_value="$rmem_max" ;;
            "wmem_max") new_value="$wmem_max" ;;
            "tcp_congestion_control") new_value="$best_congestion" ;;
            "nf_conntrack_max") new_value="$conntrack_max" ;;
            "netdev_max_backlog") new_value="$netdev_backlog" ;;
            "somaxconn") new_value="$somaxconn" ;;
        esac
        local display_current display_new
        case "$setting" in
            "rmem_max"|"wmem_max")
                display_current="$(format_bytes "$current_value")"
                display_new="$(format_bytes "$new_value")"
                ;;
            *)
                display_current="$current_value"
                display_new="$new_value"
                ;;
        esac
        if values_equal "$current_value" "$new_value"; then
            status="Same"
        else
            status="Changed"
            if [ "$current_value" != "unknown" ] && [ "$new_value" != "unknown" ]; then
                case "$setting" in
                    "rmem_max"|"wmem_max"|"netdev_max_backlog"|"somaxconn"|"nf_conntrack_max")
                        if [ "$new_value" -gt "$current_value" ] 2>/dev/null; then
                            status="↑ Increased"
                        elif [ "$new_value" -lt "$current_value" ] 2>/dev/null; then
                            status="↓ Optimized"
                        fi
                        ;;
                esac
            fi
        fi
        print_row "$setting" "$display_current" "$display_new" "$status"
    done

    print_tcp_rows() {
        local name="$1" cur="$2" new="$3"
        if [ "$cur" = "unknown" ]; then
            print_row "${name} (min)"     "unknown" "$(echo "$new" | awk '{print $1}')" "Unknown"
            print_row "${name} (default)" "unknown" "$(echo "$new" | awk '{print $2}')" "Unknown"
            print_row "${name} (max)"     "unknown" "$(echo "$new" | awk '{print $3}')" "Unknown"
            return
        fi
        local c1 c2 c3 n1 n2 n3 s1 s2 s3
        c1=$(echo "$cur" | awk '{print $1}');   n1=$(echo "$new" | awk '{print $1}')
        c2=$(echo "$cur" | awk '{print $2}');   n2=$(echo "$new" | awk '{print $2}')
        c3=$(echo "$cur" | awk '{print $3}');   n3=$(echo "$new" | awk '{print $3}')
        s1="Same"; s2="Same"; s3="Same"
        [ "$c1" != "$n1" ] && s1="Changed"
        [ "$c2" != "$n2" ] && s2="Changed"
        [ "$c3" != "$n3" ] && s3="Changed"
        [ "$n1" -gt "$c1" ] 2>/dev/null && s1="↑ Increased"
        [ "$n1" -lt "$c1" ] 2>/dev/null && s1="↓ Decreased"
        [ "$n2" -gt "$c2" ] 2>/dev/null && s2="↑ Increased"
        [ "$n2" -lt "$c2" ] 2>/dev/null && s2="↓ Decreased"
        [ "$n3" -gt "$c3" ] 2>/dev/null && s3="↑ Increased"
        [ "$n3" -lt "$c3" ] 2>/dev/null && s3="↓ Decreased"
        print_row "${name} (min)"     "$c1" "$n1" "$s1"
        print_row "${name} (default)" "$c2" "$n2" "$s2"
        print_row "${name} (max)"     "$c3" "$n3" "$s3"
    }

    print_tcp_rows "tcp_rmem" "$(get_current_value tcp_rmem)" "$tcp_rmem"
    print_tcp_rows "tcp_wmem" "$(get_current_value tcp_wmem)" "$tcp_wmem"

    printf "%s+-%s+-%s+-%s\n" "$sep_setting" "$sep_value" "$sep_value" "$sep_status"
    print_row "active_connections" "$(get_current_connections)" "$(get_current_connections)" "Same"

    printf '\n'
    printf "Legend:\n"
    printf "  Same        - No change needed\n"
    printf "  ↑ Increased - Value will be increased for better performance\n"
    printf "  ↓ Optimized - Value will be reduced for memory optimization\n"
    printf "  Changed     - Value will be modified\n"
    printf '\n'
}

verify_applied_settings() {
    printf '\n'
    log_info "=== Post-Application Verification ==="
    
    local verification_failed=0
    
    verify_setting() {
        local setting_name="$1"
        local expected_value="$2"
        local actual_value="$3"
        local display_name="$4"
        
        if values_equal "$actual_value" "$expected_value"; then
            log_success "$display_name: $(format_bytes "$actual_value" 2>/dev/null || printf "%s" "$actual_value")"
        else
            log_warning "$display_name: $actual_value (expected: $expected_value)"
            verification_failed=1
        fi
    }
    
    # Verify each setting using the same dynamic fetch method
    verify_setting "rmem_max" "$rmem_max" "$(get_current_value "rmem_max")" "rmem_max"
    verify_setting "wmem_max" "$wmem_max" "$(get_current_value "wmem_max")" "wmem_max"
    verify_setting "netdev_max_backlog" "$netdev_backlog" "$(get_current_value "netdev_max_backlog")" "netdev_max_backlog"
    verify_setting "somaxconn" "$somaxconn" "$(get_current_value "somaxconn")" "somaxconn"
    verify_setting "tcp_rmem" "$tcp_rmem" "$(get_current_value "tcp_rmem")" "tcp_rmem"
    verify_setting "tcp_wmem" "$tcp_wmem" "$(get_current_value "tcp_wmem")" "tcp_wmem"
    
    # Overall result
    if [ "$verification_failed" -eq 0 ]; then
        log_success "All settings verified successfully!"
    else
        log_warning "Some settings may not have been applied correctly"
        printf '\n'
        log_info "This may be due to:"
        printf "  - Kernel module not loaded (e.g., nf_conntrack)\n"
        printf "  - Insufficient permissions\n"
        printf "  - Kernel version compatibility\n"
        printf "  - Hardware limitations\n"
        printf '\n'
        log_info "Running 'dmesg | tail' might provide more information"
    fi
}

show_performance_impact() {
    printf "Performance Impact Summary\n"
    printf '\n'

    mem_mb=$(detect_memory)
    cores=$(detect_cpu_cores)

    printf "System Profile: %dMB RAM, %d CPU cores\n" "$mem_mb" "$cores"
    printf '\n'

    changes_found=0
    improvements=""

    # Check for actual improvements by comparing current vs new values
    current_rmem=$(get_current_value rmem_max)
    current_wmem=$(get_current_value wmem_max)
    current_backlog=$(get_current_value netdev_max_backlog)
    current_somaxconn=$(get_current_value somaxconn)

    if ! values_equal "$current_rmem" "$rmem_max" && [ "$current_rmem" != unknown ] && [ "$current_rmem" -gt 0 ] 2>/dev/null; then
        rmem_impr=$(( (rmem_max - current_rmem) * 100 / current_rmem ))
        if [ "$rmem_impr" -gt 0 ]; then
            improvements="${improvements}Receive buffer: +${rmem_impr}% increase -> Better download performance\n"
            changes_found=1
        elif [ "$rmem_impr" -lt 0 ]; then
            improvements="${improvements}Receive buffer: ${rmem_impr}% decrease -> Memory optimized\n"
            changes_found=1
        fi
    fi

    if ! values_equal "$current_wmem" "$wmem_max" && [ "$current_wmem" != unknown ] && [ "$current_wmem" -gt 0 ] 2>/dev/null; then
        wmem_impr=$(( (wmem_max - current_wmem) * 100 / current_wmem ))
        if [ "$wmem_impr" -gt 0 ]; then
            improvements="${improvements}Send buffer: +${wmem_impr}% increase -> Better upload performance\n"
            changes_found=1
        elif [ "$wmem_impr" -lt 0 ]; then
            improvements="${improvements}Send buffer: ${wmem_impr}% decrease -> Memory optimized\n"
            changes_found=1
        fi
    fi

    if ! values_equal "$current_backlog" "$netdev_backlog" && [ "$current_backlog" != unknown ] && [ "$current_backlog" -gt 0 ] 2>/dev/null; then
        backlog_impr=$(( (netdev_backlog - current_backlog) * 100 / current_backlog ))
        if [ "$backlog_impr" -gt 0 ]; then
            improvements="${improvements}Network backlog: +${backlog_impr}% increase -> Better packet processing\n"
            changes_found=1
        fi
    fi

    if ! values_equal "$current_somaxconn" "$somaxconn" && [ "$current_somaxconn" != unknown ] && [ "$current_somaxconn" -gt 0 ] 2>/dev/null; then
        connq_impr=$(( (somaxconn - current_somaxconn) * 100 / current_somaxconn ))
        if [ "$connq_impr" -gt 0 ]; then
            improvements="${improvements}Connection queue: +${connq_impr}% increase -> More concurrent connections\n"
            changes_found=1
        fi
    fi

    if [ "$changes_found" -eq 1 ]; then
        printf "Performance Improvements:\n"
        printf "%b" "$improvements"
    else
        printf "System is already optimally configured for your hardware\n"
        printf "No significant changes needed\n"
    fi

    printf '\n'
    printf "Expected Benefits:\n"
    printf "  - Reduced packet drops under high load\n"
    printf "  - Better throughput for large file transfers\n"
    printf "  - Improved responsiveness for multiple connections\n"
    printf "  - Optimized memory usage for your hardware\n"
    printf '\n'
}

remove_optimizer() {
    printf "Network Optimizer Removal Tool\n"
    printf "==============================\n"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "No optimization config found"
        return 0
    fi

    printf "Do you want to remove the existing optimization config? (y/N): "
    read -r confirm_remove
    if [ "$confirm_remove" != "y" ] && [ "$confirm_remove" != "Y" ]; then
        log_info "Removal cancelled by user"
        return 0
    fi

    local backup_file=""
    for backup in "${CONFIG_FILE}.backup."*; do
        [ -f "$backup" ] && { backup_file="$backup"; break; }
    done

    if [ -n "$backup_file" ]; then
        log_info "Restoring from backup: $backup_file"
        cp "$backup_file" "$CONFIG_FILE"
        sysctl -p "$CONFIG_FILE" >/dev/null 2>&1
        log_success "Original settings restored"
    else
        log_info "No backup found – removing config file"
        rm "$CONFIG_FILE"
        log_success "Config file removed"
        log_highlight "Reboot required to return to system defaults"
    fi
}

optimizer_main() {
    printf "Dynamic Network Performance Optimizer\n"
    printf "=====================================\n"
  
    if [ -f "$CONFIG_FILE" ]; then
        log_warning "Existing config detected: $CONFIG_FILE"
        remove_optimizer
        exit 0
    fi
    
    printf '\n'
    log_info "=== System Analysis ==="
    local mem_mb=$(detect_memory)
    local cores=$(detect_cpu_cores)
    local best_congestion=$(get_best_congestion_control)
    
    log_info "Detected RAM: ${mem_mb}MB"
    log_info "Detected CPU cores: $cores"
    log_info "Best congestion control: $best_congestion"
    
    calculate_buffer_sizes "$mem_mb" "$cores"
    
    show_comparison
    
    show_performance_impact
    
    printf "Do you want to apply these changes? (y/N): "
    read -r confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        local backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$backup_file"
        log_info "Backed up existing config to: $backup_file"
    fi
    
    log_info "Creating configuration: $CONFIG_FILE"
    cat > "$CONFIG_FILE" << CONFIG_EOF
net.core.rmem_max = $rmem_max
net.core.wmem_max = $wmem_max
net.ipv4.tcp_rmem = $tcp_rmem
net.ipv4.tcp_wmem = $tcp_wmem
net.ipv4.tcp_congestion_control = $best_congestion
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_probes = 3
net.netfilter.nf_conntrack_max = $conntrack_max
net.core.netdev_max_backlog = $netdev_backlog
net.core.somaxconn = $somaxconn
CONFIG_EOF

    printf '\n'
    log_info "Applying configuration"
    if sysctl -p "$CONFIG_FILE" >/dev/null 2>&1; then
        log_success "Configuration applied successfully"
    else
        log_warning "Some settings may have failed (check kernel support)"
    fi
    
    verify_applied_settings
    
    printf '\n'
    log_success "Network optimization completed!"
    log_highlight "Reboot recommended for full effect and persistent changes"
    
    printf '\n'
    log_info "Current memory usage:"
    free -h
}

if [ "$0" = "${0#*/}" ] || [ "${0##*/}" = "$(basename "$0")" ]; then
    optimizer_main "$@"
fi
