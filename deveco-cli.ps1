# JustPDF - Shared helpers for wrapping `devecocli` (HarmonyOS CLI)
# Note: npm package `deveco` is the AI TUI; build/run/deploy use `devecocli`.

$script:JustPdfBundleName = 'deyu.just.pdf'
$script:JustPdfAbilityName = 'EntryAbility'
$script:JustPdfModuleName = 'entry'
$script:JustPdfProductName = 'default'
$script:JustPdfLastProductName = 'default'

function Get-JustPdfBundleName { return $script:JustPdfBundleName }
function Get-JustPdfAbilityName { return $script:JustPdfAbilityName }
function Get-JustPdfModuleName { return $script:JustPdfModuleName }
function Get-JustPdfProductName { return $script:JustPdfProductName }

function Resolve-JustPdfProductName {
    param(
        [string]$BuildMode = 'debug',
        [string]$Product
    )

    if ($Product -and $Product.Trim()) {
        return $Product.Trim()
    }
    if ($BuildMode -and $BuildMode.Trim().ToLowerInvariant() -eq 'release') {
        return 'release'
    }
    return (Get-JustPdfProductName)
}

function Get-JustPdfHapOutputDir {
    param(
        [string]$Product = (Get-JustPdfProductName)
    )

    $OutputDir = Join-Path $PSScriptRoot 'entry'
    $OutputDir = Join-Path $OutputDir 'build'
    $OutputDir = Join-Path $OutputDir $Product
    $OutputDir = Join-Path $OutputDir 'outputs'
    return (Join-Path $OutputDir 'default')
}

