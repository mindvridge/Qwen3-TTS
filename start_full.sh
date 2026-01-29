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
    if wget -q -O "${WHEEL_DIR}/flash_attn.whl" "$FA_WHEEL_URL" 2>/dev/null; then
        pip install "${WHEEL_DIR}/flash_attn.whl" --quiet 2>/dev/null && \
            echo -e "  ${GREEN}Flash Attention installed from wheel${NC}" || \
            echo -e "  ${YELLOW}Flash Attention wheel install failed${NC}"
    fi
    rm -rf "$WHEEL_DIR"
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
    if [ ! -f "$MUSETALK_MODEL" ] || [ ! -f "$MUSETALK_JSON" ]; then
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
        echo -e "  ${GREEN}MuseTalk model already exists${NC}"
    fi

    # Fix 2: FaceParse BiSeNet model (79999_iter.pth)
    FACEPARSE_MODEL="$MODELS_DIR/face-parse-bisent/79999_iter.pth"
    if [ ! -f "$FACEPARSE_MODEL" ]; then
        echo -e "  Downloading FaceParse model..."
        mkdir -p "$MODELS_DIR/face-parse-bisent"

        # Download using Python with multiple fallback URLs
        python -c "
import os
import urllib.request
from huggingface_hub import hf_hub_download

output = '$FACEPARSE_MODEL'
os.makedirs(os.path.dirname(output), exist_ok=True)

# Method 1: Try HuggingFace alternatives
hf_sources = [
    ('gwang-kim/datid3d-finetuned-eg3d-car', 'face_parsing/79999_iter.pth'),
    ('h94/IP-Adapter-FaceID', 'models/parsing_model/79999_iter.pth'),
]

downloaded = False
for repo_id, filename in hf_sources:
    try:
        print(f'  Trying HuggingFace: {repo_id}')
        path = hf_hub_download(repo_id=repo_id, filename=filename)
        import shutil
        shutil.copy(path, output)
        if os.path.getsize(output) > 1000000:
            print(f'  Success from {repo_id}!')
            downloaded = True
            break
    except Exception as e:
        print(f'  Failed: {e}')
        continue

# Method 2: Try direct URLs
if not downloaded:
    urls = [
        'https://drive.usercontent.google.com/download?id=154JgKpzCPW82qINcVieuPH3fZ2e0P812&confirm=t',
    ]
    for url in urls:
        try:
            print(f'  Trying direct URL...')
            urllib.request.urlretrieve(url, output)
            if os.path.getsize(output) > 1000000:
                print(f'  Success!')
                downloaded = True
                break
        except Exception as e:
            print(f'  Failed: {e}')

if not downloaded:
    print('  Warning: Could not download FaceParse model')
" 2>/dev/null && echo -e "  ${GREEN}FaceParse model downloaded${NC}" || echo -e "  ${YELLOW}FaceParse model download skipped${NC}"
    else
        echo -e "  ${GREEN}FaceParse model already exists${NC}"
    fi

    # Fix 3: SD-VAE model (required for MuseTalk VAE)
    SDVAE_MODEL="$MODELS_DIR/sd-vae/config.json"
    if [ ! -f "$SDVAE_MODEL" ]; then
        echo -e "  Downloading SD-VAE model..."
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
        echo -e "  ${GREEN}SD-VAE model already exists${NC}"
    fi

    )  # End of subshell for model downloads
    echo -e "  ${GREEN}Model check subshell completed${NC}"
fi

# Setup NewAvata precomputed avatars
echo -e "\n${YELLOW}[6/7] Setting up NewAvata avatars...${NC}"

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
                                python "$PRECOMPUTE_SCRIPT" --video "$video" --output "$output_pkl" 2>&1 | tail -5
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

    # Ensure we're using system Python (not NewAvata venv)
    # Force deactivate any active venv
    deactivate 2>/dev/null || true
    unset VIRTUAL_ENV 2>/dev/null || true

    # Verify TTS environment before starting
    echo -e "\n  ${CYAN}Verifying TTS environment...${NC}"
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
