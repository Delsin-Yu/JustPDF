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
        [string]$Target
    )

    $CommandArgs = @()
    if ($Target) {
        $CommandArgs += @("-t", $Target)
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

function Get-TargetLines {
    $Lines = @(Invoke-Hdc -Arguments @("list", "targets") -AllowFailure)
    return @($Lines | Where-Object { $_ -and $_.Trim() -ne "" -and $_.Trim() -ne "[Empty]" })
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
    return @($Lines | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { [string]$_.Trim() })
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
    Write-Host "若设备已开启无线调试，可直接补全 IP；也可先选菜单项「局域网发现」。" -ForegroundColor DarkGray
    $Key = Read-ConnectKeyWithHistory
    Write-Host ""
    Write-Host ('正在连接 {0} ...' -f $Key) -ForegroundColor Cyan
    Invoke-Hdc -Arguments @("tconn", $Key) | Out-Null
    Add-ConnectWifiHistoryEntry -Key $Key
    Show-Targets
}

function Menu-Discover {
    Write-Host ""
    Write-Host "正在局域网广播发现 TCP 设备..." -ForegroundColor Cyan
    Invoke-Hdc -Arguments @("discover") -AllowFailure | Out-Null
    Show-Targets -Verbose
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
    Write-Host "  3) 局域网发现 (discover)"
    Write-Host "  4) 通过 WiFi 连接 (tconn ip:port)"
    Write-Host "  5) 断开连接 (tconn -remove)"
    Write-Host "  6) 在 USB 设备上开启无线调试 (tmode port)"
    Write-Host "  7) 关闭无线调试 / 切回 USB"
    Write-Host "  8) 重启 HDC 服务"
    Write-Host "  9) 显示 hdc 帮助摘要"
    Write-Host "  0) 退出"
    Write-Host "=======================================" -ForegroundColor Green
}

function Show-HdcHelpSummary {
    Write-Host ""
    Write-Host "常用 HDC 命令（WiFi 相关）：" -ForegroundColor Cyan
    Write-Host "  list targets [-v]          列出设备"
    Write-Host "  discover                   局域网发现 TCP 设备"
    Write-Host "  tconn <ip:port>            连接 WiFi 设备"
    Write-Host "  tconn <key> -remove        断开指定连接"
    Write-Host "  tmode port [port]          USB 设备上开启 TCP 调试（默认端口 ${DefaultTcpPort}）"
    Write-Host "  tmode port close           关闭 TCP 端口"
    Write-Host "  tmode usb                  切回 USB 模式"
    Write-Host ""
    Write-Host "完整帮助: hdc help verbose" -ForegroundColor DarkGray
}

Push-Location $ProjectRoot
try {
    $Script:ConnectWifiHistory = @(Get-ConnectWifiHistory)
    Write-Host "HDC: $Hdc" -ForegroundColor DarkGray
    Invoke-Hdc -Arguments @("checkserver") -AllowFailure | Out-Null
    Show-Targets

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
