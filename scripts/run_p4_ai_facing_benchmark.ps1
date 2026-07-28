[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$OutputDir,
    [string]$AosBinary,
    [string]$Model = "gpt-5.6-sol",
    [string]$CodexPackage = "@openai/codex@0.145.0",
    [string]$ScenarioId,
    [ValidateSet("p4", "p6.5")]
    [string]$AgentPolicy = "p4",
    [ValidateRange(1, 3)]
    [int]$Repeats = 2,
    [double]$MinimumTokenReductionPercent = 25,
    [double]$MinimumTimeReductionPercent = 20,
    [double]$MinimumCommandReductionPercent = 20,
    [double]$MaximumSuccessRegressionPercent = 5
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $scriptRoot "..\benchmarks\p4\scenarios.json"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p4-ai-facing-benchmark"
}
if ([string]::IsNullOrWhiteSpace($AosBinary)) {
    $AosBinary = Join-Path $scriptRoot "..\target\debug\aos.exe"
}
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$AosBinary = [System.IO.Path]::GetFullPath($AosBinary)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_P4_AI_FACING_BENCHMARK_FAILED: $Message"
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-Native([string]$File, [string[]]$Arguments, [string]$WorkingDirectory) {
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("aos-native-" + [guid]::NewGuid().ToString() + ".stderr")
    $originalLocation = Get-Location
    $originalErrorAction = $ErrorActionPreference
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $ErrorActionPreference = "Continue"
        $stdoutLines = & $File @Arguments 2> $stderrPath
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $originalErrorAction
        Set-Location -LiteralPath $originalLocation
        $stopwatch.Stop()
    }
    $stderr = if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath -Raw
    } else {
        ""
    }
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = ($stdoutLines -join [Environment]::NewLine)
        Stderr = $stderr
        ElapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    }
}

function Invoke-NativeWithInput(
    [string]$File,
    [string[]]$Arguments,
    [string]$WorkingDirectory,
    [string]$InputText
) {
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("aos-native-" + [guid]::NewGuid().ToString() + ".stderr")
    $originalLocation = Get-Location
    $originalErrorAction = $ErrorActionPreference
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $ErrorActionPreference = "Continue"
        $stdoutLines = $InputText | & $File @Arguments 2> $stderrPath
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $originalErrorAction
        Set-Location -LiteralPath $originalLocation
        $stopwatch.Stop()
    }
    $stderr = if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath -Raw
    } else {
        ""
    }
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = ($stdoutLines -join [Environment]::NewLine)
        Stderr = $stderr
        ElapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    }
}

function Copy-CleanSnapshot([string]$Source, [string]$Target, [string]$Commit) {
    $parent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $clone = Invoke-Native -File "git" -Arguments @(
        "clone", "--quiet", "--local", "--no-hardlinks", $Source, $Target
    ) -WorkingDirectory $parent
    if ($clone.ExitCode -ne 0) {
        Fail "cannot clone benchmark snapshot: $($clone.Stderr)"
    }
    $checkoutCommit = if ($Commit -eq "HEAD") {
        (& git -C $Source rev-parse HEAD).Trim()
    } else {
        $Commit
    }
    $checkout = Invoke-Native -File "git" -Arguments @(
        "-C", $Target, "checkout", "--quiet", "--detach", $checkoutCommit
    ) -WorkingDirectory $parent
    if ($checkout.ExitCode -ne 0) {
        Fail "cannot checkout benchmark snapshot $checkoutCommit"
    }
    return $checkoutCommit
}

