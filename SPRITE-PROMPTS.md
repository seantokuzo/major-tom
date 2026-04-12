# Sprite Generation Prompts

Copy-paste these into ChatGPT (DALL-E) to generate sprites.
Mark `[x]` as you complete each one.

---

## DALL-E RULES (read this first)

DALL-E will fight you on these. It WILL add gradients, glow, anti-aliasing, and soft edges. It literally cannot help itself. Every prompt below includes aggressive countermeasures, but here's what to watch for and reject:

**REJECT if you see:**
- Soft/blurry edges between the sprite and background (should be razor-sharp pixel steps)
- Gradient shading within the sprite (should be flat solid color blocks)
- Ground shadow or any shadow underneath the character
- Glow, bloom, or light halos around edges
- Background that isn't perfectly transparent (gray, white, gradient)
- Anti-aliased edges (smooth transitions instead of hard pixel steps)

**DALL-E will apologize and tell you it can't do it. Make it try again.**

The prompts below include a "pixel art enforcement block" at the end. DO NOT REMOVE IT — it's there because DALL-E needs to be told 5 times.

---

## ENFORCEMENT BLOCK (appended to every prompt)

Copy this after every prompt:

```
CRITICAL RULES — violating ANY of these means the image must be regenerated:
1. EVERY edge must be a hard 90-degree pixel step. ZERO anti-aliasing. ZERO edge smoothing. If you zoom in, each pixel boundary should be a sharp staircase, never a gradient.
2. Background MUST be perfectly transparent (PNG alpha = 0). No white, no gray, no gradient, no subtle tint.
3. NO ground shadow. NO drop shadow. NO ambient occlusion under the character. The character floats on pure transparency.
4. ALL shading must be done with FLAT solid color blocks — like Stardew Valley or Shovel Knight. Never use gradients or soft brushes.
5. NO glow effects, NO bloom, NO light halos around any part of the sprite.
6. The 4 views must be on a single canvas, clearly separated with empty space between them.
```

---

# PART 1: CHARACTER SPRITES — REDOS

> These characters have existing sprites that need to be regenerated.
> Upload the current sprite sheet as a reference for DALL-E to match the character design.

### [ ] Steve (Cattle Dog) — REDO

I'm uploading the current sprite sheet for this character. Regenerate it with these fixes:
- Make the character LARGER — fill more of each cell (currently too small)
- Remove the dark gray background — must be perfectly transparent
- Remove the ground shadow under the feet
- Sharpen all edges to hard pixel steps

Recreate this exact character (Australian cattle dog in a space suit) as a 32×32 pixel art sprite. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view should be clearly separated with empty space between them. Dogs should be WIDER than tall in side views (horizontal body). Style: Stardew Valley / Shovel Knight. Flat color blocks only, no gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Senor (Dachshund alt) — REDO

I'm uploading the current sprite sheet for this character. Regenerate it with these fixes:
- Remove the gray/white ground area under the feet — NO shadow, NO floor
- Sharpen all edges to hard pixel steps, remove any anti-aliasing

Recreate this exact character (dachshund in a green hoodie with orange trim) as a 32×32 pixel art sprite. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view should be clearly separated with empty space between them. Dachshunds are LONG — side views should be much wider than tall. Style: Stardew Valley / Shovel Knight. Flat color blocks only, no gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Hoku (Black Schnauzer) — REDO

I'm uploading the current sprite sheet for this character. Regenerate it with these fixes:
- Remove the gray/white ground area under the feet — NO shadow, NO floor
- Sharpen all edges to hard pixel steps
- Keep the space suit and helmet design exactly as shown

Recreate this exact character (black schnauzer in a small space suit) as a 32×32 pixel art sprite. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view should be clearly separated with empty space between them. Style: Stardew Valley / Shovel Knight. Flat color blocks only, no gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Kai (Pepper Schnauzer) — REDO

I'm uploading the current sprite sheet for this character. Regenerate it with these fixes:
- Remove the gray/white ground area under the feet — NO shadow, NO floor
- Sharpen all edges to hard pixel steps
- Keep the space suit and tongue-out personality exactly as shown

Recreate this exact character (salt-and-pepper schnauzer in a small space suit, tongue sticking out) as a 32×32 pixel art sprite. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view should be clearly separated with empty space between them. Style: Stardew Valley / Shovel Knight. Flat color blocks only, no gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---
---

# PART 1B: CHARACTER SPRITES — NEW CREW

> Drop source sheets in `assets/starter_sprites/`

### [ ] 6. Space Chef

Create a 32×32 pixel art character sprite — a space station chef. Tall chef's hat poking through a modified helmet, white apron over a space suit, holding a glowing space ladle, moustache visible. Color palette: white, red accents, steel gray suit. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 7. Ship's Doctor

