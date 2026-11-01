$ErrorActionPreference = "Stop"

$reportDirectory = Join-Path $env:RUNNER_TEMP "hardware-inspector-test"
if (Test-Path $reportDirectory) {
    Remove-Item $reportDirectory -Recurse -Force
}

& "$PSScriptRoot/../scripts/Check-Hardware.ps1" -OutputDirectory $reportDirectory

$jsonPath = Join-Path $reportDirectory "hardware.json"
$markdownPath = Join-Path $reportDirectory "hardware.md"

if (-not (Test-Path $jsonPath)) {
    throw "FAIL: hardware.json was not created."
}
if (-not (Test-Path $markdownPath)) {
    throw "FAIL: hardware.md was not created."
}

$report = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json

if (-not $report.OperatingSystem.Caption) {
    throw "FAIL: OS caption is missing."
}
if ([int]$report.CPU.LogicalProcessors -lt 1) {
    throw "FAIL: CPU logical processor count is invalid."
}
if ([double]$report.Memory.TotalGB -le 0) {
    throw "FAIL: RAM total is invalid."
}
if ($null -eq $report.Disks) {
    throw "FAIL: Disk information is missing."
}

Write-Host "PASS: JSON and Markdown reports exist."
Write-Host "PASS: OS, CPU, memory, and disk data are present."
Write-Host "All hardware-inspector tests passed."
