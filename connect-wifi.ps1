# JustPDF - Interactive HarmonyOS device connection over WiFi via HDC
# USB is required once to enable TCP debugging (tmode port); afterward use tconn / discover.

param(
    [string]$HdcPath,
    [string]$DevEcoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot 'hdc-target.ps1')
$Hdc = Get-HdcExecutable -HdcPath $HdcPath -DevEcoRoot $DevEcoRoot
$DefaultTcpPort = 8710
$Script:ConnectWifiHistoryPath = Join-Path $ProjectRoot ".connect-wifi-history.txt"
$Script:ConnectWifiHistoryMaxEntries = 50
$Script:ConnectWifiHistory = @()

function Invoke-Hdc {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure,
        [switch]$Quiet,
        [string]$Target
    )

    $CommandArgs = @()
    if ($Target) {
        $CommandArgs += @("-t", $Target)
    }
    $CommandArgs += $Arguments

    $Output = & $Hdc @CommandArgs 2>&1
    $ExitCode = $LASTEXITCODE
    if ($Output -and -not $Quiet) {
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

function Get-TargetLines {
    $Lines = @(Invoke-Hdc -Arguments @("list", "targets") -AllowFailure -Quiet)
    return @($Lines | Where-Object { $_ -and $_.Trim() -ne "" -and $_.Trim() -ne "[Empty]" })
}

function Get-TargetKeys {
    return @(Get-TargetLines | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
}

function Get-TargetRecords {
    $Lines = @(Invoke-Hdc -Arguments @("list", "targets", "-v") -AllowFailure -Quiet)
    $Records = [System.Collections.Generic.List[object]]::new()
    foreach ($Line in $Lines) {
        if (-not $Line -or $Line.Trim() -eq '' -or $Line.Trim() -eq '[Empty]') {
            continue
        }
        $Parts = @(($Line -as [string]) -split '\s+')
        if ($Parts.Count -lt 3) {
            continue
        }
        $Records.Add([pscustomobject]@{
            Key        = $Parts[0]
            Transport  = $Parts[1]
            State      = $Parts[2]
        })
    }
    return @($Records.ToArray())
}

function Test-HdcWifiConnectKey {
    param(
        [string]$Key
    )

    if (-not $Key) {
        return $false
    }

    if ($Key -notmatch '^(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})$') {
        return $false
    }

    $Ip = $Matches[1]
    $Port = [int]$Matches[2]
    if ($Port -lt 1 -or $Port -gt 65535) {
        return $false
    }

    $Parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Ip, [ref]$Parsed)) {
        return $false
    }
    if ($Parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }
    if ($Ip -eq '127.0.0.1' -or $Ip -eq '0.0.0.0') {
        return $false
    }
    return $true
}

function Get-LocalIPv4SkipSet {
    $Skip = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$Skip.Add('127.0.0.1')
    [void]$Skip.Add('0.0.0.0')
    try {
        $Interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
        foreach ($Interface in $Interfaces) {
            foreach ($Address in $Interface.GetIPProperties().UnicastAddresses) {
                if ($Address.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    [void]$Skip.Add($Address.Address.ToString())
                }
            }
        }
    }
    catch {
        # 本机 IP 枚举失败时至少跳过 loopback。
    }
    return $Skip
}

function Get-HdcConnectKeysFromText {
    param(
        [object]$Items
    )

    $SkipIps = Get-LocalIPv4SkipSet
    $Keys = [System.Collections.Generic.List[string]]::new()
    foreach ($Item in @(ConvertTo-StringArray -Items $Items)) {
        $Found = [regex]::Matches($Item, '\b(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})\b')
        foreach ($Match in $Found) {
            $Ip = $Match.Groups[1].Value
            if ($SkipIps.Contains($Ip)) {
                continue
            }
            $Key = $Ip + ':' + $Match.Groups[2].Value
            if ((Test-HdcWifiConnectKey -Key $Key) -and -not $Keys.Contains($Key)) {
                $Keys.Add($Key)
            }
        }
    }
    return @($Keys.ToArray())
}

