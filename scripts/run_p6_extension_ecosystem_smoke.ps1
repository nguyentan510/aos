[CmdletBinding()]
param(
    [string]$AosBinary,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($AosBinary)) {
    $windowsBinary = Join-Path $repositoryRoot "target\debug\aos.exe"
    $unixBinary = Join-Path $repositoryRoot "target/debug/aos"
    $AosBinary = if (Test-Path -LiteralPath $windowsBinary -PathType Leaf) {
        $windowsBinary
    } else {
        $unixBinary
    }
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-extension-smoke"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_P6_EXTENSION_ECOSYSTEM_FAILED: $Message"
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
        Fail "$Label did not return valid JSON: $($Result.Output)"
    }
}

function Enable-Extension([string]$Root, [string]$Manifest) {
    $result = Invoke-Aos @(
        "extension", "enable", $Root, "--apply",
        "--authority=project-reviewer", "--evidence=p6-extension-review",
        "--manifest=$Manifest", "--format=json"
    )
    Require-Success "enable $Manifest" $result
}

function Run-ExtensionWork(
    [string]$Root,
    [string]$WorkId,
    [string]$Extension,
    [string]$Capability
) {
    $create = Invoke-Aos @(
        "work", "create", $Root, "--apply", "--authority=smoke-producer",
        "--work-id=$WorkId", "--context-id=p6-context", "--context-kind=Knowledge",
        "--intent=run-governed-extension", "--expected-output=proposed-extension-evidence",
        "--verification=manifest-digest-capability-and-scope",
        "--protocol=aos.extension.readonly@1.0.0",
        "--extension=$Extension", "--capability=$Capability", "--format=json"
    )
    Require-Success "create $WorkId" $create
    $authorize = Invoke-Aos @(
        "work", "authorize", $Root, "--apply", "--authority=project-reviewer",
        "--work-id=$WorkId", "--evidence=p6-work-review", "--format=json"
    )
    Require-Success "authorize $WorkId" $authorize
    $run = Invoke-Aos @(
        "work", "run", $Root, "--apply", "--authority=local-runtime",
        "--work-id=$WorkId", "--format=json"
    )
    Require-Success "run $WorkId" $run
    $envelope = Parse-Envelope "run $WorkId" $run
    if ($envelope.data.status -ne "completed") {
        Fail "$WorkId did not complete"
    }
}

