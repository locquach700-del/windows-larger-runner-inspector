param(
    [string]$OutputDirectory = "benchmark",
    [ValidateRange(2, 15)]
    [int]$CpuDurationSeconds = 5,
    [ValidateRange(8, 128)]
    [int]$DiskTestSizeMB = 32
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

# CPU benchmark: short, bounded, parallel SHA-256 workload.
$cpuSource = @'
using System;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

public static class RunnerCpuBenchmark
{
    public static long Run(int seconds, int workers)
    {
        long total = 0;
        var timer = Stopwatch.StartNew();

        Parallel.For(0, workers, worker =>
        {
            byte[] input = new byte[4096];
            byte[] digest = new byte[32];
            new Random(worker + 12345).NextBytes(input);
            using (SHA256 sha = SHA256.Create())
            {
                long local = 0;
                while (timer.Elapsed.TotalSeconds < seconds)
                {
                    sha.ComputeHash(input);
                    local++;
                }
                Interlocked.Add(ref total, local);
            }
        });

        return total;
    }
}
'@

if (-not ("RunnerCpuBenchmark" -as [type])) {
    Add-Type -TypeDefinition $cpuSource -Language CSharp
}

$logicalProcessors = [Environment]::ProcessorCount
$cpuWatch = [Diagnostics.Stopwatch]::StartNew()
$hashOperations = [RunnerCpuBenchmark]::Run($CpuDurationSeconds, $logicalProcessors)
$cpuWatch.Stop()
$cpuElapsed = [math]::Round($cpuWatch.Elapsed.TotalSeconds, 2)
$hashPerSecond = if ($cpuElapsed -gt 0) {
    [math]::Round($hashOperations / $cpuElapsed, 2)
} else { 0 }

# Disk benchmark: bounded sequential write/read of a temporary file.
$diskPath = Join-Path ([IO.Path]::GetTempPath()) ("runner-benchmark-{0}.bin" -f [guid]::NewGuid())
$buffer = [byte[]]::new(1MB)
[Random]::new(1234).NextBytes($buffer)
$bytesToWrite = [long]$DiskTestSizeMB * 1MB

try {
    $writeWatch = [Diagnostics.Stopwatch]::StartNew()
    $stream = [IO.File]::Open($diskPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $remaining = $bytesToWrite
        while ($remaining -gt 0) {
            $chunk = [int][math]::Min($buffer.Length, $remaining)
            $stream.Write($buffer, 0, $chunk)
            $remaining -= $chunk
        }
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
    $writeWatch.Stop()

    $readWatch = [Diagnostics.Stopwatch]::StartNew()
    $stream = [IO.File]::OpenRead($diskPath)
    try {
        $readBuffer = [byte[]]::new(1MB)
        while ($stream.Read($readBuffer, 0, $readBuffer.Length) -gt 0) { }
    }
    finally {
        $stream.Dispose()
    }
    $readWatch.Stop()

    $writeMBps = if ($writeWatch.Elapsed.TotalSeconds -gt 0) {
        [math]::Round($DiskTestSizeMB / $writeWatch.Elapsed.TotalSeconds, 2)
    } else { 0 }
    $readMBps = if ($readWatch.Elapsed.TotalSeconds -gt 0) {
        [math]::Round($DiskTestSizeMB / $readWatch.Elapsed.TotalSeconds, 2)
    } else { 0 }

    $report = [PSCustomObject]@{
        CollectedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        Cpu = [PSCustomObject]@{
            LogicalProcessorsUsed = $logicalProcessors
            DurationSeconds = $cpuElapsed
            Sha256Operations = $hashOperations
            Sha256OperationsPerSecond = $hashPerSecond
        }
        Disk = [PSCustomObject]@{
            TestSizeMB = $DiskTestSizeMB
            SequentialWriteMBps = $writeMBps
            SequentialReadMBps = $readMBps
        }
        Notes = @(
            "Short synthetic benchmark; results vary with runner load and storage caching.",
            "GPU performance is not benchmarked by this script."
        )
    }

    $jsonPath = Join-Path $OutputDirectory "benchmark.json"
    $markdownPath = Join-Path $OutputDirectory "benchmark.md"
    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

    @"
# Runner benchmark

- CPU workers: $logicalProcessors
- CPU benchmark duration: $cpuElapsed seconds
- SHA-256 operations: $hashOperations
- SHA-256 operations/second: $hashPerSecond
- Disk test size: $DiskTestSizeMB MB
- Sequential write: $writeMBps MB/s
- Sequential read: $readMBps MB/s

Results are synthetic and vary with runner load and storage caching. GPU performance is not measured.
"@ | Set-Content -Path $markdownPath -Encoding UTF8

    Write-Host "CPU SHA-256 operations/sec: $hashPerSecond"
    Write-Host "Disk sequential write MB/s: $writeMBps"
    Write-Host "Disk sequential read MB/s: $readMBps"
    Write-Host "Benchmark report saved to $OutputDirectory"
}
finally {
    if (Test-Path $diskPath) {
        Remove-Item $diskPath -Force
    }
}
