# JustPDF - Build only (no deploy)
# Thin wrapper around `devecocli build`. Prints the signed HAP path and follow-ups.

param(
    [string]$Target,
    [string]$BuildMode = 'debug'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot 'hdc-target.ps1')
. (Join-Path $ProjectRoot 'deveco-cli.ps1')

Push-Location $ProjectRoot
try {
    Write-Host '[1/1] Building HAP via devecocli...' -ForegroundColor Cyan
    Invoke-DevEcoCliBuild -BuildMode $BuildMode

    $HapPath = Resolve-HapPath
    Write-Host 'Build succeeded.' -ForegroundColor Green

    $Devices = @(Resolve-DeployDevice -SpecifiedTarget $Target -AllowNone)
    Write-JustPdfFollowUpHints -Devices $Devices -HapPath $HapPath
}
finally {
    Pop-Location
}
