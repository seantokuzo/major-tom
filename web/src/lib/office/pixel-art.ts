// Pixel art builder — grid-string approach for 14 characters
// Each character defined as an ASCII grid + color palette.
// Humans: ~14×20 logical pixels. Dogs: ~20×11 logical pixels.
// Rendered to Canvas via offscreen caching.

import type { CharacterType } from './types';

const PIXEL_SIZE = 2;

// ── Grid → Pixel Converter ──────────────────────────────────

type PixelList = Array<[number, number, string]>;

function fromGrid(grid: string[], palette: Record<string, string>): PixelList {
  const p: PixelList = [];
  const h = grid.length;
  const w = Math.max(...grid.map(r => r.length));
  const cx = Math.floor(w / 2);
  const cy = Math.floor(h / 2);
  for (let row = 0; row < h; row++) {
    for (let col = 0; col < grid[row].length; col++) {
      const ch = grid[row][col];
      if (ch === '.' || ch === ' ') continue;
      const color = palette[ch];
      if (!color) continue;
      const x = col - cx;
      const y = (h - 1 - row) - cy;
      p.push([x, y, color]);
    }
  }
  return p;
}

// ── Shared Palette Constants ────────────────────────────────

// Skin tones
const SKIN_DARK    = 'rgb(139, 90, 56)';   // dark brown
const SKIN_DARK_SH = 'rgb(115, 72, 43)';
const SKIN_MED     = 'rgb(198, 145, 90)';  // medium/brown
const SKIN_MED_SH  = 'rgb(170, 120, 70)';
const SKIN_LIGHT   = 'rgb(242, 204, 166)'; // light
const SKIN_LIGHT_SH= 'rgb(217, 179, 140)';
const SKIN_OLIVE   = 'rgb(210, 165, 110)'; // olive/latina
const SKIN_OLIVE_SH= 'rgb(185, 140, 90)';
const SKIN_EAST    = 'rgb(235, 195, 155)'; // east asian
const SKIN_EAST_SH = 'rgb(210, 170, 130)';

// Eyes
const EYE_W = 'rgb(242, 242, 242)';
const EYE_B = 'rgb(26, 26, 31)';

// Common
const SHOES  = 'rgb(56, 46, 38)';
const PANTS_DARK = 'rgb(38, 46, 64)';
const PANTS_NAVY = 'rgb(38, 46, 77)';
const PANTS_BLACK = 'rgb(31, 31, 38)';
const PANTS_GRAY  = 'rgb(64, 64, 77)';

// Dog colors
const DOG_EYE  = 'rgb(51, 31, 20)';
const DOG_NOSE = 'rgb(26, 20, 15)';

// ══════════════════════════════════════════════════════════════
//  HUMAN CHARACTERS — ~14 wide × 20 tall
// ══════════════════════════════════════════════════════════════

// ── 1. Architect ♀ — Black woman, neat bun, glasses, dark blazer ──

function buildArchitect(): PixelList {
  // Legend:
  // H=hair(black), S=skin, s=skinShadow, W=eyeWhite, E=eyeBlack
  // G=glasses frame, B=blazer, b=blazer shadow, T=blouse(white),
  // A=arm(blazer), P=pants, F=shoes, N=neck skin
  const grid = [
    '......HHH.....',  // row 0: bun top
    '.....HHHHH....',  // row 1: bun
    '....HHHHHH....',  // row 2: hair top
    '...HHHHHHHH...',  // row 3: hair
    '...HHHHHHHH...',  // row 4: hair
    '..HGSSSSSGGH..',  // row 5: forehead + glasses
    '..HWESSEWESH..',  // row 6: eyes + glasses
    '...SSSssSSS...',  // row 7: nose/mouth
    '...SSSSSSSS...',  // row 8: chin
    '....SSSSSS....',  // row 9: neck
    '...BBTTTTBB...',  // row 10: collar
    '..BBBBBBBBBB..',  // row 11: blazer chest
    '.ABBBBBBBBBA..',  // row 12: blazer + arms
    '.ABBBBBBBBBA..',  // row 13: blazer mid
    '.ABBBBBBBBA...',  // row 14: blazer lower
    '..SBBBBBBBs...',  // row 15: hands peek
    '...PPPPPPPP...',  // row 16: pants
    '...PPPPPPPP...',  // row 17: pants
    '...PP...PP....',  // row 18: legs
    '..FF...FF.....',  // row 19: shoes
  ];
  return fromGrid(grid, {
    'H': 'rgb(31, 26, 22)',      // dark hair
    'S': SKIN_DARK,
    's': SKIN_DARK_SH,
    'N': SKIN_DARK,
    'W': EYE_W,
    'E': EYE_B,
    'G': 'rgb(64, 64, 77)',      // glasses frame
    'B': 'rgb(51, 51, 64)',      // dark blazer
    'b': 'rgb(38, 38, 51)',      // blazer shadow
    'T': 'rgb(230, 230, 235)',   // white blouse
    'A': 'rgb(51, 51, 64)',      // arms = blazer
    'P': PANTS_DARK,
    'F': SHOES,
  });
}

