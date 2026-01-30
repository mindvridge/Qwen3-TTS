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

# =============================================
# PRE-STEP: Stop existing servers and update code
# =============================================
echo -e "\n${CYAN}[Pre] Stopping existing servers...${NC}"

# Kill existing tmux sessions
if command -v tmux &> /dev/null; then
    tmux kill-session -t tts 2>/dev/null && echo -e "  ${GREEN}Stopped TTS server${NC}" || true
    tmux kill-session -t newavata 2>/dev/null && echo -e "  ${GREEN}Stopped NewAvata server${NC}" || true
fi

# Kill processes on ports
if command -v fuser &> /dev/null; then
    fuser -k 8000/tcp 2>/dev/null && echo -e "  ${GREEN}Freed port 8000${NC}" || true
    fuser -k 8001/tcp 2>/dev/null && echo -e "  ${GREEN}Freed port 8001${NC}" || true
fi

sleep 2

# Auto-update Qwen3-TTS from GitHub
echo -e "\n${YELLOW}[0/7] Updating Qwen3-TTS...${NC}"
cd "$SCRIPT_DIR"
if git rev-parse --git-dir > /dev/null 2>&1; then
    git pull --ff-only 2>/dev/null && \
        echo -e "  ${GREEN}Qwen3-TTS updated${NC}" || \
        echo -e "  ${CYAN}Using current Qwen3-TTS code${NC}"
else
    echo -e "  ${CYAN}Not a git repository, skipping update${NC}"
fi

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

# Install TTS dependencies (verify fastapi is actually installed)
FASTAPI_OK=false
if python -c "import fastapi" 2>/dev/null; then
    FASTAPI_OK=true
fi

if [ ! -f ".tts_deps_installed" ] || [ "$FASTAPI_OK" = false ]; then
    if [ "$FASTAPI_OK" = false ]; then
        echo -e "  ${YELLOW}fastapi not found, reinstalling dependencies...${NC}"
        rm -f .tts_deps_installed
    else
        echo -e "  Installing TTS dependencies..."
    fi

    # Install with verbose output to catch errors
    pip install -r requirements.txt --disable-pip-version-check 2>&1 | tail -5

    # Verify installation
    if python -c "import fastapi; import uvicorn; import torch" 2>/dev/null; then
        touch .tts_deps_installed
        echo -e "  ${GREEN}TTS dependencies installed and verified${NC}"
    else
        echo -e "  ${RED}Dependency installation failed!${NC}"
        echo -e "  ${YELLOW}Trying individual packages...${NC}"
        pip install fastapi uvicorn python-dotenv soundfile numpy --quiet
        pip install torch --quiet

        if python -c "import fastapi" 2>/dev/null; then
            touch .tts_deps_installed
            echo -e "  ${GREEN}Core dependencies installed${NC}"
        else
            echo -e "  ${RED}FATAL: Cannot install fastapi. Check pip and network.${NC}"
            exit 1
        fi
    fi
else
    echo -e "  ${GREEN}TTS dependencies verified (fastapi OK)${NC}"
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
    FA_INSTALLED=false
    if wget -q -O "${WHEEL_DIR}/flash_attn.whl" "$FA_WHEEL_URL" 2>/dev/null; then
        if pip install "${WHEEL_DIR}/flash_attn.whl" --quiet 2>/dev/null; then
            echo -e "  ${GREEN}Flash Attention installed from wheel${NC}"
            FA_INSTALLED=true
        fi
    fi
    rm -rf "$WHEEL_DIR"

    # If Flash Attention failed, disable it in .env
    if [ "$FA_INSTALLED" = false ]; then
        echo -e "  ${YELLOW}Flash Attention install failed, disabling in .env${NC}"
        # Update .env to disable flash attention
        if [ -f ".env" ]; then
            sed -i 's/TTS_USE_FLASH_ATTENTION=true/TTS_USE_FLASH_ATTENTION=false/g' .env 2>/dev/null || true
        fi
        # Also set environment variable for current session
        export TTS_USE_FLASH_ATTENTION=false
        echo -e "  ${CYAN}Will use SDPA (scaled dot-product attention) instead${NC}"
    fi
fi

# Install system dependencies (sox, ffmpeg)
echo -e "\n${YELLOW}[3.5/7] Installing system dependencies...${NC}"
if ! command -v sox &> /dev/null || ! command -v ffmpeg &> /dev/null; then
    echo -e "  Installing sox and ffmpeg..."
    sudo apt-get update -qq 2>/dev/null
    sudo apt-get install -y -qq sox ffmpeg 2>/dev/null && \
        echo -e "  ${GREEN}sox and ffmpeg installed${NC}" || \
        echo -e "  ${YELLOW}Could not install sox/ffmpeg (may need manual install)${NC}"
else
    echo -e "  ${GREEN}sox and ffmpeg already installed${NC}"
fi

# Configure TTS .env
echo -e "\n${YELLOW}[4/7] Configuring TTS environment...${NC}"
if [ ! -f ".env" ]; then
    cp .env.example .env
fi

# Force set video API mode (more robust method)
# Remove existing entries and add new ones
grep -v "^ENABLE_VIDEO=" .env > .env.tmp 2>/dev/null || cp .env .env.tmp
grep -v "^USE_NEWAVATA_API=" .env.tmp > .env.tmp2 2>/dev/null || cp .env.tmp .env.tmp2
grep -v "^NEWAVATA_API_URL=" .env.tmp2 > .env.tmp3 2>/dev/null || cp .env.tmp2 .env.tmp3
grep -v "^TTS_USE_FLASH_ATTENTION=" .env.tmp3 > .env.tmp4 2>/dev/null || cp .env.tmp3 .env.tmp4
grep -v "^MODEL_0_6B_BASE=$" .env.tmp4 > .env.tmp5 2>/dev/null || cp .env.tmp4 .env.tmp5
grep -v "^MODEL_1_7B_BASE=$" .env.tmp5 > .env 2>/dev/null || cp .env.tmp5 .env
rm -f .env.tmp .env.tmp2 .env.tmp3 .env.tmp4 .env.tmp5

# Add required settings
echo "" >> .env
echo "# Auto-configured by start_full.sh" >> .env
echo "ENABLE_VIDEO=true" >> .env
echo "USE_NEWAVATA_API=true" >> .env
echo "NEWAVATA_API_URL=http://localhost:8001" >> .env
echo "TTS_USE_FLASH_ATTENTION=true" >> .env

