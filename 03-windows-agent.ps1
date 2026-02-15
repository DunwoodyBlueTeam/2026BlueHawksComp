param(
    [Parameter(Mandatory=$true)]
    [string]$ManagerIP,

    [string]$RegPassword = "ja|ZtS72E'&tEQ46=P=B"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$WazuhVersion  = "4.7"
$WazuhAgentMSI = "wazuh-agent-4.7.3-1.msi"
$ClamAVMSI     = "clamav-1.4.3.win.x64.msi"
$TempDir       = "$env:TEMP\ccdc-deploy"

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

Write-Host "=========================================="
Write-Host " Windows Agent"
Write-Host " Manager IP: $ManagerIP"
Write-Host "=========================================="

#Clam
Write-Host "`n===== ClamAV Installation ====="

$ClamURL = "https://www.clamav.net/downloads/production/$ClamAVMSI"
$ClamPath = "$TempDir\$ClamAVMSI"

Write-Host "[*] Downloading Clam"
try {
    Invoke-WebRequest -Uri $ClamURL -OutFile $ClamPath -UseBasicParsing
} catch {
    Write-Host "[!] Primary download failed, trying GitHub release"
    $ClamURL = "https://github.com/Cisco-Talos/clamav/releases/download/clamav-1.4.3/$ClamAVMSI"
    Invoke-WebRequest -Uri $ClamURL -OutFile $ClamPath -UseBasicParsing
}

Write-Host "[*] Installing Clam"
Start-Process msiexec.exe -ArgumentList "/i `"$ClamPath`" /qn" -Wait -NoNewWindow

Start-Sleep -Seconds 5

$ClamDirs = @(
    "${env:ProgramFiles}\ClamAV",
    "${env:ProgramFiles(x86)}\ClamAV",
    "C:\ClamAV",
    "${env:ProgramFiles}\clamav"
)
$ClamDir = $ClamDirs | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $ClamDir) {
    Write-Host "[!] Could not find Clam install directory. Checking Program Files"
    $ClamDir = Get-ChildItem "${env:ProgramFiles}" -Directory -Filter "*clam*" -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName
}

if ($ClamDir) {
    Write-Host "[*] Clam found at: $ClamDir"
} else {
    Write-Host "[!] WARNING: Clam directory not found. Manual config may be needed."
    $ClamDir = "${env:ProgramFiles}\ClamAV"
}

$ClamdConf    = "$ClamDir\clamd.conf"
$FreshConf    = "$ClamDir\freshclam.conf"
$ClamdExample = "$ClamDir\conf_examples\clamd.conf.sample"
$FreshExample = "$ClamDir\conf_examples\freshclam.conf.sample"

if ((-not (Test-Path $ClamdConf)) -and (Test-Path $ClamdExample)) {
    Copy-Item $ClamdExample $ClamdConf
    (Get-Content $ClamdConf) -replace '^Example', '#Example' | Set-Content $ClamdConf
}

if ((-not (Test-Path $FreshConf)) -and (Test-Path $FreshExample)) {
    Copy-Item $FreshExample $FreshConf
    (Get-Content $FreshConf) -replace '^Example', '#Example' | Set-Content $FreshConf
}

if (Test-Path $ClamdConf) {
    $clamdContent = Get-Content $ClamdConf -Raw
    if ($clamdContent -notmatch 'TCPSocket\s+3310') {
        Add-Content $ClamdConf "`nTCPSocket 3310"
        Add-Content $ClamdConf "TCPAddr 127.0.0.1"
    }
}

Write-Host "[*] Running freshclam"
$freshclamExe = "$ClamDir\freshclam.exe"
if (Test-Path $freshclamExe) {
    & $freshclamExe --config-file="$FreshConf" 2>&1 | Out-Null
}

$clamdExe = "$ClamDir\clamd.exe"
if (Test-Path $clamdExe) {
    Write-Host "[*] Installing clamd as a Windows service"
    & $clamdExe --install 2>&1 | Out-Null
    Start-Service "ClamAV" -ErrorAction SilentlyContinue
    Set-Service "ClamAV" -StartupType Automatic -ErrorAction SilentlyContinue
}

Write-Host "`n Wazuh Agent Installation"

$WazuhURL  = "https://packages.wazuh.com/4.x/windows/$WazuhAgentMSI"
$WazuhPath = "$TempDir\$WazuhAgentMSI"

