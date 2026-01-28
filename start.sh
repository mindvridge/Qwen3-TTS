#!/bin/bash
# =============================================================
# Qwen3-TTS Server Start Script
# For Elice AI Cloud (A100 GPU)
# =============================================================

set -e  # Exit on error

echo "=========================================="
echo "  Qwen3-TTS Server Starting..."
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Check Python version
echo -e "\n${YELLOW}[1/5] Checking Python...${NC}"
python --version

# 2. Check GPU
echo -e "\n${YELLOW}[2/5] Checking GPU...${NC}"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
else
    echo -e "${RED}Warning: nvidia-smi not found${NC}"
fi

# 3. Install/Update dependencies
echo -e "\n${YELLOW}[3/5] Installing dependencies...${NC}"
pip install -r requirements.txt --quiet --disable-pip-version-check

# 4. Check and install Flash Attention
echo -e "\n${YELLOW}[4/5] Checking Flash Attention...${NC}"
if python -c "import flash_attn; print(f'Flash Attention {flash_attn.__version__} installed')" 2>/dev/null; then
    echo -e "${GREEN}Flash Attention is ready${NC}"
else
    echo -e "${YELLOW}Installing Flash Attention (this may take a few minutes)...${NC}"
    pip install -U flash-attn --no-build-isolation --quiet || \
        echo -e "${RED}Flash Attention installation failed, continuing without it${NC}"
fi

# 5. Create .env if not exists
if [ ! -f .env ]; then
    echo -e "\n${YELLOW}[5/5] Creating .env from template...${NC}"
    cp .env.example .env
    # Set Flash Attention to true for A100
    sed -i 's/TTS_USE_FLASH_ATTENTION=false/TTS_USE_FLASH_ATTENTION=true/' .env 2>/dev/null || true
    echo -e "${GREEN}.env created with A100 optimized settings${NC}"
else
    echo -e "\n${YELLOW}[5/5] .env already exists${NC}"
fi

# Start server
echo -e "\n=========================================="
echo -e "${GREEN}  Starting Qwen3-TTS Server${NC}"
echo -e "  URL: http://0.0.0.0:8000"
echo -e "  Docs: http://0.0.0.0:8000/docs"
echo -e "  UI: http://0.0.0.0:8000/ui"
echo -e "=========================================="

python server.py
