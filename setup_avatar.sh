#!/bin/bash
# Avatar Setup Script for NewAvata Lip-sync
# Downloads a sample avatar video and precomputes it

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== NewAvata Avatar Setup ===${NC}"
echo ""

# Paths
NEWAVATA_DIR="${NEWAVATA_DIR:-$HOME/NewAvata}"
NEWAVATA_APP_DIR="$NEWAVATA_DIR/realtime-interview-avatar"
PRECOMPUTED_DIR="$NEWAVATA_APP_DIR/precomputed"
ASSETS_DIR="$NEWAVATA_APP_DIR/assets"

echo -e "${YELLOW}[1/4] Checking directories...${NC}"
echo "  NewAvata: $NEWAVATA_APP_DIR"
echo "  Precomputed: $PRECOMPUTED_DIR"
echo "  Assets: $ASSETS_DIR"

mkdir -p "$PRECOMPUTED_DIR"
mkdir -p "$ASSETS_DIR"

# Check for existing avatars
AVATAR_COUNT=$(ls -1 "$PRECOMPUTED_DIR/"*.pkl 2>/dev/null | wc -l || echo "0")
if [ "$AVATAR_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}Found $AVATAR_COUNT existing avatar(s):${NC}"
    ls -1 "$PRECOMPUTED_DIR/"*.pkl 2>/dev/null | while read f; do
        echo "    - $(basename $f)"
    done
    echo ""
    echo -e "${GREEN}Avatars already exist! Lip-sync should work.${NC}"
    exit 0
fi

echo -e "  ${YELLOW}No precomputed avatars found${NC}"

# Step 2: Download sample avatar video
echo -e "\n${YELLOW}[2/4] Downloading sample avatar video...${NC}"
SAMPLE_VIDEO="$ASSETS_DIR/sample_avatar.mp4"

if [ -f "$SAMPLE_VIDEO" ]; then
    echo -e "  ${GREEN}Sample video already exists${NC}"
else
    # Try multiple sources
    python3 << 'PYTHON_SCRIPT'
import os
import urllib.request

output = os.path.expanduser('~/NewAvata/realtime-interview-avatar/assets/sample_avatar.mp4')
os.makedirs(os.path.dirname(output), exist_ok=True)

sources = [
    'https://github.com/mindvridge/NewAvata/releases/download/v0.1/sample_avatar.mp4',
    'https://huggingface.co/datasets/mindvridge/avatar-samples/resolve/main/sample_avatar.mp4',
]

downloaded = False
for url in sources:
    try:
        print(f'  Trying: {url[:60]}...')
        urllib.request.urlretrieve(url, output)
        size = os.path.getsize(output)
        if size > 100000:  # > 100KB
            print(f'  Downloaded: {size/1024/1024:.1f}MB')
            downloaded = True
            break
        else:
            os.remove(output)
    except Exception as e:
        print(f'  Failed: {e}')

if not downloaded:
    print('ERROR: Could not download sample avatar')
    exit(1)

print('  SUCCESS')
PYTHON_SCRIPT

    if [ $? -ne 0 ]; then
        echo -e "  ${RED}Download failed${NC}"
        echo ""
        echo "Please manually provide a video file:"
        echo "  1. Upload a short video (5-10s) of a person speaking"
        echo "  2. Save to: $ASSETS_DIR/avatar.mp4"
        echo "  3. Re-run this script"
        exit 1
    fi
fi

# Step 3: Activate venv
echo -e "\n${YELLOW}[3/4] Setting up Python environment...${NC}"
cd "$NEWAVATA_APP_DIR"

if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo -e "  ${GREEN}Activated venv${NC}"
else
    echo -e "  ${YELLOW}No venv, using system Python${NC}"
fi

# Step 4: Precompute avatar
echo -e "\n${YELLOW}[4/4] Precomputing avatar (may take 5-10 minutes on GPU)...${NC}"

# Find precompute script
PRECOMPUTE_SCRIPT=""
if [ -f "scripts/precompute_avatar.py" ]; then
    PRECOMPUTE_SCRIPT="scripts/precompute_avatar.py"
elif [ -f "precompute_avatar.py" ]; then
    PRECOMPUTE_SCRIPT="precompute_avatar.py"
fi

if [ -z "$PRECOMPUTE_SCRIPT" ]; then
    echo -e "  ${RED}ERROR: precompute_avatar.py not found${NC}"
    echo "  Looking for alternatives..."

    # Try to find any precompute script
    find . -name "*precompute*.py" 2>/dev/null | head -5
    exit 1
fi

echo "  Using: $PRECOMPUTE_SCRIPT"

# Fix hardcoded Windows paths if present
if grep -q 'os.chdir("c:' "$PRECOMPUTE_SCRIPT" 2>/dev/null; then
    echo -e "  ${YELLOW}Fixing hardcoded Windows path...${NC}"
    sed -i 's|os.chdir("c:/NewAvata/NewAvata/realtime-interview-avatar")|os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))|g' "$PRECOMPUTE_SCRIPT"
fi

# Run precompute
OUTPUT_PKL="$PRECOMPUTED_DIR/sample_avatar.pkl"

echo "  Input: $SAMPLE_VIDEO"
echo "  Output: $OUTPUT_PKL"
echo ""

python "$PRECOMPUTE_SCRIPT" --video "$SAMPLE_VIDEO" --output "$OUTPUT_PKL" 2>&1 | tail -20

if [ -f "$OUTPUT_PKL" ]; then
    SIZE=$(stat -f%z "$OUTPUT_PKL" 2>/dev/null || stat -c%s "$OUTPUT_PKL" 2>/dev/null)
    echo ""
    echo -e "${GREEN}=== Avatar Precomputed Successfully ===${NC}"
    echo "  File: $OUTPUT_PKL"
    echo "  Size: $(echo "scale=1; $SIZE/1024/1024" | bc)MB"
    echo ""
    echo -e "Now restart NewAvata server and test lip-sync:"
    echo -e "  ${CYAN}tmux kill-session -t newavata${NC}"
    echo -e "  ${CYAN}bash start_full.sh${NC}"
else
    echo ""
    echo -e "${RED}ERROR: Precompute failed${NC}"
    echo "Check the logs above for errors."
    exit 1
fi
