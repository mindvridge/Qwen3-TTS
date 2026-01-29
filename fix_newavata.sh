#!/bin/bash
# NewAvata Auto-Fix Script
# Automatically fixes unet.pth and restarts NewAvata server
# Usage: bash fix_newavata.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== NewAvata Auto-Fix Script ===${NC}"
echo ""

# Paths
NEWAVATA_DIR="${NEWAVATA_DIR:-$HOME/NewAvata}"
NEWAVATA_APP_DIR="$NEWAVATA_DIR/realtime-interview-avatar"
MODELS_DIR="$NEWAVATA_APP_DIR/models"

# Step 1: Create unet.pth
echo -e "${YELLOW}[1/4] Creating unet.pth...${NC}"
mkdir -p "$MODELS_DIR/musetalkV15"

if [ -f "$MODELS_DIR/musetalk/pytorch_model.bin" ]; then
    cp "$MODELS_DIR/musetalk/pytorch_model.bin" "$MODELS_DIR/musetalkV15/unet.pth"
    echo -e "  ${GREEN}unet.pth created${NC}"
else
    echo -e "  ${RED}ERROR: pytorch_model.bin not found${NC}"
    echo -e "  ${YELLOW}Downloading from HuggingFace...${NC}"

    # Activate venv if exists
    [ -f "$NEWAVATA_APP_DIR/venv/bin/activate" ] && source "$NEWAVATA_APP_DIR/venv/bin/activate"

    python3 -c "
from huggingface_hub import hf_hub_download
import shutil
import os

output = '$MODELS_DIR/musetalkV15/unet.pth'
os.makedirs(os.path.dirname(output), exist_ok=True)

sources = [
    ('TMElyralab/MuseTalk', 'models/musetalk/pytorch_model.bin'),
    ('netease-youdao/musetalk', 'models/musetalk/pytorch_model.bin'),
]

for repo_id, filename in sources:
    try:
        print(f'  Trying: {repo_id}')
        path = hf_hub_download(repo_id=repo_id, filename=filename)
        shutil.copy(path, output)
        print(f'  Downloaded from {repo_id}')
        break
    except Exception as e:
        print(f'  Failed: {e}')
"
    if [ -f "$MODELS_DIR/musetalkV15/unet.pth" ]; then
        echo -e "  ${GREEN}unet.pth downloaded${NC}"
    else
        echo -e "  ${RED}FATAL: Could not create unet.pth${NC}"
        exit 1
    fi
fi

# Step 2: Copy other required files
echo -e "${YELLOW}[2/4] Copying musetalk.json and pytorch_model.bin...${NC}"
[ -f "$MODELS_DIR/musetalk/musetalk.json" ] && cp "$MODELS_DIR/musetalk/musetalk.json" "$MODELS_DIR/musetalkV15/musetalk.json"
[ -f "$MODELS_DIR/musetalk/pytorch_model.bin" ] && cp "$MODELS_DIR/musetalk/pytorch_model.bin" "$MODELS_DIR/musetalkV15/pytorch_model.bin"
echo -e "  ${GREEN}Files copied${NC}"

# Step 3: Stop existing NewAvata
echo -e "${YELLOW}[3/4] Stopping existing NewAvata...${NC}"
tmux kill-session -t newavata 2>/dev/null && echo -e "  ${GREEN}Stopped${NC}" || echo -e "  ${CYAN}Not running${NC}"

# Step 4: Start NewAvata
echo -e "${YELLOW}[4/4] Starting NewAvata server...${NC}"
cd "$NEWAVATA_APP_DIR"

# Activate venv
[ -f "venv/bin/activate" ] && source venv/bin/activate

# Create startup script
cat > /tmp/start_newavata_fixed.sh << 'STARTUP'
#!/bin/bash
cd "$1"
[ -f "venv/bin/activate" ] && source venv/bin/activate

# Patch torch.load for PyTorch 2.6
find . -name "*.py" -type f 2>/dev/null | while read pyfile; do
    if grep -q "torch\.load(" "$pyfile" 2>/dev/null; then
        if ! grep -q "weights_only" "$pyfile" 2>/dev/null; then
            sed -i 's/torch\.load(\([^)]*\))/torch.load(\1, weights_only=False)/g' "$pyfile" 2>/dev/null
            sed -i 's/, , weights_only=False/, weights_only=False/g' "$pyfile" 2>/dev/null
        fi
    fi
done

# Start server
if [ -f "app.py" ]; then
    python app.py --host 0.0.0.0 --port 8001
elif [ -f "main.py" ]; then
    python main.py --host 0.0.0.0 --port 8001
else
    echo "ERROR: No app.py or main.py found"
    exit 1
fi
STARTUP
chmod +x /tmp/start_newavata_fixed.sh

# Start in tmux
tmux new-session -d -s newavata "bash /tmp/start_newavata_fixed.sh $NEWAVATA_APP_DIR"
echo -e "  ${GREEN}NewAvata starting in tmux session 'newavata'${NC}"

# Wait and check
echo -e "\n${CYAN}Waiting 30 seconds for server startup...${NC}"
sleep 30

# Health check
echo -e "\n${YELLOW}Checking server health...${NC}"
HEALTH=$(curl -s http://localhost:8001/health 2>/dev/null || echo "FAILED")

if echo "$HEALTH" | grep -q "ok\|healthy\|running"; then
    echo -e "${GREEN}=== NewAvata Server Running ===${NC}"
    echo -e "  Health: $HEALTH"
    echo -e "  URL: ${CYAN}http://localhost:8001${NC}"
    echo -e "\n${GREEN}Now you can test lip-sync!${NC}"
else
    echo -e "${YELLOW}Server may still be starting...${NC}"
    echo -e "  Check logs: ${CYAN}tmux attach -t newavata${NC}"
    echo -e "  Or: ${CYAN}tail -f /tmp/newavata_startup.log${NC}"
fi

echo ""
echo -e "${CYAN}=== Fix Complete ===${NC}"
