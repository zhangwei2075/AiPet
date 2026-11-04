<#
.SYNOPSIS
    生成真正可以单独拷贝、双击启动的 MomoPet.exe。

.DESCRIPTION
    把 MomoPet-release.zip（绿色版）作为资源内嵌进一个 PyInstaller --onefile 启动器。
    首次双击时启动器按压缩包内容哈希释放到
    %LOCALAPPDATA%\MomoPet\runtime\<hash>\ 并启动里面的 momopet.exe；
    之后直接启动，exe 内容变化时自动释放新版本。

    前置：先运行 scripts\build-portable.ps1 生成 MomoPet-release.zip。
    需要 Python 3.9+；没有 PyInstaller 时脚本会自动 pip install。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-single-exe.ps1
#>
param()

. (Join-Path $PSScriptRoot '_common.ps1')
$ErrorActionPreference = 'Stop'

$zip = Join-Path $script:RepoRoot 'MomoPet-release.zip'
if (-not (Test-Path -LiteralPath $zip)) {
    throw '找不到 MomoPet-release.zip，请先运行 scripts\build-portable.ps1'
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCommand) { throw '需要 Python 3.9+，并加入 PATH' }
$python = $pythonCommand.Source

& $python -c 'import PyInstaller' | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Step '安装 PyInstaller（仅首次需要）'
    & $python -m pip install pyinstaller
    if ($LASTEXITCODE -ne 0) { throw 'PyInstaller 安装失败，请手动 pip install pyinstaller' }
}

$tmpDir = Join-Path $script:RepoRoot '.tmp'
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$runtime = Join-Path $tmpDir 'runtime.zip'
Copy-Item -LiteralPath $zip -Destination $runtime -Force

$launcher = Join-Path $script:RepoRoot 'tools\launcher\momopet_launcher.py'
$icon = Join-Path $AppDir 'assets\icons\app_icon.ico'
$dist = Join-Path $script:RepoRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null

& $python -m PyInstaller --onefile --noconsole --clean --name MomoPet --icon $icon --add-data "${runtime};." --distpath $dist --workpath (Join-Path $tmpDir 'pyi-build') --specpath $tmpDir $launcher
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller 打包失败' }

$out = Join-Path $dist 'MomoPet.exe'
$size = [math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 1)
Write-Step "单文件 exe：$out （$size MB）"