if (-not (Test-Path -LiteralPath $AosBinary -PathType Leaf)) {
    Fail "AOS binary does not exist: $AosBinary; run cargo build --locked first"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "p6-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$root = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Path $root -Force | Out-Null
[System.IO.File]::WriteAllText(
    (Join-Path $root "Cargo.toml"),
    "[package]`nname = `"p6-smoke`"`nversion = `"0.1.0`"`nedition = `"2024`"`nrust-version = `"1.85`"`n",
    $utf8NoBom
)

$manifestRoot = Join-Path $root "extension-manifests"
New-Item -ItemType Directory -Path $manifestRoot -Force | Out-Null
$genericManifest = Join-Path $manifestRoot "repository-extension.json"
$rustManifest = Join-Path $manifestRoot "rust-extension.json"
Copy-Item -LiteralPath (
    Join-Path $repositoryRoot "extensions\reference\aos.reference.repository\extension.json"
) -Destination $genericManifest
Copy-Item -LiteralPath (
    Join-Path $repositoryRoot "extensions\reference\aos.reference.rust\extension.json"
) -Destination $rustManifest

$init = Invoke-Aos @("init", $root, "--apply", "--authority=smoke-bootstrap", "--format=json")
Require-Success "init" $init
$knowledge = Invoke-Aos @(
    "knowledge", $root, "--record", "--apply", "--authority=smoke-producer",
    "--id=p6-context", "--subject=p6-extension-contract",
    "--content=governed-declarative-local-extension",
    "--source=extension-manifests/repository-extension.json", "--format=json"
)
Require-Success "knowledge proposal" $knowledge

foreach ($manifest in @($genericManifest, $rustManifest)) {
    foreach ($action in @("discover", "validate")) {
        $readOnly = Invoke-Aos @(
            "extension", $action, $root, "--manifest=$manifest", "--format=json"
        )
        Require-Success "$action $manifest" $readOnly
    }
}
if (Test-Path -LiteralPath (Join-Path $root ".aos\extensions") -PathType Container) {
    Fail "read-only discovery or validation mutated extension state"
}

$plan = Invoke-Aos @(
    "extension", "enable", $root, "--manifest=$genericManifest", "--format=json"
)
Require-Success "enable plan" $plan
if ((Parse-Envelope "enable plan" $plan).outcome -ne "plan_ready") {
    Fail "enable without --apply did not return a plan"
}
if (Test-Path -LiteralPath (Join-Path $root ".aos\extensions") -PathType Container) {
    Fail "enable plan mutated extension state"
}

$selfAuthority = Invoke-Aos @(
    "extension", "enable", $root, "--apply", "--authority=aos-cli",
    "--evidence=self-claim", "--manifest=$genericManifest", "--format=json"
)
if ($selfAuthority.ExitCode -ne 7 -or
    $selfAuthority.Output -notmatch "AOS-GOVERNANCE-SELF-AUTHORITY-DENIED") {
    Fail "self-authority was not denied"
}

$directInvoke = Invoke-Aos @("extension", "invoke", $root, "--format=json")
if ($directInvoke.ExitCode -ne 2) {
    Fail "direct extension invocation unexpectedly exists"
}

Enable-Extension $root $genericManifest
Enable-Extension $root $rustManifest
$lifecycleBeforeInspect = @(
    Get-ChildItem (Join-Path $root ".aos\extensions\lifecycle") -File
).Count
foreach ($extensionId in @("aos.reference.repository", "aos.reference.rust")) {
    $inspect = Invoke-Aos @(
        "extension", "inspect", $root, "--extension-id=$extensionId", "--format=json"
    )
    Require-Success "inspect $extensionId" $inspect
}
$lifecycleAfterInspect = @(
    Get-ChildItem (Join-Path $root ".aos\extensions\lifecycle") -File
).Count
if ($lifecycleBeforeInspect -ne $lifecycleAfterInspect) {
    Fail "extension inspect mutated lifecycle state"
}

Run-ExtensionWork $root "generic-summary" `
    "aos.reference.repository@1.0.0" "aos.reference.repository.summary"
Run-ExtensionWork $root "rust-summary" `
    "aos.reference.rust@1.0.0" "aos.reference.rust.cargo_manifest.summary"

$genericResultPath = Join-Path $root ".aos\extensions\results\generic-summary.r1.json"
$rustResultPath = Join-Path $root ".aos\extensions\results\rust-summary.r1.json"
$genericResult = Get-Content -LiteralPath $genericResultPath -Raw | ConvertFrom-Json
$rustResult = Get-Content -LiteralPath $rustResultPath -Raw | ConvertFrom-Json
if ($genericResult.authority -ne "proposed" -or
    $genericResult.host_operation -ne "repository.summary@1.0.0") {
    Fail "generic extension result lost proposed authority or host operation"
}
if ($rustResult.authority -ne "proposed" -or
    $rustResult.proposed_output.package_name -ne "p6-smoke") {
    Fail "Rust extension result did not parse the repository-root Cargo.toml"
}
foreach ($result in @($genericResult, $rustResult)) {
    foreach ($field in @(
        "extension_reference", "manifest_digest", "capability_reference",
        "work_reference", "run_reference", "protocol_reference",
        "input_digest", "verification_evidence"
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$result.$field)) {
            Fail "extension result is missing $field"
        }
    }
}

