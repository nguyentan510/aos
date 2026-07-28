$script:P6_6CheckpointSchema = "AOS-P6-6-RESUME-CHECKPOINT-1"
$script:P6_6Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:P6_6ArtifactDigestProperties = @(
    "prompt_sha256",
    "event_sha256",
    "patch_sha256"
)

function Get-P6_6TextSha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString(
            $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
        ).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-P6_6FileSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: artifact does not exist: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-P6_6ScenarioDigest([object]$Scenario) {
    return Get-P6_6TextSha256 -Text (
        $Scenario | ConvertTo-Json -Depth 20 -Compress
    )
}

function Get-P6_6CheckpointKey(
    [string]$ScenarioId,
    [string]$Mode,
    [int]$Repeat
) {
    return "$ScenarioId|$Mode|$Repeat"
}

function New-P6_6Checkpoint(
    [string]$Model,
    [string]$Provider,
    [string]$CodexPackage,
    [string]$AgentPolicy,
    [int]$Repeats
) {
    return [ordered]@{
        schema_version = $script:P6_6CheckpointSchema
        created_at_utc = [DateTime]::UtcNow.ToString("o")
        updated_at_utc = [DateTime]::UtcNow.ToString("o")
        config = [ordered]@{
            model = $Model
            provider = $Provider
            codex_package = $CodexPackage
            agent_policy = $AgentPolicy
            repeats = $Repeats
        }
        runs = @()
    }
}

function Assert-P6_6CheckpointConfig(
    [object]$Checkpoint,
    [string]$Model,
    [string]$Provider,
    [string]$CodexPackage,
    [string]$AgentPolicy,
    [int]$Repeats
) {
    if ([string]$Checkpoint.schema_version -ne $script:P6_6CheckpointSchema) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: unsupported checkpoint schema"
    }
    $expected = @(
        @("model", $Model),
        @("provider", $Provider),
        @("codex_package", $CodexPackage),
        @("agent_policy", $AgentPolicy),
        @("repeats", [string]$Repeats)
    )
    foreach ($pair in $expected) {
        if ([string]$Checkpoint.config.($pair[0]) -ne [string]$pair[1]) {
            throw "AOS_P6_6_CHECKPOINT_FAILED: checkpoint config mismatch: $($pair[0])"
        }
    }
}

function Read-P6_6Checkpoint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: checkpoint does not exist: $Path"
    }
    try {
        $checkpoint = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "AOS_P6_6_CHECKPOINT_FAILED: invalid checkpoint JSON: $Path"
    }
    if ([string]$checkpoint.schema_version -ne $script:P6_6CheckpointSchema) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: unsupported checkpoint schema"
    }
    return $checkpoint
}

function Write-P6_6Checkpoint([string]$Path, [object]$Checkpoint) {
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Checkpoint.updated_at_utc = [DateTime]::UtcNow.ToString("o")
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText(
            $temporary,
            ($Checkpoint | ConvertTo-Json -Depth 20),
            $script:P6_6Utf8NoBom
        )
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [System.IO.File]::Replace($temporary, $Path, $null, $true)
        } else {
            [System.IO.File]::Move($temporary, $Path)
        }
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Assert-P6_6RunArtifacts([object]$Run) {
    foreach ($property in $script:P6_6ArtifactDigestProperties) {
        if ([string]::IsNullOrWhiteSpace([string]$Run.$property)) {
            throw "AOS_P6_6_CHECKPOINT_FAILED: missing artifact digest: $property"
        }
    }
    foreach ($name in @("prompt", "event", "patch")) {
        $pathProperty = "${name}_path"
        $hashProperty = "${name}_sha256"
        $actual = Get-P6_6FileSha256 -Path ([string]$Run.$pathProperty)
        if ($actual -ne [string]$Run.$hashProperty) {
            throw "AOS_P6_6_CHECKPOINT_FAILED: $name artifact digest mismatch for $($Run.checkpoint_key)"
        }
    }
}