// ── 2. Lead Engineer ♂ — White man, messy brown hair, hoodie, headphones, beard stubble ──

function buildLeadEngineer(): PixelList {
  // H=hair, h=messy hair highlight, S=skin, s=shadow, W=eye white, E=eye black
  // P=headphone band, p=headphone ear, O=hoodie, o=hoodie shadow, D=hood drawstring
  // Z=stubble, Q=pants, F=shoes, L=laptop glow
  const grid = [
    '....hHHHh.....',  // row 0: messy hair top
    '...HhHHHhH....',  // row 1: messy hair
    '..HHHHHHHHHH..',  // row 2: hair + headphone band
    '..PPHHHHHHPP..',  // row 3: headphone band over hair
    '..pHSSSSSHp...',  // row 4: headphone ears + forehead
    '..pSSWESWEp...',  // row 5: eyes + headphones
    '...SSSssSSS...',  // row 6: nose
    '...SZZZZZzS...',  // row 7: stubble/mouth
    '....SSSSSS....',  // row 8: chin
    '...OOODOOOO...',  // row 9: hoodie collar + drawstring
    '..OOOOOOOOOO..',  // row 10: hoodie chest
    '.OOOOOLLOOOOO.',  // row 11: hoodie + laptop glow
    '.OOOOOOOOOOOO.',  // row 12: hoodie body
    '.OoOOOOOOOoO..',  // row 13: hoodie shadow
    '.SOOOOOOOOS...',  // row 14: hands peek
    '...QQQQQQQQ...',  // row 15: pants
    '...QQQQQQQQ...',  // row 16: pants
    '...QQ...QQ....',  // row 17: legs
    '..FF...FF.....',  // row 18: shoes
  ];
  return fromGrid(grid, {
    'H': 'rgb(102, 64, 38)',     // brown hair
    'h': 'rgb(128, 82, 48)',     // messy highlight
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'P': 'rgb(31, 31, 38)',      // headphone band
    'p': 'rgb(31, 31, 38)',      // headphone ears
    'O': 'rgb(64, 140, 217)',    // blue hoodie
    'o': 'rgb(46, 107, 173)',    // hoodie shadow
    'D': 'rgb(200, 200, 210)',   // drawstring
    'Z': 'rgb(180, 160, 140)',   // stubble (light brownish)
    'z': 'rgb(160, 140, 120)',   // stubble shadow
    'L': 'rgb(102, 217, 255)',   // laptop screen glow
    'Q': PANTS_DARK,
    'F': SHOES,
  });
}

// ── 3. Eng Manager ♀ — Asian woman, shoulder-length black hair, professional blouse + headset ──

