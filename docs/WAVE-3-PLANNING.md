# Wave 3 Sprint 3 — Planning Notes

> Pre-implementation discussion. Don't build until aligned.

---

## Problem 1: Sprite QA Issues

### Known Bugs
- **Esteban** — `esteban_left` slice contains TWO sprites (front + back) instead of one. Source sheet has tight spacing and the slicer grabbed too wide.
- **Steve** — All 4 slices are tiny/off-center with leaked gray background. Source sheet was 2x2 grid on dark gray BG (not transparent), and sprites are smaller within their cells vs other characters.
- **General inconsistency** — Some source sheets are 1x4 horizontal, some are 2x2 grid. Backgrounds vary (transparent vs gray gradient). Sprite sizes within cells vary.

### Fix Approach
The current slicer blindly quarters the image. We need a smarter approach:

**Option A: Contour-based auto-slicer** — Python script using PIL/OpenCV that detects sprite boundaries by finding connected non-transparent regions, crops each to a consistent bounding box, and normalizes size. Handles any layout.

**Option B: Semi-manual with guides** — Keep the grid slicer but add: background removal first (threshold gray pixels to transparent), then find the 4 largest blobs, crop each individually, normalize to consistent canvas size.

**Option C: Manual crop** — You crop them in Preview. Tedious but accurate. Not recommended at scale.

**Recommendation: Option A.** We write a smarter slicer once, it handles all future sprites regardless of DALL-E layout quirks.

---

## Problem 2: New Sprites to Add

### Ready to Slice
| Source | Layout | Status |
|--------|--------|--------|
| `the_office/dwight.png` | 2x2, clean | Ready |
| `the_office/michael.png` | 2x2, clean | Ready |

### Need Re-slice (QA fix)
| Source | Issue |
|--------|-------|
| `dogs/esteban.png` | Left slice captured 2 sprites |
| `dogs/steve.png` | Dark BG, sprites too small, off-center |

### Future (from SPRITE-PROMPTS.md)
Chef, doctor, engineer, security, pilot, android, alien, hacker, botanist, captain — prompts written, waiting for you to generate.

---

## Problem 3: Map Overhaul (Phases 4-6)

### Current Issues
- Rooms are tiny — hard to see what's happening
- Furniture is programmatic shapes (rectangles, circles) — looks flat
- Usability is poor on phone screen
- Can't tell what's in each room at a glance

### Proposed Direction
**Each room should fill the screen width.** The station becomes a series of large, detailed rooms you scroll/pan between, not a zoomed-out floor plan.

### DALL-E for Map Assets — Options

**Option 1: DALL-E room backgrounds + DALL-E furniture sprites**
- Generate a tileable floor/wall texture per room type (metal panels for Engineering, warm wood for Crew Quarters, glass dome for Bio-Dome)
- Generate individual furniture sprites: desk with monitors, couch, reactor console, bunk bed, coffee machine, plants
- Highest visual quality, matches the sprite art style
- Tradeoff: more asset work upfront, harder to iterate on layout

**Option 2: DALL-E room backgrounds + programmatic furniture**
- DALL-E for atmosphere (floor texture, wall panels, ambient details)
- Keep programmatic shapes for interactive items (desks, stations)
- Easier to move furniture around without regenerating art
- Tradeoff: mixed art styles might feel inconsistent

**Option 3: Full DALL-E room scenes**
- Generate entire room interiors as single background images
- Characters walk over the pre-rendered scene
- Simplest to implement, most visually cohesive
- Tradeoff: can't rearrange furniture, need to regenerate for layout changes

**Option 4: Programmatic glow-up (no DALL-E)**
- Better gradients, shadows, glow effects, detail shapes
- Fully scalable, no asset dependencies
- Tradeoff: won't match the quality jump the sprites got

### My Take
**Option 1 is the move.** The whole point of this phase is the visual overhaul. Matching the DALL-E sprite style across the whole scene makes it cohesive. The extra asset work pays for itself because:
- Room layouts are mostly stable now (we're past the "move walls every PR" phase)
- Furniture positions change rarely
- Individual furniture sprites can be reused across rooms
- The contrast between beautiful sprites and flat rectangles will only get worse as we add more characters

### Implementation Approach (if Option 1)
1. Define a consistent art spec: isometric-ish top-down, pixel art, 32x32 or 64x64 tiles
2. Generate room floor textures (tileable)
3. Generate furniture sprites (one sheet per room type)
4. Build a `MapAssetBuilder` that loads textures from a `StationAssets.spriteatlas`
5. Rooms expand to ~375pt wide (iPhone screen width at 1x) × proportional height

---

## Questions to Answer Before Building

1. **Slicer approach** — Option A (smart contour slicer)? Or do you want to just manually re-crop esteban + steve?
2. **New characters** — Just dwight + michael for now, or do you want to generate more from SPRITE-PROMPTS.md first?
3. **Map art style** — Option 1 (full DALL-E)? If so, what vibe? Same pixel art as sprites, or more detailed/painterly backgrounds?
4. **Room scale** — Full screen width per room, with horizontal scrolling between rooms? Or keep the zoomed-out overview but make it bigger?
5. **Art spec** — Should we define pixel art guidelines for DALL-E prompts (perspective, palette, tile size) before you start generating?
