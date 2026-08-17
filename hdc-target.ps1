# JustPDF - Shared HDC target discovery and interactive selection
# Resolves hdc via PATH / DEVECO_* env vars (no hardcoded install required).

function Test-JustPdfIsWindowsHost {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return [bool]$IsWindows
    }
    return $true
}

function Get-HdcBinaryName {
    if (Test-JustPdfIsWindowsHost) {
        return 'hdc.exe'
    }
    return 'hdc'
}

function Join-JustPdfPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string[]]$Parts
    )

    $Path = $Root
    foreach ($Part in $Parts) {
        $Path = Join-Path $Path $Part
    }
    return $Path
}

function Get-CandidateDevEcoHomes {
    $Homes = [System.Collections.Generic.List[string]]::new()

    $EnvHome = [Environment]::GetEnvironmentVariable('DEVECO_HOME')
    if ($EnvHome -and $EnvHome.Trim()) {
        $Homes.Add($EnvHome.Trim())
    }

    # Last-resort defaults for common installs (still overridden by PATH / env).
    if (Test-JustPdfIsWindowsHost) {
        $Homes.Add('C:\Program Files\Huawei\DevEco Studio')
        $Homes.Add('C:\Program Files\DevEco Studio')
        $Homes.Add('D:\Program Files\Huawei\DevEco Studio')
        $Homes.Add('D:\Program Files\DevEco Studio')
    }
    else {
        if ($env:HOME) {
            $Homes.Add((Join-Path $env:HOME 'DevEco-Studio'))
            $Homes.Add((Join-Path $env:HOME 'Applications/DevEco-Studio.app/Contents'))
        }
        $Homes.Add('/Applications/DevEco-Studio.app/Contents')
        $Homes.Add('/opt/DevEco-Studio')
    }

    return @($Homes | Where-Object { $_ } | Select-Object -Unique)
}

function Get-HdcToolchainCandidates {
    param(
        [string]$DevEcoRoot
    )

    $Binary = Get-HdcBinaryName
    $Candidates = [System.Collections.Generic.List[string]]::new()

    if ($DevEcoRoot -and $DevEcoRoot.Trim()) {
        $Candidates.Add((Join-JustPdfPath -Root $DevEcoRoot.Trim() -Parts @('sdk', 'default', 'openharmony', 'toolchains', $Binary)))
    }

    $SdkHome = [Environment]::GetEnvironmentVariable('DEVECO_SDK_HOME')
    if ($SdkHome -and $SdkHome.Trim()) {
        $Root = $SdkHome.Trim()
        $Candidates.Add((Join-JustPdfPath -Root $Root -Parts @('default', 'openharmony', 'toolchains', $Binary)))
        $Candidates.Add((Join-JustPdfPath -Root $Root -Parts @('openharmony', 'toolchains', $Binary)))
        $Candidates.Add((Join-JustPdfPath -Root $Root -Parts @('toolchains', $Binary)))
    }

    $OhSdk = [Environment]::GetEnvironmentVariable('OPENHARMONY_SDK_PATH')
    if ($OhSdk -and $OhSdk.Trim()) {
        $Candidates.Add((Join-JustPdfPath -Root $OhSdk.Trim() -Parts @('toolchains', $Binary)))
    }

    foreach ($CandidateHome in Get-CandidateDevEcoHomes) {
        $Candidates.Add((Join-JustPdfPath -Root $CandidateHome -Parts @('sdk', 'default', 'openharmony', 'toolchains', $Binary)))
    }

    return @($Candidates | Where-Object { $_ } | Select-Object -Unique)
}

function Get-HdcExecutable {
    param(
        [string]$HdcPath,
        [string]$DevEcoRoot
    )

    if ($HdcPath -and $HdcPath.Trim()) {
        $Explicit = $HdcPath.Trim()
        if (-not (Test-Path -LiteralPath $Explicit)) {
            throw "hdc not found: $Explicit"
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }

    $Cmd = Get-Command 'hdc' -ErrorAction SilentlyContinue
    if ($Cmd -and $Cmd.Source -and (Test-Path -LiteralPath $Cmd.Source)) {
        return $Cmd.Source
    }

    foreach ($Candidate in Get-HdcToolchainCandidates -DevEcoRoot $DevEcoRoot) {
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }

    throw @'
未找到 hdc。请任选其一:
  1) 将 hdc 加入 PATH
  2) 设置 DEVECO_HOME（DevEco Studio 安装根目录）
  3) 设置 DEVECO_SDK_HOME 或 OPENHARMONY_SDK_PATH
  4) 调用时传入 -HdcPath 或 -DevEcoRoot
