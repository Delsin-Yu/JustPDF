# JustPDF - Shared helpers for wrapping `devecocli` (HarmonyOS CLI)
# Note: npm package `deveco` is the AI TUI; build/run/deploy use `devecocli`.

$script:JustPdfBundleName = 'deyu.just.pdf'
$script:JustPdfAbilityName = 'EntryAbility'
$script:JustPdfModuleName = 'entry'
$script:JustPdfProductName = 'default'
$script:JustPdfHapOutputDir = Join-Path $PSScriptRoot 'entry'
$script:JustPdfHapOutputDir = Join-Path $script:JustPdfHapOutputDir 'build'
$script:JustPdfHapOutputDir = Join-Path $script:JustPdfHapOutputDir 'default'
$script:JustPdfHapOutputDir = Join-Path $script:JustPdfHapOutputDir 'outputs'
$script:JustPdfHapOutputDir = Join-Path $script:JustPdfHapOutputDir 'default'

function Get-JustPdfBundleName { return $script:JustPdfBundleName }
function Get-JustPdfAbilityName { return $script:JustPdfAbilityName }
function Get-JustPdfModuleName { return $script:JustPdfModuleName }
function Get-JustPdfProductName { return $script:JustPdfProductName }
function Get-JustPdfHapOutputDir { return $script:JustPdfHapOutputDir }

function Get-DevEcoCliCommand {
    $Cmd = Get-Command 'devecocli' -ErrorAction SilentlyContinue
    if (-not $Cmd) {
        throw @'
未找到 devecocli。请先安装 HarmonyOS CLI，例如:
  npm install -g @deveco/deveco-cli
然后确认 PATH 中可执行: devecocli --version
'@
    }
    return $Cmd.Source
}

function Invoke-DevEcoCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $Cli = Get-DevEcoCliCommand
    Write-Host ('> devecocli ' + ($Arguments -join ' ')) -ForegroundColor DarkGray
    & $Cli @Arguments
    $ExitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $ExitCode -ne 0) {
        throw ('devecocli failed (exit {0}): {1}' -f $ExitCode, ($Arguments -join ' '))
    }
    return $ExitCode
}

function Resolve-HapPath {
    param(
        [string]$OutputDir = (Get-JustPdfHapOutputDir)
    )

    $SignedHapPath = Join-Path $OutputDir 'entry-default-signed.hap'
    $UnsignedHapPath = Join-Path $OutputDir 'entry-default-unsigned.hap'
    if (Test-Path $SignedHapPath) {
        return $SignedHapPath
    }
    if (Test-Path $UnsignedHapPath) {
        throw "Only unsigned HAP found: $UnsignedHapPath. Configure signing or sign manually before install."
    }

    throw "HAP output not found. Check build output directory: $OutputDir"
}

function Resolve-DeployDevice {
    <#
    .SYNOPSIS
    Resolve a device serial for `devecocli --device`.
    Uses hdc-target.ps1 for discovery / interactive pick.
    When ResolvedTarget is "all", returns every connected key (caller loops).
    #>
    param(
        [string]$SpecifiedTarget,
        [switch]$AllowNone
    )

    if (-not (Get-Command 'Get-HdcExecutable' -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'hdc-target.ps1')
    }

    $Hdc = Get-HdcExecutable
    if (-not (Test-Path $Hdc)) {
        if ($AllowNone) {
            return @()
        }
        throw "hdc not found: $Hdc"
    }

    $Resolved = Resolve-HdcTarget -Hdc $Hdc -SpecifiedTarget $SpecifiedTarget -AllowNone:$AllowNone
    if (-not $Resolved) {
        return @()
    }

    return @(Get-HdcTargetKeysForResolved -Hdc $Hdc -ResolvedTarget $Resolved)
}

