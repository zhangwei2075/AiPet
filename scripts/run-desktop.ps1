<#
.SYNOPSIS
    在 Windows 桌面上运行摸摸宠（Flutter debug，支持热重载）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run-desktop.ps1
    powershell -ExecutionPolicy Bypass -File scripts\run-desktop.ps1 -Release
#>

param(
    [switch]$Release,
    [string]$Device = 'windows'
)

. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-FlutterEnv
Initialize-NuGet

Push-Location $AppDir
try {
    Write-Step 'flutter pub get'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败' }

    & (Join-Path $PSScriptRoot 'plugin-links.ps1')

    if ($Release) {
        Write-Step "flutter run -d $Device --release"
        flutter run -d $Device --release
    } else {
        Write-Step "flutter run -d $Device"
        flutter run -d $Device
    }
} finally {
    Pop-Location
}
