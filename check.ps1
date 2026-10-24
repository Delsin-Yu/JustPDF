# JustPDF - DevEco Code Linter（比全量 build.ps1 更快的 ArkTS 检查）
# 语法/规范问题用这个；要出 HAP 仍走 .\build.ps1。

param(
    [string]$Path,
    [string]$Product = 'default',
    [switch]$Incremental,
    [switch]$Fix
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot 'deveco-cli.ps1')

Push-Location $ProjectRoot
try {
    Write-Host '[1/1] Running devecocli check lint...' -ForegroundColor Cyan
    Invoke-DevEcoCliLint -LintPath $Path -Incremental:$Incremental -Fix:$Fix -Product $Product
    Write-Host 'Lint finished.' -ForegroundColor Green
}
finally {
    Pop-Location
}
