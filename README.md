# 2026CCDC_DCT
# Splunk Setup – CCDC Run Order

This branch contains Splunk-related setup scripts.
---

## STEP 1 - 
Reset root/sysadmin password
---

## STEP 2 -
Change admin(splunkweb) password, Add listening port (9997), add custom indexes ("wineventlogs" && "linuxlogs)
---

## STEP 3 – 
Install Windows Universal Forwarder
Run on **each Windows VM** as soon as possible!!

### Requirements
- PowerShell
- Run **PowerShell as Administrator**
- Internet access

### Commands
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-WebRequest https://raw.githubusercontent.com/DunwoodyBlueTeam/2026BlueHawksComp/splunk/WinUF.ps1 -OutFile WinUF.ps1
.\WinUF.ps1 -IndexerIp <SPLUNK_ENTERPRISE_IP>
```
To verify logs are being pushed, search index="wineventlogs" and look for EventCode=777. Will be an Application log. *WILL NOT WORK IF CUSTOM INDEX IS NOT CREATED!

## STEP 4 -
--> Set up forwarders on Linux <--
Run Linux UF Scripts

### If curl exists
-----------------------------------------
Ubuntu:
curl -fsSL https://raw.githubusercontent.com/DunwoodyBlueTeam/2026BlueHawksComp/refs/heads/splunk/UbuUF.sh -o UbuUF.sh

chmod +x UbuUF.sh

sudo ./UbuUF.sh

-----------------------------------------
Fedora:
curl -fsSL https://raw.githubusercontent.com/DunwoodyBlueTeam/2026BlueHawksComp/refs/heads/splunk/FedUf.sh -o FedUf.sh

chmod +x FedUf.sh

sudo ./FedUf.sh

-----------------------------------------
### If curl does NOT exist (use wget)
-----------------------------------------
Ubuntu:
wget -qO UbuUF.sh https://raw.githubusercontent.com/DunwoodyBlueTeam/2026BlueHawksComp/refs/heads/splunk/UbuUF.sh

chmod +x UbuUF.sh

sudo ./UbuUF.sh

-----------------------------------
Fedora:
wget -qO FedUf.sh https://raw.githubusercontent.com/DunwoodyBlueTeam/2026BlueHawksComp/refs/heads/splunk/FedUf.sh

chmod +x FedUf.sh

sudo ./FedUf.sh

