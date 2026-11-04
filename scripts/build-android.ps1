<#
.SYNOPSIS
    构建 Android APK（含系统悬浮窗宠物）。
    需要 Android SDK + JDK 17，并已 `flutter doctor` 通过 Android 工具链检查。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-android.ps1
    powershell -ExecutionPolicy Bypass -File scripts\build-android.ps1 -Split
#>

param(
    [ValidateSet('apk', 'appbundle')]
    [string]$Target = 'apk',
    [switch]$Split
)

. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-FlutterEnv
Initialize-AndroidEnv

Push-Location $AppDir
try {
    Write-Step 'flutter pub get'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败' }

    $buildArgs = @('build', $Target)
    if ($Split -and $Target -eq 'apk') { $buildArgs += '--split-per-abi' }

    Write-Step "flutter $($buildArgs -join ' ')"
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw '构建失败' }

    Write-Step '产物目录: app\build\app\outputs\flutter-apk (或 bundle)'
} finally {
    Pop-Location
}
