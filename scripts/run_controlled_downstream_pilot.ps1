[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DownstreamSnapshot,
    [string]$ExpectedCommit = "3297389bd35ff3e8eb129dc74308ec3c8d165bf2",
    [string]$BenchmarkEvidenceRef = "p4-ai-20260727T062521Z",
    [string]$AosBinary,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($AosBinary)) {
    $AosBinary = Join-Path $scriptRoot "..\target\debug\aos.exe"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-controlled-downstream-pilot"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_CONTROLLED_DOWNSTREAM_PILOT_FAILED: $Message"
}

function Invoke-Native(
    [string]$File,
    [string[]]$Arguments,
    [string]$WorkingDirectory
) {
    $originalLocation = Get-Location
    $originalErrorAction = $ErrorActionPreference
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $ErrorActionPreference = "Continue"
        $output = & $File @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $originalErrorAction
        Set-Location -LiteralPath $originalLocation
    }
    [pscustomobject]@{
        Output = ($output -join [Environment]::NewLine)
        ExitCode = $exitCode
    }
}

function Invoke-Aos([string[]]$Arguments) {
    Invoke-Native -File $AosBinary -Arguments $Arguments -WorkingDirectory $scriptRoot
}

function Require-Success([string]$Label, [object]$Result) {
    if ($Result.ExitCode -ne 0) {
        Fail "$Label failed: $($Result.Output)"
    }
}

function Parse-Envelope([string]$Label, [object]$Result) {
    try {
        return $Result.Output | ConvertFrom-Json
    } catch {
        Fail "$Label did not return valid JSON"
    }
}

if (-not (Test-Path -LiteralPath $AosBinary -PathType Leaf)) {
    Fail "AOS binary does not exist: $AosBinary"
}
if (-not (Test-Path -LiteralPath $DownstreamSnapshot -PathType Container)) {
    Fail "downstream snapshot does not exist: $DownstreamSnapshot"
}
if (Test-Path -LiteralPath (Join-Path $DownstreamSnapshot ".aos")) {
    Fail "downstream snapshot already has an .aos control root"
}

$commit = Invoke-Native -File "git" -Arguments @(
    "-C", $DownstreamSnapshot, "rev-parse", "HEAD"
) -WorkingDirectory $scriptRoot
Require-Success "snapshot commit inspection" $commit
if ($commit.Output.Trim() -ne $ExpectedCommit) {
    Fail "snapshot commit mismatch: expected $ExpectedCommit, got $($commit.Output.Trim())"
}

