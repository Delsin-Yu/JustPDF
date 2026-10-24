# JustPDF - 增量 quickfix 部署（devecocli run --apply）
# 先完整跑过一次 .\build-deploy-run.ps1，再对改动的源文件打 hqf。
# 默认收集 git 未提交的源文件；可用 -Files 显式传入。

param(
    [string]$Target,
    [string]$BuildMode = 'debug',
    [string]$ChangeFile = 'changes.txt',
    [string[]]$Files
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot 'hdc-target.ps1')
. (Join-Path $ProjectRoot 'deveco-cli.ps1')

Push-Location $ProjectRoot
try {
    $ChangeFiles = @(Get-JustPdfApplyChangeFiles -Files $Files)
    if (@($ChangeFiles).Count -eq 0) {
        throw 'No changed source files to apply. Pass -Files or edit sources first.'
    }

    Write-Host 'Incremental change list:' -ForegroundColor Cyan
    foreach ($File in $ChangeFiles) {
        Write-Host ('  {0}' -f $File) -ForegroundColor DarkGray
    }

    $ChangeListPath = Write-JustPdfApplyChangeList -ChangeFileName $ChangeFile -Files $ChangeFiles
    Write-Host ('Wrote {0}' -f $ChangeListPath) -ForegroundColor DarkGray

    $Devices = @(Resolve-DeployDevice -SpecifiedTarget $Target)
    $Index = 0
    foreach ($Device in $Devices) {
        $Index++
        Write-HdcMultiTargetBanner -Index $Index -Total $Devices.Count -Key $Device
        Write-Host ('[{0}/{1}] Incremental apply via devecocli run --apply...' -f $Index, $Devices.Count) -ForegroundColor Cyan
        Invoke-DevEcoCliApply -ChangeFileName $ChangeFile -Device $Device -BuildMode $BuildMode
    }

    Write-Host ''
    Write-Host 'Apply succeeded.' -ForegroundColor Green
    Write-JustPdfFollowUpHints -Devices $Devices
}
finally {
    Pop-Location
}