function Invoke-AosContext([string]$FixtureRoot, [object]$Scenario, [object]$Manifest) {
    $profile = if ($Scenario.context_profile) {
        [string]$Scenario.context_profile
    } else {
        [string]$Manifest.default_context_profile
    }
    $budget = if ($Scenario.context_budget_bytes) {
        [int]$Scenario.context_budget_bytes
    } else {
        [int]$Manifest.default_context_budget_bytes
    }
    $result = Invoke-Native -File $AosBinary -Arguments @(
        "context", $FixtureRoot, "--limit", ([string]$Scenario.context_limit),
        "--profile", $profile, "--budget-bytes", ([string]$budget), "--format", "json"
    ) -WorkingDirectory $scriptRoot
    if ($result.ExitCode -ne 0) {
        Fail "context failed for $($Scenario.id): $($result.Stdout) $($result.Stderr)"
    }
    try {
        return $result.Stdout | ConvertFrom-Json
    } catch {
        Fail "invalid context JSON for $($Scenario.id)"
    }
}

function Invoke-CodexRun(
    [object]$Scenario,
    [string]$RepositoryPath,
    [string]$SourceRepositoryPath,
    [string]$Mode,
    [string]$ContextJson,
    [int]$Repeat,
    [string]$RunRoot,
    [bool]$PatchMode
) {
    $runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $cloneStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $agentRepositoryPath = $RepositoryPath
    if ($PatchMode) {
        $agentRepositoryPath = Join-Path $RunRoot ("agent-workspaces\{0}.{1}.r{2}" -f $Scenario.id, $Mode, $Repeat)
        Copy-CleanSnapshot -Source $SourceRepositoryPath -Target $agentRepositoryPath -Commit "HEAD" | Out-Null
    }
    $cloneStopwatch.Stop()
    $allowedFiles = @(
        @($Scenario.baseline_files) + @($Scenario.expected_patch_files) |
            Select-Object -Unique
    )
    $capsule = [ordered]@{
        schema_version = "AOS-P6-5-AGENT-CAPSULE-1"
        authoritative_context = if ($ContextJson) {
            $ContextJson | ConvertFrom-Json
        } else {
            $null
        }
        source_expansion = [ordered]@{
            allowed = $true
            allowed_files = $allowedFiles
            max_files = $allowedFiles.Count
            batch_initial_read = $true
        }
        mutation = [ordered]@{
            allowed_files = @($Scenario.expected_patch_files)
            control_root_immutable = ".aos/"
        }
        verification = [ordered]@{
            command = [string]$Scenario.verification_command
            max_runs = 1
            combine_final_checks = $true
        }
        provider = "provider-neutral"
    }
    $modeInstruction = if ($Mode -eq "aos" -and $AgentPolicy -eq "p6.5") {
        @"
Use this provider-neutral AOS Agent capsule. Treat its source and mutation
boundaries as mandatory. Read the allowed source files in one batched initial
inspection, make only the requested minimal patch, and use one final
verification tool call. Do not call MCP, scan directories, browse the network,
or inspect files outside the capsule.

AOS_AGENT_CAPSULE_JSON:
$($capsule | ConvertTo-Json -Depth 12 -Compress)
"@
    } elseif ($Mode -eq "aos") {
        @"
Use the following authoritative AOS context first. Open repository source only
when the context is insufficient. Preserve every source reference.

AOS_CONTEXT_JSON:
$ContextJson
"@
    } else {
        @"
No AOS context is supplied. Discover the answer from the repository.
"@
    }
    $expectedPatchInstruction = if ($AgentPolicy -eq "p6.5") {
        ""
    } else {
        @"
Expected patch files:
$(@($Scenario.expected_patch_files) -join ", ")
"@
    }
    $prompt = if ($PatchMode) {
@"
You are participating in a patch-and-test benchmark on a disposable repository
snapshot. Do not use network access or prior chat. Complete the task now in
this turn: inspect the repository, edit the smallest correct set of files,
run the required verification command, and leave the working tree containing
the patch. Do not return an acknowledgement or a plan to inspect later.
In baseline mode, discover the relevant implementation and tests from the
repository. In AOS mode, use the supplied context first and inspect only when
it does not establish the requested answer.

TASK:
$($Scenario.task)

$modeInstruction

Required verification command:
$($Scenario.verification_command)

$expectedPatchInstruction

Return the required JSON object with a concise evidence-backed answer, the
source files actually used, the changed files, verification_passed true only
if the command passed, and benchmark_result PASS only when the task is done.
"@
    } else {
@"
You are participating in a read-only project-intelligence benchmark.
Do not modify files. Do not use network access. Do not rely on prior chat.
Complete the task now in this turn. Do not return an acknowledgement or a plan
to inspect later. In baseline mode, inspect repository evidence before
answering. In AOS mode, use the supplied context first and inspect only when it
does not establish the requested answer.

TASK:
$($Scenario.task)

$modeInstruction

Return the required JSON object with a concise evidence-backed answer, the
source files actually used, and benchmark_result PASS.
"@
    }
    $schemaPath = Join-Path $RunRoot "agent-output-schema.json"
    $sandbox = if ($PatchMode) { "workspace-write" } else { "read-only" }
    $promptPath = Join-Path $RunRoot "$($Scenario.id).$Mode.r$Repeat.prompt.txt"
    Write-Utf8NoBom -Path $promptPath -Content $prompt
    $agentStartedAtUtc = [DateTime]::UtcNow
    $codexArguments = @("-y", $CodexPackage, "exec")
    if ($AgentPolicy -eq "p6.5" -and $Mode -eq "aos") {
        $codexArguments += @("-c", "mcp_servers={}")
    }
    if ($AgentPolicy -eq "p6.5") {
        $codexArguments += "--ephemeral"
    }
    $codexArguments += @(
        "--json", "--model", $Model,
        "--sandbox", $sandbox, "--cd", $agentRepositoryPath,
        "--output-schema", $schemaPath, "-"
    )
    $result = Invoke-NativeWithInput -File "npx.cmd" `
        -Arguments $codexArguments `
        -WorkingDirectory $agentRepositoryPath `
        -InputText $prompt
    $eventPath = Join-Path $RunRoot "$($Scenario.id).$Mode.r$Repeat.events.jsonl"
    Write-Utf8NoBom -Path $eventPath -Content $result.Stdout
    $events = @()
    foreach ($line in ($result.Stdout -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $events += $line | ConvertFrom-Json
        } catch {
            Fail "invalid Codex JSONL for $($Scenario.id) $Mode repeat $Repeat"
        }
    }
    $completed = @($events | Where-Object { $_.type -eq "turn.completed" }) | Select-Object -Last 1
    $failed = @($events | Where-Object { $_.type -eq "turn.failed" }) | Select-Object -Last 1
    $usageLimitFailure = @($events | Where-Object {
        $_.type -eq "error" -and
        [string]$_.message -match "(?i)(usage limit|purchase more credits|try again at)"
    }) | Select-Object -Last 1
    if ($null -ne $usageLimitFailure) {
        Fail "consumer quota unavailable for $($Scenario.id) $Mode repeat ${Repeat}: $($usageLimitFailure.message)"
    }
    $messages = @(
        $events |
            Where-Object { $_.type -eq "item.completed" -and $_.item.type -eq "agent_message" } |
            ForEach-Object { [string]$_.item.text }
    )
    $answer = if ($messages.Count -gt 0) { [string]$messages[-1] } else { "" }
    $structuredAnswer = $null
    try {
        $structuredAnswer = $answer | ConvertFrom-Json
    } catch {
        $structuredAnswer = $null
    }
    $terms = @($Scenario.expected_terms)
    $matchedTerms = @($terms | Where-Object { $answer.IndexOf([string]$_, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    $changedFiles = @()
    $verification = $null
    if ($PatchMode) {
        $status = Invoke-Native -File "git" -Arguments @("status", "--porcelain") -WorkingDirectory $agentRepositoryPath
        $changedFiles = @(
            $status.Stdout -split "`r?`n" |
                Where-Object { $_.Length -ge 4 } |
                ForEach-Object { $_.Substring(3).Trim().Trim('"') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        $verification = Invoke-Native -File "powershell.exe" -Arguments @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
            [string]$Scenario.verification_command
        ) -WorkingDirectory $agentRepositoryPath
    }
    $firstPatchSeconds = $null
    if ($PatchMode -and $changedFiles.Count -gt 0) {
        $patchTimes = @(
            $changedFiles |
                ForEach-Object {
                    $changedPath = Join-Path $agentRepositoryPath ([string]$_)
                    if (Test-Path -LiteralPath $changedPath -PathType Leaf) {
                        $writeTime = (Get-Item -LiteralPath $changedPath).LastWriteTimeUtc
                        if ($writeTime -ge $agentStartedAtUtc) {
                            ($writeTime - $agentStartedAtUtc).TotalSeconds
                        }
                    }
                }
        )
        if ($patchTimes.Count -gt 0) {
            $firstPatchSeconds = [Math]::Round(
                [double](($patchTimes | Measure-Object -Minimum).Minimum),
                3
            )
        }
    }
    $expectedPatchFiles = @($Scenario.expected_patch_files)
    $patchFilesPresent = $PatchMode -and $expectedPatchFiles.Count -gt 0 -and @(
        $expectedPatchFiles |
            Where-Object { $changedFiles -notcontains [string]$_ }
    ).Count -eq 0
    $verificationPassed = if ($PatchMode) {
        $null -ne $verification -and $verification.ExitCode -eq 0
    } else {
        $false
    }
    $exactPatchScope = $changedFiles.Count -eq $expectedPatchFiles.Count -and @(
        $expectedPatchFiles |
            Where-Object { $changedFiles -notcontains [string]$_ }
    ).Count -eq 0
    $reportedChangedFiles = if ($null -ne $structuredAnswer) {
        @($structuredAnswer.changed_files)
    } else {
        @()
    }
    $reportedPatchScope = $reportedChangedFiles.Count -eq $expectedPatchFiles.Count -and @(
        $expectedPatchFiles |
            Where-Object { $reportedChangedFiles -notcontains [string]$_ }
    ).Count -eq 0
    $reportedSourceFiles = if ($null -ne $structuredAnswer) {
        @($structuredAnswer.source_files)
    } else {
        @()
    }
    $sourceScopePreserved = @(
        $reportedSourceFiles |
            Where-Object { $allowedFiles -notcontains [string]$_ }
    ).Count -eq 0
    $commandEvents = @(
        $events | Where-Object {
            $_.type -eq "item.completed" -and
            $_.item.type -eq "command_execution"
        }
    )
    $mcpEvents = @(
        $events | Where-Object {
            $_.type -eq "item.completed" -and
            $_.item.type -eq "mcp_tool_call"
        }
    )
    $taskSuccess = if ($PatchMode) {
        $result.ExitCode -eq 0 -and
            $null -ne $completed -and
            $null -eq $failed -and
            $answer -match '"benchmark_result"\s*:\s*"PASS"' -and
            $patchFilesPresent -and
            $verificationPassed -and
            (
                $AgentPolicy -ne "p6.5" -or
                (
                    $exactPatchScope -and
                    $reportedPatchScope -and
                    ($Mode -ne "aos" -or $sourceScopePreserved) -and
                    ($Mode -ne "aos" -or $mcpEvents.Count -eq 0)
                )
            )
    } else {
        $result.ExitCode -eq 0 -and
            $null -ne $completed -and
            $null -eq $failed -and
            $answer -match '"benchmark_result"\s*:\s*"PASS"' -and
            $matchedTerms.Count -eq $terms.Count
    }
    $eventText = $result.Stdout
    $filesRead = @(
        $Scenario.baseline_files |
            Where-Object { $eventText.IndexOf([string]$_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
    )
    $runStopwatch.Stop()
    [pscustomobject]@{
        scenario_id = [string]$Scenario.id
        mode = $Mode
        repeat = $Repeat
        model = $Model
        provider = "codex-chatgpt"
        codex_package = $CodexPackage
        agent_policy = $AgentPolicy
        status = if ($taskSuccess) { "PASS" } else { "FAIL" }
        task_success = $taskSuccess
        input_tokens = if ($completed) { [int64]$completed.usage.input_tokens } else { 0 }
        cached_input_tokens = if ($completed) { [int64]$completed.usage.cached_input_tokens } else { 0 }
        output_tokens = if ($completed) { [int64]$completed.usage.output_tokens } else { 0 }
        reasoning_output_tokens = if ($completed) { [int64]$completed.usage.reasoning_output_tokens } else { 0 }
        elapsed_seconds = $result.ElapsedSeconds
        timing = [ordered]@{
            clone_seconds = [Math]::Round($cloneStopwatch.Elapsed.TotalSeconds, 3)
            agent_seconds = $result.ElapsedSeconds
            time_to_first_patch_seconds = $firstPatchSeconds
            verification_seconds = if ($verification) { $verification.ElapsedSeconds } else { 0 }
            runner_total_seconds = [Math]::Round($runStopwatch.Elapsed.TotalSeconds, 3)
        }
        files_read = @($filesRead)
        files_read_count = @($filesRead).Count
        command_count = $commandEvents.Count
        mcp_call_count = $mcpEvents.Count
        expected_terms = $terms
        matched_terms = $matchedTerms
        expected_patch_files = $expectedPatchFiles
        changed_files = $changedFiles
        reported_changed_files = $reportedChangedFiles
        reported_source_files = $reportedSourceFiles
        source_scope_preserved = $sourceScopePreserved
        verification_command = if ($PatchMode) { [string]$Scenario.verification_command } else { "" }
        verification_passed = $verificationPassed
        verification_exit_code = if ($verification) { $verification.ExitCode } else { $null }
        verification_output = if ($verification) { $verification.Stdout.Trim() } else { "" }
        prompt_path = $promptPath
        event_path = $eventPath
        stderr_summary = if ($result.ExitCode -eq 0) { "" } else { $result.Stderr.Trim() }
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Fail "manifest does not exist: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $AosBinary -PathType Leaf)) {
    Fail "AOS binary does not exist: $AosBinary; run cargo build --locked first"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$patchManifest = [string]$manifest.qualification_level -eq "patch-and-test"
$requestedScenarioIds = @()
if ([string]::IsNullOrWhiteSpace($ScenarioId)) {
    $selectedScenarios = @($manifest.scenarios)
} else {
    $requestedScenarioIds = @(
        $ScenarioId.Split(",") |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $selectedScenarios = @($manifest.scenarios | Where-Object {
        $requestedScenarioIds -contains [string]$_.id
    })
}
if ($selectedScenarios.Count -eq 0 -or (
    -not [string]::IsNullOrWhiteSpace($ScenarioId) -and
    $selectedScenarios.Count -ne $requestedScenarioIds.Count
)) {
    Fail "one or more scenarios do not exist in manifest: $ScenarioId"
}
$runId = "p4-ai-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$runRoot = Join-Path $OutputDir $runId
$snapshotRoot = Join-Path $runRoot "snapshots"
$structuralRoot = Join-Path $runRoot "structural"
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$agentProperties = [ordered]@{
    answer = [ordered]@{ type = "string" }
    source_files = [ordered]@{
        type = "array"
        items = [ordered]@{ type = "string" }
    }
    benchmark_result = [ordered]@{
        type = "string"
        enum = @("PASS")
    }
}
$agentRequired = @("answer", "source_files", "benchmark_result")
if ($patchManifest) {
    $agentProperties.changed_files = [ordered]@{
        type = "array"
        items = [ordered]@{ type = "string" }
    }
    $agentProperties.verification_passed = [ordered]@{ type = "boolean" }
    $agentProperties.verification_output = [ordered]@{ type = "string" }
    $agentRequired += @("changed_files", "verification_passed", "verification_output")
}
$agentSchema = [ordered]@{
    type = "object"
    properties = $agentProperties
    required = $agentRequired
    additionalProperties = $false
}
Write-Utf8NoBom -Path (Join-Path $runRoot "agent-output-schema.json") -Content ($agentSchema | ConvertTo-Json -Depth 6)

$repositoryEnvironments = @(
    $manifest.scenarios |
        ForEach-Object { [string]$_.repository_env } |
        Sort-Object -Unique
)
$originalRepositoryEnvironments = @{}
$snapshotByEnvironment = @{}
$repositoryCommits = [ordered]@{}
foreach ($name in $repositoryEnvironments) {
    $source = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($source)) {
        Fail "environment variable is not set: $name"
    }
    $expectedCommits = @(
        $manifest.scenarios |
            Where-Object { [string]$_.repository_env -eq $name } |
            ForEach-Object { [string]$_.expected_commit } |
            Sort-Object -Unique
    )
    if ($expectedCommits.Count -ne 1) {
        Fail "repository environment must bind one expected commit: $name"
    }
    $originalRepositoryEnvironments[$name] = $source
    $snapshotName = $name.ToLowerInvariant().Replace("_repo", "").Replace("_", "-")
    $snapshotPath = Join-Path $snapshotRoot $snapshotName
    $resolvedCommit = Copy-CleanSnapshot `
        -Source $source `
        -Target $snapshotPath `
        -Commit $expectedCommits[0]
    $snapshotByEnvironment[$name] = $snapshotPath
    $repositoryCommits[$snapshotName] = $resolvedCommit
    [Environment]::SetEnvironmentVariable($name, $snapshotPath)
}

