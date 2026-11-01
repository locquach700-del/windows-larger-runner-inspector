param(
    [string]$OutputDirectory = "reports"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$computer = Get-CimInstance -ClassName Win32_ComputerSystem
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$processors = @(Get-CimInstance -ClassName Win32_Processor)
$videoControllers = @(Get-CimInstance -ClassName Win32_VideoController)
$logicalDisks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3")

$totalCores = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
$totalLogicalProcessors = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

$gpus = @(
    foreach ($gpu in $videoControllers) {
        $vramGB = $null
        if ($null -ne $gpu.AdapterRAM -and [double]$gpu.AdapterRAM -gt 0) {
            $vramGB = [math]::Round(([double]$gpu.AdapterRAM / 1GB), 2)
        }

        [PSCustomObject]@{
            Name = $gpu.Name
            DriverVersion = $gpu.DriverVersion
            AdapterMemoryGB = $vramGB
        }
    }
)

$disks = @(
    foreach ($disk in $logicalDisks) {
        [PSCustomObject]@{
            Drive = $disk.DeviceID
            FileSystem = $disk.FileSystem
            SizeGB = if ($null -ne $disk.Size) {
                [math]::Round(([double]$disk.Size / 1GB), 2)
            } else { $null }
            FreeGB = if ($null -ne $disk.FreeSpace) {
                [math]::Round(([double]$disk.FreeSpace / 1GB), 2)
            } else { $null }
        }
    }
)

$report = [PSCustomObject]@{
    CollectedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    Runner = [PSCustomObject]@{
        Name = $env:RUNNER_NAME
        OperatingSystem = $env:RUNNER_OS
        Architecture = $env:RUNNER_ARCH
    }
    OperatingSystem = [PSCustomObject]@{
        Caption = $os.Caption
        Version = $os.Version
        BuildNumber = $os.BuildNumber
        Architecture = $os.OSArchitecture
    }
    CPU = [PSCustomObject]@{
        Models = @($processors | ForEach-Object { $_.Name.Trim() } | Select-Object -Unique)
        PhysicalCores = [int]$totalCores
        LogicalProcessors = [int]$totalLogicalProcessors
    }
    Memory = [PSCustomObject]@{
        TotalGB = [math]::Round(([double]$computer.TotalPhysicalMemory / 1GB), 2)
    }
    GPUs = $gpus
    Disks = $disks
}

$jsonPath = Join-Path $OutputDirectory "hardware.json"
$markdownPath = Join-Path $OutputDirectory "hardware.md"

$report | ConvertTo-Json -Depth 8 |
    Set-Content -Path $jsonPath -Encoding UTF8

$cpuModels = ($report.CPU.Models -join "; ")
$gpuNames = if ($gpus.Count -gt 0) {
    ($gpus | ForEach-Object { $_.Name }) -join "; "
} else {
    "No GPU adapter reported"
}

$diskLines = @(
    foreach ($disk in $disks) {
        "| $($disk.Drive) | $($disk.SizeGB) | $($disk.FreeGB) |"
    }
)

$markdown = @"
# Windows Runner Hardware Report

- Collected (UTC): $($report.CollectedAtUtc)
- Runner: $($report.Runner.Name)
- OS: $($report.OperatingSystem.Caption) ($($report.OperatingSystem.Version))
- Architecture: $($report.Runner.Architecture)

## CPU

- Model: $cpuModels
- Physical cores: $($report.CPU.PhysicalCores)
- Logical processors: $($report.CPU.LogicalProcessors)

## Memory

- Total RAM: $($report.Memory.TotalGB) GB

## GPU

$gpuNames

## Local disks

| Drive | Size (GB) | Free (GB) |
|---|---:|---:|
$($diskLines -join "`n")
"@

Set-Content -Path $markdownPath -Value $markdown -Encoding UTF8

Write-Host "Hardware report created:"
Write-Host " - $jsonPath"
Write-Host " - $markdownPath"

Write-Host "CPU: $cpuModels"
Write-Host "Cores: $($report.CPU.PhysicalCores)"
Write-Host "Logical processors: $($report.CPU.LogicalProcessors)"
Write-Host "RAM: $($report.Memory.TotalGB) GB"
Write-Host "GPU: $gpuNames"
