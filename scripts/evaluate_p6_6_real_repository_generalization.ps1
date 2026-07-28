[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ResultPath,
    [string]$ManifestPath = "",
    [string]$OutputDir = "",
    [double]$MinimumTokenReductionPercent = 25,
    [double]$MinimumTimeReductionPercent = 20,
    [double]$MinimumCommandReductionPercent = 20,
    [double]$MaximumSuccessRegressionPercent = 5,
    [double]$MaximumRepeatDriftPercent = 10,
    [switch]$SyntheticSmoke
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $scriptRoot "..\benchmarks\p6-6\scenarios.json"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-6-generalization"
}
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

function Fail([string]$Message) {
    throw "AOS_P6_6_GENERALIZATION_EVALUATION_FAILED: $Message"
}

function Get-Reduction([double]$Baseline, [double]$Candidate) {
    if ($Baseline -le 0) {
        return 0
    }
    return [Math]::Round((($Baseline - $Candidate) / $Baseline) * 100, 3)
}

function Get-Percent([int]$Passed, [int]$Total) {
    if ($Total -eq 0) {
        return 0
    }
    return [Math]::Round(($Passed / $Total) * 100, 3)
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Fail "manifest does not exist: $ManifestPath"
}
if ($ResultPath.Count -lt 3) {
    Fail "at least three repository batch results are required"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$manifestScenarios = @($manifest.scenarios)
if ($manifestScenarios.Count -ne 15) {
    Fail "P6.6 manifest must contain exactly 15 scenarios"
}

$expectedScenarioIds = @($manifestScenarios | ForEach-Object { [string]$_.id })
$expectedRepositories = @(
    $manifestScenarios |
        ForEach-Object { [string]$_.repository_env } |
        Sort-Object -Unique
)
if ($expectedRepositories.Count -ne 3) {
    Fail "P6.6 must cover exactly three repository environments"
}

$expectedCommitByEnvironment = @{}
foreach ($repositoryEnvironment in $expectedRepositories) {
    $commits = @(
        $manifestScenarios |
            Where-Object { [string]$_.repository_env -eq $repositoryEnvironment } |
            ForEach-Object { [string]$_.expected_commit } |
            Sort-Object -Unique
    )
    if ($commits.Count -ne 1) {
        Fail "repository environment must bind one commit: $repositoryEnvironment"
    }
    $expectedCommitByEnvironment[$repositoryEnvironment] = $commits[0]
}

$results = @()
$allRuns = @()
$coveredScenarioIds = @()
foreach ($path in $ResultPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "result does not exist: $path"
    }
    $result = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($result.schema_version -ne "AOS-P4-AI-FACING-BENCHMARK-1") {
        Fail "unsupported benchmark result schema: $path"
    }
    if ($result.agent_policy -ne "p6.5") {
        Fail "result was not produced with the P6.5 policy: $path"
    }
    if ([int]$result.repeats -ne 2) {
        Fail "result must contain exactly two repeats: $path"
    }
    if ($result.qualification_level -ne "patch-and-test") {
        Fail "result is not patch-and-test qualified: $path"
    }
    if (@($result.repository_commits.PSObject.Properties).Count -ne 3) {
        Fail "result must bind exactly three repository commits: $path"
    }
    foreach ($property in $result.repository_commits.PSObject.Properties) {
        $environmentName = switch ($property.Name) {
            "aos" { "AOS_REPO" }
            "trenux" { "TRENUX_REPO" }
            "trenux-rust" { "TRENUX_RUST_REPO" }
            default { Fail "unknown repository commit key: $($property.Name)" }
        }
        if ([string]$property.Value -ne [string]$expectedCommitByEnvironment[$environmentName]) {
            Fail "snapshot commit mismatch for $environmentName in $path"
        }
    }
    $resultRuns = @($result.runs)
    $batchScenarioIds = @(
        $resultRuns |
            ForEach-Object { [string]$_.scenario_id } |
            Sort-Object -Unique
    )
    foreach ($scenarioId in $batchScenarioIds) {
        if ($expectedScenarioIds -notcontains $scenarioId) {
            Fail "unexpected scenario in result: $scenarioId"
        }
        if ($coveredScenarioIds -contains $scenarioId) {
            Fail "scenario appears in more than one batch: $scenarioId"
        }
        $scenarioRuns = @($resultRuns | Where-Object {
            [string]$_.scenario_id -eq $scenarioId
        })
        if ($scenarioRuns.Count -ne 4) {
            Fail "scenario must contain baseline/AOS x two repeats: $scenarioId"
        }
        foreach ($mode in @("baseline", "aos")) {
            $modeRuns = @($scenarioRuns | Where-Object { $_.mode -eq $mode })
            if ($modeRuns.Count -ne 2 -or
                @($modeRuns | ForEach-Object { [int]$_.repeat } | Sort-Object -Unique).Count -ne 2) {
                Fail "scenario has incomplete repeats for mode ${mode}: $scenarioId"
            }
        }
        $coveredScenarioIds += $scenarioId
    }
    $results += $result
    $allRuns += $resultRuns
}

