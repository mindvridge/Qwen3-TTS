@echo off
echo ========================================
echo Qwen3-TTS Server
echo ========================================
echo.

REM Check if virtual environment exists
if exist "venv\Scripts\activate.bat" (
    echo Activating virtual environment...
    call venv\Scripts\activate.bat
)

echo Starting server...
python run_server.py

pause
