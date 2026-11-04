<#
.SYNOPSIS
    生成 MSIX 安装包（带测试证书签名），产物在
    app\build\windows\x64\runner\Release\momopet.msix。

.DESCRIPTION
    MSIX 是 Windows 商店 / 侧载都能用的安装格式。本项目没有正式代码签名证书，
    所以用 msix 包自动生成的 test_certificate.pfx 签名：

    - 要安装这个包，目标机器需要「开发者模式」，或者先信任这张测试证书；
    - 有正式证书时，把 certificate_path / publisher 换成你自己的即可。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-msix.ps1
#>

param()

. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-FlutterEnv
Initialize-NuGet

Push-Location $AppDir
try {
    Write-Step 'flutter pub get'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败' }

    & (Join-Path $PSScriptRoot 'plugin-links.ps1')

    Write-Step 'dart run msix:create'
    dart run msix:create
    if ($LASTEXITCODE -ne 0) { throw 'MSIX 打包失败' }

    $msix = Join-Path $AppDir 'build\windows\x64\runner\Release\momopet.msix'
    if (-not (Test-Path $msix)) { throw "没找到产物：$msix" }
    $size = [math]::Round((Get-Item $msix).Length / 1MB, 1)
    Write-Step "MSIX 已生成：$msix （$size MB）"
    Write-Host '安装前请确认目标机器已开开发者模式，或已信任测试证书。' -ForegroundColor DarkYellow
} finally {
    Pop-Location
}
