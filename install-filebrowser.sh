#!/bin/sh

SCRIPT_VERSION="2025.07.28-01-00"

SERVICE_NAME="filebrowser"
INSTALL_DIR="/usr/bin"
CONFIG_DIR="/etc/filebrowser"
DEFAULT_PORT="${DEFAULT_PORT:-8080}"
DEFAULT_ROOT="${DEFAULT_ROOT:-/}"
ARCH=""
USERNAME=${USERNAME:-admin}
PASSWORD=${PASSWORD:-admin12345678}
DEFAULT_LANGUAGE="${DEFAULT_LANGUAGE:-en}"

check_system() {
  if command -v filebrowser >/dev/null 2>&1; then
    printf "\033[1;33mFilebrowser is already installed. Exiting.\033[0m\n"
    remove_filebrowser
    exit 0
  fi
  
  printf "\033[1;34mSystem check completed\033[0m\n"
}

detect_architecture() {
  case "$(uname -m)" in
    aarch64|arm64) ARCH="arm64" ;;
    armv7l)        ARCH="armv7" ;;
    armv6l)        ARCH="armv6" ;;
    armv5l)        ARCH="armv5" ;;
    x86_64|amd64)  ARCH="amd64" ;;
    i386|i686)     ARCH="386" ;;
    riscv64)       ARCH="riscv64" ;;
    *)  
      printf "\033[1;31mUnsupported architecture: %s\033[0m\n" "$(uname -m)"
      printf "\033[1;31mSupported: aarch64, armv7l, armv6l, armv5l, x86_64, i386, riscv64\033[0m\n"
      printf "\033[1;31mFor other architectures, please download manually from:\033[0m\n"
      printf "\033[1;31mhttps://github.com/filebrowser/filebrowser/releases\033[0m\n"
      exit 1
      ;;
  esac
  printf "Detected architecture: %s\n" "$ARCH"
}

