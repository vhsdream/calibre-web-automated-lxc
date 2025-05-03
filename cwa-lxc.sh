#!/usr/bin/env bash

# v1.0.0
# Copyright 2025
# Author: vhsdream
# License: GNU GPL

set -Eeuo pipefail
trap 'catch $LINENO "$BASH_COMMAND"' SIGINT SIGTERM ERR
verbose=0
BLING_PID=""

usage() {
  header
  cat <<EOF
Functions:
'install'   Installs Calibre-Web Automated on a Debian 12 LXC in Proxmox.
'features'  Opens a features menu to add additional features.
'update'    Checks for updates to Calibre-Web Automated upstream and applies them to an existing installation.

Available options:
-h, --help      Print this help and exit
-v, --verbose   Print the script standardout to the screen
--no-color      Disable colours

This script is similar to those found in the Proxmox Helper Scripts repo, with the main difference being that you need to run this in a Proxmox LXC you have created yourself.

Usage: bash $(basename "${BASH_SOURCE[0]}") [-h] [-v] [--no-color] [install|update]

EOF
  exit
}

header() {
  t_width=$(tput cols 2>/dev/null)
  if [[ "$t_width" -gt 90 ]]; then
    echo -e "$(
      cat <<EOF
        ${CYAN}
                                         ▄▄▄▄
                                         ▀▀██
  ▄█████▄ ██      ██  ▄█████▄              ██      ▀██  ██▀   ▄█████▄
 ██▀    ▀ ▀█  ██  █▀  ▀ ▄▄▄██              ██        ████    ██▀    ▀
 ██        ██▄██▄██  ▄██▀▀▀██   █████      ██        ▄██▄    ██
 ▀██▄▄▄▄█  ▀██  ██▀  ██▄▄▄███              ██▄▄▄    ▄█▀▀█▄   ▀██▄▄▄▄█
   ▀▀▀▀▀    ▀▀  ▀▀    ▀▀▀▀ ▀▀               ▀▀▀▀   ▀▀▀  ▀▀▀    ▀▀▀▀▀
${CLR}${YELLOW}A helper script for Calibre-Web Automated in a Proxmox LXC${CLR}
EOF
    )"
  fi
}

# Handling output suppression
set_verbosity() {
  if [ "$verbose" -eq 1 ]; then
    shh=""
  else
    shh="silent_running"
  fi
}
silent_running() {
  "$@" >/dev/null 2>&1
}
set_verbosity

# Colour handling
setup_colours() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    CLR='\033[0m' GREEN='\033[0;32m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m' RED='\033[0;31m'
  else
    CLR='' GREEN='' PURPLE='' CYAN='' YELLOW='' RED=''
  fi
}
setup_colours

# Flash and bling
# app() {
#   echo -e "${CLR}${PURPLE}cwa${CLR}"
# }

