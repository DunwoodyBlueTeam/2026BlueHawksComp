# Run as Administrator

Write-Host "=== User Account Audit ===" -ForegroundColor Cyan

# List all local users
Write-Host "`nLocal Users:" -ForegroundColor Yellow
Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet | Format-Table -AutoSize

# List all local administrators
Write-Host "`nLocal Administrators:" -ForegroundColor Yellow
Get-LocalGroupMember -Group "Administrators" | Format-Table -AutoSize

# Check for users with password never expires
Write-Host "`nUsers with PasswordNeverExpires set:" -ForegroundColor Yellow
Get-LocalUser | Where-Object {$_.PasswordNeverExpires -eq $true} | Select-Object Name, Enabled

# Check for disabled accounts
Write-Host "`nDisabled Accounts:" -ForegroundColor Yellow
Get-LocalUser | Where-Object {$_.Enabled -eq $false} | Select-Object Name

# Export to CSV for documentation
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Get-LocalUser | Export-Csv -Path "UserAudit_$timestamp.csv" -NoTypeInformation
Write-Host "`nAudit exported to UserAudit_$timestamp.csv" -ForegroundColor Green

# Prompt for actions
$action = Read-Host "`nDo you want to disable unauthorized users? (y/n)"
if ($action -eq 'y') {
    $username = Read-Host "Enter username to disable"
    try {
        Disable-LocalUser -Name $username
        Write-Host "User $username has been disabled" -ForegroundColor Green
    } catch {
        Write-Host "Error disabling user: $_" -ForegroundColor Red
    }
}