try {
    $structuralStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $structural = Invoke-Native -File "powershell.exe" -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        (Join-Path $scriptRoot "run_p4_value_benchmark.ps1"),
        "-ManifestPath", $ManifestPath,
        "-OutputDir", $structuralRoot,
        "-AosBinary", $AosBinary
    ) -WorkingDirectory $scriptRoot
    $structuralStopwatch.Stop()
    if ($structural.ExitCode -ne 0) {
        Fail "structural benchmark failed: $($structural.Stdout) $($structural.Stderr)"
    }
    $structuralResultPath = (
        $structural.Stdout -split "`r?`n" |
            Where-Object { $_ -like "Result: *" } |
            Select-Object -Last 1
    ).Substring(8)
    $structuralResult = Get-Content -LiteralPath $structuralResultPath -Raw | ConvertFrom-Json
    if ($structuralResult.structural_status -ne "PASS") {
        Fail "structural benchmark did not pass"
    }
    $fixtureRoot = Split-Path -Parent $structuralResultPath
    $allRuns = @()
    $scenarioTimings = @()
    foreach ($scenario in $selectedScenarios) {
        $repositoryPath = [string]$snapshotByEnvironment[
            [string]$scenario.repository_env
        ]
        $contextStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $contextEnvelope = Invoke-AosContext -FixtureRoot (Join-Path $fixtureRoot $scenario.id) -Scenario $scenario -Manifest $manifest
        $contextStopwatch.Stop()
        $scenarioTimings += [pscustomobject]@{
            scenario_id = [string]$scenario.id
            context_generation_seconds = [Math]::Round($contextStopwatch.Elapsed.TotalSeconds, 3)
        }
        $contextJson = $contextEnvelope.data | ConvertTo-Json -Depth 8 -Compress
        for ($repeat = 1; $repeat -le $Repeats; $repeat++) {
            $patchMode = [string]$manifest.qualification_level -eq "patch-and-test"
            Write-Output "Running $($scenario.id) baseline repeat $repeat/$Repeats"
            $allRuns += Invoke-CodexRun -Scenario $scenario -RepositoryPath $repositoryPath -SourceRepositoryPath $repositoryPath -Mode "baseline" -ContextJson "" -Repeat $repeat -RunRoot $runRoot -PatchMode $patchMode
            Write-Output "Running $($scenario.id) aos repeat $repeat/$Repeats"
            $allRuns += Invoke-CodexRun -Scenario $scenario -RepositoryPath $repositoryPath -SourceRepositoryPath $repositoryPath -Mode "aos" -ContextJson $contextJson -Repeat $repeat -RunRoot $runRoot -PatchMode $patchMode
        }
    }
} finally {
    foreach ($name in $repositoryEnvironments) {
        [Environment]::SetEnvironmentVariable(
            $name,
            [string]$originalRepositoryEnvironments[$name]
        )
    }
}

