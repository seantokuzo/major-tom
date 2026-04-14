#!/bin/bash
# Full re-splice of ALL sprite and furniture assets from canonical sources.
# Nukes existing atlas contents and rebuilds from assets/crew/, assets/dogs/, assets/furniture/.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SLICER="$SCRIPT_DIR/slice-sprites.py"
FURNITURE_PROCESSOR="$SCRIPT_DIR/process-furniture.py"
CREW_ATLAS="$PROJECT_ROOT/ios/MajorTom/Assets.xcassets/CrewSprites.spriteatlas"
FURNITURE_ATLAS="$PROJECT_ROOT/ios/MajorTom/Assets.xcassets/StationFurniture.spriteatlas"

# Name mapping: source_file_prefix → camelCase output name
declare -A CREW_NAMES=(
  ["alien_diplomat"]="alienDiplomat"
  ["backend_engineer"]="backendEngineer"
  ["botanist"]="botanist"
  ["bowen_yang"]="bowenYang"
  ["captain"]="captain"
  ["chef"]="chef"
  ["claudimus_prime"]="claudimusPrime"
  ["doctor"]="doctor"
  ["dwight"]="dwight"
  ["frontend_dev"]="frontendDev"
  ["kendrick"]="kendrick"
  ["mechanic"]="mechanic"
  ["prince"]="prince"
  ["project_manager"]="pm"
)

declare -A DOG_NAMES=(
  ["elvis"]="elvis"
  ["esteban"]="esteban"
  ["hoku"]="hoku"
  ["kai"]="kai"
  ["señor"]="senor"
  ["steve"]="steve"
  ["zuckerbot"]="zuckerbot"
)

echo "=========================================="
echo "FULL RE-SPLICE — Nuking old atlases"
echo "=========================================="

# Step 1: Nuke all .imageset dirs in both atlases (keep the atlas dir + Contents.json)
echo "Clearing CrewSprites atlas..."
find "$CREW_ATLAS" -mindepth 1 -maxdepth 1 -type d -name "*.imageset" -exec rm -rf {} +
echo "Clearing StationFurniture atlas..."
find "$FURNITURE_ATLAS" -mindepth 1 -maxdepth 1 -type d -name "*.imageset" -exec rm -rf {} +

echo ""
echo "=========================================="
echo "CREW — Standing sheets (front/back/left/right)"
echo "=========================================="
for src_name in "${!CREW_NAMES[@]}"; do
  out_name="${CREW_NAMES[$src_name]}"
  src="$SCRIPT_DIR/crew/${src_name}.png"
  if [ -f "$src" ]; then
    python3 "$SLICER" "$src" "$out_name" --source-dir . --threshold 220
  else
    echo "SKIP (missing): $src"
  fi
done

echo ""
echo "=========================================="
echo "CREW — Walk sheets (walkLeft1/walkLeft2/walkRight1/walkRight2)"
echo "=========================================="
for src_name in "${!CREW_NAMES[@]}"; do
  out_name="${CREW_NAMES[$src_name]}"
  src="$SCRIPT_DIR/crew/${src_name}_walk.png"
  if [ -f "$src" ]; then
    python3 "$SLICER" "$src" "$out_name" --source-dir . --threshold 220 --mode walk
  else
    echo "SKIP (missing): $src"
  fi
done

echo ""
echo "=========================================="
echo "CREW — Activity sheets (sitting/sleeping/working/exercising)"
echo "=========================================="
for src_name in "${!CREW_NAMES[@]}"; do
  out_name="${CREW_NAMES[$src_name]}"
  src="$SCRIPT_DIR/crew/${src_name}_activity.png"
  if [ -f "$src" ]; then
    python3 "$SLICER" "$src" "$out_name" --source-dir . --threshold 220 --mode human-activity
  else
    echo "SKIP (missing): $src"
  fi
done

echo ""
echo "=========================================="
echo "DOGS — Standing sheets"
echo "=========================================="
for src_name in "${!DOG_NAMES[@]}"; do
  out_name="${DOG_NAMES[$src_name]}"
  src="$SCRIPT_DIR/dogs/${src_name}.png"
  if [ -f "$src" ]; then
    python3 "$SLICER" "$src" "$out_name" --source-dir . --threshold 220
  else
    echo "SKIP (missing): $src"
  fi
done

echo ""
echo "=========================================="
echo "DOGS — Walk sheets"
echo "=========================================="
for src_name in "${!DOG_NAMES[@]}"; do
  out_name="${DOG_NAMES[$src_name]}"
  src="$SCRIPT_DIR/dogs/${src_name}_walk.png"
  if [ -f "$src" ]; then
    python3 "$SLICER" "$src" "$out_name" --source-dir . --threshold 220 --mode walk
  else
    echo "SKIP (missing): $src"
  fi
done

echo ""
echo "=========================================="
echo "DOGS — Activity sheets (sleeping/running/sniffing/sitting)"
echo "=========================================="
for src_name in "${!DOG_NAMES[@]}"; do
  out_name="${DOG_NAMES[$src_name]}"
  src="$SCRIPT_DIR/dogs/${src_name}_activity.png"
  if [ -f "$src" ]; then
    python3 "$SLICER" "$src" "$out_name" --source-dir . --threshold 220 --mode dog-activity
  else
    echo "SKIP (missing): $src"
  fi
done

echo ""
echo "=========================================="
echo "FURNITURE — Process all"
echo "=========================================="
if [ -f "$FURNITURE_PROCESSOR" ]; then
  python3 "$FURNITURE_PROCESSOR"
else
  # Manual furniture processing — green screen remove + imageset wrap
  echo "No furniture processor found, doing manual processing..."
  for src in "$SCRIPT_DIR/furniture/"*.png; do
    name="$(basename "$src" .png)"
    imageset_dir="$FURNITURE_ATLAS/${name}.imageset"
    mkdir -p "$imageset_dir"

    # Use Python for green screen removal
    python3 -c "
from PIL import Image
img = Image.open('$src').convert('RGBA')
pixels = img.load()
w, h = img.size
for y in range(h):
    for x in range(w):
        r, g, b, a = pixels[x, y]
        if a < 10 or (g > 200 and r < 80 and b < 80):
            pixels[x, y] = (0, 0, 0, 0)
        elif r > 220 and g > 220 and b > 220:
            pixels[x, y] = (0, 0, 0, 0)
# Crop to content
bbox = img.getbbox()
if bbox:
    img = img.crop(bbox)
img.save('$imageset_dir/${name}.png', 'PNG')
"
    # Write Contents.json
    cat > "$imageset_dir/Contents.json" << EOF
{
  "images": [
    {"filename": "${name}.png", "idiom": "universal", "scale": "1x"},
    {"idiom": "universal", "scale": "2x"},
    {"idiom": "universal", "scale": "3x"}
  ],
  "info": {"author": "xcode", "version": 1}
}
EOF
    echo "  Processed: $name"
  done
fi

echo ""
echo "=========================================="
echo "DONE — Full re-splice complete"
echo "=========================================="
echo "CrewSprites: $(find "$CREW_ATLAS" -name "*.imageset" -type d | wc -l | tr -d ' ') imagesets"
echo "Furniture:   $(find "$FURNITURE_ATLAS" -name "*.imageset" -type d | wc -l | tr -d ' ') imagesets"
