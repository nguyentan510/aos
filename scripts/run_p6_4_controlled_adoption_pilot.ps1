[CmdletBinding()]
param(
    [string]$ReleaseVersion = "v0.1.0-rc.4",
    [string]$AosBinary = "",
    [string]$ArchivePath = "",
    [string]$ChecksumPath = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $PSScriptRoot
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runningOnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
if (-not $OutputDir) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aos-p6-4-controlled-adoption"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

function Fail([string]$Message) {
    throw "AOS_P6_4_CONTROLLED_ADOPTION_FAILED: $Message"
}

function Write-Json([string]$Path, [object]$Value) {
    [System.IO.File]::WriteAllText(
        $Path,
        ($Value | ConvertTo-Json -Depth 12),
        $utf8NoBom
    )
}

function Invoke-Aos([string[]]$Arguments) {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lines = & $script:installedBinary @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $stopwatch.Stop()
    $text = $lines -join [Environment]::NewLine
    if ($exitCode -ne 0) {
        Fail "aos $($Arguments -join ' ') failed: $text"
    }
    try {
        $envelope = $text | ConvertFrom-Json
    } catch {
        Fail "aos $($Arguments -join ' ') returned invalid JSON: $text"
    }
    [pscustomobject]@{
        Envelope = $envelope
        ElapsedMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
        Raw = $text
    }
}

function Get-SourceFingerprint([string]$Root) {
    $entries = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Where-Object {
                $relative = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
                $relative -notmatch '(^|[\\/])\.aos([\\/]|$)'
            } |
            ForEach-Object {
                $relative = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
                [ordered]@{
                    path = $relative.Replace('\', '/')
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            } |
            Sort-Object path
    )
    ($entries | ConvertTo-Json -Depth 4 -Compress)
}

function New-OfflineDistribution(
    [string]$Binary,
    [string]$RunRoot
) {
    if (-not (Test-Path -LiteralPath $Binary -PathType Leaf)) {
        Fail "AOS binary does not exist: $Binary"
    }
    $distributionRoot = Join-Path $RunRoot "offline-distribution"
    $packageRoot = Join-Path $distributionRoot "package"
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    $extensions = Join-Path $scriptRoot "extensions"
    if ($script:runningOnWindows) {
        Copy-Item -LiteralPath $Binary -Destination (Join-Path $packageRoot "aos.exe")
        Copy-Item -LiteralPath $extensions -Destination (Join-Path $packageRoot "extensions") -Recurse
        $archive = Join-Path $distributionRoot "aos-x86_64-pc-windows-msvc.zip"
        Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $archive
        $assetName = "aos-x86_64-pc-windows-msvc.zip"
    } else {
        Copy-Item -LiteralPath $Binary -Destination (Join-Path $packageRoot "aos")
        & chmod 755 (Join-Path $packageRoot "aos")
        Copy-Item -LiteralPath $extensions -Destination (Join-Path $packageRoot "extensions") -Recurse
        $archive = Join-Path $distributionRoot "aos-x86_64-unknown-linux-gnu.tar.gz"
        & tar -czf $archive -C $packageRoot aos extensions
        if ($LASTEXITCODE -ne 0) {
            Fail "could not create Linux offline distribution"
        }
        $assetName = "aos-x86_64-unknown-linux-gnu.tar.gz"
    }
    $checksum = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksums = Join-Path $distributionRoot "SHA256SUMS"
    [System.IO.File]::WriteAllText($checksums, "$checksum  $assetName`n", $utf8NoBom)
    [pscustomobject]@{
        Archive = $archive
        Checksums = $checksums
        Sha256 = $checksum
        Source = "locally-packaged-ci-fixture"
    }
}

function Install-Distribution(
    [string]$InstallRoot,
    [string]$Archive,
    [string]$Checksums
) {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($script:runningOnWindows) {
        $parameters = @{
            Version = $ReleaseVersion
            Yes = $true
            InstallRoot = $InstallRoot
            NoPathUpdate = $true
        }
        if ($Archive) {
            $parameters.ArchivePath = $Archive
            $parameters.ChecksumPath = $Checksums
        }
        & (Join-Path $scriptRoot "install.ps1") @parameters | Out-Null
        $binary = Join-Path $InstallRoot "bin\aos.exe"
    } else {
        $currentBinary = Join-Path $HOME ".local/bin/aos"
        if (Test-Path -LiteralPath $currentBinary) {
            Fail "Linux pilot refuses to replace an existing user AOS binary: $currentBinary"
        }
        $installerArgs = @(
            "--version", $ReleaseVersion,
            "--yes",
            "--install-root", $InstallRoot,
            "--no-path-update"
        )
        if ($Archive) {
            $installerArgs += @("--archive-path", $Archive, "--checksum-path", $Checksums)
        }
        & sh (Join-Path $scriptRoot "install.sh") @installerArgs | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Fail "Linux distribution installation failed"
        }
        $binary = $currentBinary
    }
    $stopwatch.Stop()
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
        Fail "installed binary is missing: $binary"
    }
    [pscustomobject]@{
        Binary = [System.IO.Path]::GetFullPath($binary)
        ElapsedMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
    }
}

