# Run as Administrator
# CAUTION: Review before running in production

Write-Host "=== CCDC Security Baseline Hardening ===" 
Write-Host "This script will apply basic security hardening" 
$confirm = Read-Host "Continue? (y/n)"
if ($confirm -ne 'y') { exit }

# Enable Windows Firewall on all profiles
Write-Host "`n[+] Enabling Windows Firewall..." 
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# Disable SMBv1
Write-Host "[+] Disabling SMBv1..." 
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

# Enable Windows Defender real-time protection
Write-Host "[+] Enabling Windows Defender..." 
Set-MpPreference -DisableRealtimeMonitoring $false

# Set password policy (requires elevated permissions)
Write-Host "[+] Configuring password policy..." 
net accounts /minpwlen:12
net accounts /maxpwage:90
net accounts /minpwage:1
net accounts /uniquepw:5

# Disable guest account
Write-Host "[+] Disabling Guest account..." 
Disable-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
    Write-Host "`nChecking status of Guest account"
    Get-ADUser -Identity "Guest" -Properties Enabled,MemberOfGroup

# Enable audit logging
Write-Host "[+] Enabling audit policies..." 
auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable
auditpol /set /category:"Account Logon" /success:enable /failure:enable
auditpol /set /category:"Account Management" /success:enable /failure:enable

# Disable unnecessary services (adjust based on your needs)
$servicesToDisable = @(
    "RemoteRegistry",
    "RemoteAccess"
)

Write-Host "[+] Disabling unnecessary services..." 
foreach ($svc in $servicesToDisable) {
    try {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  - Disabled $svc" 
    } catch {
        Write-Host "  - Could not disable $svc" 
    }
}

# Clear DNS cache
Write-Host "[+] Clearing DNS cache..." 
Clear-DnsClientCache

# Update Windows Defender signatures
Write-Host "[+] Updating Windows Defender signatures..." 
Update-MpSignature

Write-Host "`n=== Hardening Complete ===" 

Write-Host "Review changes and test critical services!" 


