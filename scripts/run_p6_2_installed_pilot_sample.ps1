[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RepositoryPath,
    [ValidateRange(1, 10)]
    [int]$SamplesPerRun = 3,
    [ValidateRange(2, 10)]
    [int]$Repeats = 2,
    [ValidateRange(0, 30)]
    [int]$MinimumDurationDays = 7,
    [ValidateRange(1, 100)]
    [int]$MinimumSamples = 7,
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$PilotId = "p6-2-installed-pilot",
    [string]$AosBinary,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$aosRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))
$p6OnePilot = Join-Path $scriptRoot "run_p6_1_multi_repository_pilot.ps1"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-2-production-like-qualification"
}
$pilotRoot = Join-Path $OutputDir $PilotId
$rawRoot = Join-Path $pilotRoot "raw"
$samplesRoot = Join-Path $pilotRoot "samples"
$statePath = Join-Path $pilotRoot "pilot-state.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Percentile([double[]]$Values, [double]$Percentile) {
    if ($Values.Count -eq 0) {
        return 0
    }
    $sorted = @($Values | Sort-Object)
    $index = [Math]::Ceiling($Percentile * $sorted.Count) - 1
    $index = [Math]::Max(0, [Math]::Min($index, $sorted.Count - 1))
    return [Math]::Round([double]$sorted[$index], 3)
}

function Get-ControlBytes([object]$PilotResult) {
    [long]$total = 0
    foreach ($repository in @($PilotResult.repositories)) {
        $controlRoot = Join-Path $repository.snapshot_repository ".aos"
        if (Test-Path -LiteralPath $controlRoot -PathType Container) {
            $measure = Get-ChildItem -LiteralPath $controlRoot -File -Recurse |
                Measure-Object -Property Length -Sum
            if ($null -ne $measure.Sum) {
                $total += [long]$measure.Sum
            }
        }
    }
    return $total
}

function Write-ImmutableJson([string]$Path, [object]$Value) {
    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    try {
        $writer = New-Object System.IO.StreamWriter($stream, $utf8NoBom)
        try {
            $writer.Write(($Value | ConvertTo-Json -Depth 12))
            $writer.Flush()
        } finally {
            $writer.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $p6OnePilot -PathType Leaf)) {
    throw "P6.1 pilot harness not found: $p6OnePilot"
}
New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null
New-Item -ItemType Directory -Path $samplesRoot -Force | Out-Null

$existingObservations = @(
    Get-ChildItem -LiteralPath $samplesRoot -File -Filter "*.json" |
        Sort-Object -Property Name |
        ForEach-Object {
            Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        }
)
$newObservations = @()
$sampleFailure = $false

for ($sample = 1; $sample -le $SamplesPerRun; $sample++) {
    $sampleId = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
    $sampleOutput = Join-Path $rawRoot $sampleId
    $started = [DateTime]::UtcNow
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $arguments = @{
            RepositoryPath = $RepositoryPath
            Repeats = $Repeats
            OutputDir = $sampleOutput
        }
        if (-not [string]::IsNullOrWhiteSpace($AosBinary)) {
            $arguments.AosBinary = $AosBinary
        }
        $output = @(& $p6OnePilot @arguments 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw ($output -join [Environment]::NewLine)
        }
        $resultLine = $output |
            Where-Object { "$_".StartsWith("Result: ") } |
            Select-Object -Last 1
        if ($null -eq $resultLine) {
            throw "P6.1 pilot did not report its result path"
        }
        $resultPath = "$resultLine".Substring("Result: ".Length).Trim()
        $pilotResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        if ($pilotResult.result -ne "pass" -or $pilotResult.source_mutation -ne "none") {
            throw "P6.1 pilot result is not a non-mutating pass"
        }
        $stopwatch.Stop()
        $elapsedMilliseconds = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
        $extensionRuns = [int]$pilotResult.total_extension_runs
        $newObservations += [pscustomobject][ordered]@{
            sample_id = $sampleId
            sampled_at_utc = $started.ToString("o")
            status = "pass"
            elapsed_ms = $elapsedMilliseconds
            extension_runs = $extensionRuns
            milliseconds_per_extension_run = [Math]::Round(
                $elapsedMilliseconds / [Math]::Max(1, $extensionRuns),
                3
            )
            repository_count = [int]$pilotResult.repository_count
            control_bytes = Get-ControlBytes $pilotResult
            source_mutation = "none"
            result_path = $resultPath
            result_sha256 = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
            repositories = @(
                $pilotResult.repositories | ForEach-Object {
                    [ordered]@{
                        source_repository = $_.source_repository
                        source_commit = $_.source_commit
                    }
                }
            )
        }
    } catch {
        $stopwatch.Stop()
        $sampleFailure = $true
        $newObservations += [pscustomobject][ordered]@{
            sample_id = $sampleId
            sampled_at_utc = $started.ToString("o")
            status = "fail"
            elapsed_ms = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
            extension_runs = 0
            milliseconds_per_extension_run = 0
            repository_count = $RepositoryPath.Count
            control_bytes = 0
            source_mutation = "unknown"
            result_path = $null
            result_sha256 = $null
            error = $_.Exception.Message
            repositories = @()
        }
    }
    Write-ImmutableJson (
        Join-Path $samplesRoot "$sampleId.json"
    ) ($newObservations | Select-Object -Last 1)
}