echo -e "  ${GREEN}TTS configured for API mode${NC}"
echo -e "    ENABLE_VIDEO=true"
echo -e "    USE_NEWAVATA_API=true"
echo -e "    NEWAVATA_API_URL=http://localhost:8001"

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
    # Run in subshell to isolate venv activation
    (
        cd "$NEWAVATA_APP_DIR"

        # Activate venv if exists
        if [ -f "venv/bin/activate" ]; then
            source venv/bin/activate
            echo -e "  ${GREEN}Activated NewAvata venv for model download${NC}"
        fi

        MODELS_DIR="$NEWAVATA_APP_DIR/models"

    # Fix 1: MuseTalk model (pytorch_model.bin + musetalk.json)
    MUSETALK_MODEL="$MODELS_DIR/musetalk/pytorch_model.bin"
    MUSETALK_JSON="$MODELS_DIR/musetalk/musetalk.json"
    NEED_MUSETALK=false

    # Check if models exist and are valid (pytorch_model.bin should be >1GB)
    if [ ! -f "$MUSETALK_MODEL" ] || [ ! -f "$MUSETALK_JSON" ]; then
        NEED_MUSETALK=true
        echo -e "  MuseTalk model not found, downloading..."
    elif [ $(stat -c%s "$MUSETALK_MODEL" 2>/dev/null || stat -f%z "$MUSETALK_MODEL" 2>/dev/null || echo 0) -lt 1000000000 ]; then
        echo -e "  ${YELLOW}MuseTalk model corrupted (too small), re-downloading...${NC}"
        rm -f "$MUSETALK_MODEL" "$MUSETALK_JSON"
        NEED_MUSETALK=true
    fi

    if [ "$NEED_MUSETALK" = true ]; then
        echo -e "  Downloading MuseTalk model files..."
        mkdir -p "$MODELS_DIR/musetalk"
        python -c "
from huggingface_hub import hf_hub_download
import shutil
import os

output_dir = '$MODELS_DIR/musetalk'
os.makedirs(output_dir, exist_ok=True)

# Download pytorch_model.bin (3.4GB)
model_file = os.path.join(output_dir, 'pytorch_model.bin')
if not os.path.exists(model_file):
    try:
        print('  Downloading pytorch_model.bin (3.4GB)...')
        path = hf_hub_download(
            repo_id='TMElyralab/MuseTalk',
            filename='musetalk/pytorch_model.bin'
        )
        shutil.copy(path, model_file)
        print(f'  Downloaded: pytorch_model.bin')
    except Exception as e:
        print(f'  Warning: pytorch_model.bin download failed: {e}')

# Download musetalk.json (748B)
json_file = os.path.join(output_dir, 'musetalk.json')
if not os.path.exists(json_file):
    try:
        print('  Downloading musetalk.json...')
        path = hf_hub_download(
            repo_id='TMElyralab/MuseTalk',
            filename='musetalk/musetalk.json'
        )
        shutil.copy(path, json_file)
        print(f'  Downloaded: musetalk.json')
    except Exception as e:
        print(f'  Warning: musetalk.json download failed: {e}')
" 2>/dev/null && echo -e "  ${GREEN}MuseTalk model downloaded${NC}" || echo -e "  ${YELLOW}MuseTalk model download skipped${NC}"
    else
        echo -e "  ${GREEN}MuseTalk model already exists (valid)${NC}"
    fi

    # Fix 2: FaceParse BiSeNet model (79999_iter.pth)
    FACEPARSE_MODEL="$MODELS_DIR/face-parse-bisent/79999_iter.pth"
    NEED_DOWNLOAD=false

    # Check if file exists, has valid size (>1MB), and can be loaded by torch
    if [ ! -f "$FACEPARSE_MODEL" ]; then
        NEED_DOWNLOAD=true
        echo -e "  FaceParse model not found, downloading..."
    elif [ $(stat -c%s "$FACEPARSE_MODEL" 2>/dev/null || stat -f%z "$FACEPARSE_MODEL" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo -e "  ${YELLOW}FaceParse model corrupted (too small), re-downloading...${NC}"
        rm -f "$FACEPARSE_MODEL"
        NEED_DOWNLOAD=true
    else
        # Validate by actually loading with torch (catches pickle corruption)
        echo -e "  Validating FaceParse model with torch.load..."
        if ! python -c "
import torch
try:
    torch.load('$FACEPARSE_MODEL', map_location='cpu', weights_only=False)
    print('  FaceParse model validation: OK')
except Exception as e:
    print(f'  FaceParse model validation FAILED: {e}')
    exit(1)
" 2>/dev/null; then
            echo -e "  ${YELLOW}FaceParse model corrupted (torch.load failed), re-downloading...${NC}"
            rm -f "$FACEPARSE_MODEL"
            NEED_DOWNLOAD=true
        fi
    fi

    if [ "$NEED_DOWNLOAD" = true ]; then
        mkdir -p "$MODELS_DIR/face-parse-bisent"

        # Download using Python with multiple fallback URLs
        python -c "
import os
import urllib.request
import shutil
import torch

output = '$FACEPARSE_MODEL'
os.makedirs(os.path.dirname(output), exist_ok=True)

# HuggingFace sources (verified working as of Jan 2026)
hf_sources = [
    ('vivym/face-parsing-bisenet', '79999_iter.pth'),
    ('ManyOtherFunctions/face-parse-bisent', '79999_iter.pth'),
    ('afrizalha/musetalk-models', 'face-parse-bisent/79999_iter.pth'),
]

downloaded = False
try:
    from huggingface_hub import hf_hub_download
    for repo_id, filename in hf_sources:
        try:
            print(f'  Trying HuggingFace: {repo_id}')
            path = hf_hub_download(repo_id=repo_id, filename=filename)
            shutil.copy(path, output)
            if os.path.getsize(output) > 1000000:
                torch.load(output, map_location='cpu', weights_only=False)
                print(f'  SUCCESS from {repo_id}!')
                downloaded = True
                break
        except Exception as e:
            print(f'  Failed: {e}')
            if os.path.exists(output):
                os.remove(output)
except ImportError:
    print('  huggingface_hub not available')

if not downloaded:
    print('  Warning: Could not download FaceParse model')
" 2>/dev/null && echo -e "  ${GREEN}FaceParse model downloaded${NC}" || echo -e "  ${YELLOW}FaceParse model download skipped${NC}"
    else
        echo -e "  ${GREEN}FaceParse model already exists (valid)${NC}"
    fi

    # Fix 3: SD-VAE model (required for MuseTalk VAE)
    SDVAE_CONFIG="$MODELS_DIR/sd-vae/config.json"
    SDVAE_BIN="$MODELS_DIR/sd-vae/diffusion_pytorch_model.bin"
    NEED_SDVAE=false

    # Check if models exist and diffusion_pytorch_model.bin is valid (>100MB)
    if [ ! -f "$SDVAE_CONFIG" ] || [ ! -f "$SDVAE_BIN" ]; then
        NEED_SDVAE=true
        echo -e "  SD-VAE model not found, downloading..."
    elif [ $(stat -c%s "$SDVAE_BIN" 2>/dev/null || stat -f%z "$SDVAE_BIN" 2>/dev/null || echo 0) -lt 100000000 ]; then
        echo -e "  ${YELLOW}SD-VAE model corrupted (too small), re-downloading...${NC}"
        rm -rf "$MODELS_DIR/sd-vae"
        NEED_SDVAE=true
    fi

    if [ "$NEED_SDVAE" = true ]; then
        mkdir -p "$MODELS_DIR/sd-vae"
        python -c "
from huggingface_hub import snapshot_download
import os

output_dir = '$MODELS_DIR/sd-vae'
os.makedirs(output_dir, exist_ok=True)

try:
    print('  Downloading stabilityai/sd-vae-ft-mse...')
    snapshot_download(
        repo_id='stabilityai/sd-vae-ft-mse',
        local_dir=output_dir,
        local_dir_use_symlinks=False
    )
    print('  SD-VAE downloaded!')
except Exception as e:
    print(f'  Warning: SD-VAE download failed: {e}')
" && echo -e "  ${GREEN}SD-VAE model downloaded${NC}" || echo -e "  ${YELLOW}SD-VAE model download skipped${NC}"
    else
        echo -e "  ${GREEN}SD-VAE model already exists (valid)${NC}"
    fi

    # Create symlinks for MuseTalk's expected model paths
    # MuseTalk looks for models in its own directory structure
    echo -e "  ${YELLOW}Setting up MuseTalk model symlinks...${NC}"
    MUSETALK_MODELS="$NEWAVATA_DIR/MuseTalk/models"
    mkdir -p "$MUSETALK_MODELS/musetalk" "$MUSETALK_MODELS/face-parse-bisent" "$MUSETALK_MODELS/sd-vae"

    # MuseTalk model symlink
    if [ -f "$MODELS_DIR/musetalk/pytorch_model.bin" ] && [ ! -f "$MUSETALK_MODELS/musetalk/pytorch_model.bin" ]; then
        ln -sf "$MODELS_DIR/musetalk/pytorch_model.bin" "$MUSETALK_MODELS/musetalk/pytorch_model.bin" 2>/dev/null || \
            cp "$MODELS_DIR/musetalk/pytorch_model.bin" "$MUSETALK_MODELS/musetalk/pytorch_model.bin"
        [ -f "$MODELS_DIR/musetalk/musetalk.json" ] && \
            (ln -sf "$MODELS_DIR/musetalk/musetalk.json" "$MUSETALK_MODELS/musetalk/musetalk.json" 2>/dev/null || \
             cp "$MODELS_DIR/musetalk/musetalk.json" "$MUSETALK_MODELS/musetalk/musetalk.json")
        echo -e "    ${GREEN}MuseTalk model linked${NC}"
    fi

    # FaceParse model symlink
    if [ -f "$FACEPARSE_MODEL" ] && [ ! -f "$MUSETALK_MODELS/face-parse-bisent/79999_iter.pth" ]; then
        ln -sf "$FACEPARSE_MODEL" "$MUSETALK_MODELS/face-parse-bisent/79999_iter.pth" 2>/dev/null || \
            cp "$FACEPARSE_MODEL" "$MUSETALK_MODELS/face-parse-bisent/79999_iter.pth"
        echo -e "    ${GREEN}FaceParse model linked${NC}"
    fi

    # SD-VAE model symlink
    if [ -d "$MODELS_DIR/sd-vae" ] && [ ! -f "$MUSETALK_MODELS/sd-vae/config.json" ]; then
        ln -sf "$MODELS_DIR/sd-vae/config.json" "$MUSETALK_MODELS/sd-vae/config.json" 2>/dev/null || \
            cp "$MODELS_DIR/sd-vae/config.json" "$MUSETALK_MODELS/sd-vae/config.json"
        ln -sf "$MODELS_DIR/sd-vae/diffusion_pytorch_model.bin" "$MUSETALK_MODELS/sd-vae/diffusion_pytorch_model.bin" 2>/dev/null || \
            cp "$MODELS_DIR/sd-vae/diffusion_pytorch_model.bin" "$MUSETALK_MODELS/sd-vae/diffusion_pytorch_model.bin"
        echo -e "    ${GREEN}SD-VAE model linked${NC}"
    fi

    # musetalkV15 symlink (NewAvata app.py looks for models in ./models/musetalkV15/)
    # NewAvata expects: unet.pth, musetalk.json, pytorch_model.bin
    if [ -f "$MODELS_DIR/musetalk/pytorch_model.bin" ]; then
        echo -e "  ${YELLOW}Creating musetalkV15 symlinks...${NC}"
        mkdir -p "$MODELS_DIR/musetalkV15"

        # Link pytorch_model.bin
        ln -sf "$MODELS_DIR/musetalk/pytorch_model.bin" "$MODELS_DIR/musetalkV15/pytorch_model.bin" 2>/dev/null || \
            cp "$MODELS_DIR/musetalk/pytorch_model.bin" "$MODELS_DIR/musetalkV15/pytorch_model.bin"

        # Link musetalk.json
        [ -f "$MODELS_DIR/musetalk/musetalk.json" ] && \
            (ln -sf "$MODELS_DIR/musetalk/musetalk.json" "$MODELS_DIR/musetalkV15/musetalk.json" 2>/dev/null || \
             cp "$MODELS_DIR/musetalk/musetalk.json" "$MODELS_DIR/musetalkV15/musetalk.json")

        # Download or link unet.pth (required by NewAvata's MuseTalk UNet)
        # unet.pth is often the same as pytorch_model.bin, but some repos have it separate
        if [ ! -f "$MODELS_DIR/musetalkV15/unet.pth" ]; then
            # Try to download unet.pth from HuggingFace first
            echo -e "    Downloading unet.pth..."
            python3 -c "
import os
import shutil

output = '$MODELS_DIR/musetalkV15/unet.pth'
os.makedirs(os.path.dirname(output), exist_ok=True)

# Try HuggingFace sources for unet.pth
sources = [
    ('TMElyralab/MuseTalk', 'models/musetalk/pytorch_model.bin'),
    ('netease-youdao/musetalk', 'models/musetalk/pytorch_model.bin'),
]

downloaded = False
try:
    from huggingface_hub import hf_hub_download
    for repo_id, filename in sources:
        try:
            print(f'  Trying: {repo_id}/{filename}')
            path = hf_hub_download(repo_id=repo_id, filename=filename)
            shutil.copy(path, output)
            print(f'  Downloaded unet.pth from {repo_id}')
            downloaded = True
            break
        except Exception as e:
            print(f'  Failed: {e}')
except ImportError:
    pass

# Fallback: copy from pytorch_model.bin (they're often the same weights)
if not downloaded:
    src = '$MODELS_DIR/musetalk/pytorch_model.bin'
    if os.path.exists(src):
        print(f'  Copying from pytorch_model.bin as fallback')
        shutil.copy(src, output)
        downloaded = True

exit(0 if downloaded else 1)
" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "    ${GREEN}unet.pth downloaded${NC}"
            else
                # Final fallback: symlink to pytorch_model.bin
                echo -e "    ${YELLOW}Using pytorch_model.bin as unet.pth${NC}"
                ln -sf "$MODELS_DIR/musetalk/pytorch_model.bin" "$MODELS_DIR/musetalkV15/unet.pth" 2>/dev/null || \
                    cp "$MODELS_DIR/musetalk/pytorch_model.bin" "$MODELS_DIR/musetalkV15/unet.pth"
            fi
        fi

        echo -e "    ${GREEN}musetalkV15 model linked${NC}"
    fi

    echo -e "  ${GREEN}MuseTalk model symlinks configured${NC}"

    )  # End of subshell for model downloads
    echo -e "  ${GREEN}Model check subshell completed${NC}"
fi

# CRITICAL: Ensure unet.pth exists (NewAvata requires this file)
# This runs outside the subshell to guarantee the file is created
NEWAVATA_DIR="${NEWAVATA_DIR:-$HOME/NewAvata}"
NEWAVATA_APP_DIR="$NEWAVATA_DIR/realtime-interview-avatar"
MODELS_DIR_CHECK="$NEWAVATA_APP_DIR/models"

if [ ! -f "$MODELS_DIR_CHECK/musetalkV15/unet.pth" ]; then
    echo -e "${YELLOW}[CRITICAL] Creating unet.pth for NewAvata...${NC}"
    mkdir -p "$MODELS_DIR_CHECK/musetalkV15"

    if [ -f "$MODELS_DIR_CHECK/musetalk/pytorch_model.bin" ]; then
        cp "$MODELS_DIR_CHECK/musetalk/pytorch_model.bin" "$MODELS_DIR_CHECK/musetalkV15/unet.pth"
        echo -e "  ${GREEN}unet.pth created from pytorch_model.bin${NC}"
    else
        echo -e "  ${RED}ERROR: pytorch_model.bin not found, cannot create unet.pth${NC}"
    fi
fi

# Also ensure musetalk.json and pytorch_model.bin exist in musetalkV15
if [ ! -f "$MODELS_DIR_CHECK/musetalkV15/musetalk.json" ] && [ -f "$MODELS_DIR_CHECK/musetalk/musetalk.json" ]; then
    cp "$MODELS_DIR_CHECK/musetalk/musetalk.json" "$MODELS_DIR_CHECK/musetalkV15/musetalk.json"
fi
if [ ! -f "$MODELS_DIR_CHECK/musetalkV15/pytorch_model.bin" ] && [ -f "$MODELS_DIR_CHECK/musetalk/pytorch_model.bin" ]; then
    cp "$MODELS_DIR_CHECK/musetalk/pytorch_model.bin" "$MODELS_DIR_CHECK/musetalkV15/pytorch_model.bin"
fi

# Final validation: Ensure all critical models are valid before proceeding
echo -e "\n${YELLOW}[5.5/7] Final model validation...${NC}"
MODELS_VALID=true

# Re-define paths (subshell variables don't persist)
NEWAVATA_DIR="${NEWAVATA_DIR:-$HOME/NewAvata}"
NEWAVATA_APP_DIR="$NEWAVATA_DIR/realtime-interview-avatar"
MODELS_DIR="$NEWAVATA_APP_DIR/models"
MUSETALK_MODELS="$NEWAVATA_DIR/MuseTalk/models"

# Activate venv for validation
if [ -f "$NEWAVATA_APP_DIR/venv/bin/activate" ]; then
    source "$NEWAVATA_APP_DIR/venv/bin/activate"
fi

# Check FaceParse model (most critical)
FACEPARSE_MODEL="$MODELS_DIR/face-parse-bisent/79999_iter.pth"
FACEPARSE_SYMLINK="$MUSETALK_MODELS/face-parse-bisent/79999_iter.pth"

validate_faceparse() {
    local model_path="$1"
    if [ ! -f "$model_path" ]; then
        return 1
    fi
    python3 -c "
import torch
try:
    torch.load('$model_path', map_location='cpu', weights_only=False)
    exit(0)
except:
    exit(1)
" 2>/dev/null
    return $?
}

echo -e "  Checking FaceParse model..."
if ! validate_faceparse "$FACEPARSE_MODEL"; then
    echo -e "  ${YELLOW}FaceParse model invalid or missing. Downloading...${NC}"
    rm -f "$FACEPARSE_MODEL" "$FACEPARSE_SYMLINK"
    mkdir -p "$(dirname $FACEPARSE_MODEL)" "$(dirname $FACEPARSE_SYMLINK)"

    # Normalize path to avoid issues with '..' in path
    FACEPARSE_MODEL=$(realpath -m "$FACEPARSE_MODEL")
    FACEPARSE_SYMLINK=$(realpath -m "$FACEPARSE_SYMLINK")
    export FACEPARSE_MODEL

    python3 << 'DOWNLOAD_FACEPARSE'
import os
import shutil
import torch

# Use normalized absolute path from environment
output = os.environ.get('FACEPARSE_MODEL',
    os.path.expanduser('~/NewAvata/realtime-interview-avatar/models/face-parse-bisent/79999_iter.pth'))
# Normalize path in Python too
output = os.path.abspath(os.path.expanduser(output))
os.makedirs(os.path.dirname(output), exist_ok=True)

print(f'  Target path: {output}')

# HuggingFace sources (verified working as of Jan 2026)
sources = [
    ('vivym/face-parsing-bisenet', '79999_iter.pth'),
    ('ManyOtherFunctions/face-parse-bisent', '79999_iter.pth'),
    ('afrizalha/musetalk-models', 'face-parse-bisent/79999_iter.pth'),
]

downloaded = False
try:
    from huggingface_hub import hf_hub_download
    for repo_id, filename in sources:
        try:
            print(f'  Trying HuggingFace: {repo_id}')
            path = hf_hub_download(repo_id=repo_id, filename=filename)
            shutil.copy(path, output)
            # Validate the copied file
            torch.load(output, map_location='cpu', weights_only=False)
            # Verify file exists and has reasonable size
            size = os.path.getsize(output)
            print(f'  SUCCESS from {repo_id} (size: {size/1024/1024:.1f}MB)')
            downloaded = True
            break
        except Exception as e:
            print(f'  Failed: {e}')
            if os.path.exists(output):
                os.remove(output)
except ImportError:
    print('  ERROR: huggingface_hub not available')

exit(0 if downloaded else 1)
DOWNLOAD_FACEPARSE

    # Save exit code immediately (before any other command)
    DOWNLOAD_RESULT=$?
    # Trust Python's validation - it already ran torch.load successfully
    if [ $DOWNLOAD_RESULT -eq 0 ]; then
        echo -e "  ${GREEN}FaceParse model downloaded and validated${NC}"
        # Create symlink
        ln -sf "$FACEPARSE_MODEL" "$FACEPARSE_SYMLINK" 2>/dev/null || \
            cp "$FACEPARSE_MODEL" "$FACEPARSE_SYMLINK"
    else
        echo -e "  ${RED}ERROR: Failed to download valid FaceParse model${NC}"
        MODELS_VALID=false
    fi
else
    echo -e "  ${GREEN}FaceParse model: OK${NC}"
    # Ensure symlink exists
    if [ ! -f "$FACEPARSE_SYMLINK" ]; then
        mkdir -p "$(dirname $FACEPARSE_SYMLINK)"
        ln -sf "$FACEPARSE_MODEL" "$FACEPARSE_SYMLINK" 2>/dev/null || \
            cp "$FACEPARSE_MODEL" "$FACEPARSE_SYMLINK"
    fi
fi

if [ "$MODELS_VALID" = false ]; then
    echo -e "\n${RED}=== Critical models missing. Retrying download... ===${NC}"

    # Retry download with more sources and longer timeout
    for retry in 1 2 3; do
        echo -e "  ${YELLOW}Retry attempt $retry/3...${NC}"

        python3 << 'RETRY_DOWNLOAD'
import os
import shutil
import torch

# Use normalized absolute path from environment
output = os.environ.get('FACEPARSE_MODEL',
    os.path.expanduser('~/NewAvata/realtime-interview-avatar/models/face-parse-bisent/79999_iter.pth'))
output = os.path.abspath(os.path.expanduser(output))
os.makedirs(os.path.dirname(output), exist_ok=True)

print(f'  Target path: {output}')

# HuggingFace sources (verified working as of Jan 2026)
sources = [
    ('vivym/face-parsing-bisenet', '79999_iter.pth'),
    ('ManyOtherFunctions/face-parse-bisent', '79999_iter.pth'),
    ('afrizalha/musetalk-models', 'face-parse-bisent/79999_iter.pth'),
]

downloaded = False
try:
    from huggingface_hub import hf_hub_download
    for repo_id, filename in sources:
        try:
            print(f'  Trying HuggingFace: {repo_id}')
            path = hf_hub_download(repo_id=repo_id, filename=filename)
            shutil.copy(path, output)
            torch.load(output, map_location='cpu', weights_only=False)
            size = os.path.getsize(output)
            print(f'  SUCCESS from {repo_id} (size: {size/1024/1024:.1f}MB)')
            downloaded = True
            break
        except Exception as e:
            print(f'  Failed: {e}')
            if os.path.exists(output):
                os.remove(output)
except ImportError:
    print('  ERROR: huggingface_hub not available')

exit(0 if downloaded else 1)
RETRY_DOWNLOAD

        # Save exit code immediately (before any other command)
        RETRY_RESULT=$?
        # Trust Python's validation - it already ran torch.load successfully
        if [ $RETRY_RESULT -eq 0 ]; then
            echo -e "  ${GREEN}FaceParse model downloaded successfully on retry $retry${NC}"
            ln -sf "$FACEPARSE_MODEL" "$FACEPARSE_SYMLINK" 2>/dev/null || \
                cp "$FACEPARSE_MODEL" "$FACEPARSE_SYMLINK"
            MODELS_VALID=true
            break
        fi

        sleep 5
    done

    if [ "$MODELS_VALID" = false ]; then
        echo -e "\n${RED}=== FATAL: Could not download FaceParse model after 3 retries ===${NC}"
        echo -e "${YELLOW}Please manually download the model:${NC}"
        echo -e "  1. Visit: https://huggingface.co/vivym/face-parsing-bisenet/tree/main"
        echo -e "  2. Download: 79999_iter.pth"
        echo -e "  3. Place in: $FACEPARSE_MODEL"
        echo -e ""
        echo -e "${YELLOW}Then re-run: bash start_full.sh${NC}"
        exit 1
    fi
fi

# Setup NewAvata precomputed avatars
echo -e "\n${YELLOW}[6/7] Setting up NewAvata avatars...${NC}"

# CRITICAL: Re-validate and fix FaceParse model right before precompute
# MuseTalk looks for model at: MuseTalk/models/face-parse-bisent/79999_iter.pth
echo -e "  ${YELLOW}Final FaceParse model check before precompute...${NC}"

MUSETALK_FACEPARSE="$NEWAVATA_DIR/MuseTalk/models/face-parse-bisent/79999_iter.pth"
NEWAVATA_FACEPARSE="$NEWAVATA_APP_DIR/models/face-parse-bisent/79999_iter.pth"

# Activate venv for validation
if [ -f "$NEWAVATA_APP_DIR/venv/bin/activate" ]; then
    source "$NEWAVATA_APP_DIR/venv/bin/activate"
fi

# Check if MuseTalk's expected model location is valid
NEED_FIX=false
if [ ! -f "$MUSETALK_FACEPARSE" ]; then
    echo -e "  ${YELLOW}MuseTalk FaceParse model missing${NC}"
    NEED_FIX=true
elif ! python3 -c "import torch; torch.load('$MUSETALK_FACEPARSE', map_location='cpu', weights_only=False)" 2>/dev/null; then
    echo -e "  ${YELLOW}MuseTalk FaceParse model corrupted${NC}"
    NEED_FIX=true
fi

if [ "$NEED_FIX" = true ]; then
    echo -e "  ${CYAN}Downloading fresh FaceParse model...${NC}"

    # Delete ALL copies (corrupted)
    rm -f "$MUSETALK_FACEPARSE" "$NEWAVATA_FACEPARSE"
    mkdir -p "$(dirname $MUSETALK_FACEPARSE)" "$(dirname $NEWAVATA_FACEPARSE)"

    # Download directly to MuseTalk's expected location
    python3 << 'FIX_FACEPARSE'
import os
import shutil
import torch

musetalk_path = os.path.expanduser('~/NewAvata/MuseTalk/models/face-parse-bisent/79999_iter.pth')
newavata_path = os.path.expanduser('~/NewAvata/realtime-interview-avatar/models/face-parse-bisent/79999_iter.pth')

print(f'  Target paths:')
print(f'    MuseTalk: {musetalk_path}')
print(f'    NewAvata: {newavata_path}')

os.makedirs(os.path.dirname(musetalk_path), exist_ok=True)
os.makedirs(os.path.dirname(newavata_path), exist_ok=True)

# HuggingFace sources (verified working as of Jan 2026)
sources = [
    ('vivym/face-parsing-bisenet', '79999_iter.pth'),
    ('ManyOtherFunctions/face-parse-bisent', '79999_iter.pth'),
    ('afrizalha/musetalk-models', 'face-parse-bisent/79999_iter.pth'),
]

try:
    from huggingface_hub import hf_hub_download
    for repo_id, filename in sources:
        try:
            print(f'  Trying HuggingFace: {repo_id}...')
            path = hf_hub_download(repo_id=repo_id, filename=filename)
            shutil.copy(path, musetalk_path)
            shutil.copy(path, newavata_path)

            # Validate both
            print(f'  Validating MuseTalk location...')
            torch.load(musetalk_path, map_location='cpu', weights_only=False)
            print(f'  Validating NewAvata location...')
            torch.load(newavata_path, map_location='cpu', weights_only=False)

            print(f'  SUCCESS from {repo_id}')
            exit(0)
        except Exception as e:
            print(f'  Failed from {repo_id}: {e}')
            for p in [musetalk_path, newavata_path]:
                if os.path.exists(p):
                    os.remove(p)
except ImportError:
    print('  ERROR: huggingface_hub not available')

print('  ERROR: Could not download valid FaceParse model')
exit(1)
FIX_FACEPARSE

    if [ $? -ne 0 ]; then
        echo -e "  ${RED}FATAL: Cannot fix FaceParse model. Exiting.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}FaceParse model fixed successfully${NC}"
else
    echo -e "  ${GREEN}FaceParse model: OK${NC}"
fi

PRECOMPUTED_DIR="$NEWAVATA_APP_DIR/precomputed"
ASSETS_DIR="$NEWAVATA_APP_DIR/assets"
mkdir -p "$PRECOMPUTED_DIR"

# Check for existing precomputed avatars
AVATAR_COUNT=$(ls -1 "$PRECOMPUTED_DIR/"*.pkl 2>/dev/null | wc -l)
if [ "$AVATAR_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}Found $AVATAR_COUNT precomputed avatar(s)${NC}"
    ls -1 "$PRECOMPUTED_DIR/"*.pkl 2>/dev/null | while read f; do
        echo -e "    - $(basename "$f")"
    done
else
    echo -e "  ${YELLOW}No precomputed avatars found. Generating from assets/...${NC}"

    # Run precompute in a subshell to isolate environment changes
    (
        cd "$NEWAVATA_APP_DIR"

        # Activate NewAvata venv
        if [ -f "venv/bin/activate" ]; then
            source venv/bin/activate
            echo -e "  ${GREEN}Activated NewAvata venv for precompute${NC}"
        fi

        # Check assets/ folder for source videos (pushed to GitHub ~36MB)
        if [ -d "$ASSETS_DIR" ]; then
            VIDEO_COUNT=$(ls -1 "$ASSETS_DIR/"*.mp4 2>/dev/null | wc -l)
            if [ "$VIDEO_COUNT" -gt 0 ]; then
                echo -e "  Found ${CYAN}$VIDEO_COUNT${NC} video(s) in assets/"
                echo -e "  ${YELLOW}Generating precomputed avatars (3.9GB total, may take 5-10 min)...${NC}"

                # Find precompute script (NewAvata uses scripts/precompute_avatar.py)
                PRECOMPUTE_SCRIPT=""
                if [ -f "scripts/precompute_avatar.py" ]; then
                    PRECOMPUTE_SCRIPT="scripts/precompute_avatar.py"
                elif [ -f "precompute.py" ]; then
                    PRECOMPUTE_SCRIPT="precompute.py"
                elif [ -f "scripts/precompute.py" ]; then
                    PRECOMPUTE_SCRIPT="scripts/precompute.py"
                fi

                if [ -n "$PRECOMPUTE_SCRIPT" ]; then
                    # Fix hardcoded Windows path in precompute_avatar.py
                    # Change: os.chdir("c:/NewAvata/NewAvata/realtime-interview-avatar")
                    # To:     os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
                    if grep -q 'os.chdir("c:' "$PRECOMPUTE_SCRIPT" 2>/dev/null; then
                        echo -e "  ${YELLOW}Fixing hardcoded Windows path in precompute_avatar.py...${NC}"
                        sed -i 's|os.chdir("c:/NewAvata/NewAvata/realtime-interview-avatar")|os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))|g' "$PRECOMPUTE_SCRIPT"
                        echo -e "  ${GREEN}Hardcoded path fixed${NC}"
                    fi

                    # Fix PyTorch 2.6 weights_only issue
                    # PyTorch 2.6 changed default weights_only=True which breaks legacy .tar models
                    echo -e "  ${YELLOW}Checking PyTorch 2.6 compatibility...${NC}"
                    PYTORCH_VERSION=$(python -c "import torch; print(torch.__version__)" 2>/dev/null)
                    echo -e "  PyTorch version: ${CYAN}$PYTORCH_VERSION${NC}"

                    # Fix PyTorch 2.6 weights_only issue by patching source files
                    # Add weights_only=False to all torch.load calls in MuseTalk and NewAvata
                    echo -e "  ${YELLOW}Patching torch.load calls for PyTorch 2.6 compatibility...${NC}"

                    # Patch files that use torch.load without weights_only parameter
                    PATCH_DIRS=(
                        "$NEWAVATA_DIR/MuseTalk"
                        "$NEWAVATA_APP_DIR"
                    )

                    for patch_dir in "${PATCH_DIRS[@]}"; do
                        if [ -d "$patch_dir" ]; then
                            # Find and patch Python files with torch.load calls
                            find "$patch_dir" -name "*.py" -type f 2>/dev/null | while read pyfile; do
                                # Check if file has torch.load without weights_only
                                if grep -q "torch\.load(" "$pyfile" 2>/dev/null; then
                                    if ! grep -q "weights_only" "$pyfile" 2>/dev/null; then
                                        # Patch: torch.load(X) -> torch.load(X, weights_only=False)
                                        # Handle both torch.load(path) and torch.load(path, map_location=...)
                                        sed -i 's/torch\.load(\([^)]*\))/torch.load(\1, weights_only=False)/g' "$pyfile" 2>/dev/null
                                        # Fix double comma if map_location was present
                                        sed -i 's/, , weights_only=False/, weights_only=False/g' "$pyfile" 2>/dev/null
                                        echo -e "    ${CYAN}Patched: $(basename $pyfile)${NC}"
                                    fi
                                fi
                            done
                        fi
                    done
                    echo -e "  ${GREEN}torch.load patches applied${NC}"

                    # Set PYTHONPATH to include MuseTalk module
                    MUSETALK_PATH="$NEWAVATA_DIR/MuseTalk"
                    if [ -d "$MUSETALK_PATH" ]; then
                        export PYTHONPATH="${PYTHONPATH}:${MUSETALK_PATH}"
                        echo -e "  ${GREEN}PYTHONPATH set to include MuseTalk${NC}"
                    fi

                    # Process each video in assets/
                    for video in "$ASSETS_DIR"/*.mp4; do
                        if [ -f "$video" ]; then
                            basename=$(basename "$video" .mp4)
                            output_pkl="$PRECOMPUTED_DIR/${basename}.pkl"

                            if [ ! -f "$output_pkl" ]; then
                                echo -e "    Processing: ${CYAN}$basename${NC}..."
                                python "$PRECOMPUTE_SCRIPT" --video "$video" --output "$output_pkl" 2>&1 | tail -10
                                if [ -f "$output_pkl" ]; then
                                    echo -e "    ${GREEN}✓ $basename precomputed${NC}"
                                else
                                    echo -e "    ${YELLOW}✗ $basename failed${NC}"
                                fi
                            else
                                echo -e "    ${GREEN}✓ $basename already exists${NC}"
                            fi
                        fi
                    done
                else
                    echo -e "  ${YELLOW}Precompute script not found${NC}"
                    echo -e "  ${CYAN}Try running MuseTalk preprocessing manually:${NC}"
                    echo -e "    cd MuseTalk && python scripts/preprocess.py --video_path ../assets/your_video.mp4"
                fi
            else
                echo -e "  ${YELLOW}No videos found in assets/${NC}"
            fi
        else
            echo -e "  ${YELLOW}assets/ folder not found${NC}"
        fi

        # Fallback: download sample if no assets AND no precomputed avatars
        CURRENT_AVATAR_COUNT=$(ls -1 "$PRECOMPUTED_DIR/"*.pkl 2>/dev/null | wc -l)
        if [ "$CURRENT_AVATAR_COUNT" -eq 0 ]; then
            echo -e "  ${YELLOW}No precomputed avatars exist. Creating sample avatar...${NC}"

            mkdir -p "$ASSETS_DIR"
            SAMPLE_VIDEO="$ASSETS_DIR/sample_avatar.mp4"

            # Download sample video if not exists
            if [ ! -f "$SAMPLE_VIDEO" ] || [ $(stat -c%s "$SAMPLE_VIDEO" 2>/dev/null || echo 0) -lt 100000 ]; then
                echo -e "  ${CYAN}Downloading sample avatar video...${NC}"
                python3 << 'DOWNLOAD_SAMPLE'
import urllib.request
import os

output = os.path.expanduser('~/NewAvata/realtime-interview-avatar/assets/sample_avatar.mp4')
os.makedirs(os.path.dirname(output), exist_ok=True)

urls = [
    'https://github.com/mindvridge/NewAvata/releases/download/v0.1/sample_avatar.mp4',
    'https://huggingface.co/datasets/mindvridge/avatar-samples/resolve/main/sample_avatar.mp4',
]

downloaded = False
for url in urls:
    try:
        print(f'  Trying: {url[:60]}...')
        urllib.request.urlretrieve(url, output)
        size = os.path.getsize(output)
        if size > 100000:
            print(f'  Downloaded: {size/1024/1024:.1f}MB')
            downloaded = True
            break
        else:
            os.remove(output)
    except Exception as e:
        print(f'  Failed: {e}')

if not downloaded:
    print('  ERROR: Could not download sample avatar video')
    exit(1)
print('  Sample video ready!')
DOWNLOAD_SAMPLE

                if [ $? -ne 0 ]; then
                    echo -e "  ${RED}Failed to download sample video${NC}"
                fi
            else
                echo -e "  ${GREEN}Sample video already exists${NC}"
            fi

            # Precompute the sample avatar
            if [ -f "$SAMPLE_VIDEO" ]; then
                OUTPUT_PKL="$PRECOMPUTED_DIR/sample_avatar.pkl"

                if [ ! -f "$OUTPUT_PKL" ]; then
                    echo -e "  ${CYAN}Precomputing sample avatar (this may take 5-10 minutes)...${NC}"

                    # Find precompute script
                    PRECOMPUTE_SCRIPT=""
                    if [ -f "scripts/precompute_avatar.py" ]; then
                        PRECOMPUTE_SCRIPT="scripts/precompute_avatar.py"
                    elif [ -f "precompute.py" ]; then
                        PRECOMPUTE_SCRIPT="precompute.py"
                    elif [ -f "scripts/precompute.py" ]; then
                        PRECOMPUTE_SCRIPT="scripts/precompute.py"
                    fi

                    if [ -n "$PRECOMPUTE_SCRIPT" ]; then
                        # Fix hardcoded Windows path if present
                        if grep -q 'os.chdir("c:' "$PRECOMPUTE_SCRIPT" 2>/dev/null; then
                            echo -e "  ${YELLOW}Fixing hardcoded Windows path...${NC}"
                            sed -i 's|os.chdir("c:/NewAvata/NewAvata/realtime-interview-avatar")|os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))|g' "$PRECOMPUTE_SCRIPT"
                        fi

                        # Set PYTHONPATH
                        MUSETALK_PATH="$NEWAVATA_DIR/MuseTalk"
                        if [ -d "$MUSETALK_PATH" ]; then
                            export PYTHONPATH="${PYTHONPATH}:${MUSETALK_PATH}"
                        fi

                        echo -e "  Input:  $SAMPLE_VIDEO"
                        echo -e "  Output: $OUTPUT_PKL"
                        echo ""

                        # Run precompute with progress output
                        python "$PRECOMPUTE_SCRIPT" --video "$SAMPLE_VIDEO" --output "$OUTPUT_PKL" 2>&1 | while read line; do
                            echo "    $line"
                        done

                        if [ -f "$OUTPUT_PKL" ]; then
                            SIZE=$(du -h "$OUTPUT_PKL" 2>/dev/null | cut -f1)
                            echo -e "  ${GREEN}Sample avatar precomputed successfully! ($SIZE)${NC}"
                        else
                            echo -e "  ${RED}Precompute failed - avatar file not created${NC}"
                        fi
                    else
                        echo -e "  ${RED}Precompute script not found${NC}"
                    fi
                else
                    echo -e "  ${GREEN}Sample avatar already precomputed${NC}"
                fi
            fi
        fi
    )  # End of subshell - venv and PYTHONPATH changes are isolated
    echo -e "  ${GREEN}Avatar setup completed${NC}"
fi

# Fix nested directory structure for precomputed avatars
# NewAvata precompute creates: precomputed/name.pkl/name_precomputed.pkl (directory with file inside)
# But API expects: precomputed/name.pkl (file)
# Solution: Move the inner file to the expected location
echo -e "\n  ${CYAN}Checking precomputed avatar structure...${NC}"

if [ -d "$PRECOMPUTED_DIR" ]; then
    FIXED_COUNT=0

    # First, check for directories ending in .pkl
    for item in "$PRECOMPUTED_DIR"/*; do
        if [ -d "$item" ]; then
            dir_name=$(basename "$item")

            # Check if it's a .pkl directory (contains inner pkl file)
            if [[ "$dir_name" == *.pkl ]]; then
                # Find the actual .pkl file inside
                inner_pkl=$(find "$item" -maxdepth 1 -name "*.pkl" -type f 2>/dev/null | head -1)

                if [ -n "$inner_pkl" ] && [ -f "$inner_pkl" ]; then
                    # Move inner file out, rename directory to _backup
                    backup_dir="${item}_backup"
                    target_file="$item"

                    echo -e "    Found: ${CYAN}$dir_name${NC} (directory)"
                    echo -e "      Inner: $(basename $inner_pkl) ($(du -h "$inner_pkl" 2>/dev/null | cut -f1))"

                    # Move directory to backup
                    mv "$item" "$backup_dir"
                    # Move inner file to expected location
                    mv "$backup_dir/$(basename $inner_pkl)" "$target_file"
                    echo -e "      ${GREEN}Fixed: moved to $dir_name${NC}"
                    FIXED_COUNT=$((FIXED_COUNT + 1))
                fi
            elif [[ "$dir_name" == *.pkl_dir ]] || [[ "$dir_name" == *.pkl_backup ]]; then
                # Already processed backup directory, check if file exists
                base_name="${dir_name%_dir}"
                base_name="${base_name%_backup}"
                expected_file="$PRECOMPUTED_DIR/$base_name"

                if [ ! -f "$expected_file" ]; then
                    # File doesn't exist, try to restore from backup
                    inner_pkl=$(find "$item" -maxdepth 1 -name "*.pkl" -type f 2>/dev/null | head -1)
                    if [ -n "$inner_pkl" ] && [ -f "$inner_pkl" ]; then
                        cp "$inner_pkl" "$expected_file"
                        echo -e "    Restored: ${CYAN}$base_name${NC} from backup"
                        FIXED_COUNT=$((FIXED_COUNT + 1))
                    fi
                fi
            fi
        fi
    done

    # Also check for symlinks that might be broken
    for item in "$PRECOMPUTED_DIR"/*.pkl; do
        if [ -L "$item" ]; then
            # It's a symlink
            if [ ! -e "$item" ]; then
                # Broken symlink
                link_target=$(readlink "$item" 2>/dev/null)
                echo -e "    ${YELLOW}Warning: broken symlink $item -> $link_target${NC}"
                # Try to find the actual file
                dir_name=$(basename "$item")
                backup_dir="${item}_backup"
                if [ -d "$backup_dir" ]; then
                    inner_pkl=$(find "$backup_dir" -maxdepth 1 -name "*.pkl" -type f 2>/dev/null | head -1)
                    if [ -n "$inner_pkl" ] && [ -f "$inner_pkl" ]; then
                        rm "$item"
                        cp "$inner_pkl" "$item"
                        echo -e "      ${GREEN}Fixed: copied from backup${NC}"
                        FIXED_COUNT=$((FIXED_COUNT + 1))
                    fi
                fi
            fi
        fi
    done

    if [ "$FIXED_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Fixed $FIXED_COUNT avatar file(s)${NC}"
    else
        echo -e "  ${GREEN}Avatar structure OK${NC}"
    fi

    # Convert symlinks to actual files (NewAvata API doesn't follow symlinks properly)
    echo -e "\n  ${CYAN}Checking for symlinks...${NC}"
    SYMLINK_FIXED=0
    for item in "$PRECOMPUTED_DIR"/*.pkl; do
        if [ -L "$item" ]; then
            target=$(readlink -f "$item" 2>/dev/null)
            if [ -f "$target" ]; then
                rm "$item"
                cp "$target" "$item"
                echo -e "    Converted symlink: ${CYAN}$(basename $item)${NC}"
                SYMLINK_FIXED=$((SYMLINK_FIXED + 1))
            fi
        fi
    done
    if [ "$SYMLINK_FIXED" -gt 0 ]; then
        echo -e "  ${GREEN}Converted $SYMLINK_FIXED symlink(s) to files${NC}"
    fi

    # Rename files to *_precomputed.pkl format (required by NewAvata API)
    echo -e "\n  ${CYAN}Checking file naming convention...${NC}"
    RENAMED_COUNT=0
    for f in "$PRECOMPUTED_DIR"/*.pkl; do
        if [ -f "$f" ]; then
            fname=$(basename "$f")
            # Skip if already has _precomputed suffix
            if [[ "$fname" != *"_precomputed.pkl" ]]; then
                name="${fname%.pkl}"
                newname="${name}_precomputed.pkl"
                mv "$f" "$PRECOMPUTED_DIR/$newname"
                echo -e "    Renamed: ${CYAN}$fname${NC} -> ${GREEN}$newname${NC}"
                RENAMED_COUNT=$((RENAMED_COUNT + 1))
            fi
        fi
    done
    if [ "$RENAMED_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Renamed $RENAMED_COUNT file(s) to *_precomputed.pkl format${NC}"
    fi

    # Show actual file count
    FILE_COUNT=$(find "$PRECOMPUTED_DIR" -maxdepth 1 -name "*_precomputed.pkl" -type f 2>/dev/null | wc -l)
    echo -e "  ${CYAN}Actual *_precomputed.pkl files: $FILE_COUNT${NC}"
fi

# Final avatar count and TensorRT note
# Use find to count only actual files with correct naming (not directories or symlinks)
AVATAR_FILE_COUNT=$(find "$PRECOMPUTED_DIR" -maxdepth 1 -name "*_precomputed.pkl" -type f 2>/dev/null | wc -l)
AVATAR_SYMLINK_COUNT=$(find "$PRECOMPUTED_DIR" -maxdepth 1 -name "*.pkl" -type l 2>/dev/null | wc -l)
AVATAR_DIR_COUNT=$(find "$PRECOMPUTED_DIR" -maxdepth 1 -name "*.pkl" -type d 2>/dev/null | wc -l)

echo -e "\n  ${CYAN}Avatar Summary:${NC}"
echo -e "    .pkl files:     ${GREEN}$AVATAR_FILE_COUNT${NC}"
if [ "$AVATAR_SYMLINK_COUNT" -gt 0 ]; then
    echo -e "    .pkl symlinks:  ${YELLOW}$AVATAR_SYMLINK_COUNT${NC} (may not work with API)"
fi
if [ "$AVATAR_DIR_COUNT" -gt 0 ]; then
    echo -e "    .pkl dirs:      ${RED}$AVATAR_DIR_COUNT${NC} (need fixing)"
fi
echo -e "    TensorRT:       ${YELLOW}Auto-generated on first inference (~5GB)${NC}"

if [ "$AVATAR_FILE_COUNT" -eq 0 ]; then
    echo -e "\n  ${YELLOW}Note: Add videos to assets/ and re-run, or use avatar_path='auto'${NC}"
    if [ "$AVATAR_DIR_COUNT" -gt 0 ]; then
        echo -e "  ${YELLOW}Found $AVATAR_DIR_COUNT .pkl directories that need manual fixing${NC}"
        echo -e "  Run: find $PRECOMPUTED_DIR -maxdepth 1 -name '*.pkl' -type d"
    fi
fi

# Start both servers
echo -e "\n${YELLOW}[7/7] Starting servers...${NC}"

# Check if tmux is available
if command -v tmux &> /dev/null; then
    echo -e "  Using tmux for multi-server management"

    # Kill existing sessions
    tmux kill-session -t tts 2>/dev/null || true
    tmux kill-session -t newavata 2>/dev/null || true

    # =============================================
    # STEP 1: Start TTS server FIRST (so NewAvata can detect it)
    # =============================================
    echo -e "\n  ${CYAN}[Step 1/2] Starting TTS server first...${NC}"

    # Kill any existing process on port 8000
    if command -v fuser &> /dev/null; then
        fuser -k 8000/tcp 2>/dev/null || true
        sleep 1
    fi

    # Start TTS server in tmux
    TTS_LOG="/tmp/tts_startup.log"
    cd "$SCRIPT_DIR"

    # Create TTS startup script
    cat > /tmp/start_tts.sh << 'TTS_SCRIPT'
#!/bin/bash
cd "$1"
echo "=== TTS Server Startup ===" > /tmp/tts_startup.log
echo "Working dir: $(pwd)" >> /tmp/tts_startup.log
echo "Date: $(date)" >> /tmp/tts_startup.log
echo "" >> /tmp/tts_startup.log

# Ensure we have the right Python environment
deactivate 2>/dev/null || true
unset VIRTUAL_ENV 2>/dev/null || true

# If Qwen3-TTS has its own venv, activate it
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo "Activated venv" >> /tmp/tts_startup.log
fi

# Verify environment
if python -c "import fastapi; import torch; print('OK')" 2>/dev/null | grep -q "OK"; then
    echo "Environment OK" >> /tmp/tts_startup.log
else
    echo "Installing dependencies..." >> /tmp/tts_startup.log
    pip install -r requirements.txt --quiet 2>/dev/null
fi

echo "Starting TTS server on port 8000..." >> /tmp/tts_startup.log
python -u server.py 2>&1 | tee -a /tmp/tts_startup.log
TTS_SCRIPT
    chmod +x /tmp/start_tts.sh

    # Start TTS in tmux
    tmux new-session -d -s tts "bash /tmp/start_tts.sh '$SCRIPT_DIR'"
    echo -e "    ${GREEN}TTS server starting (tmux session: tts)${NC}"
    echo -e "    Port: ${CYAN}8000${NC}"

    # Wait for TTS server to be ready
    echo -e "    Waiting for TTS server..."
    TTS_READY=false
    for i in $(seq 1 30); do
        if curl -s --max-time 2 http://localhost:8000/health 2>/dev/null | grep -qiE "ok|healthy|status"; then
            TTS_READY=true
            echo -e "    ${GREEN}✓ TTS server ready (${i}s)${NC}"
            break
        fi
        sleep 2
    done

    if [ "$TTS_READY" = false ]; then
        echo -e "    ${YELLOW}⚠ TTS server not responding yet (may still be loading models)${NC}"
        echo -e "    ${YELLOW}  NewAvata will start anyway, but qwen3tts may not be available initially${NC}"
    fi

    # =============================================
    # STEP 2: Start NewAvata server (will detect TTS)
    # =============================================
    echo -e "\n  ${CYAN}[Step 2/2] Starting NewAvata server...${NC}"

    # Start NewAvata server in tmux
    NEWAVATA_LOG="/tmp/newavata_startup.log"
    if [ -d "$NEWAVATA_APP_DIR" ]; then
        cd "$NEWAVATA_APP_DIR"

        # Create PyTorch 2.6 patch wrapper
        cat > /tmp/torch_patch_wrapper.py << 'TORCH_WRAPPER'
#!/usr/bin/env python3
# PyTorch 2.6 compatibility wrapper - patches torch.load before any imports
import sys
import functools

# Patch torch.load immediately after torch is imported
_original_import = __builtins__.__import__ if hasattr(__builtins__, '__import__') else __import__

def _patched_import(name, *args, **kwargs):
    module = _original_import(name, *args, **kwargs)
    if name == 'torch' and not getattr(module, '_load_patched', False):
        original_load = module.load
        @functools.wraps(original_load)
        def patched_load(*a, **kw):
            if 'weights_only' not in kw:
                kw['weights_only'] = False
            return original_load(*a, **kw)
        module.load = patched_load
        module._load_patched = True
        print("[PATCH] torch.load patched for PyTorch 2.6+ compatibility")
    return module

if hasattr(__builtins__, '__import__'):
    __builtins__.__import__ = _patched_import
else:
    import builtins
    builtins.__import__ = _patched_import

# Now run the actual main module
if __name__ == "__main__":
    # Remove this wrapper from argv
    sys.argv = sys.argv[1:] if len(sys.argv) > 1 else sys.argv

    # Import and run main
    if len(sys.argv) > 0 and sys.argv[0].endswith('.py'):
        script = sys.argv[0]
        sys.argv = sys.argv[1:]
        with open(script) as f:
            code = compile(f.read(), script, 'exec')
            exec(code, {'__name__': '__main__', '__file__': script})
    else:
        import main
TORCH_WRAPPER

        # Create a startup wrapper script for better logging
        cat > /tmp/start_newavata.sh << 'NEWAVATA_SCRIPT'
#!/bin/bash
cd "$1"
echo "=== NewAvata Startup ===" > /tmp/newavata_startup.log
echo "Working dir: $(pwd)" >> /tmp/newavata_startup.log
echo "Date: $(date)" >> /tmp/newavata_startup.log
echo "" >> /tmp/newavata_startup.log

# Activate venv if exists
if [ -f "venv/bin/activate" ]; then
    echo "Activating venv..." >> /tmp/newavata_startup.log
    source venv/bin/activate
fi

# CRITICAL: Set PYTHONPATH to include MuseTalk module
MUSETALK_PATH="$HOME/NewAvata/MuseTalk"
if [ -d "$MUSETALK_PATH" ]; then
    export PYTHONPATH="${PYTHONPATH}:${MUSETALK_PATH}"
    echo "PYTHONPATH set: $PYTHONPATH" >> /tmp/newavata_startup.log
else
    echo "WARNING: MuseTalk not found at $MUSETALK_PATH" >> /tmp/newavata_startup.log
fi

# Configure Qwen3-TTS connection (TTS server running on port 8000)
export QWEN3_TTS_API_URL="http://localhost:8000"
export QWEN3_TTS_REF_AUDIO="https://github.com/mindvridge/Qwen3-TTS/raw/main/sample(1).mp3"
export QWEN3_TTS_REF_TEXT="안녕하세요, 반갑습니다."
echo "Qwen3-TTS configured: $QWEN3_TTS_API_URL" >> /tmp/newavata_startup.log

# Fix Whisper warmup bug in load_models - the bug is passing tuple to get_audio_feature
echo "Fixing Whisper warmup bug..." >> /tmp/newavata_startup.log
if [ -f "app.py" ]; then
    python3 << 'PATCH_SCRIPT'
with open('app.py', 'r') as f:
    content = f.read()

# Check if already patched
if 'PATCHED_WHISPER_WARMUP' in content:
    print('  Already patched')
else:
    modified = False

    # The bug is in load_models: get_audio_feature((dummy_audio_np, 16000)) passes tuple instead of path
    # We need to comment out the Whisper warmup section in load_models

    # Find and replace the problematic Whisper warmup code
    # Pattern: "Whisper 워밍업" followed by the buggy code
    old_code = 'print("    Whisper 워밍업...")'
    if old_code in content:
        # Find where this line is and wrap the following whisper warmup in try/except
        lines = content.split('\n')
        new_lines = []
        i = 0
        while i < len(lines):
            line = lines[i]
            if 'Whisper 워밍업' in line:
                # Get the indentation
                indent = len(line) - len(line.lstrip())
                spaces = ' ' * indent

                # Add the original print but with patched marker
                new_lines.append(f'{spaces}# PATCHED_WHISPER_WARMUP: Disabled problematic warmup')
                new_lines.append(f'{spaces}print("    Whisper 워밍업... (SKIPPED - patched)")')

                # Skip the original print line and subsequent warmup code until we hit a different section
                i += 1
                # Skip until we find a line that starts a new section (not indented more, or new print statement)
                while i < len(lines):
                    next_line = lines[i]
                    next_stripped = next_line.strip()
                    next_indent = len(next_line) - len(next_line.lstrip()) if next_stripped else indent + 1

                    # Stop if we hit a new section marker or less indentation
                    if next_stripped.startswith('print(') and '워밍업' not in next_line and 'chunk' not in next_line.lower():
                        break
                    if next_stripped.startswith('self.whisper_processor') or next_stripped.startswith('return') or next_stripped.startswith('def '):
                        break
                    if next_indent < indent and next_stripped:
                        break
                    # Skip this line (comment it out)
                    if next_stripped:
                        new_lines.append(f'{spaces}# SKIPPED: {next_stripped}')
                    i += 1
                modified = True
                continue
            new_lines.append(line)
            i += 1

        if modified:
            content = '\n'.join(new_lines)

    # Alternative: Direct string replacement of the problematic line
    if not modified:
        # Replace the specific buggy line
        old_line = 'whisper_features, librosa_len = self.audio_processor.get_audio_feature((dummy_audio_np, 16000))'
        if old_line in content:
            new_line = '# PATCHED_WHISPER_WARMUP: Disabled - tuple not supported\n            whisper_features, librosa_len = None, 0  # Warmup skipped'
            content = content.replace(old_line, new_line)
            modified = True
            print('  Patched get_audio_feature line directly')

    if modified:
        with open('app.py', 'w') as f:
            f.write(content)
        print('  Whisper warmup bug fixed!')
    else:
        print('  No matching code found to patch')
PATCH_SCRIPT
    echo "  Patch script completed" >> /tmp/newavata_startup.log
fi

# Fix Qwen3-TTS tuple bug - ensure tuple (audio_numpy, sample_rate) is saved to file before path operations
echo "Fixing Qwen3-TTS tuple bug..." >> /tmp/newavata_startup.log
if [ -f "app.py" ]; then
    python3 << 'QWEN3_PATCH'
import re

with open('app.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Check if already patched
if 'PATCHED_QWEN3TTS_TUPLE' in content:
    print('  Qwen3-TTS tuple fix already applied')
else:
    modified = False

    # Pattern 1: Find where os.stat or os.path is called on audio_input that could be a tuple
    # We need to add type checking before file operations

    # Look for the generate_lipsync_internal function and add tuple handling
    # The issue is that qwen3tts returns (audio_bytes, sample_rate) or similar tuple

    # Fix: Add wrapper to save tuple audio to temp file
    fix_code = '''
# PATCHED_QWEN3TTS_TUPLE: Auto-convert tuple to file path
def _ensure_audio_path(audio_input, output_dir="/tmp"):
    """Convert audio tuple/bytes to file path if needed"""
    import os
    import tempfile
    import uuid

    if audio_input is None:
        return None

    # Already a string path
    if isinstance(audio_input, str):
        return audio_input

    # Tuple of (audio_data, sample_rate)
    if isinstance(audio_input, tuple) and len(audio_input) == 2:
        audio_data, sample_rate = audio_input
        try:
            import soundfile as sf
            import numpy as np

            # Ensure output directory exists
            os.makedirs(output_dir, exist_ok=True)

            # Generate unique filename
            temp_path = os.path.join(output_dir, f"qwen3tts_audio_{uuid.uuid4().hex[:8]}.wav")

            # Handle different audio data types
            if isinstance(audio_data, bytes):
                # Raw bytes - write directly
                with open(temp_path, 'wb') as f:
                    f.write(audio_data)
            elif isinstance(audio_data, np.ndarray):
                # Numpy array - use soundfile
                sf.write(temp_path, audio_data, sample_rate)
            else:
                print(f"[WARN] Unknown audio data type: {type(audio_data)}")
                return None

            return temp_path
        except Exception as e:
            print(f"[ERROR] Failed to convert tuple to audio file: {e}")
            return None

    # Bytes data (without sample rate)
    if isinstance(audio_input, bytes):
        try:
            import uuid
            temp_path = os.path.join(output_dir, f"qwen3tts_audio_{uuid.uuid4().hex[:8]}.wav")
            with open(temp_path, 'wb') as f:
                f.write(audio_input)
            return temp_path
        except Exception as e:
            print(f"[ERROR] Failed to save bytes to audio file: {e}")
            return None

    return audio_input

'''

    # Find a good place to insert the fix - after imports
    if 'from flask import' in content or 'import flask' in content:
        # Find the end of imports section
        lines = content.split('\n')
        insert_idx = 0
        for i, line in enumerate(lines):
            if line.strip().startswith('import ') or line.strip().startswith('from '):
                insert_idx = i + 1
            elif line.strip() and not line.strip().startswith('#') and insert_idx > 0:
                # Found first non-import line
                break

        # Insert the fix after imports
        lines.insert(insert_idx, fix_code)
        content = '\n'.join(lines)
        modified = True
        print('  Added _ensure_audio_path helper function')

    # CRITICAL FIX: Patch line 699 where get_audio_feature(audio_input) is called
    # The error is: TypeError: stat: path should be string, bytes, os.PathLike or integer, not tuple
    # This happens because qwen3tts returns tuple (audio_numpy, sample_rate) instead of file path

    # Pattern 1: Find the exact line calling get_audio_feature(audio_input)
    pattern1 = r'(\s*)(whisper_input_features\s*,\s*librosa_length\s*=\s*self\.audio_processor\.get_audio_feature\(audio_input\))'
    replacement1 = r'''\1# PATCHED_QWEN3TTS_TUPLE: Convert tuple to file path before get_audio_feature
\1if isinstance(audio_input, tuple) and len(audio_input) == 2:
\1    audio_input = _ensure_audio_path(audio_input)
\1whisper_input_features, librosa_length = self.audio_processor.get_audio_feature(audio_input)'''

    if re.search(pattern1, content):
        content = re.sub(pattern1, replacement1, content)
        modified = True
        print('  Patched: get_audio_feature(audio_input) at line 699')

    # Pattern 2: Also patch any other get_audio_feature calls with audio variables
    pattern2 = r'(\s*)([\w_]+\s*,\s*[\w_]+\s*=\s*[\w\.]+\.get_audio_feature\((audio_input|wav_path|audio_path)\))'
    def patch_audio_call(match):
        indent = match.group(1)
        line = match.group(2)
        var = match.group(3)
        if 'PATCHED_QWEN3TTS_TUPLE' in content[max(0, match.start()-200):match.start()]:
            return match.group(0)  # Already patched nearby
        return f'''{indent}# PATCHED_QWEN3TTS_TUPLE: Ensure file path
{indent}if isinstance({var}, tuple) and len({var}) == 2:
{indent}    {var} = _ensure_audio_path({var})
{indent}{line}'''

    new_content = re.sub(pattern2, patch_audio_call, content)
    if new_content != content:
        content = new_content
        modified = True
        print('  Patched additional get_audio_feature calls')

    # Pattern 3: Also fix os.path.exists and os.stat on audio variables
    patterns_to_fix = [
        (r'os\.path\.exists\(wav_path\)', 'isinstance(wav_path, str) and os.path.exists(wav_path)'),
        (r'os\.path\.exists\(audio_input\)', 'isinstance(audio_input, str) and os.path.exists(audio_input)'),
        (r'os\.stat\(wav_path\)', 'os.stat(wav_path if isinstance(wav_path, str) else "")'),
    ]

    for pattern, replacement in patterns_to_fix:
        if re.search(pattern, content) and replacement not in content:
            content = re.sub(pattern, replacement, content)
            modified = True
            print(f'  Patched: {pattern}')

    if modified:
        with open('app.py', 'w', encoding='utf-8') as f:
            f.write(content)
        print('  Qwen3-TTS tuple bug fix applied!')
    else:
        print('  No changes needed or patterns not found')
QWEN3_PATCH
    echo "  Qwen3-TTS patch completed" >> /tmp/newavata_startup.log
fi

# BACKUP FIX: Also patch audio_processor.py in MuseTalk to handle tuple input
echo "Patching MuseTalk audio_processor.py..." >> /tmp/newavata_startup.log
AUDIO_PROCESSOR_PATH="$HOME/NewAvata/MuseTalk/musetalk/utils/audio_processor.py"
if [ -f "$AUDIO_PROCESSOR_PATH" ]; then
    python3 << 'AUDIO_PATCH'
import os
import re

audio_path = os.path.expanduser('~/NewAvata/MuseTalk/musetalk/utils/audio_processor.py')
if not os.path.exists(audio_path):
    print(f'  audio_processor.py not found at {audio_path}')
    exit(0)

with open(audio_path, 'r', encoding='utf-8') as f:
    content = f.read()

if 'PATCHED_TUPLE_FIX' in content:
    print('  audio_processor.py already patched')
    exit(0)

# Find the get_audio_feature function and add tuple handling at the start
# Original: def get_audio_feature(self, wav_path):
#           if not os.path.exists(wav_path):

# Look for the function definition
func_pattern = r'(def get_audio_feature\(self,\s*wav_path[^)]*\):)'
if not re.search(func_pattern, content):
    print('  get_audio_feature function not found')
    exit(0)

# Add tuple handling after the function definition
tuple_fix = '''
        # PATCHED_TUPLE_FIX: Handle tuple input (audio_data, sample_rate)
        if isinstance(wav_path, tuple) and len(wav_path) == 2:
            import uuid
            import tempfile
            import numpy as np
            audio_data, sample_rate = wav_path
            temp_dir = tempfile.gettempdir()
            temp_path = os.path.join(temp_dir, f"musetalk_audio_{uuid.uuid4().hex[:8]}.wav")
            try:
                import soundfile as sf
                if isinstance(audio_data, bytes):
                    with open(temp_path, 'wb') as f:
                        f.write(audio_data)
                elif isinstance(audio_data, np.ndarray):
                    sf.write(temp_path, audio_data, sample_rate)
                else:
                    print(f"[WARN] Unknown audio type: {type(audio_data)}")
                wav_path = temp_path
            except Exception as e:
                print(f"[ERROR] Failed to save tuple audio: {e}")
'''

# Insert the fix after the function definition
def add_tuple_fix(match):
    func_def = match.group(1)
    return func_def + tuple_fix

new_content = re.sub(func_pattern, add_tuple_fix, content, count=1)

if new_content != content:
    with open(audio_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('  audio_processor.py patched successfully!')
else:
    print('  No changes made to audio_processor.py')
AUDIO_PATCH
    echo "  MuseTalk audio_processor patch completed" >> /tmp/newavata_startup.log
else
    echo "  audio_processor.py not found (MuseTalk not installed?)" >> /tmp/newavata_startup.log
fi

# Apply PyTorch 2.6 patches to source files (for diffusers etc.)
echo "Applying PyTorch 2.6 patches..." >> /tmp/newavata_startup.log
find . -name "*.py" -type f 2>/dev/null | while read pyfile; do
    if grep -q "torch\.load(" "$pyfile" 2>/dev/null; then
        if ! grep -q "weights_only" "$pyfile" 2>/dev/null; then
            sed -i 's/torch\.load(\([^)]*\))/torch.load(\1, weights_only=False)/g' "$pyfile" 2>/dev/null
            sed -i 's/, , weights_only=False/, weights_only=False/g' "$pyfile" 2>/dev/null
            echo "  Patched: $pyfile" >> /tmp/newavata_startup.log
        fi
    fi
done

# Also patch diffusers library if present
DIFFUSERS_PATH=$(python -c "import diffusers; print(diffusers.__path__[0])" 2>/dev/null)
if [ -n "$DIFFUSERS_PATH" ] && [ -d "$DIFFUSERS_PATH" ]; then
    echo "Patching diffusers library..." >> /tmp/newavata_startup.log
    find "$DIFFUSERS_PATH" -name "*.py" -type f 2>/dev/null | while read pyfile; do
        if grep -q "torch\.load(" "$pyfile" 2>/dev/null; then
            if ! grep -q "weights_only" "$pyfile" 2>/dev/null; then
                sed -i 's/torch\.load(\([^)]*\))/torch.load(\1, weights_only=False)/g' "$pyfile" 2>/dev/null
                sed -i 's/, , weights_only=False/, weights_only=False/g' "$pyfile" 2>/dev/null
            fi
        fi
    done
    echo "  diffusers patched" >> /tmp/newavata_startup.log
fi

# Kill any existing process on port 5000 or 8001
echo "Killing existing processes on ports 5000 and 8001..." >> /tmp/newavata_startup.log
fuser -k 5000/tcp 2>/dev/null || true
fuser -k 8001/tcp 2>/dev/null || true
sleep 2

# Start app.py directly with port 8001
# We patch the port in app.py before starting
if [ -f "app.py" ]; then
    echo "Patching app.py to use port 8001..." >> /tmp/newavata_startup.log

    # More robust port patching - handle various formats
    # Pattern 1: port=5000
    sed -i 's/port=5000/port=8001/g' app.py 2>/dev/null
    # Pattern 2: port = 5000 (with spaces)
    sed -i 's/port\s*=\s*5000/port=8001/g' app.py 2>/dev/null
    # Pattern 3: "port": 5000 (JSON style)
    sed -i 's/"port":\s*5000/"port": 8001/g' app.py 2>/dev/null
    # Pattern 4: PORT = 5000 (constant)
    sed -i 's/PORT\s*=\s*5000/PORT = 8001/g' app.py 2>/dev/null
    # Pattern 5: default_port = 5000
    sed -i 's/default_port\s*=\s*5000/default_port = 8001/g' app.py 2>/dev/null
    # Pattern 6: in socketio.run(..., port=5000)
    sed -i "s/socketio\.run([^)]*port\s*=\s*5000/socketio.run(app, host='0.0.0.0', port=8001/g" app.py 2>/dev/null

    # Also check and patch any config.py or settings
    if [ -f "config.py" ]; then
        sed -i 's/PORT\s*=\s*5000/PORT = 8001/g' config.py 2>/dev/null
        sed -i 's/port\s*=\s*5000/port = 8001/g' config.py 2>/dev/null
    fi

    # Verify patch was applied
    if grep -q "8001" app.py; then
        echo "  Port patched to 8001" >> /tmp/newavata_startup.log
    else
        echo "  WARNING: Port patch may not have applied, adding override..." >> /tmp/newavata_startup.log
    fi

    echo "Starting app.py on port 8001..." >> /tmp/newavata_startup.log
    # Use -u for unbuffered output to see logs in real-time
    # Add PORT environment variable as fallback
    PORT=8001 python -u app.py --port 8001 2>&1 | tee -a /tmp/newavata_startup.log
else
    echo "ERROR: app.py not found!" >> /tmp/newavata_startup.log
    echo "Available files:" >> /tmp/newavata_startup.log
    ls -la >> /tmp/newavata_startup.log
    sleep 300  # Keep session alive to debug
fi
NEWAVATA_SCRIPT
        chmod +x /tmp/start_newavata.sh

        # Start tmux with the wrapper script
        tmux new-session -d -s newavata "bash /tmp/start_newavata.sh '$NEWAVATA_APP_DIR'"

        echo -e "  ${GREEN}NewAvata server starting (tmux session: newavata)${NC}"
        echo -e "    Port: ${CYAN}8001${NC}"
        echo -e "    Log: ${CYAN}$NEWAVATA_LOG${NC}"
    else
        echo -e "  ${RED}NewAvata app directory not found: $NEWAVATA_APP_DIR${NC}"
    fi

    # Wait for NewAvata to initialize and verify with real-time monitoring
    echo -e "  ${CYAN}Waiting for NewAvata to initialize (monitoring progress)...${NC}"
    echo ""

    # Monitor startup in real-time with timeout
    MAX_WAIT=120  # 2 minutes maximum
    WAITED=0
    NEWAVATA_OK=false
    PORT_LISTENING=false

    while [ $WAITED -lt $MAX_WAIT ]; do
        # Show progress every 10 seconds
        if [ $((WAITED % 10)) -eq 0 ]; then
            echo -e "  [${WAITED}s] Checking NewAvata status..."

            # Show latest log lines
            if [ -f "/tmp/newavata_startup.log" ]; then
                LAST_LOG=$(tail -3 /tmp/newavata_startup.log 2>/dev/null | head -3)
                if [ -n "$LAST_LOG" ]; then
                    echo -e "  ${CYAN}Latest log:${NC}"
                    echo "$LAST_LOG" | sed 's/^/    /'
                fi
            fi

            # Check for errors in log
            if [ -f "/tmp/newavata_startup.log" ]; then
                if grep -qiE "error|exception|traceback|failed" /tmp/newavata_startup.log 2>/dev/null; then
                    echo -e "  ${RED}[ERROR DETECTED in log]${NC}"
                    grep -iE "error|exception|traceback" /tmp/newavata_startup.log | tail -5 | sed 's/^/    /'
                fi
            fi
        fi

        # Check if port 8001 is listening
        if command -v ss &> /dev/null; then
            if ss -tln | grep -q ":8001"; then
                PORT_LISTENING=true
            fi
        elif command -v netstat &> /dev/null; then
            if netstat -tln | grep -q ":8001"; then
                PORT_LISTENING=true
            fi
        elif command -v lsof &> /dev/null; then
            if lsof -i :8001 &>/dev/null; then
                PORT_LISTENING=true
            fi
        fi

        if [ "$PORT_LISTENING" = true ]; then
            echo -e "  ${GREEN}[${WAITED}s] Port 8001 is now listening!${NC}"

            # Test health endpoint
            HEALTH_RESPONSE=$(curl -s --max-time 5 http://localhost:8001/health 2>/dev/null || echo "")

            if echo "$HEALTH_RESPONSE" | grep -qiE "ok|healthy|running|status"; then
                echo -e "  ${GREEN}NewAvata health check: OK${NC}"
                echo -e "  Response: $HEALTH_RESPONSE"
                NEWAVATA_OK=true
                break
            else
                # Port is listening but health check fails - wait more
                echo -e "  ${YELLOW}Port listening but health check pending...${NC}"
            fi
        fi

        # Check if tmux session died
        if ! tmux has-session -t newavata 2>/dev/null; then
            echo -e "  ${RED}[${WAITED}s] NewAvata tmux session died!${NC}"
            break
        fi

        sleep 5
        WAITED=$((WAITED + 5))
    done

    echo ""

    # Final status check
    if tmux has-session -t newavata 2>/dev/null; then
        echo -e "  ${GREEN}NewAvata tmux session is running${NC}"
    else
        echo -e "  ${RED}NewAvata tmux session died!${NC}"
    fi

    # If NewAvata failed, show detailed error logs
    if [ "$NEWAVATA_OK" = false ]; then
        echo ""
        echo -e "  ${RED}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${RED}║           NewAvata ERROR DETAILS                         ║${NC}"
        echo -e "  ${RED}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""

        # [1] Full Startup Log
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}[1/6] FULL STARTUP LOG (/tmp/newavata_startup.log):${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        if [ -f "/tmp/newavata_startup.log" ]; then
            echo ""
            cat /tmp/newavata_startup.log | tail -100
            echo ""
        else
            echo "    (log file not found)"
        fi

        # [2] Tmux Session Output
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}[2/6] TMUX SESSION OUTPUT:${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        if tmux has-session -t newavata 2>/dev/null; then
            echo ""
            tmux capture-pane -t newavata -p 2>/dev/null | tail -80
            echo ""
        else
            echo "    (tmux session not running)"
        fi

        # [3] Error Pattern Analysis
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}[3/6] ERROR PATTERN ANALYSIS:${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        ERROR_FOUND=false

        if [ -f "/tmp/newavata_startup.log" ]; then
            # Check each error type with detailed info
            if grep -q "IndentationError" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ IndentationError detected - Python syntax error${NC}"
                grep -B3 -A5 "IndentationError" /tmp/newavata_startup.log | head -15
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "SyntaxError" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ SyntaxError detected - Python syntax error${NC}"
                grep -B3 -A5 "SyntaxError" /tmp/newavata_startup.log | head -15
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "ModuleNotFoundError" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ ModuleNotFoundError detected - Missing module${NC}"
                grep -B2 -A2 "ModuleNotFoundError" /tmp/newavata_startup.log | head -10
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "ImportError" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ ImportError detected - Import failure${NC}"
                grep -B2 -A2 "ImportError" /tmp/newavata_startup.log | head -10
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "TypeError" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ TypeError detected${NC}"
                grep -B5 -A5 "TypeError" /tmp/newavata_startup.log | head -15
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "FileNotFoundError" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ FileNotFoundError detected - Missing file${NC}"
                grep -B2 -A2 "FileNotFoundError" /tmp/newavata_startup.log | head -10
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "EOFError" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ EOFError detected - Corrupted model file${NC}"
                grep -B5 -A2 "EOFError" /tmp/newavata_startup.log | head -10
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "RuntimeError" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ RuntimeError detected${NC}"
                grep -B3 -A5 "RuntimeError" /tmp/newavata_startup.log | head -15
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "CUDA" /tmp/newavata_startup.log | grep -qi "error\|fail"; then
                echo -e "    ${RED}✗ CUDA Error detected${NC}"
                grep -i "CUDA" /tmp/newavata_startup.log | head -10
                echo ""
                ERROR_FOUND=true
            fi

            if grep -q "OutOfMemoryError\|OOM\|out of memory" /tmp/newavata_startup.log; then
                echo -e "    ${RED}✗ Out of Memory Error detected${NC}"
                grep -i "memory\|OOM" /tmp/newavata_startup.log | head -10
                echo ""
                ERROR_FOUND=true
            fi

            # Check if server is stuck at specific point
            if grep -q "Lipsync Server 시작" /tmp/newavata_startup.log; then
                LAST_LINE=$(tail -1 /tmp/newavata_startup.log)
                if [[ "$LAST_LINE" == *"시작"* ]] || [[ "$LAST_LINE" == *"loading"* ]] || [[ "$LAST_LINE" == *"Loading"* ]]; then
                    echo -e "    ${YELLOW}⚠ Server appears STUCK during initialization${NC}"
                    echo -e "      Last activity: $LAST_LINE"
                    echo ""
                    ERROR_FOUND=true
                fi
            fi
        fi

        if [ "$ERROR_FOUND" = false ]; then
            echo -e "    ${YELLOW}No specific error patterns detected in log${NC}"
            echo -e "    ${CYAN}Possible causes:${NC}"
            echo -e "      - Server is still loading models (may take >2 min)"
            echo -e "      - Server is hung during model initialization"
            echo -e "      - GPU memory allocation is stuck"
        fi

        # [4] Check patched app.py for syntax errors
        echo ""
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}[4/6] APP.PY SYNTAX CHECK:${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        if [ -f "$NEWAVATA_APP_DIR/app.py" ]; then
            cd "$NEWAVATA_APP_DIR"
            if [ -f "venv/bin/activate" ]; then
                source venv/bin/activate 2>/dev/null
            fi

            SYNTAX_CHECK=$(python -m py_compile app.py 2>&1)
            if [ -z "$SYNTAX_CHECK" ]; then
                echo -e "    ${GREEN}✓ app.py syntax: OK${NC}"
            else
                echo -e "    ${RED}✗ app.py syntax ERROR:${NC}"
                echo ""
                echo "$SYNTAX_CHECK"
                echo ""

                # Show the problematic lines
                echo -e "    ${YELLOW}Problematic code section:${NC}"
                # Extract line number from error
                LINE_NUM=$(echo "$SYNTAX_CHECK" | grep -oE 'line [0-9]+' | grep -oE '[0-9]+' | head -1)
                if [ -n "$LINE_NUM" ]; then
                    START=$((LINE_NUM - 5))
                    [ $START -lt 1 ] && START=1
                    END=$((LINE_NUM + 5))
                    echo "    Lines $START-$END of app.py:"
                    awk "NR>=$START && NR<=$END {printf \"    %4d: %s\\n\", NR, \$0}" app.py
                fi
            fi
            cd "$SCRIPT_DIR"
        else
            echo -e "    ${RED}app.py not found at: $NEWAVATA_APP_DIR/app.py${NC}"
        fi

        # [5] Model Files Check
        echo ""
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}[5/6] MODEL FILES STATUS:${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        MODEL_DIR="$NEWAVATA_APP_DIR/models"
        if [ -d "$MODEL_DIR" ]; then
            # Check critical model files
            echo -e "    ${CYAN}Critical Model Files:${NC}"

            # musetalkV15/unet.pth
            if [ -f "$MODEL_DIR/musetalkV15/unet.pth" ]; then
                SIZE=$(du -h "$MODEL_DIR/musetalkV15/unet.pth" 2>/dev/null | cut -f1)
                echo -e "    ✓ musetalkV15/unet.pth: ${GREEN}OK${NC} ($SIZE)"
            else
                echo -e "    ✗ musetalkV15/unet.pth: ${RED}MISSING${NC}"
            fi

            # musetalk/pytorch_model.bin
            if [ -f "$MODEL_DIR/musetalk/pytorch_model.bin" ]; then
                SIZE=$(du -h "$MODEL_DIR/musetalk/pytorch_model.bin" 2>/dev/null | cut -f1)
                echo -e "    ✓ musetalk/pytorch_model.bin: ${GREEN}OK${NC} ($SIZE)"
            else
                echo -e "    ✗ musetalk/pytorch_model.bin: ${RED}MISSING${NC}"
            fi

            # face-parse-bisent/79999_iter.pth
            if [ -f "$MODEL_DIR/face-parse-bisent/79999_iter.pth" ]; then
                SIZE=$(du -h "$MODEL_DIR/face-parse-bisent/79999_iter.pth" 2>/dev/null | cut -f1)
                echo -e "    ✓ face-parse-bisent/79999_iter.pth: ${GREEN}OK${NC} ($SIZE)"
            else
                echo -e "    ✗ face-parse-bisent/79999_iter.pth: ${RED}MISSING${NC}"
            fi

            # sd-vae
            if [ -f "$MODEL_DIR/sd-vae/diffusion_pytorch_model.bin" ]; then
                SIZE=$(du -h "$MODEL_DIR/sd-vae/diffusion_pytorch_model.bin" 2>/dev/null | cut -f1)
                echo -e "    ✓ sd-vae/diffusion_pytorch_model.bin: ${GREEN}OK${NC} ($SIZE)"
            else
                echo -e "    ✗ sd-vae/diffusion_pytorch_model.bin: ${RED}MISSING${NC}"
            fi
        else
            echo -e "    ${RED}Model directory not found: $MODEL_DIR${NC}"
        fi

        # [6] GPU Status
        echo ""
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}[6/6] GPU STATUS:${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        if command -v nvidia-smi &> /dev/null; then
            nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv 2>/dev/null | head -5 | sed 's/^/    /'
            echo ""

            # Check if GPU memory is nearly full
            MEM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '[:space:]')
            MEM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '[:space:]')

            if [[ "$MEM_USED" =~ ^[0-9]+$ ]] && [[ "$MEM_TOTAL" =~ ^[0-9]+$ ]]; then
                MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
                if [ "$MEM_PERCENT" -gt 90 ]; then
                    echo -e "    ${RED}⚠ GPU memory usage is at ${MEM_PERCENT}% - possible OOM issue${NC}"
                elif [ "$MEM_PERCENT" -gt 70 ]; then
                    echo -e "    ${YELLOW}⚠ GPU memory usage is at ${MEM_PERCENT}%${NC}"
                else
                    echo -e "    ${GREEN}✓ GPU memory usage: ${MEM_PERCENT}%${NC}"
                fi
            fi
        else
            echo -e "    ${YELLOW}nvidia-smi not available${NC}"
        fi

        echo ""
        echo -e "  ${RED}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${RED}║           END ERROR DETAILS                              ║${NC}"
        echo -e "  ${RED}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}Debug Commands:${NC}"
        echo -e "    ${YELLOW}tmux attach -t newavata${NC}  # View live server output"
        echo -e "    ${YELLOW}tail -f /tmp/newavata_startup.log${NC}  # View startup log"
        echo -e "    ${YELLOW}cd $NEWAVATA_APP_DIR && source venv/bin/activate && python app.py${NC}"
        echo ""

        # Option to restore original app.py and retry
        echo -e "  ${CYAN}If app.py is corrupted, restore and retry:${NC}"
        echo -e "    ${YELLOW}cd $NEWAVATA_APP_DIR && git checkout app.py${NC}"
        echo -e "    ${YELLOW}bash ~/Qwen3-TTS/start_full.sh${NC}"
        echo ""
    fi

    # Start TTS server in foreground
    cd "$SCRIPT_DIR"

    # Ensure we're using the correct Python environment
    # Force deactivate any active venv and reset PATH
    deactivate 2>/dev/null || true
    unset VIRTUAL_ENV 2>/dev/null || true

    # If Qwen3-TTS has its own venv, activate it
    if [ -f "$SCRIPT_DIR/venv/bin/activate" ]; then
        source "$SCRIPT_DIR/venv/bin/activate"
        echo -e "  ${GREEN}Activated Qwen3-TTS venv${NC}"
    fi

    # Verify TTS environment before starting
    echo -e "\n  ${CYAN}Verifying TTS environment...${NC}"

    # Check which Python we're using
    PYTHON_PATH=$(which python)
    echo -e "  Python: ${CYAN}$PYTHON_PATH${NC}"

    # Make sure we're not using NewAvata's Python
    if echo "$PYTHON_PATH" | grep -q "NewAvata"; then
        echo -e "  ${YELLOW}Warning: Using NewAvata Python, attempting to fix...${NC}"
        # Try to use system Python
        if [ -x "/usr/bin/python3" ]; then
            alias python=/usr/bin/python3
            export PATH="/usr/bin:$PATH"
        fi
    fi

    if ! python -c "import fastapi" 2>/dev/null; then
        echo -e "  ${YELLOW}fastapi missing after NewAvata setup, reinstalling...${NC}"
        pip install -r requirements.txt --quiet 2>/dev/null
    fi

    if python -c "import fastapi; import torch; print('OK')" 2>/dev/null | grep -q "OK"; then
        echo -e "  ${GREEN}TTS environment OK${NC}"
    else
        echo -e "  ${RED}TTS environment broken! Attempting repair...${NC}"
        pip install fastapi uvicorn torch soundfile numpy python-dotenv --quiet
    fi

    echo ""
    echo "==========================================="
    echo -e "  ${GREEN}Full Stack Ready!${NC}"
    echo "==========================================="
    echo -e "  TTS Server:     ${CYAN}http://localhost:8000${NC} (tmux: tts)"
    echo -e "  NewAvata:       ${CYAN}http://localhost:8001${NC} (tmux: newavata)"
    echo -e "  API Docs:       ${CYAN}http://localhost:8000/docs${NC}"
    echo -e "  Web UI:         ${CYAN}http://localhost:8000/ui${NC}"
    echo ""

    # =============================================
    # Auto-verification: Check NewAvata APIs
    # =============================================
    echo -e "${CYAN}=== Auto-Verification ===${NC}"
    echo ""

    # 1. Check TTS Engines
    echo -e "  ${YELLOW}[1/3] Checking TTS Engines...${NC}"
    TTS_ENGINES_RESPONSE=$(curl -s --max-time 10 http://localhost:8001/api/tts_engines 2>/dev/null || echo "")

    if [ -n "$TTS_ENGINES_RESPONSE" ]; then
        echo "$TTS_ENGINES_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    engines = data if isinstance(data, list) else data.get('engines', [])
    print('  TTS Engines:')
    for e in engines:
        name = e.get('name', 'unknown')
        avail = e.get('available', False)
        status = '\033[0;32m✓\033[0m' if avail else '\033[0;31m✗\033[0m'
        print(f'    {status} {name}: {\"available\" if avail else \"not available\"}')

    # Check qwen3tts specifically
    qwen = next((e for e in engines if e.get('name') == 'qwen3tts'), None)
    if qwen and qwen.get('available'):
        print('\n  \033[0;32m✓ Qwen3-TTS integration: OK\033[0m')
    else:
        print('\n  \033[1;33m⚠ Qwen3-TTS not available - check QWEN3_TTS_API_URL\033[0m')
except Exception as ex:
    print(f'  Error parsing TTS engines: {ex}')
" 2>/dev/null || echo -e "    ${RED}Failed to parse TTS engines response${NC}"
    else
        echo -e "    ${RED}Could not reach /api/tts_engines${NC}"
    fi
    echo ""

    # 2. Check Avatars
    echo -e "  ${YELLOW}[2/3] Checking Avatars...${NC}"
    AVATARS_RESPONSE=$(curl -s --max-time 10 http://localhost:8001/api/avatars 2>/dev/null || echo "")

    if [ -n "$AVATARS_RESPONSE" ]; then
        AVATAR_COUNT=$(echo "$AVATARS_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    avatars = data if isinstance(data, list) else []
    print(len(avatars))
except:
    print(0)
" 2>/dev/null || echo "0")

        if [ "$AVATAR_COUNT" -gt 0 ]; then
            echo -e "    ${GREEN}✓ Found $AVATAR_COUNT avatar(s)${NC}"
            echo "$AVATARS_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    avatars = data if isinstance(data, list) else []
    for a in avatars[:5]:
        name = a.get('name', str(a))
        print(f'      - {name}')
    if len(avatars) > 5:
        print(f'      ... and {len(avatars)-5} more')
except:
    pass
" 2>/dev/null
        else
            echo -e "    ${RED}✗ No avatars found!${NC}"
            echo -e "    ${YELLOW}Run: bash setup_avatar.sh${NC}"
        fi
    else
        echo -e "    ${RED}Could not reach /api/avatars${NC}"
    fi
    echo ""

    # 3. Quick health summary
    echo -e "  ${YELLOW}[3/3] System Summary...${NC}"
    TTS_HEALTH=$(curl -s --max-time 5 http://localhost:8000/health 2>/dev/null | grep -qi "ok\|healthy" && echo "OK" || echo "FAIL")

    # Try port 8001 first, then fallback to port 5000
    NEWAVATA_PORT=8001
    NEWAVATA_HEALTH=$(curl -s --max-time 5 http://localhost:8001/health 2>/dev/null | grep -qi "ok\|healthy\|status" && echo "OK" || echo "FAIL")
    if [ "$NEWAVATA_HEALTH" != "OK" ]; then
        # Try port 5000 as fallback
        NEWAVATA_HEALTH=$(curl -s --max-time 5 http://localhost:5000/health 2>/dev/null | grep -qi "ok\|healthy\|status" && echo "OK" || echo "FAIL")
        if [ "$NEWAVATA_HEALTH" = "OK" ]; then
            NEWAVATA_PORT=5000
            echo -e "    ${YELLOW}Note: NewAvata running on port 5000 (not 8001)${NC}"
        fi
    fi

    if [ "$TTS_HEALTH" = "OK" ]; then
        echo -e "    ${GREEN}✓ TTS Server: Running${NC}"
    else
        echo -e "    ${YELLOW}⚠ TTS Server: Not started yet (will start below)${NC}"
    fi

    if [ "$NEWAVATA_HEALTH" = "OK" ]; then
        echo -e "    ${GREEN}✓ NewAvata Server: Running (port $NEWAVATA_PORT)${NC}"
    else
        echo -e "    ${RED}✗ NewAvata Server: Not responding (tried 8001 and 5000)${NC}"
    fi

    if [ "$AVATAR_COUNT" -gt 0 ]; then
        echo -e "    ${GREEN}✓ Avatars: $AVATAR_COUNT available${NC}"
    else
        echo -e "    ${RED}✗ Avatars: None available${NC}"
    fi
    echo ""

    echo -e "${CYAN}=== Verification Complete ===${NC}"
    echo ""

    # === AUTOMATIC LIP-SYNC TEST ===
    echo -e "${CYAN}=== Running Lip-sync Test ===${NC}"
    echo ""

    # Only run test if both servers are healthy and avatars exist
    if [ "$TTS_HEALTH" = "OK" ] && [ "$NEWAVATA_HEALTH" = "OK" ] && [ "$AVATAR_COUNT" -gt 0 ]; then
        echo -e "  ${YELLOW}[테스트] 립싱크 생성 중...${NC}"
        echo -e "  Text: 안녕하세요, 립싱크 테스트입니다."
        echo -e "  Port: $NEWAVATA_PORT"
        echo ""

        # Run lip-sync test with timeout (use detected port)
        LIPSYNC_RESULT=$(curl -s --max-time 300 -X POST "http://localhost:${NEWAVATA_PORT}/api/v2/lipsync" \
            -H 'Content-Type: application/json' \
            -d '{"text":"안녕하세요, 립싱크 테스트입니다.","tts_engine":"qwen3tts","avatar":"auto","resolution":"480p"}' 2>/dev/null)

        if echo "$LIPSYNC_RESULT" | grep -qi "success.*true\|video_url"; then
            VIDEO_URL=$(echo "$LIPSYNC_RESULT" | grep -oP '"video_url"\s*:\s*"\K[^"]+' | head -1)
            echo -e "  ${GREEN}✓ 립싱크 테스트 성공!${NC}"
            if [ -n "$VIDEO_URL" ]; then
                echo -e "  ${GREEN}  Video URL: http://localhost:${NEWAVATA_PORT}${VIDEO_URL}${NC}"
            fi
            echo ""
        elif echo "$LIPSYNC_RESULT" | grep -qi "error\|fail"; then
            ERROR_MSG=$(echo "$LIPSYNC_RESULT" | grep -oP '"error"\s*:\s*"\K[^"]+' | head -1)
            echo -e "  ${RED}✗ 립싱크 테스트 실패${NC}"
            if [ -n "$ERROR_MSG" ]; then
                echo -e "  ${RED}  Error: $ERROR_MSG${NC}"
            fi
            echo ""
            echo -e "  ${YELLOW}디버그: NewAvata 로그 확인${NC}"
            echo -e "    tmux attach -t newavata"
            echo ""
        else
            echo -e "  ${YELLOW}⚠ 립싱크 테스트 타임아웃 또는 응답 없음${NC}"
            echo -e "  Response: ${LIPSYNC_RESULT:0:200}"
            echo ""
        fi
    else
        echo -e "  ${YELLOW}⚠ 립싱크 테스트 건너뜀 (서버 또는 아바타 준비 안됨)${NC}"
        if [ "$TTS_HEALTH" != "OK" ]; then
            echo -e "    - TTS 서버 확인 필요"
        fi
        if [ "$NEWAVATA_HEALTH" != "OK" ]; then
            echo -e "    - NewAvata 서버 확인 필요"
        fi
        if [ "$AVATAR_COUNT" -eq 0 ]; then
            echo -e "    - 아바타 설정 필요: bash setup_avatar.sh"
        fi
        echo ""
    fi

    echo -e "  ${YELLOW}수동 테스트 (새 터미널에서):${NC}"
    echo -e "    curl -X POST http://localhost:${NEWAVATA_PORT:-8001}/api/v2/lipsync \\"
    echo -e "      -H 'Content-Type: application/json' \\"
    echo -e "      -d '{\"text\":\"안녕하세요\",\"tts_engine\":\"qwen3tts\",\"avatar\":\"auto\",\"resolution\":\"480p\"}'"
    echo ""
    echo -e "  ${YELLOW}테스트 스크립트 사용:${NC}"
    echo -e "    cd ~/Qwen3-TTS && NEWAVATA_URL=http://localhost:${NEWAVATA_PORT:-8001} python test_lipsync_rest.py \"안녕하세요\""
    echo ""

    # Both servers are now running in tmux sessions
    echo -e "${GREEN}==========================================="
    echo -e "  All servers running in background!"
    echo -e "===========================================${NC}"
    echo ""
    echo -e "  ${CYAN}Tmux sessions:${NC}"
    echo -e "    ${YELLOW}tmux attach -t tts${NC}       # View TTS server logs"
    echo -e "    ${YELLOW}tmux attach -t newavata${NC}  # View NewAvata logs"
    echo ""
    echo -e "  ${CYAN}Stop servers:${NC}"
    echo -e "    ${YELLOW}tmux kill-session -t tts${NC}"
    echo -e "    ${YELLOW}tmux kill-session -t newavata${NC}"
    echo ""
    echo -e "  ${CYAN}Restart all:${NC}"
    echo -e "    ${YELLOW}bash ~/Qwen3-TTS/start_full.sh${NC}"
    echo ""

    # Optional: Tail logs in foreground
    echo -e "  ${CYAN}Monitoring TTS server logs (Ctrl+C to exit)...${NC}"
    echo ""
    tail -f /tmp/tts_startup.log 2>/dev/null || echo "Log file not available"

else
    # No tmux - use background process
    echo -e "  ${YELLOW}tmux not found, using background processes${NC}"

    # Start NewAvata in background
    if [ -d "$NEWAVATA_APP_DIR" ]; then
        cd "$NEWAVATA_APP_DIR"

        # Activate venv if exists
        if [ -f "venv/bin/activate" ]; then
            source venv/bin/activate
        fi

        # CRITICAL: Set PYTHONPATH to include MuseTalk module
        MUSETALK_PATH="$HOME/NewAvata/MuseTalk"
        if [ -d "$MUSETALK_PATH" ]; then
            export PYTHONPATH="${PYTHONPATH}:${MUSETALK_PATH}"
            echo -e "  ${GREEN}PYTHONPATH set to include MuseTalk${NC}"
        fi

        # Start server (try multiple methods)
        NEWAVATA_LOG="/tmp/newavata.log"
        if [ -f "run_server.sh" ]; then
            nohup bash run_server.sh > "$NEWAVATA_LOG" 2>&1 &
        elif [ -f "main.py" ]; then
            nohup python main.py --port 8001 > "$NEWAVATA_LOG" 2>&1 &
        elif [ -f "app.py" ]; then
            nohup uvicorn app:app --host 0.0.0.0 --port 8001 > "$NEWAVATA_LOG" 2>&1 &
        fi

        NEWAVATA_PID=$!
        echo -e "  ${GREEN}NewAvata started (PID: $NEWAVATA_PID)${NC}"
        echo -e "    Log: $NEWAVATA_LOG"

        deactivate 2>/dev/null || true
    fi

    # Wait for NewAvata
    echo -e "  Waiting for NewAvata to initialize (15s)..."
    sleep 15

    # Start TTS server
    cd "$SCRIPT_DIR"

    # Ensure we're using system Python (not NewAvata venv)
    deactivate 2>/dev/null || true
    unset VIRTUAL_ENV 2>/dev/null || true

    # Verify TTS environment before starting
    echo -e "\n  ${CYAN}Verifying TTS environment...${NC}"
    if ! python -c "import fastapi" 2>/dev/null; then
        echo -e "  ${YELLOW}fastapi missing, reinstalling...${NC}"
        pip install -r requirements.txt --quiet 2>/dev/null
    fi

    if python -c "import fastapi; import torch; print('OK')" 2>/dev/null | grep -q "OK"; then
        echo -e "  ${GREEN}TTS environment OK${NC}"
    else
        echo -e "  ${RED}TTS environment broken! Attempting repair...${NC}"
        pip install fastapi uvicorn torch soundfile numpy python-dotenv --quiet
    fi

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

    # Kill any existing process on port 8000 before starting TTS server
    if command -v fuser &> /dev/null; then
        fuser -k 8000/tcp 2>/dev/null || true
        sleep 1
    fi

    python server.py
fi
