<#
.SYNOPSIS
    公共函数：定位仓库根目录、配置 Flutter 镜像、检查 flutter 命令。
    被其他脚本 dot-source 引用，不单独执行。
#>

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:AppDir = Join-Path $script:RepoRoot 'app'
$script:ForgeDir = Join-Path $script:RepoRoot 'services\petforge'

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "找不到命令 '$Name'。$Hint"
    }
}

function Initialize-FlutterEnv {
    # 国内网络默认走镜像；已经配置过则不覆盖。
    if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn' }
    if (-not $env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn' }
    Assert-Command -Name 'flutter' -Hint '请先安装 Flutter SDK 并把 flutter\bin 加入 PATH。'
}

function Get-ForgePython {
    $venvPython = Join-Path $script:ForgeDir '.venv\Scripts\python.exe'
    if (Test-Path $venvPython) { return $venvPython }
    return 'python'
}

function Initialize-NuGet {
    # flutter_tts 的 Windows 实现要下载 Microsoft.Windows.CppWinRT，
    # 构建时由 CMake 调用 nuget.exe。没装的话自动落一份到用户目录。
    if (Get-Command nuget -ErrorAction SilentlyContinue) { return }
    $dir = Join-Path $env:LOCALAPPDATA 'MomoPet\tools'
    $exe = Join-Path $dir 'nuget.exe'
    if (-not (Test-Path $exe)) {
        Write-Step '下载 nuget.exe（语音插件构建需要，仅首次）'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $exe -UseBasicParsing
    }
    $env:PATH = "$dir;$env:PATH"
}

function Initialize-AndroidEnv {
    # Android 构建需要 JDK 17 + Android SDK，两者都从环境变量读。
    if (-not $env:JAVA_HOME) {
        throw '未设置 JAVA_HOME。Android 构建需要 JDK 17，例如 $env:JAVA_HOME = "D:\\software\\jdk\\jdk-17.0.20.1+1"'
    }
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
    if (-not $sdk) {
        throw '未设置 ANDROID_HOME（或 ANDROID_SDK_ROOT）。需要 Android SDK，包含 platform-tools / platforms;android-36 / build-tools;36.0.0'
    }
    $env:PATH = "$env:JAVA_HOME\bin;$sdk\platform-tools;$env:PATH"
    # 某些网络环境下 Java 拉 Google 仓库会卡住（IPv6 问题），强制 IPv4。
    if (-not $env:_JAVA_OPTIONS) { $env:_JAVA_OPTIONS = '-Djava.net.preferIPv4Stack=true' }
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}