$baselineRuns = @($allRuns | Where-Object { $_.mode -eq "baseline" })
$aosRuns = @($allRuns | Where-Object { $_.mode -eq "aos" })
$baselineTokens = [double](($baselineRuns | Measure-Object -Property input_tokens -Sum).Sum)
$aosTokens = [double](($aosRuns | Measure-Object -Property input_tokens -Sum).Sum)
$baselineTime = [double](($baselineRuns | Measure-Object -Property elapsed_seconds -Sum).Sum)
$aosTime = [double](($aosRuns | Measure-Object -Property elapsed_seconds -Sum).Sum)
$baselineFirstPatch = [double]((
    $baselineRuns |
        ForEach-Object { $_.timing.time_to_first_patch_seconds } |
        Where-Object { $null -ne $_ } |
        Measure-Object -Sum
).Sum)
$aosFirstPatch = [double]((
    $aosRuns |
        ForEach-Object { $_.timing.time_to_first_patch_seconds } |
        Where-Object { $null -ne $_ } |
        Measure-Object -Sum
).Sum)
$baselineVerification = [double]((
    $baselineRuns |
        ForEach-Object { $_.timing.verification_seconds } |
        Measure-Object -Sum
).Sum)
$aosVerification = [double]((
    $aosRuns |
        ForEach-Object { $_.timing.verification_seconds } |
        Measure-Object -Sum
).Sum)
$baselineCommands = [double]((
    $baselineRuns |
        ForEach-Object { $_.command_count } |
        Measure-Object -Sum
).Sum)
$aosCommands = [double]((
    $aosRuns |
        ForEach-Object { $_.command_count } |
        Measure-Object -Sum
).Sum)
$firstPatchReduction = if ($baselineFirstPatch -gt 0) {
    100 * (1 - ($aosFirstPatch / $baselineFirstPatch))
} else { 0 }
$baselineSuccess = if ($baselineRuns.Count -gt 0) {
    100 * @($baselineRuns | Where-Object { $_.task_success }).Count / $baselineRuns.Count
} else { 0 }
$aosSuccess = if ($aosRuns.Count -gt 0) {
    100 * @($aosRuns | Where-Object { $_.task_success }).Count / $aosRuns.Count
} else { 0 }
$tokenReduction = if ($baselineTokens -gt 0) {
    100 * (1 - ($aosTokens / $baselineTokens))
} else { 0 }
$timeReduction = if ($baselineTime -gt 0) {
    100 * (1 - ($aosTime / $baselineTime))
} else { 0 }
$commandReduction = if ($baselineCommands -gt 0) {
    100 * (1 - ($aosCommands / $baselineCommands))
} else { 0 }
$contextRepeatable = @(
    $structuralResult.scenarios |
        Where-Object { $_.withheld_count -ne $_.withheld_with_reason }
).Count -eq 0
$thresholds = [ordered]@{
    token_reduction = $tokenReduction -ge $MinimumTokenReductionPercent
    time_reduction = $timeReduction -ge $MinimumTimeReductionPercent
    success_regression = $aosSuccess -ge ($baselineSuccess - $MaximumSuccessRegressionPercent)
    all_aos_tasks_success = @($aosRuns | Where-Object { -not $_.task_success }).Count -eq 0
    structural_context = $structuralResult.structural_status -eq "PASS"
    withholding_reasons = $contextRepeatable
    repeat_count = $Repeats -ge 2
}
if ($AgentPolicy -eq "p6.5") {
    $thresholds.command_reduction =
        $commandReduction -ge $MinimumCommandReductionPercent
    $thresholds.execution_count =
        $allRuns.Count -ge ($selectedScenarios.Count * $Repeats * 2)
    $thresholds.scope_safety = @($aosRuns | Where-Object {
        -not $_.source_scope_preserved -or
        [int]$_.mcp_call_count -ne 0
    }).Count -eq 0
}
$allPass = @($thresholds.Values | Where-Object { -not $_ }).Count -eq 0
$qualificationReady = [string]$manifest.qualification_level -eq "patch-and-test" -and @(
    $selectedScenarios |
        Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.verification_command) -or
            @($_.expected_patch_files).Count -eq 0
        }
).Count -eq 0
$marker = if ($AgentPolicy -eq "p6.5" -and $allPass -and $qualificationReady) {
    "AOS_P6_6_CONSUMER_BATCH_OK"
} elseif ($AgentPolicy -eq "p6.5") {
    "AOS_P6_6_CONSUMER_BATCH_NOT_MET"
} elseif ($allPass -and $qualificationReady) {
    "AOS_P4_VALUE_BENCHMARK_OK"
} elseif ($allPass) {
    "AOS_P4_AI_FACING_CALIBRATION_OK"
} else {
    "AOS_P4_VALUE_BENCHMARK_NOT_MET"
}
$result = [ordered]@{
    schema_version = "AOS-P4-AI-FACING-BENCHMARK-1"
    run_id = $runId
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    model = $Model
    provider = "codex-chatgpt"
    codex_package = $CodexPackage
    agent_policy = $AgentPolicy
    repeats = $Repeats
    scenario_count = $selectedScenarios.Count
    repository_commits = $repositoryCommits
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
        baseline_verification_seconds = [Math]::Round($baselineVerification, 3)
        aos_verification_seconds = [Math]::Round($aosVerification, 3)
        baseline_command_count = [int]$baselineCommands
        aos_command_count = [int]$aosCommands
        command_reduction_percent = [Math]::Round($commandReduction, 2)
        structural_harness_seconds = [Math]::Round($structuralStopwatch.Elapsed.TotalSeconds, 3)
        baseline_task_success_percent = [Math]::Round($baselineSuccess, 2)
        aos_task_success_percent = [Math]::Round($aosSuccess, 2)
    }
    thresholds = $thresholds
    qualification_level = [string]$manifest.qualification_level
    qualification_ready = $qualificationReady
    status = if ($allPass) { "PASS" } else { "FAIL" }
    pass_marker = $marker
    structural_result = $structuralResultPath
    scenario_timings = $scenarioTimings
    runs = $allRuns
}
$resultPath = Join-Path $runRoot "ai-facing-results.json"
Write-Utf8NoBom -Path $resultPath -Content ($result | ConvertTo-Json -Depth 10)

Write-Output "P4 AI-facing benchmark: $runId"
Write-Output "Model: $Model"
Write-Output "Repeats: $Repeats"
Write-Output "Token reduction: $([Math]::Round($tokenReduction, 2))%"
Write-Output "Time reduction: $([Math]::Round($timeReduction, 2))%"
Write-Output "Time-to-first-patch reduction: $([Math]::Round($firstPatchReduction, 2))%"
Write-Output "Baseline success: $([Math]::Round($baselineSuccess, 2))%"
Write-Output "AOS success: $([Math]::Round($aosSuccess, 2))%"
Write-Output "Result: $resultPath"
Write-Output $result.pass_marker