function buildEngManager(): PixelList {
  // H=hair, S=skin, s=shadow, W=eye, E=eye, M=headset mic
  // B=blouse, b=blouse accent, A=arm, R=headset band, r=headset ear
  // P=pants, F=shoes
  const grid = [
    '....HHHHHH....',  // row 0: hair top
    '...HHHHHHHH...',  // row 1: hair
    '..HHHHHHHHHH..',  // row 2: hair sides
    '..HHSSSSSSHH..',  // row 3: hair frames face
    '..HSSWESWEHS..',  // row 4: eyes
    '..HSSSSsSSrH..',  // row 5: nose + headset ear
    '...SSSssSSS...',  // row 6: mouth
    '..H.SSSSSS.H..',  // row 7: chin + hair falls
    '..H..SSSS..H..',  // row 8: neck + shoulder hair
    '...BBBBBBBB...',  // row 9: blouse collar
    '..BBBBbBBBBB..',  // row 10: blouse
    '.ABBBBbBBBBA..',  // row 11: blouse + arms
    '.ABBBBBBBBBA..',  // row 12: blouse body
    '.ABBBBBBBBBA..',  // row 13: blouse lower
    '.SBBBBBBBBBS..',  // row 14: hands
    '...PPPPPPPP...',  // row 15: pants
    '...PPPPPPPP...',  // row 16: pants
    '...PP...PP....',  // row 17: legs
    '..FF...FF.....',  // row 18: shoes
  ];
  return fromGrid(grid, {
    'H': 'rgb(26, 22, 20)',      // black hair
    'S': SKIN_EAST,
    's': SKIN_EAST_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(51, 51, 64)',      // headset band
    'r': 'rgb(51, 51, 64)',      // headset earpiece
    'M': 'rgb(77, 77, 89)',      // mic
    'B': 'rgb(77, 128, 179)',    // professional blouse
    'b': 'rgb(60, 100, 148)',    // blouse accent
    'A': 'rgb(77, 128, 179)',    // arms = blouse
    'P': PANTS_NAVY,
    'F': SHOES,
  });
}

// ── 4. Backend Engineer ♂ — Brown/South Asian man, short dark hair, dark green hoodie, terminal glow ──

function buildBackendEngineer(): PixelList {
  const grid = [
    '....HHHHHH....',  // row 0: hair
    '...HHHHHHHH...',  // row 1: hair
    '...HHHHHHHH...',  // row 2: hair short
    '...SSSSSSSS...',  // row 3: forehead
    '...SWESSWES...',  // row 4: eyes
    '...SSSssSSS...',  // row 5: nose
    '...SSSssSSS...',  // row 6: mouth
    '....SSSSSS....',  // row 7: chin
    '...GGGGGGGG...',  // row 8: hoodie collar
    '..GGGGGGGGGG..',  // row 9: hoodie chest
    '.AGGGGLLGGGGA.',  // row 10: hoodie + terminal glow
    '.AGGGGGGGGGGA.',  // row 11: hoodie body
    '.AgGGGGGGGgA..',  // row 12: hoodie shadow
    '.AGGGGGGGGA...',  // row 13: hoodie lower
    '.SGGGGGGGGGS..',  // row 14: hands
    '...PPPPPPPP...',  // row 15: pants
    '...PPPPPPPP...',  // row 16: pants
    '...PP...PP....',  // row 17: legs
    '..FF...FF.....',  // row 18: shoes
  ];
  return fromGrid(grid, {
    'H': 'rgb(26, 22, 20)',      // dark hair
    'S': SKIN_MED,
    's': SKIN_MED_SH,
    'W': EYE_W,
    'E': EYE_B,
    'G': 'rgb(46, 102, 64)',     // dark green hoodie
    'g': 'rgb(36, 82, 50)',      // hoodie shadow
    'L': 'rgb(64, 230, 128)',    // terminal green glow
    'A': 'rgb(46, 102, 64)',     // arms = hoodie
    'P': PANTS_BLACK,
    'F': SHOES,
  });
}

// ── 5. Frontend Engineer ♀ — White woman, short bob with pink streak, colorful top ──

