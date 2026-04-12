# Next Session Pickup — Wave 3 Sprint 4

> Written 2026-04-11 end of Sprint 3 session.
> Branch: start from `main` (current HEAD: bf1cf90)

---

## What's Ready

User generated a massive batch of DALL-E sprites. Everything is in `assets/` (gitignored — source files only, sliced output goes to the atlas).

### Asset Inventory

**Crew (`assets/crew/`) — 16 characters:**

| File | CharacterType | Status |
|------|---------------|--------|
| `dwight.png` | `dwight` | Already sliced + in code |
| `michael.png` | `michael` | Already sliced + in code |
| `frankenstein.png` | `frankenstein` | NEW source — re-slice needed |
| `alien_diplomat.png` | `alienDiplomat` | NEW — slice + add to code |
| `backend_engineer.png` | `backendEngineer` | NEW — slice + add to code |
| `botanist.png` | `botanist` | NEW — slice + add to code |
| `captain.png` | `captain` | NEW — slice + add to code |
| `chef.png` | `chef` | NEW — slice + add to code |
| `claudimus_prime.png` | `claudimusPrime` | NEW — slice + add to code |
| `doctor.png` | `doctor` | NEW — slice + add to code |
| `frontend_dev.png` | `frontendDev` | NEW — slice + add to code |
| `hacker.png` | `hacker` | NEW — slice + add to code |
| `mechanic.png` | `mechanic` | NEW — slice + add to code |
| `pilot.png` | `pilot` | NEW — slice + add to code |
| `security.png` | `security` | NEW — slice + add to code |
| `tpm.png` | `tpm` | NEW — slice + add to code |

**Dogs (`assets/dogs/`) — 6 redos (better quality, transparent BGs):**

| File | CharacterType | Note |
|------|---------------|------|
| `elvis.png` | `elvis` | Re-slice with new source |
| `esteban.png` | `esteban` | Re-slice with new source |
| `hoku.png` | `hoku` | Re-slice with new source |
| `kai.png` | `kai` | Re-slice with new source |
| `señor.png` | `senor` | ⚠️ RENAME to `senor.png` first (ñ will break things) |
| `steve.png` | `steve` | Re-slice with new source |

**Furniture (`assets/furniture/`) — 21 items:**

| File | Use | Note |
|------|-----|------|
| `workstation_desk1.png` | Command Bridge | Angled view variant |
| `workstation_desk2.png` | Command Bridge | Straight-on variant |
| `captains_chair.png` | Command Bridge | |
| `tactical_display.png` | Command Bridge | |
| `reactor_core.png` | Engineering | |
| `control_panel.png` | Engineering | |
| `tool_rack.png` | Engineering | |
| `bunk_bed.png` | Crew Quarters | |
| `couch.png` | Crew Quarters | |
| `media_screen.png` | Crew Quarters | |
| `food_dispenser.png` | Galley | Single view |
| `food_dispenser_2x2.png` | Galley | 2x2 grid variant — pick best |
| `coffee_machine.png` | Galley | |
| `dining_table.png` | Galley | |
| `tree.png` | Bio-Dome / Arboretum | |
| `water_feature.png` | Bio-Dome | |
| `park_brench.png` | Arboretum | (typo — rename to park_bench) |
| `pond.png` | Arboretum | |
| `treadmill.png` | Training Bay | |
| `weight_rack.png` | Training Bay | |
| `space_suit_rack.png` | EVA Bay | |

Also: `assets/potted_plant.png` — office plant, use for Bio-Dome/shared

**Missing furniture (not generated yet — can skip for now):**
- equipment_locker
- floor_lamp
- wall_panel / status_screen
- storage_crate

---

## Task 1: Slice All New Assets

### Characters (crew + dogs)

Use the smart slicer at `assets/slice-sprites.py`:
```bash
# Dogs — rename señor first!
mv assets/dogs/señor.png assets/dogs/senor.png

# Slice dogs
python3 assets/slice-sprites.py dogs/elvis.png elvis
python3 assets/slice-sprites.py dogs/senor.png senor
python3 assets/slice-sprites.py dogs/steve.png steve
python3 assets/slice-sprites.py dogs/esteban.png esteban
python3 assets/slice-sprites.py dogs/hoku.png hoku
python3 assets/slice-sprites.py dogs/kai.png kai

# Slice new crew (update --source-dir to assets/crew/ or use relative paths)
python3 assets/slice-sprites.py --source-dir assets/crew alien_diplomat.png alienDiplomat
python3 assets/slice-sprites.py --source-dir assets/crew backend_engineer.png backendEngineer
# ... etc for each
```

