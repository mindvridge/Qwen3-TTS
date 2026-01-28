@echo off
title Qwen3-TTS Server

echo ============================================
echo  Qwen3-TTS Server Launcher
echo ============================================
echo.

echo [1/2] Stopping existing server...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":8000" ^| findstr "LISTENING"') do (
    echo   - Killing PID %%a
    taskkill /PID %%a /F >nul 2>&1
)
timeout /t 2 /nobreak >nul
echo   Done.
echo.

echo [2/2] Starting server...
echo   Local:  http://localhost:8000
echo   LAN:    http://172.16.10.200:8000
echo   Web UI: http://172.16.10.200:8000/ui
echo.
echo ============================================
echo  Press Ctrl+C to stop
echo ============================================
echo.

cd /d %~dp0
python server.py

pause
