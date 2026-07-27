[CmdletBinding()]
param(
    [string]$AosBinary,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($AosBinary)) {
    $AosBinary = Join-Path $scriptRoot "..\target\debug\aos.exe"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p5-governed-work-smoke"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_P5_GOVERNED_WORK_SMOKE_FAILED: $Message"
}

function Invoke-Aos([string[]]$Arguments) {
    $output = & $AosBinary @Arguments 2>&1
    [pscustomobject]@{
        Output = ($output -join [Environment]::NewLine)
        ExitCode = $LASTEXITCODE
    }
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
    Fail "AOS binary does not exist: $AosBinary; run cargo build --locked first"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "p5-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$root = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Path $root -Force | Out-Null

$init = Invoke-Aos @("init", $root, "--apply", "--authority=smoke-bootstrap", "--format=json")
Require-Success "init" $init

$knowledge = Invoke-Aos @(
    "knowledge", $root, "--record", "--apply", "--authority=smoke-producer",
    "--id=architecture", "--subject=architecture", "--content=modular-local-context",
    "--source=DESIGN.md", "--format=json"
)
Require-Success "knowledge proposal" $knowledge

$create = Invoke-Aos @(
    "work", "create", $root, "--apply", "--authority=smoke-producer",
    "--work-id=verify-architecture", "--context-id=architecture",
    "--context-kind=Knowledge", "--intent=verify-governed-context",
    "--expected-output=verified-result", "--verification=local-context-integrity",
    "--format=json"
)
Require-Success "work create" $create

$selfAuthority = Invoke-Aos @(
    "work", "authorize", $root, "--apply", "--authority=aos-cli",
    "--work-id=verify-architecture", "--evidence=self-claim", "--format=json"
)
if ($selfAuthority.ExitCode -ne 7 -or $selfAuthority.Output -notmatch "AOS-GOVERNANCE-SELF-AUTHORITY-DENIED") {
    Fail "self-authority was not denied"
}

$authorize = Invoke-Aos @(
    "work", "authorize", $root, "--apply", "--authority=project-reviewer",
    "--work-id=verify-architecture", "--evidence=review-evidence", "--format=json"
)
Require-Success "work authorize" $authorize
$authorizationEnvelope = Parse-Envelope "work authorize" $authorize
if ($authorizationEnvelope.data.status -ne "authorized") {
    Fail "authorized Work status was not recorded"
}

$context = Invoke-Aos @("context", $root, "--profile=compact", "--format=json")
Require-Success "promoted context query" $context
$contextEnvelope = Parse-Envelope "promoted context query" $context
if (@($contextEnvelope.data.selected | Where-Object { $_.id -eq "architecture" }).Count -ne 1) {
    Fail "Governance promotion did not make the approved context eligible"
}

$run = Invoke-Aos @(
    "work", "run", $root, "--apply", "--authority=local-runtime",
    "--work-id=verify-architecture", "--evidence=verification-evidence", "--format=json"
)
Require-Success "successful Protocol Run" $run
$runEnvelope = Parse-Envelope "successful Protocol Run" $run
if ($runEnvelope.data.status -ne "completed" -or $runEnvelope.operation.result -ne "completed") {
    Fail "successful Protocol Run did not complete Work"
}

$createUnknown = Invoke-Aos @(
    "work", "create", $root, "--apply", "--authority=smoke-producer",
    "--work-id=reconcile-work", "--context-id=architecture",
    "--context-kind=Knowledge", "--intent=verify-reconciliation",
    "--expected-output=verified-result", "--verification=local-context-integrity",
    "--format=json"
)
Require-Success "reconciliation Work create" $createUnknown
$authorizeUnknown = Invoke-Aos @(
    "work", "authorize", $root, "--apply", "--authority=project-reviewer",
    "--work-id=reconcile-work", "--evidence=review-evidence", "--format=json"
)
Require-Success "reconciliation Work authorize" $authorizeUnknown
$unknown = Invoke-Aos @(
    "work", "run", $root, "--apply", "--authority=local-runtime",
    "--work-id=reconcile-work", "--result=unknown",
    "--reason=verification-interrupted", "--format=json"
)
if ($unknown.ExitCode -ne 4) {
    Fail "unknown Protocol Run must report non-success findings: $($unknown.Output)"
}
$unknownEnvelope = Parse-Envelope "unknown Protocol Run" $unknown
if ($unknownEnvelope.data.status -ne "blocked" -or $unknownEnvelope.operation.reconciliation -ne "required") {
    Fail "unknown Protocol Run did not block Work"
}

$duplicate = Invoke-Aos @(
    "work", "run", $root, "--apply", "--authority=local-runtime",
    "--work-id=reconcile-work", "--format=json"
)
if ($duplicate.ExitCode -ne 4 -or $duplicate.Output -notmatch "AOS-WORK-TRANSITION-INVALID") {
    Fail "duplicate Run was not blocked before reconciliation"
}

$reconcile = Invoke-Aos @(
    "work", "reconcile", $root, "--apply", "--authority=project-reviewer",
    "--work-id=reconcile-work", "--result=resolved",
    "--evidence=current-observation", "--format=json"
)
Require-Success "reconciliation" $reconcile
$reconcileEnvelope = Parse-Envelope "reconciliation" $reconcile
if ($reconcileEnvelope.data.status -ne "authorized") {
    Fail "resolved reconciliation did not return Work to authorized"
}

$show = Invoke-Aos @(
    "work", "show", $root, "--work-id=verify-architecture", "--format=json"
)
Require-Success "work show" $show
$showEnvelope = Parse-Envelope "work show" $show
if (@($showEnvelope.data.work).Count -ne 1) {
    Fail "work show did not return current Work"
}
if (@($showEnvelope.data.governance).Count -lt 1 -or
    @($showEnvelope.data.runs).Count -lt 1 -or
    @($showEnvelope.data.audit).Count -lt 3) {
    Fail "work show did not return the complete Governance/Run/Audit trace"
}

$requiredDirectories = @("work", "protocol", "governance", "runs", "audit")
foreach ($directory in $requiredDirectories) {
    if (-not (Test-Path -LiteralPath (Join-Path $root ".aos\$directory") -PathType Container)) {
        Fail "missing P5 namespace: .aos/$directory"
    }
}

$result = [ordered]@{
    schema_version = "AOS-P5-GOVERNED-WORK-SMOKE-1"
    run_id = $runId
    repository = $root
    protocol = "aos.local.verify@1.0.0"
    self_authority_denied = $true
    authoritative_context_selected = $true
    completed_work = "verify-architecture"
    unknown_work_blocked = "reconcile-work"
    reconciliation = "resolved"
    arbitrary_command_execution = "not_supported"
    external_mutation = "none"
}
$resultPath = Join-Path $root "p5-smoke-result.json"
[System.IO.File]::WriteAllText(
    $resultPath,
    ($result | ConvertTo-Json -Depth 5),
    $utf8NoBom
)

Write-Output "P5 governed Work smoke: $runId"
Write-Output "Result: $resultPath"
Write-Output "AOS_P5_GOVERNED_WORK_CONTRACT_OK"
Write-Output "AOS_P5_GOVERNED_WORK_SMOKE_OK"
Write-Output "AOS_P5_GOVERNANCE_RECONCILIATION_OK"
