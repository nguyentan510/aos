[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PilotResultPath,
    [Parameter(Mandatory = $true)]
    [string]$BaselineResultPath,
    [string]$OutputDir = "",
    [string]$Model = "gpt-5.6-sol",
    [string]$CodexPackage = "@openai/codex@0.145.0"
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if (-not $OutputDir) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-5-agent-efficiency"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

function Fail([string]$Message) {
    throw "AOS_P6_5_AGENT_EFFICIENCY_FAILED: $Message"
}

function Write-Utf8([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-Native(
    [string]$File,
    [string[]]$Arguments,
    [string]$WorkingDirectory,
    [string]$InputText = ""
) {
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) (
        "aos-p6-5-native-" + [guid]::NewGuid().ToString("N") + ".stderr"
    )
    $original = Get-Location
    $originalErrorAction = $ErrorActionPreference
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $ErrorActionPreference = "Continue"
        if ($InputText) {
            $lines = $InputText | & $File @Arguments 2> $stderrPath
        } else {
            $lines = & $File @Arguments 2> $stderrPath
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $originalErrorAction
        Set-Location -LiteralPath $original
        $stopwatch.Stop()
    }
    $stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
        Get-Content -LiteralPath $stderrPath -Raw
    } else {
        ""
    }
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = ($lines -join [Environment]::NewLine)
        Stderr = $stderr
        ElapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    }
}

function Get-ControlFingerprint([string]$Root) {
    $control = Join-Path $Root ".aos"
    $entries = @(
        Get-ChildItem -LiteralPath $control -Recurse -File |
            ForEach-Object {
                [ordered]@{
                    path = $_.FullName.Substring($control.Length).TrimStart('\', '/').Replace('\', '/')
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            } |
            Sort-Object path
    )
    $entries | ConvertTo-Json -Depth 4 -Compress
}

function Initialize-Workspace(
    [string]$Source,
    [string]$Target,
    [string]$Scenario
) {
    Copy-Item -LiteralPath $Source -Destination $Target -Recurse
    Write-Utf8 -Path (Join-Path $Target ".gitignore") -Content "/target/`n"
    $libraryPath = Join-Path $Target "src/lib.rs"
    if ($Scenario -eq "bugfix") {
        Write-Utf8 -Path $libraryPath -Content @'
pub fn project_name() -> &'static str { "wrong-name" }

#[cfg(test)]
mod tests {
    #[test]
    fn project_name_matches_the_manifest() {
        assert_eq!(super::project_name(), "p6-4-rust-adoption");
    }
}
'@
    }
    if ($Scenario -eq "feature") {
        Write-Utf8 -Path $libraryPath -Content @'
pub fn project_name() -> &'static str { "p6-4-rust-adoption" }

#[cfg(test)]
mod tests {
    #[test]
    fn project_slug_is_stable() {
        assert_eq!(super::project_slug(), "p6_4_rust_adoption");
    }
}
'@
    }
    $git = Invoke-Native -File "git" -Arguments @("init", "--quiet") -WorkingDirectory $Target
    if ($git.ExitCode -ne 0) {
        Fail "could not initialize disposable Agent workspace"
    }
    Invoke-Native -File "git" -Arguments @(
        "config", "user.name", "AOS P6.5 Benchmark"
    ) -WorkingDirectory $Target | Out-Null
    Invoke-Native -File "git" -Arguments @(
        "config", "user.email", "p6-5@aos.local"
    ) -WorkingDirectory $Target | Out-Null
    $lock = Invoke-Native -File "cargo" -Arguments @(
        "generate-lockfile"
    ) -WorkingDirectory $Target
    if ($lock.ExitCode -ne 0) {
        Fail "could not generate the disposable Cargo lockfile"
    }
    Invoke-Native -File "git" -Arguments @("add", ".") -WorkingDirectory $Target | Out-Null
    $commit = Invoke-Native -File "git" -Arguments @(
        "commit", "--quiet", "-m", "fixture baseline"
    ) -WorkingDirectory $Target
    if ($commit.ExitCode -ne 0) {
        Fail "could not commit disposable Agent fixture: $($commit.Stderr)"
    }
}

function Read-AgentEvents([string]$Path) {
    $events = @()
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            try {
                $events += $line | ConvertFrom-Json
            } catch {
                Fail "invalid Codex JSONL in $Path"
            }
        }
    }
    $events
}

