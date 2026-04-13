#!/usr/bin/env python3
"""
Smart sprite slicer for Major Tom.

Takes a DALL-E sprite sheet and outputs individual direction PNGs into
the Xcode atlas imageset structure.

Detects sprite positions using gap analysis instead of assuming fixed grids.
Handles transparent BGs, colored BGs, inconsistent sizing, any layout.

Usage:
    python3 slice-sprites.py <source.png> <character_name>
    python3 slice-sprites.py dogs/esteban.png esteban
    python3 slice-sprites.py the_office/dwight.png dwight

Output: ios/MajorTom/Assets.xcassets/CrewSprites.spriteatlas/{name}_{dir}.imageset/
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Optional
from PIL import Image

DIRECTIONS = ["front", "back", "left", "right"]

# Walk sheet labels: top-left, top-right, bottom-left, bottom-right
WALK_LABELS = ["walkLeft1", "walkLeft2", "walkRight1", "walkRight2"]

# Activity sheet labels (humans): sitting, sleeping, working, exercising
HUMAN_ACTIVITY_LABELS = ["sitting", "sleeping", "working", "exercising"]

# Activity sheet labels (dogs): sleeping, running, sniffing, sitting
DOG_ACTIVITY_LABELS = ["sleeping", "running", "sniffing", "sitting"]

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
DEFAULT_SOURCE_DIR = SCRIPT_DIR / "starter_sprites"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "ios" / "MajorTom" / "Assets.xcassets" / "CrewSprites.spriteatlas"


def remove_background(img: Image.Image, threshold: int = 220) -> Image.Image:
    """Remove background by making it transparent.

    Supports:
    - Green screen (#00FF00) backgrounds — primary method for new sprites
    - Near-white and near-gray backgrounds — legacy fallback
    - Already-transparent backgrounds — pass through
    """
    img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]

            if a < 10:
                pixels[x, y] = (0, 0, 0, 0)
                continue

            # Green screen removal (#00FF00 and nearby greens)
            if g > 200 and r < 80 and b < 80:
                pixels[x, y] = (0, 0, 0, 0)
                continue

            # Near-white
            if r > threshold and g > threshold and b > threshold:
                pixels[x, y] = (0, 0, 0, 0)
                continue

            # Gray background (all channels similar)
            avg = (r + g + b) / 3
            spread = max(r, g, b) - min(r, g, b)
            if spread < 30 and 80 < avg < threshold:
                pixels[x, y] = (0, 0, 0, 0)
                continue

    return img


def column_has_content(img: Image.Image, x: int, min_pixels: int = 3) -> bool:
    """Check if a column has enough non-transparent pixels to be 'content'."""
    pixels = img.load()
    count = 0
    for y in range(img.height):
        if pixels[x, y][3] > 20:
            count += 1
            if count >= min_pixels:
                return True
    return False


def row_has_content(img: Image.Image, y: int, min_pixels: int = 3) -> bool:
    """Check if a row has enough non-transparent pixels to be 'content'."""
    pixels = img.load()
    count = 0
    for x in range(img.width):
        if pixels[x, y][3] > 20:
            count += 1
            if count >= min_pixels:
                return True
    return False


def find_content_runs(img: Image.Image, axis: str) -> list[tuple[int, int]]:
    """Find contiguous runs of content along an axis.

    Returns list of (start, end) ranges where content exists.
    """
    size = img.width if axis == "x" else img.height
    check = column_has_content if axis == "x" else row_has_content

    runs = []
    in_run = False
    start = 0

    for i in range(size):
        has = check(img, i)
        if has and not in_run:
            start = i
            in_run = True
        elif not has and in_run:
            runs.append((start, i))
            in_run = False

    if in_run:
        runs.append((start, size))

    return runs


def merge_close_runs(runs: list[tuple[int, int]], min_gap: int = 5) -> list[tuple[int, int]]:
    """Merge runs that are separated by very small gaps (stray pixels)."""
    if len(runs) <= 1:
        return runs

    merged = [runs[0]]
    for start, end in runs[1:]:
        prev_start, prev_end = merged[-1]
        if start - prev_end < min_gap:
            merged[-1] = (prev_start, end)
        else:
            merged.append((start, end))

    return merged


def find_sprites(img: Image.Image) -> list[Image.Image]:
    """Find and extract individual sprites from the sheet using gap analysis."""
    # Find content runs along X (columns) and Y (rows)
    x_runs = find_content_runs(img, "x")
    y_runs = find_content_runs(img, "y")

    # Merge tiny gaps (anti-aliasing artifacts, stray pixels)
    x_runs = merge_close_runs(x_runs, min_gap=8)
    y_runs = merge_close_runs(y_runs, min_gap=8)

    print(f"  Content regions: {len(x_runs)} columns × {len(y_runs)} rows")

    # Determine grid from content runs
    if len(x_runs) == 4 and len(y_runs) == 1:
        # 1x4 horizontal strip
        cells = [(x0, y_runs[0][0], x1, y_runs[0][1]) for x0, x1 in x_runs]
    elif len(x_runs) == 2 and len(y_runs) == 2:
        # 2x2 grid
        cells = [
            (x_runs[0][0], y_runs[0][0], x_runs[0][1], y_runs[0][1]),  # top-left
            (x_runs[1][0], y_runs[0][0], x_runs[1][1], y_runs[0][1]),  # top-right
            (x_runs[0][0], y_runs[1][0], x_runs[0][1], y_runs[1][1]),  # bottom-left
            (x_runs[1][0], y_runs[1][0], x_runs[1][1], y_runs[1][1]),  # bottom-right
        ]
    elif len(x_runs) == 4 and len(y_runs) == 2:
        # 4 columns, 2 rows — probably 1x4 with some vertical scatter
        # Merge into 4 cells using full vertical extent
        y0 = y_runs[0][0]
        y1 = y_runs[-1][1]
        cells = [(x0, y0, x1, y1) for x0, x1 in x_runs]
    elif len(x_runs) == 2 and len(y_runs) == 4:
        # 2 columns, 4 rows — unusual but handle it
        x0 = x_runs[0][0]
        x1 = x_runs[-1][1]
        cells = [(x0, y0, x1, y1) for y0, y1 in y_runs]
    elif len(x_runs) >= 4:
        # More columns than expected — take the 4 widest
        x_runs_sorted = sorted(x_runs, key=lambda r: r[1] - r[0], reverse=True)[:4]
        x_runs_sorted.sort(key=lambda r: r[0])  # re-sort by position
        y0 = y_runs[0][0] if y_runs else 0
        y1 = y_runs[-1][1] if y_runs else img.height
        cells = [(x0, y0, x1, y1) for x0, x1 in x_runs_sorted]
    else:
        # Fallback: split into quadrants
        print(f"  WARNING: Unusual layout ({len(x_runs)}x{len(y_runs)}) — falling back to quadrant split")
        hw, hh = img.width // 2, img.height // 2
        cells = [
            (0, 0, hw, hh),
            (hw, 0, img.width, hh),
            (0, hh, hw, img.height),
            (hw, hh, img.width, img.height),
        ]

    # Crop each cell tightly to its actual content
    sprites = []
    for i, (cx0, cy0, cx1, cy1) in enumerate(cells):
        # Find tight bounding box within this cell
        bbox = find_tight_bbox(img, cx0, cy0, cx1, cy1)
        if bbox:
            sprite = img.crop(bbox)
            print(f"  {DIRECTIONS[i]}: {sprite.width}x{sprite.height}")
            sprites.append(sprite)
        else:
            print(f"  WARNING: Empty cell {i} — using placeholder")
            sprites.append(Image.new("RGBA", (32, 32), (0, 0, 0, 0)))

    return sprites[:4]  # Only take first 4


def find_tight_bbox(img: Image.Image, x0: int, y0: int, x1: int, y1: int) -> tuple[int, int, int, int] | None:
    """Find tight bounding box of non-transparent pixels in a region."""
    pixels = img.load()
    min_x, min_y = x1, y1
    max_x, max_y = x0, y0

    for y in range(y0, y1):
        for x in range(x0, x1):
            if pixels[x, y][3] > 20:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

    if min_x >= max_x or min_y >= max_y:
        return None

    return (min_x, min_y, max_x + 1, max_y + 1)


def normalize_sprites(sprites: list[Image.Image], padding: int = 4) -> list[Image.Image]:
    """Normalize all sprites to the same square canvas (centered)."""
    if not sprites:
        return sprites

    max_w = max(s.width for s in sprites)
    max_h = max(s.height for s in sprites)
    canvas_size = max(max_w, max_h) + padding * 2

    normalized = []
    for sprite in sprites:
        canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
        offset_x = (canvas_size - sprite.width) // 2
        offset_y = (canvas_size - sprite.height) // 2
        canvas.paste(sprite, (offset_x, offset_y))
        normalized.append(canvas)

    return normalized


def write_imageset(img: Image.Image, name: str, direction: str, output_dir: Path) -> None:
    """Write a sprite to an Xcode .imageset directory with Contents.json."""
    filename = f"{name}_{direction}"
    imageset_dir = output_dir / f"{filename}.imageset"
    imageset_dir.mkdir(parents=True, exist_ok=True)

    img.save(imageset_dir / f"{filename}.png", "PNG")

    contents = {
        "images": [
            {"filename": f"{filename}.png", "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(imageset_dir / "Contents.json", "w") as f:
        json.dump(contents, f, indent=2)


def slice_sprite_sheet(source_path: Path, name: str, output_dir: Path, bg_threshold: int = 220, labels: Optional[list[str]] = None) -> bool:
    """Slice a sprite sheet into 4 sprites with given labels."""
    used_labels = DIRECTIONS if labels is None else labels
    if len(used_labels) != 4:
        print(f"  ERROR: Expected 4 labels, got {len(used_labels)}: {used_labels}")
        return False
    print(f"\n{'='*50}")
    print(f"Slicing: {source_path.name} → {name} ({', '.join(used_labels)})")
    print(f"{'='*50}")

    img = Image.open(source_path).convert("RGBA")
    print(f"  Source: {img.width}x{img.height}")

    img = remove_background(img, threshold=bg_threshold)
    print(f"  Background removed (threshold={bg_threshold})")

    sprites = find_sprites(img)
    if len(sprites) != 4:
        print(f"  ERROR: Found {len(sprites)} sprites, expected 4")
        return False

    sprites = normalize_sprites(sprites)
    print(f"  Normalized to: {sprites[0].width}x{sprites[0].height}")

    for sprite, label in zip(sprites, used_labels):
        write_imageset(sprite, name, label, output_dir)
        print(f"  Wrote: {name}_{label}.imageset/")

    print(f"  ✓ Done — {name}")
    return True


def main():
    parser = argparse.ArgumentParser(description="Smart sprite slicer for Major Tom")
    parser.add_argument("source", help="Source PNG (relative to starter_sprites/)")
    parser.add_argument("name", help="Character name for output files")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE_DIR)
    parser.add_argument("--threshold", type=int, default=220, help="BG removal threshold")
    parser.add_argument("--labels", nargs=4, help="Custom labels for the 4 quadrants (default: front back left right)")
    parser.add_argument("--mode", choices=["standing", "walk", "human-activity", "dog-activity"],
                       default="standing", help="Preset label modes")
    args = parser.parse_args()

    source_path = args.source_dir / args.source
    if not source_path.exists():
        source_path = Path(args.source)
    if not source_path.exists():
        print(f"Source not found: {source_path}")
        sys.exit(1)

    # Determine labels
    labels = args.labels
    if not labels:
        if args.mode == "walk":
            labels = WALK_LABELS
        elif args.mode == "human-activity":
            labels = HUMAN_ACTIVITY_LABELS
        elif args.mode == "dog-activity":
            labels = DOG_ACTIVITY_LABELS
        else:
            labels = DIRECTIONS

    if not slice_sprite_sheet(source_path, args.name, args.output_dir, args.threshold, labels):
        sys.exit(1)


if __name__ == "__main__":
    main()