function Test-HdcWifiTcpReachable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [int]$TimeoutMs = 500
    )

    if (-not (Test-HdcWifiConnectKey -Key $Key)) {
        return $false
    }

    $Parts = $Key.Split(':')
    $Client = [System.Net.Sockets.TcpClient]::new()
    try {
        $Async = $Client.BeginConnect($Parts[0], [int]$Parts[1], $null, $null)
        if (-not $Async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $Client.EndConnect($Async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $Client.Close()
    }
}

function Connect-HdcWifiKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [switch]$AllowFailure
    )

    if (-not (Test-HdcWifiConnectKey -Key $Key)) {
        $Message = ('无效 IP:port：{0}' -f $Key)
        if ($AllowFailure) {
            Write-Host $Message -ForegroundColor DarkYellow
            return $false
        }
        throw $Message
    }

    if (-not (Test-HdcWifiTcpReachable -Key $Key)) {
        $Message = ('端口不可达，跳过 {0}' -f $Key)
        Write-Host $Message -ForegroundColor DarkYellow
        if ($AllowFailure) {
            return $false
        }
        throw $Message
    }

    Write-Host ('正在连接 {0} ...' -f $Key) -ForegroundColor Cyan
    $Output = @(Invoke-Hdc -Arguments @('tconn', $Key) -AllowFailure)
    $Text = ($Output | Out-String)
    if ($Text -match 'Connect OK' -or $Text -match 'Target is connected') {
        Add-ConnectWifiHistoryEntry -Key $Key
        return $true
    }

    Invoke-Hdc -Arguments @('tconn', $Key, '-remove') -AllowFailure -Quiet | Out-Null
    if ($AllowFailure) {
        return $false
    }
    throw ('连接失败 {0}' -f $Key)
}

function Remove-OfflineWifiTargets {
    $Removed = 0
    foreach ($Record in @(Get-TargetRecords)) {
        if ($Record.State -ne 'Offline') {
            continue
        }
        if (-not (Test-HdcWifiConnectKey -Key $Record.Key)) {
            continue
        }
        Write-Host ('移除离线目标 {0}' -f $Record.Key) -ForegroundColor DarkGray
        Invoke-Hdc -Arguments @('tconn', $Record.Key, '-remove') -AllowFailure -Quiet | Out-Null
        $Removed++
    }
    return $Removed
}

function Show-Targets {
    param(
        [switch]$Verbose
    )

    Write-Host ""
    if ($Verbose) {
        Write-Host "已连接设备（详细）：" -ForegroundColor Cyan
        Invoke-Hdc -Arguments @("list", "targets", "-v") -AllowFailure | Out-Null
    }
    else {
        Write-Host "已连接设备：" -ForegroundColor Cyan
        $Targets = @(Get-TargetLines)
        if (@($Targets).Count -eq 0) {
            Write-Host "  （无）" -ForegroundColor DarkYellow
        }
        else {
            $Index = 1
            foreach ($Line in $Targets) {
                Write-Host "  [$Index] $Line"
                $Index++
            }
        }
    }
}

function Get-ConnectWifiHistory {
    if (-not (Test-Path $Script:ConnectWifiHistoryPath)) {
        return @()
    }

    $Lines = @(Get-Content -Path $Script:ConnectWifiHistoryPath -Encoding UTF8 -ErrorAction SilentlyContinue)
    $Valid = @($Lines | ForEach-Object { [string]$_.Trim() } | Where-Object { Test-HdcWifiConnectKey -Key $_ })
    if (@($Valid).Count -ne @($Lines | Where-Object { $_ -and $_.Trim() -ne '' }).Count) {
        $Script:ConnectWifiHistory = @($Valid)
        Save-ConnectWifiHistory
    }
    return @($Valid)
}