$coveredScenarioIds = @($coveredScenarioIds | Sort-Object -Unique)
$missingScenarioIds = @($expectedScenarioIds | Where-Object {
    $coveredScenarioIds -notcontains $_
})
if ($missingScenarioIds.Count -ne 0) {
    Fail "missing scenarios: $($missingScenarioIds -join ', ')"
}
if ($allRuns.Count -ne 60) {
    Fail "expected 60 executions, found $($allRuns.Count)"
}

$scenarioDetails = @()
foreach ($scenario in $manifestScenarios) {
    $scenarioId = [string]$scenario.id
    $scenarioRuns = @($allRuns | Where-Object { $_.scenario_id -eq $scenarioId })
    $baselineRuns = @($scenarioRuns | Where-Object { $_.mode -eq "baseline" })
    $aosRuns = @($scenarioRuns | Where-Object { $_.mode -eq "aos" })
    $aosInputs = @($aosRuns | ForEach-Object { [double]$_.input_tokens })
    $inputMean = [double](($aosInputs | Measure-Object -Average).Average)
    $inputSpread = [double](($aosInputs | Measure-Object -Maximum).Maximum) -
        [double](($aosInputs | Measure-Object -Minimum).Minimum)
    $repeatDrift = if ($inputMean -gt 0) {
        [Math]::Round(($inputSpread / $inputMean) * 100, 3)
    } else {
        0
    }
    $scenarioDetails += [pscustomobject][ordered]@{
        scenario_id = $scenarioId
        repository_env = [string]$scenario.repository_env
        task_type = [string]$scenario.task_type
        baseline_success = @($baselineRuns | Where-Object { $_.task_success }).Count -eq 2
        aos_success = @($aosRuns | Where-Object { $_.task_success }).Count -eq 2
        input_token_reduction_percent = Get-Reduction `
            ([double](($baselineRuns.input_tokens | Measure-Object -Sum).Sum)) `
            ([double](($aosRuns.input_tokens | Measure-Object -Sum).Sum))
        elapsed_reduction_percent = Get-Reduction `
            ([double](($baselineRuns.elapsed_seconds | Measure-Object -Sum).Sum)) `
            ([double](($aosRuns.elapsed_seconds | Measure-Object -Sum).Sum))
        command_reduction_percent = Get-Reduction `
            ([double](($baselineRuns.command_count | Measure-Object -Sum).Sum)) `
            ([double](($aosRuns.command_count | Measure-Object -Sum).Sum))
        aos_input_repeat_drift_percent = $repeatDrift
        scope_safe = @($aosRuns | Where-Object {
            -not $_.source_scope_preserved -or [int]$_.mcp_call_count -ne 0
        }).Count -eq 0
    }
}

$baselineRuns = @($allRuns | Where-Object { $_.mode -eq "baseline" })
$aosRuns = @($allRuns | Where-Object { $_.mode -eq "aos" })
$baselineInput = [double](($baselineRuns.input_tokens | Measure-Object -Sum).Sum)
$aosInput = [double](($aosRuns.input_tokens | Measure-Object -Sum).Sum)
$baselineElapsed = [double](($baselineRuns.elapsed_seconds | Measure-Object -Sum).Sum)
$aosElapsed = [double](($aosRuns.elapsed_seconds | Measure-Object -Sum).Sum)
$baselineCommands = [double](($baselineRuns.command_count | Measure-Object -Sum).Sum)
$aosCommands = [double](($aosRuns.command_count | Measure-Object -Sum).Sum)
$baselineSuccess = Get-Percent `
    (@($baselineRuns | Where-Object { $_.task_success }).Count) $baselineRuns.Count
$aosSuccess = Get-Percent `
    (@($aosRuns | Where-Object { $_.task_success }).Count) $aosRuns.Count
$comparison = [ordered]@{
    input_token_reduction_percent = Get-Reduction $baselineInput $aosInput
    elapsed_reduction_percent = Get-Reduction $baselineElapsed $aosElapsed
    command_reduction_percent = Get-Reduction $baselineCommands $aosCommands
    baseline_task_success_percent = $baselineSuccess
    aos_task_success_percent = $aosSuccess
    maximum_aos_repeat_drift_percent = [double](
        ($scenarioDetails.aos_input_repeat_drift_percent | Measure-Object -Maximum).Maximum
    )
}

