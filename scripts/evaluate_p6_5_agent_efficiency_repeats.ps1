[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ResultPath,
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if (-not $OutputDir) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-5-efficiency-evaluation"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

function Fail([string]$Message) {
    throw "AOS_P6_5_EFFICIENCY_EVALUATION_FAILED: $Message"
}

function Get-PercentReduction([double]$Baseline, [double]$Candidate) {
    if ($Baseline -le 0) {
        return 0
    }
    [Math]::Round((($Baseline - $Candidate) / $Baseline) * 100, 3)
}

if ($ResultPath.Count -lt 2) {
    Fail "at least two independent P6.5 result paths are required"
}

$results = @()
foreach ($path in $ResultPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "result does not exist: $path"
    }
    $result = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($result.schema_version -ne "AOS-P6-5-AGENT-EFFICIENCY-1") {
        Fail "unsupported result schema: $path"
    }
    if ([int]$result.optimized.totals.task_success_count -ne 3) {
        Fail "optimized task success is incomplete: $path"
    }
    foreach ($run in $result.optimized.runs) {
        if ($run.PSObject.Properties.Name -notcontains "batched_source_read") {
            $commands = @($run.commands)
            $batchedSourceRead = @($commands | Where-Object {
                $_ -match "Cargo\.toml" -and
                $_ -match "src[\\/]+lib\.rs"
            }).Count -eq 1
            $singleVerificationCall = @($commands | Where-Object {
                $_ -match "(?i)cargo\s+test"
            }).Count -eq 1
            $forbiddenCommandScope = @($commands | Where-Object {
                $_ -match "(?i)(Get-ChildItem|Select-String|\brg\b|\bgrep\b|git\s+(show|log|ls-files))" -or
                $_ -match "(?i)(README|notes[\\/]|\.aos[\\/])"
            }).Count -ne 0
            $run | Add-Member -NotePropertyName "batched_source_read" `
                -NotePropertyValue $batchedSourceRead
            $run | Add-Member -NotePropertyName "single_verification_call" `
                -NotePropertyValue $singleVerificationCall
            $run | Add-Member -NotePropertyName "bounded_tool_loop" `
                -NotePropertyValue ([int]$run.command_count -le 2)
            $run | Add-Member -NotePropertyName "forbidden_command_scope" `
                -NotePropertyValue $forbiddenCommandScope
        }
    }
    if (@($result.optimized.runs | Where-Object {
        -not $_.verification_passed -or
        -not $_.control_data_unchanged -or
        -not $_.source_scope_preserved -or
        -not $_.batched_source_read -or
        -not $_.single_verification_call -or
        -not $_.bounded_tool_loop -or
        $_.forbidden_command_scope -or
        [int]$_.mcp_call_count -ne 0
    }).Count -ne 0) {
        Fail "an optimized safety or verification invariant failed: $path"
    }
    $results += $result
}

$baselineJson = $results[0].baseline.totals | ConvertTo-Json -Compress
foreach ($result in $results) {
    if (($result.baseline.totals | ConvertTo-Json -Compress) -ne $baselineJson) {
        Fail "repeat results do not share the same frozen baseline"
    }
}

$baseline = $results[0].baseline.totals
$optimizedInput = @(
    $results | ForEach-Object { [double]$_.optimized.totals.input_tokens }
)
$optimizedCached = @(
    $results | ForEach-Object { [double]$_.optimized.totals.cached_input_tokens }
)
$optimizedUncached = @(
    $results | ForEach-Object { [double]$_.optimized.totals.uncached_input_tokens }
)
$optimizedOutput = @(
    $results | ForEach-Object { [double]$_.optimized.totals.output_tokens }
)
$optimizedCommands = @(
    $results | ForEach-Object { [double]$_.optimized.totals.command_count }
)
$optimizedElapsed = @(
    $results | ForEach-Object { [double]$_.optimized.totals.elapsed_seconds }
)

function Get-Average([double[]]$Values) {
    [Math]::Round([double](($Values | Measure-Object -Average).Average), 3)
}

$average = [ordered]@{
    input_tokens = Get-Average $optimizedInput
    cached_input_tokens = Get-Average $optimizedCached
    uncached_input_tokens = Get-Average $optimizedUncached
    output_tokens = Get-Average $optimizedOutput
    command_count = Get-Average $optimizedCommands
    elapsed_seconds = Get-Average $optimizedElapsed
}
$inputMean = [double]$average.input_tokens
$inputSpread = [double](($optimizedInput | Measure-Object -Maximum).Maximum) -
    [double](($optimizedInput | Measure-Object -Minimum).Minimum)