function buildFrontendEngineer(): PixelList {
  // H=hair(brown), K=pink streak, S=skin, T=colorful top, t=top accent
  const grid = [
    '...HHKHHHHH...',  // row 0: hair top with pink streak
    '..HHKHHHHHHH..',  // row 1: bob hair
    '..HHKHHHHHH...',  // row 2: bob sides
    '..HHSSSSSSSH..',  // row 3: hair frames face
    '..HSSWESWEHS..',  // row 4: eyes
    '...SSSssSSS...',  // row 5: nose
    '...SSSssSSS...',  // row 6: mouth
    '....SSSSSS....',  // row 7: chin
    '....SSSSSS....',  // row 8: neck
    '...TTTTTTTT...',  // row 9: top collar
    '..TTTTtTTTTT..',  // row 10: colorful top
    '.ATTTTtTTTTA..',  // row 11: top + arms
    '.ATTTTTTTTTTA.',  // row 12: top body
    '.ATTTTTTTTTA..',  // row 13: top lower
    '.STTTTTTTTS...',  // row 14: hands
    '...PPPPPPPP...',  // row 15: pants
    '...PPPPPPPP...',  // row 16: pants
    '...PP...PP....',  // row 17: legs
    '..FF...FF.....',  // row 18: shoes
  ];
  return fromGrid(grid, {
    'H': 'rgb(140, 100, 64)',    // light brown bob
    'K': 'rgb(230, 102, 166)',   // pink streak!
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'T': 'rgb(217, 115, 166)',   // colorful pink/coral top
    't': 'rgb(115, 179, 230)',   // blue accent stripe
    'A': 'rgb(217, 115, 166)',   // arms = top
    'P': PANTS_GRAY,
    'F': SHOES,
  });
}

// ── 6. UX Designer ♀ — Latina woman, dark hair, beret, turtleneck ──

function buildUxDesigner(): PixelList {
  // R=beret, H=hair, S=skin, N=turtleneck
  const grid = [
    '.....RRRRR....',  // row 0: beret top
    '....RRRRRRR...',  // row 1: beret
    '...RRRRRRRR...',  // row 2: beret brim
    '...HHHHHHHH...',  // row 3: hair under beret
    '..HHSSSSSSHH..',  // row 4: hair frames face
    '..HSSWESWEHS..',  // row 5: eyes
    '...SSSssSSS...',  // row 6: nose
    '...SSSssSSS...',  // row 7: mouth
    '....SSSSSS....',  // row 8: chin
    '...NNNNNNNN...',  // row 9: turtleneck collar
    '..NNNNNNNNNN..',  // row 10: turtleneck
    '.ANNNNNNNNNA..',  // row 11: turtleneck + arms
    '.ANNNNNNNNNA..',  // row 12: turtleneck body
    '.ANNNNNNNNA...',  // row 13: turtleneck lower
    '.SNNNNNNNNS...',  // row 14: hands
    '...PPPPPPPP...',  // row 15: pants
    '...PPPPPPPP...',  // row 16: pants
    '...PP...PP....',  // row 17: legs
    '..FF...FF.....',  // row 18: shoes
  ];
  return fromGrid(grid, {
    'R': 'rgb(179, 51, 64)',     // red beret
    'H': 'rgb(31, 22, 18)',      // dark hair
    'S': SKIN_OLIVE,
    's': SKIN_OLIVE_SH,
    'W': EYE_W,
    'E': EYE_B,
    'N': 'rgb(51, 51, 64)',      // black turtleneck
    'A': 'rgb(51, 51, 64)',      // arms = turtleneck
    'P': PANTS_DARK,
    'F': SHOES,
  });
}

// ── 7. Project Manager ♀ — White woman, blonde ponytail, blazer, clipboard ──

function buildProjectManager(): PixelList {
  // H=hair(blonde), T=ponytail, S=skin, B=blazer, W=blouse, C=clipboard, c=clipboard page
  const grid = [
    '....HHHHHHT...',  // row 0: hair + ponytail start
    '...HHHHHHHT...',  // row 1: hair
    '..HHHHHHHH.T..',  // row 2: hair + ponytail hangs
    '..HHSSSSSS.T..',  // row 3: forehead + ponytail
    '..HSSWESWE....',  // row 4: eyes
    '...SSSssSSS...',  // row 5: nose
    '...SSSssSSS...',  // row 6: mouth
    '....SSSSSS....',  // row 7: chin
    '...BBWWWWBB...',  // row 8: blazer collar + blouse
    '..BBBBWWBBBB..',  // row 9: blazer chest
    'CABBBBBBBBBA..',  // row 10: clipboard + blazer + arms
    'cABBBBBBBBBA..',  // row 11: clipboard page + body
    'cABBBBBBBBBA..',  // row 12: blazer body
    '.ABBBBBBBBA...',  // row 13: blazer lower
    '.SBBBBBBBBS...',  // row 14: hands
    '...PPPPPPPP...',  // row 15: pants
    '...PPPPPPPP...',  // row 16: pants
    '...PP...PP....',  // row 17: legs
    '..FF...FF.....',  // row 18: shoes
  ];
  return fromGrid(grid, {
    'H': 'rgb(230, 200, 120)',   // blonde hair
    'T': 'rgb(210, 180, 100)',   // ponytail (slightly darker)
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': 'rgb(230, 230, 235)',   // white blouse
    'E': EYE_B,
    'B': 'rgb(51, 64, 89)',      // navy blazer
    'A': 'rgb(51, 64, 89)',      // arms = blazer
    'C': 'rgb(179, 140, 89)',    // clipboard
    'c': 'rgb(242, 237, 224)',   // clipboard page
    'P': PANTS_NAVY,
    'F': SHOES,
  });
}

