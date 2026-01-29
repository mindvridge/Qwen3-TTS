#!/bin/bash
# Quick fix script for FaceParse model on Elice AI Cloud
# Run this if start_full.sh fails with FaceParse EOFError

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${YELLOW}=== FaceParse Model Quick Fix ===${NC}"

# Paths
NEWAVATA_DIR="${NEWAVATA_DIR:-$HOME/NewAvata}"
NEWAVATA_APP_DIR="$NEWAVATA_DIR/realtime-interview-avatar"
MODELS_DIR="$NEWAVATA_APP_DIR/models"
MUSETALK_MODELS="$NEWAVATA_DIR/MuseTalk/models"

FACEPARSE_MODEL="$MODELS_DIR/face-parse-bisent/79999_iter.pth"

# Step 1: Delete corrupted files
echo -e "\n${CYAN}[1/4] Removing corrupted FaceParse models...${NC}"
rm -f "$FACEPARSE_MODEL"
rm -rf "$MUSETALK_MODELS/face-parse-bisent"
echo -e "${GREEN}Done${NC}"

# Step 2: Activate venv
echo -e "\n${CYAN}[2/4] Activating NewAvata venv...${NC}"
if [ -f "$NEWAVATA_APP_DIR/venv/bin/activate" ]; then
    source "$NEWAVATA_APP_DIR/venv/bin/activate"
    echo -e "${GREEN}Activated${NC}"
else
    echo -e "${YELLOW}No venv found, using system Python${NC}"
fi

# Step 3: Download and validate
echo -e "\n${CYAN}[3/4] Downloading FaceParse model...${NC}"
mkdir -p "$(dirname $FACEPARSE_MODEL)"

python3 << 'PYTHON_SCRIPT'
import os
import shutil
import torch
from huggingface_hub import hf_hub_download

output = os.environ.get('FACEPARSE_MODEL',
    os.path.expanduser('~/NewAvata/realtime-interview-avatar/models/face-parse-bisent/79999_iter.pth'))
os.makedirs(os.path.dirname(output), exist_ok=True)

# Try multiple sources
sources = [
    ('camenduru/MuseTalk', 'models/face-parse-bisent/79999_iter.pth'),
    ('TMElyralab/MuseTalk', 'models/face-parse-bisent/79999_iter.pth'),
]

downloaded = False
for repo_id, filename in sources:
    try:
        print(f'  Trying: {repo_id}')
        path = hf_hub_download(repo_id=repo_id, filename=filename)
        shutil.copy(path, output)

        # Validate
        print(f'  Validating with torch.load...')
        torch.load(output, map_location='cpu', weights_only=False)
        print(f'  SUCCESS: Downloaded and validated from {repo_id}')
        downloaded = True
        break
    except Exception as e:
        print(f'  Failed: {e}')
        if os.path.exists(output):
            os.remove(output)
        continue

if not downloaded:
    print('ERROR: Could not download FaceParse model from any source')
    exit(1)
PYTHON_SCRIPT

export FACEPARSE_MODEL
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Download successful${NC}"
else
    echo -e "${YELLOW}Download failed${NC}"
    exit 1
fi

# Step 4: Create symlinks
echo -e "\n${CYAN}[4/4] Creating MuseTalk symlinks...${NC}"
mkdir -p "$MUSETALK_MODELS/face-parse-bisent"
ln -sf "$FACEPARSE_MODEL" "$MUSETALK_MODELS/face-parse-bisent/79999_iter.pth" 2>/dev/null || \
    cp "$FACEPARSE_MODEL" "$MUSETALK_MODELS/face-parse-bisent/79999_iter.pth"
echo -e "${GREEN}Symlink created${NC}"

echo -e "\n${GREEN}=== FaceParse Fix Complete ===${NC}"
echo -e "Model: $FACEPARSE_MODEL"
echo -e "Symlink: $MUSETALK_MODELS/face-parse-bisent/79999_iter.pth"
echo ""
echo -e "Now run: ${CYAN}bash start_full.sh${NC}"
