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
