#!/bin/bash
# =============================================================
# Qwen3-TTS + NewAvata (Lip-sync) Full Stack Start Script
# For Elice AI Cloud (A100 GPU)
# =============================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEWAVATA_DIR="${SCRIPT_DIR}/../NewAvata"

echo ""
echo "==========================================="
echo "  Qwen3-TTS + NewAvata Full Stack Setup"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "==========================================="

# Check GPU memory to recommend mode
echo -e "\n${YELLOW}[1/7] Checking GPU...${NC}"
GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
if [ -n "$GPU_MEM" ]; then
    echo -e "  GPU Memory: ${CYAN}${GPU_MEM} MB${NC}"
    if [ "$GPU_MEM" -lt 50000 ]; then
        echo -e "  ${YELLOW}Warning: A100 40GB detected. Memory may be tight.${NC}"
        echo -e "  ${YELLOW}Recommendation: Use A100 80GB for TTS + Lip-sync${NC}"
    else
        echo -e "  ${GREEN}A100 80GB detected. Full stack supported.${NC}"
    fi
else
    echo -e "  ${RED}Warning: Could not detect GPU${NC}"
fi

# Step 1: Setup Qwen3-TTS
echo -e "\n${YELLOW}[2/7] Setting up Qwen3-TTS...${NC}"
cd "$SCRIPT_DIR"

# Install TTS dependencies
if [ ! -f ".tts_deps_installed" ]; then
    echo -e "  Installing TTS dependencies..."
    pip install -r requirements.txt --quiet --disable-pip-version-check 2>/dev/null
    touch .tts_deps_installed
    echo -e "  ${GREEN}TTS dependencies installed${NC}"
else
    echo -e "  ${GREEN}TTS dependencies already installed${NC}"
fi

# Install Flash Attention
echo -e "\n${YELLOW}[3/7] Checking Flash Attention...${NC}"
if python -c "import flash_attn" 2>/dev/null; then
    echo -e "  ${GREEN}Flash Attention is ready${NC}"
else
    echo -e "  Installing Flash Attention..."
    # Try pre-built wheel first
    FA_WHEEL_URL="https://github.com/mindvridge/Qwen3-TTS/releases/download/flash-attn-wheels/flash_attn-2.8.3-cp310-cp310-linux_x86_64.whl"
    WHEEL_DIR="/tmp/fa_wheel"
    mkdir -p "$WHEEL_DIR"
    if wget -q -O "${WHEEL_DIR}/flash_attn.whl" "$FA_WHEEL_URL" 2>/dev/null; then
        pip install "${WHEEL_DIR}/flash_attn.whl" --quiet 2>/dev/null && \
            echo -e "  ${GREEN}Flash Attention installed from wheel${NC}" || \
            echo -e "  ${YELLOW}Flash Attention wheel install failed${NC}"
    fi
    rm -rf "$WHEEL_DIR"
fi

# Configure TTS .env
echo -e "\n${YELLOW}[4/7] Configuring TTS environment...${NC}"
if [ ! -f ".env" ]; then
    cp .env.example .env
fi

# Enable video mode with NewAvata API
sed -i 's/ENABLE_VIDEO=false/ENABLE_VIDEO=true/' .env 2>/dev/null || true
sed -i 's/USE_NEWAVATA_API=false/USE_NEWAVATA_API=true/' .env 2>/dev/null || true
sed -i 's/TTS_USE_FLASH_ATTENTION=false/TTS_USE_FLASH_ATTENTION=true/' .env 2>/dev/null || true

# Comment out empty model paths
sed -i 's/^MODEL_0_6B_BASE=$/# MODEL_0_6B_BASE=/' .env 2>/dev/null || true
sed -i 's/^MODEL_1_7B_BASE=$/# MODEL_1_7B_BASE=/' .env 2>/dev/null || true

echo -e "  ${GREEN}TTS configured for API mode${NC}"
echo -e "    ENABLE_VIDEO=true"
echo -e "    USE_NEWAVATA_API=true"

# Step 2: Setup NewAvata
echo -e "\n${YELLOW}[5/7] Setting up NewAvata...${NC}"

if [ ! -d "$NEWAVATA_DIR" ]; then
    echo -e "  Cloning NewAvata repository..."
    cd "$SCRIPT_DIR/.."
    git clone https://github.com/mindvridge/NewAvata.git
    echo -e "  ${GREEN}NewAvata cloned${NC}"
else
    echo -e "  ${GREEN}NewAvata already exists${NC}"
    cd "$NEWAVATA_DIR"
    git pull --ff-only 2>/dev/null || echo -e "  ${CYAN}Using current NewAvata code${NC}"
fi