install_filebrowser() {
  printf "\033[1;34mDownloading filebrowser\033[0m\n"
  
  CA="--no-check-certificate"
  URL="https://api.github.com/repos/filebrowser/filebrowser/releases/latest"
  
  VER=$( { wget -q -O - "$URL" || wget -q "$CA" -O - "$URL"; } | jsonfilter -e '@.tag_name' )
  
  if [ -z "$VER" ]; then
    printf "\033[1;31mError: Failed to get filebrowser version from GitHub API.\033[0m\n"
    printf "\033[1;31mTrying with hardcoded version v2.27.0\033[0m\n"
    VER="v2.27.0"
  fi
  
  VER=${VER#v}
  
  TAR="linux-${ARCH}-filebrowser.tar.gz"
  URL2="https://github.com/filebrowser/filebrowser/releases/download/v${VER}/${TAR}"
  DEST="/tmp/${TAR}"
  trap 'rm -f "$DEST"' EXIT
  
  printf "Downloading filebrowser v%s for %s\n" "$VER" "$ARCH"
  
  if ! { wget -q -O "$DEST" "$URL2" || wget -q "$CA" -O "$DEST" "$URL2"; }; then
    printf '\033[1;31mDownload failed. Please check network connection.\033[0m\n'
    exit 1
  fi
  
  printf "\033[1;32mFilebrowser v%s downloaded successfully\033[0m\n" "$VER"
  
  cd /tmp || exit 1
  tar -xzf "$TAR" || {
    printf "\033[1;31mFailed to extract filebrowser\033[0m\n"
    exit 1
  }
  
  mv filebrowser "$INSTALL_DIR/" || {
    printf "\033[1;31mFailed to move filebrowser to %s\033[0m\n" "$INSTALL_DIR"
    exit 1
  }
  
  chmod +x "$INSTALL_DIR/filebrowser"
  rm -f "/tmp/${TAR}" /tmp/filebrowser /tmp/README.md /tmp/LICENSE /tmp/CHANGELOG.md

  trap - EXIT
  
  printf "\033[1;32mFilebrowser installed to %s/filebrowser\033[0m\n" "$INSTALL_DIR"
}

create_config() {
  [ ! -d /etc/config ] && mkdir -p /etc/config
  [ ! -f /etc/config/filebrowser ] && touch /etc/config/filebrowser

  if ! uci -q get filebrowser.config.enabled >/dev/null 2>&1; then
    SEC=$(uci -q add filebrowser filebrowser) || return 1
    uci -q rename filebrowser."$SEC"=config
  fi

  uci -q set filebrowser.config.enabled='1'
  uci -q set filebrowser.config.port="$DEFAULT_PORT"
  uci -q set filebrowser.config.root="$DEFAULT_ROOT"
  uci -q set filebrowser.config.address='0.0.0.0'
  uci -q set filebrowser.config.database='/etc/filebrowser/filebrowser.db'
  uci -q set filebrowser.config.log='/var/log/filebrowser.log'
  uci -q set filebrowser.config.username="$USERNAME"
  uci -q set filebrowser.config.password="$PASSWORD"
  uci -q set filebrowser.config.locale="$DEFAULT_LANGUAGE"

  if uci commit filebrowser; then
    printf "\033[1;32mUCI configuration written and committed\033[0m\n"
  else
    printf "\033[1;31mFailed to commit UCI configuration\033[0m\n" >&2
    return 1
  fi
}

create_init_script() {
  printf "\033[1;34mCreating init script\033[0m\n"

  cat > "/etc/init.d/$SERVICE_NAME" << 'EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
PROG=/usr/bin/filebrowser

start_service() {
  procd_open_instance
  USERNAME=$(uci -q get filebrowser.config.username)
  PASSWORD=$(uci -q get filebrowser.config.password)
  PORT=$(uci -q get filebrowser.config.port)
  ROOT=$(uci -q get filebrowser.config.root)
  ADDRESS=$(uci -q get filebrowser.config.address)
  DB=$(uci -q get filebrowser.config.database)
  [ -z "$DB" ] && DB="/etc/filebrowser/filebrowser.db"
  LANG=$(uci -q get filebrowser.config.locale)
  LOGFILE=$(uci -q get filebrowser.config.log)

  mkdir -p /etc/filebrowser
  rm -f "$DB"
  /usr/bin/filebrowser config init --database "$DB" >/dev/null 2>&1
  /usr/bin/filebrowser config set --database "$DB" --root "$ROOT" --address "$ADDRESS" --port "$PORT" --locale "$LANG" --log "$LOGFILE" >/dev/null 2>&1
  /usr/bin/filebrowser users add "$USERNAME" "$PASSWORD" --perm.admin --database "$DB" >/dev/null 2>&1

  procd_set_param command /usr/bin/filebrowser -r "$ROOT" -p "$PORT" -a "$ADDRESS" --database "$DB"
  procd_set_param respawn
  procd_close_instance
}
filebrowser config init --database "$DB"

restart_service() {
  stop_service
  sleep 1
  start_service
}

stop_service() {
    killall filebrowser 2>/dev/null
    sleep 1
    killall -9 filebrowser 2>/dev/null || true
}
EOF

  chmod +x "/etc/init.d/$SERVICE_NAME"
  printf "\033[1;32mInit script created: /etc/init.d/%s\033[0m\n" "$SERVICE_NAME"
}

start_service() {
  printf "\033[1;34mStarting filebrowser service\033[0m\n"
  
  "/etc/init.d/$SERVICE_NAME" enable || {
    printf "\033[1;31mFailed to enable filebrowser service\033[0m\n"
    exit 1
  }
  
  "/etc/init.d/$SERVICE_NAME" start || {
    printf "\033[1;31mFailed to start filebrowser service\033[0m\n"
    exit 1
  }
  
  sleep 2
  
  if pgrep filebrowser >/dev/null; then
    printf "\033[1;32mFilebrowser service started successfully\033[0m\n"
  else
    printf "\033[1;31mFilebrowser service failed to start\033[0m\n"
    exit 1
  fi
}

get_access_info() {
  LAN_IFACE=$(ubus call network.interface.lan status 2>/dev/null | sed -n 's/.*"l3_device":"\([^"]*\)".*/\1/p')
  [ -z "$LAN_IFACE" ] && LAN_IFACE="br-lan"

  ROUTER_IP=$(ip -4 addr show "$LAN_IFACE" 2>/dev/null | awk '/inet / { sub(/\/.*/, "", $2); print $2; exit }')

  USER=$(uci get filebrowser.config.username 2>/dev/null || echo "${USERNAME}")
  PASS=$(uci get filebrowser.config.password 2>/dev/null || echo "${PASSWORD}")
  PORT=$(uci get filebrowser.config.port 2>/dev/null || echo "${DEFAULT_PORT}")

  if [ -n "$ROUTER_IP" ]; then
    printf "\n\033[1;32m=== Filebrowser Access Information ===\033[0m\n"
    printf "\033[1;32mWeb Interface: http://%s:%s/\033[0m\n" "$ROUTER_IP" "$DEFAULT_PORT"
    printf "\033[1;32mUsername: %s\033[0m\n" "$USER"
    printf "\033[1;32mPassword: %s\033[0m\n" "$PASS"
    printf "\033[1;33mIMPORTANT: Change default password after first login!\033[0m\n"
  else
    printf "\033[1;33mWarning: Could not determine router IP address\033[0m\n"
    printf "Access via: http://[ROUTER_IP]:%s/\n" "$DEFAULT_PORT"
    printf "\033[1;32mUsername: %s\033[0m\n" "$USER"
    printf "\033[1;32mPassword: %s\033[0m\n" "$PASS"
  fi
}

remove_filebrowser() {
  local auto_confirm="$1"

  printf "\033[1;34mRemoving filebrowser\033[0m\n"

  if ! command -v filebrowser >/dev/null 2>&1; then
    printf "\033[1;31mFilebrowser not found\033[0m\n"
    return 1
  fi
  printf "Found filebrowser installation\n"

  if [ "$auto_confirm" != "auto" ]; then
    while true; do
      printf "Do you want to remove Filebrowser binary and service? (y/N): "
      read -r confirm
      case "$confirm" in
        [yY]*)
          break
          ;;
        [nN]*)
          printf "\033[1;33mCancelled\033[0m\n"
          return 0
          ;;
        *)
          printf "\033[1;33mInvalid input. Please enter 'y' or 'N'.\033[0m\n"
          ;;
      esac
    done
  else
    printf "\033[1;33mAuto-removing due to installation error\033[0m\n"
  fi

  "/etc/init.d/$SERVICE_NAME" stop    2>/dev/null || true
  "/etc/init.d/$SERVICE_NAME" disable 2>/dev/null || true

  rm -f "$INSTALL_DIR/filebrowser"
  rm -f "/etc/init.d/$SERVICE_NAME"
  rm -f "/etc/config/$SERVICE_NAME"

  printf "\033[1;32mFilebrowser binary and service removed.\033[0m\n"

  if [ "$auto_confirm" != "auto" ]; then
    while true; do
      printf "Do you also want to delete configuration, database and log files? (y/N): "
      read -r cfg_confirm
      case "$cfg_confirm" in
        [yY]*)
          printf "\033[1;34mDeleting config files...\033[0m\n"
          rm -rf "$CONFIG_DIR" /var/log/filebrowser.log /root/.filebrowser.db /root/.filebrowser.log
          break
          ;;
        [nN]*)  
          printf "\033[1;33mKept configuration and database files.\033[0m\n"
          break
          ;;
        *)
          printf "\033[1;33mInvalid input. Please enter 'y' or 'N'.\033[0m\n"
          ;;
      esac
    done
  else
    printf "\033[1;33mAuto-deleting all data files\033[0m\n"
    rm -rf "$CONFIG_DIR" /var/log/filebrowser.log /root/.filebrowser.db /root/.filebrowser.log
  fi

  printf "\033[1;32mFilebrowser removal complete.\033[0m\n"
  exit 0
}