'@
}

function Invoke-HdcRaw {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hdc,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure,
        [string]$Target
    )

    $CommandArgs = @()
    if ($Target) {
        $CommandArgs += @('-t', $Target)
    }
    $CommandArgs += $Arguments

    $Output = & $Hdc @CommandArgs 2>&1
    $ExitCode = $LASTEXITCODE
    if ($Output) {
        $Output | ForEach-Object { Write-Host $_ }
    }
    if (-not $AllowFailure -and $ExitCode -ne 0) {
        throw "hdc command failed (exit $ExitCode): $($CommandArgs -join ' ')"
    }
    if ($null -eq $Output) {
        return @()
    }
    return @($Output)
}

function Get-HdcTargetLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hdc
    )

    $Lines = @(Invoke-HdcRaw -Hdc $Hdc -Arguments @('list', 'targets') -AllowFailure)
    return @($Lines | Where-Object { $_ -and $_.Trim() -ne '' -and $_.Trim() -ne '[Empty]' })
}

function Get-HdcTargetKeyFromLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    return ($Line.Trim() -split '\s+')[0]
}

function Show-HdcTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hdc,
        [string]$Title = '已连接设备:'
    )

    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    $Targets = @(Get-HdcTargetLines -Hdc $Hdc)
    if (@($Targets).Count -eq 0) {
        Write-Host '  （无）' -ForegroundColor DarkYellow
    }
    else {
        $Index = 1
        foreach ($Line in $Targets) {
            Write-Host "  [$Index] $Line"
            $Index++
        }
    }
    return $Targets
}

function Test-HdcResolvedTargetIsAll {
    param(
        [string]$ResolvedTarget
    )

    return ($ResolvedTarget -ieq 'all')
}

function Get-HdcTargetKeysForResolved {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hdc,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedTarget
    )

    if (Test-HdcResolvedTargetIsAll -ResolvedTarget $ResolvedTarget) {
        $Lines = @(Get-HdcTargetLines -Hdc $Hdc)
        return @($Lines | ForEach-Object { Get-HdcTargetKeyFromLine -Line $_ })
    }

    return @($ResolvedTarget)
}

function Write-HdcMultiTargetBanner {
    param(
        [int]$Index,
        [int]$Total,
        [string]$Key
    )

    if ($Total -gt 1) {
        Write-Host ('--- [{0}/{1}] {2} ---' -f $Index, $Total, $Key) -ForegroundColor DarkGray
    }
}

function Resolve-HdcTarget {
    <#
    .SYNOPSIS
    Returns an HDC connect key, or "all" to run on every connected target.
    With no -SpecifiedTarget, uses every connected device. Pass a serial to target one.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hdc,
        [string]$SpecifiedTarget,
        [switch]$AllowNone
    )

    if ($SpecifiedTarget -and (Test-HdcResolvedTargetIsAll -ResolvedTarget $SpecifiedTarget)) {
        Write-Host '使用全部已连接设备' -ForegroundColor Cyan
        return 'all'
    }

    if ($SpecifiedTarget) {
        Write-Host ('使用指定设备: ' + $SpecifiedTarget) -ForegroundColor Cyan
        Invoke-HdcRaw -Hdc $Hdc -Arguments @('list', 'targets') -Target $SpecifiedTarget | Out-Null
        return $SpecifiedTarget
    }

    $Targets = @(Get-HdcTargetLines -Hdc $Hdc)
    $Count = @($Targets).Count

    if ($Count -eq 0) {
        if ($AllowNone) {
            return $null
        }
        throw '未检测到 HarmonyOS 设备。请先连接真机或启动模拟器。'
    }

    if ($Count -eq 1) {
        $Key = Get-HdcTargetKeyFromLine -Line $Targets[0]
        Write-Host ('已自动选择唯一设备: ' + $Key) -ForegroundColor DarkGray
        return $Key
    }

    Show-HdcTargets -Hdc $Hdc -Title '将部署到全部已连接设备:' | Out-Null
    Write-Host ('共 {0} 台，使用 -Target <serial> 可只装一台。' -f $Count) -ForegroundColor DarkGray
    return 'all'
}

function Test-HdcAvailable {
    param(
        [string]$HdcPath,
        [string]$DevEcoRoot
    )

    try {
        $Hdc = Get-HdcExecutable -HdcPath $HdcPath -DevEcoRoot $DevEcoRoot
        return [bool]$Hdc
    }
    catch {
        return $false
    }
}
