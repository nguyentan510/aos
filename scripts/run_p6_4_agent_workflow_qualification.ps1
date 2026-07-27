[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PilotResultPath,
    [string]$OutputDir = "",
    [string]$Model = "gpt-5.6-sol",
    [string]$CodexPackage = "@openai/codex@0.145.0"
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if (-not $OutputDir) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-4-agent-qualification"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

function Fail([string]$Message) {
    throw "AOS_P6_4_AGENT_WORKFLOW_FAILED: $Message"
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
        "aos-p6-4-native-" + [guid]::NewGuid().ToString("N") + ".stderr"
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
    Invoke-Native -File "git" -Arguments @("config", "user.name", "AOS P6.4 Pilot") -WorkingDirectory $Target | Out-Null
    Invoke-Native -File "git" -Arguments @("config", "user.email", "p6-4@aos.local") -WorkingDirectory $Target | Out-Null
    Invoke-Native -File "cargo" -Arguments @("generate-lockfile") -WorkingDirectory $Target | Out-Null
    Invoke-Native -File "git" -Arguments @("add", ".") -WorkingDirectory $Target | Out-Null
    $commit = Invoke-Native -File "git" -Arguments @("commit", "--quiet", "-m", "fixture baseline") -WorkingDirectory $Target
    if ($commit.ExitCode -ne 0) {
        Fail "could not commit disposable Agent fixture: $($commit.Stderr)"
    }
}

if (-not (Test-Path -LiteralPath $PilotResultPath -PathType Leaf)) {
    Fail "controlled-adoption result does not exist: $PilotResultPath"
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
    Fail "installed-RC4 Agent brief is missing"
}
$brief = Get-Content -LiteralPath $briefPath -Raw | ConvertFrom-Json
if ($brief.provider -ne "provider-neutral" -or $brief.secret_scan -ne "pass") {
    Fail "Agent brief did not preserve the provider-neutral safety contract"
}
$contextJson = $brief.context | ConvertTo-Json -Depth 10 -Compress

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "p6-4-agent-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
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
            enum = @("PASS")
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
        task = "Explain which file defines the package identity and which function exposes it. Do not modify source. Run cargo test to verify the current project."
        expected_changed = @()
        expected_terms = @("Cargo.toml", "src/lib.rs", "project_name")
    },
    [ordered]@{
        id = "bugfix"
        task = "Fix the failing project_name regression with the smallest source change. Do not weaken or remove the test. Run cargo test."
        expected_changed = @("src/lib.rs")
        expected_terms = @("src/lib.rs", "cargo test")
    },
    [ordered]@{
        id = "feature"
        task = "Implement project_slug so the existing test passes. Derive the stable slug from the package identity semantics already present in the fixture. Run cargo test."
        expected_changed = @("src/lib.rs")
        expected_terms = @("src/lib.rs", "cargo test")
    }
)
$runs = @()
$npx = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    "npx.cmd"
} else {
    "npx"
}

