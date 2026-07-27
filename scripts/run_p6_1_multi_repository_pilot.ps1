[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RepositoryPath,
    [ValidateRange(2, 10)]
    [int]$Repeats = 2,
    [string]$AosBinary,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$aosRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($AosBinary)) {
    $windowsBinary = Join-Path $aosRoot "target\debug\aos.exe"
    $unixBinary = Join-Path $aosRoot "target/debug/aos"
    $AosBinary = if (Test-Path -LiteralPath $windowsBinary -PathType Leaf) {
        $windowsBinary
    } else {
        $unixBinary
    }
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-1-multi-repository-pilot"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw "AOS_P6_1_MULTI_REPOSITORY_PILOT_FAILED: $Message"
}

function Invoke-Aos([string[]]$Arguments) {
    $output = & $AosBinary @Arguments 2>&1
    $result = [pscustomobject]@{
        Output = ($output -join [Environment]::NewLine)
        ExitCode = $LASTEXITCODE
    }
    if ($result.ExitCode -ne 0) {
        Fail $result.Output
    }
    try {
        return $result.Output | ConvertFrom-Json
    } catch {
        Fail "AOS did not return valid JSON: $($result.Output)"
    }
}

function Enable-Extension([string]$Root, [string]$Manifest) {
    Invoke-Aos @(
        "extension", "enable", $Root, "--apply",
        "--authority=pilot-reviewer", "--evidence=p6-1-pilot-review",
        "--manifest=$Manifest", "--format=json"
    ) | Out-Null
}

function Run-Capability(
    [string]$Root,
    [string]$WorkId,
    [string]$Extension,
    [string]$Capability
) {
    Invoke-Aos @(
        "work", "create", $Root, "--apply", "--authority=pilot-producer",
        "--work-id=$WorkId", "--context-id=source-snapshot",
        "--context-kind=Knowledge", "--intent=repeat-extension-pilot",
        "--expected-output=normalized-proposed-evidence",
        "--verification=digest-capability-scope-and-replay",
        "--protocol=aos.extension.readonly@1.0.0",
        "--extension=$Extension", "--capability=$Capability", "--format=json"
    ) | Out-Null
    Invoke-Aos @(
        "work", "authorize", $Root, "--apply", "--authority=pilot-reviewer",
        "--work-id=$WorkId", "--evidence=p6-1-work-review", "--format=json"
    ) | Out-Null
    $run = Invoke-Aos @(
        "work", "run", $Root, "--apply", "--authority=local-runtime",
        "--work-id=$WorkId", "--format=json"
    )
    if ($run.data.status -ne "completed") {
        Fail "$WorkId did not complete"
    }
    $resultPath = Join-Path $Root ".aos\extensions\results\$WorkId.r1.json"
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    return [ordered]@{
        extension_reference = $result.extension_reference
        manifest_digest = $result.manifest_digest
        capability_reference = $result.capability_reference
        host_operation = $result.host_operation
        resource_references = @($result.resource_references)
        input_digest = $result.input_digest
        status = $result.status
        proposed_output = $result.proposed_output
        verification_evidence = $result.verification_evidence
    }
}

