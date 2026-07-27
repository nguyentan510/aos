param(
    [string]$BinaryPath = "",
    [string]$EvidenceRoot = ""
)

$ErrorActionPreference = "Stop"
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $BinaryPath) {
    $BinaryPath = Join-Path $RepositoryRoot "target\debug\aos.exe"
}
if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
    throw "Build the AOS binary before running the installer smoke: $BinaryPath"
}
if (-not $EvidenceRoot) {
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aos-p6-3-windows-" + [guid]::NewGuid().ToString("N"))
}
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
$package = Join-Path $EvidenceRoot "package"
$project = Join-Path $EvidenceRoot "project"
$install = Join-Path $EvidenceRoot "install"
$archive = Join-Path $EvidenceRoot "aos-x86_64-pc-windows-msvc.zip"
$checksums = Join-Path $EvidenceRoot "SHA256SUMS"

New-Item -ItemType Directory -Path $package, $project -Force | Out-Null
Copy-Item -LiteralPath $BinaryPath -Destination (Join-Path $package "aos.exe")
Copy-Item -LiteralPath (Join-Path $RepositoryRoot "extensions") `
    -Destination (Join-Path $package "extensions") -Recurse
Compress-Archive -Path (Join-Path $package "*") -DestinationPath $archive
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksums `
    -Value "$hash  aos-x86_64-pc-windows-msvc.zip" -Encoding ascii

& (Join-Path $RepositoryRoot "install.ps1") `
    -Version v0.1.0-rc.4 `
    -ProjectPath $project `
    -Yes `
    -InstallRoot $install `
    -NoPathUpdate `
    -ArchivePath $archive `
    -ChecksumPath $checksums
if (-not $?) {
    throw "fresh offline installation failed"
}

$installedBinary = Join-Path $install "bin\aos.exe"
& $installedBinary doctor $project --format=json | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "installed binary doctor failed"
}

& (Join-Path $RepositoryRoot "install.ps1") `
    -Version v0.1.0-rc.4 `
    -Yes `
    -InstallRoot $install `
    -NoPathUpdate `
    -ArchivePath $archive `
    -ChecksumPath $checksums | Out-Null
if (-not $?) {
    throw "repeated installation was not idempotent"
}

$badChecksums = Join-Path $EvidenceRoot "SHA256SUMS.bad"
Set-Content -LiteralPath $badChecksums `
    -Value ("0" * 64 + "  aos-x86_64-pc-windows-msvc.zip") -Encoding ascii
$tamperRejected = $false
try {
    & (Join-Path $RepositoryRoot "install.ps1") `
        -Version v0.1.0-rc.4 `
        -Yes `
        -InstallRoot (Join-Path $EvidenceRoot "tampered-install") `
        -NoPathUpdate `
        -ArchivePath $archive `
        -ChecksumPath $badChecksums 2>$null | Out-Null
} catch {
    $tamperRejected = $_.Exception.Message -like "*Checksum mismatch*"
}
if (-not $tamperRejected) {
    throw "checksum tampering was not rejected"
}

# The same verified fixture can model version-directory switching because the
# installer provenance is bound to both the requested version and archive hash.
& (Join-Path $RepositoryRoot "install.ps1") `
    -Version v0.1.0-rc.3 `
    -Yes `
    -InstallRoot $install `
    -NoPathUpdate `
    -ArchivePath $archive `
    -ChecksumPath $checksums | Out-Null
& (Join-Path $RepositoryRoot "install.ps1") `
    -Version v0.1.0-rc.4 `
    -Yes `
    -InstallRoot $install `
    -NoPathUpdate `
    -ArchivePath $archive `
    -ChecksumPath $checksums | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $install "versions\v0.1.0-rc.3\aos.exe"))) {
    throw "version switch did not retain rollback history"
}

Add-Type -AssemblyName System.IO.Compression
$unsafeArchive = Join-Path $EvidenceRoot "unsafe.zip"
$unsafeStream = [System.IO.File]::Open($unsafeArchive, [System.IO.FileMode]::CreateNew)
$unsafeZip = New-Object System.IO.Compression.ZipArchive(
    $unsafeStream,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    $entry = $unsafeZip.CreateEntry("../escape.txt")
    $writer = New-Object System.IO.StreamWriter($entry.Open())
    try {
        $writer.Write("must not escape")
    } finally {
        $writer.Dispose()
    }
} finally {
    $unsafeZip.Dispose()
    $unsafeStream.Dispose()
}
$unsafeHash = (Get-FileHash -LiteralPath $unsafeArchive -Algorithm SHA256).Hash.ToLowerInvariant()
$unsafeChecksums = Join-Path $EvidenceRoot "SHA256SUMS.unsafe"
Set-Content -LiteralPath $unsafeChecksums `
    -Value "$unsafeHash  aos-x86_64-pc-windows-msvc.zip" -Encoding ascii
$traversalRejected = $false
try {
    & (Join-Path $RepositoryRoot "install.ps1") `
        -Version v0.1.0-rc.4 `
        -Yes `
        -InstallRoot (Join-Path $EvidenceRoot "unsafe-install") `
        -NoPathUpdate `
        -ArchivePath $unsafeArchive `
        -ChecksumPath $unsafeChecksums 2>$null | Out-Null
} catch {
    $traversalRejected = $_.Exception.Message -like "*unsafe path*"
}
if (-not $traversalRejected) {
    throw "archive traversal was not rejected"
}

[System.IO.File]::AppendAllText($installedBinary, "tampered")
$modifiedRejected = $false
try {
    & (Join-Path $RepositoryRoot "install.ps1") `
        -Uninstall `
        -Yes `
        -InstallRoot $install `
        -NoPathUpdate 2>$null | Out-Null
} catch {
    $modifiedRejected = $_.Exception.Message -like "*modified*"
}
if (-not $modifiedRejected) {
    throw "modified installer-owned binary was not protected"
}
Copy-Item -LiteralPath (Join-Path $install "versions\v0.1.0-rc.4\aos.exe") `
    -Destination $installedBinary -Force

& (Join-Path $RepositoryRoot "install.ps1") `
    -Uninstall `
    -Yes `
    -InstallRoot $install `
    -NoPathUpdate
if (-not $?) {
    throw "owned distribution uninstall failed"
}
if (Test-Path -LiteralPath $installedBinary) {
    throw "distribution binary remains after uninstall"
}
if (-not (Test-Path -LiteralPath (Join-Path $project ".aos\repository.json") -PathType Leaf)) {
    throw "uninstall removed downstream .aos data"
}

Write-Output "AOS_P6_3_INSTALL_WINDOWS_OK"
Write-Output "AOS_P6_3_FRESH_PROJECT_SMOKE_OK"