$observations = @($existingObservations) + @($newObservations)
$firstSample = [DateTime]::Parse(
    ($observations | Select-Object -First 1).sampled_at_utc
).ToUniversalTime()
$lastSample = [DateTime]::Parse(
    ($observations | Select-Object -Last 1).sampled_at_utc
).ToUniversalTime()
$elapsedDays = [Math]::Round(($lastSample - $firstSample).TotalDays, 6)
$passed = @($observations | Where-Object { $_.status -eq "pass" })
$failed = @($observations | Where-Object { $_.status -ne "pass" })
$integrityFailures = @(
    $passed | Where-Object {
        [string]::IsNullOrWhiteSpace($_.result_path) -or
        -not (Test-Path -LiteralPath $_.result_path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $_.result_path -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            $_.result_sha256
    }
)
$latencies = @($passed | ForEach-Object { [double]$_.milliseconds_per_extension_run })
$qualified = (
    $failed.Count -eq 0 -and
    $integrityFailures.Count -eq 0 -and
    $passed.Count -ge $MinimumSamples -and
    $elapsedDays -ge $MinimumDurationDays
)
$status = if ($qualified) { "qualified" } else { "active" }
$state = [ordered]@{
    schema_version = "AOS-P6-2-INSTALLED-PILOT-1"
    pilot_id = $PilotId
    status = $status
    qualification = [ordered]@{
        minimum_duration_days = $MinimumDurationDays
        minimum_samples = $MinimumSamples
        observed_duration_days = $elapsedDays
        passed_samples = $passed.Count
        failed_samples = $failed.Count
        integrity_failures = $integrityFailures.Count
        total_extension_runs = (
            $passed | Measure-Object -Property extension_runs -Sum
        ).Sum
        latency_ms_per_extension_run_p50 = Get-Percentile $latencies 0.50
        latency_ms_per_extension_run_p95 = Get-Percentile $latencies 0.95
        qualification_gate = if ($qualified) { "pass" } else { "active" }
    }
    observations = $observations
}
[System.IO.File]::WriteAllText(
    $statePath,
    ($state | ConvertTo-Json -Depth 12),
    $utf8NoBom
)

Write-Output "P6.2 pilot: $PilotId"
Write-Output "Status: $status"
Write-Output "Passed samples: $($passed.Count)"
Write-Output "Observed duration days: $elapsedDays"
Write-Output "Latency per extension Run p50/p95 ms: $(
    $state.qualification.latency_ms_per_extension_run_p50
)/$($state.qualification.latency_ms_per_extension_run_p95)"
Write-Output "State: $statePath"
Write-Output "AOS_P6_2_QUALIFICATION_SAMPLE_OK"
if ($qualified) {
    Write-Output "AOS_P6_2_DURATION_GATE_OK"
} else {
    Write-Output "AOS_P6_2_DURATION_GATE_ACTIVE"
}
if ($sampleFailure) {
    throw "one or more P6.2 qualification samples failed; inspect $statePath"
}
$global:LASTEXITCODE = 0