function Remove-ConnectWifiHistoryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $Entries = [System.Collections.Generic.List[string]]::new()
    foreach ($Item in @(ConvertTo-StringArray -Items $Script:ConnectWifiHistory)) {
        if ($Item -and $Item -ne $Key) {
            $Entries.Add($Item)
        }
    }
    $Script:ConnectWifiHistory = @($Entries.ToArray())
    Save-ConnectWifiHistory
}

function ConvertTo-StringArray {
    param(
        [object]$Items
    )

    if ($null -eq $Items) {
        return @()
    }

    if ($Items -is [string]) {
        return @([string]$Items)
    }

    return @($Items | ForEach-Object { [string]$_ })
}

function Save-ConnectWifiHistory {
    $Lines = @(ConvertTo-StringArray -Items $Script:ConnectWifiHistory)
    if (@($Lines).Count -eq 0) {
        if (Test-Path $Script:ConnectWifiHistoryPath) {
            Remove-Item -Path $Script:ConnectWifiHistoryPath -Force
        }
        return
    }

    Set-Content -Path $Script:ConnectWifiHistoryPath -Value $Lines -Encoding UTF8
}

function Add-ConnectWifiHistoryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $Entries = [System.Collections.Generic.List[string]]::new()
    $Existing = @(ConvertTo-StringArray -Items $Script:ConnectWifiHistory)
    if (@($Existing).Count -gt 0) {
        $Entries.AddRange([string[]]$Existing)
    }
    $Entries.Remove($Key) | Out-Null
    $Entries.Add($Key)
    while ($Entries.Count -gt $Script:ConnectWifiHistoryMaxEntries) {
        $Entries.RemoveAt(0)
    }

    $Script:ConnectWifiHistory = @($Entries.ToArray())
    Save-ConnectWifiHistory
}

function Resolve-ConnectKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Raw,
        [int]$Port = $DefaultTcpPort
    )

    $Key = $Raw.Trim()
    if (-not $Key) {
        throw "未输入地址。"
    }
    if ($Key -notmatch ':') {
        $Key = "${Key}:${Port}"
    }
    if (-not (Test-HdcWifiConnectKey -Key $Key)) {
        throw ('无效 IP:port：{0}（需要形如 192.168.1.10:{1}）' -f $Key, $Port)
    }
    return $Key
}

