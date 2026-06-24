@echo off
setlocal EnableExtensions
chcp 65001 >nul
set "BASE=%~dp0"
set "SCRIPT=%BASE%setup-codex-sub2api.ps1"
set "LOG=%BASE%install-error.log"

echo [%date% %time%] Starting Codex Sub2API installer > "%LOG%"
echo Script: %SCRIPT% >> "%LOG%"

if not exist "%SCRIPT%" (
  echo Cannot find setup-codex-sub2api.ps1 >> "%LOG%"
  echo.
  echo ???? setup-codex-sub2api.ps1??????? zip?????????????
  echo ??: "%LOG%"
  pause
  exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo powershell.exe not found >> "%LOG%"
  echo.
  echo ?????? Windows PowerShell?????????
  echo ??: "%LOG%"
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -Command "try { Get-ChildItem -LiteralPath '%BASE%' -File | Unblock-File -ErrorAction SilentlyContinue; & '%SCRIPT%' -Gui *>> '%LOG%'; exit $LASTEXITCODE } catch { $_ | Out-String | Add-Content -LiteralPath '%LOG%'; Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue; [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '???????', 'OK', 'Error') | Out-Null; exit 1 }"
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
  echo.
  echo ???????????: %EC%
  echo ????: "%LOG%"
  echo ?? install-error.log ????????
  pause
  exit /b %EC%
)
endlocal
