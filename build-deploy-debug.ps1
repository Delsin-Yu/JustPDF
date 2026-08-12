# JustPDF - Build/install via devecocli, then launch with hdc `aa start -D`
# May leave the app waiting at splash until a debugger attaches.

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
        Write-Host ('[{0}/{1}] Build + install via devecocli run...' -f $Index, $Devices.Count) -ForegroundColor Cyan
        $SkipBuild = $Index -gt 1
        Invoke-DevEcoCliRun -Device $Device -BuildMode $BuildMode -SkipBuild:$SkipBuild
    }

    Write-Host 'Re-launching with hdc aa start -D (devecocli has no debug-wait flag)...' -ForegroundColor Yellow
    Write-Host 'If the app stays on splash, attach a debugger or use build-deploy-run.ps1 instead.' -ForegroundColor Yellow
    Invoke-HdcDebugLaunch -Devices $Devices

    $HapPath = Resolve-HapPath
    Write-Host ''
    Write-Host 'Done!' -ForegroundColor Green
    Write-JustPdfFollowUpHints -Devices $Devices -HapPath $HapPath
    Write-Host 'Debug extras:' -ForegroundColor Cyan
    foreach ($Device in $Devices) {
        $Hdc = Get-HdcExecutable
        Write-Host ('  & "{0}" -t {1} jpid' -f $Hdc, $Device) -ForegroundColor DarkGray
        Write-Host ('  & "{0}" -t {1} track-jpid -a' -f $Hdc, $Device) -ForegroundColor DarkGray
    }
}
finally {
    Pop-Location
}
