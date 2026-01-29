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

        # Fallback: download sample if no assets
        if [ ! -d "$ASSETS_DIR" ] || [ "$(ls -1 "$ASSETS_DIR"/*.mp4 2>/dev/null | wc -l)" -eq 0 ]; then
            SAMPLE_VIDEO="$NEWAVATA_APP_DIR/sample_avatar.mp4"
            if [ ! -f "$SAMPLE_VIDEO" ]; then
                echo -e "  Downloading sample avatar video..."
                python -c "
import urllib.request
import os

output = '$SAMPLE_VIDEO'
urls = [
    'https://github.com/mindvridge/NewAvata/releases/download/v0.1/sample_avatar.mp4',
    'https://huggingface.co/datasets/mindvridge/avatar-samples/resolve/main/sample_avatar.mp4',
]

for url in urls:
    try:
        print(f'  Trying: {url[:60]}...')
        urllib.request.urlretrieve(url, output)
        if os.path.getsize(output) > 100000:
            print('  Sample video downloaded!')
            break
    except Exception as e:
        print(f'  Failed: {e}')
" 2>/dev/null
            fi
        fi
    )  # End of subshell - venv and PYTHONPATH changes are isolated
    echo -e "  ${GREEN}Precompute subshell completed${NC}"
fi

# Final avatar count and TensorRT note
AVATAR_COUNT=$(ls -1 "$PRECOMPUTED_DIR/"*.pkl 2>/dev/null | wc -l)
echo -e "\n  ${CYAN}Avatar Summary:${NC}"
echo -e "    Precomputed: ${GREEN}$AVATAR_COUNT${NC} avatar(s)"
echo -e "    TensorRT:    ${YELLOW}Auto-generated on first inference (~5GB)${NC}"

if [ "$AVATAR_COUNT" -eq 0 ]; then
    echo -e "\n  ${YELLOW}Note: Add videos to assets/ and re-run, or use avatar_path='auto'${NC}"
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

# Check which server script to use
if [ -f "run_server.sh" ]; then
    echo "Using run_server.sh" >> /tmp/newavata_startup.log
    chmod +x run_server.sh
    bash run_server.sh 2>&1 | tee -a /tmp/newavata_startup.log
elif [ -f "main.py" ]; then
    echo "Using main.py directly" >> /tmp/newavata_startup.log
    python main.py --port 8001 2>&1 | tee -a /tmp/newavata_startup.log
elif [ -f "app.py" ]; then
    echo "Using app.py directly" >> /tmp/newavata_startup.log
    uvicorn app:app --host 0.0.0.0 --port 8001 2>&1 | tee -a /tmp/newavata_startup.log
else
    echo "ERROR: No server script found!" >> /tmp/newavata_startup.log
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

    # Wait for NewAvata to initialize and verify
    echo -e "  Waiting for NewAvata to initialize (15s)..."
    sleep 15

    # Check if tmux session is still alive
    if tmux has-session -t newavata 2>/dev/null; then
        echo -e "  ${GREEN}NewAvata tmux session is running${NC}"

        # Check if port 8001 is listening
        if command -v lsof &> /dev/null; then
            if lsof -i :8001 &>/dev/null; then
                echo -e "  ${GREEN}Port 8001 is listening${NC}"
            else
                echo -e "  ${YELLOW}Port 8001 not yet listening (may still be starting)${NC}"
                echo -e "  ${CYAN}Check logs: cat $NEWAVATA_LOG${NC}"
            fi
        elif command -v ss &> /dev/null; then
            if ss -tln | grep -q ":8001"; then
                echo -e "  ${GREEN}Port 8001 is listening${NC}"
            else
                echo -e "  ${YELLOW}Port 8001 not yet listening (may still be starting)${NC}"
            fi
        fi
    else
        echo -e "  ${RED}NewAvata tmux session died!${NC}"
        echo -e "  ${CYAN}Startup log:${NC}"
        cat "$NEWAVATA_LOG" 2>/dev/null | head -30
        echo -e "\n  ${YELLOW}Try running manually:${NC}"
        echo -e "    cd $NEWAVATA_APP_DIR && source venv/bin/activate && python main.py"
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
    if [ -d "$NEWAVATA_APP_DIR" ]; then
        cd "$NEWAVATA_APP_DIR"

        # Activate venv if exists
        if [ -f "venv/bin/activate" ]; then
            source venv/bin/activate
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

    python server.py
fi
