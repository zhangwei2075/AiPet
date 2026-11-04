<#
.SYNOPSIS
    在没有开启 Windows 开发者模式（无法创建符号链接）时，用目录联接（junction）
    代替 Flutter 自动生成的插件符号链接。

.DESCRIPTION
    Flutter 构建 Windows 桌面应用时，会把每个插件的源码目录符号链接到
    app\windows\flutter\ephemeral\.plugin_symlinks\<插件名>。
    创建符号链接需要管理员权限或“开发者模式”，而目录联接（mklink /J）普通用户
    就能创建，Dart 也把它识别为 Link，因此 Flutter 会直接复用、不再重建。

    使用顺序：flutter pub get 之后、flutter build/run 之前执行本脚本。
    若已经开启开发者模式，脚本会什么都不做，可以安全地重复执行。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\plugin-links.ps1
#>

param()

. (Join-Path $PSScriptRoot '_common.ps1')

$depsFile = Join-Path $AppDir '.flutter-plugins-dependencies'
if (-not (Test-Path $depsFile)) {
    Write-Step '找不到 .flutter-plugins-dependencies，先执行 flutter pub get'
    Push-Location $AppDir
    try { flutter pub get } finally { Pop-Location }
}

$deps = Get-Content $depsFile -Raw -Encoding UTF8 | ConvertFrom-Json
$plugins = @($deps.plugins.windows)
$linkDir = Join-Path $AppDir 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Path $linkDir -Force | Out-Null

$created = 0
foreach ($plugin in $plugins) {
    $target = $plugin.path.TrimEnd('\', '/')
    $link = Join-Path $linkDir $plugin.name
    if (Test-Path -LiteralPath $link) { continue }

    try {
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        $created++
    } catch {
        # 开发者模式可用时，交给 Flutter 自己建符号链接即可。
        Write-Host "跳过 $($plugin.name)：$($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

Write-Step "插件目录联接就绪（新建 $created 个，共 $($plugins.Count) 个 Windows 插件）"
