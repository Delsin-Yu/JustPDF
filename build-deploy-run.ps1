# JustPDF - Build, deploy, and launch normally via devecocli
# Non-debug launch path (no aa start -D).

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
    $Devices = @(Resolve-DeployDevice -SpecifiedTarget $Target)
    if ($ClearLogs) {
        Write-Host 'Clearing existing device logs...' -ForegroundColor Cyan
        Clear-DeviceHilogs -Devices $Devices
    }

    $Index = 0
    foreach ($Device in $Devices) {
        $Index++
        Write-HdcMultiTargetBanner -Index $Index -Total $Devices.Count -Key $Device
        Write-Host ('[{0}/{1}] Build + install + launch via devecocli run...' -f $Index, $Devices.Count) -ForegroundColor Cyan
        # Skip rebuild on subsequent devices after the first full run.
        $SkipBuild = $Index -gt 1
        Invoke-DevEcoCliRun -Device $Device -BuildMode $BuildMode -SkipBuild:$SkipBuild
    }

    $HapPath = Resolve-HapPath
    Write-Host ''
    Write-Host 'Done!' -ForegroundColor Green
    Write-JustPdfFollowUpHints -Devices $Devices -HapPath $HapPath
}
finally {
    Pop-Location
}
