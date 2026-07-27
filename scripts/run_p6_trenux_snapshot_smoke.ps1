[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryPath,
    [string]$AosBinary,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$aosRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($AosBinary)) {
    $AosBinary = Join-Path $aosRoot "target\debug\aos.exe"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-trenux-smoke"
}

function Fail([string]$Message) {
    throw "AOS_P6_TRENUX_SNAPSHOT_SMOKE_FAILED: $Message"
}

function Invoke-Aos([string[]]$Arguments) {
    $output = & $AosBinary @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail ($output -join [Environment]::NewLine)
    }
    return ($output -join [Environment]::NewLine) | ConvertFrom-Json
}

$sourceRoot = (Resolve-Path -LiteralPath $RepositoryPath).Path
$sourceCargo = Join-Path $sourceRoot "Cargo.toml"
if (-not (Test-Path -LiteralPath $sourceCargo -PathType Leaf)) {
    Fail "TRENUX snapshot source has no repository-root Cargo.toml"
}
if (-not (Test-Path -LiteralPath $AosBinary -PathType Leaf)) {
    Fail "AOS binary does not exist: $AosBinary"
}

$sourceStatusBefore = git -C $sourceRoot status --porcelain=v1
if ($LASTEXITCODE -ne 0) {
    Fail "TRENUX source must be a Git repository"
}
$commitSha = (git -C $sourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commitSha)) {
    Fail "could not resolve the TRENUX source commit"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "trenux-" + $commitSha.Substring(0, 12) + "-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$snapshotRoot = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceCargo -Destination (Join-Path $snapshotRoot "Cargo.toml")
$manifest = Join-Path $snapshotRoot "aos.reference.rust.extension.json"
Copy-Item -LiteralPath (
    Join-Path $aosRoot "extensions\reference\aos.reference.rust\extension.json"
) -Destination $manifest
$snapshotEvidence = [ordered]@{
    source_repository = $sourceRoot
    source_commit = $commitSha
    copied_resources = @("Cargo.toml")
    source_mutation = "forbidden"
}
$snapshotEvidence | ConvertTo-Json -Depth 4 | Set-Content (
    Join-Path $snapshotRoot "SOURCE-SNAPSHOT.json"
) -Encoding utf8

Invoke-Aos @("init", $snapshotRoot, "--apply", "--authority=pilot-bootstrap", "--format=json") | Out-Null
Invoke-Aos @(
    "knowledge", $snapshotRoot, "--record", "--apply", "--authority=pilot-producer",
    "--id=trenux-snapshot", "--subject=trenux-cargo-manifest",
    "--content=fixed-repository-manifest-snapshot",
    "--source=SOURCE-SNAPSHOT.json", "--format=json"
) | Out-Null
Invoke-Aos @(
    "extension", "enable", $snapshotRoot, "--apply", "--authority=project-reviewer",
    "--evidence=trenux-snapshot-review", "--manifest=$manifest", "--format=json"
) | Out-Null
Invoke-Aos @(
    "work", "create", $snapshotRoot, "--apply", "--authority=pilot-producer",
    "--work-id=trenux-rust-summary", "--context-id=trenux-snapshot",
    "--context-kind=Knowledge", "--intent=summarize-trenux-cargo-manifest",
    "--protocol=aos.extension.readonly@1.0.0",
    "--extension=aos.reference.rust@1.0.0",
    "--capability=aos.reference.rust.cargo_manifest.summary", "--format=json"
) | Out-Null
Invoke-Aos @(
    "work", "authorize", $snapshotRoot, "--apply", "--authority=project-reviewer",
    "--work-id=trenux-rust-summary", "--evidence=trenux-pilot-review", "--format=json"
) | Out-Null
$run = Invoke-Aos @(
    "work", "run", $snapshotRoot, "--apply", "--authority=local-runtime",
    "--work-id=trenux-rust-summary", "--format=json"
)
if ($run.data.status -ne "completed") {
    Fail "TRENUX fixed snapshot Work did not complete"
}
$extensionResult = Get-Content (
    Join-Path $snapshotRoot ".aos\extensions\results\trenux-rust-summary.r1.json"
) -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$extensionResult.proposed_output.package_name) -and
    [int]$extensionResult.proposed_output.workspace_member_count -lt 1) {
    Fail "TRENUX Cargo summary exposed neither a package name nor workspace member names"
}

$sourceStatusAfter = git -C $sourceRoot status --porcelain=v1
if (($sourceStatusBefore -join "`n") -ne ($sourceStatusAfter -join "`n")) {
    Fail "TRENUX source worktree changed during snapshot smoke"
}

$evidence = [ordered]@{
    schema_version = "AOS-P6-TRENUX-SNAPSHOT-SMOKE-1"
    source_repository = $sourceRoot
    source_commit = $commitSha
    snapshot_repository = $snapshotRoot
    extension = "aos.reference.rust@1.0.0"
    capability = "aos.reference.rust.cargo_manifest.summary"
    result = $extensionResult.proposed_output
    source_mutated = $false
}
$evidencePath = Join-Path $snapshotRoot "p6-trenux-snapshot-result.json"
$evidence | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding utf8

Write-Output "TRENUX source commit: $commitSha"
Write-Output "Result: $evidencePath"
Write-Output "AOS_P6_TRENUX_SNAPSHOT_SMOKE_OK"
