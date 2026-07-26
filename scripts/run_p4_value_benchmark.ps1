[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$OutputDir,
    [string]$AosBinary,
    [switch]$AllowDirty,
    [switch]$RequireAgentRuns
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $scriptRoot "..\benchmarks\p4\scenarios.json"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p4-value-benchmark"
}
if ([string]::IsNullOrWhiteSpace($AosBinary)) {
    $AosBinary = Join-Path $scriptRoot "..\target\debug\aos.exe"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_P4_VALUE_BENCHMARK_FAILED: $Message"
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-Aos([string[]]$Arguments) {
    $output = & $AosBinary @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        Output = ($output -join [Environment]::NewLine)
        ExitCode = $exitCode
    }
}

function Get-RepositorySnapshot([string]$RepositoryPath, [string]$ExpectedCommit) {
    if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
        Fail "repository path does not exist: $RepositoryPath"
    }

    $commit = (& git -C $RepositoryPath rev-parse HEAD 2>&1).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) {
        Fail "repository does not expose a Git commit: $RepositoryPath"
    }

    $status = (& git -C $RepositoryPath status --porcelain 2>&1) -join [Environment]::NewLine
    if (-not $AllowDirty -and -not [string]::IsNullOrWhiteSpace($status)) {
        Fail "repository is dirty: $RepositoryPath"
    }

    if ($ExpectedCommit -ne "HEAD" -and $commit -ne $ExpectedCommit) {
        Fail "repository commit mismatch for $RepositoryPath; expected $ExpectedCommit, found $commit"
    }

    [pscustomobject]@{
        Path = $RepositoryPath
        Commit = $commit
        Clean = [string]::IsNullOrWhiteSpace($status)
    }
}

function Get-FileBytes([string]$RepositoryPath, [object[]]$RelativePaths) {
    $total = 0
    foreach ($relativePath in $RelativePaths) {
        $path = Join-Path $RepositoryPath ([string]$relativePath)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Fail "baseline file does not exist: $path"
        }
        $total += (Get-Item -LiteralPath $path).Length
    }
    return [int64]$total
}

function Write-RecordFixture([string]$Root, [object]$Record) {
    $kind = [string]$Record.kind
    $directory = if ($kind -eq "Knowledge") { "knowledge" } elseif ($kind -eq "State") { "state" } else { Fail "unsupported fixture kind: $kind" }
    New-Item -ItemType Directory -Path (Join-Path $Root ".aos\$directory") -Force | Out-Null
    $path = Join-Path $Root (".aos\$directory\$($Record.id).r1.json")
    $document = [ordered]@{
        kind = $kind
        id = [string]$Record.id
        project_id = "project-benchmark"
        contract_version = "AOS-SPEC-001"
        revision = "1"
        previous_revision = $null
        owner = "benchmark-owner"
        producer = "benchmark-fixture"
        created_at_unix = "1700000000"
        last_produced_at_unix = "1700000000"
        authority = "authoritative"
        lifecycle = "active"
        subject = [string]$Record.subject
        source_reference = [string]$Record.source_reference
        derived = "false"
        authority_basis = "benchmark-fixture"
        authority_reference = "benchmark"
    }
    if ($kind -eq "Knowledge") {
        $document.content = [string]$Record.content
    } else {
        $document.observed_value = [string]$Record.value
        $document.observation_instant_unix = "1700000000"
        $document.observer = "benchmark-fixture"
        $document.freshness = [string]$Record.freshness
        $document.freshness_policy = "benchmark"
    }
    Write-Utf8NoBom -Path $path -Content ($document | ConvertTo-Json -Compress)
}

function New-ContextFixture([object]$Scenario, [string]$WorkRoot) {
    New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    $init = Invoke-Aos @("init", $WorkRoot, "--apply", "--authority", "p4-benchmark", "--format", "json")
    if ($init.ExitCode -ne 0) {
        Fail "cannot initialize context fixture for $($Scenario.id): $($init.Output)"
    }
    foreach ($record in $Scenario.records) {
        Write-RecordFixture -Root $WorkRoot -Record $record
    }
}