Create a 32×32 pixel art character sprite — a space station medic/doctor. Glowing red cross on helmet, medical scanner in hand, white suit with teal medical accents, calm expression, small round glasses. Color palette: white, teal, red cross. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 8. Grease Monkey (Engineer)

Create a 32×32 pixel art character sprite — a space station mechanic/engineer. Oil-stained orange jumpsuit space suit, welding goggles pushed up on forehead, big wrench in hand, utility belt with tools, scruffy look. Color palette: orange, dark brown, steel gray. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 9. Security Officer

Create a 32×32 pixel art character sprite — a space station security officer. Heavy armored space suit, tinted visor helmet, stun baton on belt, shoulder pads with chevrons, intimidating stance. Color palette: dark charcoal, red visor, silver trim. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 10. Ace Pilot

Create a 32×32 pixel art character sprite — a cocky space station pilot. Flight suit with patches, aviator sunglasses over the helmet visor, fingerless gloves, confident smirk, wings insignia on chest. Color palette: dark green flight suit, gold aviator frames, brown leather accents. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 11. Ship's Android

Create a 32×32 pixel art character sprite — a friendly android crew member. Smooth metallic body, glowing blue eyes, panel lines visible, small antenna, no helmet needed (robot), slight smile on LED face display. Color palette: silver, white, blue accents. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 12. Alien Diplomat

Create a 32×32 pixel art character sprite — a friendly alien crew member. Mint-green skin, two small antennae, three eyes, wearing a diplomatic sash over a sleek space suit, gentle expression, slightly taller and thinner than humans. Color palette: mint green skin, purple sash, silver suit. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 13. Cyber Hacker

Create a 32×32 pixel art character sprite — a cyberpunk hacker on a space station. Hoodie with LED trim under a light space vest, holographic screens near hands, face half-covered by a data visor, neon wires trailing. Color palette: black, neon green, electric purple. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 14. Space Botanist

Create a 32×32 pixel art character sprite — a space station botanist/gardener. Modified suit with a built-in greenhouse backpack (tiny plants visible through glass dome on back), flower tucked behind ear, holding a watering can, warm smile. Color palette: green suit, earth browns, plant greens, yellow flower. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] 15. The Captain

Create a 32×32 pixel art character sprite — the distinguished space station captain. Long captain's coat over space suit, peaked officer's cap with gold insignia, medals on chest, hands clasped behind back (front view: one hand on hip), silver temples, commanding presence. Color palette: navy blue coat, gold trim, white undershirt, silver medals. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients. 4 views in a 2×2 grid on a single image: front (top-left), back (top-right), left-facing (bottom-left), right-facing (bottom-right). Each view clearly separated with empty space between them.

[PASTE ENFORCEMENT BLOCK HERE]

---
---

# PART 2: FURNITURE & PROP SPRITES

> Drop source PNGs in `assets/furniture/`
> Single item per image — NOT a 4-view grid. Just one top-down ¾ view.
> Generate at 64×64 for detail, we scale down in-engine.

## Command Bridge

### [ ] Workstation Desk

Create a single 64×64 pixel art top-down ¾ view of a sci-fi workstation desk. Sleek dark metal desk with 2 glowing holographic monitors, a keyboard, a coffee mug, and a small status LED strip along the front edge. Subtle cyan illumination from screens on the desk surface — rendered as flat color blocks, NOT as a gradient glow. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Captain's Chair

Create a single 64×64 pixel art top-down ¾ view of a sci-fi captain's command chair. High-backed swivel chair with armrest control panels, dark leather seat, metallic frame, small holographic display on the left armrest. Blue accent lighting rendered as flat color blocks. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Tactical Display

Create a single 64×64 pixel art top-down ¾ view of a large wall-mounted tactical display screen. Wide curved screen showing a star map with glowing dots and route lines, mounted on a dark metal bracket. Green/cyan display rendered as flat color blocks. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

## Engineering

### [ ] Reactor Core

Create a single 64×64 pixel art top-down ¾ view of a compact fusion reactor core. Cylindrical chamber with blue-white plasma visible through a viewport, heavy bolted metal housing, coolant pipes running out the sides, warning labels. Energy rendered as flat color blocks NOT gradient glow. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Power Control Panel

Create a single 64×64 pixel art top-down ¾ view of a wall-mounted engineering control panel. Array of switches, dials, and small screens, some green/amber status lights, a big red emergency lever, exposed wiring along the bottom. Industrial look. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Tool Rack

Create a single 64×64 pixel art top-down ¾ view of a wall-mounted tool rack. Wrenches, screwdrivers, a welding torch, a multimeter, all hanging on pegs against a metal backplate. Organized but well-used. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

## Crew Quarters

