<#
.SYNOPSIS
    Batch-convert standalone Granny .gr2 files to Collada .dae via lslib.

.DESCRIPTION
    Walks an input directory of .gr2 files (e.g. the output of
    `granny_unpack.py unpack-all`) and runs Divine.exe (Norbyte/lslib's
    Granny converter) on each, writing .dae files to the output dir.
    DAE imports natively into Blender.

    Why DAE not glTF: lslib's glTF exporter fails on Hades II files with
    "Object reference not set to an instance of an object" inside
    GLTFExporter.ExportMeshExtensions - lslib expects BG3-specific
    extension metadata that Hades II files don't carry. DAE export
    skips that path and succeeds.

.PARAMETER InputDir
    Directory of .gr2 files. Defaults to `.\melinoe-gr2`.

.PARAMETER OutputDir
    Where to write .dae files. Defaults to `.\melinoe-dae`.

.PARAMETER DivinePath
    Path to Divine.exe. Default assumes lslib is unzipped at
    C:\Users\matte\src\lslib\ExportTool\.

.PARAMETER Game
    Target game flag for Divine. `bg3` is the most recent format and
    accepts Hades II's Granny v7 64-bit LE files fine.

.EXAMPLE
    pwsh tools\granny\convert_to_dae.ps1
#>
[CmdletBinding()]
param(
    [string]$InputDir   = "$PSScriptRoot\melinoe-gr2",
    [string]$OutputDir  = "$PSScriptRoot\melinoe-dae",
    [string]$DivinePath = "C:\Users\matte\src\lslib\ExportTool\Packed\Tools\Divine.exe",
    [string]$Game       = "bg3"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $DivinePath)) {
    throw "Divine.exe not found at $DivinePath. Download lslib release: gh release download v1.20.4 -R Norbyte/lslib"
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
    $dst = Join-Path $OutputDir ($f.BaseName + ".dae")
    if (Test-Path $dst) { $ok++; continue }
    $output = & $DivinePath -g $Game -a convert-model -s $f.FullName -d $dst -i gr2 -o dae 2>&1
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
