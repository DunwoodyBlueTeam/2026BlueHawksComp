# Run as Administrator

Write-Host "=== Network Connections Audit ===" -ForegroundColor Cyan

# Show active network connections
Write-Host "`nActive Network Connections:" -ForegroundColor Yellow
Get-NetTCPConnection | Where-Object {$_.State -eq "Established"} | 
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess | 
    ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        $_ | Add-Member -NotePropertyName ProcessName -NotePropertyValue $proc.Name -PassThru
    } | Format-Table -AutoSize

# Show listening ports
Write-Host "`nListening Ports:" -ForegroundColor Yellow
Get-NetTCPConnection | Where-Object {$_.State -eq "Listen"} | 
    Select-Object LocalAddress, LocalPort, State, OwningProcess | 
    ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        $_ | Add-Member -NotePropertyName ProcessName -NotePropertyValue $proc.Name -PassThru
    } | Sort-Object LocalPort | Format-Table -AutoSize

# Check firewall status
Write-Host "`nFirewall Status:" -ForegroundColor Yellow
Get-NetFirewallProfile | Select-Object Name, Enabled | Format-Table -AutoSize

# Export connections
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Get-NetTCPConnection | Export-Csv -Path "NetworkConnections_$timestamp.csv" -NoTypeInformation
Write-Host "`nConnections exported to NetworkConnections_$timestamp.csv" -ForegroundColor Green

# Show suspicious ports (common backdoor ports)
$suspiciousPorts = @(4444, 5555, 6666, 31337, 12345, 1337, 3389)
Write-Host "`nChecking for connections on suspicious ports:" -ForegroundColor Red
Get-NetTCPConnection | Where-Object {$suspiciousPorts -contains $_.LocalPort -or $suspiciousPorts -contains $_.RemotePort} | 
    Format-Table -AutoSize