# Run NewAvata deployment
NEWAVATA_APP_DIR="$NEWAVATA_DIR/realtime-interview-avatar"
if [ -d "$NEWAVATA_APP_DIR" ]; then
    cd "$NEWAVATA_APP_DIR"

    if [ ! -f ".newavata_deployed" ]; then
        echo -e "  Running NewAvata A100 deployment..."
        if [ -f "deploy_a100.sh" ]; then
            chmod +x deploy_a100.sh
            ./deploy_a100.sh
            touch .newavata_deployed
            echo -e "  ${GREEN}NewAvata deployed${NC}"
        else
            echo -e "  ${YELLOW}deploy_a100.sh not found, skipping deployment${NC}"
        fi
    else
        echo -e "  ${GREEN}NewAvata already deployed${NC}"
    fi
else
    echo -e "  ${RED}NewAvata app directory not found${NC}"
fi

# Create avatars directory
echo -e "\n${YELLOW}[6/7] Setting up avatars...${NC}"
mkdir -p "$SCRIPT_DIR/avatars"
AVATAR_COUNT=$(ls -1 "$SCRIPT_DIR/avatars/"*.{jpg,jpeg,png} 2>/dev/null | wc -l)
if [ "$AVATAR_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}Found $AVATAR_COUNT avatar(s) in avatars/${NC}"
else
    echo -e "  ${YELLOW}No avatars found. Add images to avatars/ folder${NC}"
fi

# Start both servers
echo -e "\n${YELLOW}[7/7] Starting servers...${NC}"

# Check if tmux is available
if command -v tmux &> /dev/null; then
    echo -e "  Using tmux for multi-server management"

    # Kill existing sessions
    tmux kill-session -t tts 2>/dev/null || true
    tmux kill-session -t newavata 2>/dev/null || true

    # Start NewAvata server in tmux
    if [ -d "$NEWAVATA_APP_DIR" ] && [ -f "$NEWAVATA_APP_DIR/run_server.sh" ]; then
        tmux new-session -d -s newavata -c "$NEWAVATA_APP_DIR" "bash run_server.sh"
        echo -e "  ${GREEN}NewAvata server started (tmux session: newavata)${NC}"
        echo -e "    Port: ${CYAN}8001${NC}"
    fi

    # Wait for NewAvata to initialize
    echo -e "  Waiting for NewAvata to initialize (10s)..."
    sleep 10

    # Start TTS server in foreground
    cd "$SCRIPT_DIR"
    echo ""
    echo "==========================================="
    echo -e "  ${GREEN}Full Stack Ready!${NC}"
    echo "==========================================="
    echo -e "  TTS Server:     ${CYAN}http://0.0.0.0:8000${NC}"
    echo -e "  NewAvata:       ${CYAN}http://0.0.0.0:8001${NC}"
    echo -e "  API Docs:       ${CYAN}http://0.0.0.0:8000/docs${NC}"
    echo -e "  Web UI:         ${CYAN}http://0.0.0.0:8000/ui${NC}"
    echo ""
    echo -e "  ${YELLOW}Tmux commands:${NC}"
    echo -e "    tmux attach -t newavata  # View NewAvata logs"
    echo -e "    tmux kill-session -t newavata  # Stop NewAvata"
    echo ""

    python server.py

else
    # No tmux - use background process
    echo -e "  ${YELLOW}tmux not found, using background processes${NC}"

    # Start NewAvata in background
    if [ -d "$NEWAVATA_APP_DIR" ] && [ -f "$NEWAVATA_APP_DIR/run_server.sh" ]; then
        cd "$NEWAVATA_APP_DIR"
        nohup bash run_server.sh > /tmp/newavata.log 2>&1 &
        NEWAVATA_PID=$!
        echo -e "  ${GREEN}NewAvata started (PID: $NEWAVATA_PID)${NC}"
        echo -e "    Log: /tmp/newavata.log"
    fi

    # Wait for NewAvata
    echo -e "  Waiting for NewAvata to initialize (10s)..."
    sleep 10

    # Start TTS server
    cd "$SCRIPT_DIR"
    echo ""
    echo "==========================================="
    echo -e "  ${GREEN}Full Stack Ready!${NC}"
    echo "==========================================="
    echo -e "  TTS Server:     ${CYAN}http://0.0.0.0:8000${NC}"
    echo -e "  NewAvata:       ${CYAN}http://0.0.0.0:8001${NC}"
    echo -e "  API Docs:       ${CYAN}http://0.0.0.0:8000/docs${NC}"
    echo ""
    echo -e "  ${YELLOW}To stop NewAvata:${NC} kill $NEWAVATA_PID"
    echo -e "  ${YELLOW}NewAvata logs:${NC} tail -f /tmp/newavata.log"
    echo ""

    python server.py
fi
