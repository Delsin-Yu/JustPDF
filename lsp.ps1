# JustPDF - 启动官方 ArkTS LSP（ace-server，stdio）
# 编辑器侧优先用已安装的 HarmonyOS-ArkTS 插件（arkts.deveco.path）。
# 本脚本给需要手动拉起 `devecocli serve lsp --arkts` 的客户端用。

param(
    [switch]$AutoDetect
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot 'deveco-cli.ps1')

Push-Location $ProjectRoot
try {
    $Args = @('serve', 'lsp', '--arkts')
    if ($AutoDetect) {
        $Args += '--auto-detect'
    }
    else {
        $Args += @('--project-path', $ProjectRoot)
    }
    Invoke-DevEcoCli -Arguments $Args
}
finally {
    Pop-Location
}