bling() {
  local frames=('▹▹▹▹▹' '▸▹▹▹▹' '▹▸▹▹▹' '▹▹▸▹▹' '▹▹▹▸▹' '▹▹▹▹▸')
  local arrow_i=0
  local interval=0.1
  printf "\e[?25l"

  while true; do
    printf "\r${PURPLE}%s${CLR}" "${frames[arrow_i]}"
    arrow_i=$(((arrow_i + 1) % ${#frames[@]}))
    sleep "$interval"
  done
}

msg_start() {
  printf "       "
  echo >&1 -ne "${CYAN}${1-}${CLR}"
  bling &
  BLING_PID=$!
}

msg_done() {
  if [[ -n "$BLING_PID" ]] && ps -p "$BLING_PID" >/dev/null; then kill "$BLING_PID" >/dev/null; fi
  printf "\e[?25h"
  local msg="${1-}"
  echo -e "\r"
  echo >&1 -e "${GREEN}Done ✔ ${msg}${CLR}"
}

msg_info() {
  if [[ -n "$BLING_PID" ]] && ps -p "$BLING_PID" >/dev/null; then kill "$BLING_PID" >/dev/null; fi
  printf "\e[?25h"
  echo >&1 -e "${1-}\r"
}

# Exception and error handling
msg_err() {
  if [[ -n "$BLING_PID" ]] && ps -p "$BLING_PID" >/dev/null; then kill "$BLING_PID" >/dev/null; fi
  printf "\e[?25h"
  echo >&2 -e "${RED}${1-}${CLR}"
}

die() {
  local err=$1
  local code=${2-1}
  msg_err "$err"
  exit "$code"
}

catch() {
  local code=$?
  local line=$1
  local command=$2
  printf "\e[?25h"
  msg_err "Caught error in line $line: exit code $code: while executing $command"
}

parse_params() {
  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) verbose=1 && set_verbosity ;;
    --no-color) NO_COLOR=1 ;;
    -?*) die "Unknown flag: $1. Use -h|--help for help" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")
  [[ ${#args[@]} -eq 0 ]] && die "Missing script arguments. Use -h|--help for help"
  return 0
}
parse_params "$@"

# Global vars
OLD_BASE="/app/calibre-web-automated"
BASE="/opt/cwa"
SCRIPTS="$BASE/scripts"
APP="$BASE/root/app/calibre-web/cps"
OLD_CONFIG="/config"
CONFIG="/var/lib/cwa"
OLD_DB="$OLD_CONFIG/app.db"
DB="/opt/calibre-web/.calibre-web/app.db"
OLD_META_TEMP="$OLD_BASE/metadata_temp"
META_TEMP="$CONFIG/metadata_temp"
OLD_META_LOGS="$OLD_BASE/metadata_change_logs"
META_LOGS="$CONFIG/metadata_change_logs"
INGEST="cwa-book-ingest"
CONVERSION=".cwa_conversion_tmp"

# Main functions
features() {
  header
  msg_info "Features"
  msg_info "-----------------------------"
  msg_info "1) Enable SSHFS support"
  msg_info "q) Quit"
  echo

  read -rp "Choose a feature to install [1/q]: " choice
  case "$choice" in
    1)
      enable_sshfs
      ;;
    q | Q)
      msg_info "Quitting."
      exit 0
      ;;
    *)
      msg_error "Invalid option"
      sleep 1
      features
      ;;
  esac
}

