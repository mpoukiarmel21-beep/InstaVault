#!/bin/bash
set -e

# ============================================================
# InstaVault - IPA Builder
# Compiles tweak + injects into Instagram IPA
# ============================================================

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== InstaVault IPA Builder ===${NC}"

# --- Config ---
INPUT_IPA="${1:-Input.ipa}"
OUTPUT_IPA="InstaVault.ipa"
DYLIB="obj/InstaVault.dylib"

# --- Check prerequisites ---
if ! command -v optool &> /dev/null; then
    echo -e "${RED}ERROR: optool not found. Install it first.${NC}"
    echo "  brew install optool  OR  build from https://github.com/alexzielenski/optool"
    exit 1
fi

if ! command -v ldid &> /dev/null; then
    echo -e "${RED}ERROR: ldid not found.${NC}"
    echo "  brew install ldid"
    exit 1
fi

if [ ! -f "$INPUT_IPA" ]; then
    echo -e "${RED}ERROR: $INPUT_IPA not found.${NC}"
    echo "Usage: ./build_ipa.sh <path_to_instagram.ipa>"
    exit 1
fi

# --- Step 1: Build tweak ---
echo -e "${BLUE}[1/5] Building tweak...${NC}"
cd Tweak
make clean all
cd ..
ls -la "$DYLIB" || { echo -e "${RED}ERROR: Dylib not found at $DYLIB${NC}"; exit 1; }

# --- Step 2: Extract IPA ---
echo -e "${BLUE}[2/5] Extracting IPA...${NC}"
WORKDIR=$(mktemp -d)
cd "$WORKDIR"
unzip -q "/$OLDPWD/$INPUT_IPA"
APP_PATH=$(find Payload -name "*.app" -maxdepth 1 | head -1)
echo "  App: $APP_PATH"

# --- Step 3: Inject dylib ---
echo -e "${BLUE}[3/5] Injecting dylib...${NC}"
mkdir -p "$APP_PATH/Frameworks"
cp "/$OLDPWD/$DYLIB" "$APP_PATH/Frameworks/InstaVault.dylib"
optool install -c load -p @executable_path/Frameworks/InstaVault.dylib -t "$APP_PATH/Instagram"

# --- Step 4: Copy entitlements & re-sign ---
echo -e "${BLUE}[4/5] Signing...${NC}"
ENT="/$OLDPWD/Entitlements/instagram.entitlements"

if [ -f "$ENT" ]; then
    ldid -S"$ENT" "$APP_PATH/Instagram"
    echo "  Signed with custom entitlements"
else
    ldid -S "$APP_PATH/Instagram"
    echo "  Ad-hoc signed"
fi

# --- Step 5: Re-package ---
echo -e "${BLUE}[5/5] Packaging IPA...${NC}"
rm -f "/$OLDPWD/$OUTPUT_IPA"
zip -r -q "/$OLDPWD/$OUTPUT_IPA" Payload/

# Cleanup
cd "$OLDPWD"
rm -rf "$WORKDIR"

echo ""
echo -e "${GREEN}=== Done! ===${NC}"
echo -e "Output: ${GREEN}$OUTPUT_IPA${NC}"
echo "Install via Sideloadly or: ios-deploy --bundle $OUTPUT_IPA"
