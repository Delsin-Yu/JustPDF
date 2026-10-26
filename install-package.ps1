# JustPDF - Install an arbitrary HAP / HSP / APP onto connected devices.
# Does not compile. Drop files onto install-package.cmd, or pass paths here.
# Default: every connected device. Use -Target <serial> for one device.

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Package,
    [string]$Target,
    [switch]$Grant
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot 'hdc-target.ps1')
. (Join-Path $ProjectRoot 'deveco-cli.ps1')

function Get-InstallPackagePath {
    param([Parameter(Mandatory = $true)][string]$Raw)

    $Trimmed = $Raw.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($Trimmed)) {
        throw 'Empty package path.'
    }

    $Resolved = $Trimmed
    if (-not [System.IO.Path]::IsPathRooted($Resolved)) {
        $Resolved = Join-Path (Get-Location) $Resolved
    }
    $Resolved = [System.IO.Path]::GetFullPath($Resolved)

    if (Test-Path -LiteralPath $Resolved -PathType Container) {
        return [pscustomobject]@{
            Path = $Resolved
            Kind = 'directory'
        }
    }
    if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
        throw "Package not found: $Resolved"
    }

    $Ext = [System.IO.Path]::GetExtension($Resolved).ToLowerInvariant()
    switch ($Ext) {
        '.hap' { $Kind = 'hap' }
        '.app' { $Kind = 'app' }
        '.hsp' { $Kind = 'hsp' }
        default {
            throw "Unsupported package type '$Ext': $Resolved (use .hap / .app / .hsp or a folder)"
        }
    }

    return [pscustomobject]@{
        Path = $Resolved
        Kind = $Kind
    }
}

function Invoke-HdcInstallPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Device,
        [Parameter(Mandatory = $true)]$PackageInfo,
        [switch]$GrantPerms
    )

    $Args = [System.Collections.Generic.List[string]]::new()
    $Args.Add('install')
    # -r is the documented overwrite flag (also the hdc default).
    $Args.Add('-r')
    if ($GrantPerms) {
        $Args.Add('-g')
    }
    if ($PackageInfo.Kind -eq 'hsp') {
        $Args.Add('-s')
    }
    if ($PackageInfo.Kind -eq 'directory') {
        $Args.Add('-p')
    }
    $Args.Add($PackageInfo.Path)

    Write-Host ("hdc -t {0} {1}" -f $Device, ($Args -join ' ')) -ForegroundColor DarkGray
    Invoke-HdcRaw -Hdc $Hdc -Arguments $Args.ToArray() -Target $Device | Out-Null
}

if (-not $Package -or $Package.Count -eq 0) {
    Write-Host 'Usage:' -ForegroundColor Yellow
    Write-Host '  Drag .hap / .app / .hsp (or a folder) onto install-package.cmd'
    Write-Host '  .\install-package.ps1 <path> [<path>...] [-Target <serial>] [-Grant]'
    Write-Host ''
    Write-Host 'Does not build. Does not launch. For the project HAP + launch, use .\deploy.ps1'
    exit 1
}

$Packages = @(
    foreach ($Item in $Package) {
        Get-InstallPackagePath -Raw $Item
    }
)

$Hdc = Get-HdcExecutable
$Devices = @(Resolve-DeployDevice -SpecifiedTarget $Target)
if ($Devices.Count -eq 0) {
    throw 'No connected hdc device. USB-pair once, or run .\connect-wifi.ps1'
}

Write-Host ('Installing {0} package(s) onto {1} device(s) (no build).' -f $Packages.Count, $Devices.Count) -ForegroundColor Cyan

$Failed = 0
$Index = 0
foreach ($Device in $Devices) {
    $Index++
    Write-HdcMultiTargetBanner -Index $Index -Total $Devices.Count -Key $Device
    foreach ($Info in $Packages) {
        Write-Host ("[{0}/{1}] {2}  {3}" -f $Index, $Devices.Count, $Info.Kind, $Info.Path) -ForegroundColor Cyan
        try {
            Invoke-HdcInstallPackage -Hdc $Hdc -Device $Device -PackageInfo $Info -GrantPerms:$Grant
            Write-Host 'Installed.' -ForegroundColor Green
        } catch {
            $Failed++
            Write-Host $_ -ForegroundColor Red
            if ("$_" -match '9568286|provision type not same') {
                Write-Host 'Debug and release cannot overlay. Uninstall the existing app on that device, then drop the package again.' -ForegroundColor Yellow
            }
        }
    }
}

if ($Failed -gt 0) {
    throw ("Install finished with {0} failure(s)." -f $Failed)
}

Write-Host ''
Write-Host 'Done. No launch — start the app on the device if needed.' -ForegroundColor Green
