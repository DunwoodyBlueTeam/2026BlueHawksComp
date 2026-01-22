#!/bin/bash
# ============================================================
# linuxUF_fedora42_linuxlogs.sh
# Fedora 42 UF install && config.
# Sends logs to Splunk index: linuxlogs
# Forwards to <SPLUNK_IP>:9997
# ============================================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Run as root: sudo ./linuxUF_fedora42_linuxlogs.sh"
  exit 1
fi

echo "Enter Splunk Enterprise (Indexer) IP:"
read -r SPLUNK_IP
[ -z "$SPLUNK_IP" ] && echo "[ERROR] Splunk IP cannot be empty." && exit 1

echo "Create a local Splunk UF admin username (example: admin):"
read -r SPLUNK_ADMIN_USER
[ -z "$SPLUNK_ADMIN_USER" ] && echo "[ERROR] Username cannot be empty." && exit 1

echo "Create a local Splunk UF admin password (input hidden):"
read -rs SPLUNK_ADMIN_PASS; echo
echo "Confirm password:"
read -rs SPLUNK_ADMIN_PASS_CONFIRM; echo
[ "$SPLUNK_ADMIN_PASS" != "$SPLUNK_ADMIN_PASS_CONFIRM" ] && echo "[ERROR] Passwords do not match." && exit 1

UF_PKG="splunkforwarder-9.1.0-1c86ca0bacc3-Linux-x86_64.tgz"
UF_URL="https://download.splunk.com/products/universalforwarder/releases/9.1.0/linux/${UF_PKG}"
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_REC_PORT="9997"

# ---------- Index = linuxlogs -> MAKE SURE THIS WAS ADDED ON ENTERPRISE ----------
SPLUNK_INDEX="linuxlogs"

echo "[*] Downloading UF..."
cd /tmp
wget -q --show-progress -O "$UF_PKG" "$UF_URL"

echo "[*] Installing UF..."
tar -xzf "$UF_PKG" -C /opt

echo "[*] Seeding UF admin user..."
USERSEED_DIR="$SPLUNK_HOME/etc/system/local"
mkdir -p "$USERSEED_DIR"
cat > "$USERSEED_DIR/user-seed.conf" <<EOF
[user_info]
USERNAME = $SPLUNK_ADMIN_USER
PASSWORD = $SPLUNK_ADMIN_PASS
EOF
chmod 600 "$USERSEED_DIR/user-seed.conf"

echo "[*] Starting UF..."
"$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt

echo "[*] Writing inputs.conf (Fedora 42) → index=${SPLUNK_INDEX}..."
INPUTS_FILE="$SPLUNK_HOME/etc/system/local/inputs.conf"

# Helper: only add a monitor if the file exists 
add_monitor_if_exists () {
  local path="$1"
  local st="$2"
  if [ -f "$path" ]; then
    cat >> "$INPUTS_FILE" <<EOF

[monitor://$path]
disabled = false
index = ${SPLUNK_INDEX}
sourcetype = $st
EOF
    echo "[OK] Monitoring $path"
  else
    echo "[SKIP] Missing $path"
  fi
}

# Start fresh
cat > "$INPUTS_FILE" <<EOF
# ========= CCDC Fedora 42 UF Inputs =========
# All data goes to index: ${SPLUNK_INDEX}
EOF

# Auth/system (Fedora often uses /var/log/secure when rsyslog is writing)
add_monitor_if_exists "/var/log/secure" "linux_secure"
add_monitor_if_exists "/var/log/messages" "messages"

# Package log
add_monitor_if_exists "/var/log/dnf.log" "linux_dnf"

# Mail logs
add_monitor_if_exists "/var/log/maillog" "linux_mail"
add_monitor_if_exists "/var/log/mail.log" "linux_mail"

# Web logs (nginx or apache)
add_monitor_if_exists "/var/log/nginx/access.log" "nginx_access"
add_monitor_if_exists "/var/log/nginx/error.log" "nginx_error"
add_monitor_if_exists "/var/log/httpd/access_log" "apache_access"
add_monitor_if_exists "/var/log/httpd/error_log" "apache_error"

chmod 600 "$INPUTS_FILE"
echo "[OK] inputs.conf written"

echo "[*] Setting forward-server to ${SPLUNK_IP}:${SPLUNK_REC_PORT}..."
"$SPLUNK_HOME/bin/splunk" add forward-server "${SPLUNK_IP}:${SPLUNK_REC_PORT}" \
  -auth "${SPLUNK_ADMIN_USER}:${SPLUNK_ADMIN_PASS}"

echo "[*] Enabling boot-start..."
"$SPLUNK_HOME/bin/splunk" enable boot-start || true

echo "[*] Restarting UF..."
"$SPLUNK_HOME/bin/splunk" restart

echo "[*] UF status:"
"$SPLUNK_HOME/bin/splunk" status || true

echo "[DONE] Fedora 42 UF forwarding to ${SPLUNK_IP}:${SPLUNK_REC_PORT} with index=${SPLUNK_INDEX}"
