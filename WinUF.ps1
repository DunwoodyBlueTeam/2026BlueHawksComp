<#
WinUF.ps1
CCDC-safe baseline: download & install Splunk Universal Forwarder & configure outputs & enable WinEventLog. Make sure custom Index is enabled or you will NOT see test log at the end of the script. 
#>

param(
  # REQUIRED: IP of your Splunk Enterprise server (Indexer/Receiver) -> Enter when executing code in powershell. (.\Install-UF.ps1 -IndexerIp <SPLUNK_SERVER_IP>)
  [Parameter(Mandatory=$true)]
  [string]$IndexerIp,

  # Port your Splunk Enterprise is listening on for forwarders ( 9997)
  [int]$ReceiverPort = 9997,

  # UF version
  [string]$SplunkVersion = "9.1.0",

  # IMPORTANT: Index I want all forwarded logs to collect in
  # Make sure this index exists on Splunk Enterprise (Settings -> Indexes -> New Index).
  [string]$CustomIndexName = "Wineventlogs"
)

# 0) Require admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Run PowerShell as Administrator."
}

$ErrorActionPreference = "Stop"

# 1) Force TLS 1.2 so downloads work reliably
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# 2) UF download URL $SplunkVersion 9.1.0
$MsiName     = "splunkforwarder-9.1.0-1c86ca0bacc3-x64-release.msi"
$DownloadUrl = "https://download.splunk.com/products/universalforwarder/releases/9.1.0/windows/splunkforwarder-9.1.0-1c86ca0bacc3-x64-release.msi"

# 3) Paths
$DownloadDir = Join-Path $env:TEMP "splunkuf"
$MsiPath     = Join-Path $DownloadDir $MsiName

$UfHome   = Join-Path $env:ProgramFiles "SplunkUniversalForwarder"
$UfBin    = Join-Path $UfHome "bin\splunk.exe"
$LocalDir = Join-Path $UfHome "etc\system\local"

$OutputsConf = Join-Path $LocalDir "outputs.conf"
$InputsConf  = Join-Path $LocalDir "inputs.conf"

# 4) Download MSI (only if not already downloaded)
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

if (Test-Path $MsiPath) {
  Write-Host "[*] UF installer already downloaded. Using existing file:" $MsiPath
} else {
  Write-Host "[*] Downloading UF MSI from:" $DownloadUrl
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath -UseBasicParsing
}

if (-not (Test-Path $MsiPath)) { throw "Download failed: $MsiPath not found." }

# 5) Install UF silently (only if UF not already installed)
if (Test-Path $UfBin) {
  Write-Host "[*] UF already installed. Skipping MSI install."
} else {
  Write-Host "[*] Installing Splunk Universal Forwarder..."
  $msiArgs = "/i `"$MsiPath`" AGREETOLICENSE=Yes /quiet /norestart"
  $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
  if ($proc.ExitCode -ne 0) { throw "MSI install failed with exit code: $($proc.ExitCode)" }

  if (-not (Test-Path $UfBin)) { throw "UF install appears incomplete: $UfBin not found." }
}

# 6) Ensure local config dir exists
New-Item -ItemType Directory -Force -Path $LocalDir | Out-Null

# 7) Configure outputs.conf (send to Splunk)
$tcpTarget = "$IndexerIp`:$ReceiverPort"
Write-Host "[*] Writing outputs.conf -> $tcpTarget"

@"
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = $tcpTarget
"@ | Set-Content -Path $OutputsConf -Encoding ASCII

# 8) Configure inputs.conf (collect Windows event logs) - ALWAYS uses custom index (wineventlogs)
Write-Host "[*] Writing inputs.conf (WinEventLog) -> index=$CustomIndexName"

@"
[default]
host = $env:COMPUTERNAME

[WinEventLog://Application]
disabled = 0
index = $CustomIndexName

[WinEventLog://System]
disabled = 0
index = $CustomIndexName

[WinEventLog://Security]
disabled = 0
index = $CustomIndexName
"@ | Set-Content -Path $InputsConf -Encoding ASCII


# 9) Start/restart forwarder
Write-Host "[*] Starting/restarting splunkforwarder..."
& $UfBin start --accept-license --answer-yes | Out-Null

Start-Sleep -Seconds 2
Stop-Service -Name "splunkforwarder" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service -Name "splunkforwarder"

# 10) Print verification
Write-Host ""
Write-Host "[+] UF installed at:" $UfHome
Write-Host "[+] Service status:"
Get-Service splunkforwarder | Format-Table -AutoSize

Write-Host "`n[+] Effective outputs (btool):"
& $UfBin btool outputs list --debug | Select-String -Pattern "tcpout|server" -Context 0,1

Write-Host "`n[+] Effective inputs (btool):"
& $UfBin btool inputs list --debug | Select-String -Pattern "WinEventLog" -Context 0,0

# 11) Push a test log to verify forwarding
Write-Host "[*] Sending test event to verify Splunk forwarding..."

$TestMessage = "Testing Splunk Forwarder from $env:COMPUTERNAME"

eventcreate `
  /L APPLICATION `
  /ID 777 `
  /T INFORMATION `
  /SO SplunkForwarderTest `
  /D "$TestMessage"

Write-Host "[+] Test event created: '$TestMessage'"


Write-Host "`n[*] Done."
# ===================== [END] =====================