function Get-EventMetrics([object[]]$Events) {
    $completed = @(
        $Events | Where-Object { $_.type -eq "turn.completed" }
    ) | Select-Object -Last 1
    $commands = @(
        $Events | Where-Object {
            $_.type -eq "item.completed" -and
            $_.item.type -eq "command_execution"
        }
    )
    $mcpCalls = @(
        $Events | Where-Object {
            $_.type -eq "item.completed" -and
            $_.item.type -eq "mcp_tool_call"
        }
    )
    $fileChanges = @(
        $Events | Where-Object {
            $_.type -eq "item.completed" -and
            $_.item.type -eq "file_change"
        }
    )
    $inputTokens = if ($completed) {
        [int64]$completed.usage.input_tokens
    } else {
        0
    }
    $cachedTokens = if ($completed) {
        [int64]$completed.usage.cached_input_tokens
    } else {
        0
    }
    [pscustomobject]@{
        Completed = $completed
        InputTokens = $inputTokens
        CachedInputTokens = $cachedTokens
        UncachedInputTokens = $inputTokens - $cachedTokens
        OutputTokens = if ($completed) {
            [int64]$completed.usage.output_tokens
        } else {
            0
        }
        CommandCount = $commands.Count
        McpCallCount = $mcpCalls.Count
        FileChangeCount = $fileChanges.Count
        Commands = @($commands | ForEach-Object { [string]$_.item.command })
    }
}

function Get-PercentReduction([double]$Baseline, [double]$Candidate) {
    if ($Baseline -le 0) {
        return 0
    }
    [Math]::Round((($Baseline - $Candidate) / $Baseline) * 100, 3)
}

if (-not (Test-Path -LiteralPath $PilotResultPath -PathType Leaf)) {
    Fail "controlled-adoption result does not exist: $PilotResultPath"
}
if (-not (Test-Path -LiteralPath $BaselineResultPath -PathType Leaf)) {
    Fail "P6.4 baseline result does not exist: $BaselineResultPath"
}

$pilot = Get-Content -LiteralPath $PilotResultPath -Raw | ConvertFrom-Json
if ($pilot.status -ne "PASS" -or $pilot.marker -ne "AOS_P6_4_CONTROLLED_ADOPTION_PILOT_OK") {
    Fail "controlled-adoption pilot has not passed"
}
$rustScenario = @($pilot.scenarios | Where-Object { $_.type -eq "rust" })
if ($rustScenario.Count -ne 1) {
    Fail "controlled-adoption result must contain exactly one Rust scenario"
}
$sourceRoot = [string]$rustScenario[0].root
$briefPath = [string]$rustScenario[0].agent_brief
if (-not (Test-Path -LiteralPath $briefPath -PathType Leaf)) {
    Fail "provider-neutral Agent brief is missing"
}
$brief = Get-Content -LiteralPath $briefPath -Raw | ConvertFrom-Json
if ($brief.provider -ne "provider-neutral" -or $brief.secret_scan -ne "pass") {
    Fail "Agent brief did not preserve the provider-neutral safety contract"
}

$baseline = Get-Content -LiteralPath $BaselineResultPath -Raw | ConvertFrom-Json
if ($baseline.status -ne "PASS" -or
    $baseline.marker -ne "AOS_P6_4_AGENT_WORKFLOW_QUALIFICATION_OK" -or
    [int]$baseline.task_success_count -ne 3) {
    Fail "P6.4 Agent baseline has not passed all three tasks"
}