// ── 8. Product Manager ♂ — Black man, clean-cut, polo shirt ──

function buildProductManager(): PixelList {
  const grid = [
    '....HHHHHH....',  // row 0: hair
    '...HHHHHHHH...',  // row 1: hair
    '...HHHHHHHH...',  // row 2: hair short/clean
    '...SSSSSSSS...',  // row 3: forehead
    '...SWESSWES...',  // row 4: eyes
    '...SSSssSSS...',  // row 5: nose
    '...SSSssSSS...',  // row 6: mouth
    '....SSSSSS....',  // row 7: chin
    '...OOCCCOOO...',  // row 8: polo collar
    '..OOOOOOOOOO..',  // row 9: polo chest
    '.AOOOOOOOOOA..',  // row 10: polo + arms
    '.AOOOOOOOOOA..',  // row 11: polo body
    '.AoOOOOOOoA...',  // row 12: polo shadow
    '.AOOOOOOOOA...',  // row 13: polo lower
    '.SOOOOOOOOOS..',  // row 14: hands
    '...PPPPPPPP...',  // row 15: pants
    '...PPPPPPPP...',  // row 16: pants
    '...PP...PP....',  // row 17: legs
    '..FF...FF.....',  // row 18: shoes
  ];
  return fromGrid(grid, {
    'H': 'rgb(26, 22, 18)',      // dark hair
    'S': SKIN_DARK,
    's': SKIN_DARK_SH,
    'W': EYE_W,
    'E': EYE_B,
    'O': 'rgb(64, 128, 153)',    // teal polo
    'o': 'rgb(46, 102, 128)',    // polo shadow
    'C': 'rgb(64, 128, 153)',    // collar (same as polo)
    'A': 'rgb(64, 128, 153)',    // arms = polo
    'P': 'rgb(51, 51, 64)',      // dark chinos
    'F': SHOES,
  });
}

// ── 9. DevOps ♂ — White man, big red/ginger beard, flannel/plaid shirt ──

function buildDevops(): PixelList {
  // H=hair(ginger), R=beard, r=beard dark, S=skin
  // F=flannel, f=flannel dark stripe (plaid), A=arms
  const grid = [
    '....HHHHHH....',  // row 0: hair
    '...HHHHHHHH...',  // row 1: ginger hair
    '..HHHHHHHHHH..',  // row 2: hair
    '..HHSSSSSSHH..',  // row 3: forehead
    '..RSSWESWERR..',  // row 4: eyes + beard starts on sides
    '..RRSSsSSSRR..',  // row 5: nose + beard sides
    '..RRRRRrRRRR..',  // row 6: big beard!
    '..RRRRRRRRRR..',  // row 7: beard bottom
    '...RRRRRRRR...',  // row 8: beard tapers
    '...FFfFFfFF...',  // row 9: flannel collar (plaid!)
    '..FFfFFfFFFF..',  // row 10: flannel chest
    '.AFFfFFfFFFA..',  // row 11: flannel + arms
    '.AFFfFFfFFFA..',  // row 12: flannel body
    '.AFFFFFFFfFA..',  // row 13: flannel lower
    '.SFFFFFFFFFS..',  // row 14: hands
    '...PPPPPPPP...',  // row 15: pants
    '...PPPPPPPP...',  // row 16: jeans
    '...PP...PP....',  // row 17: legs
    '..QQ...QQ.....',  // row 18: boots
  ];
  return fromGrid(grid, {
    'H': 'rgb(191, 102, 38)',    // ginger hair
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(179, 77, 31)',     // red/ginger beard
    'r': 'rgb(148, 60, 24)',     // beard shadow
    'F': 'rgb(153, 64, 51)',     // flannel red
    'f': 'rgb(38, 51, 38)',      // flannel dark green stripe (plaid)
    'A': 'rgb(153, 64, 51)',     // arms = flannel
    'P': 'rgb(64, 77, 115)',     // blue jeans
    'Q': 'rgb(77, 56, 38)',      // work boots
  });
}

