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
GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '[:space:]')

# Check if GPU_MEM is a valid number
if [[ "$GPU_MEM" =~ ^[0-9]+$ ]]; then
    echo -e "  GPU Memory: ${CYAN}${GPU_MEM} MB${NC}"
    if [ "$GPU_MEM" -lt 50000 ]; then
        echo -e "  ${YELLOW}Warning: A100 40GB detected. Memory may be tight.${NC}"
        echo -e "  ${YELLOW}Recommendation: Use A100 80GB for TTS + Lip-sync${NC}"
    else
        echo -e "  ${GREEN}A100 80GB detected. Full stack supported.${NC}"
    fi
else
    # Try to get GPU name instead
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    if [ -n "$GPU_NAME" ]; then
        echo -e "  GPU: ${CYAN}${GPU_NAME}${NC}"
        if [[ "$GPU_NAME" == *"80GB"* ]]; then
            echo -e "  ${GREEN}A100 80GB detected. Full stack supported.${NC}"
        elif [[ "$GPU_NAME" == *"A100"* ]]; then
            echo -e "  ${GREEN}A100 detected. Proceeding with setup.${NC}"
        else
            echo -e "  ${YELLOW}GPU detected: $GPU_NAME${NC}"
        fi
    else
        echo -e "  ${YELLOW}Warning: Could not detect GPU memory (permission issue)${NC}"
        echo -e "  ${CYAN}Proceeding with setup anyway...${NC}"
    fi
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
            # Run deploy_a100.sh with auto-yes for GFPGAN prompt
            yes | ./deploy_a100.sh || true
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

# Fix missing models (MuseTalk, FaceParse)
echo -e "\n${YELLOW}[5.5/7] Checking and fixing missing models...${NC}"
if [ -d "$NEWAVATA_APP_DIR" ]; then
    cd "$NEWAVATA_APP_DIR"

    # Activate venv if exists
    if [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
    fi

    MODELS_DIR="$NEWAVATA_APP_DIR/models"

    # Fix 1: MuseTalk model (pytorch_model.bin)
    MUSETALK_MODEL="$MODELS_DIR/musetalk/pytorch_model.bin"
    if [ ! -f "$MUSETALK_MODEL" ]; then
        echo -e "  Downloading MuseTalk model..."
        mkdir -p "$MODELS_DIR/musetalk"
        python -c "
from huggingface_hub import hf_hub_download
import shutil
import os

# Download MuseTalk pytorch model
try:
    path = hf_hub_download(
        repo_id='TMElyralab/MuseTalk',
        filename='pytorch_model.bin',
        local_dir='$MODELS_DIR/musetalk',
        local_dir_use_symlinks=False
    )
    print(f'  Downloaded: {path}')
except Exception as e:
    # Try alternative: download musetalk.pt
    try:
        path = hf_hub_download(
            repo_id='TMElyralab/MuseTalk',
            filename='musetalk/pytorch_model.bin',
            local_dir='$MODELS_DIR',
            local_dir_use_symlinks=False
        )
        print(f'  Downloaded: {path}')
    except Exception as e2:
        print(f'  Warning: Could not download MuseTalk model: {e2}')
" 2>/dev/null && echo -e "  ${GREEN}MuseTalk model downloaded${NC}" || echo -e "  ${YELLOW}MuseTalk model download skipped${NC}"
    else
        echo -e "  ${GREEN}MuseTalk model already exists${NC}"
    fi

    # Fix 2: FaceParse BiSeNet model (79999_iter.pth)
    FACEPARSE_MODEL="$MODELS_DIR/face-parse-bisent/79999_iter.pth"
    if [ ! -f "$FACEPARSE_MODEL" ]; then
        echo -e "  Downloading FaceParse model..."
        mkdir -p "$MODELS_DIR/face-parse-bisent"

        # Try multiple sources
        FACEPARSE_URLS=(
            "https://github.com/zllrunning/face-parsing.PyTorch/releases/download/v1.0/79999_iter.pth"
            "https://huggingface.co/lllyasviel/fooocus_inpaint/resolve/main/fooocus_inpaint_head.pth"
        )

        # Method 1: Direct download with wget
        if wget -q --show-progress -O "$FACEPARSE_MODEL" "https://github.com/zllrunning/face-parsing.PyTorch/releases/download/v1.0/79999_iter.pth" 2>/dev/null; then
            echo -e "  ${GREEN}FaceParse model downloaded${NC}"
        else
            # Method 2: Try with Python
            python -c "
import urllib.request
import os

urls = [
    'https://github.com/zllrunning/face-parsing.PyTorch/releases/download/v1.0/79999_iter.pth',
]

output = '$FACEPARSE_MODEL'
os.makedirs(os.path.dirname(output), exist_ok=True)

for url in urls:
    try:
        print(f'  Trying: {url}')
        urllib.request.urlretrieve(url, output)
        if os.path.getsize(output) > 1000000:  # > 1MB
            print(f'  Success!')
            break
    except Exception as e:
        print(f'  Failed: {e}')
        continue
" 2>/dev/null && echo -e "  ${GREEN}FaceParse model downloaded${NC}" || echo -e "  ${YELLOW}FaceParse model download failed - may need manual download${NC}"
        fi
    else
        echo -e "  ${GREEN}FaceParse model already exists${NC}"
    fi

    # Deactivate venv
    deactivate 2>/dev/null || true
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