function Clear-DeviceHilogs {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Devices
    )

    if (-not (Get-Command 'Get-HdcExecutable' -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'hdc-target.ps1')
    }

    $Hdc = Get-HdcExecutable
    $Index = 0
    foreach ($Device in $Devices) {
        $Index++
        Write-HdcMultiTargetBanner -Index $Index -Total $Devices.Count -Key $Device
        Invoke-HdcRaw -Hdc $Hdc -Arguments @('shell', 'hilog', '-r') -Target $Device -AllowFailure | Out-Null
    }
}

function Invoke-DevEcoCliBuild {
    param(
        [string]$BuildMode = 'debug',
        [string]$Product = (Get-JustPdfProductName),
        [string]$Module = (Get-JustPdfModuleName)
    )

    $ModuleSpec = $Module + '@' + $Product
    Invoke-DevEcoCli -Arguments @(
        'build',
        '--product', $Product,
        '--modules', $ModuleSpec,
        '--build-mode', $BuildMode
    ) | Out-Null
}

function Invoke-DevEcoCliRun {
    param(
        [string]$Device,
        [switch]$SkipBuild,
        [string]$BuildMode = 'debug',
        [string]$Product = (Get-JustPdfProductName),
        [string]$Module = (Get-JustPdfModuleName),
        [string]$Ability = (Get-JustPdfAbilityName)
    )

    $Args = @(
        'run',
        '--module', $Module,
        '--product', $Product,
        '--build-mode', $BuildMode,
        '--ability', $Ability
    )
    if ($Device) {
        $Args += @('--device', $Device)
    }
    if ($SkipBuild) {
        $Args += '--skip-build'
    }
    Invoke-DevEcoCli -Arguments $Args | Out-Null
}

function Write-JustPdfFollowUpHints {
    param(
        [string[]]$Devices = @(),
        [string]$HapPath
    )

    if ($HapPath) {
        Write-Host ('Signed HAP: ' + $HapPath) -ForegroundColor Green
    }

    Write-Host ''
    Write-Host 'Useful follow-up commands:' -ForegroundColor Cyan
    if (@($Devices).Count -eq 0) {
        Write-Host '  .\deploy.ps1' -ForegroundColor DarkGray
        Write-Host '  .\build-deploy-run.ps1' -ForegroundColor DarkGray
        Write-Host ('  devecocli log --bundle-name {0} --follow' -f (Get-JustPdfBundleName)) -ForegroundColor DarkGray
        return
    }

    foreach ($Device in $Devices) {
        if (@($Devices).Count -gt 1) {
            Write-Host ('  # {0}' -f $Device) -ForegroundColor DarkGray
        }
        Write-Host ('  .\deploy.ps1 -Target {0}' -f $Device) -ForegroundColor DarkGray
        Write-Host ('  devecocli log --device {0} --bundle-name {1} --follow' -f $Device, (Get-JustPdfBundleName)) -ForegroundColor DarkGray
    }
}

function Invoke-HdcDebugLaunch {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Devices
    )

    if (-not (Get-Command 'Get-HdcExecutable' -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'hdc-target.ps1')
    }

    $Hdc = Get-HdcExecutable
    $Bundle = Get-JustPdfBundleName
    $Ability = Get-JustPdfAbilityName
    $Module = Get-JustPdfModuleName
    $Index = 0
    foreach ($Device in $Devices) {
        $Index++
        Write-HdcMultiTargetBanner -Index $Index -Total $Devices.Count -Key $Device
        Invoke-HdcRaw -Hdc $Hdc -Arguments @('shell', 'aa', 'force-stop', $Bundle) -Target $Device -AllowFailure | Out-Null
        Invoke-HdcRaw -Hdc $Hdc -Arguments @('shell', 'bm', 'set-debug-app', $Bundle, '--debug') -Target $Device -AllowFailure | Out-Null
        Invoke-HdcRaw -Hdc $Hdc -Arguments @(
            'shell', 'aa', 'start',
            '-a', $Ability,
            '-b', $Bundle,
            '-m', $Module,
            '-D'
        ) -Target $Device | Out-Null
    }
}