// ── 10. Database Guru ♀ — Asian woman, purple wizard hat, dark robe/cloak ──

function buildDatabaseGuru(): PixelList {
  // W=wizard hat purple, w=hat band/stars, H=hair, S=skin
  // D=dark robe, d=robe accent, V=robe clasp
  const grid = [
    '.......W......',  // row 0: hat tip
    '......WW......',  // row 1: hat point
    '.....WWWW.....',  // row 2: hat
    '....WWWWWW....',  // row 3: hat
    '...WWWWWWWW...',  // row 4: hat wider
    '..wwwwwwwwww..',  // row 5: hat brim + star band
    '..HHHHHHHHHH..',  // row 6: hair under hat
    '..HHSSSSSSHH..',  // row 7: hair frames face
    '..HSSWESWEHS..',  // row 8: eyes
    '...SSSssSSS...',  // row 9: nose
    '...SSSssSSS...',  // row 10: mouth
    '....SSSSSS....',  // row 11: chin
    '...DDVVVDDD...',  // row 12: robe collar + clasp
    '..DDDDDDDDDD..',  // row 13: robe chest
    '.ADDDDDDDDDA..',  // row 14: robe + arms (wide sleeves)
    '.ADDDDDDDDDA..',  // row 15: robe body
    '.SDDDDDDDDDS..',  // row 16: hands
    '..DDDDDDDDDD..',  // row 17: robe skirt
    '..DDDDDDDDDD..',  // row 18: robe hem
    '...FF...FF....',  // row 19: shoes peek
  ];
  return fromGrid(grid, {
    'W': 'rgb(102, 51, 153)',    // purple wizard hat
    'w': 'rgb(128, 77, 179)',    // hat brim (lighter purple + stars)
    'H': 'rgb(26, 22, 20)',      // dark hair
    'S': SKIN_EAST,
    's': SKIN_EAST_SH,
    'E': EYE_B,
    'D': 'rgb(38, 31, 46)',      // dark robe
    'd': 'rgb(51, 38, 64)',      // robe accent
    'V': 'rgb(191, 153, 51)',    // gold clasp
    'A': 'rgb(38, 31, 46)',      // arms = robe
    'F': SHOES,
  });
}

// ══════════════════════════════════════════════════════════════
//  DOG CHARACTERS — ~20 wide × 11 tall
// ══════════════════════════════════════════════════════════════

// ── 11. Dachshund — Long body, brown, short legs ──

function buildDachshund(): PixelList {
  // B=brown body, D=dark brown, L=light belly, N=nose, E=eye, T=tail
  const grid = [
    '................DDDD....',  // row 0: ears
    '................BBBB....',  // row 1: head top
    '...............BBBBB....',  // row 2: head
    '...............BBEBN....',  // row 3: face (eye + nose)
    '..T.BBBBBBBBBBBBBBB.....',  // row 4: body top + tail
    '..TBBBBBBBBBBBBBBBBB....',  // row 5: body
    '...BBLLLLLLLLLLLBBBB....',  // row 6: body + belly
    '...BBLLLLLLLLLLLBBBB....',  // row 7: body lower
    '...BB..........BB.......',  // row 8: legs start
    '...DD..........DD.......',  // row 9: legs
    '...DD..........DD.......',  // row 10: paws
  ];
  return fromGrid(grid, {
    'B': 'rgb(184, 107, 46)',    // brown
    'D': 'rgb(140, 77, 31)',     // dark brown
    'L': 'rgb(217, 153, 89)',    // light belly
    'T': 'rgb(140, 77, 31)',     // tail
    'E': DOG_EYE,
    'N': DOG_NOSE,
  });
}

