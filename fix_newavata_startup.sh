#!/bin/bash
# NewAvata Startup Fix Script
# Fixes the core issues preventing NewAvata from starting
# Run this once, then run start_full.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== NewAvata Startup Fix ===${NC}"
echo ""

NEWAVATA_DIR="${NEWAVATA_DIR:-$HOME/NewAvata}"
NEWAVATA_APP_DIR="$NEWAVATA_DIR/realtime-interview-avatar"

# Check if NewAvata exists
if [ ! -d "$NEWAVATA_APP_DIR" ]; then
    echo -e "${RED}ERROR: NewAvata not found at $NEWAVATA_APP_DIR${NC}"
    exit 1
fi

cd "$NEWAVATA_APP_DIR"

# Activate venv
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo -e "${GREEN}Activated venv${NC}"
fi

# Step 1: Reset app.py to original state
echo -e "\n${YELLOW}[1/4] Resetting app.py to original...${NC}"
git checkout app.py 2>/dev/null && echo -e "  ${GREEN}Reset complete${NC}" || echo -e "  ${CYAN}Already clean${NC}"

# Step 2: Fix Whisper warmup bug
echo -e "\n${YELLOW}[2/4] Fixing Whisper warmup bug in app.py...${NC}"

python3 << 'PATCH_APP'
import re

with open('app.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Check if already patched
if '# WHISPER_WARMUP_PATCHED' in content:
    print('  Already patched')
    exit(0)

# Find and comment out the problematic Whisper warmup code
# The bug: get_audio_feature((dummy_audio_np, 16000)) passes tuple instead of file path

# Pattern 1: Direct tuple call
old_pattern1 = r'(\s+)(whisper_features, librosa_len = self\.audio_processor\.get_audio_feature\(\(dummy_audio_np, 16000\)\))'
new_pattern1 = r'\1# WHISPER_WARMUP_PATCHED: Disabled - tuple not supported by get_audio_feature\n\1# \2\n\1whisper_features, librosa_len = None, 0  # Warmup skipped'

if re.search(old_pattern1, content):
    content = re.sub(old_pattern1, new_pattern1, content)
    print('  Fixed tuple call pattern')
else:
    # Pattern 2: Look for the entire warmup section and skip it
    # Find "Whisper 워밍업" section
    lines = content.split('\n')
    new_lines = []
    skip_mode = False
    skip_indent = 0

    for i, line in enumerate(lines):
        if 'Whisper 워밍업' in line and 'print' in line:
            # Start skipping
            indent = len(line) - len(line.lstrip())
            skip_indent = indent
            new_lines.append(' ' * indent + '# WHISPER_WARMUP_PATCHED: Disabled problematic warmup')
            new_lines.append(' ' * indent + 'print("    Whisper 워밍업... (SKIPPED)")')
            skip_mode = True
            continue

        if skip_mode:
            current_indent = len(line) - len(line.lstrip()) if line.strip() else skip_indent + 1
            # Stop skipping when we hit a new section or less indentation
            if line.strip() and (
                current_indent <= skip_indent or
                'print("  ' in line or  # New section print
                'self.whisper_processor' in line or
                'return' in line.startswith
            ):
                skip_mode = False
                new_lines.append(line)
            else:
                # Comment out this line
                if line.strip():
                    new_lines.append(' ' * skip_indent + '# SKIPPED: ' + line.strip())
                continue
        else:
            new_lines.append(line)

    content = '\n'.join(new_lines)
    print('  Fixed warmup section')

with open('app.py', 'w', encoding='utf-8') as f:
    f.write(content)

print('  Whisper warmup bug fixed!')
PATCH_APP

# Step 3: Fix PyTorch 2.6 weights_only issue
echo -e "\n${YELLOW}[3/4] Fixing PyTorch 2.6 compatibility...${NC}"

# Patch all torch.load calls in the project
find . -name "*.py" -type f 2>/dev/null | while read pyfile; do
    if grep -q "torch\.load(" "$pyfile" 2>/dev/null; then
        if ! grep -q "weights_only" "$pyfile" 2>/dev/null; then
            sed -i 's/torch\.load(\([^)]*\))/torch.load(\1, weights_only=False)/g' "$pyfile" 2>/dev/null
            # Fix double parameters
            sed -i 's/, , weights_only=False/, weights_only=False/g' "$pyfile" 2>/dev/null
            sed -i 's/, weights_only=False, weights_only=False/, weights_only=False/g' "$pyfile" 2>/dev/null
            echo -e "  Patched: $pyfile"
        fi
    fi
done

# Also patch MuseTalk
MUSETALK_DIR="$NEWAVATA_DIR/MuseTalk"
if [ -d "$MUSETALK_DIR" ]; then
    find "$MUSETALK_DIR" -name "*.py" -type f 2>/dev/null | while read pyfile; do
        if grep -q "torch\.load(" "$pyfile" 2>/dev/null; then
            if ! grep -q "weights_only" "$pyfile" 2>/dev/null; then
                sed -i 's/torch\.load(\([^)]*\))/torch.load(\1, weights_only=False)/g' "$pyfile" 2>/dev/null
                sed -i 's/, , weights_only=False/, weights_only=False/g' "$pyfile" 2>/dev/null
                echo -e "  Patched: $pyfile"
            fi
        fi
    done
fi

echo -e "  ${GREEN}PyTorch 2.6 compatibility fixed${NC}"

# Step 4: Test app.py syntax
echo -e "\n${YELLOW}[4/4] Validating app.py syntax...${NC}"
if python -m py_compile app.py 2>&1; then
    echo -e "  ${GREEN}Syntax OK${NC}"
else
    echo -e "  ${RED}Syntax ERROR - restoring original${NC}"
    git checkout app.py
    exit 1
fi

echo ""
echo -e "${GREEN}=== Fix Complete ===${NC}"
echo ""
echo -e "Now run: ${CYAN}bash ~/Qwen3-TTS/start_full.sh${NC}"
