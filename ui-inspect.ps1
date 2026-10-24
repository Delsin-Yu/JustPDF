# JustPDF - 真机/模拟器 UI 检查（截图或布局树）
# 给 agent 做可见性验证，不替代手动回归。

param(
    [ValidateSet('screenshot', 'layout')]
    [string]$Action = 'screenshot',
    [string]$Target,
    [string]$OutPath,
    [ValidateSet('default', 'json')]
    [string]$Format = 'default',
    [ValidateSet('simplified', 'full')]
    [string]$Mode = 'simplified'
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
        if ($Action -eq 'screenshot') {
            $Destination = $OutPath
            if (-not $Destination) {
                $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $SafeDevice = ($Device -replace '[^\w\.-]', '_')
                $TempDir = Join-Path $ProjectRoot 'temp'
                if (-not (Test-Path -LiteralPath $TempDir)) {
                    New-Item -ItemType Directory -Path $TempDir | Out-Null
                }
                $Destination = Join-Path $TempDir ('ui-{0}-{1}.png' -f $SafeDevice, $Stamp)
            }
            Write-Host ('[{0}/{1}] Capturing screenshot -> {2}' -f $Index, $Devices.Count, $Destination) -ForegroundColor Cyan
            Invoke-DevEcoCliUiScreenshot -OutPath $Destination -Device $Device
            Write-Host ('Screenshot: {0}' -f $Destination) -ForegroundColor Green
        }
        else {
            Write-Host ('[{0}/{1}] Dumping on-screen layout tree...' -f $Index, $Devices.Count) -ForegroundColor Cyan
            Invoke-DevEcoCliUiLayout -Device $Device -Format $Format -Mode $Mode
        }
    }
}
finally {
    Pop-Location
}