function Read-EditableLineWithHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$InitialText = '',
        [string[]]$History = @()
    )

    $HistoryList = [System.Collections.Generic.List[string]]::new()
    $HistoryItems = @(ConvertTo-StringArray -Items $History)
    if (@($HistoryItems).Count -gt 0) {
        $HistoryList.AddRange([string[]]$HistoryItems)
    }

    $HistoryPos = $HistoryList.Count
    $SavedDraft = $null
    $Buffer = $InitialText
    $Cursor = $Buffer.Length

    $RedrawLine = {
        param($Line, $CursorIndex)
        $Width = [Console]::WindowWidth
        [Console]::Write("`r" + (' ' * ($Width - 1)) + "`r")
        [Console]::Write($Prompt + $Line)
        [Console]::SetCursorPosition($Prompt.Length + $CursorIndex, [Console]::CursorTop)
    }

    & $RedrawLine $Buffer $Cursor

    while ($true) {
        $KeyInfo = [Console]::ReadKey($true)
        switch ($KeyInfo.Key) {
            'Enter' {
                return $Buffer
            }
            'UpArrow' {
                if ($HistoryList.Count -eq 0) {
                    continue
                }
                if ($HistoryPos -eq $HistoryList.Count) {
                    $SavedDraft = $Buffer
                }
                if ($HistoryPos -gt 0) {
                    $HistoryPos--
                }
                $Buffer = $HistoryList[$HistoryPos]
                $Cursor = $Buffer.Length
                & $RedrawLine $Buffer $Cursor
            }
            'DownArrow' {
                if ($HistoryList.Count -eq 0) {
                    continue
                }
                if ($HistoryPos -lt ($HistoryList.Count - 1)) {
                    $HistoryPos++
                    $Buffer = $HistoryList[$HistoryPos]
                }
                elseif ($HistoryPos -eq ($HistoryList.Count - 1)) {
                    $HistoryPos = $HistoryList.Count
                    if ($null -ne $SavedDraft) {
                        $Buffer = $SavedDraft
                    }
                    else {
                        $Buffer = $InitialText
                    }
                }
                $Cursor = $Buffer.Length
                & $RedrawLine $Buffer $Cursor
            }
            'Backspace' {
                if ($Cursor -gt 0) {
                    $Buffer = $Buffer.Remove($Cursor - 1, 1)
                    $Cursor--
                    & $RedrawLine $Buffer $Cursor
                }
            }
            'Delete' {
                if ($Cursor -lt $Buffer.Length) {
                    $Buffer = $Buffer.Remove($Cursor, 1)
                    & $RedrawLine $Buffer $Cursor
                }
            }
            'LeftArrow' {
                if ($Cursor -gt 0) {
                    $Cursor--
                    [Console]::SetCursorPosition($Prompt.Length + $Cursor, [Console]::CursorTop)
                }
            }
            'RightArrow' {
                if ($Cursor -lt $Buffer.Length) {
                    $Cursor++
                    [Console]::SetCursorPosition($Prompt.Length + $Cursor, [Console]::CursorTop)
                }
            }
            'Home' {
                $Cursor = 0
                [Console]::SetCursorPosition($Prompt.Length, [Console]::CursorTop)
            }
            'End' {
                $Cursor = $Buffer.Length
                [Console]::SetCursorPosition($Prompt.Length + $Cursor, [Console]::CursorTop)
            }
            default {
                if ([int][char]$KeyInfo.KeyChar -ge 32) {
                    $Buffer = $Buffer.Insert($Cursor, [string]$KeyInfo.KeyChar)
                    $Cursor++
                    & $RedrawLine $Buffer $Cursor
                }
            }
        }
    }
}

function Read-ConnectKeyWithHistory {
    param(
        [int]$Port = $DefaultTcpPort
    )

    Write-Host ""
    Write-Host "补全主机与端口（默认端口 ${Port}；↑↓ 翻阅历史）" -ForegroundColor DarkGray
    $Prompt = "  ip:port = "
    $Raw = Read-EditableLineWithHistory -Prompt $Prompt -InitialText "192.168.1." -History @(ConvertTo-StringArray -Items $Script:ConnectWifiHistory)
    return (Resolve-ConnectKey -Raw $Raw -Port $Port)
}

function Read-ConnectKey {
    param(
        [string]$Prompt,
        [string]$DefaultPrefix,
        [int]$Port = $DefaultTcpPort
    )

    if (-not $Prompt) {
        if ($DefaultPrefix) {
            $Prompt = "补全主机与端口（默认端口 ${Port}，仅主机时可省略 :port）"
        }
        else {
            $Prompt = "请输入设备地址 (ip:port，例如 192.168.1.10:${Port})"
        }
    }

    $Raw = $null
    if ($DefaultPrefix) {
        Write-Host ""
        Write-Host $Prompt -ForegroundColor DarkGray
        Write-Host -NoNewline "  ip:port = "
        Write-Host -NoNewline $DefaultPrefix -ForegroundColor Cyan
        $Suffix = [Console]::ReadLine()
        if ($null -eq $Suffix) {
            $Suffix = ""
        }
        $Suffix = $Suffix.Trim()
        if ($Suffix -match '^\d{1,3}(\.\d{1,3})+') {
            $Raw = $Suffix
        }
        else {
            $Raw = $DefaultPrefix + $Suffix
        }
    }
    else {
        $Raw = Read-Host $Prompt
    }

    return (Resolve-ConnectKey -Raw $Raw -Port $Port)
}

function Confirm-Action {
    param(
        [string]$Message
    )

    $Answer = Read-Host "$Message [y/N]"
    return $Answer -match ('^(y|yes)' + '$')
}

