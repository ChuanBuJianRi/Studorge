# =============================================================
#  Studorge Windows Installer  v1.0
#  PowerShell 5.1+  |  Run via setup.bat (no admin required)
# =============================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ── paths ─────────────────────────────────────────────────────
$AppName   = "Studorge"
$AppDir    = Join-Path $env:APPDATA $AppName          # %APPDATA%\Studorge
$SrcDir    = Join-Path $AppDir "app"                  # …\app  (source files)
$VenvDir   = Join-Path $AppDir "venv"                 # …\venv
$DataDir   = Join-Path $AppDir "data"                 # …\data (db + chroma)
$PyExe     = Join-Path $VenvDir "Scripts\python.exe"
$PipExe    = Join-Path $VenvDir "Scripts\pip.exe"
$LaunchBat = Join-Path $AppDir "Studorge.bat"         # generated launcher

# Setup.bat lives in scripts\windows\; source root is two levels up
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path
$SrcRoot   = Split-Path (Split-Path $ScriptDir)        # project root

# ── helpers ───────────────────────────────────────────────────
function Banner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║      Studorge AI 学习助手  —  安装程序       ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}
function Step([int]$n, [string]$msg) { Write-Host "  [$n/8] $msg" -ForegroundColor Yellow }
function OK([string]$msg)            { Write-Host "  ✓  $msg"   -ForegroundColor Green }
function Warn([string]$msg)          { Write-Host "  ⚠  $msg"   -ForegroundColor DarkYellow }
function Fail([string]$msg)          { Write-Host "  ✗  $msg"   -ForegroundColor Red }

# ── find Python 3.10+ ─────────────────────────────────────────
function Find-Python {
    $candidates = @(
        "python3.13","python3.12","python3.11","python3.10",
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
        "$env:ProgramFiles\Python313\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "$env:ProgramFiles\Python311\python.exe",
        "$env:ProgramFiles\Python310\python.exe",
        "python3","python"
    )
    foreach ($cmd in $candidates) {
        try {
            $ver = (& $cmd --version 2>&1 | Out-String).Trim()
            if ($ver -match "Python (\d+)\.(\d+)") {
                [int]$major = $Matches[1]; [int]$minor = $Matches[2]
                if ($major -eq 3 -and $minor -ge 10) { return $cmd }
            }
        } catch {}
    }
    return $null
}

# ═══════════════════════════ MAIN ════════════════════════════
Banner

# ── 1. Python ─────────────────────────────────────────────────
Step 1 "检查 Python 3.10+ 环境..."
$py = Find-Python
if (-not $py) {
    Fail "未找到 Python 3.10 或更高版本"
    Write-Host ""
    Write-Host "  请前往以下地址下载并安装 Python：" -ForegroundColor White
    Write-Host "  https://www.python.org/downloads/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ⚠  安装时请勾选 'Add Python to PATH'" -ForegroundColor Yellow
    Write-Host ""
    Start-Process "https://www.python.org/downloads/"
    Read-Host "  安装完成后，按 Enter 重新检测..."
    $py = Find-Python
    if (-not $py) {
        Fail "仍未找到 Python，请重启本安装程序后重试"
        Read-Host "按 Enter 退出"
        exit 1
    }
}
$verStr = (& $py --version 2>&1 | Out-String).Trim()
OK "使用 $verStr  ($py)"

# ── 2. 创建目录 ───────────────────────────────────────────────
Step 2 "创建应用目录..."
foreach ($dir in @($SrcDir, $DataDir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}
OK $AppDir

# ── 3. 复制源文件 ─────────────────────────────────────────────
Step 3 "复制程序文件..."
foreach ($folder in @("backend","frontend")) {
    $dst = Join-Path $SrcDir $folder
    if (Test-Path (Join-Path $SrcRoot $folder)) {
        Copy-Item -Path (Join-Path $SrcRoot $folder) -Destination $dst -Recurse -Force
    }
}
foreach ($f in @("requirements.txt","run.py",".env.example")) {
    $src = Join-Path $SrcRoot $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $SrcDir $f) -Force }
}
OK "文件已复制到 $SrcDir"

# ── 4. 虚拟环境 ───────────────────────────────────────────────
Step 4 "创建 Python 虚拟环境..."
if (-not (Test-Path $PyExe)) {
    Write-Host "  (首次创建，请稍候…)" -ForegroundColor Gray
    & $py -m venv $VenvDir
    OK "虚拟环境已创建"
} else {
    OK "虚拟环境已存在，跳过"
}