// ── 12. Steve ❤️ — Red Heeler, auburn body, white speckles, pointed ears,
//    white forehead dot, THREE LEGS (missing one hind leg) ──

function buildCattleDog(): PixelList {
  // A=auburn body, D=auburn dark, W=white speckle, F=forehead dot
  // E=eye, N=nose, T=tail, L=leg tan, P=paw dark
  const grid = [
    '..............AA..AA....',  // row 0: pointed ears
    '..............AAAAAA....',  // row 1: head top
    '.............AAAFAAA....',  // row 2: head + white dot on forehead
    '.............AAEAAAN....',  // row 3: face (eye + nose)
    '..T.AAAAAAAAAAAAAAA.....',  // row 4: body top + tail
    '..TAAAWADAWADAAAAAAA....',  // row 5: body + speckles
    '...AADAWAWDAWAAAAAAA....',  // row 6: body + speckles
    '...AAAWADAWADAAAA.......',  // row 7: body lower + speckles
    '....L..........LL.......',  // row 8: ONE back leg + two front legs (3 total!)
    '....L..........LL.......',  // row 9: legs
    '....P..........PP.......',  // row 10: paws
  ];
  return fromGrid(grid, {
    'A': 'rgb(179, 89, 51)',     // auburn/red heeler
    'D': 'rgb(148, 66, 36)',     // darker auburn
    'W': 'rgb(230, 220, 210)',   // white speckles
    'F': 'rgb(240, 235, 230)',   // white forehead dot
    'T': 'rgb(148, 66, 36)',     // tail
    'E': DOG_EYE,
    'N': DOG_NOSE,
    'L': 'rgb(210, 170, 120)',   // tan legs
    'P': 'rgb(120, 80, 50)',     // dark paws
  });
}

// ── 13. Black Schnauzer — Black with gray beard ──

function buildSchnauzerBlack(): PixelList {
  // B=black body, G=gray beard, D=darker black, E=eye, N=nose, R=brow
  const grid = [
    '..............BB..BB....',  // row 0: ears
    '..............BBBBBB....',  // row 1: head top
    '.............RBBBBR.....',  // row 2: brows
    '.............BBEBBBN....',  // row 3: face + eye + nose
    '...............GGG......',  // row 4: beard!
    '..T.BBBBBBBBBBBGGGG....',  // row 5: body + beard continues
    '..TBBBBBBBBBBBBBBBB.....',  // row 6: body
    '...BBBDBBDBBBBBB.......',  // row 7: body + texture
    '...GG..........GG.......',  // row 8: legs (gray lower)
    '...GG..........GG.......',  // row 9: legs
    '...DD..........DD.......',  // row 10: paws
  ];
  return fromGrid(grid, {
    'B': 'rgb(31, 31, 38)',      // black
    'D': 'rgb(20, 20, 26)',      // darker black
    'G': 'rgb(89, 89, 102)',     // gray beard + lower legs
    'R': 'rgb(77, 77, 89)',      // brow highlights
    'E': DOG_EYE,
    'N': DOG_NOSE,
    'T': 'rgb(31, 31, 38)',      // tail
  });
}

// ── 14. Pepper Schnauzer — Salt & pepper with beard ──

function buildSchnauzerPepper(): PixelList {
  // M=mid gray body, L=light salt, D=dark pepper, G=beard, E=eye, N=nose, R=brow
  const grid = [
    '..............MM..MM....',  // row 0: ears
    '..............MMMMMM....',  // row 1: head top
    '.............RMMMMR.....',  // row 2: brows
    '.............MMEMMMN....',  // row 3: face
    '...............GGG......',  // row 4: beard
    '..T.LMDLMDLMMMGGGG.....',  // row 5: body (salt & pepper) + beard
    '..TMLDMLMDLMMMMMMMM....',  // row 6: body
    '...MMDLMDLMMMMMM.......',  // row 7: body lower
    '...LL..........LL.......',  // row 8: legs (lighter)
    '...LL..........LL.......',  // row 9: legs
    '...DD..........DD.......',  // row 10: paws
  ];
  return fromGrid(grid, {
    'M': 'rgb(97, 97, 107)',     // mid gray
    'L': 'rgb(150, 150, 158)',   // light salt
    'D': 'rgb(56, 56, 64)',      // dark pepper
    'G': 'rgb(170, 170, 178)',   // light beard
    'R': 'rgb(130, 130, 140)',   // brow highlights
    'E': DOG_EYE,
    'N': DOG_NOSE,
    'T': 'rgb(97, 97, 107)',     // tail
  });
}

