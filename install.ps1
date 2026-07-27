[CmdletBinding()]
param(
    [string]$Version,
    [string]$ProjectPath,
    [switch]$Yes,
    [switch]$Uninstall,
    [string]$InstallRoot,
    [switch]$NoPathUpdate,
    [string]$ArchivePath,
    [string]$ChecksumPath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$Repository = "nguyentan510/aos"
$AssetName = "aos-x86_64-pc-windows-msvc.zip"

function Resolve-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
}

function Test-SamePath([string]$Left, [string]$Right) {
    try {
        return (Resolve-FullPath $Left) -eq (Resolve-FullPath $Right)
    } catch {
        return $false
    }
}

function Confirm-Operation([string]$Message) {
    if ($Yes) {
        return
    }
    $answer = Read-Host "$Message [y/N]"
    if ($answer -notmatch '^(?i:y|yes)$') {
        Write-Output "AOS installation cancelled."
        exit 0
    }
}

function Resolve-ReleaseVersion {
    if ($Version) {
        if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-rc\.[0-9]+)?$') {
            throw "Version must look like v0.1.0 or v0.1.0-rc.4."
        }
        return $Version
    }
    $releases = Invoke-RestMethod -Headers @{ "User-Agent" = "aos-installer" } `
        -Uri "https://api.github.com/repos/$Repository/releases"
    $release = $releases | Where-Object { -not $_.draft -and -not $_.prerelease } | Select-Object -First 1
    if (-not $release) {
        $release = $releases | Where-Object { -not $_.draft } | Select-Object -First 1
    }
    if (-not $release) {
        throw "No published AOS release is available."
    }
    return [string]$release.tag_name
}

function Assert-OwnedPath([string]$Candidate, [string]$Root) {
    $resolvedRoot = (Resolve-FullPath $Root).TrimEnd('\') + '\'
    $resolvedCandidate = Resolve-FullPath $Candidate
    if (-not $resolvedCandidate.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify path outside the installation root: $resolvedCandidate"
    }
    return $resolvedCandidate
}

function Get-ExpectedChecksum([string]$Checksums, [string]$Name) {
    $pattern = "^([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($Name))$"
    $entries = @(
        Get-Content -LiteralPath $Checksums | ForEach-Object {
            $match = [regex]::Match($_, $pattern)
            if ($match.Success) {
                $match.Groups[1].Value.ToLowerInvariant()
            }
        }
    )
    if ($entries.Count -ne 1) {
        throw "SHA256SUMS must contain exactly one entry for $Name."
    }
    return $entries[0]
}

function Expand-VerifiedZip([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $destinationRoot = (Resolve-FullPath $Destination).TrimEnd('\') + '\'
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $target = Resolve-FullPath (Join-Path $Destination $entry.FullName)
            if (-not $target.StartsWith($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Archive contains an unsafe path: $($entry.FullName)"
            }
        }
    } finally {
        $zip.Dispose()
    }
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination
}

$defaultRoot = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "AOS"
if (-not $InstallRoot) {
    $InstallRoot = $defaultRoot
}
$InstallRoot = Resolve-FullPath $InstallRoot
if ($InstallRoot -eq [System.IO.Path]::GetPathRoot($InstallRoot)) {
    throw "InstallRoot cannot be a filesystem root."
}
$manifestPath = Join-Path $InstallRoot "install.json"
$existingManifest = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $existingManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ((Resolve-FullPath ([string]$existingManifest.install_root)) -ne $InstallRoot) {
        throw "Existing installation ownership does not match the requested root."
    }
    $existingBin = [string]$existingManifest.bin_path
    if (Test-Path -LiteralPath $existingBin -PathType Leaf) {
        $existingHash = (Get-FileHash -LiteralPath $existingBin -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($existingHash -ne [string]$existingManifest.current_binary_sha256) {
            throw "Refusing to replace a modified or unowned current binary."
        }
    }
}

if ($Uninstall) {
    Confirm-Operation "Uninstall the AOS distribution from $InstallRoot?"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "No installer-owned installation manifest exists at $manifestPath."
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ((Resolve-FullPath ([string]$manifest.install_root)) -ne $InstallRoot) {
        throw "Installation ownership does not match the requested root."
    }
    $binPath = Assert-OwnedPath ([string]$manifest.bin_path) $InstallRoot
    if (Test-Path -LiteralPath $binPath -PathType Leaf) {
        $actual = (Get-FileHash -LiteralPath $binPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne [string]$manifest.current_binary_sha256) {
            throw "Refusing uninstall because the current binary was modified or is not installer-owned."
        }
        Remove-Item -LiteralPath $binPath
    }
    if (-not $NoPathUpdate) {
        $binDirectory = Split-Path -Parent $binPath
        $entries = ([Environment]::GetEnvironmentVariable("Path", "User") -split ';') |
            Where-Object { $_ -and -not (Test-SamePath $_ $binDirectory) }
        [Environment]::SetEnvironmentVariable("Path", ($entries -join ';'), "User")
    }
    foreach ($ownedPath in @($manifest.managed_version_paths)) {
        $resolved = Assert-OwnedPath ([string]$ownedPath) $InstallRoot
        if (Test-Path -LiteralPath $resolved) {
            Remove-Item -LiteralPath $resolved -Recurse
        }
    }
    Remove-Item -LiteralPath $manifestPath
    Write-Output "AOS_P6_3_UNINSTALL_WINDOWS_OK"
    exit 0
}

if ([bool]$ArchivePath -xor [bool]$ChecksumPath) {
    throw "ArchivePath and ChecksumPath must be provided together."
}
if ($ProjectPath) {
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        throw "ProjectPath must be an existing directory."
    }
    Confirm-Operation "Install AOS and set up project '$ProjectPath'?"
}

if ($env:PROCESSOR_ARCHITECTURE -notin @("AMD64", "x86_64")) {
    throw "P6.3 supports Windows x86_64 only."
}

$resolvedVersion = Resolve-ReleaseVersion
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("aos-install-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $archive = Join-Path $temporary $AssetName
    $checksums = Join-Path $temporary "SHA256SUMS"
    if ($ArchivePath) {
        Copy-Item -LiteralPath (Resolve-FullPath $ArchivePath) -Destination $archive
        Copy-Item -LiteralPath (Resolve-FullPath $ChecksumPath) -Destination $checksums
    } else {
        $base = "https://github.com/$Repository/releases/download/$resolvedVersion"
        Invoke-WebRequest -Headers @{ "User-Agent" = "aos-installer" } -Uri "$base/$AssetName" -OutFile $archive
        Invoke-WebRequest -Headers @{ "User-Agent" = "aos-installer" } -Uri "$base/SHA256SUMS" -OutFile $checksums
    }
    $expected = Get-ExpectedChecksum $checksums $AssetName
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "Checksum mismatch for $AssetName."
    }

    $stage = Join-Path $temporary "stage"
    New-Item -ItemType Directory -Path $stage | Out-Null
    Expand-VerifiedZip $archive $stage
    $stagedBinary = Join-Path $stage "aos.exe"
    if (-not (Test-Path -LiteralPath $stagedBinary -PathType Leaf)) {
        throw "Archive does not contain aos.exe at its root."
    }
    & $stagedBinary version --format=json | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "The staged AOS binary failed its version smoke."
    }

    $versionDirectory = Assert-OwnedPath (Join-Path (Join-Path $InstallRoot "versions") $resolvedVersion) $InstallRoot
    $binDirectory = Assert-OwnedPath (Join-Path $InstallRoot "bin") $InstallRoot
    New-Item -ItemType Directory -Path (Split-Path -Parent $versionDirectory) -Force | Out-Null
    if (-not (Test-Path -LiteralPath $versionDirectory)) {
        Move-Item -LiteralPath $stage -Destination $versionDirectory
    }
    $versionBinary = Join-Path $versionDirectory "aos.exe"
    if (-not (Test-Path -LiteralPath $versionBinary -PathType Leaf)) {
        throw "Installed version directory is incomplete."
    }
    New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null
    $binPath = Join-Path $binDirectory "aos.exe"
    $pendingBin = Join-Path $binDirectory ("aos.exe.pending-" + [guid]::NewGuid().ToString("N"))
    Copy-Item -LiteralPath $versionBinary -Destination $pendingBin
    Move-Item -LiteralPath $pendingBin -Destination $binPath -Force
    $binaryHash = (Get-FileHash -LiteralPath $binPath -Algorithm SHA256).Hash.ToLowerInvariant()

    if (-not $NoPathUpdate) {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $entries = @($userPath -split ';' | Where-Object { $_ })
        if (-not ($entries | Where-Object { Test-SamePath $_ $binDirectory })) {
            [Environment]::SetEnvironmentVariable("Path", (($entries + $binDirectory) -join ';'), "User")
        }
    }

    $managedVersionPaths = @($versionDirectory)
    if ($existingManifest) {
        $managedVersionPaths = @($existingManifest.managed_version_paths) + $versionDirectory |
            Select-Object -Unique
    }
    $installation = [ordered]@{
        schema_version = "1"
        installer = "install.ps1"
        repository = $Repository
        version = $resolvedVersion
        install_root = $InstallRoot
        bin_path = $binPath
        current_binary_sha256 = $binaryHash
        archive_name = $AssetName
        archive_sha256 = $actual
        managed_version_paths = @($managedVersionPaths)
        installed_at_utc = [DateTime]::UtcNow.ToString("o")
    }
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    $pendingManifest = Join-Path $InstallRoot ("install.json.pending-" + [guid]::NewGuid().ToString("N"))
    $installation | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $pendingManifest -Encoding utf8
    Move-Item -LiteralPath $pendingManifest -Destination $manifestPath -Force

    Write-Output "Installed AOS $resolvedVersion at $binPath"
    Write-Output "AOS_P6_3_INSTALL_WINDOWS_OK"
    if ($ProjectPath) {
        & $binPath setup (Resolve-FullPath $ProjectPath) --yes --format=json
        if ($LASTEXITCODE -ne 0) {
            throw "Distribution installation succeeded, but project setup failed; rerun 'aos setup' after resolving the finding."
        }
        Write-Output "AOS_P6_3_FRESH_PROJECT_SMOKE_OK"
    }
} finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Recurse
    }
}