$baselineRuns = @()
foreach ($run in $baseline.runs) {
    $eventPath = [string]$run.event_path
    if (-not (Test-Path -LiteralPath $eventPath -PathType Leaf)) {
        Fail "baseline event evidence is missing: $eventPath"
    }
    $eventMetrics = Get-EventMetrics (Read-AgentEvents $eventPath)
    $baselineRuns += [ordered]@{
        scenario = [string]$run.scenario
        task_success = [bool]$run.task_success
        input_tokens = $eventMetrics.InputTokens
        cached_input_tokens = $eventMetrics.CachedInputTokens
        uncached_input_tokens = $eventMetrics.UncachedInputTokens
        output_tokens = $eventMetrics.OutputTokens
        command_count = $eventMetrics.CommandCount
        mcp_call_count = $eventMetrics.McpCallCount
        elapsed_seconds = [double]$run.elapsed_seconds
    }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "p6-5-efficiency-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$runRoot = Join-Path $OutputDir $runId
$workspaceRoot = Join-Path $runRoot "workspaces"
New-Item -ItemType Directory -Path $workspaceRoot -Force | Out-Null

$schemaPath = Join-Path $runRoot "agent-output-schema.json"
$schema = [ordered]@{
    type = "object"
    properties = [ordered]@{
        answer = [ordered]@{ type = "string" }
        source_files = [ordered]@{
            type = "array"
            items = [ordered]@{ type = "string" }
        }
        changed_files = [ordered]@{
            type = "array"
            items = [ordered]@{ type = "string" }
        }
        verification_passed = [ordered]@{ type = "boolean" }
        verification_output = [ordered]@{ type = "string" }
        task_result = [ordered]@{
            type = "string"
            enum = @("PASS", "FAIL", "BLOCKED")
        }
    }
    required = @(
        "answer",
        "source_files",
        "changed_files",
        "verification_passed",
        "verification_output",
        "task_result"
    )
    additionalProperties = $false
}
Write-Utf8 -Path $schemaPath -Content ($schema | ConvertTo-Json -Depth 8)

$scenarioDefinitions = @(
    [ordered]@{
        id = "onboarding"
        task = "Explain which file defines the package identity and which function exposes it. Do not modify source."
        expected_changed = @()
        expected_terms = @("Cargo.toml", "src/lib.rs", "project_name")
    },
    [ordered]@{
        id = "bugfix"
        task = "Fix the failing project_name regression with the smallest source change. Do not weaken or remove the test."
        expected_changed = @("src/lib.rs")
        expected_terms = @("src/lib.rs", "cargo test")
    },
    [ordered]@{
        id = "feature"
        task = "Implement project_slug so the existing test passes. Derive the stable slug from the package identity semantics already present in the fixture."
        expected_changed = @("src/lib.rs")
        expected_terms = @("src/lib.rs", "cargo test")
    }
)

$contextCapsule = [ordered]@{
    schema_version = "AOS-P6-5-AGENT-CAPSULE-1"
    authoritative_context = $brief.context
    source_expansion = [ordered]@{
        allowed = $true
        allowed_files = @("Cargo.toml", "src/lib.rs")
        max_files = 2
        batch_initial_read = $true
    }
    mutation = [ordered]@{
        allowed_files = @("src/lib.rs")
        control_root_immutable = ".aos/"
    }
    verification = [ordered]@{
        command = "cargo test"
        max_runs = 1
        combine_final_checks = $true
    }
    provider = "provider-neutral"
}
$contextCapsuleJson = $contextCapsule | ConvertTo-Json -Depth 12 -Compress

$npx = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    "npx.cmd"
} else {
    "npx"
}
$optimizedRuns = @()
foreach ($definition in $scenarioDefinitions) {
    $workspace = Join-Path $workspaceRoot $definition.id
    Initialize-Workspace -Source $sourceRoot -Target $workspace -Scenario $definition.id
    $controlBefore = Get-ControlFingerprint $workspace
    $prompt = @"
You are executing one bounded coding task using a provider-neutral AOS Agent
capsule. The capsule is authoritative for scope and provenance, but source
files remain the implementation truth.

TASK:
$($definition.task)

AOS_AGENT_CAPSULE_JSON:
$contextCapsuleJson

Efficiency policy:
1. Do not call MCP, browse the network, scan directories, or inspect files
   outside Cargo.toml and src/lib.rs.
2. Read both allowed source files together in one initial tool call.
3. Do not run a preflight git status or test before the change.
4. If mutation is required, make one minimal patch to src/lib.rs.
5. Run exactly one final verification tool call. It must run cargo test and may
   combine git diff --check, the scoped diff, and git status in that same call.
6. Do not modify .aos, Cargo.toml, tests, Cargo.lock, or .gitignore.
7. Return the required JSON immediately after verification. Report only source
   files actually used and files actually changed.

Set task_result to PASS only when the task is complete and cargo test passes.
"@
    $promptPath = Join-Path $runRoot "$($definition.id).prompt.txt"
    Write-Utf8 -Path $promptPath -Content $prompt
    $startedAt = [DateTime]::UtcNow
    $agent = Invoke-Native -File $npx -Arguments @(
        "-y", $CodexPackage,
        "exec",
        "-c", "mcp_servers={}",
        "--ephemeral",
        "--json",
        "--model", $Model,
        "--sandbox", "workspace-write",
        "--cd", $workspace,
        "--output-schema", $schemaPath,
        "-"
    ) -WorkingDirectory $workspace -InputText $prompt
    $eventPath = Join-Path $runRoot "$($definition.id).events.jsonl"
    Write-Utf8 -Path $eventPath -Content $agent.Stdout
    $events = Read-AgentEvents $eventPath
    $metrics = Get-EventMetrics $events
    $failed = @(
        $events | Where-Object { $_.type -eq "turn.failed" }
    ) | Select-Object -Last 1
    $message = @(
        $events |
            Where-Object {
                $_.type -eq "item.completed" -and
                $_.item.type -eq "agent_message"
            } |
            ForEach-Object { [string]$_.item.text }
    ) | Select-Object -Last 1
    $structured = $null
    try {
        $structured = ([string]$message) | ConvertFrom-Json
    } catch {
        $structured = $null
    }

    $status = Invoke-Native -File "git" -Arguments @(
        "status", "--porcelain"
    ) -WorkingDirectory $workspace
    $changed = @(
        $status.Stdout -split "`r?`n" |
            Where-Object { $_.Length -ge 4 } |
            ForEach-Object { $_.Substring(3).Trim().Trim('"') } |
            Where-Object { $_ }
    )
    $verification = Invoke-Native -File "cargo" -Arguments @(
        "test"
    ) -WorkingDirectory $workspace
    $controlAfter = Get-ControlFingerprint $workspace
    $expectedChanged = @($definition.expected_changed)
    $changesMatch = $changed.Count -eq $expectedChanged.Count -and @(
        $expectedChanged | Where-Object { $changed -notcontains $_ }
    ).Count -eq 0
    $reportedChanged = if ($structured) {
        @($structured.changed_files)
    } else {
        @()
    }
    $reportedChangesMatch = $reportedChanged.Count -eq $expectedChanged.Count -and @(
        $expectedChanged | Where-Object { $reportedChanged -notcontains $_ }
    ).Count -eq 0
    $sourceScopePreserved = $null -ne $structured -and @(
        @($structured.source_files) |
            Where-Object { @("Cargo.toml", "src/lib.rs") -notcontains $_ }
    ).Count -eq 0
    $termsMatch = $null -ne $structured -and @(
        $definition.expected_terms |
            Where-Object {
                ([string]$message).IndexOf(
                    [string]$_,
                    [StringComparison]::OrdinalIgnoreCase
                ) -lt 0
            }
    ).Count -eq 0
    $batchedSourceRead = @($metrics.Commands | Where-Object {
        $_ -match "Cargo\.toml" -and
        $_ -match "src[\\/]+lib\.rs"
    }).Count -eq 1
    $singleVerificationCall = @($metrics.Commands | Where-Object {
        $_ -match "(?i)cargo\s+test"
    }).Count -eq 1
    $boundedToolLoop = $metrics.CommandCount -le 2
    $forbiddenCommandScope = @($metrics.Commands | Where-Object {
        $_ -match "(?i)(Get-ChildItem|Select-String|\brg\b|\bgrep\b|git\s+(show|log|ls-files))" -or
        $_ -match "(?i)(README|notes[\\/]|\.aos[\\/])"
    }).Count -ne 0
    $firstPatchSeconds = $null
    if ($changed -contains "src/lib.rs") {
        $writeTime = (Get-Item -LiteralPath (
            Join-Path $workspace "src/lib.rs"
        )).LastWriteTimeUtc
        if ($writeTime -ge $startedAt) {
            $firstPatchSeconds = [Math]::Round(
                ($writeTime - $startedAt).TotalSeconds,
                3
            )
        }
    }
    $taskPass = $agent.ExitCode -eq 0 -and
        $null -ne $metrics.Completed -and
        $null -eq $failed -and
        $null -ne $structured -and
        $structured.task_result -eq "PASS" -and
        [bool]$structured.verification_passed -and
        $verification.ExitCode -eq 0 -and
        $changesMatch -and
        $reportedChangesMatch -and
        $sourceScopePreserved -and
        $termsMatch -and
        $batchedSourceRead -and
        $singleVerificationCall -and
        $boundedToolLoop -and
        -not $forbiddenCommandScope -and
        $controlBefore -eq $controlAfter -and
        $metrics.McpCallCount -eq 0
    $optimizedRuns += [ordered]@{
        scenario = $definition.id
        status = if ($taskPass) { "PASS" } else { "FAIL" }
        agent_exit_code = $agent.ExitCode
        task_success = $taskPass
        input_tokens = $metrics.InputTokens
        cached_input_tokens = $metrics.CachedInputTokens
        uncached_input_tokens = $metrics.UncachedInputTokens
        output_tokens = $metrics.OutputTokens
        command_count = $metrics.CommandCount
        mcp_call_count = $metrics.McpCallCount
        file_change_count = $metrics.FileChangeCount
        elapsed_seconds = $agent.ElapsedSeconds
        time_to_first_patch_seconds = $firstPatchSeconds
        expected_changed_files = $expectedChanged
        changed_files = $changed
        reported_changed_files = $reportedChanged
        source_scope_preserved = $sourceScopePreserved
        batched_source_read = $batchedSourceRead
        single_verification_call = $singleVerificationCall
        bounded_tool_loop = $boundedToolLoop
        forbidden_command_scope = $forbiddenCommandScope
        verification_passed = $verification.ExitCode -eq 0
        control_data_unchanged = $controlBefore -eq $controlAfter
        prompt_path = $promptPath
        event_path = $eventPath
        commands = $metrics.Commands
        stderr_summary = if ($agent.ExitCode -eq 0) {
            ""
        } else {
            $agent.Stderr.Trim()
        }
    }
}

