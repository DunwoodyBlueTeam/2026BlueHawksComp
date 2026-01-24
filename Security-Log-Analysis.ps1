# Run as Administrator

param(
    [int]$Hours = 2  # How many hours back to analyze
)

Write-Host "=== Security Log Analysis ===" -ForegroundColor Cyan
Write-Host "Analyzing logs from the last $Hours hour(s)" -ForegroundColor Yellow

$startTime = (Get-Date).AddHours(-$Hours)

# ===== FAILED LOGON ATTEMPTS =====
Write-Host "`n=== Failed Logon Attempts (Event ID 4625) ===" -ForegroundColor Red
try {
    $failedLogons = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        ID = 4625
        StartTime = $startTime
    } -ErrorAction SilentlyContinue
    
    if ($failedLogons) {
        $failedSummary = $failedLogons | ForEach-Object {
            $xml = [xml]$_.ToXml()
            [PSCustomObject]@{
                TimeCreated = $_.TimeCreated
                TargetUserName = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'} | Select-Object -ExpandProperty '#text'
                IpAddress = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'IpAddress'} | Select-Object -ExpandProperty '#text'
                LogonType = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'LogonType'} | Select-Object -ExpandProperty '#text'
                FailureReason = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'SubStatus'} | Select-Object -ExpandProperty '#text'
            }
        }
        
        $failedSummary | Format-Table -AutoSize
        Write-Host "Total failed logons: $($failedLogons.Count)" -ForegroundColor Yellow
        
        # Group by user
        Write-Host "`nFailed logons by user:" -ForegroundColor Yellow
        $failedSummary | Group-Object TargetUserName | Sort-Object Count -Descending | 
            Select-Object Count, Name | Format-Table -AutoSize
            
    } else {
        Write-Host "No failed logons detected" -ForegroundColor Green
    }
} catch {
    Write-Host "Error reading failed logon events: $_" -ForegroundColor Red
}

# ===== SUCCESSFUL LOGONS =====
Write-Host "`n=== Successful Logons (Event ID 4624) ===" -ForegroundColor Green
try {
    $successLogons = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        ID = 4624
        StartTime = $startTime
    } -ErrorAction SilentlyContinue | Select-Object -First 50
    
    if ($successLogons) {
        $logonSummary = $successLogons | ForEach-Object {
            $xml = [xml]$_.ToXml()
            [PSCustomObject]@{
                TimeCreated = $_.TimeCreated
                TargetUserName = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'} | Select-Object -ExpandProperty '#text'
                IpAddress = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'IpAddress'} | Select-Object -ExpandProperty '#text'
                LogonType = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'LogonType'} | Select-Object -ExpandProperty '#text'
            }
        } | Where-Object {$_.TargetUserName -notmatch '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|DWM-|UMFD-)'}
        
        $logonSummary | Format-Table -AutoSize
    } else {
        Write-Host "No successful logons detected" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error reading successful logon events: $_" -ForegroundColor Red
}

# ===== ACCOUNT CHANGES =====
Write-Host "`n=== Account Changes (Created/Deleted/Modified) ===" -ForegroundColor Yellow
try {
    $accountChanges = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        ID = 4720, 4722, 4724, 4726, 4728, 4732, 4756
        StartTime = $startTime
    } -ErrorAction SilentlyContinue
    
    if ($accountChanges) {
        $accountChanges | ForEach-Object {
            $xml = [xml]$_.ToXml()
            $targetUser = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'} | Select-Object -ExpandProperty '#text'
            $subjectUser = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'SubjectUserName'} | Select-Object -ExpandProperty '#text'
            
            [PSCustomObject]@{
                TimeCreated = $_.TimeCreated
                EventID = $_.Id
                Action = switch ($_.Id) {
                    4720 { "User Created" }
                    4722 { "User Enabled" }
                    4724 { "Password Reset" }
                    4726 { "User Deleted" }
                    4728 { "Added to Global Group" }
                    4732 { "Added to Local Group" }
                    4756 { "Added to Universal Group" }
                }
                TargetUser = $targetUser
                ByUser = $subjectUser
            }
        } | Format-Table -AutoSize
    } else {
        Write-Host "No account changes detected" -ForegroundColor Green
    }
} catch {
    Write-Host "Error reading account change events: $_" -ForegroundColor Red
}