function Uninstall-Distribution([string]$InstallRoot) {
    if ($script:runningOnWindows) {
        & (Join-Path $scriptRoot "install.ps1") `
            -Uninstall -Yes -InstallRoot $InstallRoot -NoPathUpdate | Out-Null
    } else {
        & sh (Join-Path $scriptRoot "install.sh") `
            --uninstall --yes --install-root $InstallRoot --no-path-update | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Fail "Linux distribution uninstall failed"
        }
    }
}

function Invoke-GovernedContext(
    [string]$Root,
    [string]$ScenarioId,
    [string]$SourceReference,
    [string]$Content
) {
    $knowledgeId = "$ScenarioId-adoption-context"
    $workId = "$ScenarioId-context-verification"
    Invoke-Aos @(
        "knowledge", $Root, "--record", "--apply",
        "--authority=p6-4-pilot-producer",
        "--id=$knowledgeId",
        "--subject=$ScenarioId-controlled-adoption",
        "--content=$Content",
        "--source=$SourceReference",
        "--format=json"
    ) | Out-Null
    Invoke-Aos @(
        "work", "create", $Root, "--apply",
        "--authority=p6-4-pilot-producer",
        "--work-id=$workId",
        "--context-id=$knowledgeId",
        "--context-kind=Knowledge",
        "--intent=qualify-agent-context-after-adoption",
        "--expected-output=authoritative-provider-neutral-context",
        "--verification=source-reference-and-context-policy",
        "--format=json"
    ) | Out-Null
    Invoke-Aos @(
        "work", "authorize", $Root, "--apply",
        "--authority=p6-4-pilot-reviewer",
        "--work-id=$workId",
        "--evidence=p6-4-adoption-review",
        "--format=json"
    ) | Out-Null
    $first = Invoke-Aos @(
        "context", $Root, "--profile=compact",
        "--budget-bytes=900", "--format=json"
    )
    $second = Invoke-Aos @(
        "context", $Root, "--profile=compact",
        "--budget-bytes=900", "--format=json"
    )
    if ($first.Raw -ne $second.Raw) {
        Fail "$ScenarioId context output is not deterministic"
    }
    $selected = @($first.Envelope.data.selected)
    if (@($selected | Where-Object { $_.id -eq $knowledgeId }).Count -ne 1) {
        Fail "$ScenarioId authoritative context was not selected"
    }
    if (@($selected | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.source_reference)
    }).Count -ne 0) {
        Fail "$ScenarioId selected context lost source references"
    }
    if (@($first.Envelope.data.withheld | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.reason)
    }).Count -ne 0) {
        Fail "$ScenarioId withheld context lost a reason"
    }
    if ($first.Raw -match "(?i)(api[_-]?key|password|secret|token)\s*[:=]") {
        Fail "$ScenarioId context contains secret-like output"
    }
    $run = Invoke-Aos @(
        "work", "run", $Root, "--apply",
        "--authority=p6-4-local-runtime",
        "--work-id=$workId",
        "--format=json"
    )
    if ($run.Envelope.data.status -ne "completed") {
        Fail "$ScenarioId governed context Work did not complete"
    }
    [pscustomobject]@{
        KnowledgeId = $knowledgeId
        Context = $first.Envelope
        ContextMs = $first.ElapsedMs
        SelectedBytes = [int]$first.Envelope.data.selected_bytes
        SelectedCount = $selected.Count
        WithheldCount = @($first.Envelope.data.withheld).Count
    }
}

