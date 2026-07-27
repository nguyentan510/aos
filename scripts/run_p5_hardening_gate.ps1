[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Resolve-Path (Join-Path $scriptRoot "..")
$requiredTests = @(
    "governance_denies_scope_mismatch_before_promotion",
    "governance_denies_cross_project_context_reference",
    "unsupported_protocol_record_fails_closed",
    "secret_like_governance_evidence_is_rejected_without_decision",
    "audit_write_failure_reports_unknown_and_preserves_reconcilable_work",
    "concurrent_work_writes_never_overwrite_an_immutable_revision"
)

$previousErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    Push-Location $repositoryRoot
    $output = & cargo test --test cli_smoke 2>&1
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $ErrorActionPreference = $previousErrorAction
}

$text = $output -join [Environment]::NewLine
if ($exitCode -ne 0) {
    throw "AOS_P5_HARDENING_FAILED: CLI process tests failed`n$text"
}
foreach ($test in $requiredTests) {
    if ($text -notmatch [regex]::Escape($test)) {
        throw "AOS_P5_HARDENING_FAILED: required test did not run: $test"
    }
}
if ($text -notmatch "test result: ok") {
    throw "AOS_P5_HARDENING_FAILED: Cargo success result is missing"
}

Write-Output "P5 hardening scenarios: $($requiredTests.Count)"
Write-Output "AOS_P5_HARDENING_OK"
