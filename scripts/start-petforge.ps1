<#
.SYNOPSIS
    启动 PetForge 图片服务（默认 127.0.0.1:8787）。
    第一次运行会自动创建 .venv 并安装 requirements.txt 里的依赖。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\start-petforge.ps1
    powershell -ExecutionPolicy Bypass -File scripts\start-petforge.ps1 -Port 8788
#>

param(
    [int]$Port = 8787,
    [switch]$WithRembg
)

. (Join-Path $PSScriptRoot '_common.ps1')

$venvPython = Join-Path $ForgeDir '.venv\Scripts\python.exe'
$req = Join-Path $ForgeDir 'requirements.txt'

if (-not (Test-Path $venvPython)) {
    Write-Step '创建 Python 虚拟环境 services\petforge\.venv'
    python -m venv (Join-Path $ForgeDir '.venv')
    $venvPython = Join-Path $ForgeDir '.venv\Scripts\python.exe'
}

Write-Step '安装 / 校验依赖'
& $venvPython -m pip install -q --upgrade pip
& $venvPython -m pip install -q -r $req
if ($WithRembg) {
    & $venvPython -m pip install -q -r (Join-Path $ForgeDir 'requirements-optional.txt')
}

Push-Location $ForgeDir
try {
    Write-Step "http://127.0.0.1:$Port/docs  （Ctrl+C 停止）"
    & $venvPython -m uvicorn petforge.api:app --host 127.0.0.1 --port $Port
} finally {
    Pop-Location
}
