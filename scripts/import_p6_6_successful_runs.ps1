[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ResultPath,
    [string]$ManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$CheckpointPath
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "p6_6_checkpoint.ps1")

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $scriptRoot "..\benchmarks\p6-6\scenarios.json"
}
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$CheckpointPath = [System.IO.Path]::GetFullPath($CheckpointPath)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_P6_6_IMPORT_FAILED: $Message"
}

function Invoke-Native(
    [string]$File,
    [string[]]$Arguments,
    [string]$WorkingDirectory
) {
    $original = Get-Location
    $originalErrorAction = $ErrorActionPreference
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $ErrorActionPreference = "Continue"
        $output = & $File @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $originalErrorAction
        Set-Location -LiteralPath $original
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join [Environment]::NewLine)
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Fail "manifest does not exist: $ManifestPath"
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$results = @()
foreach ($path in $ResultPath) {
    $resolved = [System.IO.Path]::GetFullPath($path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        Fail "result does not exist: $resolved"
    }
    $result = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
    $result | Add-Member -NotePropertyName import_source_path `
        -NotePropertyValue $resolved -Force
    $results += $result
}
if ($results.Count -eq 0) {
    Fail "at least one result is required"
}

$first = $results[0]
foreach ($result in $results) {
    foreach ($property in @("model", "provider", "codex_package", "agent_policy", "repeats")) {
        if ([string]$result.$property -ne [string]$first.$property) {
            Fail "result config mismatch: $property"
        }
    }
}

if (Test-Path -LiteralPath $CheckpointPath -PathType Leaf) {
    $checkpoint = Read-P6_6Checkpoint -Path $CheckpointPath
    Assert-P6_6CheckpointConfig `
        -Checkpoint $checkpoint `
        -Model ([string]$first.model) `
        -Provider ([string]$first.provider) `
        -CodexPackage ([string]$first.codex_package) `
        -AgentPolicy ([string]$first.agent_policy) `
        -Repeats ([int]$first.repeats)
} else {
    $checkpoint = New-P6_6Checkpoint `
        -Model ([string]$first.model) `
        -Provider ([string]$first.provider) `
        -CodexPackage ([string]$first.codex_package) `
        -AgentPolicy ([string]$first.agent_policy) `
        -Repeats ([int]$first.repeats)
}

