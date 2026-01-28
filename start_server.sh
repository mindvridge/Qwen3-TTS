#!/bin/bash
# Qwen3-TTS Server Launcher for Linux
# Usage: ./start_server.sh

set -e

echo "============================================"
echo " Qwen3-TTS Server Launcher"
echo "============================================"
echo ""

# Activate virtual environment if exists
if [ -d "venv" ]; then
    echo "Activating virtual environment..."
    source venv/bin/activate
fi

# Kill existing server on port 8000
echo "[1/2] Stopping existing server..."
if lsof -ti:8000 >/dev/null 2>&1; then
    lsof -ti:8000 | xargs kill -9 2>/dev/null || true
    echo "  - Killed existing process on port 8000"
else
    echo "  - No existing server found"
fi
sleep 2
echo "  Done."
echo ""

# Start server
echo "[2/2] Starting server..."
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo "  Local:  http://localhost:8000"
echo "  LAN:    http://$LOCAL_IP:8000"
echo "  Web UI: http://$LOCAL_IP:8000/ui"
echo ""
echo "============================================"
echo " Press Ctrl+C to stop"
echo "============================================"
echo ""

# Run server
python server.py
