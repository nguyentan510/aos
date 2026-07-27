[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$aosRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))

Push-Location $aosRoot
try {
    & cargo test --locked p6_2_ -- --nocapture
    if ($LASTEXITCODE -ne 0) {
        throw "P6.2 filesystem fault-injection tests failed"
    }
} finally {
    Pop-Location
}

Write-Output "AOS_P6_2_FILESYSTEM_FAULT_INJECTION_OK"
Write-Output "AOS_P6_2_RECONCILIATION_OK"
$global:LASTEXITCODE = 0