$status = Invoke-Native -File "git" -Arguments @(
    "-C", $DownstreamSnapshot, "status", "--porcelain"
) -WorkingDirectory $scriptRoot
Require-Success "snapshot status inspection" $status
$changedFiles = @(
    $status.Output -split "`r?`n" |
        Where-Object { $_.Length -ge 4 } |
        ForEach-Object { $_.Substring(3).Trim().Trim('"') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($changedFiles.Count -ne 1 -or $changedFiles[0] -ne "docs/TRACEABILITY_MATRIX.md") {
    Fail "pilot requires the isolated benchmark patch to docs/TRACEABILITY_MATRIX.md"
}

$patchVerification = Invoke-Native -File "git" -Arguments @(
    "-C", $DownstreamSnapshot, "diff", "--check"
) -WorkingDirectory $scriptRoot
Require-Success "patch verification" $patchVerification

$init = Invoke-Aos @(
    "init", $DownstreamSnapshot, "--apply",
    "--authority=controlled-pilot-bootstrap", "--format=json"
)
Require-Success "pilot init" $init

$knowledge = Invoke-Aos @(
    "knowledge", $DownstreamSnapshot, "--record", "--apply",
    "--authority=controlled-pilot-producer",
    "--id=downstream-consumer-traceability",
    "--subject=downstream-consumer-traceability",
    "--content=Upstream contract, implementation owner, verification evidence, and readiness status are required before promotion.",
    "--source=docs/TRACEABILITY_MATRIX.md",
    "--format=json"
)
Require-Success "pilot knowledge proposal" $knowledge

$work = Invoke-Aos @(
    "work", "create", $DownstreamSnapshot, "--apply",
    "--authority=controlled-pilot-producer",
    "--work-id=verify-downstream-consumer-traceability",
    "--context-id=downstream-consumer-traceability",
    "--context-kind=Knowledge",
    "--intent=verify-controlled-downstream-patch",
    "--expected-output=verified-traceability-patch",
    "--verification=git-diff-check",
    "--format=json"
)
Require-Success "pilot work create" $work

$authorize = Invoke-Aos @(
    "work", "authorize", $DownstreamSnapshot, "--apply",
    "--authority=controlled-pilot-reviewer",
    "--work-id=verify-downstream-consumer-traceability",
    "--evidence=$BenchmarkEvidenceRef",
    "--format=json"
)
Require-Success "pilot work authorize" $authorize

$context = Invoke-Aos @(
    "context", $DownstreamSnapshot, "--profile=compact",
    "--budget-bytes=900", "--format=json"
)
Require-Success "pilot context query" $context
$contextEnvelope = Parse-Envelope "pilot context query" $context
if (@(
    $contextEnvelope.data.selected |
        Where-Object { $_.id -eq "downstream-consumer-traceability" }
).Count -ne 1) {
    Fail "authorized pilot context was not selected"
}

$run = Invoke-Aos @(
    "work", "run", $DownstreamSnapshot, "--apply",
    "--authority=controlled-pilot-runtime",
    "--work-id=verify-downstream-consumer-traceability",
    "--evidence=verification:git-diff-check-pass",
    "--format=json"
)
Require-Success "pilot governed run" $run
$runEnvelope = Parse-Envelope "pilot governed run" $run
if ($runEnvelope.data.status -ne "completed") {
    Fail "pilot Work did not complete"
}

$show = Invoke-Aos @(
    "work", "show", $DownstreamSnapshot,
    "--work-id=verify-downstream-consumer-traceability",
    "--format=json"
)
Require-Success "pilot audit trace" $show
$showEnvelope = Parse-Envelope "pilot audit trace" $show
if (@($showEnvelope.data.governance).Count -lt 1 -or
    @($showEnvelope.data.runs).Count -lt 1 -or
    @($showEnvelope.data.audit).Count -lt 3) {
    Fail "pilot Governance/Run/Audit trace is incomplete"
}

$runId = "pilot-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$pilotRoot = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Path $pilotRoot -Force | Out-Null
$result = [ordered]@{
    schema_version = "AOS-CONTROLLED-DOWNSTREAM-PILOT-1"
    run_id = $runId
    downstream_snapshot = $DownstreamSnapshot
    repository_commit = $commit.Output.Trim()
    benchmark_evidence = $BenchmarkEvidenceRef
    changed_files = $changedFiles
    patch_verification = "git diff --check: PASS"
    selected_context = "downstream-consumer-traceability"
    work_id = "verify-downstream-consumer-traceability"
    work_status = "completed"
    governance_records = @($showEnvelope.data.governance).Count
    protocol_runs = @($showEnvelope.data.runs).Count
    audit_records = @($showEnvelope.data.audit).Count
    arbitrary_command_execution = "not_supported"
    external_mutation = "none"
    source_repository_mutation = "none"
}
$resultPath = Join-Path $pilotRoot "controlled-pilot-result.json"
[System.IO.File]::WriteAllText(
    $resultPath,
    ($result | ConvertTo-Json -Depth 6),
    $utf8NoBom
)

Write-Output "Controlled downstream pilot: $runId"
Write-Output "Result: $resultPath"
Write-Output "AOS_CONTROLLED_DOWNSTREAM_PILOT_OK"
