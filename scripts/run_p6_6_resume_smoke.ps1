[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "p6_6_checkpoint.ps1")
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$root = Join-Path ([System.IO.Path]::GetTempPath()) (
    "aos-p6-6-resume-smoke-" + [guid]::NewGuid().ToString("N")
)

function Expect-Failure([scriptblock]$Action, [string]$Label) {
    try {
        & $Action
    } catch {
        if ([string]$_.Exception.Message -notlike "AOS_P6_6_CHECKPOINT_FAILED:*") {
            throw
        }
        return
    }
    throw "AOS_P6_6_RESUME_SMOKE_FAILED: expected failure for $Label"
}

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $promptPath = Join-Path $root "prompt.txt"
    $eventPath = Join-Path $root "events.jsonl"
    $patchPath = Join-Path $root "patch.diff"
    [System.IO.File]::WriteAllText($promptPath, "prompt", $utf8NoBom)
    [System.IO.File]::WriteAllText($eventPath, '{"type":"turn.completed"}', $utf8NoBom)
    [System.IO.File]::WriteAllText($patchPath, "diff --git a/README.md b/README.md", $utf8NoBom)

    $scenario = [pscustomobject]@{
        id = "resume-smoke"
        expected_commit = "0123456789012345678901234567890123456789"
        expected_patch_files = @("README.md")
        task = "smoke"
        verification_command = "exit 0"
    }
    $run = [pscustomobject]@{
        scenario_id = "resume-smoke"
        mode = "aos"
        repeat = 1
        model = "smoke-model"
        provider = "codex-chatgpt"
        codex_package = "codex-smoke"
        agent_policy = "p6.5"
        status = "PASS"
        task_success = $true
        verification_passed = $true
        source_scope_preserved = $true
        mcp_call_count = 0
        changed_files = @("README.md")
        input_tokens = 10
        prompt_path = $promptPath
        event_path = $eventPath
        patch_path = $patchPath
    }
    $checkpointPath = Join-Path $root "checkpoint.json"
    $checkpoint = New-P6_6Checkpoint `
        -Model "smoke-model" `
        -Provider "codex-chatgpt" `
        -CodexPackage "codex-smoke" `
        -AgentPolicy "p6.5" `
        -Repeats 2
    Add-P6_6CheckpointRun `
        -Checkpoint $checkpoint `
        -Run $run `
        -Scenario $scenario `
        -RepositoryCommit ([string]$scenario.expected_commit) | Out-Null
    Write-P6_6Checkpoint -Path $checkpointPath -Checkpoint $checkpoint

    $loaded = Read-P6_6Checkpoint -Path $checkpointPath
    Assert-P6_6CheckpointConfig `
        -Checkpoint $loaded `
        -Model "smoke-model" `
        -Provider "codex-chatgpt" `
        -CodexPackage "codex-smoke" `
        -AgentPolicy "p6.5" `
        -Repeats 2
    $resumed = Get-P6_6CheckpointRun `
        -Checkpoint $loaded `
        -Scenario $scenario `
        -Mode "aos" `
        -Repeat 1 `
        -RepositoryCommit ([string]$scenario.expected_commit)
    if ($null -eq $resumed -or [int]$resumed.input_tokens -ne 10) {
        throw "AOS_P6_6_RESUME_SMOKE_FAILED: valid run was not resumed"
    }

    [System.IO.File]::WriteAllText($eventPath, "tampered", $utf8NoBom)
    Expect-Failure -Label "artifact tamper" -Action {
        Get-P6_6CheckpointRun `
            -Checkpoint $loaded `
            -Scenario $scenario `
            -Mode "aos" `
            -Repeat 1 `
            -RepositoryCommit ([string]$scenario.expected_commit) | Out-Null
    }
    [System.IO.File]::WriteAllText($eventPath, '{"type":"turn.completed"}', $utf8NoBom)

    Add-P6_6CheckpointRun `
        -Checkpoint $loaded `
        -Run $resumed `
        -Scenario $scenario `
        -RepositoryCommit ([string]$scenario.expected_commit) | Out-Null
    $conflict = $resumed | Select-Object *
    $conflict.input_tokens = 11
    Expect-Failure -Label "conflicting duplicate" -Action {
        Add-P6_6CheckpointRun `
            -Checkpoint $loaded `
            -Run $conflict `
            -Scenario $scenario `
            -RepositoryCommit ([string]$scenario.expected_commit) | Out-Null
    }

    Write-Output "Resume validated: 1/1"
    Write-Output "Tamper denial: PASS"
    Write-Output "Conflicting duplicate denial: PASS"
    Write-Output "AOS_P6_6_RESUMABLE_RUNNER_OK"
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