function Menu-ConnectWifi {
    Write-Host ""
    Write-Host "通过 WiFi 连接" -ForegroundColor Cyan
    Write-Host "若设备已开启无线调试，可直接补全 IP；也可先选菜单项「自动连接」。" -ForegroundColor DarkGray
    $Key = Read-ConnectKeyWithHistory
    Write-Host ""
    Connect-HdcWifiKey -Key $Key
    Show-Targets
}

function Invoke-HdcWifiAutoConnect {
    param(
        [switch]$SkipHistory
    )

    Write-Host ""
    Write-Host "正在自动连接无线设备..." -ForegroundColor Cyan
    if (-not (Test-HdcServerFirewallRulesReady -Port $DefaultTcpPort)) {
        Write-Host ('未检测到入站 TCP/UDP {0} 防火墙规则。自动连接可能失败，请用菜单 10 添加。' -f $DefaultTcpPort) -ForegroundColor DarkYellow
    }

    $ConnectedKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($Record in @(Get-TargetRecords)) {
        if ($Record.State -eq 'Connected' -and (Test-HdcWifiConnectKey -Key $Record.Key)) {
            if (-not $ConnectedKeys.Contains($Record.Key)) {
                $ConnectedKeys.Add($Record.Key)
            }
        }
    }

    Write-Host "正在局域网广播发现 TCP 设备..." -ForegroundColor DarkGray
    $DiscoverOutput = @(Invoke-Hdc -Arguments @('discover') -AllowFailure -Quiet)
    foreach ($Line in $DiscoverOutput) {
        $Text = [string]$Line
        if ($Text -match 'firewall ruler') {
            if (Test-HdcServerFirewallRulesReady -Port $DefaultTcpPort) {
                Write-Host "  hdc 固定提示：请放行 UDP 8710（本机规则已存在，可忽略）" -ForegroundColor DarkGray
            }
            else {
                Write-Host $Text
            }
            continue
        }
        if ($Text.Trim()) {
            Write-Host $Text
        }
    }

    $Discovered = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in @(Get-HdcConnectKeysFromText -Items $DiscoverOutput)) {
        if ((Test-HdcWifiConnectKey -Key $Key) -and -not $Discovered.Contains($Key)) {
            $Discovered.Add($Key)
        }
    }

    $Candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in $Discovered) {
        $Candidates.Add($Key)
    }

    if (-not $SkipHistory) {
        $History = @(ConvertTo-StringArray -Items $Script:ConnectWifiHistory)
        for ($Index = $History.Count - 1; $Index -ge 0; $Index--) {
            $Key = $History[$Index]
            if ((Test-HdcWifiConnectKey -Key $Key) -and -not $Candidates.Contains($Key)) {
                $Candidates.Add($Key)
            }
        }
    }

    if (@($Discovered).Count -eq 0 -and @($Candidates).Count -gt 0) {
        Write-Host ('discover 未找到设备，改连已知设备：{0}' -f ($Candidates -join ', ')) -ForegroundColor DarkGray
    }

    if (@($Candidates).Count -eq 0) {
        Write-Host "没有发现可连接的 IP:port。" -ForegroundColor DarkYellow
        Remove-OfflineWifiTargets | Out-Null
        Show-Targets -Verbose
        return
    }

    $Connected = 0
    foreach ($Key in $Candidates) {
        if ($ConnectedKeys.Contains($Key)) {
            Write-Host ('已连接，跳过 {0}' -f $Key) -ForegroundColor DarkGray
            continue
        }
        if (Connect-HdcWifiKey -Key $Key -AllowFailure) {
            $Connected++
            if (-not $ConnectedKeys.Contains($Key)) {
                $ConnectedKeys.Add($Key)
            }
        }
    }

    Remove-OfflineWifiTargets | Out-Null
    Write-Host ('自动连接结束，成功 {0} 台。' -f $Connected) -ForegroundColor Green
    Show-Targets -Verbose
}

function Menu-Discover {
    Invoke-HdcWifiAutoConnect
}