$disable = Invoke-Aos @(
    "extension", "disable", $root, "--apply", "--authority=project-reviewer",
    "--evidence=p6-disable-review", "--extension-id=aos.reference.rust", "--format=json"
)
Require-Success "disable Rust extension" $disable
$disabledWork = Invoke-Aos @(
    "work", "create", $root, "--apply", "--authority=smoke-producer",
    "--work-id=disabled-rust", "--context-id=p6-context", "--context-kind=Knowledge",
    "--intent=deny-disabled-extension", "--protocol=aos.extension.readonly@1.0.0",
    "--extension=aos.reference.rust@1.0.0",
    "--capability=aos.reference.rust.cargo_manifest.summary", "--format=json"
)
if ($disabledWork.ExitCode -ne 7 -or $disabledWork.Output -notmatch "AOS-EXTENSION-NOT-ENABLED") {
    Fail "disabled extension accepted new Work"
}

$tamperCreate = Invoke-Aos @(
    "work", "create", $root, "--apply", "--authority=smoke-producer",
    "--work-id=tamper-check", "--context-id=p6-context", "--context-kind=Knowledge",
    "--intent=detect-manifest-tamper", "--protocol=aos.extension.readonly@1.0.0",
    "--extension=aos.reference.repository@1.0.0",
    "--capability=aos.reference.repository.summary", "--format=json"
)
Require-Success "tamper Work create" $tamperCreate
$tamperAuthorize = Invoke-Aos @(
    "work", "authorize", $root, "--apply", "--authority=project-reviewer",
    "--work-id=tamper-check", "--evidence=p6-tamper-review", "--format=json"
)
Require-Success "tamper Work authorize" $tamperAuthorize
$snapshot = Join-Path $root ".aos\extensions\manifests\aos.reference.repository@1.0.0.json"
$snapshotContent = [System.IO.File]::ReadAllText($snapshot)
[System.IO.File]::WriteAllText(
    $snapshot,
    $snapshotContent.Replace('"owner":"AOS project"', '"owner":"tampered"'),
    $utf8NoBom
)
$tamperRun = Invoke-Aos @(
    "work", "run", $root, "--apply", "--authority=local-runtime",
    "--work-id=tamper-check", "--format=json"
)
if ($tamperRun.ExitCode -ne 4) {
    Fail "digest tampering did not return validation findings"
}
$tamperEnvelope = Parse-Envelope "tamper Run" $tamperRun
if ($tamperEnvelope.data.status -ne "blocked" -or
    $tamperEnvelope.operation.reconciliation -ne "required") {
    Fail "digest tampering did not block Work with reconciliation"
}
$lifecycleBodies = Get-ChildItem (
    Join-Path $root ".aos\extensions\lifecycle"
) -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
if (($lifecycleBodies -join [Environment]::NewLine) -notmatch '"status":"quarantined"') {
    Fail "digest tampering did not quarantine the extension"
}

$result = [ordered]@{
    schema_version = "AOS-P6-EXTENSION-SMOKE-1"
    run_id = $runId
    repository = $root
    reference_extensions = @(
        "aos.reference.repository@1.0.0",
        "aos.reference.rust@1.0.0"
    )
    execution_model = "declarative-local-read-only"
    direct_invocation = "not_exposed"
    self_authority_denied = $true
    exact_scope = $true
    proposed_results = $true
    integrity_failure = "quarantined-and-blocked"
    arbitrary_process = "not_supported"
    network = "not_supported"
}
$resultPath = Join-Path $root "p6-smoke-result.json"
[System.IO.File]::WriteAllText(
    $resultPath,
    ($result | ConvertTo-Json -Depth 6),
    $utf8NoBom
)

Write-Output "P6 extension ecosystem smoke: $runId"
Write-Output "Result: $resultPath"
Write-Output "AOS_P6_EXTENSION_CONTRACT_OK"
Write-Output "AOS_P6_EXTENSION_LIFECYCLE_OK"
Write-Output "AOS_P6_EXTENSION_ISOLATION_OK"
Write-Output "AOS_P6_REFERENCE_EXTENSION_SMOKE_OK"
Write-Output "AOS_P6_EXTENSION_ECOSYSTEM_OK"
$global:LASTEXITCODE = 0
