<#
.SYNOPSIS
    Batch-convert standalone Granny .gr2 files to binary glTF .glb via
    a *patched* lslib that handles meshes without BG3 ExtendedData.

.DESCRIPTION
    lslib v1.20.4's stock GLTFExporter throws NullReferenceException
    inside ExportMeshExtensions when handling Hades II meshes (they
    don't carry BG3-specific UserMeshProperties). Our patched LSLib.dll
    (built from lslib-source after a one-line null guard) fixes that.

    .glb files import natively into Blender via File > Import > glTF
    2.0 (.glb/.gltf) - no Collada add-on needed.

.PARAMETER InputDir
    Directory of .gr2 files. Defaults to `.\melinoe-gr2`.

.PARAMETER OutputDir
    Where to write .glb files. Defaults to `.\melinoe-glb`.

.PARAMETER DivinePath
    Path to Divine.exe. Default assumes patched lslib is at
    C:\Users\matte\src\lslib\ExportTool\.

.PARAMETER Game
    Target game flag. `bg3` is the latest GR2 format profile and
    accepts Hades II files with the patched ExportMeshExtensions.

.EXAMPLE
    pwsh tools\granny\convert_to_glb.ps1
#>
[CmdletBinding()]
param(
    [string]$InputDir   = "$PSScriptRoot\melinoe-gr2",
    [string]$OutputDir  = "$PSScriptRoot\melinoe-glb",
    [string]$DivinePath = "C:\Users\matte\src\lslib\ExportTool\Packed\Tools\Divine.exe",
    [string]$Game       = "bg3"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $DivinePath)) {
    throw "Divine.exe not found at $DivinePath"
}
if (-not (Test-Path $InputDir)) {
    throw "Input dir not found: $InputDir. Run granny_unpack.py unpack-all first."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$files = Get-ChildItem -Path $InputDir -Filter "*.gr2"
$total = $files.Count
$ok = 0
$failed = @()

Write-Host "Converting $total files: $InputDir -> $OutputDir"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($f in $files) {
    $dst = Join-Path $OutputDir ($f.BaseName + ".glb")
    if (Test-Path $dst) { $ok++; continue }
    $output = & $DivinePath -g $Game -a convert-model -s $f.FullName -d $dst -i gr2 -o glb 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dst)) {
        $failed += [pscustomobject]@{ name = $f.Name; err = ($output -join " | ") }
    } else {
        $ok++
    }
    if ($ok % 50 -eq 0) { Write-Host "  $ok / $total ..." }
}

$sw.Stop()
Write-Host ""
Write-Host "Done in $([Math]::Round($sw.Elapsed.TotalSeconds,1))s: $ok succeeded, $($failed.Count) failed."
if ($failed.Count -gt 0) {
    Write-Host "First 5 failures:"
    $failed | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.name): $($_.err.Substring(0,[Math]::Min(120, $_.err.Length)))" }
}
