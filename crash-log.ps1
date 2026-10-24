# JustPDF - 拉取应用 crash 日志（devecocli log --crash）

param(
    [string]$Target
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot 'hdc-target.ps1')
. (Join-Path $ProjectRoot 'deveco-cli.ps1')

Push-Location $ProjectRoot
try {
    $Devices = @(Resolve-DeployDevice -SpecifiedTarget $Target)
    $Index = 0
    foreach ($Device in $Devices) {
        $Index++
        Write-HdcMultiTargetBanner -Index $Index -Total $Devices.Count -Key $Device
        Write-Host ('[{0}/{1}] Fetching crash logs...' -f $Index, $Devices.Count) -ForegroundColor Cyan
        Invoke-DevEcoCliCrashLog -Device $Device
    }
}
finally {
    Pop-Location
}