function Assert-JustPdfLocalBuildProfile {
    $ProfilePath = Join-Path $PSScriptRoot 'build-profile.json5'
    $ExamplePath = Join-Path $PSScriptRoot 'build-profile.json5.example'
    if (Test-Path -LiteralPath $ProfilePath) {
        return
    }
    throw @"
Missing local build-profile.json5 (gitignored signing profile).
Copy `"$ExamplePath`" to `"$ProfilePath`", then add signingConfigs.material in DevEco.
Do not commit build-profile.json5 or files under certs/.
"@
}

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
        [string]$Product = $script:JustPdfLastProductName,
        [string]$OutputDir
    )

    if (-not $Product -or -not $Product.Trim()) {
        $Product = Get-JustPdfProductName
    }
    if (-not $OutputDir -or -not $OutputDir.Trim()) {
        $OutputDir = Get-JustPdfHapOutputDir -Product $Product
    }

    $SignedCandidates = @(
        (Join-Path $OutputDir 'entry-default-signed.hap'),
        (Join-Path $OutputDir ('entry-{0}-signed.hap' -f $Product))
    )
    foreach ($SignedHapPath in $SignedCandidates) {
        if (Test-Path -LiteralPath $SignedHapPath) {
            return $SignedHapPath
        }
    }

    $FoundSigned = @(Get-ChildItem -Path $OutputDir -Filter '*-signed.hap' -ErrorAction SilentlyContinue)
    if (@($FoundSigned).Count -eq 1) {
        return $FoundSigned[0].FullName
    }

    $UnsignedHapPath = Join-Path $OutputDir 'entry-default-unsigned.hap'
    if (Test-Path -LiteralPath $UnsignedHapPath) {
        throw "Only unsigned HAP found: $UnsignedHapPath. Configure signing or sign manually before install."
    }

    throw "HAP output not found. Check build output directory: $OutputDir"
}

function Resolve-DeployDevice {
    <#
    .SYNOPSIS
    Resolve device serials for `devecocli --device`.
    With no SpecifiedTarget, returns every connected key (caller loops).
    Pass a serial or "all" via SpecifiedTarget.
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
        [string]$Product,
        [string]$Module = (Get-JustPdfModuleName)
    )

    Assert-JustPdfLocalBuildProfile
    $ResolvedProduct = Resolve-JustPdfProductName -BuildMode $BuildMode -Product $Product
    $script:JustPdfLastProductName = $ResolvedProduct
    $ModuleSpec = $Module + '@' + $ResolvedProduct
    Invoke-DevEcoCli -Arguments @(
        'build',
        '--product', $ResolvedProduct,
        '--modules', $ModuleSpec,
        '--build-mode', $BuildMode
    ) | Out-Null
}

function Invoke-DevEcoCliRun {
    param(
        [string]$Device,
        [switch]$SkipBuild,
        [string]$BuildMode = 'debug',
        [string]$Product,
        [string]$Module = (Get-JustPdfModuleName),
        [string]$Ability = (Get-JustPdfAbilityName)
    )

    Assert-JustPdfLocalBuildProfile
    $ResolvedProduct = Resolve-JustPdfProductName -BuildMode $BuildMode -Product $Product
    $script:JustPdfLastProductName = $ResolvedProduct
    $Args = @(
        'run',
        '--module', $Module,
        '--product', $ResolvedProduct,
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
    Write-Host '  .\check.ps1' -ForegroundColor DarkGray
    Write-Host '  .\apply.ps1' -ForegroundColor DarkGray
    if (@($Devices).Count -eq 0) {
        Write-Host '  .\deploy.ps1' -ForegroundColor DarkGray
        Write-Host '  .\build-deploy-run.ps1' -ForegroundColor DarkGray
        Write-Host ('  devecocli log --bundle-name {0} --follow' -f (Get-JustPdfBundleName)) -ForegroundColor DarkGray
        Write-Host '  .\crash-log.ps1' -ForegroundColor DarkGray
        Write-Host '  .\ui-inspect.ps1 -Action screenshot' -ForegroundColor DarkGray
        return
    }

    foreach ($Device in $Devices) {
        if (@($Devices).Count -gt 1) {
            Write-Host ('  # {0}' -f $Device) -ForegroundColor DarkGray
        }
        Write-Host ('  .\deploy.ps1 -Target {0}' -f $Device) -ForegroundColor DarkGray
        Write-Host ('  .\apply.ps1 -Target {0}' -f $Device) -ForegroundColor DarkGray
        Write-Host ('  .\ui-inspect.ps1 -Action screenshot -Target {0}' -f $Device) -ForegroundColor DarkGray
        Write-Host ('  .\ui-inspect.ps1 -Action layout -Target {0}' -f $Device) -ForegroundColor DarkGray
        Write-Host ('  devecocli log --device {0} --bundle-name {1} --follow' -f $Device, (Get-JustPdfBundleName)) -ForegroundColor DarkGray
        Write-Host ('  .\crash-log.ps1 -Target {0}' -f $Device) -ForegroundColor DarkGray
    }
}

function Invoke-DevEcoCliLint {
    param(
        [string]$LintPath,
        [switch]$Incremental,
        [switch]$Fix,
        [string]$Product = (Get-JustPdfProductName),
        [string]$Format = 'default'
    )

    $Args = @('check', 'lint', '--product', $Product, '--format', $Format)
    if ($Incremental) {
        $Args += '--incremental'
    }
    if ($Fix) {
        $Args += '--fix'
    }
    if ($LintPath -and $LintPath.Trim()) {
        $Args += $LintPath.Trim()
    }
    Invoke-DevEcoCli -Arguments $Args | Out-Null
}

function Get-JustPdfApplyChangeFiles {
    param(
        [string[]]$Files
    )

    if ($Files -and @($Files).Count -gt 0) {
        return @($Files | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    }

    $Raw = @()
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $Raw += @(git diff --name-only HEAD 2>$null)
        $Raw += @(git ls-files --others --exclude-standard 2>$null)
    }

    $Allowed = @('.ets', '.ts', '.cpp', '.c', '.json5', '.json')
    $Ignored = @('oh_modules/', 'node_modules/', '/build/', '.hvigor/', '.test/')
    return @(
        $Raw |
            Where-Object { $_ -and $_.Trim() } |
            ForEach-Object { $_.Trim().Replace('\', '/') } |
            Where-Object {
                $Rel = $_
                $Ext = [System.IO.Path]::GetExtension($Rel).ToLowerInvariant()
                if ($Allowed -notcontains $Ext) {
                    return $false
                }
                foreach ($Skip in $Ignored) {
                    if ($Rel -like ('*{0}*' -f $Skip)) {
                        return $false
                    }
                }
                return $true
            } |
            Select-Object -Unique
    )
}

function Write-JustPdfApplyChangeList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChangeFileName,
        [Parameter(Mandatory = $true)]
        [string[]]$Files
    )

    if ($ChangeFileName -match '[\\/]') {
        throw 'Change list file name must not contain path separators.'
    }

    $HvigorDir = Join-Path $PSScriptRoot '.hvigor'
    if (-not (Test-Path -LiteralPath $HvigorDir)) {
        New-Item -ItemType Directory -Path $HvigorDir | Out-Null
    }

    $ChangeListPath = Join-Path $HvigorDir $ChangeFileName
    Set-Content -Path $ChangeListPath -Value $Files -Encoding UTF8
    return $ChangeListPath
}

function Invoke-DevEcoCliApply {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChangeFileName,
        [string]$Device,
        [string]$BuildMode = 'debug',
        [string]$Product,
        [string]$Module = (Get-JustPdfModuleName),
        [string]$Ability = (Get-JustPdfAbilityName)
    )

    Assert-JustPdfLocalBuildProfile
    $ResolvedProduct = Resolve-JustPdfProductName -BuildMode $BuildMode -Product $Product
    $script:JustPdfLastProductName = $ResolvedProduct
    $Args = @(
        'run',
        '--module', $Module,
        '--product', $ResolvedProduct,
        '--build-mode', $BuildMode,
        '--ability', $Ability,
        '--apply', $ChangeFileName
    )
    if ($Device) {
        $Args += @('--device', $Device)
    }
    Invoke-DevEcoCli -Arguments $Args | Out-Null
}

function Invoke-DevEcoCliCrashLog {
    param(
        [string]$Device,
        [string]$Bundle = (Get-JustPdfBundleName)
    )

    $Args = @('log', '--crash', '--bundle-name', $Bundle)
    if ($Device) {
        $Args += @('--device', $Device)
    }
    Invoke-DevEcoCli -Arguments $Args | Out-Null
}

function Invoke-DevEcoCliUiScreenshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPath,
        [string]$Device
    )

    $Args = @('ui', 'screenshot', '--path', $OutPath)
    if ($Device) {
        $Args += @('--device', $Device)
    }
    Invoke-DevEcoCli -Arguments $Args | Out-Null
}

function Invoke-DevEcoCliUiLayout {
    param(
        [string]$Device,
        [string]$Format = 'default',
        [string]$Mode = 'simplified'
    )

    $Args = @('ui', 'layout', '--format', $Format, '--mode', $Mode)
    if ($Device) {
        $Args += @('--device', $Device)
    }
    Invoke-DevEcoCli -Arguments $Args | Out-Null
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