$inputDriftPercent = if ($inputMean -gt 0) {
    [Math]::Round(($inputSpread / $inputMean) * 100, 3)
} else {
    0
}
$comparison = [ordered]@{
    input_token_reduction_percent = Get-PercentReduction `
        ([double]$baseline.input_tokens) ([double]$average.input_tokens)
    uncached_input_token_reduction_percent = Get-PercentReduction `
        ([double]$baseline.uncached_input_tokens) ([double]$average.uncached_input_tokens)
    output_token_reduction_percent = Get-PercentReduction `
        ([double]$baseline.output_tokens) ([double]$average.output_tokens)
    command_reduction_percent = Get-PercentReduction `
        ([double]$baseline.command_count) ([double]$average.command_count)
    elapsed_reduction_percent = Get-PercentReduction `
        ([double]$baseline.elapsed_seconds) ([double]$average.elapsed_seconds)
    optimized_input_repeat_drift_percent = $inputDriftPercent
}
$thresholds = [ordered]@{
    repeats_at_least_two = $results.Count -ge 2
    task_success_preserved = @($results | Where-Object {
        [int]$_.optimized.totals.task_success_count -ne 3
    }).Count -eq 0
    verification_and_safety_preserved = @($results | Where-Object {
        @($_.optimized.runs | Where-Object {
            -not $_.verification_passed -or
            -not $_.control_data_unchanged -or
            -not $_.source_scope_preserved -or
            -not $_.batched_source_read -or
            -not $_.single_verification_call -or
            -not $_.bounded_tool_loop -or
            $_.forbidden_command_scope
        }).Count -ne 0
    }).Count -eq 0
    no_mcp_calls = @($results | Where-Object {
        [int]$_.optimized.totals.mcp_call_count -ne 0
    }).Count -eq 0
    total_input_reduction_at_least_25_percent =
        $comparison.input_token_reduction_percent -ge 25
    command_reduction_at_least_20_percent =
        $comparison.command_reduction_percent -ge 20
    optimized_input_repeat_drift_at_most_5_percent =
        $comparison.optimized_input_repeat_drift_percent -le 5
}
$allPass = @($thresholds.Values | Where-Object { -not $_ }).Count -eq 0
$evaluationId = "p6-5-evaluation-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$evaluationRoot = Join-Path $OutputDir $evaluationId
New-Item -ItemType Directory -Path $evaluationRoot -Force | Out-Null
$evaluation = [ordered]@{
    schema_version = "AOS-P6-5-AGENT-EFFICIENCY-EVALUATION-1"
    evaluation_id = $evaluationId
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    result_paths = @($ResultPath | ForEach-Object {
        [System.IO.Path]::GetFullPath($_)
    })
    repeat_count = $results.Count
    baseline = $baseline
    optimized_average = $average
    comparison = $comparison
    diagnostic = [ordered]@{
        uncached_tokens_are_provider_cache_state_dependent = $true
        uncached_regression_is_reported_but_not_a_provider_neutral_gate = $true
    }
    thresholds = $thresholds
    status = if ($allPass) { "PASS" } else { "FAIL" }
    marker = if ($allPass) {
        "AOS_P6_5_AGENT_EFFICIENCY_OK"
    } else {
        "AOS_P6_5_AGENT_EFFICIENCY_NOT_MET"
    }
}
$evaluationPath = Join-Path $evaluationRoot "p6-5-agent-efficiency-evaluation.json"
[System.IO.File]::WriteAllText(
    $evaluationPath,
    ($evaluation | ConvertTo-Json -Depth 12),
    $utf8NoBom
)

Write-Output "P6.5 efficiency evaluation: $evaluationId"
Write-Output "Repeats: $($results.Count)"
Write-Output "Average input tokens: $($baseline.input_tokens) -> $($average.input_tokens)"
Write-Output "Average commands: $($baseline.command_count) -> $($average.command_count)"
Write-Output "Input reduction: $($comparison.input_token_reduction_percent)%"
Write-Output "Repeat drift: $($comparison.optimized_input_repeat_drift_percent)%"
Write-Output "Result: $evaluationPath"
Write-Output $evaluation.marker
if (-not $allPass) {
    exit 1
}
