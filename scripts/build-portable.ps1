<#
.SYNOPSIS
    把 flutter build windows --release 的产物整理成「双击即用」的绿色版目录，
    并重建项目根目录的 MomoPet-release.zip。

.DESCRIPTION
    Flutter Windows 的 momopet.exe 必须与 flutter_windows.dll、插件 dll 和 data\
    目录放在一起才能运行，单独拷出一个 exe 是打不开的。本脚本：
      1. 复制 Release 产物到 dist\MomoPet\，去掉 msix / pdb / lib 等不需要的文件；
      2. 额外生成一个中文名副本「摸摸宠.exe」，双击体验更直观（与 momopet.exe 等价）；
      3. 放入 LICENSE，重建免安装压缩包。

    脚本幂等：每次都会重建 dist\MomoPet 与 zip，可重复运行。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-portable.ps1
#>
param()

. (Join-Path $PSScriptRoot '_common.ps1')
$ErrorActionPreference = 'Stop'

$release = Join-Path $AppDir 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'momopet.exe'))) {
    throw "找不到 Release 产物：$release`n请先运行 scripts\build-windows.ps1"
}

$distRoot = Join-Path $script:RepoRoot 'dist'
$portable = Join-Path $distRoot 'MomoPet'
# 纯覆盖式幂等：不删除目录（某些环境禁止脚本删除），同名文件一律覆盖。
New-Item -ItemType Directory -Path $portable -Force | Out-Null

$excludePatterns = @('*.msix', '*.pdb', '*.exp', '*.lib', '*.ilk', '*.idb')
$copied = 0
Get-ChildItem -LiteralPath $release -Force | ForEach-Object {
    $name = $_.Name
    $skip = $false
    foreach ($pattern in $excludePatterns) {
        if ($name -like $pattern) { $skip = $true; break }
    }
    if ($skip) { return }
    Copy-Item -LiteralPath $_.FullName -Destination $portable -Recurse -Force
    $copied++
}

# 中文名副本：Flutter runner 按自身所在目录找 data\，改文件名不影响运行。
# 用码点拼接，避免 PowerShell 5.1 读取无 BOM 的 UTF-8 脚本时把中文解成乱码文件名。
$cnExe = (-join ([char[]](0x6478, 0x6478, 0x5BA0))) + '.exe'
Copy-Item -LiteralPath (Join-Path $portable 'momopet.exe') -Destination (Join-Path $portable $cnExe) -Force

$license = Join-Path $script:RepoRoot 'LICENSE'
if (Test-Path $license) { Copy-Item -LiteralPath $license -Destination $portable -Force }

$zip = Join-Path $script:RepoRoot 'MomoPet-release.zip'
Compress-Archive -Path (Join-Path $portable '*') -DestinationPath $zip -CompressionLevel Optimal -Force

$exe = Join-Path $portable 'momopet.exe'
$size = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
Write-Step "绿色版目录：$portable （$copied 项）"
Write-Step "启动程序：$exe （或同目录的 摸摸宠.exe）"
Write-Step "免安装包：$zip （$size MB）"