show_usage() {
  printf "Usage: %s [install|remove|status]\n" "$0"
  printf "  install - Install filebrowser\n"
  printf "  remove  - Remove filebrowser\n"
  printf "  status  - Show service status\n"
  printf "  (no args) - Interactive install\n"
}

show_status() {
  if command -v filebrowser >/dev/null 2>&1; then
    printf "\033[1;32mFilebrowser: Installed\033[0m\n"
    filebrowser version 2>/dev/null || printf "Version: Unknown\n"
    
    if pgrep filebrowser >/dev/null; then
      printf "\033[1;32mService: Running\033[0m\n"
    else
      printf "\033[1;31mService: Not running\033[0m\n"
    fi
    
    get_access_info
  else
    printf "\033[1;31mFilebrowser: Not installed\033[0m\n"
  fi
}

filebrowser_main() {
  case "$1" in
    install)
      detect_architecture
      install_filebrowser
      create_config
      create_init_script
      start_service
      get_access_info
      printf "\n\033[1;32mFilebrowser installation completed successfully!\033[0m\n"
      ;;
    remove)
      remove_filebrowser
      ;;
    status)
      show_status
      ;;
    restart)
      restart_service
      ;;
    "")
      check_system
      printf "\033[1;34mFilebrowser Auto Installer for OpenWrt\033[0m\n"
      printf "This will install filebrowser web interface.\n"
      
      while true; do
        printf "Continue? (y/N): "
        read -r confirm
        case "$confirm" in
          [yY]*)
            detect_architecture
            install_filebrowser
            create_config
            create_init_script
            start_service
            get_access_info
            printf "\n\033[1;32mFilebrowser installation completed successfully!\033[0m\n"
            break
            ;;
          [nN]*)
            printf "\033[1;33mInstallation cancelled\033[0m\n"
            exit 0
            ;;
          *)
            printf "\033[1;33mInvalid input. Please enter 'y' or 'N'.\033[0m\n"
            ;;
        esac
      done
      ;;
    *)
      show_usage
      exit 1
      ;;
  esac
}

filebrowser_main "$@"
