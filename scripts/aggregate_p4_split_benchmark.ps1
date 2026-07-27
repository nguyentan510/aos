[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ResultPath,
    [ValidateSet("aos", "trenux_rust")]
    [string]$RepositoryKey,
    [int]$MinimumRepeatsPerScenario = 2,
    [double]$MinimumTokenReductionPercent = 25,
    [double]$MinimumTimeReductionPercent = 20,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p4-split-aggregate"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_P4_SPLIT_AGGREGATE_FAILED: $Message"
}

$results = @(
    $ResultPath |
        ForEach-Object {
            if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
                Fail "result does not exist: $_"
            }
            try {
                Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json
            } catch {
                Fail "result is not valid JSON: $_"
            }
        }
)
if ($results.Count -eq 0) {
    Fail "at least one result is required"
}

foreach ($result in $results) {
    if ($result.schema_version -ne "AOS-P4-AI-FACING-BENCHMARK-1") {
        Fail "unsupported result schema"
    }
    if ($result.qualification_level -ne "patch-and-test" -or
        -not $result.qualification_ready) {
        Fail "result is not patch-and-test qualified: $($result.run_id)"
    }
}

$models = @($results.model | Select-Object -Unique)
$providers = @($results.provider | Select-Object -Unique)
$commits = @(
    $results |
        ForEach-Object { $_.repository_commits.$RepositoryKey } |
        Select-Object -Unique
)
if ($models.Count -ne 1 -or $providers.Count -ne 1 -or $commits.Count -ne 1) {
    Fail "model, provider, and repository commit must be identical"
}

$runs = @($results | ForEach-Object { $_.runs })
$scenarioIds = @($runs.scenario_id | Select-Object -Unique)
$repeatCoverage = @()
foreach ($scenarioId in $scenarioIds) {
    foreach ($mode in @("baseline", "aos")) {
        $modeRuns = @(
            $runs |
                Where-Object {
                    $_.scenario_id -eq $scenarioId -and $_.mode -eq $mode
                }
        )
        $repeatCoverage += [pscustomobject]@{
            scenario_id = $scenarioId
            mode = $mode
            repeat_count = $modeRuns.Count
        }
    }
}

$repeatPass = @(
    $repeatCoverage |
        Where-Object { $_.repeat_count -lt $MinimumRepeatsPerScenario }
).Count -eq 0
$taskSuccess = @($runs | Where-Object { -not $_.task_success }).Count -eq 0
$verificationPass = $true
foreach ($run in $runs) {
    $expectedPatchFiles = @($run.expected_patch_files)
    $changedFiles = @($run.changed_files)
    $missingPatchFiles = @(
        $expectedPatchFiles |
            Where-Object { $changedFiles -notcontains [string]$_ }
    )
    if (-not $run.verification_passed -or
        $expectedPatchFiles.Count -eq 0 -or
        $missingPatchFiles.Count -gt 0) {
        $verificationPass = $false
    }
}
$structuralPass = @(
    $results |
        Where-Object {
            -not $_.thresholds.structural_context -or
            -not $_.thresholds.withholding_reasons
        }
).Count -eq 0

$baselineRuns = @($runs | Where-Object { $_.mode -eq "baseline" })
$aosRuns = @($runs | Where-Object { $_.mode -eq "aos" })
$baselineTokens = [double](($baselineRuns | Measure-Object input_tokens -Sum).Sum)
$aosTokens = [double](($aosRuns | Measure-Object input_tokens -Sum).Sum)
$baselineTime = [double](($baselineRuns | Measure-Object elapsed_seconds -Sum).Sum)
$aosTime = [double](($aosRuns | Measure-Object elapsed_seconds -Sum).Sum)
$baselineFirstPatch = [double]((
    $baselineRuns |
        ForEach-Object { $_.timing.time_to_first_patch_seconds } |
        Measure-Object -Sum
).Sum)
$aosFirstPatch = [double]((
    $aosRuns |
        ForEach-Object { $_.timing.time_to_first_patch_seconds } |
        Measure-Object -Sum
).Sum)

$tokenReduction = if ($baselineTokens -gt 0) {
    100 * (1 - ($aosTokens / $baselineTokens))
} else { 0 }
$timeReduction = if ($baselineTime -gt 0) {
    100 * (1 - ($aosTime / $baselineTime))
} else { 0 }
$firstPatchReduction = if ($baselineFirstPatch -gt 0) {
    100 * (1 - ($aosFirstPatch / $baselineFirstPatch))
} else { 0 }

$thresholds = [ordered]@{
    token_reduction = $tokenReduction -ge $MinimumTokenReductionPercent
    time_reduction = $timeReduction -ge $MinimumTimeReductionPercent
    repeat_coverage = $repeatPass
    task_success = $taskSuccess
    patch_and_verification = $verificationPass
    structural_context = $structuralPass
}
$pass = @($thresholds.Values | Where-Object { -not $_ }).Count -eq 0
$marker = if ($pass) {
    "AOS_P4_VALUE_BENCHMARK_OK"
} else {
    "AOS_P4_VALUE_BENCHMARK_NOT_MET"
}

$runId = "p4-aggregate-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$root = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Path $root -Force | Out-Null
$aggregate = [ordered]@{
    schema_version = "AOS-P4-SPLIT-AGGREGATE-1"
    run_id = $runId
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    repository_key = $RepositoryKey
    repository_commit = $commits[0]
    model = $models[0]
    provider = $providers[0]
    source_run_ids = @($results.run_id)
    scenario_count = $scenarioIds.Count
    minimum_repeats_per_scenario = $MinimumRepeatsPerScenario
    repeat_coverage = $repeatCoverage
    metrics = [ordered]@{
        baseline_input_tokens = [int64]$baselineTokens
        aos_input_tokens = [int64]$aosTokens
        token_reduction_percent = [Math]::Round($tokenReduction, 2)
        baseline_elapsed_seconds = [Math]::Round($baselineTime, 3)
        aos_elapsed_seconds = [Math]::Round($aosTime, 3)
        time_reduction_percent = [Math]::Round($timeReduction, 2)
        baseline_time_to_first_patch_seconds = [Math]::Round($baselineFirstPatch, 3)
        aos_time_to_first_patch_seconds = [Math]::Round($aosFirstPatch, 3)
        time_to_first_patch_reduction_percent = [Math]::Round($firstPatchReduction, 2)
        baseline_task_success = "$(@($baselineRuns | Where-Object { $_.task_success }).Count)/$($baselineRuns.Count)"
        aos_task_success = "$(@($aosRuns | Where-Object { $_.task_success }).Count)/$($aosRuns.Count)"
    }
    thresholds = $thresholds
    status = if ($pass) { "PASS" } else { "FAIL" }
    pass_marker = $marker
}
$resultPath = Join-Path $root "aggregate-results.json"
[System.IO.File]::WriteAllText(
    $resultPath,
    ($aggregate | ConvertTo-Json -Depth 8),
    $utf8NoBom
)

Write-Output "P4 split aggregate: $runId"
Write-Output "Repository: $RepositoryKey@$($commits[0])"
Write-Output "Token reduction: $([Math]::Round($tokenReduction, 2))%"
Write-Output "Time reduction: $([Math]::Round($timeReduction, 2))%"
Write-Output "Time-to-first-patch reduction: $([Math]::Round($firstPatchReduction, 2))%"
Write-Output "Result: $resultPath"
Write-Output $marker