function Get-Totals([object[]]$Runs) {
    $totals = [ordered]@{
        scenario_count = $Runs.Count
        task_success_count = @($Runs | Where-Object { $_.task_success }).Count
        input_tokens = [int64]0
        cached_input_tokens = [int64]0
        uncached_input_tokens = [int64]0
        output_tokens = [int64]0
        command_count = 0
        mcp_call_count = 0
        elapsed_seconds = [double]0
    }
    foreach ($run in $Runs) {
        $totals.input_tokens += [int64]$run["input_tokens"]
        $totals.cached_input_tokens += [int64]$run["cached_input_tokens"]
        $totals.uncached_input_tokens += [int64]$run["uncached_input_tokens"]
        $totals.output_tokens += [int64]$run["output_tokens"]
        $totals.command_count += [int]$run["command_count"]
        $totals.mcp_call_count += [int]$run["mcp_call_count"]
        $totals.elapsed_seconds += [double]$run["elapsed_seconds"]
    }
    $totals.elapsed_seconds = [Math]::Round($totals.elapsed_seconds, 3)
    $totals
}

$baselineTotals = Get-Totals $baselineRuns
$optimizedTotals = Get-Totals $optimizedRuns
$comparison = [ordered]@{
    input_token_reduction_percent = Get-PercentReduction `
        $baselineTotals.input_tokens $optimizedTotals.input_tokens
    uncached_input_token_reduction_percent = Get-PercentReduction `
        $baselineTotals.uncached_input_tokens $optimizedTotals.uncached_input_tokens
    output_token_reduction_percent = Get-PercentReduction `
        $baselineTotals.output_tokens $optimizedTotals.output_tokens
    command_reduction_percent = Get-PercentReduction `
        $baselineTotals.command_count $optimizedTotals.command_count
    elapsed_reduction_percent = Get-PercentReduction `
        $baselineTotals.elapsed_seconds $optimizedTotals.elapsed_seconds
}
$thresholds = [ordered]@{
    task_success_preserved = $optimizedTotals.task_success_count -eq 3
    verification_passed = @(
        $optimizedRuns | Where-Object { -not $_.verification_passed }
    ).Count -eq 0
    control_data_unchanged = @(
        $optimizedRuns | Where-Object { -not $_.control_data_unchanged }
    ).Count -eq 0
    source_scope_preserved = @(
        $optimizedRuns | Where-Object { -not $_.source_scope_preserved }
    ).Count -eq 0
    bounded_orchestration_preserved = @(
        $optimizedRuns | Where-Object {
            -not $_.batched_source_read -or
            -not $_.single_verification_call -or
            -not $_.bounded_tool_loop -or
            $_.forbidden_command_scope
        }
    ).Count -eq 0
    no_mcp_calls = $optimizedTotals.mcp_call_count -eq 0
    total_input_reduction_at_least_25_percent =
        $comparison.input_token_reduction_percent -ge 25
    command_reduction_at_least_20_percent =
        $comparison.command_reduction_percent -ge 20
}
$allPass = @($thresholds.Values | Where-Object { -not $_ }).Count -eq 0
$result = [ordered]@{
    schema_version = "AOS-P6-5-AGENT-EFFICIENCY-1"
    run_id = $runId
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    model = $Model
    provider = "codex-chatgpt"
    codex_package = $CodexPackage
    controlled_adoption_result = [System.IO.Path]::GetFullPath($PilotResultPath)
    baseline_result = [System.IO.Path]::GetFullPath($BaselineResultPath)
    optimization = [ordered]@{
        provider_neutral_capsule = $true
        bounded_source_expansion = $true
        batched_initial_read = $true
        combined_final_verification = $true
        user_mcp_configuration_disabled = $true
        ephemeral_agent_session = $true
        core_contract_changed = $false
    }
    baseline = [ordered]@{
        totals = $baselineTotals
        runs = $baselineRuns
    }
    optimized = [ordered]@{
        totals = $optimizedTotals
        runs = $optimizedRuns
    }
    comparison = $comparison
    thresholds = $thresholds
    status = if ($allPass) { "PASS" } else { "FAIL" }
    marker = if ($allPass) {
        "AOS_P6_5_AGENT_EFFICIENCY_OK"
    } else {
        "AOS_P6_5_AGENT_EFFICIENCY_NOT_MET"
    }
}
$resultPath = Join-Path $runRoot "p6-5-agent-efficiency.json"
Write-Utf8 -Path $resultPath -Content ($result | ConvertTo-Json -Depth 14)

Write-Output "P6.5 Agent efficiency: $runId"
Write-Output "Tasks: $($optimizedTotals.task_success_count)/$($optimizedTotals.scenario_count)"
Write-Output "Uncached tokens: $($baselineTotals.uncached_input_tokens) -> $($optimizedTotals.uncached_input_tokens)"
Write-Output "Commands: $($baselineTotals.command_count) -> $($optimizedTotals.command_count)"
Write-Output "Uncached reduction: $($comparison.uncached_input_token_reduction_percent)%"
Write-Output "Result: $resultPath"
Write-Output $result.marker
if (-not $allPass) {
    exit 1
}
