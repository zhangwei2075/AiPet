<#
.SYNOPSIS
    构建 Windows 发布包，产物在 app\build\windows\x64\runner\Release\。
    Release 目录可以整体拷贝到其他机器运行（需要 VC++ 运行库）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
#>

param(
    [ValidateSet('release', 'debug', 'profile')]
    [string]$Mode = 'release',
    [switch]$Zip
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

    Write-Step "flutter build windows --$Mode"
    flutter build windows "--$Mode"
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows 失败' }

    $out = Join-Path $AppDir "build\windows\x64\runner\$($Mode.Substring(0,1).ToUpper() + $Mode.Substring(1))"
    Write-Step "产物: $out"

    if ($Zip) {
        $zipPath = Join-Path $script:RepoRoot "MomoPet-$Mode.zip"
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zipPath
        Write-Step "已打包: $zipPath"
    }
} finally {
    Pop-Location
}