function Invoke-ExtensionWork(
    [string]$Root,
    [string]$ScenarioId,
    [string]$KnowledgeId,
    [string]$Extension,
    [string]$Capability
) {
    $extensionSlug = $Extension.Split('@')[0].Replace('.', '-')
    $workId = "$ScenarioId-$extensionSlug-extension"
    Invoke-Aos @(
        "work", "create", $Root, "--apply",
        "--authority=p6-4-pilot-producer",
        "--work-id=$workId",
        "--context-id=$KnowledgeId",
        "--context-kind=Knowledge",
        "--intent=qualify-installed-reference-extension",
        "--expected-output=proposed-extension-evidence",
        "--verification=manifest-digest-capability-and-scope",
        "--protocol=aos.extension.readonly@1.0.0",
        "--extension=$Extension",
        "--capability=$Capability",
        "--format=json"
    ) | Out-Null
    Invoke-Aos @(
        "work", "authorize", $Root, "--apply",
        "--authority=p6-4-pilot-reviewer",
        "--work-id=$workId",
        "--evidence=p6-4-extension-review",
        "--format=json"
    ) | Out-Null
    $run = Invoke-Aos @(
        "work", "run", $Root, "--apply",
        "--authority=p6-4-local-runtime",
        "--work-id=$workId",
        "--format=json"
    )
    if ($run.Envelope.data.status -ne "completed") {
        Fail "$ScenarioId extension Work did not complete: $Capability"
    }
    $resultPath = Join-Path $Root ".aos/extensions/results/$workId.r1.json"
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Fail "$ScenarioId extension result is missing"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    [ordered]@{
        work_id = $workId
        extension_reference = $result.extension_reference
        capability_reference = $result.capability_reference
        manifest_digest = $result.manifest_digest
        status = $result.status
        resource_references = @($result.resource_references)
    }
}

function Get-Percentile([double[]]$Values, [double]$Percentile) {
    if ($Values.Count -eq 0) {
        return 0
    }
    $sorted = @($Values | Sort-Object)
    $index = [Math]::Ceiling($Percentile * $sorted.Count) - 1
    [Math]::Round([double]$sorted[[Math]::Max(0, $index)], 3)
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$runId = "p6-4-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$runRoot = Join-Path $OutputDir $runId
$projectRoot = Join-Path $runRoot "projects"
$briefRoot = Join-Path $runRoot "agent-briefs"
$installRoot = Join-Path $runRoot "distribution"
New-Item -ItemType Directory -Path $projectRoot, $briefRoot -Force | Out-Null

$scenarios = @(
    [ordered]@{
        id = "empty"
        type = "empty"
        source = ".aos/repository.json"
        content = "The repository was adopted from an existing empty directory; source expansion is required when no project source exists."
        expected_extensions = @("aos.reference.repository@1.0.0")
    },
    [ordered]@{
        id = "generic"
        type = "generic"
        source = "README.md"
        content = "README.md identifies a generic repository; Agent consumers should use this source reference before expanding to notes/."
        expected_extensions = @("aos.reference.repository@1.0.0")
    },
    [ordered]@{
        id = "rust"
        type = "rust"
        source = "Cargo.toml"
        content = "Cargo.toml defines the p6-4-rust-adoption package; Rust source is owned by src/lib.rs and verified with cargo test."
        expected_extensions = @(
            "aos.reference.repository@1.0.0",
            "aos.reference.rust@1.0.0"
        )
    }
)

foreach ($scenario in $scenarios) {
    $root = Join-Path $projectRoot $scenario.id
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    if ($scenario.type -eq "generic") {
        New-Item -ItemType Directory -Path (Join-Path $root "notes") | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $root "README.md"),
            "# Generic adoption fixture`n",
            $utf8NoBom
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $root "notes/architecture.md"),
            "The fixture has no language-specific adapter.`n",
            $utf8NoBom
        )
    }
    if ($scenario.type -eq "rust") {
        New-Item -ItemType Directory -Path (Join-Path $root "src") | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $root "Cargo.toml"),
            "[package]`nname = `"p6-4-rust-adoption`"`nversion = `"0.1.0`"`nedition = `"2024`"`n",
            $utf8NoBom
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $root "src/lib.rs"),
            "pub fn project_name() -> &'static str { `"p6-4-rust-adoption`" }`n",
            $utf8NoBom
        )
    }
    $scenario.root = $root
    $scenario.source_fingerprint_before = Get-SourceFingerprint $root
}