# Function to enable SSHFS support
enable_ssh_fs() {

    # Default Configuration for sshfs-feature (suggested values)
    DEFAULT_REMOTE_USER="someUser"                     # Remote user on the remote host
    DEFAULT_REMOTE_HOST="someIP"                       # IP or hostname of the remote server
    DEFAULT_REMOTE_PATH="someRemotePath"               # Path to the remote folder
    DEFAULT_LOCAL_MOUNT="/mnt/cwa_share"
    DEFAULT_SSH_KEY_PATH="/root/.ssh/id_rsa_cwa_share" # Path to the private SSH key (custom name)
    
    # Check if the script is being run as root
    if [[ $EUID -ne 0 ]]; then
        msg_error "This script must be run as root!"
        exit 1
    fi

    # Prompt the user to confirm if FUSE is enabled
    read -p "Is FUSE enabled in this container? (y/n): " fuse_enabled

    if [[ "$fuse_enabled" != "y" && "$fuse_enabled" != "Y" ]]; then
        msg_error "Please ensure that FUSE is enabled in the container and try again."
        msg_info "You can enable FUSE in the Proxmox LXC container options (features: fuse)."
        exit 1
    else
        msg_info "FUSE is enabled. Proceeding with setup..."
    fi

    # Ask if the user wants to adjust the configuration values
    read -p "Do you want to adjust the default configuration values? (y/n): " adjust_config
    if [[ "$adjust_config" == "y" || "$adjust_config" == "Y" ]]; then
        msg_info "You will be prompted to adjust the following configuration parameters."
        
        # Get user input for each configuration variable
        REMOTE_USER=$(get_input "Enter the remote user" "$DEFAULT_REMOTE_USER")
        REMOTE_HOST=$(get_input "Enter the remote host (IP or hostname)" "$DEFAULT_REMOTE_HOST")
        REMOTE_PATH=$(get_input "Enter the path to the remote folder" "$DEFAULT_REMOTE_PATH")
        LOCAL_MOUNT=$(get_input "Enter the local mount point" "$DEFAULT_LOCAL_MOUNT")
        SSH_KEY_PATH=$(get_input "Enter the path to the SSH private key" "$DEFAULT_SSH_KEY_PATH")
    else
        # Use default values if the user doesn't want to adjust them
        REMOTE_USER="$DEFAULT_REMOTE_USER"
        REMOTE_HOST="$DEFAULT_REMOTE_HOST"
        REMOTE_PATH="$DEFAULT_REMOTE_PATH"
        LOCAL_MOUNT="$DEFAULT_LOCAL_MOUNT"
        SSH_KEY_PATH="$DEFAULT_SSH_KEY_PATH"
        msg_info "Using default configuration values."
    fi

    # Confirm the selected configuration
    msg_info "\nThe following configuration will be used:"
    msg_info "Remote User: $REMOTE_USER"
    msg_info "Remote Host: $REMOTE_HOST"
    msg_info "Remote Path: $REMOTE_PATH"
    msg_info "Local Mount: $LOCAL_MOUNT"
    msg_info "SSH Key Path: $SSH_KEY_PATH"

    # Ask for confirmation before proceeding
    read -p "Do you want to proceed with this configuration? (y/n): " proceed
    if [[ "$proceed" != "y" && "$proceed" != "Y" ]]; then
        msg_info "Exiting the script. No changes were made."
        exit 1
    fi
}



