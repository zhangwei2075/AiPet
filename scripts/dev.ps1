<#
.SYNOPSIS
    一条命令把开发环境拉起来：新窗口启动 PetForge，然后在当前窗口 flutter run。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\dev.ps1
#>

param(
    [switch]$NoForge
)

. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-FlutterEnv

if (-not $NoForge) {
    Write-Step '在新窗口启动 PetForge（关闭该窗口即停止服务）'
    Start-Process -FilePath 'powershell' -ArgumentList @(
        '-NoExit', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'start-petforge.ps1')
    ) | Out-Null
}

& (Join-Path $PSScriptRoot 'run-desktop.ps1')