# ===== PRIVILEGE USE =====
Write-Host "`n=== Privilege Escalation/Use (Event ID 4672) ===" -ForegroundColor Yellow
try {
    $privUse = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        ID = 4672
        StartTime = $startTime
    } -ErrorAction SilentlyContinue | Select-Object -First 20
    
    if ($privUse) {
        $privUse | ForEach-Object {
            $xml = [xml]$_.ToXml()
            [PSCustomObject]@{
                TimeCreated = $_.TimeCreated
                SubjectUserName = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'SubjectUserName'} | Select-Object -ExpandProperty '#text'
            }
        } | Where-Object {$_.SubjectUserName -notmatch '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE)'} | 
            Format-Table -AutoSize
    } else {
        Write-Host "No privilege use events detected" -ForegroundColor Green
    }
} catch {
    Write-Host "Error reading privilege events: $_" -ForegroundColor Red
}

# ===== PROCESS CREATION =====
Write-Host "`n=== Suspicious Process Creation (Event ID 4688) ===" -ForegroundColor Red
try {
    $processes = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        ID = 4688
        StartTime = $startTime
    } -ErrorAction SilentlyContinue
    
    if ($processes) {
        $suspiciousProcesses = $processes | ForEach-Object {
            $xml = [xml]$_.ToXml()
            $newProcess = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'NewProcessName'} | Select-Object -ExpandProperty '#text'
            $commandLine = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'CommandLine'} | Select-Object -ExpandProperty '#text'
            
            [PSCustomObject]@{
                TimeCreated = $_.TimeCreated
                Process = $newProcess
                CommandLine = $commandLine
                Creator = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'SubjectUserName'} | Select-Object -ExpandProperty '#text'
            }
        } | Where-Object {
            $_.Process -match '(powershell|cmd|wscript|cscript|mshta|regsvr32|rundll32|psexec|nc\.exe|ncat\.exe)' -or
            $_.CommandLine -match '(Invoke-|downloadstring|IEX|encoded|bypass|hidden)'
        }
        
        if ($suspiciousProcesses) {
            $suspiciousProcesses | Format-Table -Wrap -AutoSize
            Write-Host "Found $($suspiciousProcesses.Count) suspicious processes" -ForegroundColor Red
        } else {
            Write-Host "No suspicious processes detected" -ForegroundColor Green
        }
    } else {
        Write-Host "Process auditing may not be enabled (Event 4688 not found)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error reading process events: $_" -ForegroundColor Red
}

# ===== SYSTEM LOG ERRORS =====
Write-Host "`n=== Critical System Errors ===" -ForegroundColor Red
try {
    $systemErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Level = 1,2  # Critical and Error
        StartTime = $startTime
    } -MaxEvents 20 -ErrorAction SilentlyContinue
    
    if ($systemErrors) {
        $systemErrors | Select-Object TimeCreated, Id, ProviderName, Message | Format-List
    } else {
        Write-Host "No critical system errors" -ForegroundColor Green
    }
} catch {
    Write-Host "Error reading system log: $_" -ForegroundColor Red
}

# Export all findings
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Write-Host "`n=== Exporting Results ===" -ForegroundColor Cyan

if ($failedLogons) {
    $failedSummary | Export-Csv -Path "LogAnalysis_FailedLogons_$timestamp.csv" -NoTypeInformation
}
if ($logonSummary) {
    $logonSummary | Export-Csv -Path "LogAnalysis_SuccessLogons_$timestamp.csv" -NoTypeInformation
}
if ($accountChanges) {
    $accountChanges | Export-Csv -Path "LogAnalysis_AccountChanges_$timestamp.csv" -NoTypeInformation
}

Write-Host "Analysis complete! Results exported to LogAnalysis_*_$timestamp.csv" -ForegroundColor Green