$artifactRoot = Join-Path (Split-Path -Parent $CheckpointPath) "artifacts"
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$imported = 0
$eligibleScenarios = 0
$allCandidateRuns = @(
    $results |
        ForEach-Object {
            $source = [string]$_.import_source_path
            @($_.runs) | ForEach-Object {
                $_ | Add-Member -NotePropertyName import_source_result `
                    -NotePropertyValue $source -Force
                $_
            }
        }
)

foreach ($scenario in $manifest.scenarios) {
    $scenarioRuns = @($allCandidateRuns | Where-Object {
        [string]$_.scenario_id -eq [string]$scenario.id
    })
    $expectedKeys = @()
    for ($repeat = 1; $repeat -le [int]$first.repeats; $repeat++) {
        foreach ($mode in @("baseline", "aos")) {
            $expectedKeys += Get-P6_6CheckpointKey `
                -ScenarioId ([string]$scenario.id) `
                -Mode $mode `
                -Repeat $repeat
        }
    }
    $successfulRuns = @($scenarioRuns | Where-Object {
        [bool]$_.task_success -and
        [bool]$_.verification_passed -and
        [string]$_.status -eq "PASS"
    })
    $successfulKeys = @($successfulRuns | ForEach-Object {
        Get-P6_6CheckpointKey `
            -ScenarioId ([string]$_.scenario_id) `
            -Mode ([string]$_.mode) `
            -Repeat ([int]$_.repeat)
    })
    if (
        $successfulRuns.Count -ne $expectedKeys.Count -or
        @($successfulKeys | Sort-Object -Unique).Count -ne $expectedKeys.Count -or
        @(Compare-Object ($expectedKeys | Sort-Object) ($successfulKeys | Sort-Object)).Count -ne 0
    ) {
        continue
    }

    $eligibleScenarios++
    foreach ($run in $successfulRuns) {
        $resultRoot = Split-Path -Parent ([string]$run.import_source_result)
        $workspace = Join-Path $resultRoot (
            "agent-workspaces\{0}.{1}.r{2}" -f
                $scenario.id,
                $run.mode,
                $run.repeat
        )
        if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
            Fail "workspace does not exist for $($scenario.id) $($run.mode) repeat $($run.repeat)"
        }
        $head = Invoke-Native `
            -File "git" `
            -Arguments @("rev-parse", "HEAD") `
            -WorkingDirectory $workspace
        if (
            $head.ExitCode -ne 0 -or
            $head.Output.Trim() -ne [string]$scenario.expected_commit
        ) {
            Fail "repository commit mismatch for $($scenario.id)"
        }
        $status = Invoke-Native `
            -File "git" `
            -Arguments @("status", "--porcelain") `
            -WorkingDirectory $workspace
        $changed = @(
            $status.Output -split "`r?`n" |
                Where-Object { $_.Length -ge 4 } |
                ForEach-Object { $_.Substring(3).Trim().Trim('"') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object
        )
        $expectedChanged = @($scenario.expected_patch_files | Sort-Object)
        if (($changed -join "`n") -ne ($expectedChanged -join "`n")) {
            Fail "changed-file scope mismatch for $($scenario.id) $($run.mode) repeat $($run.repeat)"
        }
        $verification = Invoke-Native `
            -File "powershell.exe" `
            -Arguments @(
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                [string]$scenario.verification_command
            ) `
            -WorkingDirectory $workspace
        if ($verification.ExitCode -ne 0) {
            Fail "verification replay failed for $($scenario.id) $($run.mode) repeat $($run.repeat)"
        }
        $patch = Invoke-Native `
            -File "git" `
            -Arguments @("diff", "--binary", "HEAD", "--") `
            -WorkingDirectory $workspace
        if ($patch.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($patch.Output)) {
            Fail "patch capture failed for $($scenario.id) $($run.mode) repeat $($run.repeat)"
        }
        $key = Get-P6_6CheckpointKey `
            -ScenarioId ([string]$scenario.id) `
            -Mode ([string]$run.mode) `
            -Repeat ([int]$run.repeat)
        $patchPath = Join-Path $artifactRoot "$($key.Replace('|', '.')).patch.diff"
        [System.IO.File]::WriteAllText($patchPath, $patch.Output, $utf8NoBom)

        $candidate = $run | Select-Object *
        $candidate | Add-Member -NotePropertyName patch_path `
            -NotePropertyValue $patchPath -Force
        $candidate | Add-Member -NotePropertyName changed_files `
            -NotePropertyValue $changed -Force
        $candidate | Add-Member -NotePropertyName import_source_result `
            -NotePropertyValue ([string]$run.import_source_result) -Force
        $before = @($checkpoint.runs).Count
        Add-P6_6CheckpointRun `
            -Checkpoint $checkpoint `
            -Run $candidate `
            -Scenario $scenario `
            -RepositoryCommit ([string]$scenario.expected_commit) | Out-Null
        if (@($checkpoint.runs).Count -gt $before) {
            $imported++
            Write-P6_6Checkpoint -Path $CheckpointPath -Checkpoint $checkpoint
        }
    }
}

if ($eligibleScenarios -eq 0) {
    Fail "no complete successful scenario was eligible for import"
}
Write-P6_6Checkpoint -Path $CheckpointPath -Checkpoint $checkpoint

Write-Output "Eligible scenarios: $eligibleScenarios"
Write-Output "Imported executions: $imported"
Write-Output "Checkpoint executions: $(@($checkpoint.runs).Count)"
Write-Output "Checkpoint: $CheckpointPath"
Write-Output "AOS_P6_6_SUCCESSFUL_RUN_IMPORT_OK"