function Invoke-Context([object]$Scenario, [string]$WorkRoot, [string]$Profile, [int]$BudgetBytes) {
    $result = Invoke-Aos @("context", $WorkRoot, "--limit", ([string]$Scenario.context_limit), "--profile", $Profile, "--budget-bytes", ([string]$BudgetBytes), "--format", "json")
    if ($result.ExitCode -ne 0) {
        Fail "context command failed for $($Scenario.id): $($result.Output)"
    }
    try {
        $envelope = $result.Output | ConvertFrom-Json
    } catch {
        Fail "context output is not valid JSON for $($Scenario.id)"
    }
    if ($envelope.outcome -ne "success") {
        Fail "context outcome is not success for $($Scenario.id)"
    }
    if ($null -eq $envelope.data.selected -or $null -eq $envelope.data.withheld) {
        Fail "context envelope is missing selected/withheld data for $($Scenario.id)"
    }
    if ($envelope.data.profile -ne $Profile -or [int]$envelope.data.budget_bytes -ne $BudgetBytes) {
        Fail "context profile/budget mismatch for $($Scenario.id)"
    }
    $selectedJson = ConvertTo-Json -InputObject (,@($envelope.data.selected)) -Compress
    $withheldJson = ConvertTo-Json -InputObject (,@($envelope.data.withheld)) -Compress
    $withheldWithReason = @($envelope.data.withheld | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.reason) }).Count
    [pscustomobject]@{
        SelectedCount = @($envelope.data.selected).Count
        WithheldCount = @($envelope.data.withheld).Count
        WithheldWithReason = $withheldWithReason
        SelectedBytes = [Text.Encoding]::UTF8.GetByteCount($selectedJson)
        WithheldBytes = [Text.Encoding]::UTF8.GetByteCount($withheldJson)
        Profile = [string]$envelope.data.profile
        BudgetBytes = [int]$envelope.data.budget_bytes
        Policy = [string]$envelope.data.policy
        Raw = $result.Output
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Fail "manifest does not exist: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $AosBinary -PathType Leaf)) {
    Fail "AOS binary does not exist: $AosBinary; run cargo build --locked first"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne "AOS-P4-BENCHMARK-1") {
    Fail "unsupported benchmark manifest version"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "p4-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$runRoot = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$scenarioResults = @()
$allStructuralPass = $true
$allAgentResultsPresent = $true
$allAgentThresholdsPass = $true

foreach ($scenario in $manifest.scenarios) {
    $repositoryPath = [Environment]::GetEnvironmentVariable([string]$scenario.repository_env)
    if ([string]::IsNullOrWhiteSpace($repositoryPath)) {
        Fail "environment variable is not set: $($scenario.repository_env)"
    }
    $snapshot = Get-RepositorySnapshot -RepositoryPath $repositoryPath -ExpectedCommit ([string]$scenario.expected_commit)
    $baselineBytes = Get-FileBytes -RepositoryPath $repositoryPath -RelativePaths $scenario.baseline_files
    $workRoot = Join-Path $runRoot $scenario.id
    New-ContextFixture -Scenario $scenario -WorkRoot $workRoot
    $profile = if ($scenario.context_profile) { [string]$scenario.context_profile } else { [string]$manifest.default_context_profile }
    $budgetBytes = if ($scenario.context_budget_bytes) { [int]$scenario.context_budget_bytes } else { [int]$manifest.default_context_budget_bytes }
    $context = Invoke-Context -Scenario $scenario -WorkRoot $workRoot -Profile $profile -BudgetBytes $budgetBytes
    if ($context.WithheldCount -ne $context.WithheldWithReason) {
        $allStructuralPass = $false
    }
    if ($context.SelectedBytes -gt $context.BudgetBytes) {
        $allStructuralPass = $false
    }
    $baselineTokens = [Math]::Ceiling($baselineBytes / 4)
    $aosTokens = [Math]::Ceiling($context.SelectedBytes / 4)
    $reduction = if ($baselineTokens -gt 0) { [Math]::Round((1 - ($aosTokens / $baselineTokens)) * 100, 2) } else { 0 }
    $agentResultPath = Join-Path $runRoot "$($scenario.id).agent.json"
    $agentStatus = "PENDING_AGENT_RUN"
    $agentMetrics = $null
    if (Test-Path -LiteralPath $agentResultPath -PathType Leaf) {
        $agentMetrics = Get-Content -LiteralPath $agentResultPath -Raw | ConvertFrom-Json
        $agentStatus = [string]$agentMetrics.status
        if ($agentStatus -ne "PASS") {
            $allAgentThresholdsPass = $false
        }
    } else {
        $allAgentResultsPresent = $false
        if ($RequireAgentRuns) {
            Fail "agent result is required but missing: $agentResultPath"
        }
    }
    $scenarioResults += [pscustomobject]@{
        id = [string]$scenario.id
        task_type = [string]$scenario.task_type
        repository = $snapshot.Path
        repository_commit = $snapshot.Commit
        repository_clean = $snapshot.Clean
        baseline_files = @($scenario.baseline_files)
        baseline_bytes = $baselineBytes
        selected_context_bytes = $context.SelectedBytes
        context_profile = $context.Profile
        context_budget_bytes = $context.BudgetBytes
        estimated_baseline_tokens = $baselineTokens
        estimated_context_tokens = $aosTokens
        estimated_context_reduction_percent = $reduction
        selected_count = $context.SelectedCount
        withheld_count = $context.WithheldCount
        withheld_with_reason = $context.WithheldWithReason
        policy = $context.Policy
        agent_status = $agentStatus
        agent_metrics = $agentMetrics
    }
}

$result = [ordered]@{
    schema_version = "AOS-P4-BENCHMARK-1"
    run_id = $runId
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    manifest = (Resolve-Path -LiteralPath $ManifestPath).Path
    structural_status = if ($allStructuralPass) { "PASS" } else { "FAIL" }
    agent_status = if ($allAgentResultsPresent -and $allAgentThresholdsPass) { "PASS" } else { "PENDING" }
    pass_marker = if ($allStructuralPass -and $allAgentResultsPresent -and $allAgentThresholdsPass) { "AOS_P4_VALUE_BENCHMARK_OK" } else { "AOS_P4_VALUE_BENCHMARK_STRUCTURAL_OK" }
    token_estimates = "Provider-neutral estimate uses UTF-8 bytes divided by four; provider tokenizer runs require agent result files."
    scenarios = $scenarioResults
}
$resultPath = Join-Path $runRoot "benchmark-results.json"
Write-Utf8NoBom -Path $resultPath -Content ($result | ConvertTo-Json -Depth 8)

Write-Output "P4 benchmark run: $runId"
Write-Output "Structural status: $($result.structural_status)"
Write-Output "Agent status: $($result.agent_status)"
Write-Output "Result: $resultPath"
Write-Output $result.pass_marker
