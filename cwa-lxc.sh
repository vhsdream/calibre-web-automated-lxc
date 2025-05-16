#!/usr/bin/env bash

# v1.1.1
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
'install'   Installs AutoCaliWeb on a Debian 12 LXC in Proxmox.
'update'    Checks for updates to AutoCaliWeb upstream and applies them to an existing installation.

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
${CLR}${YELLOW}A helper script for AutoCaliWeb in a Proxmox LXC${CLR}
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
#   echo -e "${CLR}${PURPLE}acw${CLR}"
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
OLD_BASE="/app/autocaliweb"
BASE="/opt/acw"
SCRIPTS="$BASE/scripts"
APP="$BASE/cps"
OLD_CONFIG="/config"
CONFIG="/var/lib/acw"
OLD_DB="$OLD_CONFIG/app.db"
DB="$CONFIG/app.db"
OLD_META_TEMP="$OLD_BASE/metadata_temp"
META_TEMP="$CONFIG/metadata_temp"
OLD_META_LOGS="$OLD_BASE/metadata_change_logs"
META_LOGS="$CONFIG/metadata_change_logs"
LIBRARY="calibre-library"
INGEST="acw-book-ingest"
CONVERSION=".acw_conversion_tmp"

# Main functions
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
    unrar-free \
    sqlite3
  msg_done "Dependencies installed!"

  msg_start "Installing Kepubify..."
  mkdir -p /opt/kepubify
  cd /opt/kepubify
  curl -fsSLO https://github.com/pgaskin/kepubify/releases/latest/download/kepubify-linux-64bit &>/dev/null
  chmod +x kepubify-linux-64bit
  ./kepubify-linux-64bit --version | awk '{print substr($2 ,2)}' >/opt/kepubify/version.txt
  msg_done "Installed Kepubify!"

  msg_start "Installing uv..."
  export UV_INSTALL_DIR="/usr/bin"
  $shh bash -c "$(curl -fsSL https://astral.sh/uv/install.sh)"
  msg_done "uv installed!"

  msg_start "Installing Calibre..."
  $shh apt-get install -y calibre --no-install-recommends
  msg_done "Calibre installed!"

  msg_start "Installing AutoCaliWeb..."
  cd /tmp
  RELEASE=$(curl -s https://api.github.com/repos/gelbphoenix/autocaliweb/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  curl -fsSLO "https://github.com/gelbphoenix/autocaliweb/archive/refs/tags/v$RELEASE.zip"
  unzip -q v"$RELEASE".zip
  mv autocaliweb-"$RELEASE"/ "$BASE"
  cd "$BASE"
  uv -q venv venv
  source ./venv/bin/activate
  sed -n "/^goodreads/p; /^jsonschema/p; /^rarfile/,/^pycountry/p" ./optional-requirements.txt >./options.txt
  uv -q pip install -r requirements.txt
  uv -q pip install -r options.txt
  deactivate
  msg_done "AutoCaliWeb installed!"

  msg_start "Starting patching operations..."
  mkdir -p /opt/{"$INGEST","$LIBRARY"}
  mkdir -p /var/lib/acw/{metadata_change_logs,metadata_temp,processed_books,log_archive,.acw_conversion_tmp}
  mkdir -p /var/lib/acw/processed_books/{converted,imported,failed,fixed_originals}
  touch /var/lib/acw/convert-library.log
  curl -fsSL https://github.com/gelbphoenix/autocaliweb/raw/refs/heads/master/library/metadata.db -o /opt/"$LIBRARY"/metadata.db
  sleep 2
  curl -fsSL https://github.com/gelbphoenix/autocaliweb/raw/refs/heads/master/library/app.db -o "$DB"

  # patcher functions
  replacer
  script_generator
  msg_done "Patching operations successful!"

  msg_start "Creating & starting services & timers, confirming a successful start..."
  cat <<EOF >"$BASE"/.env
CONFIG_DIR=/var/lib/acw
CALIBRE_DBPATH=/var/lib/acw
DEFAULT_LOG_FILE=/var/lib/acw/autocaliweb.log
DEFAULT_ACCESS_LOG=/var/lib/acw/access.log
EOF
  cat <<EOF >/etc/systemd/system/cps.service
[Unit]
Description=Calibre-Web Server
After=network.target

[Service]
Type=simple
User=calibre
Group=calibre
WorkingDirectory=/opt/acw
EnvironmentFile=/opt/acw/.env
ExecStart=/opt/acw/venv/bin/python3 /opt/acw/cps.py
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  #   cat <<EOF >/etc/systemd/system/acw-autolibrary.service
  # [Unit]
  # Description=AutoCaliWeb Auto-Library Service
  # After=network.target cps.service
  #
  # [Service]
  # Type=simple
  # User=calibre
  # Group=calibre
  # WorkingDirectory=/opt/acw
  # ExecStart=/opt/acw/venv/bin/python3 /opt/acw/scripts/auto_library.py
  # TimeoutStopSec=10
  # KillMode=process
  # Restart=on-failure
  #
  # [Install]
  # WantedBy=multi-user.target
  # EOF
  cat <<EOF >/etc/systemd/system/acw-ingester.service
[Unit]
Description=AutoCaliWeb Ingest Service
After=network.target cps.service

[Service]
Type=simple
User=calibre
Group=calibre
WorkingDirectory=/opt/acw
ExecStart=/usr/bin/bash -c /opt/acw/scripts/ingest-service.sh
TimeoutStopSec=10
KillMode=mixed
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  cat <<EOF >/etc/systemd/system/acw-change-detector.service
[Unit]
Description=AutoCaliWeb Metadata Change Detector Service
After=network.target cps.service

[Service]
Type=simple
User=calibre
Group=calibre
WorkingDirectory=/opt/acw
ExecStart=/usr/bin/bash -c /opt/acw/scripts/change-detector.sh
TimeoutStopSec=10
KillMode=mixed
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  cat <<EOF >/etc/systemd/system/acw.target
[Unit]
Description=AutoCaliWeb Services
After=network-online.target
Wants=cps.service acw-ingester.service acw-change-detector.service acw-autozip.timer

[Install]
WantedBy=multi-user.target
EOF
  cat <<EOF >/etc/systemd/system/acw-autozip.service
[Unit]
Description=AutoCaliWeb Nightly Auto-Zip Backup Service
After=network.target cps.service

[Service]
Type=simple
User=calibre
Group=calibre
WorkingDirectory=/var/lib/acw/processed_books
ExecStart=/opt/acw/venv/bin/python3 /opt/acw/scripts/auto_zip.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  cat <<EOF >/etc/systemd/system/acw-autozip.timer
[Unit]
Description=AutoCaliWeb Nightly Auto-Zip Backup Timer
RefuseManualStart=no
RefuseManualStop=no

[Timer]
Persistent=true
# run every day at 11:59PM
OnCalendar=*-*-* 23:59:00
Unit=acw-autozip.service

[Install]
WantedBy=timers.target
EOF

  cd "$SCRIPTS"
  chmod +x check-acw-services.sh ingest-service.sh change-detector.sh
  $shh "$BASE"/venv/bin/python3 "$SCRIPTS"/auto_library.py
  echo "v${RELEASE}" >"$BASE"/version.txt
  useradd -r -M -U -s /usr/sbin/nologin -d "$BASE" calibre
  chown -R calibre:calibre "$BASE" "$CONFIG" /opt/{"$INGEST","$LIBRARY",kepubify}
  systemctl -q enable --now acw.target
  $shh apt autoremove
  $shh apt autoclean
  rm -f /tmp/acw.zip
  sleep 3
  local services=("cps" "acw-ingester" "acw-change-detector")
  readarray -t status < <(for service in "${services[@]}"; do
    systemctl is-active "$service" | grep ^active$ -
  done)
  if [[ "${#status[@]}" -eq 3 ]]; then
    msg_done "AutoCaliWeb is live!"
    sleep 1
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    msg_info "Go to ${YELLOW}http://$LOCAL_IP:8083${CLR} to login"
    sleep 2
    msg_info "${PURPLE}Default creds are user: 'admin', password: 'admin123'${CLR}"
    exit 0
  else
    die "Something's not right, please check acw services!"
  fi
}