function Assert-P6_6SuccessfulRun(
    [object]$Run,
    [object]$Scenario,
    [string]$RepositoryCommit
) {
    $key = Get-P6_6CheckpointKey `
        -ScenarioId ([string]$Run.scenario_id) `
        -Mode ([string]$Run.mode) `
        -Repeat ([int]$Run.repeat)
    if ([string]$Run.checkpoint_key -ne $key) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: invalid checkpoint key"
    }
    if ([string]$Run.scenario_digest -ne (Get-P6_6ScenarioDigest -Scenario $Scenario)) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: scenario digest mismatch for $key"
    }
    if ([string]$Run.repository_commit -ne $RepositoryCommit) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: repository commit mismatch for $key"
    }
    if (-not [bool]$Run.task_success -or -not [bool]$Run.verification_passed) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: unsuccessful run cannot be resumed: $key"
    }
    $expected = @($Scenario.expected_patch_files | Sort-Object)
    $actual = @($Run.changed_files | Sort-Object)
    if (($expected -join "`n") -ne ($actual -join "`n")) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: changed-file scope mismatch for $key"
    }
    if ([string]$Run.mode -eq "aos" -and (
        -not [bool]$Run.source_scope_preserved -or [int]$Run.mcp_call_count -ne 0
    )) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: AOS source isolation mismatch for $key"
    }
    Assert-P6_6RunArtifacts -Run $Run
}

function Get-P6_6CheckpointRun(
    [object]$Checkpoint,
    [object]$Scenario,
    [string]$Mode,
    [int]$Repeat,
    [string]$RepositoryCommit
) {
    $key = Get-P6_6CheckpointKey `
        -ScenarioId ([string]$Scenario.id) `
        -Mode $Mode `
        -Repeat $Repeat
    $matches = @($Checkpoint.runs | Where-Object {
        [string]$_.checkpoint_key -eq $key
    })
    if ($matches.Count -gt 1) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: duplicate checkpoint key: $key"
    }
    if ($matches.Count -eq 0) {
        return $null
    }
    Assert-P6_6SuccessfulRun `
        -Run $matches[0] `
        -Scenario $Scenario `
        -RepositoryCommit $RepositoryCommit
    return $matches[0]
}

function Add-P6_6CheckpointRun(
    [object]$Checkpoint,
    [object]$Run,
    [object]$Scenario,
    [string]$RepositoryCommit
) {
    if (-not [bool]$Run.task_success -or -not [bool]$Run.verification_passed) {
        throw "AOS_P6_6_CHECKPOINT_FAILED: only successful verified runs may be checkpointed"
    }
    $stored = $Run | Select-Object *
    $key = Get-P6_6CheckpointKey `
        -ScenarioId ([string]$Run.scenario_id) `
        -Mode ([string]$Run.mode) `
        -Repeat ([int]$Run.repeat)
    $stored | Add-Member -NotePropertyName checkpoint_key -NotePropertyValue $key -Force
    $stored | Add-Member -NotePropertyName scenario_digest `
        -NotePropertyValue (Get-P6_6ScenarioDigest -Scenario $Scenario) -Force
    $stored | Add-Member -NotePropertyName repository_commit `
        -NotePropertyValue $RepositoryCommit -Force
    foreach ($name in @("prompt", "event", "patch")) {
        $pathProperty = "${name}_path"
        $stored | Add-Member -NotePropertyName "${name}_sha256" `
            -NotePropertyValue (Get-P6_6FileSha256 -Path ([string]$stored.$pathProperty)) `
            -Force
    }
    Assert-P6_6SuccessfulRun `
        -Run $stored `
        -Scenario $Scenario `
        -RepositoryCommit $RepositoryCommit

    $existing = @($Checkpoint.runs | Where-Object {
        [string]$_.checkpoint_key -eq $key
    })
    if ($existing.Count -gt 0) {
        $left = $existing[0] | ConvertTo-Json -Depth 20 -Compress
        $right = $stored | ConvertTo-Json -Depth 20 -Compress
        if ($left -ne $right) {
            throw "AOS_P6_6_CHECKPOINT_FAILED: conflicting checkpoint run: $key"
        }
        return $existing[0]
    }
    $Checkpoint.runs = @($Checkpoint.runs) + @($stored)
    return $stored
}
