<#
.SYNOPSIS
    提交前自检：flutter analyze + flutter test + PetForge CLI 冒烟测试。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\check.ps1
#>

. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-FlutterEnv

Push-Location $AppDir
try {
    Write-Step 'flutter pub get'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败' }

    Write-Step 'flutter analyze'
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw '静态分析未通过' }

    Write-Step 'flutter test'
    flutter test
    if ($LASTEXITCODE -ne 0) { throw '测试未通过' }
} finally {
    Pop-Location
}

$venvPython = Join-Path $ForgeDir '.venv\Scripts\python.exe'
if (Test-Path $venvPython) {
    Write-Step 'PetForge CLI 冒烟测试'
    $outDir = Join-Path $env:TEMP ('petforge-smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Push-Location $ForgeDir
    try {
        & $venvPython -m petforge.cli 'tests/sample_photo.jpg' -o $outDir
        if ($LASTEXITCODE -ne 0) { throw 'PetForge 生成失败' }
    } finally {
        Pop-Location
        if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    }
} else {
    Write-Host '跳过 PetForge 冒烟测试（未创建 .venv，可先运行 scripts\start-petforge.ps1）' -ForegroundColor DarkYellow
}

Write-Step '全部检查通过'