// ── Pixel List → Canvas ──────────────────────────────────────

interface CachedSprite {
  canvas: OffscreenCanvas | HTMLCanvasElement;
  width: number;
  height: number;
}

/** Create an offscreen canvas, falling back to HTMLCanvasElement for Safari/iOS */
function createOffscreen(w: number, h: number): OffscreenCanvas | HTMLCanvasElement {
  if (typeof globalThis.OffscreenCanvas !== 'undefined') {
    return new OffscreenCanvas(w, h);
  }
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
}

const spriteCache = new Map<CharacterType, CachedSprite>();

function getPixels(type: CharacterType): PixelList {
  switch (type) {
    case 'architect':         return buildArchitect();
    case 'leadEngineer':      return buildLeadEngineer();
    case 'engManager':        return buildEngManager();
    case 'backendEngineer':   return buildBackendEngineer();
    case 'frontendEngineer':  return buildFrontendEngineer();
    case 'uxDesigner':        return buildUxDesigner();
    case 'projectManager':    return buildProjectManager();
    case 'productManager':    return buildProductManager();
    case 'devops':            return buildDevops();
    case 'databaseGuru':      return buildDatabaseGuru();
    case 'dachshund':         return buildDachshund();
    case 'cattleDog':         return buildCattleDog();
    case 'schnauzerBlack':    return buildSchnauzerBlack();
    case 'schnauzerPepper':   return buildSchnauzerPepper();
  }
}

function buildCachedSprite(type: CharacterType): CachedSprite {
  const pixels = getPixels(type);

  // Find bounding box
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const [x, y] of pixels) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }

  const w = (maxX - minX + 1) * PIXEL_SIZE;
  const h = (maxY - minY + 1) * PIXEL_SIZE;

  const canvas = createOffscreen(w, h);
  const ctx = canvas.getContext('2d')!;

  for (const [x, y, color] of pixels) {
    (ctx as CanvasRenderingContext2D).fillStyle = color;
    (ctx as CanvasRenderingContext2D).fillRect(
      (x - minX) * PIXEL_SIZE, (y - minY) * PIXEL_SIZE, PIXEL_SIZE, PIXEL_SIZE
    );
  }

  return { canvas, width: w, height: h };
}

function getCachedSprite(type: CharacterType): CachedSprite {
  let cached = spriteCache.get(type);
  if (!cached) {
    cached = buildCachedSprite(type);
    spriteCache.set(type, cached);
  }
  return cached;
}

// ── Public API ───────────────────────────────────────────────

/**
 * Render a character sprite centered at (x, y) on the given canvas context.
 * The sprite is rendered from the offscreen cache for performance.
 * Note: iOS SpriteKit draws with Y-up, but the pixel art grid coordinates
 * already have Y-up baked in. We flip the sprite vertically when drawing
 * to Canvas so the characters appear right-side-up.
 */
export function renderCharacter(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number,
  y: number,
  alpha: number = 1
): void {
  const sprite = getCachedSprite(type);

  if (alpha < 1) {
    ctx.save();
    ctx.globalAlpha = alpha;
  }

  // Flip vertically: the pixel art was built with Y-up (SpriteKit) but Canvas is Y-down
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(1, -1);
  ctx.drawImage(
    sprite.canvas,
    -sprite.width / 2,
    -sprite.height / 2
  );
  ctx.restore();

  if (alpha < 1) {
    ctx.restore();
  }
}

/** Get the rendered size of a character sprite for hit testing. */
export function getCharacterSize(type: CharacterType): { width: number; height: number } {
  const sprite = getCachedSprite(type);
  return { width: sprite.width, height: sprite.height };
}
