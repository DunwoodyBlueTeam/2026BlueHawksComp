#!/usr/bin/env bash
set -euo pipefail

# Dependency check

if ! command -v curl &>/dev/null; then
    echo "[*] curl not found, installing"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y curl
    elif command -v dnf &>/dev/null; then
        dnf install -y curl
    elif command -v yum &>/dev/null; then
        yum install -y curl
    fi
fi

WAZUH_VERSION="4.7"
WAZUH_AGENT_DEB="wazuh-agent_4.7.3-1_amd64.deb"
WAZUH_AGENT_RPM="wazuh-agent-4.7.3-1.x86_64.rpm"
REG_PASSWORD="ja|ZtS72E'&tEQ46=P=B"

#Args

if [[ $# -lt 1 ]]; then
    echo "Usage: sudo bash $0 <MANAGER_IP>"
    exit 1
fi
MANAGER_IP="$1"
echo "[*] Manager IP: ${MANAGER_IP}"

# Detect distro 

if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    echo "[!] Unsupported package manager. Exiting."
    exit 1
fi
echo "[*] Detected package manager: ${PKG_MGR}"

# SECTION 1: ClamAV

echo ""
echo "===== ClamAV Installation ====="

if [[ "$PKG_MGR" == "apt" ]]; then
    apt-get update -qq
    apt-get install -y clamav clamav-daemon
    systemctl stop clamav-freshclam || true
    freshclam || echo "[!] freshclam initial pull failed (may retry on its own)"
    systemctl enable --now clamav-freshclam
    systemctl enable --now clamav-daemon
else
    "$PKG_MGR" install -y clamav clamav-update clamd
    setsebool -P antivirus_can_scan_system 1 2>/dev/null || true
    freshclam || echo "[!] freshclam initial pull failed"
    echo "[*] Detecting ClamAV daemon service"
    CLAMD_SVC="clamd@scan"
    echo "[*] Using forced ClamAV daemon service: $CLAMD_SVC"
    
    sed -i 's/^Example/#Example/' /etc/clamd.d/scan.conf 2>/dev/null || true
    
    sed -i 's/^#LocalSocket/LocalSocket/' /etc/clamd.d/scan.conf 2>/dev/null || \
        { grep -q "^LocalSocket" /etc/clamd.d/scan.conf || echo "LocalSocket /run/clamd.scan/clamd.sock" >> /etc/clamd.d/scan.conf; }
    
    systemctl enable --now "$CLAMD_SVC" || echo "[!] Failed to enable $CLAMD_SVC – check if installed correctly"
    systemctl enable --now clamav-freshclam 2>/dev/null || true
    
    if systemctl is-active --quiet "$CLAMD_SVC"; then
        echo "[✓] ClamAV daemon ($CLAMD_SVC) is now running!"
    else
        echo "[!] ClamAV daemon failed to start. Run 'systemctl status $CLAMD_SVC' for details."
    fi
fi

# Timer
cat > /etc/systemd/system/clamav-scan.service <<'EOF'
[Unit]
Description=ClamAV Full System Scan
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/clamscan --recursive --infected --log=/var/log/clamav/scan.log /
Nice=19
IOSchedulingClass=idle
EOF

cat > /etc/systemd/system/clamav-scan.timer <<'EOF'
[Unit]
Description=Run ClamAV scan hourly

[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=120

[Install]
WantedBy=timers.target
EOF

mkdir -p /var/log/clamav
systemctl daemon-reload
systemctl enable --now clamav-scan.timer

echo "[*] Hourly scan timer enabled."


if command -v clamonacc &>/dev/null; then
    cat > /etc/systemd/system/clamav-onacc.service <<EOF
[Unit]
Description=ClamAV On-Access Scanner
After=clamav-daemon.service
Requires=clamav-daemon.service

[Service]
Type=simple
ExecStart=/usr/bin/clamonacc --fdpass --move=/tmp/quarantine
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /tmp/quarantine
    systemctl daemon-reload
    systemctl enable --now clamav-onacc.service 2>/dev/null || \
        echo "[!] clamonacc failed to start (may need kernel fanotify). Timer scanning still active."
else
    echo "[!] clamonacc not available on this distro. Relying on hourly timer scans."
fi

# Wazuh Agent
echo ""
echo "===== Wazuh Agent Installation ====="

if [[ "$PKG_MGR" == "apt" ]]; then
    cd /tmp
    curl -sO "https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/${WAZUH_AGENT_DEB}"
    WAZUH_MANAGER="${MANAGER_IP}" \
    WAZUH_REGISTRATION_PASSWORD="${REG_PASSWORD}" \
        apt-get install -y "./${WAZUH_AGENT_DEB}"
else
    cd /tmp
    curl -sO "https://packages.wazuh.com/4.x/yum/${WAZUH_AGENT_RPM}"
    WAZUH_MANAGER="${MANAGER_IP}" \
    WAZUH_REGISTRATION_PASSWORD="${REG_PASSWORD}" \
        rpm -ivh "${WAZUH_AGENT_RPM}" || \
    WAZUH_MANAGER="${MANAGER_IP}" \
    WAZUH_REGISTRATION_PASSWORD="${REG_PASSWORD}" \
        "$PKG_MGR" localinstall -y "${WAZUH_AGENT_RPM}"
fi

OSSEC_CONF="/var/ossec/etc/ossec.conf"

echo "[*] Configuring ossec.conf modules"

if grep -q '<syscollector>' "$OSSEC_CONF"; then
    sed -i 's|<syscollector>|<syscollector>\n    <enabled>yes</enabled>|' "$OSSEC_CONF" 2>/dev/null || true
    sed -i '/<syscollector>/,/<\/syscollector>/s|<enabled>no</enabled>|<enabled>yes</enabled>|' "$OSSEC_CONF"
fi

if grep -q '<syscheck>' "$OSSEC_CONF"; then
    sed -i '/<syscheck>/a\
    <directories realtime="yes">/home</directories>\
    <directories realtime="yes">/etc</directories>\
    <directories realtime="yes">/var/www</directories>' "$OSSEC_CONF"
else
    sed -i '/<\/ossec_config>/i\
  <syscheck>\
    <disabled>no</disabled>\
    <directories realtime="yes">/home</directories>\
    <directories realtime="yes">/etc</directories>\
    <directories realtime="yes">/var/www</directories>\
  </syscheck>' "$OSSEC_CONF"
fi

sed -i "s|<address>.*</address>|<address>${MANAGER_IP}</address>|g" "$OSSEC_CONF"

# Start agent
systemctl daemon-reload
systemctl enable --now wazuh-agent

echo ""
echo "===== Done ====="
echo "[*] Wazuh agent enrolled to ${MANAGER_IP}"
echo "[*] Clam daemon active, hourly timer scan enabled"
echo ""
echo "Verification commands:"
echo "  sudo ss -ltnp | grep :3310        # Clam listening"
echo "  sudo systemctl status wazuh-agent  # Agent status"
echo "  sudo systemctl list-timers         # Confirm scan timer"