replacer() {
  cd $BASE
  # Deal with a couple initial modifications
  sed -i "s|\"/$LIBRARY\"|\"/opt/$LIBRARY\"|" dirs.json "$SCRIPTS"/auto_library.py
  sed -i -e "s|\"$OLD_CONFIG/$CONVERSION\"|\"$CONFIG/$CONVERSION\"|" \
    -e "s|\"/$INGEST\"|\"/opt/$INGEST\"|" dirs.json

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
    -e "s|app/ACW_RELEASE|opt/acw/version.txt|g" \
    -e "s|app/KEPUBIFY_RELEASE|opt/kepubify/version.txt|g" \
    -e "s|app/acw_update_notice|opt/.acw_update_notice|g" \
    $APP/admin.py $APP/render_template.py $APP/services/hardcover.py
  sed -i "s|\"$CONFIG/post_request\"|\"$OLD_CONFIG/post_request\"|; s|python3|/opt/acw/venv/bin/python3|g" $APP/acw_functions.py
  sed -i -e "/^# Define user/,/^os.chown/d" -e "/nbp.set_l\|self.set_l/d" -e "/def set_libr/,/^$/d" \
    ./scripts/{convert_library.py,kindle_epub_fixer.py,ingest_processor.py}
  sed -i "/chown/d" "$SCRIPTS"/auto_library.py
}

