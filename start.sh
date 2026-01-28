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

# 1. Check Python version
echo -e "\n${YELLOW}[1/5] Checking Python...${NC}"
STEP1_START=$(date +%s)
python --version
echo -e "  ${CYAN}($(elapsed_time $STEP1_START))${NC}"

# 2. Check GPU
echo -e "\n${YELLOW}[2/5] Checking GPU...${NC}"
STEP2_START=$(date +%s)
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null || \
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || \
    echo "GPU detected (details unavailable)"
else
    echo -e "${RED}Warning: nvidia-smi not found${NC}"
fi
echo -e "  ${CYAN}($(elapsed_time $STEP2_START))${NC}"

# 3. Install/Update dependencies
echo -e "\n${YELLOW}[3/5] Installing dependencies...${NC}"
STEP3_START=$(date +%s)
pip install -r requirements.txt --quiet --disable-pip-version-check 2>&1 | while read line; do
    printf "\r  ${CYAN}Installing packages...${NC} "
done
echo -e "\r  ${GREEN}Dependencies installed${NC} ${CYAN}($(elapsed_time $STEP3_START))${NC}          "

# 4. Check and install Flash Attention
echo -e "\n${YELLOW}[4/5] Checking Flash Attention...${NC}"
STEP4_START=$(date +%s)
if python -c "import flash_attn; print(f'  Flash Attention {flash_attn.__version__} installed')" 2>/dev/null; then
    echo -e "  ${GREEN}Flash Attention is ready${NC} ${CYAN}($(elapsed_time $STEP4_START))${NC}"
else
    echo -e "  ${YELLOW}Installing Flash Attention...${NC}"
    echo -e "  ${CYAN}This may take 5-10 minutes on first run${NC}"

    # Install with progress
    (
        MAX_JOBS=4 pip install -U flash-attn --no-build-isolation 2>&1 | while read line; do
            # Show compilation progress
            if [[ "$line" == *"Building"* ]] || [[ "$line" == *"Compiling"* ]]; then
                printf "\r  ${CYAN}Compiling CUDA kernels...${NC}     "
            elif [[ "$line" == *"Installing"* ]]; then
                printf "\r  ${CYAN}Installing package...${NC}         "
            fi
        done
    ) &
    INSTALL_PID=$!

    # Progress indicator
    SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    i=0
    while kill -0 $INSTALL_PID 2>/dev/null; do
        i=$(( (i + 1) % ${#SPINNER} ))
        printf "\r  ${CYAN}[${SPINNER:$i:1}] Installing Flash Attention... ${NC}($(elapsed_time $STEP4_START))"
        sleep 0.2
    done

    wait $INSTALL_PID
    INSTALL_EXIT=$?

    if [ $INSTALL_EXIT -eq 0 ]; then
        echo -e "\r  ${GREEN}Flash Attention installed${NC} ${CYAN}($(elapsed_time $STEP4_START))${NC}          "
    else
        echo -e "\r  ${RED}Flash Attention installation failed${NC} ${CYAN}($(elapsed_time $STEP4_START))${NC}"
        echo -e "  ${YELLOW}Continuing without Flash Attention...${NC}"
    fi
fi

# 5. Create .env if not exists
echo -e "\n${YELLOW}[5/5] Configuring environment...${NC}"
STEP5_START=$(date +%s)
if [ ! -f .env ]; then
    cp .env.example .env
    # Set Flash Attention to true for A100
    sed -i 's/TTS_USE_FLASH_ATTENTION=false/TTS_USE_FLASH_ATTENTION=true/' .env 2>/dev/null || true
    echo -e "  ${GREEN}.env created with A100 optimized settings${NC} ${CYAN}($(elapsed_time $STEP5_START))${NC}"
else
    echo -e "  ${GREEN}.env already exists${NC} ${CYAN}($(elapsed_time $STEP5_START))${NC}"
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
