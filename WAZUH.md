# Wazuh Deployment

### Manager

```bash
sudo git clone -b linux https://github.com/DunwoodyBlueTeam/2026BlueHawksComp.git
cd 2026BlueHawksComp
sudo chmod +x *.sh
sudo bash 01-manager-setup.sh
```

Note the manager IP it detects. You will need it for every agent.

**Linux agents**

```bash
# SCP or curl the script to each box, then:
sudo curl -sO https://raw.githubusercontent.com/DunwoodyBlueTeam/2026BlueHawksComp/Linux/02-linux-agent.sh
sudo bash 02-linux-agent.sh <MANAGER_IP>
```

**Windows agents**
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DunwoodyBlueTeam/2026BlueHawksComp/windows/03-windows-agent.ps1" -OutFile "C:\03-windows-agent.ps1"
Set-ExecutionPolicy Bypass -Scope Process -Force
C:\03-windows-agent.ps1 -ManagerIP "<MANAGER_IP>"
```


1. Open the Wazuh dashboard at `https://<MANAGER_IP>:443`
2. Log in with the admin credentials printed by the manager script
3. Navigate to Agents -- all 7 should show green

## Troubleshooting

**Agent not showing in dashboard:**
- Check agent can reach manager: `curl -k https://<MANAGER_IP>:1514` (will error, but should connect)
- Check firewall rules on Palo Alto / Cisco FTD for ports 1514 (agent enrollment) and 1515 (agent comms)
- Restart agent: `systemctl restart wazuh-agent` or `Restart-Service WazuhSvc`

**Clam not listening on 3310:**
- Check `clamd.conf` has `TCPSocket 3310` and `TCPAddr 127.0.0.1` (or `LocalSocket`)
- On RHEL-family: check `/etc/clamd.d/scan.conf`, remove the `Example` line

**Agents behind different firewalls:**
- Linux agents (172.20.242.x) are behind Palo Alto, Windows agents (172.20.240.x) are behind Cisco FTD
- Manager is on the Linux side (172.20.242.x DHCP), so Windows agents cross firewall boundaries
- Make sure routing and firewall rules allow 172.20.240.x -> manager IP on ports 1514-1515