script_generator() {
  bash -c "cat > /opt/acw/scripts/change-detector.sh" <<-EOF
#!/usr/bin/env bash

echo "========== STARTING METADATA CHANGE DETECTOR ==========="

# Folder to monitor
WATCH_FOLDER="/var/lib/acw/metadata_change_logs"
echo "[metadata-change-detector] Watching folder: \$WATCH_FOLDER"

# Monitor the folder for new files
inotifywait -m -e close_write -e moved_to --exclude '^.*\.(swp)$' "\$WATCH_FOLDER" |
while read -r directory events filename; do
        echo "[metadata-change-detector] New file detected: \$filename"
        /opt/acw/venv/bin/python3 /opt/acw/scripts/cover_enforcer.py "--log" "\$filename"
done
EOF

  bash -c "cat > $SCRIPTS/ingest-service.sh" <<-EOF
#!/usr/bin/env bash

echo "========== STARTING acw-INGEST SERVICE =========="

WATCH_FOLDER=$(grep -o '"ingest_folder": "[^"]*' /opt/acw/dirs.json | grep -o '[^"]*$')
echo "[acw-ingest-service] Watching folder: \$WATCH_FOLDER"

inotifywait -m -r --format="%e %w%f" -e close_write -e moved_to "\$WATCH_FOLDER" |
while read -r events filepath ; do
        echo "[acw-ingest-service] New files detected - \$filepath - Starting Ingest Processor..."
        /opt/acw/venv/bin/python3 /opt/acw/scripts/ingest_processor.py "\$filepath"
done
EOF

  bash -c "cat > $SCRIPTS/check-acw-services.sh" <<-EOF
#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "====== AutoCaliWeb -- Status of Monitoring Services ======"
echo ""

INGESTER_STATUS=\$(systemctl is-active acw-ingester)
METACHANGE_STATUS=\$(systemctl is-active acw-change-detector)

if [ "\$INGESTER_STATUS" = "active" ] ; then
    echo -e "- acw-ingest-service \${GREEN}is running\${NC}"
    is=true
else
    echo -e "- acw-ingest-service \${RED}is not running\${NC}"
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
    echo -e "AutoCaliWeb was \${GREEN}successfully installed \${NC}and \${GREEN}is running properly!\${NC}"
    exit 0
else
    echo -e "AutoCaliWeb was \${RED}not installed successfully\${NC}, please check the logs for more information."
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
*)
  die "Unknown command. Choose 'install' or 'update'."
  ;;
esac
