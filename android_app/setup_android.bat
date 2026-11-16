@echo off
REM Double-click to set up and build the Android app. See setup_android.ps1 for options.
REM To use options, run from a terminal:  setup_android.bat -Org com.yourname
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_android.ps1" %*
echo.
pause
