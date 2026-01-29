#!/bin/bash
# =============================================================
# Stop all Qwen3-TTS and NewAvata servers
# =============================================================

echo "Stopping all servers..."

# Stop tmux sessions
if command -v tmux &> /dev/null; then
    tmux kill-session -t tts 2>/dev/null && echo "  Stopped TTS tmux session"
    tmux kill-session -t newavata 2>/dev/null && echo "  Stopped NewAvata tmux session"
fi

# Kill Python servers on ports 8000 and 8001
pkill -f "python server.py" 2>/dev/null && echo "  Stopped TTS server"
pkill -f "run_server.sh" 2>/dev/null && echo "  Stopped NewAvata server"

# Kill by port
fuser -k 8000/tcp 2>/dev/null && echo "  Freed port 8000"
fuser -k 8001/tcp 2>/dev/null && echo "  Freed port 8001"

echo "All servers stopped."
