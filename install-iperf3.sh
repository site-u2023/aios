#!/bin/sh

TMP=/tmp/aios
mkdir -p "$TMP"
cat > "$TMP"/iperf3_setup.sh << 'SCRIPT_END'
#!/bin/sh

# Usage: ./iperf3_setup.sh [start|stop|restart|enable|disable|status|interactive]

SERVICE_FILE="/etc/init.d/iperf3"
PIDFILE="/var/run/iperf3.pid"
LAN="br-lan"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

print_msg() { printf "${1}${2}${NC}\n"; }

get_iface_addrs() {
    local flag=0
    if ip -4 -o addr show dev "$LAN" scope global 2>/dev/null | grep -q 'inet '; then
        NET_ADDR=$(ip -4 -o addr show dev "$LAN" scope global | awk 'NR==1{sub(/\/.*/,"",$4); print $4}')
        flag=$((flag | 1))
    else
        printf "\033[1;33mWarning: No IPv4 address on %s\033[0m\n" "$LAN"
    fi
    
    if ip -6 -o addr show dev "$LAN" scope global 2>/dev/null | grep -q 'inet6 '; then
        NET_ADDR6_LIST=$(ip -6 -o addr show dev "$LAN" scope global | grep -v temporary | awk 'match($4,/^(2|fd|fc)/){sub(/\/.*/,"",$4); print $4;}')
        flag=$((flag | 2))
    else
        printf "\033[1;33mWarning: No IPv6 address on %s\033[0m\n" "$LAN"
    fi
    
    case $flag in
        3) FAMILY_TYPE=any ;;
        1) FAMILY_TYPE=ipv4 ;;
        2) FAMILY_TYPE=ipv6 ;;
        *) FAMILY_TYPE="" ;;
    esac
}

get_lan_ip() {
    get_iface_addrs
    if [ -n "$NET_ADDR" ]; then
        printf "${NET_ADDR}"
    else
        printf "192.168.1.1"
    fi
}

check_package() {
    command -v iperf3 >/dev/null 2>&1 || {
        command -v apk >/dev/null 2>&1 && apk info iperf3 >/dev/null 2>&1
    } || {
        command -v opkg >/dev/null 2>&1 && opkg list-installed | grep -q "^iperf3 "
    }
}

check_service() { [ -f "$SERVICE_FILE" ]; }

install_package(){
  PKGS="iperf3"
  print_msg "$BLUE" "Installing $PKGS package"
  command -v opkg >/dev/null 2>&1 && opkg update >/dev/null 2>&1 && opkg install $PKGS && return 0
  command -v apk  >/dev/null 2>&1 && apk update >/dev/null 2>&1 && apk add $PKGS && return 0
  print_msg "$RED" "No supported package manager found (opkg/apk)"
  return 1
}

create_service() {
    local ip
    ip=$(get_lan_ip)
    print_msg "$BLUE" "Creating iperf3 service for $ip:5201"
    
    cat > "$SERVICE_FILE" << 'SERVICEEOF'
#!/bin/sh /etc/rc.common
START=95
STOP=01
USE_PROCD=1
PROG=/usr/bin/iperf3
pidfile=/var/run/iperf3.pid

start_service() {
    local ip
    ip=$(ip -4 -o addr show dev br-lan scope global 2>/dev/null | awk 'NR==1{sub(/\/.*/,"",$4); print $4}')
    [ -z "$ip" ] && ip="192.168.1.1"
    
    printf "Starting iperf3 server on %s:5201\n" "$ip"
    procd_open_instance
    procd_set_param command "$PROG" --server --daemon --pidfile "$pidfile" --bind "$ip"
    procd_set_param pidfile "$pidfile"
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    printf "Stopping iperf3 server\n"
    [ -f "$pidfile" ] && {
        pid=$(cat "$pidfile" 2>/dev/null)
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && {
            kill "$pid" 2>/dev/null && printf "iperf3 server stopped\n" || {
                printf "Failed to stop iperf3 server (PID: %s)\n" "$pid"; return 1
            }
        }
        rm -f "$pidfile"
    }
}

status() {
    local ip pid
    ip=$(ip -4 -o addr show dev br-lan scope global 2>/dev/null | awk 'NR==1{sub(/\/.*/,"",$4); print $4}')
    [ -z "$ip" ] && ip="192.168.1.1"
    
    [ -f "$pidfile" ] && {
        pid=$(cat "$pidfile" 2>/dev/null)
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && {
            printf "iperf3 server is running (PID: %s) on %s:5201\n" "$pid" "$ip"; return 0
        }
        printf "iperf3 server is not running (stale pidfile)\n"; rm -f "$pidfile"; return 1
    } || { printf "iperf3 server is not running\n"; return 1; }
}
SERVICEEOF
    
    chmod +x "$SERVICE_FILE"
    print_msg "$GREEN" "Service configured for $ip:5201"
}

install_iperf3() {
  print_msg "$BLUE" "Installing iperf3"
  command -v iperf3 >/dev/null 2>&1 || install_package iperf3 || { print_msg "$RED" "Package installation failed"; return 1; }
  [ -f "$SERVICE_FILE" ]   || create_service  || { print_msg "$RED" "Service creation failed";  return 1; }
  print_msg "$GREEN" "Installation completed"
  printf "${CYAN}service iperf3 [enable|start|stop|status]${NC}\n"
  printf "${CYAN}Test: iperf3 -c $(get_lan_ip) -t 10${NC}\n"
}