### [ ] Bunk Bed

Create a single 64×64 pixel art top-down ¾ view of a space station bunk bed. Metal frame, two levels, thin mattresses with colored blankets (top: blue, bottom: green), small reading light on each bunk, a pillow on each. Compact and utilitarian. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Lounge Couch

Create a single 64×64 pixel art top-down ¾ view of a worn but comfortable space station couch. Dark gray fabric, a few throw pillows (one orange, one blue), slightly sagging cushions, metal legs. Lived-in feel. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Media Screen

Create a single 64×64 pixel art top-down ¾ view of a wall-mounted entertainment screen. Flat panel TV showing a paused movie (colorful static image), small soundbar beneath it, a remote on a side shelf. Screen glow as flat color blocks. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

## Galley

### [ ] Food Dispenser

Create a single 64×64 pixel art top-down ¾ view of a futuristic food dispenser/replicator. Wall-mounted metal unit with a glowing slot where food appears, a touchscreen menu panel, a small tray below the slot with a steaming bowl on it. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Coffee Machine

Create a single 64×64 pixel art top-down ¾ view of a chunky space station coffee machine. Retro-futuristic design, chrome body, pressure gauges, a drip spout with a mug underneath, steam wisps as flat pixel puffs (NOT blurred), a small bean hopper on top. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Dining Table

Create a single 64×64 pixel art top-down ¾ view of a small round dining table with 2 chairs. Metal table with a couple food trays and cups on it, simple metal chairs pushed in. Cafeteria vibe. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

## Bio-Dome

### [ ] Potted Plant (Small)

Create a single 64×64 pixel art top-down ¾ view of a small potted plant in a futuristic planter. Lush green leaves spilling over a sleek white cylindrical pot, a small grow-light strip on the rim, soil visible. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Dome Tree (Large)

Create a single 64×64 pixel art top-down ¾ view of a small tree growing inside a space station. Thick trunk, full leafy canopy with varied greens, planted in a large metal planter bed, a few fallen leaves on the ground. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Water Feature

Create a single 64×64 pixel art top-down ¾ view of a small indoor water fountain. Stacked smooth stones with water trickling down into a shallow pool, a few small plants around the base. Water as flat blue color blocks NOT gradient. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

## Arboretum

### [ ] Park Bench

Create a single 64×64 pixel art top-down ¾ view of a park bench inside a space station arboretum. Wooden slat seat with metal frame, a small reading tablet left on it, grass patches around the base. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Pond

Create a single 64×64 pixel art top-down ¾ view of a small artificial pond. Circular shallow pool with clear blue water, a few lily pads, small rocks around the edge, a tiny fish visible. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

## Training Bay

### [ ] Exercise Machine

Create a single 64×64 pixel art top-down ¾ view of a futuristic exercise machine / space treadmill. Angular metal frame, a running belt with magnetic resistance indicators, a small screen showing stats, handrails. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Weight Rack

Create a single 64×64 pixel art top-down ¾ view of a compact weight rack. Metal frame holding various dumbbells and a barbell, a rubber mat underneath, a towel draped over the top bar. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

## EVA Bay

### [ ] Space Suit Rack

Create a single 64×64 pixel art top-down ¾ view of a space suit storage rack. Metal frame holding 2 full EVA space suits — white with orange accents, helmets resting on top shelf, gloves clipped to the sides, name tags on each suit. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Equipment Locker

Create a single 64×64 pixel art top-down ¾ view of a tall metal equipment locker. Two doors (one open showing tools and gear inside), magnetic locks, a hazard stripe along the bottom, a clipboard hanging on the front. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

## Shared / Generic Props

### [ ] Office Plant

Create a single 64×64 pixel art top-down ¾ view of a tall office plant in a modern pot. Snake plant / sansevieria style, dark green striped leaves, matte black pot, sitting on the floor. Simple and clean. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Wall Panel / Status Screen

Create a single 64×64 pixel art top-down ¾ view of a small wall-mounted status panel. Rectangular screen showing system metrics (bars, numbers, a pie chart), mounted on a dark metal bracket. Amber display as flat color blocks. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Storage Crate

Create a single 64×64 pixel art top-down ¾ view of a metal cargo crate. Rectangular with reinforced corners, a shipping label sticker, "FRAGILE" stamp, magnetic clasps, slightly dented and scratched. Well-traveled look. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]

---

### [ ] Floor Lamp

Create a single 64×64 pixel art top-down ¾ view of a modern floor lamp. Tall thin metal pole, adjustable dome head angled down, warm yellow-white light cone rendered as flat color block NOT gradient glow, minimal base. Style: Stardew Valley / Shovel Knight — flat solid color blocks, ZERO gradients.

[PASTE ENFORCEMENT BLOCK HERE]
