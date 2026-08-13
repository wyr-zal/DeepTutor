@echo off
setlocal

REM Run from this .bat file directory so .\quick-deploy.ps1 is resolved correctly.
cd /d "%~dp0"

if not exist "quick-deploy.ps1" (
  echo [ERROR] quick-deploy.ps1 not found in: %cd%
  echo Please copy the full PowerShell quick deploy command from docs\LOCAL_BUILD_PATCH.md into quick-deploy.ps1 first.
  pause
  exit /b 1
)

echo [INFO] Running quick-deploy.ps1 ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\quick-deploy.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] quick-deploy.ps1 failed with exit code %EXIT_CODE%.
  pause
  exit /b %EXIT_CODE%
)

echo.
echo [OK] quick-deploy.ps1 completed successfully.
pause
exit /b 0