$repositoryDetails = @()
foreach ($repositoryEnvironment in $expectedRepositories) {
    $repositoryScenarios = @($scenarioDetails | Where-Object {
        $_.repository_env -eq $repositoryEnvironment
    })
    $repositoryDetails += [pscustomobject][ordered]@{
        repository_env = $repositoryEnvironment
        fixed_commit = [string]$expectedCommitByEnvironment[$repositoryEnvironment]
        scenario_count = $repositoryScenarios.Count
        task_types = @($repositoryScenarios.task_type | Sort-Object -Unique)
        aos_success_count = @($repositoryScenarios | Where-Object { $_.aos_success }).Count
        scope_safe = @($repositoryScenarios | Where-Object { -not $_.scope_safe }).Count -eq 0
    }
}

$thresholds = [ordered]@{
    three_fixed_repositories = $repositoryDetails.Count -eq 3 -and
        @($repositoryDetails | Where-Object { $_.scenario_count -ne 5 }).Count -eq 0
    five_task_types_per_repository = @($repositoryDetails | Where-Object {
        $_.task_types.Count -ne 5
    }).Count -eq 0
    sixty_executions = $allRuns.Count -eq 60
    total_input_reduction_at_least_25_percent =
        $comparison.input_token_reduction_percent -ge $MinimumTokenReductionPercent
    elapsed_reduction_at_least_20_percent =
        $comparison.elapsed_reduction_percent -ge $MinimumTimeReductionPercent
    command_reduction_at_least_20_percent =
        $comparison.command_reduction_percent -ge $MinimumCommandReductionPercent
    task_success_regression_at_most_5_percent =
        $comparison.aos_task_success_percent -ge
            ($comparison.baseline_task_success_percent - $MaximumSuccessRegressionPercent)
    all_aos_tasks_success = @($aosRuns | Where-Object { -not $_.task_success }).Count -eq 0
    all_aos_verification_passed = @($aosRuns | Where-Object {
        -not $_.verification_passed
    }).Count -eq 0
    scope_and_isolation_preserved = @($aosRuns | Where-Object {
        -not $_.source_scope_preserved -or [int]$_.mcp_call_count -ne 0
    }).Count -eq 0
    optimized_repeat_drift_at_most_10_percent =
        $comparison.maximum_aos_repeat_drift_percent -le $MaximumRepeatDriftPercent
}
$allPass = @($thresholds.Values | Where-Object { -not $_ }).Count -eq 0

$evaluationId = "p6-6-generalization-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$evaluationRoot = Join-Path $OutputDir $evaluationId
New-Item -ItemType Directory -Path $evaluationRoot -Force | Out-Null
$evaluation = [ordered]@{
    schema_version = "AOS-P6-6-REAL-REPOSITORY-GENERALIZATION-1"
    evaluation_id = $evaluationId
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    manifest_path = $ManifestPath
    result_paths = @($ResultPath | ForEach-Object {
        [System.IO.Path]::GetFullPath($_)
    })
    repository_count = $repositoryDetails.Count
    scenario_count = $scenarioDetails.Count
    execution_count = $allRuns.Count
    baseline = [ordered]@{
        input_tokens = [int64]$baselineInput
        elapsed_seconds = [Math]::Round($baselineElapsed, 3)
        command_count = [int]$baselineCommands
        task_success_percent = $baselineSuccess
    }
    aos = [ordered]@{
        input_tokens = [int64]$aosInput
        elapsed_seconds = [Math]::Round($aosElapsed, 3)
        command_count = [int]$aosCommands
        task_success_percent = $aosSuccess
    }
    comparison = $comparison
    repositories = $repositoryDetails
    scenarios = $scenarioDetails
    thresholds = $thresholds
    status = if ($allPass) { "PASS" } else { "FAIL" }
    marker = if ($allPass -and $SyntheticSmoke) {
        "AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_EVALUATOR_SMOKE_OK"
    } elseif ($allPass) {
        "AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_OK"
    } else {
        "AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_NOT_MET"
    }
}
$evaluationPath = Join-Path $evaluationRoot "p6-6-real-repository-generalization.json"
[System.IO.File]::WriteAllText(
    $evaluationPath,
    ($evaluation | ConvertTo-Json -Depth 12),
    $utf8NoBom
)

Write-Output "P6.6 generalization evaluation: $evaluationId"
Write-Output "Repositories/scenarios/executions: $($repositoryDetails.Count)/$($scenarioDetails.Count)/$($allRuns.Count)"
Write-Output "Input reduction: $($comparison.input_token_reduction_percent)%"
Write-Output "Elapsed reduction: $($comparison.elapsed_reduction_percent)%"
Write-Output "Command reduction: $($comparison.command_reduction_percent)%"
Write-Output "Task success: $baselineSuccess% -> $aosSuccess%"
Write-Output "Maximum optimized repeat drift: $($comparison.maximum_aos_repeat_drift_percent)%"
Write-Output "Result: $evaluationPath"
Write-Output $evaluation.marker
if (-not $allPass) {
    exit 1
}
