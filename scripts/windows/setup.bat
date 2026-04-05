@echo off
chcp 65001 > nul
echo.
echo  ╔══════════════════════════════════════════════╗
echo  ║      Studorge AI 学习助手  —  安装程序       ║
echo  ╚══════════════════════════════════════════════╝
echo.
echo  正在启动安装程序，请稍候...
echo.

:: Run the PowerShell installer (no admin required)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer.ps1"

if %errorlevel% neq 0 (
    echo.
    echo  安装过程中出现错误，请查看上方提示。
    pause
)