Write-Host "[*] Downloading Wazuh agent"
Invoke-WebRequest -Uri $WazuhURL -OutFile $WazuhPath -UseBasicParsing

Write-Host "[*] Installing Wazuh agent"
Start-Process msiexec.exe -ArgumentList @(
    "/i", "`"$WazuhPath`"",
    "WAZUH_MANAGER=`"$ManagerIP`"",
    "WAZUH_REGISTRATION_PASSWORD=`"$RegPassword`"",
    "/qn"
) -Wait -NoNewWindow

Start-Sleep -Seconds 5

$OssecConf = "C:\Program Files (x86)\ossec-agent\ossec.conf"
if (-not (Test-Path $OssecConf)) {
    $OssecConf = "C:\Program Files\ossec-agent\ossec.conf"
}

if (Test-Path $OssecConf) {
    Write-Host "[*] Patching ossec.conf"

    [xml]$xml = Get-Content $OssecConf

    $sysc = $xml.ossec_config.syscollector
    if ($sysc) {
        $enabledNode = $sysc.SelectSingleNode("enabled")
        if ($enabledNode) {
            $enabledNode.InnerText = "yes"
        } else {
            $el = $xml.CreateElement("enabled")
            $el.InnerText = "yes"
            $sysc.PrependChild($el) | Out-Null
        }
    }

    $syscheck = $xml.ossec_config.syscheck
    if ($syscheck) {
        $alreadySet = $false
        foreach ($dir in $syscheck.SelectNodes("directories")) {
            if ($dir.InnerText -match 'C:\\Users' -and $dir.GetAttribute("realtime") -eq "yes") {
                $alreadySet = $true
            }
        }
        if (-not $alreadySet) {
            $dirNode = $xml.CreateElement("directories")
            $dirNode.SetAttribute("realtime", "yes")
            $dirNode.InnerText = "C:\Users"
            $syscheck.AppendChild($dirNode) | Out-Null
        }
        $disabledNode = $syscheck.SelectSingleNode("disabled")
        if ($disabledNode) { $disabledNode.InnerText = "no" }
    }

    $secChannel = $xml.CreateElement("localfile")
    $locName = $xml.CreateElement("location")
    $locName.InnerText = "Security"
    $logFormat = $xml.CreateElement("log_format")
    $logFormat.InnerText = "eventchannel"
    $secChannel.AppendChild($locName) | Out-Null
    $secChannel.AppendChild($logFormat) | Out-Null
    $xml.ossec_config.AppendChild($secChannel) | Out-Null

    $sysmonChannel = $xml.CreateElement("localfile")
    $locName2 = $xml.CreateElement("location")
    $locName2.InnerText = "Microsoft-Windows-Sysmon/Operational"
    $logFormat2 = $xml.CreateElement("log_format")
    $logFormat2.InnerText = "eventchannel"
    $sysmonChannel.AppendChild($locName2) | Out-Null
    $sysmonChannel.AppendChild($logFormat2) | Out-Null
    $xml.ossec_config.AppendChild($sysmonChannel) | Out-Null

    $xml.Save($OssecConf)
    Write-Host "[*] ossec.conf updated with syscollector, FIM, and event channels."
} else {
    Write-Host "[!] ossec.conf not found. Manual configuration required."
}

Write-Host "[*] Restarting Wazuh agent"
Restart-Service "WazuhSvc" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$wazuhSvc = Get-Service "WazuhSvc" -ErrorAction SilentlyContinue
if ($wazuhSvc -and $wazuhSvc.Status -eq "Running") {
    Write-Host "[*] Wazuh agent is running."
} else {
    Write-Host "[!] Wazuh agent may not have started. Check services manually."
}

Write-Host "`n=========================================="
Write-Host " VERIFICATION"
Write-Host "=========================================="
Write-Host "`nClam service status:"
Get-Service "ClamAV*" -ErrorAction SilentlyContinue | Select-Object Status, Name, DisplayName | Format-Table -AutoSize

Write-Host "Wazuh agent service status:"
Get-Service "WazuhSvc" -ErrorAction SilentlyContinue | Select-Object Status, Name, DisplayName | Format-Table -AutoSize

Write-Host "Scheduled tasks:"
Get-ScheduledTask -TaskName "ClamAV*" -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table -AutoSize

Write-Host "`n=========================================="
Write-Host " Done. Agent should register with manager at $ManagerIP"
Write-Host "=========================================="