foreach ($definition in $scenarioDefinitions) {
    $workspace = Join-Path $workspaceRoot $definition.id
    Initialize-Workspace -Source $sourceRoot -Target $workspace -Scenario $definition.id
    $controlBefore = Get-ControlFingerprint $workspace
    $prompt = @"
You are qualifying an installed AOS Agent workflow on a disposable local
repository. Do not use network access or prior chat. Use the authoritative AOS
context first, preserve its source references, and open repository source only
when the context is insufficient. Complete the task in this turn and keep the
change minimal.

TASK:
$($definition.task)

AOS_CONTEXT_JSON:
$contextJson

Return the required JSON object. Set task_result to PASS only when the task is
complete and the independent verification command passed.
"@
    $promptPath = Join-Path $runRoot "$($definition.id).prompt.txt"
    Write-Utf8 -Path $promptPath -Content $prompt
    $startedAt = [DateTime]::UtcNow
    $agent = Invoke-Native -File $npx -Arguments @(
        "-y", $CodexPackage,
        "exec",
        "--json",
        "--model", $Model,
        "--sandbox", "workspace-write",
        "--cd", $workspace,
        "--output-schema", $schemaPath,
        "-"
    ) -WorkingDirectory $workspace -InputText $prompt
    $eventPath = Join-Path $runRoot "$($definition.id).events.jsonl"
    Write-Utf8 -Path $eventPath -Content $agent.Stdout
    $events = @()
    foreach ($line in ($agent.Stdout -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            try {
                $events += $line | ConvertFrom-Json
            } catch {
                Fail "$($definition.id) returned invalid Codex JSONL"
            }
        }
    }
    $completed = @($events | Where-Object { $_.type -eq "turn.completed" }) | Select-Object -Last 1
    $failed = @($events | Where-Object { $_.type -eq "turn.failed" }) | Select-Object -Last 1
    $message = @(
        $events |
            Where-Object { $_.type -eq "item.completed" -and $_.item.type -eq "agent_message" } |
            ForEach-Object { [string]$_.item.text }
    ) | Select-Object -Last 1
    $status = Invoke-Native -File "git" -Arguments @("status", "--porcelain") -WorkingDirectory $workspace
    $changed = @(
        $status.Stdout -split "`r?`n" |
            Where-Object { $_.Length -ge 4 } |
            ForEach-Object { $_.Substring(3).Trim().Trim('"') } |
            Where-Object { $_ }
    )
    $verification = Invoke-Native -File "cargo" -Arguments @("test") -WorkingDirectory $workspace
    $controlAfter = Get-ControlFingerprint $workspace
    $expectedChanged = @($definition.expected_changed)
    $changesMatch = $changed.Count -eq $expectedChanged.Count -and @(
        $expectedChanged | Where-Object { $changed -notcontains $_ }
    ).Count -eq 0
    $termsMatch = @(
        $definition.expected_terms |
            Where-Object {
                ([string]$message).IndexOf(
                    [string]$_,
                    [StringComparison]::OrdinalIgnoreCase
                ) -lt 0
            }
    ).Count -eq 0
    $firstPatchSeconds = $null
    if ($changed -contains "src/lib.rs") {
        $writeTime = (Get-Item -LiteralPath (Join-Path $workspace "src/lib.rs")).LastWriteTimeUtc
        if ($writeTime -ge $startedAt) {
            $firstPatchSeconds = [Math]::Round(($writeTime - $startedAt).TotalSeconds, 3)
        }
    }
    $taskPass = $agent.ExitCode -eq 0 -and
        $null -ne $completed -and
        $null -eq $failed -and
        ([string]$message) -match '"task_result"\s*:\s*"PASS"' -and
        $verification.ExitCode -eq 0 -and
        $changesMatch -and
        $termsMatch -and
        $controlBefore -eq $controlAfter
    $runs += [ordered]@{
        scenario = $definition.id
        status = if ($taskPass) { "PASS" } else { "FAIL" }
        agent_exit_code = $agent.ExitCode
        task_success = $taskPass
        input_tokens = if ($completed) { [int64]$completed.usage.input_tokens } else { 0 }
        cached_input_tokens = if ($completed) { [int64]$completed.usage.cached_input_tokens } else { 0 }
        output_tokens = if ($completed) { [int64]$completed.usage.output_tokens } else { 0 }
        elapsed_seconds = $agent.ElapsedSeconds
        time_to_first_patch_seconds = $firstPatchSeconds
        expected_changed_files = $expectedChanged
        changed_files = $changed
        expected_terms_found = $termsMatch
        verification_passed = $verification.ExitCode -eq 0
        control_data_unchanged = $controlBefore -eq $controlAfter
        prompt_path = $promptPath
        event_path = $eventPath
        stderr_summary = if ($agent.ExitCode -eq 0) { "" } else { $agent.Stderr.Trim() }
    }
}

$allPass = @($runs | Where-Object { -not $_.task_success }).Count -eq 0
$inputTokenTotal = [int64]0
$outputTokenTotal = [int64]0
foreach ($run in $runs) {
    $inputTokenTotal += [int64]$run["input_tokens"]
    $outputTokenTotal += [int64]$run["output_tokens"]
}
$result = [ordered]@{
    schema_version = "AOS-P6-4-AGENT-WORKFLOW-1"
    run_id = $runId
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    controlled_adoption_result = [System.IO.Path]::GetFullPath($PilotResultPath)
    model = $Model
    provider = "codex-chatgpt"
    codex_package = $CodexPackage
    scenario_count = $runs.Count
    task_success_count = @($runs | Where-Object { $_.task_success }).Count
    input_tokens = $inputTokenTotal
    output_tokens = $outputTokenTotal
    context_source = "installed RC4 provider-neutral Agent brief"
    runs = $runs
    thresholds = [ordered]@{
        onboarding_success = @($runs | Where-Object {
            $_.scenario -eq "onboarding" -and $_.task_success
        }).Count -eq 1
        bugfix_success = @($runs | Where-Object {
            $_.scenario -eq "bugfix" -and $_.task_success
        }).Count -eq 1
        feature_success = @($runs | Where-Object {
            $_.scenario -eq "feature" -and $_.task_success
        }).Count -eq 1
        verification_passed = @($runs | Where-Object {
            -not $_.verification_passed
        }).Count -eq 0
        control_data_unchanged = @($runs | Where-Object {
            -not $_.control_data_unchanged
        }).Count -eq 0
    }
    status = if ($allPass) { "PASS" } else { "FAIL" }
    marker = if ($allPass) {
        "AOS_P6_4_AGENT_WORKFLOW_QUALIFICATION_OK"
    } else {
        "AOS_P6_4_AGENT_WORKFLOW_QUALIFICATION_NOT_MET"
    }
}
$resultPath = Join-Path $runRoot "p6-4-agent-workflow.json"
Write-Utf8 -Path $resultPath -Content ($result | ConvertTo-Json -Depth 12)

Write-Output "P6.4 Agent workflow: $runId"
Write-Output "Tasks: $($result.task_success_count)/$($result.scenario_count)"
Write-Output "Input tokens: $($result.input_tokens)"
Write-Output "Result: $resultPath"
Write-Output $result.marker
if (-not $allPass) {
    exit 1
}
