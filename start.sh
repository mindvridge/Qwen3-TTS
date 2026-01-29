#!/bin/bash
# =============================================================
# Qwen3-TTS Server Start Script
# For Elice AI Cloud (A100 GPU)
# =============================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# GitHub Release settings for pre-built Flash Attention wheel
GITHUB_REPO="mindvridge/Qwen3-TTS"
FA_WHEEL_TAG="flash-attn-wheels"
FA_WHEEL_NAME="flash_attn-2.8.3-cp310-cp310-linux_x86_64.whl"
FA_WHEEL_URL="https://github.com/${GITHUB_REPO}/releases/download/${FA_WHEEL_TAG}/${FA_WHEEL_NAME}"

# Timer functions
SCRIPT_START=$(date +%s)

elapsed_time() {
    local start=$1
    local end=$(date +%s)
    local diff=$((end - start))
    local min=$((diff / 60))
    local sec=$((diff % 60))
    if [ $min -gt 0 ]; then
        echo "${min}m ${sec}s"
    else
        echo "${sec}s"
    fi
}

total_elapsed() {
    elapsed_time $SCRIPT_START
}

# Progress indicator with time
run_with_progress() {
    local msg="$1"
    shift
    local start=$(date +%s)

    # Run command in background
    "$@" &
    local pid=$!

    # Show progress dots
    local dots=""
    while kill -0 $pid 2>/dev/null; do
        dots="${dots}."
        if [ ${#dots} -gt 30 ]; then
            dots="."
        fi
        printf "\r  ${CYAN}%s${NC}%s " "$msg" "$dots"
        sleep 1
    done

    # Wait for completion and get exit code
    wait $pid
    local exit_code=$?

    local time_taken=$(elapsed_time $start)

    if [ $exit_code -eq 0 ]; then
        printf "\r  ${GREEN}%s${NC} ${CYAN}(%s)${NC}          \n" "$msg" "$time_taken"
    else
        printf "\r  ${RED}%s FAILED${NC} ${CYAN}(%s)${NC}     \n" "$msg" "$time_taken"
        return $exit_code
    fi
}

echo ""
echo "=========================================="
echo "  Qwen3-TTS Server Starting..."
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="

# 1. Check Python & GPU
echo -e "\n${YELLOW}[1/6] Checking environment...${NC}"
STEP1_START=$(date +%s)
python --version
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null || \
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || \
    echo "GPU detected (details unavailable)"
else
    echo -e "${RED}Warning: nvidia-smi not found${NC}"
fi
echo -e "  ${CYAN}($(elapsed_time $STEP1_START))${NC}"

# 2. Pull latest code
echo -e "\n${YELLOW}[2/6] Pulling latest code...${NC}"
STEP2_START=$(date +%s)
if git pull --ff-only 2>/dev/null; then
    echo -e "  ${GREEN}Code updated${NC} ${CYAN}($(elapsed_time $STEP2_START))${NC}"
else
    echo -e "  ${CYAN}Using current code${NC} ${CYAN}($(elapsed_time $STEP2_START))${NC}"
fi

# 3. Install/Update dependencies
echo -e "\n${YELLOW}[3/6] Installing dependencies...${NC}"
STEP3_START=$(date +%s)
pip install -r requirements.txt --quiet --disable-pip-version-check 2>&1 | while read line; do
    printf "\r  ${CYAN}Installing packages...${NC} "
done
echo -e "\r  ${GREEN}Dependencies installed${NC} ${CYAN}($(elapsed_time $STEP3_START))${NC}          "

# 4. Check and install Flash Attention
echo -e "\n${YELLOW}[4/6] Checking Flash Attention...${NC}"
STEP4_START=$(date +%s)
if python -c "import flash_attn; print(f'  Flash Attention {flash_attn.__version__} installed')" 2>/dev/null; then
    echo -e "  ${GREEN}Flash Attention is ready${NC} ${CYAN}($(elapsed_time $STEP4_START))${NC}"
else
    FA_INSTALLED=false

    # Strategy 1: Try downloading pre-built wheel from GitHub Releases
    echo -e "  ${YELLOW}Trying pre-built wheel from GitHub Releases...${NC}"
    WHEEL_DIR="/tmp/fa_wheel"
    mkdir -p "$WHEEL_DIR"

    if wget -q --show-progress -O "${WHEEL_DIR}/${FA_WHEEL_NAME}" "${FA_WHEEL_URL}" 2>/dev/null || \
       curl -sL -o "${WHEEL_DIR}/${FA_WHEEL_NAME}" "${FA_WHEEL_URL}" 2>/dev/null; then
        # Verify file is a valid wheel (not an HTML error page)
        if file "${WHEEL_DIR}/${FA_WHEEL_NAME}" 2>/dev/null | grep -q "Zip\|archive" || \
           python -c "import zipfile; zipfile.ZipFile('${WHEEL_DIR}/${FA_WHEEL_NAME}')" 2>/dev/null; then
            echo -e "  ${CYAN}Installing from pre-built wheel...${NC}"
            if pip install "${WHEEL_DIR}/${FA_WHEEL_NAME}" --quiet --disable-pip-version-check 2>/dev/null; then
                FA_INSTALLED=true
                echo -e "  ${GREEN}Flash Attention installed from wheel${NC} ${CYAN}($(elapsed_time $STEP4_START))${NC}"
            fi
        else
            echo -e "  ${CYAN}Pre-built wheel not available${NC}"
        fi
    else
        echo -e "  ${CYAN}Pre-built wheel not found${NC}"
    fi
    rm -rf "$WHEEL_DIR"

    # Strategy 2: Compile from source (slow, ~2-3 hours)
    if [ "$FA_INSTALLED" = false ]; then
        echo -e "  ${YELLOW}Compiling Flash Attention from source...${NC}"
        echo -e "  ${CYAN}This takes 2-3 hours on first run. Server will start without it.${NC}"
        echo -e "  ${CYAN}Compilation continues in background.${NC}"

        # Start compilation in background
        (
            MAX_JOBS=4 pip install -U flash-attn --no-build-isolation > /tmp/flash_attn_build.log 2>&1
            BUILD_EXIT=$?
            if [ $BUILD_EXIT -eq 0 ]; then
                echo "[$(date '+%H:%M:%S')] Flash Attention compiled successfully!" >> /tmp/flash_attn_build.log
                # Save wheel for future use
                echo "[$(date '+%H:%M:%S')] Saving wheel file..." >> /tmp/flash_attn_build.log
                mkdir -p ~/flash_attn_wheels
                pip wheel flash-attn -w ~/flash_attn_wheels/ --no-deps --no-build-isolation >> /tmp/flash_attn_build.log 2>&1 || true
                echo "[$(date '+%H:%M:%S')] Wheel saved to ~/flash_attn_wheels/" >> /tmp/flash_attn_build.log
                echo "" >> /tmp/flash_attn_build.log
                echo "To upload wheel to GitHub Releases:" >> /tmp/flash_attn_build.log
                echo "  gh release create ${FA_WHEEL_TAG} ~/flash_attn_wheels/*.whl --repo ${GITHUB_REPO} --title 'Flash Attention Pre-built Wheels' --notes 'Pre-built for CUDA 12.4, Python 3.10, PyTorch 2.6'" >> /tmp/flash_attn_build.log
            else
                echo "[$(date '+%H:%M:%S')] Flash Attention compilation failed (exit code: $BUILD_EXIT)" >> /tmp/flash_attn_build.log
            fi
        ) &
        echo -e "  ${YELLOW}Background PID: $!${NC}"
        echo -e "  ${CYAN}Monitor: tail -f /tmp/flash_attn_build.log${NC}"
        echo -e "  ${YELLOW}Continuing without Flash Attention for now...${NC}"
    fi
fi

# 5. Create .env if not exists
echo -e "\n${YELLOW}[5/6] Configuring environment...${NC}"
STEP5_START=$(date +%s)
if [ ! -f .env ]; then
    cp .env.example .env
    # Set Flash Attention based on availability
    if python -c "import flash_attn" 2>/dev/null; then
        sed -i 's/TTS_USE_FLASH_ATTENTION=false/TTS_USE_FLASH_ATTENTION=true/' .env 2>/dev/null || true
        echo -e "  ${GREEN}.env created with Flash Attention enabled${NC} ${CYAN}($(elapsed_time $STEP5_START))${NC}"
    else
        echo -e "  ${GREEN}.env created (Flash Attention disabled)${NC} ${CYAN}($(elapsed_time $STEP5_START))${NC}"
    fi
else
    echo -e "  ${GREEN}.env already exists${NC} ${CYAN}($(elapsed_time $STEP5_START))${NC}"
fi

# 6. Install SoX (optional, for audio processing)
echo -e "\n${YELLOW}[6/6] Checking optional tools...${NC}"
STEP6_START=$(date +%s)
if command -v sox &> /dev/null; then
    echo -e "  ${GREEN}SoX is available${NC} ${CYAN}($(elapsed_time $STEP6_START))${NC}"
else
    if command -v apt-get &> /dev/null; then
        apt-get install -y sox libsox-dev > /dev/null 2>&1 && \
            echo -e "  ${GREEN}SoX installed${NC} ${CYAN}($(elapsed_time $STEP6_START))${NC}" || \
            echo -e "  ${CYAN}SoX not available (optional)${NC} ${CYAN}($(elapsed_time $STEP6_START))${NC}"
    else
        echo -e "  ${CYAN}SoX not available (optional)${NC} ${CYAN}($(elapsed_time $STEP6_START))${NC}"
    fi
fi

# Summary
echo ""
echo "=========================================="
echo -e "  ${GREEN}Setup Complete!${NC}"
echo -e "  Total time: ${CYAN}$(total_elapsed)${NC}"
echo "=========================================="

# Start server
echo ""
echo -e "${YELLOW}Starting Qwen3-TTS Server...${NC}"
echo -e "  URL:  ${CYAN}http://0.0.0.0:8000${NC}"
echo -e "  Docs: ${CYAN}http://0.0.0.0:8000/docs${NC}"
echo -e "  UI:   ${CYAN}http://0.0.0.0:8000/ui${NC}"
echo ""

python server.py