remove_iperf3() {
    local auto="$1"
    print_msg "$BLUE" "Removing iperf3"
    
    local pkg=false svc=false
    check_package && pkg=true
    check_service && svc=true
    
    [ "$pkg" = "false" ] && [ "$svc" = "false" ] && { print_msg "$RED" "iperf3 not found"; return 1; }
    
    [ "$auto" != "auto" ] && {
        printf "Remove iperf3? (y/N): "
        read -r confirm
        case "$confirm" in 
            [yY]*) ;; 
            *) print_msg "$YELLOW" "Cancelled"; return 0;; 
        esac
    }
    
    [ "$svc" = "true" ] && {
        print_msg "$BLUE" "Removing service"
        service iperf3 stop 2>/dev/null || true
        service iperf3 disable 2>/dev/null || true
        rm -f "$SERVICE_FILE" "$PIDFILE"
        print_msg "$GREEN" "Service removed"
    }
    
    [ "$pkg" = "true" ] && {
        print_msg "$BLUE" "Removing package"
        if command -v apk >/dev/null 2>&1; then
            apk del iperf3 && print_msg "$GREEN" "Package removed" || { print_msg "$RED" "Remove failed"; return 1; }
        elif command -v opkg >/dev/null 2>&1; then
            opkg remove iperf3 && print_msg "$GREEN" "Package removed" || { print_msg "$RED" "Remove failed"; return 1; }
        else
            print_msg "$YELLOW" "Cannot remove package - no package manager"
        fi
    }
    
    print_msg "$GREEN" "Removal completed"
}

show_usage() {
    printf "Usage: %s [command]\n\n" "$0"
    printf "Commands:\n"
    printf "  start       - Start iperf3 service\n"
    printf "  stop        - Stop iperf3 service\n"
    printf "  restart     - Restart iperf3 service\n"
    printf "  enable      - Enable service at boot\n"
    printf "  disable     - Disable service at boot\n"
    printf "  status      - Show service status\n"
    printf "  interactive - Interactive mode (default)\n"
    printf "  help        - Show this help\n\n"
    printf "Note: Install/Uninstall is determined automatically\n"
}

interactive_mode() {
    while true; do
        printf "\n${BLUE}iperf3 Management${NC}\n"

        check_package && pkg=true || pkg=false
        check_service && svc=true || svc=false
        if [ "$svc" = "true" ]; then
            service iperf3 status >/dev/null 2>&1 && running=true || running=false
        else
            running=false
        fi

        if [ "$pkg" = "false" ] || [ "$svc" = "false" ]; then
            printf "[1] Install iperf3\n"
            printf "[2] Exit\n"
            printf "Please select (1-2): "
            read -r choice

            case "$choice" in
                1)
                    install_iperf3
                    ;;
                2)
                    print_msg "$GREEN" "Goodbye"
                    break
                    ;;
                *)
                    printf "${RED}Invalid selection: %s${NC}\n" "$choice"
                    ;;
            esac

        else
            printf "[1] Start service     [5] Disable service\n"
            printf "[2] Stop service      [6] Show status\n"
            printf "[3] Restart service   [7] Remove iperf3\n"
            printf "[4] Enable service    [8] Exit\n"
            printf "Please select (1-8): "
            read -r choice

            case "$choice" in
                1) service iperf3 start;;
                2) service iperf3 stop;;
                3) service iperf3 restart;;
                4)
                    service iperf3 enable
                    print_msg "$GREEN" "Enabled at boot"
                    ;;
                5)
                    service iperf3 disable
                    print_msg "$GREEN" "Disabled at boot"
                    ;;
                6)
                    service iperf3 status
                    ;;
                7)
                    remove_iperf3
                    ;;
                8)
                    print_msg "$GREEN" "Goodbye"
                    break
                    ;;
                *)
                    printf "${RED}Invalid selection: %s${NC}\n" "$choice"
                    ;;
            esac
        fi

        if [ "$choice" != "2" ] && [ "$choice" != "8" ]; then
            printf "\n${CYAN}Press Enter to continue${NC}"
            read -r dummy 2>/dev/null || true
        fi
    done
}

iperf3_main() {
    case "${1:-interactive}" in
        start|stop|restart)
            check_service || {
                print_msg "$RED" "Service not configured. Run script to install."
                exit 1
            }
            service iperf3 "$1"
            ;;

        enable|disable)
            check_service || {
                print_msg "$RED" "Service not configured. Run script to install."
                exit 1
            }
            service iperf3 "$1"
            print_msg "$GREEN" "Service ${1}d at boot"
            ;;

        status)
            check_service || {
                print_msg "$RED" "Service not configured"
                exit 1
            }
            service iperf3 status
            printf "\n${CYAN}Server: $(get_lan_ip):5201${NC}\n"
            printf "${CYAN}Test: iperf3 -c $(get_lan_ip) -t 10${NC}\n"
            ;;

        interactive)
            interactive_mode
            ;;

        auto-toggle)
            if check_package || check_service; then
                remove_iperf3
            else
                install_iperf3
            fi
            ;;

        help|-h|--help)
            show_usage
            ;;

        *)
            print_msg "$RED" "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

[ "${0##*/}" = "iperf3_setup.sh" ] && iperf3_main "$@"
SCRIPT_END

chmod +x "$TMP"/iperf3_setup.sh
printf "\n${GREEN}=== iperf3 Setup Script Created ===${NC}\n"
printf "${CYAN}Location: $TMP/iperf3_setup.sh${NC}\n"
printf "${YELLOW}Usage: $TMP/iperf3_setup.sh [start|stop|status|help]${NC}\n"
printf "${YELLOW}Interactive: $TMP/iperf3_setup.sh${NC}\n"

printf "\n${BLUE}Running script in interactive mode${NC}\n"
sh "$TMP"/iperf3_setup.sh