The slicer auto-detects 2x2 vs 1x4 layouts and handles BG removal. **Verify each output** — read the PNGs to check for double-sprites or bad crops.

### Furniture

Furniture is SINGLE-VIEW images (not 4-view grids). The character slicer won't work on these. Instead:
1. Open each PNG, remove background if needed, crop to content, normalize size
2. Save directly as an imageset (no `_front` suffix — just `workstation_desk.imageset/workstation_desk.png`)
3. Use a separate atlas or add to `CrewSprites.spriteatlas` (recommend separate `StationFurniture.spriteatlas`)

Consider writing a simpler `slice-furniture.py` that just: loads → removes BG → crops to content → normalizes → writes imageset.

For items with variants (workstation_desk1 vs desk2, food_dispenser vs 2x2), pick the best one or keep both as separate assets.

---

## Task 2: Add New Characters to Code

### Files to modify:

**`AgentState.swift`** — Add 13 new CharacterType cases:
```swift
// New crew
case alienDiplomat
case backendEngineer
case botanist
case captain
case chef
case claudimusPrime
case doctor
case frontendDev
case hacker
case mechanic
case pilot
case security
case tpm
```

**`CharacterConfig.swift`** — Add CharacterCatalog entries for each (displayName, spriteColor, breakBehaviors)

**`CharacterGalleryView.swift`** — Add descriptions for each in `characterDescription(for:)`

**`AgentSprite.swift`** — No changes needed (dogTypes set stays the same, humans use default sizing)

**`project.pbxproj`** — No changes needed for new atlas imagesets (Xcode auto-discovers them in the spriteatlas)

---

## Task 3: Update Walk Frame Prompts

`WALK-FRAME-PROMPTS.md` currently has 13 characters. Needs to be updated to cover ALL characters including the new ones:
- Add walk frame prompts for: alienDiplomat, backendEngineer, botanist, captain, chef, claudimusPrime, doctor, frontendDev, hacker, mechanic, pilot, security, tpm
- Each prompt uploads the idle sprite as reference and asks for mid-stride variant
- Enforcement block already baked in — just follow the same template

---

## Task 4: Map Overhaul (if time)

See `docs/WAVE-3-PLANNING.md` for full spec. Key decisions:
- **Floors/walls**: programmatic tiles
- **Furniture/props**: DALL-E pixel art sprites (the ones just generated)
- **Room scale**: each room fills phone screen width (~375pt), stacked vertically
- **Room views**: grouped views (command, crew, etc.)
- **Station overview**: full station shows room columns, tap to zoom into column

Start by creating a `StationFurniture.spriteatlas` and a `FurnitureSpriteBuilder.swift` that loads furniture textures. Then refactor OfficeScene to use larger room modules with furniture sprites instead of programmatic shapes.

---

## Key Files

| File | Role |
|------|------|
| `assets/slice-sprites.py` | Smart slicer — gap detection, BG removal, any layout |
| `assets/crew/` | New human character source sheets |
| `assets/dogs/` | Dog redo source sheets |
| `assets/furniture/` | Furniture/prop source images |
| `ios/.../CrewSprites.spriteatlas/` | Output atlas for character sprites |
| `ios/.../AgentState.swift` | CharacterType enum |
| `ios/.../CharacterConfig.swift` | CharacterCatalog with colors/behaviors |
| `ios/.../CharacterGalleryView.swift` | Gallery descriptions |
| `docs/WAVE-3-PLANNING.md` | Map overhaul decisions |
| `WALK-FRAME-PROMPTS.md` | Walk animation DALL-E prompts (needs expansion) |

## Naming Convention

- Dogs use pet names: elvis, senor, steve, esteban, hoku, kai
- Humans use descriptive role names for now; when mapped to a live agent, they inherit the agent's role from tool invocation events
- CharacterType raw values must match atlas texture names exactly (camelCase → atlas key)
