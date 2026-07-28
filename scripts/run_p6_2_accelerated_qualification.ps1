[CmdletBinding()]
param(
    [string]$OfficialRoot = "D:\AOS-PILOT-EVIDENCE\p6-2-production-like-official",
    [string]$OutputDir = "D:\AOS-PILOT-EVIDENCE",
    [ValidateRange(8, 10)]
    [int]$TargetSamples = 8
)

$ErrorActionPreference = "Stop"
$pinRoot = Join-Path $OfficialRoot "pinned\4031c3e"
$pinManifestPath = Join-Path $pinRoot "pin-manifest.json"
$pilotId = "p6-2-accelerated-qualification"
$statePath = Join-Path (Join-Path $OutputDir $pilotId) "pilot-state.json"

function Fail([string]$Message) {
    throw "AOS_P6_2_ACCELERATED_QUALIFICATION_FAILED: $Message"
}

if (-not (Test-Path -LiteralPath $pinManifestPath -PathType Leaf)) {
    Fail "pin manifest does not exist: $pinManifestPath"
}

$pinManifest = Get-Content -LiteralPath $pinManifestPath -Raw | ConvertFrom-Json
foreach ($file in $pinManifest.files) {
    $path = Join-Path $pinRoot ([string]$file.relative_path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "pinned file does not exist: $path"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne [string]$file.sha256) {
        Fail "pinned file digest mismatch: $($file.relative_path)"
    }
}

$repositorySpecifications = @(
    [ordered]@{
        path = Join-Path $OfficialRoot "repositories\aos-4031c3e"
        commit = "4031c3e596dc5dc846d46a0c115dac50088bf19c"
    },
    [ordered]@{
        path = Join-Path $OfficialRoot "repositories\trenux-rust-3297389"
        commit = "3297389bd35ff3e8eb129dc74308ec3c8d165bf2"
    },
    [ordered]@{
        path = Join-Path $OfficialRoot "repositories\trenux-020b1ca"
        commit = "020b1ca41824bd0e13d7552136ec6fd1b8ba5f20"
    }
)

foreach ($repository in $repositorySpecifications) {
    if (-not (Test-Path -LiteralPath $repository.path -PathType Container)) {
        Fail "detached repository does not exist: $($repository.path)"
    }
    $head = (& git -C $repository.path rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -ne $repository.commit) {
        Fail "detached repository commit drift: $($repository.path)"
    }
    $dirty = @(& git -C $repository.path status --porcelain=v1)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
        Fail "detached repository is not clean: $($repository.path)"
    }
}

$existingPassed = 0
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $existing = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $existingPassed = [int]$existing.qualification.passed_samples
}
$remaining = [Math]::Max(0, $TargetSamples - $existingPassed)
if ($remaining -gt 0) {
    $sampleHarness = Join-Path $pinRoot "scripts\run_p6_2_installed_pilot_sample.ps1"
    $binary = Join-Path $pinRoot "target\debug\aos.exe"
    $output = @(
        & $sampleHarness `
            -RepositoryPath @($repositorySpecifications.path) `
            -SamplesPerRun $remaining `
            -Repeats 2 `
            -MinimumDurationDays 0 `
            -MinimumSamples $TargetSamples `
            -PilotId $pilotId `
            -AosBinary $binary `
            -OutputDir $OutputDir 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        Fail ($output -join [Environment]::NewLine)
    }
}

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    Fail "accelerated pilot state was not written"
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$qualification = $state.qualification
if ($state.status -ne "qualified" -or
    $qualification.qualification_gate -ne "pass" -or
    [int]$qualification.passed_samples -lt $TargetSamples -or
    [int]$qualification.failed_samples -ne 0 -or
    [int]$qualification.integrity_failures -ne 0 -or
    [int]$qualification.total_extension_runs -lt ($TargetSamples * 12)) {
    Fail "accelerated aggregate gate did not pass"
}

foreach ($observation in $state.observations) {
    if ($observation.status -ne "pass" -or
        $observation.source_mutation -ne "none" -or
        [int]$observation.repository_count -ne 3) {
        Fail "sample invariant failed: $($observation.sample_id)"
    }
    if (-not (Test-Path -LiteralPath $observation.result_path -PathType Leaf)) {
        Fail "nested result is missing: $($observation.sample_id)"
    }
    $actualResultDigest = (
        Get-FileHash -LiteralPath $observation.result_path -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if ($actualResultDigest -ne [string]$observation.result_sha256) {
        Fail "nested result digest mismatch: $($observation.sample_id)"
    }
    $nested = Get-Content -LiteralPath $observation.result_path -Raw | ConvertFrom-Json
    if ($nested.result -ne "pass" -or
        $nested.source_mutation -ne "none" -or
        [int]$nested.repository_count -ne 3 -or
        [int]$nested.total_extension_runs -ne 12) {
        Fail "nested P6.1 result failed: $($observation.sample_id)"
    }
    foreach ($repository in $nested.repositories) {
        if ($repository.source_mutated -or
            @($repository.capabilities | Where-Object {
                -not $_.deterministic
            }).Count -ne 0) {
            Fail "nested determinism or mutation invariant failed: $($observation.sample_id)"
        }
    }
}

Write-Output "P6.2 accelerated qualification: $pilotId"
Write-Output "Samples: $($qualification.passed_samples)"
Write-Output "Extension Runs: $($qualification.total_extension_runs)"
Write-Output "Latency p50/p95 ms: $($qualification.latency_ms_per_extension_run_p50)/$($qualification.latency_ms_per_extension_run_p95)"
Write-Output "State: $statePath"
Write-Output "AOS_P6_2_ACCELERATED_QUALIFICATION_OK"