function Menu-Disconnect {
    $Targets = @(Get-TargetLines)
    if (@($Targets).Count -eq 0) {
        Write-Host "当前没有可断开的连接。" -ForegroundColor DarkYellow
        return
    }

    Write-Host ""
    Write-Host "断开连接" -ForegroundColor Cyan
    Show-Targets
    Write-Host ""
    Write-Host "输入要断开的 connect key（与 list targets 中一致），或按 Enter 手动输入。"
    $Choice = Read-Host "编号 / ip:port / Enter"
    $Key = $null
    if ($Choice -match ('^\d+' + '$')) {
        $Index = [int]$Choice - 1
        if ($Index -lt 0 -or $Index -ge @($Targets).Count) {
            throw "无效编号：$Choice"
        }
        $Key = ($Targets[$Index] -split '\s+')[0]
    }
    elseif ($Choice.Trim()) {
        $Key = $Choice.Trim()
    }
    else {
        $Key = Read-ConnectKey -Prompt "请输入要断开的 connect key (ip:port)"
    }

    Write-Host "正在断开 $Key ..." -ForegroundColor Cyan
    Invoke-Hdc -Arguments @("tconn", $Key, "-remove") | Out-Null
    Show-Targets
}

function Menu-EnableWifiOnUsb {
    Write-Host ""
    Write-Host "在 USB 已连接的设备上开启无线调试" -ForegroundColor Cyan
    Write-Host "设备将重启 hdc 守护进程并监听 TCP；请记下设备上显示的 IP 与端口。" -ForegroundColor DarkGray
    Write-Host "默认端口：${DefaultTcpPort}（直接按 Enter 使用）"
    $PortInput = Read-Host "监听端口"
    $Port = $DefaultTcpPort
    if ($PortInput.Trim()) {
        if ($PortInput -notmatch ('^\d+' + '$')) {
            throw "端口必须是数字。"
        }
        $Port = [int]$PortInput
    }

    $ConfirmMessage = ('将对当前 USB 设备执行 hdc tmode port {0}（设备可能短暂断开），是否继续？' -f $Port)
    if (-not (Confirm-Action $ConfirmMessage)) {
        Write-Host "已取消。" -ForegroundColor DarkGray
        return
    }

    Invoke-Hdc -Arguments @("tmode", "port", "$Port") | Out-Null
    Write-Host ""
    Write-Host "无线调试已开启。请在本机使用「通过 WiFi 连接」输入 设备IP:${Port}" -ForegroundColor Green
    Show-Targets -Verbose
}

function Menu-DisableWifi {
    Write-Host ""
    Write-Host "关闭无线调试 / 切回 USB" -ForegroundColor Cyan
    Write-Host "  1) tmode port close  - 关闭 TCP 端口"
    Write-Host "  2) tmode usb         - 重启为 USB 监听"
    $Choice = Read-Host "选择 [1/2]，Enter 取消"
    switch ($Choice.Trim()) {
        "1" {
            if (Confirm-Action "执行 tmode port close？") {
                Invoke-Hdc -Arguments @("tmode", "port", "close") | Out-Null
            }
        }
        "2" {
            if (Confirm-Action "执行 tmode usb（设备可能短暂断开）？") {
                Invoke-Hdc -Arguments @("tmode", "usb") | Out-Null
            }
        }
        default {
            Write-Host "已取消。" -ForegroundColor DarkGray
            return
        }
    }
    Show-Targets
}

function Menu-AddHdcFirewallRules {
    Write-Host ""
    Write-Host "添加 HDC 入站防火墙规则（TCP/UDP ${DefaultTcpPort} + hdc.exe）" -ForegroundColor Cyan
    Write-Host "discover 用 UDP 广播；HDC 服务与 tconn 用 TCP。需要管理员权限。" -ForegroundColor DarkGray
    if (-not (Confirm-Action "添加 Windows 入站 TCP/UDP ${DefaultTcpPort} 和 hdc.exe 规则？")) {
        Write-Host "已取消。" -ForegroundColor DarkGray
        return
    }

    Add-HdcServerFirewallRules -Port $DefaultTcpPort -HdcPath $Hdc | Out-Null
}

