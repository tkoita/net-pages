@echo off
rem =====================================================================
rem  ネットワーク応用  第1回 課題  自己採点（Windows・ダブルクリック用）
rem
rem  先に、別のウィンドウで EchoServer を起動したままにしてください：
rem      java -jar EchoServer.jar 40001
rem =====================================================================
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check.ps1"
echo.
pause
