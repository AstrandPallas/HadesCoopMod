#requires -Version 5.1
<#
.SYNOPSIS
    Build a release ZIP for the AstrandPallas/HadesCoopMod fork.

.DESCRIPTION
    Stages the deployed TN_CoopMod and TN_MainMenuApi folders plus the
    two bootstrap DLLs (HadesModCore.dll, Xinput9_1_0.dll) into the layout
    GitHub releases expect, then writes HadesCoop-<Version>.zip at the
    repo root using Compress-Archive -CompressionLevel Optimal.

    HadesCoopGame.dll.backup-2p inside TN_CoopMod is the local 2P-DLL
    backup and is excluded from the packaged copy — it must never ship.

    Every required source path is verified before any staging happens, so
    a missing bootstrap DLL fails loudly instead of producing a broken
    release (the bug behind the initial v0.5.0-4p.1 release).

.PARAMETER Version
    Version tag, e.g. v0.5.0-4p.2. Used verbatim in the wrapper folder and
    ZIP file name (HadesCoop-<Version>/, HadesCoop-<Version>.zip).

.EXAMPLE
    .\tools\build-release.ps1 -Version v0.5.0-4p.2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Repo root = parent of tools\
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Live Hades install — source of truth for the deployed mod and bootstrap DLLs.
$HadesRoot      = 'E:\SteamLibrary\steamapps\common\Hades'
$ModsRoot       = Join-Path $HadesRoot 'Content\Mods'
$X64Root        = Join-Path $HadesRoot 'x64'

$CoopModSrc     = Join-Path $ModsRoot 'TN_CoopMod'
$MainMenuApiSrc = Join-Path $ModsRoot 'TN_MainMenuApi'
$ModCoreDll     = Join-Path $X64Root  'HadesModCore.dll'
$XinputDll      = Join-Path $X64Root  'Xinput9_1_0.dll'

# File inside TN_CoopMod that must never ship.
$LocalBackupName = 'HadesCoopGame.dll.backup-2p'

# --- Verify every required source up front -----------------------------------
$required = [ordered]@{
    'TN_CoopMod folder'     = $CoopModSrc
    'TN_MainMenuApi folder' = $MainMenuApiSrc
    'HadesModCore.dll'      = $ModCoreDll
    'Xinput9_1_0.dll'       = $XinputDll
}
$missing = @()
foreach ($entry in $required.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        $missing += ('  - {0}: {1}' -f $entry.Key, $entry.Value)
    }
}
if ($missing.Count -gt 0) {
    throw "Missing required release source(s):`n$($missing -join "`n")"
}

# --- Stage --------------------------------------------------------------------
$WrapperName = "HadesCoop-$Version"
$StagingRoot = Join-Path $RepoRoot 'build'
$StagingDir  = Join-Path $StagingRoot $WrapperName

if (Test-Path -LiteralPath $StagingDir) {
    Remove-Item -LiteralPath $StagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

$StagingMods = Join-Path $StagingDir 'Content\Mods'
$StagingX64  = Join-Path $StagingDir 'x64'
New-Item -ItemType Directory -Path $StagingMods -Force | Out-Null
New-Item -ItemType Directory -Path $StagingX64  -Force | Out-Null

# TN_CoopMod — copy in full, then strip the local 2P-DLL backup.
$CoopModDest = Join-Path $StagingMods 'TN_CoopMod'
Write-Host "Staging TN_CoopMod..."
Copy-Item -LiteralPath $CoopModSrc -Destination $CoopModDest -Recurse -Force
$BackupInDest = Join-Path $CoopModDest $LocalBackupName
if (Test-Path -LiteralPath $BackupInDest) {
    Remove-Item -LiteralPath $BackupInDest -Force
    Write-Host "  excluded $LocalBackupName"
}

# TN_MainMenuApi — copy as-is.
Write-Host "Staging TN_MainMenuApi..."
Copy-Item -LiteralPath $MainMenuApiSrc -Destination (Join-Path $StagingMods 'TN_MainMenuApi') -Recurse -Force

# Bootstrap DLLs.
Write-Host "Staging bootstrap DLLs..."
Copy-Item -LiteralPath $ModCoreDll -Destination (Join-Path $StagingX64 'HadesModCore.dll') -Force
Copy-Item -LiteralPath $XinputDll  -Destination (Join-Path $StagingX64 'Xinput9_1_0.dll')  -Force

# README.txt — generated inline so this script is self-contained.
$ReadmePath = Join-Path $StagingDir 'README.txt'
$ReadmeBody = @"
HadesCoop $Version

INSTALLATION
1. Locate your Hades install folder.
   Default Steam path:
     <Steam>\steamapps\common\Hades
2. Copy the Content\ and x64\ folders from this archive into your
   Hades install folder, merging with the existing folders.
3. Launch Hades.

Issues, support, and updates:
  https://github.com/AstrandPallas/HadesCoopMod/issues
"@
Set-Content -LiteralPath $ReadmePath -Value $ReadmeBody -Encoding UTF8

# --- Compress -----------------------------------------------------------------
# Passing the staging dir itself (no trailing \*) puts HadesCoop-<Version>\ at
# the ZIP root, which is the layout the GitHub release expects.
$ZipPath = Join-Path $RepoRoot "HadesCoop-$Version.zip"
if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}
Write-Host "Compressing (Optimal)..."
Compress-Archive -Path $StagingDir -DestinationPath $ZipPath -CompressionLevel Optimal

Write-Host ''
Write-Host 'Release ZIP built:'
Write-Host "  $ZipPath"
