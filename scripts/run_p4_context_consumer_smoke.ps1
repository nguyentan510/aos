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
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p4-context-consumer-smoke"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_CONTEXT_CONSUMER_SMOKE_FAILED: $Message"
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-Aos([string[]]$Arguments) {
    $output = & $AosBinary @Arguments 2>&1
    [pscustomobject]@{
        Output = ($output -join [Environment]::NewLine)
        ExitCode = $LASTEXITCODE
    }
}

function Write-Fixture([string]$Root, [string]$Kind, [string]$Id, [string]$Subject, [string]$Source, [string]$Authority, [string]$Lifecycle, [string]$Freshness, [string]$Value) {
    $directory = if ($Kind -eq "Knowledge") { "knowledge" } else { "state" }
    New-Item -ItemType Directory -Path (Join-Path $Root ".aos\$directory") -Force | Out-Null
    $path = Join-Path $Root ".aos\$directory\$Id.r1.json"
    $document = [ordered]@{
        kind = $Kind
        id = $Id
        project_id = "project-consumer-smoke"
        contract_version = "AOS-SPEC-001"
        revision = "1"
        previous_revision = $null
        owner = "consumer-smoke"
        producer = "consumer-smoke"
        created_at_unix = "1700000000"
        last_produced_at_unix = "1700000000"
        authority = $Authority
        lifecycle = $Lifecycle
        subject = $Subject
        source_reference = $Source
        derived = "false"
        authority_basis = "consumer-smoke"
        authority_reference = "consumer-smoke"
    }
    if ($Kind -eq "Knowledge") {
        $document.content = $Value
    } else {
        $document.observed_value = $Value
        $document.observation_instant_unix = "1700000000"
        $document.observer = "consumer-smoke"
        $document.freshness = $Freshness
        $document.freshness_policy = "consumer-smoke"
    }
    Write-Utf8NoBom -Path $path -Content ($document | ConvertTo-Json -Compress)
}

if (-not (Test-Path -LiteralPath $AosBinary -PathType Leaf)) {
    Fail "AOS binary does not exist: $AosBinary; run cargo build --locked first"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "consumer-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$root = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Path $root -Force | Out-Null

$init = Invoke-Aos @("init", $root, "--apply", "--authority", "consumer-smoke", "--format", "json")
if ($init.ExitCode -ne 0) {
    Fail "fixture initialization failed: $($init.Output)"
}

Write-Fixture -Root $root -Kind "Knowledge" -Id "selected-knowledge" -Subject "selected knowledge" -Source "README.md" -Authority "authoritative" -Lifecycle "active" -Freshness "" -Value "This record is eligible for default context."
Write-Fixture -Root $root -Kind "State" -Id "selected-state" -Subject "selected state" -Source "ROADMAP.md" -Authority "authoritative" -Lifecycle "active" -Freshness "confirmed" -Value "This record is eligible for default context."
Write-Fixture -Root $root -Kind "Knowledge" -Id "withheld-proposal" -Subject "withheld proposal" -Source "notes.md" -Authority "proposed" -Lifecycle "active" -Freshness "" -Value "This record must be withheld."
Write-Fixture -Root $root -Kind "State" -Id "withheld-stale" -Subject "withheld stale state" -Source "ci.log" -Authority "authoritative" -Lifecycle "active" -Freshness "stale" -Value "This record must be withheld."

$first = Invoke-Aos @("context", $root, "--limit", "2", "--format", "json")
$second = Invoke-Aos @("context", $root, "--limit", "2", "--format", "json")
if ($first.ExitCode -ne 0 -or $second.ExitCode -ne 0) {
    Fail "context command failed"
}
if ($first.Output -ne $second.Output) {
    Fail "context output is not deterministic across repeated runs"
}

try {
    $envelope = $first.Output | ConvertFrom-Json
} catch {
    Fail "context output is not valid JSON"
}
if ($envelope.outcome -ne "success") {
    Fail "context outcome is not success"
}
if ($envelope.data.policy -ne "authoritative-active-knowledge-and-confirmed-state") {
    Fail "unexpected context policy"
}
if (@($envelope.data.selected).Count -ne 2) {
    Fail "expected exactly two selected records under the limit"
}
if (@($envelope.data.withheld).Count -ne 2) {
    Fail "expected proposed and stale records to be withheld"
}
if (@($envelope.data.selected | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.source_reference) }).Count -ne 0) {
    Fail "selected records must retain source references"
}
if (@($envelope.data.withheld | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.reason) }).Count -ne 0) {
    Fail "withheld records must include reasons"
}
if ($first.Output -match "(?i)(api[_-]?key|password|secret|token)=") {
    Fail "context output contains secret-like content"
}

$result = [ordered]@{
    schema_version = "AOS-P4-CONTEXT-CONSUMER-SMOKE-1"
    run_id = $runId
    selected_count = @($envelope.data.selected).Count
    withheld_count = @($envelope.data.withheld).Count
    selected_source_references = @($envelope.data.selected | ForEach-Object { $_.source_reference })
    withheld_reasons = @($envelope.data.withheld | ForEach-Object { $_.reason })
    deterministic = $true
    secret_scan = "pass"
    provider = "provider-neutral-json-consumer"
    ai_task_execution = "pending-external-agent-run"
}
$resultPath = Join-Path $root "consumer-smoke-result.json"
Write-Utf8NoBom -Path $resultPath -Content ($result | ConvertTo-Json -Depth 5)

Write-Output "Context consumer smoke: $runId"
Write-Output "Result: $resultPath"
Write-Output "AOS_CONTEXT_CONSUMER_SMOKE_OK"