# ── 5. 安装依赖 ───────────────────────────────────────────────
Step 5 "安装 Python 依赖 (首次约需 3–5 分钟)..."
Write-Host "  (可能下载较多文件，请保持网络连接)" -ForegroundColor Gray
& $PipExe install --upgrade pip --quiet
& $PipExe install -r (Join-Path $SrcDir "requirements.txt")
if ($LASTEXITCODE -ne 0) { Fail "依赖安装失败，请检查网络并重试"; Read-Host; exit 1 }
OK "依赖安装完成"

# ── 6. API 密钥配置 ───────────────────────────────────────────
Step 6 "配置 API 密钥..."
$envFile = Join-Path $SrcDir ".env"
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $SrcDir ".env.example") $envFile
}

$envContent = Get-Content $envFile -Raw
$keyOk = ($envContent -match "OPENAI_API_KEY=(?!your-api-key-here)\S+")

if (-not $keyOk) {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │  需要配置您自己的 API Key 才能使用 Studorge          │" -ForegroundColor Yellow
    Write-Host "  │  即将打开配置文件，请填写：                          │" -ForegroundColor Yellow
    Write-Host "  │                                                       │" -ForegroundColor Yellow
    Write-Host "  │    OPENAI_API_KEY=sk-...您的密钥...                  │" -ForegroundColor Yellow
    Write-Host "  │                                                       │" -ForegroundColor Yellow
    Write-Host "  │  保存并关闭记事本后，安装将继续。                    │" -ForegroundColor Yellow
    Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    Start-Process notepad.exe -ArgumentList $envFile -Wait

    $envContent = Get-Content $envFile -Raw
    if ($envContent -match "OPENAI_API_KEY=your-api-key-here" -or
        $envContent -notmatch "OPENAI_API_KEY=\S+") {
        Warn "未检测到有效的 API Key，启动后功能可能异常"
        Warn "请稍后编辑：$envFile"
    } else {
        OK "API Key 已配置"
    }
} else {
    OK "API Key 已存在"
}

# ── 7. 生成启动脚本 ───────────────────────────────────────────
Step 7 "生成启动文件..."

# The .bat that the desktop shortcut points to
@"
@echo off
chcp 65001 > nul
title Studorge
set "STUDORGE_DATA_DIR=$DataDir"
cd /d "$SrcDir"

:: ── Check API key ──────────────────────────────────────────────
findstr /i "OPENAI_API_KEY=your-api-key-here" ".env" > nul 2>&1
if %errorlevel%==0 (
    echo.
    echo  [!] 您尚未配置 OPENAI_API_KEY
    echo      请用记事本打开并编辑：
    echo      $envFile
    echo.
    notepad "$envFile"
    pause
    exit /b 1
)

:: ── Kill existing server on port 8000 ─────────────────────────
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":8000 "') do (
    taskkill /PID %%a /F > nul 2>&1
)

:: ── Start server ───────────────────────────────────────────────
echo  Starting Studorge...
"$PyExe" run.py
"@ | Set-Content -Path $LaunchBat -Encoding UTF8

OK "启动脚本：$LaunchBat"

# ── 8. 桌面快捷方式 ───────────────────────────────────────────
Step 8 "创建桌面快捷方式..."
$desktop   = [Environment]::GetFolderPath("Desktop")
$lnkPath   = Join-Path $desktop "Studorge.lnk"

$wsh = New-Object -ComObject WScript.Shell
$sc  = $wsh.CreateShortcut($lnkPath)
$sc.TargetPath      = "cmd.exe"
$sc.Arguments       = "/c `"$LaunchBat`""
$sc.WorkingDirectory = $SrcDir
$sc.Description     = "Studorge AI 学习助手"
$sc.WindowStyle     = 1
# Use icon from frontend if available
$iconSrc = Join-Path $SrcDir "frontend\favicon.ico"
if (Test-Path $iconSrc) { $sc.IconLocation = $iconSrc }
$sc.Save()
OK "桌面快捷方式：$lnkPath"

# ── Done ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅  安装完成！" -ForegroundColor Green
Write-Host ""
Write-Host "  · 双击桌面的 Studorge 图标启动应用" -ForegroundColor White
Write-Host "  · 配置文件位置（可随时修改 API Key）：" -ForegroundColor White
Write-Host "    $envFile" -ForegroundColor Cyan
Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

$ans = Read-Host "  是否现在立即启动 Studorge？(Y/N)"
if ($ans -match "^[Yy]") {
    Start-Process cmd.exe -ArgumentList "/c `"$LaunchBat`""
}