function Menu-RestartHdcServer {
    if (-not (Confirm-Action "重启 HDC 服务 (kill -r)？")) {
        Write-Host "已取消。" -ForegroundColor DarkGray
        return
    }
    Invoke-Hdc -Arguments @("kill", "-r") -AllowFailure | Out-Null
    Start-Sleep -Seconds 1
    Invoke-Hdc -Arguments @("start") -AllowFailure | Out-Null
    Write-Host "HDC 服务已重启。" -ForegroundColor Green
    Show-Targets
}

function Show-MainMenu {
    Write-Host ""
    Write-Host "======== JustPDF HDC WiFi 连接 ========" -ForegroundColor Green
    Write-Host "  1) 列出已连接设备"
    Write-Host "  2) 列出设备（详细）"
    Write-Host "  3) 自动连接（discover + tconn）"
    Write-Host "  4) 通过 WiFi 手动连接 (tconn ip:port)"
    Write-Host "  5) 断开连接 (tconn -remove)"
    Write-Host "  6) 在 USB 设备上开启无线调试 (tmode port)"
    Write-Host "  7) 关闭无线调试 / 切回 USB"
    Write-Host "  8) 重启 HDC 服务"
    Write-Host "  9) 显示 hdc 帮助摘要"
    Write-Host " 10) 添加防火墙规则（入站 TCP/UDP ${DefaultTcpPort} + hdc.exe）"
    Write-Host "  0) 退出"
    Write-Host "=======================================" -ForegroundColor Green
}

function Show-HdcHelpSummary {
    Write-Host ""
    Write-Host "常用 HDC 命令（WiFi 相关）：" -ForegroundColor Cyan
    Write-Host "  list targets [-v]          列出设备"
    Write-Host "  discover                   局域网广播发现 TCP 设备（需再 tconn）"
    Write-Host "  tconn <ip:port>            连接 WiFi 设备（TCP 需手动/自动 tconn）"
    Write-Host "  tconn <key> -remove        断开指定连接"
    Write-Host "  tmode port [port]          USB 设备上开启 TCP 调试（默认端口 ${DefaultTcpPort}）"
    Write-Host "  tmode port close           关闭 TCP 端口"
    Write-Host "  tmode usb                  切回 USB 模式"
    Write-Host "  防火墙入站 TCP/UDP ${DefaultTcpPort}  connect-wifi 菜单 10，或 Add-HdcServerFirewallRules"
    Write-Host ""
    Write-Host "完整帮助: hdc help verbose" -ForegroundColor DarkGray
}

Push-Location $ProjectRoot
try {
    $Script:ConnectWifiHistory = @(Get-ConnectWifiHistory)
    Write-Host "HDC: $Hdc" -ForegroundColor DarkGray
    Invoke-Hdc -Arguments @("checkserver") -AllowFailure | Out-Null
    Show-Targets
    Invoke-HdcWifiAutoConnect

    do {
        Show-MainMenu
        $Selection = Read-Host "请选择"
        try {
            switch ($Selection.Trim()) {
                "1" { Show-Targets }
                "2" { Show-Targets -Verbose }
                "3" { Menu-Discover }
                "4" { Menu-ConnectWifi }
                "5" { Menu-Disconnect }
                "6" { Menu-EnableWifiOnUsb }
                "7" { Menu-DisableWifi }
                "8" { Menu-RestartHdcServer }
                "9" { Show-HdcHelpSummary }
                "10" { Menu-AddHdcFirewallRules }
                "0" { break }
                "q" { break }
                "" { }
                default {
                    Write-Host "无效选项：$Selection" -ForegroundColor DarkYellow
                }
            }
        }
        catch {
            Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
        }
    } while ($Selection.Trim() -notin @("0", "q"))

    Write-Host "再见。" -ForegroundColor Green
}
finally {
    Pop-Location
}
