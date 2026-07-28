[CmdletBinding()]
param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $scriptRoot "..\benchmarks\p6-6\scenarios.json"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-6-evaluator-smoke"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$fixtureRoot = Join-Path $OutputDir "fixtures"
$evaluationRoot = Join-Path $OutputDir "evaluation"
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$repositoryCommits = [ordered]@{
    aos = [string](
        $manifest.scenarios |
            Where-Object { $_.repository_env -eq "AOS_REPO" } |
            Select-Object -First 1
    ).expected_commit
    trenux = [string](
        $manifest.scenarios |
            Where-Object { $_.repository_env -eq "TRENUX_REPO" } |
            Select-Object -First 1
    ).expected_commit
    "trenux-rust" = [string](
        $manifest.scenarios |
            Where-Object { $_.repository_env -eq "TRENUX_RUST_REPO" } |
            Select-Object -First 1
    ).expected_commit
}

$resultPaths = @()
foreach ($repositoryEnvironment in @("AOS_REPO", "TRENUX_RUST_REPO", "TRENUX_REPO")) {
    $runs = @()
    $scenarios = @($manifest.scenarios | Where-Object {
        $_.repository_env -eq $repositoryEnvironment
    })
    foreach ($scenario in $scenarios) {
        foreach ($repeat in @(1, 2)) {
            $runs += [pscustomobject][ordered]@{
                scenario_id = [string]$scenario.id
                mode = "baseline"
                repeat = $repeat
                task_success = $true
                input_tokens = 1000
                elapsed_seconds = 100
                command_count = 10
                mcp_call_count = 0
                source_scope_preserved = $true
                verification_passed = $true
            }
            $runs += [pscustomobject][ordered]@{
                scenario_id = [string]$scenario.id
                mode = "aos"
                repeat = $repeat
                task_success = $true
                input_tokens = if ($repeat -eq 1) { 600 } else { 620 }
                elapsed_seconds = 70
                command_count = 6
                mcp_call_count = 0
                source_scope_preserved = $true
                verification_passed = $true
            }
        }
    }
    $result = [ordered]@{
        schema_version = "AOS-P4-AI-FACING-BENCHMARK-1"
        run_id = "fixture-$($repositoryEnvironment.ToLowerInvariant())"
        agent_policy = "p6.5"
        repeats = 2
        qualification_level = "patch-and-test"
        repository_commits = $repositoryCommits
        runs = $runs
    }
    $resultPath = Join-Path $fixtureRoot "$repositoryEnvironment.json"
    [System.IO.File]::WriteAllText(
        $resultPath,
        ($result | ConvertTo-Json -Depth 8),
        $utf8NoBom
    )
    $resultPaths += $resultPath
}

$output = & (Join-Path $scriptRoot "evaluate_p6_6_real_repository_generalization.ps1") `
    -ResultPath $resultPaths `
    -ManifestPath $manifestPath `
    -OutputDir $evaluationRoot `
    -SyntheticSmoke
if (@($output | Where-Object {
    $_ -eq "AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_EVALUATOR_SMOKE_OK"
}).Count -ne 1) {
    throw "P6.6 evaluator smoke marker is missing"
}

$output
Write-Output "AOS_P6_6_EVALUATOR_SMOKE_OK"
