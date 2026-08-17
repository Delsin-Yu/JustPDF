# JustPDF - Deploy existing HAP and launch via devecocli (no build)
# Default: every connected device. Use -Target <serial> for one device.

param(
    [switch]$ClearLogs,
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
    $HapPath = Resolve-HapPath
    $Devices = @(Resolve-DeployDevice -SpecifiedTarget $Target)

    if ($ClearLogs) {
        Write-Host 'Clearing existing device logs...' -ForegroundColor Cyan
        Clear-DeviceHilogs -Devices $Devices
    }

    $Index = 0
    foreach ($Device in $Devices) {
        $Index++
        Write-HdcMultiTargetBanner -Index $Index -Total $Devices.Count -Key $Device
        Write-Host ('[{0}/{1}] Install + launch via devecocli run --skip-build...' -f $Index, $Devices.Count) -ForegroundColor Cyan
        Invoke-DevEcoCliRun -Device $Device -BuildMode $BuildMode -SkipBuild
    }

    Write-Host ''
    Write-Host 'Done!' -ForegroundColor Green
    Write-JustPdfFollowUpHints -Devices $Devices -HapPath $HapPath
}
finally {
    Pop-Location
}