$distribution = $null
if ($ArchivePath -or $ChecksumPath) {
    if (-not $ArchivePath -or -not $ChecksumPath) {
        Fail "ArchivePath and ChecksumPath must be provided together"
    }
    $distribution = [pscustomobject]@{
        Archive = [System.IO.Path]::GetFullPath($ArchivePath)
        Checksums = [System.IO.Path]::GetFullPath($ChecksumPath)
        Sha256 = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        Source = "caller-provided-offline-fixture"
    }
} elseif ($AosBinary) {
    $distribution = New-OfflineDistribution -Binary $AosBinary -RunRoot $runRoot
}

$installation = Install-Distribution `
    -InstallRoot $installRoot `
    -Archive $(if ($distribution) { $distribution.Archive } else { "" }) `
    -Checksums $(if ($distribution) { $distribution.Checksums } else { "" })
$script:installedBinary = $installation.Binary
$version = Invoke-Aos @("version", "--format=json")
if ($version.Envelope.outcome -ne "success") {
    Fail "installed binary version query failed"
}

$scenarioResults = @()
foreach ($scenario in $scenarios) {
    $setup = Invoke-Aos @(
        "setup", $scenario.root, "--yes",
        "--authority=p6-4-pilot-owner", "--format=json"
    )
    if ($setup.Envelope.outcome -ne "success") {
        Fail "$($scenario.id) setup did not succeed"
    }
    $extensions = @($setup.Envelope.data.extension_references)
    foreach ($expected in $scenario.expected_extensions) {
        if ($extensions -notcontains $expected) {
            Fail "$($scenario.id) setup did not enable $expected"
        }
    }
    $repeatSetup = Invoke-Aos @(
        "setup", $scenario.root, "--yes",
        "--authority=p6-4-pilot-owner", "--format=json"
    )
    if (@($repeatSetup.Envelope.operation.changed_paths).Count -ne 0) {
        Fail "$($scenario.id) repeated setup was not idempotent"
    }
    $doctor = Invoke-Aos @("doctor", $scenario.root, "--format=json")
    $minimalContext = Invoke-Aos @(
        "context", $scenario.root, "--profile=compact",
        "--budget-bytes=900", "--format=json"
    )
    if (@($minimalContext.Envelope.data.selected).Count -ne 0) {
        Fail "$($scenario.id) setup invented authoritative Knowledge"
    }
    $governed = Invoke-GovernedContext `
        -Root $scenario.root `
        -ScenarioId $scenario.id `
        -SourceReference $scenario.source `
        -Content $scenario.content
    $extensionResults = @(
        Invoke-ExtensionWork `
            -Root $scenario.root `
            -ScenarioId $scenario.id `
            -KnowledgeId $governed.KnowledgeId `
            -Extension "aos.reference.repository@1.0.0" `
            -Capability "aos.reference.repository.summary"
    )
    if ($scenario.type -eq "rust") {
        $extensionResults += Invoke-ExtensionWork `
            -Root $scenario.root `
            -ScenarioId $scenario.id `
            -KnowledgeId $governed.KnowledgeId `
            -Extension "aos.reference.rust@1.0.0" `
            -Capability "aos.reference.rust.cargo_manifest.summary"
    }
    $brief = [ordered]@{
        schema_version = "AOS-P6-4-AGENT-BRIEF-1"
        scenario = $scenario.id
        task_types = @("onboarding", "bugfix", "feature")
        context = $governed.Context.data
        source_expansion = [ordered]@{
            allowed = $true
            policy = "open repository source only when selected context is insufficient"
        }
        provider = "provider-neutral"
        secret_scan = "pass"
    }
    $briefPath = Join-Path $briefRoot "$($scenario.id).agent-brief.json"
    Write-Json -Path $briefPath -Value $brief
    $sourceAfter = Get-SourceFingerprint $scenario.root
    if ($sourceAfter -ne $scenario.source_fingerprint_before) {
        Fail "$($scenario.id) source changed during controlled adoption"
    }
    $scenarioResults += [ordered]@{
        id = $scenario.id
        type = $scenario.type
        root = $scenario.root
        setup_ms = $setup.ElapsedMs
        idempotent_setup_ms = $repeatSetup.ElapsedMs
        doctor_ms = $doctor.ElapsedMs
        minimal_context_ms = $minimalContext.ElapsedMs
        authoritative_context_ms = $governed.ContextMs
        selected_context_count = $governed.SelectedCount
        selected_context_bytes = $governed.SelectedBytes
        extension_references = $extensions
        extension_results = $extensionResults
        agent_brief = $briefPath
        deterministic_context = $true
        secret_scan = "pass"
        source_mutated = $false
    }
}

Uninstall-Distribution -InstallRoot $installRoot
if (Test-Path -LiteralPath $script:installedBinary) {
    Fail "distribution binary remains after uninstall"
}
foreach ($scenario in $scenarios) {
    if (-not (Test-Path -LiteralPath (Join-Path $scenario.root ".aos/repository.json") -PathType Leaf)) {
        Fail "$($scenario.id) downstream .aos was removed by uninstall"
    }
}

$setupValues = @($scenarioResults | ForEach-Object { [double]$_.setup_ms })
$contextValues = @($scenarioResults | ForEach-Object { [double]$_.authoritative_context_ms })
$agentEvidence = Get-Content -LiteralPath (Join-Path $scriptRoot "evidence/P4-VALUE-BENCHMARK.md") -Raw
$priorAgentEvidence = $agentEvidence.Contains("AOS_P4_VALUE_BENCHMARK_OK") -and
    $agentEvidence.Contains("scenarios: onboarding, bugfix, feature")
if (-not $priorAgentEvidence) {
    Fail "canonical external-Agent benchmark evidence is missing"
}

$thresholds = [ordered]@{
    project_count = $scenarioResults.Count -eq 3
    setup_success = @($scenarioResults).Count -eq 3
    setup_p95_under_5000_ms = (Get-Percentile $setupValues 0.95) -lt 5000
    context_p95_under_2000_ms = (Get-Percentile $contextValues 0.95) -lt 2000
    deterministic_context = @($scenarioResults | Where-Object { -not $_.deterministic_context }).Count -eq 0
    source_mutation_zero = @($scenarioResults | Where-Object { $_.source_mutated }).Count -eq 0
    secret_scan = @($scenarioResults | Where-Object { $_.secret_scan -ne "pass" }).Count -eq 0
    extension_runs_completed = @(
        $scenarioResults.extension_results |
            Where-Object { $_.status -ne "succeeded" }
    ).Count -eq 0
    prior_external_agent_evidence = $priorAgentEvidence
    uninstall_preserved_downstream_data = $true
}
$allPass = @($thresholds.Values | Where-Object { -not $_ }).Count -eq 0
$result = [ordered]@{
    schema_version = "AOS-P6-4-CONTROLLED-ADOPTION-1"
    run_id = $runId
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    release_version = $ReleaseVersion
    distribution_source = if ($distribution) { $distribution.Source } else { "published-release" }
    distribution_sha256 = if ($distribution) { $distribution.Sha256 } else { "verified-by-installer" }
    installation_ms = $installation.ElapsedMs
    installed_binary = $installation.Binary
    metrics = [ordered]@{
        project_count = $scenarioResults.Count
        setup_p50_ms = Get-Percentile $setupValues 0.50
        setup_p95_ms = Get-Percentile $setupValues 0.95
        authoritative_context_p50_ms = Get-Percentile $contextValues 0.50
        authoritative_context_p95_ms = Get-Percentile $contextValues 0.95
        extension_run_count = @($scenarioResults.extension_results).Count
        source_mutation_count = @($scenarioResults | Where-Object { $_.source_mutated }).Count
        secret_finding_count = @($scenarioResults | Where-Object { $_.secret_scan -ne "pass" }).Count
    }
    thresholds = $thresholds
    scenarios = $scenarioResults
    external_agent_evidence = "evidence/P4-VALUE-BENCHMARK.md"
    external_agent_execution = "separate P6.4 qualification gate"
    uninstall = [ordered]@{
        distribution_removed = $true
        downstream_aos_preserved = $true
    }
    status = if ($allPass) { "PASS" } else { "FAIL" }
    marker = if ($allPass) {
        "AOS_P6_4_CONTROLLED_ADOPTION_PILOT_OK"
    } else {
        "AOS_P6_4_CONTROLLED_ADOPTION_PILOT_NOT_MET"
    }
}
$resultPath = Join-Path $runRoot "p6-4-controlled-adoption.json"
Write-Json -Path $resultPath -Value $result

Write-Output "P6.4 controlled adoption: $runId"
Write-Output "Projects: $($scenarioResults.Count)"
Write-Output "Setup p95: $($result.metrics.setup_p95_ms) ms"
Write-Output "Authoritative context p95: $($result.metrics.authoritative_context_p95_ms) ms"
Write-Output "Extension Runs: $($result.metrics.extension_run_count)"
Write-Output "Result: $resultPath"
Write-Output $result.marker
if (-not $allPass) {
    exit 1
}
