@echo off
chcp 65001 >nul
cd /d "%~dp0"

if not exist ".venv\Scripts\activate.bat" (
    echo 未找到虚拟环境：%CD%\.venv
    echo 请先在项目目录创建并安装依赖。
    pause
    exit /b 1
)

call ".venv\Scripts\activate.bat"
python -m deeptutor_cli.main start

pause