if (-not (Test-Path -LiteralPath $AosBinary -PathType Leaf)) {
    Fail "AOS binary does not exist: $AosBinary; run cargo build --locked first"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "p6-1-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$runRoot = Join-Path $OutputDir $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$repositoryResults = @()
$totalRuns = 0

foreach ($candidate in $RepositoryPath) {
    $sourceRoot = (Resolve-Path -LiteralPath $candidate).Path
    $statusBefore = @(git -C $sourceRoot status --porcelain=v1)
    if ($LASTEXITCODE -ne 0) {
        Fail "$sourceRoot is not a readable Git repository"
    }
    $commitSha = (git -C $sourceRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commitSha)) {
        Fail "could not resolve commit SHA for $sourceRoot"
    }
    $sourceName = (Split-Path -Leaf $sourceRoot) -replace '[^A-Za-z0-9._-]', '-'
    $snapshotName = "$sourceName-$($commitSha.Substring(0, 12))"
    $snapshotRoot = Join-Path $runRoot $snapshotName
    New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null

    $copiedResources = @()
    $sourceCargo = Join-Path $sourceRoot "Cargo.toml"
    if (Test-Path -LiteralPath $sourceCargo -PathType Leaf) {
        Copy-Item -LiteralPath $sourceCargo -Destination (Join-Path $snapshotRoot "Cargo.toml")
        $copiedResources += "Cargo.toml"
    }
    $snapshotEvidence = [ordered]@{
        source_repository = $sourceRoot
        source_commit = $commitSha
        copied_resources = $copiedResources
        source_mutation = "forbidden"
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $snapshotRoot "SOURCE-SNAPSHOT.json"),
        ($snapshotEvidence | ConvertTo-Json -Depth 4),
        $utf8NoBom
    )

    $manifestRoot = Join-Path $snapshotRoot "extension-manifests"
    New-Item -ItemType Directory -Path $manifestRoot -Force | Out-Null
    $genericManifest = Join-Path $manifestRoot "repository-extension.json"
    Copy-Item -LiteralPath (
        Join-Path $aosRoot "extensions\reference\aos.reference.repository\extension.json"
    ) -Destination $genericManifest
    $rustManifest = Join-Path $manifestRoot "rust-extension.json"
    if ($copiedResources -contains "Cargo.toml") {
        Copy-Item -LiteralPath (
            Join-Path $aosRoot "extensions\reference\aos.reference.rust\extension.json"
        ) -Destination $rustManifest
    }

    Invoke-Aos @(
        "init", $snapshotRoot, "--apply", "--authority=pilot-bootstrap", "--format=json"
    ) | Out-Null
    Invoke-Aos @(
        "knowledge", $snapshotRoot, "--record", "--apply",
        "--authority=pilot-producer", "--id=source-snapshot",
        "--subject=fixed-repository-snapshot",
        "--content=allowlisted-fixed-resource-snapshot",
        "--source=SOURCE-SNAPSHOT.json", "--format=json"
    ) | Out-Null
    Enable-Extension $snapshotRoot $genericManifest
    if ($copiedResources -contains "Cargo.toml") {
        Enable-Extension $snapshotRoot $rustManifest
    }

    $capabilities = @(
        [ordered]@{
            label = "repository"
            extension = "aos.reference.repository@1.0.0"
            capability = "aos.reference.repository.summary"
        }
    )
    if ($copiedResources -contains "Cargo.toml") {
        $capabilities += [ordered]@{
            label = "rust"
            extension = "aos.reference.rust@1.0.0"
            capability = "aos.reference.rust.cargo_manifest.summary"
        }
    }

    $capabilityResults = @()
    foreach ($definition in $capabilities) {
        $normalizedRuns = @()
        for ($repeat = 1; $repeat -le $Repeats; $repeat++) {
            $workId = "$($definition.label)-repeat-$repeat"
            $normalized = Run-Capability `
                $snapshotRoot $workId $definition.extension $definition.capability
            $normalizedRuns += $normalized
            $totalRuns += 1
        }
        $baseline = $normalizedRuns[0] | ConvertTo-Json -Depth 10 -Compress
        foreach ($normalized in $normalizedRuns | Select-Object -Skip 1) {
            if (($normalized | ConvertTo-Json -Depth 10 -Compress) -ne $baseline) {
                Fail "$sourceRoot $($definition.capability) normalized replay drifted"
            }
        }
        $capabilityResults += [ordered]@{
            capability = $definition.capability
            repeats = $Repeats
            deterministic = $true
            normalized_result = $normalizedRuns[0]
        }
    }

    $statusAfter = @(git -C $sourceRoot status --porcelain=v1)
    if (($statusBefore -join "`n") -ne ($statusAfter -join "`n")) {
        Fail "source repository changed during pilot: $sourceRoot"
    }
    $repositoryResults += [ordered]@{
        source_repository = $sourceRoot
        source_commit = $commitSha
        snapshot_repository = $snapshotRoot
        copied_resources = $copiedResources
        capabilities = $capabilityResults
        source_mutated = $false
    }
}

$result = [ordered]@{
    schema_version = "AOS-P6-1-MULTI-REPOSITORY-PILOT-1"
    run_id = $runId
    repeats = $Repeats
    repository_count = $repositoryResults.Count
    total_extension_runs = $totalRuns
    repositories = $repositoryResults
    source_mutation = "none"
    result = "pass"
}
$resultPath = Join-Path $runRoot "p6-1-multi-repository-pilot.json"
[System.IO.File]::WriteAllText(
    $resultPath,
    ($result | ConvertTo-Json -Depth 12),
    $utf8NoBom
)

Write-Output "P6.1 multi-repository pilot: $runId"
Write-Output "Repositories: $($repositoryResults.Count)"
Write-Output "Extension Runs: $totalRuns"
Write-Output "Result: $resultPath"
Write-Output "AOS_P6_1_MULTI_REPOSITORY_PILOT_OK"
$global:LASTEXITCODE = 0
