# Run as Administrator

$value = Read-Host "Please enter baseline or check to begin script: "  # baseline or check
param(
    [string]$Mode = $value, 
    [string]$BaselineFile = "C:\CCDC-Docs\file_baseline.csv"
)

Write-Host "=== File Integrity Monitoring ===" 

# Critical directories to monitor
$criticalPaths = @(
    "$env:SystemRoot\System32",
    "$env:SystemRoot\SysWOW64",
    "$env:ProgramFiles",
    "${env:ProgramFiles(x86)}",
    "$env:SystemRoot\Tasks",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"
)

# File extensions to monitor
$criticalExtensions = @("*.exe", "*.dll", "*.sys", "*.bat", "*.ps1", "*.vbs", "*.cmd")

function Get-FileHashes {
    param([string[]]$Paths)
    
    $results = @()
    
    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Write-Host "Scanning: $path" 
            
            foreach ($ext in $criticalExtensions) {
                $files = Get-ChildItem -Path $path -Filter $ext -File -ErrorAction SilentlyContinue
                
                foreach ($file in $files) {
                    try {
                        $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop
                        
                        $results += [PSCustomObject]@{
                            Path = $file.FullName
                            FileName = $file.Name
                            Hash = $hash.Hash
                            Size = $file.Length
                            CreationTime = $file.CreationTime
                            LastWriteTime = $file.LastWriteTime
                            LastAccessTime = $file.LastAccessTime
                        }
                    } catch {
                        Write-Host "  Error hashing: $($file.FullName)" 
                    }
                }
            }
        }
    }
    
    return $results
}

if ($Mode -eq "baseline") {
    Write-Host "`nCreating baseline..." 
    
    $baseline = Get-FileHashes -Paths $criticalPaths
    $baseline | Export-Csv -Path $BaselineFile -NoTypeInformation
    
    Write-Host "Baseline created with $($baseline.Count) files" 
    Write-Host "Saved to: $BaselineFile" 
    
} elseif ($Mode -eq "check") {
    
    if (-not (Test-Path $BaselineFile)) {
        Write-Host "Baseline file not found! Run with -Mode baseline first." 
        exit
    }
    
    Write-Host "`nLoading baseline..." 
    $baseline = Import-Csv -Path $BaselineFile
    
    Write-Host "Checking current state..." 
    $current = Get-FileHashes -Paths $criticalPaths
    
    # Create hash tables for quick lookup
    $baselineHash = @{}
    foreach ($item in $baseline) {
        $baselineHash[$item.Path] = $item
    }
    
    $currentHash = @{}
    foreach ($item in $current) {
        $currentHash[$item.Path] = $item
    }
    
    # Check for new files
    Write-Host "`n=== NEW FILES ===" 
    $newFiles = $current | Where-Object { -not $baselineHash.ContainsKey($_.Path) }
    if ($newFiles) {
        $newFiles | Select-Object Path, LastWriteTime | Format-Table -AutoSize
    } else {
        Write-Host "None detected" 
    }
    
    # Check for deleted files
    Write-Host "`n=== DELETED FILES ===" 
    $deletedFiles = $baseline | Where-Object { -not $currentHash.ContainsKey($_.Path) }
    if ($deletedFiles) {
        $deletedFiles | Select-Object Path | Format-Table -AutoSize
    } else {
        Write-Host "None detected" 
    }
    
    # Check for modified files
    Write-Host "`n=== MODIFIED FILES ===" 
    $modifiedFiles = @()
    foreach ($file in $current) {
        if ($baselineHash.ContainsKey($file.Path)) {
            $baselineItem = $baselineHash[$file.Path]
            if ($file.Hash -ne $baselineItem.Hash) {
                $modifiedFiles += [PSCustomObject]@{
                    Path = $file.Path
                    OriginalHash = $baselineItem.Hash
                    CurrentHash = $file.Hash
                    OriginalTime = $baselineItem.LastWriteTime
                    CurrentTime = $file.LastWriteTime
                }
            }
        }
    }
    
    if ($modifiedFiles) {
        $modifiedFiles | Format-Table -AutoSize
    } else {
        Write-Host "None detected" 
    }
    
    # Export results
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $newFiles | Export-Csv -Path "C:\CCDC-Docs\FIM_NewFiles_$timestamp.csv" -NoTypeInformation
    $deletedFiles | Export-Csv -Path "C:\CCDC-Docs\FIM_DeletedFiles_$timestamp.csv" -NoTypeInformation
    $modifiedFiles | Export-Csv -Path "C:\CCDC-Docs\FIM_ModifiedFiles_$timestamp.csv" -NoTypeInformation
    
    Write-Host "`nResults exported to FIM_*_$timestamp.csv" 
}

Write-Host "`nUsage:" 
Write-Host "  Create baseline: .\script.ps1 -Mode baseline" 
Write-Host "  Check integrity: .\script.ps1 -Mode check" 