install() {
  header
  sleep 2 && msg_start "Updating system..."
  $shh apt-get update
  $shh apt-get dist-upgrade -y
  msg_done "System updated!"
  msg_start "Installing Dependencies..."
  $shh apt-get install -y \
    curl \
    sudo \
    build-essential \
    imagemagick \
    libldap2-dev \
    libsasl2-dev \
    ghostscript \
    libldap-2.5-0 \
    libmagic1 \
    libsasl2-2 \
    libxi6 \
    libxslt1.1 \
    xdg-utils \
    inotify-tools \
    zip \
    unzip \
    sqlite3
  msg_done "Dependencies installed!"

  msg_start "Installing Kepubify..."
  mkdir -p /opt/kepubify
  cd /opt/kepubify
  curl -fsSLO https://github.com/pgaskin/kepubify/releases/latest/download/kepubify-linux-64bit &>/dev/null
  chmod +x kepubify-linux-64bit
  ./kepubify-linux-64bit --version | awk '{print substr($2 ,2)}' >/opt/kepubify/version.txt
  msg_done "Installed Kepubify!"

  msg_start "Installing uv & creating virtualenv..."
  export UV_INSTALL_DIR="/usr/bin"
  $shh bash -c "$(curl -fsSL https://astral.sh/uv/install.sh)"
  uv -q venv /opt/venv
  msg_done "uv installed, venv created!"

  msg_start "Installing Calibre..."
  $shh apt-get install -y calibre --no-install-recommends
  msg_done "Calibre installed!"

  msg_start "Installing Calibre-Web..."
  mkdir -p /opt/calibre-web
  wget -q https://github.com/janeczku/calibre-web/raw/master/library/metadata.db -P /opt/calibre-web
  cd /opt/calibre-web
  source /opt/venv/bin/activate
  uv -q pip install calibreweb[goodreads,metadata,kobo]
  uv -q pip list | grep calibreweb | awk '{print $2}' >/opt/calibre-web/calibreweb_version.txt
  msg_done "Installed Calibre-Web!"

  # Create calibre user
  useradd -U -s /usr/sbin/nologin -M -d /opt/calibre-web calibre
  chown -R calibre:calibre /opt/{venv,calibre-web}

  # Create service file
  cat <<EOF >/etc/systemd/system/cps.service
  [Unit]
  Description=Calibre-Web Server
  After=network.target

  [Service]
  Type=simple
  User=calibre
  Group=calibre
  WorkingDirectory=/opt/calibre-web
  ExecStart=/opt/venv/bin/cps
  TimeoutStopSec=20
  KillMode=process
  Restart=on-failure

  [Install]
  WantedBy=multi-user.target
EOF

  msg_start "Starting and then stopping Calibre-Web Service..."
  # necessary otherwise the patching operation will fail
  systemctl start cps && sleep 5 && systemctl stop cps
  msg_done "Calibre-Web Service successfully cycled."

  msg_start "Installing Calibre-Web Automated..."
  cd /tmp
  RELEASE=$(curl -s https://api.github.com/repos/crocodilestick/Calibre-Web-Automated/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  wget -q "https://github.com/crocodilestick/Calibre-Web-Automated/archive/refs/tags/V$RELEASE.zip" -O cwa.zip
  unzip -q cwa.zip
  mv Calibre-Web-Automated-"$RELEASE"/ /opt/cwa
  cd /opt/cwa
  uv -q pip install -r requirements.txt
  deactivate
  msg_done "Calibre-Web Automated installed!"

  msg_start "Starting patching operations..."
  mkdir -p /opt/cwa-book-ingest
  mkdir -p /var/lib/cwa/{metadata_change_logs,metadata_temp,processed_books,log_archive,.cwa_conversion_tmp}
  mkdir -p /var/lib/cwa/processed_books/{converted,imported,failed,fixed_originals}
  touch /var/lib/cwa/convert-library.log

  # patcher functions
  replacer
  script_generator
  chown -R calibre:calibre "$BASE" "$CONFIG" /opt/{"$INGEST",kepubify,calibre-web,venv}
  msg_done "Patching operations successful!"

  msg_start "Creating & starting services & timers, confirming a successful start..."
  cat <<EOF >/etc/systemd/system/cwa-autolibrary.service
  [Unit]
  Description=Calibre-Web Automated Auto-Library Service
  After=network.target cps.service

  [Service]
  Type=simple
  User=calibre
  Group=calibre
  WorkingDirectory=/opt/cwa
  ExecStart=/opt/venv/bin/python3 /opt/cwa/scripts/auto_library.py
  TimeoutStopSec=10
  KillMode=process
  Restart=on-failure

  [Install]
  WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/cwa-ingester.service
  [Unit]
  Description=Calibre-Web Automated Ingest Service
  After=network.target cps.service cwa-autolibrary.service

  [Service]
  Type=simple
  User=calibre
  Group=calibre
  WorkingDirectory=/opt/cwa
  ExecStart=/usr/bin/bash -c /opt/cwa/scripts/ingest-service.sh
  TimeoutStopSec=10
  KillMode=mixed
  Restart=on-failure

  [Install]
  WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/cwa-change-detector.service
  [Unit]
  Description=Calibre-Web Automated Metadata Change Detector Service
  After=network.target cps.service cwa-autolibrary.service

  [Service]
  Type=simple
  User=calibre
  Group=calibre
  WorkingDirectory=/opt/cwa
  ExecStart=/usr/bin/bash -c /opt/cwa/scripts/change-detector.sh
  TimeoutStopSec=10
  KillMode=mixed
  Restart=on-failure

  [Install]
  WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/cwa.target
  [Unit]
  Description=Calibre-Web Automated Services
  After=network-online.target
  Wants=cps.service cwa-autolibrary.service cwa-ingester.service cwa-change-detector.service cwa-autozip.timer

  [Install]
  WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/cwa-autozip.service
  [Unit]
  Description=Calibre-Web Automated Nightly Auto-Zip Backup Service
  After=network.target cps.service

  [Service]
  Type=simple
  User=calibre
  Group=calibre
  WorkingDirectory=/var/lib/cwa/processed_books
  ExecStart=/opt/venv/bin/python3 /opt/cwa/scripts/auto_zip.py
  Restart=on-failure

  [Install]
  WantedBy=multi-user.target
EOF

  cat <<EOF >/etc/systemd/system/cwa-autozip.timer
  [Unit]
  Description=Calibre-Web Automated Nightly Auto-Zip Backup Timer
  RefuseManualStart=no
  RefuseManualStop=no

  [Timer]
  Persistent=true
  # run every day at 11:59PM
  OnCalendar=*-*-* 23:59:00
  Unit=cwa-autozip.service

  [Install]
  WantedBy=timers.target
EOF

  cd scripts
  chmod +x check-cwa-services.sh ingest-service.sh change-detector.sh
  echo "V${RELEASE}" >/opt/cwa/version.txt
  systemctl -q enable --now cwa.target
  $shh apt autoremove
  $shh apt autoclean
  rm -f /tmp/cwa.zip
  sleep 3
  local services=("cps" "cwa-ingester" "cwa-change-detector")
  local status=""
  status=$(for service in "${services[@]}"; do
    systemctl is-active "$service" | grep active -
  done)
  if [[ "$status" ]]; then
    msg_done "Calibre-Web Automated is live!"
    sleep 1
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    msg_info "Go to ${YELLOW}http://$LOCAL_IP:8083${CLR} to login"
    sleep 2
    msg_info "${PURPLE}Default creds are user: 'admin', password: 'admin123'${CLR}"
    exit 0
  else
    die "Something's not right, please check CWA services!"
  fi
}

replacer() {
  cd $BASE
  # Deal with a couple initial modifications
  sed -i "s|\"/calibre-library\"| \"/opt/calibre-web\"|" dirs.json ./scripts/auto_library.py
  sed -i -e "s|\"$OLD_CONFIG/$CONVERSION\"| \"$CONFIG/$CONVERSION\"|" \
    -e "s|\"/$INGEST\"| \"/opt/$INGEST\"|" dirs.json

  # Gather list of Python scripts to be iterated
  FILES=$(find ./scripts "$APP" -type f -name "*.py" -or -name "*.html")
  # Create two arrays containing the paths to be modified
  OLD_PATHS=("$OLD_META_TEMP" "$OLD_META_LOGS" "$OLD_DB" "$OLD_BASE" "$OLD_CONFIG")
  NEW_PATHS=("$META_TEMP" "$META_LOGS" "$DB" "$BASE" "$CONFIG")

  # Loop over each file; if the old paths are there, then replace using sed
  for file in $FILES; do
    for ((path = 0; path < ${#OLD_PATHS[@]}; path++)); do
      if grep -q "${OLD_PATHS[path]}" "$file"; then
        sed -i "s|${OLD_PATHS[path]}|${NEW_PATHS[path]}|g" "$file"
      fi
    done
  done

  # Deal with edge case(s)
  sed -i -e "s|\"/admin$CONFIG\"|\"/admin$OLD_CONFIG\"|" \
    -e "s|app/LSCW_RELEASE|opt/calibre-web/calibreweb_version.txt|g" \
    -e "s|app/CWA_RELEASE|opt/cwa/version.txt|g" \
    -e "s/lscw_version/calibreweb_version/g" \
    -e "s|app/KEPUBIFY_RELEASE|opt/kepubify/version.txt|g" \
    -e "s|app/cwa_update_notice|opt/.cwa_update_notice|g" \
    $APP/admin.py $APP/render_template.py
  sed -i "s|\"$CONFIG/post_request\"|\"$OLD_CONFIG/post_request\"|" $APP/cwa_functions.py
  sed -i -e "/^# Define user/,/^os.chown/d" -e "/nbp.set_l\|self.set_l/d" -e "/def set_libr/,/^$/d" \
    ./scripts/{convert_library.py,kindle_epub_fixer.py,ingest_processor.py}
  sed -i "/chown/d" ./scripts/auto_library.py
  sed -i -n '/Linuxserver.io/{x;d;};1h;1!{x;p;};${x;p;}' $APP/templates/admin.html &&
    sed -i -e "/Linuxserver.io/,+3d" \
      -e "s/commit/calibreweb_version/" $APP/templates/admin.html

  # patch the calibre-web python libs in the virtualenv
  cp -r /opt/cwa/root/app/calibre-web/cps/* /opt/venv/lib/python3*/site-packages/calibreweb/cps
}

script_generator() {
  bash -c "cat > /opt/cwa/scripts/change-detector.sh" <<-EOF
#!/usr/bin/env bash

echo "========== STARTING METADATA CHANGE DETECTOR ==========="

# Folder to monitor
WATCH_FOLDER="/var/lib/cwa/metadata_change_logs"
echo "[metadata-change-detector] Watching folder: \$WATCH_FOLDER"

# Monitor the folder for new files
inotifywait -m -e close_write -e moved_to --exclude '^.*\.(swp)$' "\$WATCH_FOLDER" |
while read -r directory events filename; do
        echo "[metadata-change-detector] New file detected: \$filename"
        /opt/venv/bin/python3 /opt/cwa/scripts/cover_enforcer.py "--log" "\$filename"
done
EOF

  bash -c "cat > $SCRIPTS/ingest-service.sh" <<-EOF
#!/usr/bin/env bash

echo "========== STARTING CWA-INGEST SERVICE =========="

WATCH_FOLDER=$(grep -o '"ingest_folder": "[^"]*' /opt/cwa/dirs.json | grep -o '[^"]*$')
echo "[cwa-ingest-service] Watching folder: \$WATCH_FOLDER"

inotifywait -m -r --format="%e %w%f" -e close_write -e moved_to "\$WATCH_FOLDER" |
while read -r events filepath ; do
        echo "[cwa-ingest-service] New files detected - \$filepath - Starting Ingest Processor..."
        /opt/venv/bin/python3 /opt/cwa/scripts/ingest_processor.py "\$filepath"
done
EOF

  bash -c "cat > $SCRIPTS/check-cwa-services.sh" <<-EOF
#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "====== Calibre-Web Automated -- Status of Monitoring Services ======"
echo ""

INGESTER_STATUS=\$(systemctl is-active cwa-ingester)
METACHANGE_STATUS=\$(systemctl is-active cwa-change-detector)

if [ "\$INGESTER_STATUS" = "active" ] ; then
    echo -e "- cwa-ingest-service \${GREEN}is running\${NC}"
    is=true
else
    echo -e "- cwa-ingest-service \${RED}is not running\${NC}"
    is=false
fi

if [ "\$METACHANGE_STATUS" = "active" ]; then
    echo -e "- metadata-change-detector \${GREEN}is running\${NC}"
    mc=true
else
    echo -e "- metadata-change-detector \${RED}is not running\${NC}"
    mc=false
fi

echo ""

if \$is && \$mc; then
    echo -e "Calibre-Web-Automated was \${GREEN}successfully installed \${NC}and \${GREEN}is running properly!\${NC}"
    exit 0
else
    echo -e "Calibre-Web-Automated was \${RED}not installed successfully\${NC}, please check the logs for more information."
    if [ "\$is" = true ] && [ "\$mc" = false ] ; then
        exit 1
    elif [ "\$is" = false ] && [ "\$mc" = true ] ; then
        exit 2
    else
        exit 3
    fi
fi
EOF
}

update() {
  msg_info "${RED}Sorry, I lied, updating is not yet implemented!${CLR}"
}

[ "$(id -u)" -ne 0 ] && die "This script requires root privileges. Please run with sudo or as the root user."

case "${args[0]}" in
install)
  install
  ;;
update)
  update
  ;;
features) 
  features 
  ;;  
*)
  die "Unknown command. Choose 'install' or 'update'."
  ;;
esac
