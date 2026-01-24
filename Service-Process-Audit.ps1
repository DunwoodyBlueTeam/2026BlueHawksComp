# Run as Administrator

Write-Host "=== Service and Process Audit ===" 

# List all running services
Write-Host "`nRunning Services:" 
Get-Service | Where-Object {$_.Status -eq "Running"} | 
    Select-Object Name, DisplayName, StartType | 
    Sort-Object Name | 
    Format-Table -AutoSize

# Check for services with automatic start that are stopped
Write-Host "`nAutomatic Services that are Stopped (potential issues):" 
Get-Service | Where-Object {$_.StartType -eq "Automatic" -and $_.Status -eq "Stopped"} | 
    Select-Object Name, DisplayName | 
    Format-Table -AutoSize

# List scheduled tasks
Write-Host "`nScheduled Tasks (Ready state):" 
Get-ScheduledTask | Where-Object {$_.State -eq "Ready"} | 
    Select-Object TaskName, TaskPath, State | 
    Format-Table -AutoSize

# Check for suspicious processes
Write-Host "`nProcesses listening on network:" 
Get-Process | Where-Object {$_.Id -in (Get-NetTCPConnection | Select-Object -ExpandProperty OwningProcess -Unique)} | 
    Select-Object Id, ProcessName, Path, StartTime | 
    Sort-Object ProcessName | 
    Format-Table -AutoSize

# Export data
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Get-Service | Export-Csv -Path "Services_$timestamp.csv" -NoTypeInformation
Get-ScheduledTask | Export-Csv -Path "C:\CCDC-Docs\ScheduledTasks_$timestamp.csv" -NoTypeInformation
Write-Host "`nData exported to Services_$timestamp.csv and ScheduledTasks_$timestamp.csv" 

# Interactive service management
$manage = Read-Host "`nDo you want to stop a service? (y/n)"
if ($manage -eq 'y') {
    $serviceName = Read-Host "Enter service name to stop"
    try {
        Stop-Service -Name $serviceName -Force
        Set-Service -Name $serviceName -StartupType Disabled
        Write-Host "Service $serviceName stopped and disabled" 
    } catch {
        Write-Host "Error managing service: $_" 
    }

}
