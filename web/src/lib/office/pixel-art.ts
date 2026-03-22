// Pixel art builder — grid-string approach for 14 characters
// Each character defined as an ASCII grid + color palette.
// Humans: ~42×60 logical pixels (SNES-quality 16-bit).
// Dogs: ~60×33 logical pixels.
// Rendered to Canvas via offscreen caching.

import type { CharacterType } from './types';

const PIXEL_SIZE = 1;

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
const SKIN_DARK_HI = 'rgb(160, 108, 72)';
const SKIN_MED     = 'rgb(198, 145, 90)';  // medium/brown
const SKIN_MED_SH  = 'rgb(170, 120, 70)';
const SKIN_MED_HI  = 'rgb(215, 165, 112)';
const SKIN_LIGHT   = 'rgb(242, 204, 166)'; // light
const SKIN_LIGHT_SH= 'rgb(217, 179, 140)';
const SKIN_LIGHT_HI= 'rgb(252, 220, 186)';
const SKIN_OLIVE   = 'rgb(210, 165, 110)'; // olive/latina
const SKIN_OLIVE_SH= 'rgb(185, 140, 90)';
const SKIN_OLIVE_HI= 'rgb(228, 182, 130)';
const SKIN_EAST    = 'rgb(235, 195, 155)'; // east asian
const SKIN_EAST_SH = 'rgb(210, 170, 130)';
const SKIN_EAST_HI = 'rgb(248, 212, 175)';

// Eyes
const EYE_W = 'rgb(242, 242, 242)';
const EYE_B = 'rgb(26, 26, 31)';

// Common
const SHOES  = 'rgb(56, 46, 38)';
const SHOES_HI = 'rgb(72, 60, 50)';
const PANTS_DARK = 'rgb(38, 46, 64)';
const PANTS_NAVY = 'rgb(38, 46, 77)';
const PANTS_BLACK = 'rgb(31, 31, 38)';
const PANTS_GRAY  = 'rgb(64, 64, 77)';

// Dog colors
const DOG_EYE  = 'rgb(51, 31, 20)';
const DOG_NOSE = 'rgb(26, 20, 15)';

// ══════════════════════════════════════════════════════════════
//  HUMAN CHARACTERS — ~42 wide × 60 tall
// ══════════════════════════════════════════════════════════════

// ── 1. Architect ♂ — Black man, clean blazer, glasses, neat short hair ──

function buildArchitect(): PixelList {
  // H=hair, h=hair highlight, S=skin, s=shadow, i=skin highlight
  // W=eye white, E=eye black, G=glasses frame, B=blazer, b=blazer shadow
  // K=blazer highlight, T=shirt(white), t=shirt shadow
  // A=arm(blazer), P=pants, p=pants shadow, F=shoes, f=shoe highlight
  // M=mouth, R=eyebrow
  const grid = [
    '..........................................', // 0
    '...............HHHHHHHHHHHH...............', // 1
    '..............HHHHHHHHHHHHHH..............', // 2
    '.............HHHHHHHHHHHHHhHH.............', // 3
    '.............HHHHHHHHHHHHHhHH.............', // 4
    '............HHHHHHHHHHHHHHhHHH............', // 5
    '............HHHHHHHHHHHHHHhHHH............', // 6
    '............HHHHHHHHHHHHHHHHHH.............', // 7
    '............HHHHHHHHHHHHHHHHHH.............', // 8
    '...........HHHHHHHHHHHHHHHHHH..............', // 9
    '...........HHHHHHHHHHHHHHHHHH..............', // 10
    '...........GGSSSSSSSSSSSSSSGG..............', // 11
    '...........GGSSSSSSSSSSSSSSGG..............', // 12
    '..........GGSSSSSSSSSSSSSSSSgG.............', // 13
    '..........GRRSSSSSSSSSSSRRSG...............', // 14: eyebrows
    '..........GWWWESSSSSSEWWWESG...............', // 15: eyes
    '..........GWWEESSSSSSEWWESG................', // 16: eyes lower
    '...........SSSSSSSsSSSSSSSS................', // 17
    '...........SSSSSSSsSSSSSSSS................', // 18
    '...........SSSSSSSSsSSSSSSS................', // 19: nose
    '...........SSSSSSSsSSSSSSSS................', // 20
    '............SSSSsMMMMsSSSS.................', // 21: mouth
    '............SSSSsSSSsSSSS..................', // 22
    '.............SSSSSSSSSsSS..................', // 23
    '.............SSSSSSSSSsSS..................', // 24: chin
    '..............SSSSSSSSSS...................', // 25: neck
    '..............SSSSSSSSSS...................', // 26
    '.............BBTTTTTTTTTBB.................', // 27: collar
    '............BBBTTTtTTTTBBBB................', // 28
    '...........BBBBBBBBBBBBBBBB................', // 29
    '..........BBBBBBBBBBBBBBBBBB...............', // 30
    '.........BBBBBBBBBBBBBBBBBBB...............', // 31
    '........ABBBBBBBBBBBBBBBBBBA...............', // 32
    '........ABBBBBBBBBBBBBBBBbBA..............', // 33
    '.......AABBBBBBBBBBBBBBBBbBAA..............', // 34
    '.......AABBBBBBBBBBBBBBbBbBAA..............', // 35
    '........ABBBBBBBBBBBBBBbBBA...............', // 36
    '........ABBBBBBBBBBBBBBbBBA...............', // 37
    '........ABBBBBBBBBBBBBBbBBA...............', // 38
    '.........SBBBBBBBBBBBBBBBS.................', // 39: hands
    '.........SBBBBBBBBBBBBBBBS.................', // 40
    '..........sBBBBBBBBBBBBBs..................', // 41
    '...........PPPPPPPPPPPPPP..................', // 42
    '...........PPPPPPPPPPPPPP..................', // 43
    '...........PPPPPPPPPPPPPP..................', // 44
    '...........PPPPPPppPPPPPP..................', // 45
    '...........PPPPPP..PPPPPP..................', // 46
    '...........PPPPP....PPPPP..................', // 47
    '...........PPPPP....PPPPP..................', // 48
    '...........PPPPP....PPPPP..................', // 49
    '...........PPPPP....PPPPP..................', // 50
    '...........PPPPP....PPPPP..................', // 51
    '...........PPPP......PPPP..................', // 52
    '...........PPPP......PPPP..................', // 53
    '..........FFFF......FFFFF..................', // 54
    '..........FFfFF.....FFfFF..................', // 55
    '..........FFFFF.....FFFFF..................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'H': 'rgb(31, 26, 22)',
    'h': 'rgb(48, 40, 34)',
    'S': SKIN_DARK,
    's': SKIN_DARK_SH,
    'i': SKIN_DARK_HI,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(22, 18, 14)',
    'G': 'rgb(64, 64, 77)',
    'g': 'rgb(50, 50, 60)',
    'B': 'rgb(51, 51, 64)',
    'b': 'rgb(38, 38, 51)',
    'K': 'rgb(64, 64, 80)',
    'T': 'rgb(230, 230, 235)',
    't': 'rgb(200, 200, 210)',
    'A': 'rgb(51, 51, 64)',
    'M': 'rgb(100, 60, 40)',
    'P': PANTS_DARK,
    'p': 'rgb(30, 36, 52)',
    'F': SHOES,
    'f': SHOES_HI,
  });
}

// ── 2. Lead Engineer ♂ — White man, blue hoodie, headphones, messy hair ──

function buildLeadEngineer(): PixelList {
  // H=hair, h=messy highlight, S=skin, s=shadow, W=eye white, E=eye black
  // P=headphone band, p=headphone ear, O=hoodie, o=shadow, D=drawstring
  // Z=stubble, Q=pants, F=shoes, f=shoe highlight, R=eyebrow, M=mouth
  const grid = [
    '..........................................', // 0
    '..............hHHHHHHHHh..................', // 1
    '.............hHhHHHHhHHh..................', // 2
    '............HHhHHHHHhHHHH.................', // 3
    '...........HHHhHHHHHhHHHHH................', // 4
    '...........HHHHHHHHHHHHHhH................', // 5
    '..........HHHHHHHHHHHHHHHHH................', // 6
    '..........HHHHHHHHHHHHHHhH................', // 7
    '..........PPHHHHHHHHHHHHPP.................', // 8: headphone band
    '.........PPPHHHHHHHHHHHPPP.................', // 9
    '.........ppHHSSSSSSSSSHHpp.................', // 10: headphone ears + forehead
    '.........ppHSSSSSSSSSSSHpp.................', // 11
    '.........ppHSSSSSSSSSSSSpp.................', // 12
    '.........ppSRRSSSSSSSRRSpp................', // 13: eyebrows
    '.........ppSWWWESSSSEWWWpp................', // 14: eyes
    '..........SSWWEESSSSEWWES..................', // 15: eyes lower
    '..........SSSSSSSSsSSSSSSS.................', // 16
    '...........SSSSSSsSSSSSS...................', // 17: nose
    '...........SSSSSSsSSSSSS...................', // 18
    '...........SZZZZZZZZZZzS..................', // 19: stubble
    '............SZZsMMMMsZZS..................', // 20: mouth + stubble
    '............SSSSSSSSSSSS...................', // 21
    '.............SSSSSSSSSS....................', // 22: chin
    '..............SSSSSSSS.....................', // 23: neck
    '..............SSSSSSSS.....................', // 24
    '.............OOODDDOOOOO..................', // 25: hoodie collar + drawstrings
    '............OOOOOOOOOOOO...................', // 26
    '...........OOOOOOOOOOOOOO..................', // 27
    '..........OOOOOOOOOOOOOOOO.................', // 28
    '.........OOOOOOOOOOOOOOOOOO................', // 29
    '........OOOOOOOOOOOOOOOOOOO................', // 30
    '........OOOOOOOOOOOOOOOOOoO...............', // 31
    '.......OOOOOOOOOOOOOOOOOOoOO..............', // 32
    '.......OOoOOOOOOOOOOOOOoOOO...............', // 33
    '........OOoOOOOOOOOOOOoOOO................', // 34
    '........OOoOOOOOOOOOOOoOOO................', // 35
    '.........OOOOOOOOOOOOOOOO..................', // 36
    '.........SOOOOOOOOOOOOOS...................', // 37: hands
    '.........SOOOOOOOOOOOOOS...................', // 38
    '..........sOOOOOOOOOOOs....................', // 39
    '...........QQQQQQQQQQQQ...................', // 40
    '...........QQQQQQQQQQQQ...................', // 41
    '...........QQQQQQQQQQQQ...................', // 42
    '...........QQQQQQQQQQQQ...................', // 43
    '...........QQQQQ..QQQQQ...................', // 44
    '...........QQQQQ..QQQQQ...................', // 45
    '...........QQQQQ..QQQQQ...................', // 46
    '...........QQQQ....QQQQ...................', // 47
    '...........QQQQ....QQQQ...................', // 48
    '...........QQQQ....QQQQ...................', // 49
    '..........FFFFF...FFFFF...................', // 50
    '..........FFfFF...FFfFF...................', // 51
    '..........FFFFF...FFFFF...................', // 52
    '..........................................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'H': 'rgb(102, 64, 38)',
    'h': 'rgb(128, 82, 48)',
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(82, 52, 30)',
    'P': 'rgb(31, 31, 38)',
    'p': 'rgb(31, 31, 38)',
    'O': 'rgb(64, 140, 217)',
    'o': 'rgb(46, 107, 173)',
    'D': 'rgb(200, 200, 210)',
    'Z': 'rgb(200, 175, 150)',
    'z': 'rgb(180, 155, 130)',
    'M': 'rgb(195, 130, 110)',
    'Q': PANTS_DARK,
    'F': SHOES,
    'f': SHOES_HI,
  });
}

// ── 3. Eng Manager ♀ — East Asian woman, neat bun, professional blouse ──

function buildEngManager(): PixelList {
  // H=hair, h=hair highlight, S=skin, s=shadow, W=eye, E=eye, B=blouse
  // b=blouse accent, A=arm, P=pants, F=shoes, R=eyebrow, M=mouth
  // U=bun, L=lip
  const grid = [
    '..........................................', // 0
    '...............UUUUUU.....................', // 1: bun top
    '..............UUUUUUUU....................', // 2
    '..............UUUUUUUU....................', // 3
    '..............HHUUUUHH....................', // 4
    '.............HHHHHHHHHH...................', // 5
    '............HHHHHHHHHHHH..................', // 6
    '............HHHHHHHHHHHH..................', // 7
    '...........HHHHHHHHHHHHH..................', // 8
    '...........HHHHHHHHHHHHH..................', // 9
    '...........HHSSSSSSSSSHH..................', // 10: hair frames face
    '...........HHSSSSSSSSSHH..................', // 11
    '..........HHSSSSSSSSSSHH..................', // 12
    '..........HHSRRSSSSSRRSHH.................', // 13: eyebrows
    '..........HSSWWWESSEWWWSH.................', // 14: eyes
    '..........HSSSWWESSEWWSH..................', // 15: eyes lower
    '...........SSSSSSsSSSSSS...................', // 16
    '...........SSSSSSSsSSSSSS..................', // 17: nose
    '...........SSSSSSSsSSSSSS..................', // 18
    '...........SSSSSSsSSSSSS...................', // 19
    '............SSSSsLLLsSSSS.................', // 20: mouth
    '............SSSSSSSSSsSSSS.................', // 21
    '.............SSSSSSSSSSS...................', // 22: chin
    '.............SSSSSSSSSSS...................', // 23
    '..............SSSSSSSSS....................', // 24: neck
    '..............SSSSSSSS.....................', // 25
    '.............BBBBBBBBBBB...................', // 26: blouse collar
    '............BBBBBbBBBBBBB..................', // 27
    '...........BBBBBBBBBBBBBBB.................', // 28
    '..........BBBBBBBBBBBBBBBBB................', // 29
    '.........BBBBBBBBBBBBBBBBBB................', // 30
    '........ABBBBBBBBBBBBBBBBBBA...............', // 31
    '........ABBBBBBbBBBBBBBBBBBA..............', // 32
    '.......AABBBBBBbBBBBBBBBBBBAA..............', // 33
    '.......AABBBBBBBBBBBBBBBbBAA...............', // 34
    '........ABBBBBBBBBBBBBBBbBA................', // 35
    '........ABBBBBBBBBBBBBBBbBA................', // 36
    '........ABBBBBBBBBBBBBBBBBA................', // 37
    '.........SBBBBBBBBBBBBBBBS.................', // 38: hands
    '.........SBBBBBBBBBBBBBBBS.................', // 39
    '..........sBBBBBBBBBBBBs..................', // 40
    '...........PPPPPPPPPPPPPP..................', // 41
    '...........PPPPPPPPPPPPPP..................', // 42
    '...........PPPPPPPPPPPPPP..................', // 43
    '...........PPPPPPPPPPPPPP..................', // 44
    '...........PPPPP..PPPPPP..................', // 45
    '...........PPPPP..PPPPPP..................', // 46
    '...........PPPPP..PPPPP...................', // 47
    '...........PPPP....PPPP...................', // 48
    '...........PPPP....PPPP...................', // 49
    '...........PPPP....PPPP...................', // 50
    '..........FFFFF...FFFFF...................', // 51
    '..........FFfFF...FFfFF...................', // 52
    '..........FFFFF...FFFFF...................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'H': 'rgb(26, 22, 20)',
    'h': 'rgb(40, 34, 30)',
    'U': 'rgb(26, 22, 20)',
    'S': SKIN_EAST,
    's': SKIN_EAST_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(20, 16, 12)',
    'L': 'rgb(190, 100, 100)',
    'B': 'rgb(77, 128, 179)',
    'b': 'rgb(60, 100, 148)',
    'A': 'rgb(77, 128, 179)',
    'P': PANTS_NAVY,
    'F': SHOES,
    'f': SHOES_HI,
    'M': 'rgb(200, 140, 120)',
  });
}

// ── 4. Backend Engineer ♂ — Medium-brown man, dark green hoodie, beard ──

function buildBackendEngineer(): PixelList {
  // H=hair, S=skin, s=shadow, W=eye, E=eye, G=hoodie, g=shadow
  // L=terminal glow, A=arm, P=pants, F=shoes, R=eyebrow, Z=beard
  // M=mouth
  const grid = [
    '..........................................', // 0
    '.............HHHHHHHHHHHH..................', // 1
    '............HHHHHHHHHHHHHH.................', // 2
    '...........HHHHHHHHHHHHHHHH................', // 3
    '...........HHHHHHHHHHHHHHHH................', // 4
    '...........HHHHHHHHHHHHHHHH................', // 5
    '...........HHHHHHHHHHHHHHHH................', // 6
    '...........HSSSSSSSSSSSSSHH................', // 7
    '..........HSSSSSSSSSSSSSSHH................', // 8
    '..........HSSSSSSSSSSSSSSSH................', // 9
    '..........SSRRSSSSSSSSRRSSS................', // 10: eyebrows
    '..........SSWWWESSSSSEWWWSS................', // 11: eyes
    '..........SSSWWESSSSSEWWSS.................', // 12: eyes lower
    '...........SSSSSSSsSSSSSS..................', // 13
    '...........SSSSSSSsSSSSSS..................', // 14: nose
    '...........SZZZZZZsZZZZZS.................', // 15: beard starts
    '...........SZZZZMMMZZZZZS.................', // 16: mouth in beard
    '............ZZZZZZZZZZZZ...................', // 17: beard
    '............ZZZZZZZZZZZ....................', // 18: beard tapers
    '.............ZZZZZZZZZZ....................', // 19
    '..............SSSSSSSS.....................', // 20: neck
    '..............SSSSSSSS.....................', // 21
    '.............GGGGGGGGGG....................', // 22: hoodie collar
    '............GGGGGGGGGGGGG..................', // 23
    '...........GGGGGGGGGGGGGG.................', // 24
    '..........GGGGGGGGGGGGGGGGG................', // 25
    '.........GGGGGGGGGGGGGGGGGG................', // 26
    '........AGGGGGGGGGGGGGGGGGA................', // 27
    '........AGGGGGGGGGGGGGGGgGA...............', // 28
    '.......AAGGGGGGLLGGGGGGGGAA................', // 29: terminal glow
    '.......AAGGGGGGLLGGGGGGgGAA...............', // 30
    '........AGGgGGGGGGGGGGgGGA................', // 31
    '........AGGgGGGGGGGGGGgGGA................', // 32
    '.........GGGGGGGGGGGGGGGGG.................', // 33
    '.........SGGGGGGGGGGGGGGGS.................', // 34: hands
    '.........SGGGGGGGGGGGGGGGS.................', // 35
    '..........sGGGGGGGGGGGGs..................', // 36
    '...........PPPPPPPPPPPPPP..................', // 37
    '...........PPPPPPPPPPPPPP..................', // 38
    '...........PPPPPPPPPPPPPP..................', // 39
    '...........PPPPPP..PPPPPP..................', // 40
    '...........PPPPP....PPPPP..................', // 41
    '...........PPPPP....PPPPP..................', // 42
    '...........PPPPP....PPPPP..................', // 43
    '...........PPPP......PPPP..................', // 44
    '...........PPPP......PPPP..................', // 45
    '..........FFFFF.....FFFFF..................', // 46
    '..........FFFFF.....FFFFF..................', // 47
    '..........FFFFF.....FFFFF..................', // 48
    '..........................................', // 49
    '..........................................', // 50
    '..........................................', // 51
    '..........................................', // 52
    '..........................................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'H': 'rgb(26, 22, 20)',
    'S': SKIN_MED,
    's': SKIN_MED_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(20, 16, 12)',
    'Z': 'rgb(36, 30, 24)',
    'M': 'rgb(150, 95, 65)',
    'G': 'rgb(46, 102, 64)',
    'g': 'rgb(36, 82, 50)',
    'L': 'rgb(64, 230, 128)',
    'A': 'rgb(46, 102, 64)',
    'P': PANTS_BLACK,
    'F': SHOES,
    'f': SHOES_HI,
  });
}

// ── 5. Frontend Engineer ♀ — White woman, ponytail, colorful pink top ──

function buildFrontendEngineer(): PixelList {
  // H=hair brown, K=pink streak, S=skin, s=shadow, W=eye, E=eye
  // T=pink top, t=blue accent, A=arm, P=pants, F=shoes, R=eyebrow
  // L=lip, N=ponytail, n=ponytail tie
  const grid = [
    '..........................................', // 0
    '...........HHKHHHHHHHH....................', // 1
    '..........HHKHHHHHHHHHN...................', // 2
    '.........HHKKHHHHHHHHHN...................', // 3
    '.........HHKHHHHHHHHHHN...................', // 4
    '........HHHKHHHHHHHHHH.N..................', // 5
    '........HHHHHHHHHHHHHHH.N.................', // 6
    '........HHHHHHHHHHHHHH..N.................', // 7
    '........HHHHHHHHHHHHHH..N.................', // 8
    '........HHHHHHHHHHHHHHH.n.................', // 9: ponytail tie
    '........HHSSSSSSSSSSSHH.N.................', // 10
    '........HHSSSSSSSSSSSHH.N.................', // 11
    '.........HSSSSSSSSSSSSH..N................', // 12
    '.........HSRRSSSSSSRRSH..N................', // 13: eyebrows
    '.........HSWWWESSSESWWWH.N................', // 14: eyes
    '.........HSSWWESSSESWWSH..N...............', // 15: eyes lower
    '..........SSSSSSSsSSSSSSS.N...............', // 16
    '..........SSSSSSSsSSSSSS..N...............', // 17: nose
    '..........SSSSSSSsSSSSSS..N...............', // 18
    '...........SSSSsLLLsSSS...N...............', // 19: mouth
    '...........SSSSSSSSSSSS...N...............', // 20
    '............SSSSSSSSSS....N...............', // 21: chin
    '............SSSSSSSSSS....N...............', // 22
    '.............SSSSSSSS.....N...............', // 23: neck
    '.............SSSSSSSS.....N...............', // 24
    '............TTTTTTTTTT....N...............', // 25: top collar
    '...........TTTTtTTTTTTT...N...............', // 26
    '..........TTTTTTTTTTTTTT..N...............', // 27
    '.........TTTTTTtTTTTTTTTT.................', // 28
    '........ATTTTTTtTTTTTTTTA.................', // 29
    '........ATTTTTTTTTTTTTTtTA................', // 30
    '.......AATTTTTTTTTTTTTTtTAA...............', // 31
    '.......AATTTTTTTTTTTTTtTTAA...............', // 32
    '........ATTTTTTTTTTTTTtTTA................', // 33
    '........ATTTTTTTTTTTTTTTA..................', // 34
    '.........ATTTTTTTTTTTTTA...................', // 35
    '.........STTTTTTTTTTTTS....................', // 36: hands
    '.........STTTTTTTTTTTTS....................', // 37
    '..........sTTTTTTTTTTs.....................', // 38
    '...........PPPPPPPPPPPP...................', // 39
    '...........PPPPPPPPPPPP...................', // 40
    '...........PPPPPPPPPPPP...................', // 41
    '...........PPPPP..PPPPP...................', // 42
    '...........PPPPP..PPPPP...................', // 43
    '...........PPPPP..PPPPP...................', // 44
    '...........PPPP....PPPP...................', // 45
    '...........PPPP....PPPP...................', // 46
    '...........PPPP....PPPP...................', // 47
    '..........FFFFF...FFFFF...................', // 48
    '..........FFfFF...FFfFF...................', // 49
    '..........FFFFF...FFFFF...................', // 50
    '..........................................', // 51
    '..........................................', // 52
    '..........................................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'H': 'rgb(140, 100, 64)',
    'K': 'rgb(230, 102, 166)',
    'N': 'rgb(130, 90, 55)',
    'n': 'rgb(230, 102, 166)',
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(110, 75, 45)',
    'L': 'rgb(200, 100, 100)',
    'T': 'rgb(217, 115, 166)',
    't': 'rgb(115, 179, 230)',
    'A': 'rgb(217, 115, 166)',
    'P': PANTS_GRAY,
    'F': SHOES,
    'f': SHOES_HI,
  });
}

// ── 6. UX Designer ♀ — Olive-skinned woman, dark turtleneck, short stylish hair ──

function buildUxDesigner(): PixelList {
  // H=hair, h=highlight, S=skin, s=shadow, W=eye, E=eye
  // N=turtleneck, n=turtleneck shadow, A=arm, P=pants, F=shoes
  // R=eyebrow, L=lip
  const grid = [
    '..........................................', // 0
    '............HHHHHHHHHHHH..................', // 1
    '...........HHHHHHHHHHHHhH.................', // 2
    '..........HHHHHHHHHHHHHhH.................', // 3
    '..........HHHHHHHHHHHHHhHH................', // 4
    '..........HHHHHHHHHHHHHhHH................', // 5
    '.........HHHHHHHHHHHHHHHHHH................', // 6
    '.........HHHHHHHHHHHHHHHHHH................', // 7
    '.........HHSSSSSSSSSSSSSHH.................', // 8
    '.........HHSSSSSSSSSSSSSHH.................', // 9
    '..........HSSSSSSSSSSSSSH..................', // 10
    '..........HSRRSSSSSSSRRSSH.................', // 11: eyebrows
    '..........HSWWWESSSSSEWWWH.................', // 12: eyes
    '..........HSSWWESSSSSEWWSH.................', // 13: eyes lower
    '...........SSSSSSSsSSSSSS..................', // 14
    '...........SSSSSSSsSSSSSS..................', // 15: nose
    '...........SSSSSSSsSSSSSS..................', // 16
    '............SSSSsLLLsSSSS.................', // 17: mouth
    '............SSSSSSSSSSSSS..................', // 18
    '.............SSSSSSSSSSS...................', // 19: chin
    '.............SSSSSSSSSS....................', // 20
    '..............SSSSSSSS.....................', // 21: neck
    '..............SSSSSSSS.....................', // 22
    '.............NNNNNNNNNN....................', // 23: turtleneck collar tall
    '.............NNNNNNNNNN....................', // 24
    '............NNNNNNNNNNNNN..................', // 25
    '...........NNNNNNNNNNNNNN.................', // 26
    '..........NNNNNNNNNNNNNNNNN................', // 27
    '.........NNNNNNNNNNNNNNNNNN................', // 28
    '........ANNNNNNNNNNNNNNNNNNA...............', // 29
    '........ANNNNNNNNNNNNNNNnNNA..............', // 30
    '.......AANNNNNNNNNNNNNNNnNNAA..............', // 31
    '.......AANNNNNNNNNNNNNnNNNAA...............', // 32
    '........ANNNNNNNNNNNNNnNNA.................', // 33
    '........ANNNNNNNNNNNNNnNNA.................', // 34
    '.........NNNNNNNNNNNNNNNNN.................', // 35
    '.........SNNNNNNNNNNNNNNS..................', // 36: hands
    '.........SNNNNNNNNNNNNNNS..................', // 37
    '..........sNNNNNNNNNNNs....................', // 38
    '...........PPPPPPPPPPPPPP..................', // 39
    '...........PPPPPPPPPPPPPP..................', // 40
    '...........PPPPPPPPPPPPPP..................', // 41
    '...........PPPPP..PPPPPP..................', // 42
    '...........PPPPP..PPPPP...................', // 43
    '...........PPPPP..PPPPP...................', // 44
    '...........PPPP....PPPP...................', // 45
    '...........PPPP....PPPP...................', // 46
    '...........PPPP....PPPP...................', // 47
    '..........FFFFF...FFFFF...................', // 48
    '..........FFfFF...FFfFF...................', // 49
    '..........FFFFF...FFFFF...................', // 50
    '..........................................', // 51
    '..........................................', // 52
    '..........................................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'H': 'rgb(31, 22, 18)',
    'h': 'rgb(48, 36, 28)',
    'S': SKIN_OLIVE,
    's': SKIN_OLIVE_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(24, 18, 12)',
    'L': 'rgb(180, 95, 90)',
    'N': 'rgb(51, 51, 64)',
    'n': 'rgb(38, 38, 51)',
    'A': 'rgb(51, 51, 64)',
    'P': PANTS_DARK,
    'F': SHOES,
    'f': SHOES_HI,
  });
}

// ── 7. Project Manager ♂ — White man, blazer over button-down, neat side-part ──

function buildProjectManager(): PixelList {
  // H=hair, h=part highlight, S=skin, s=shadow, W=eye white, E=eye black
  // B=blazer, b=shadow, T=white shirt, t=shadow, A=arm, P=pants, F=shoes
  // R=eyebrow, M=mouth
  const grid = [
    '..........................................', // 0
    '.............HHHHHHHHHHHH..................', // 1
    '............HHhHHHHHHHHHH.................', // 2
    '...........HHhHHHHHHHHHHHH................', // 3
    '...........HHhHHHHHHHHHHHH................', // 4
    '..........HHHhHHHHHHHHHHHH................', // 5
    '..........HHHhHHHHHHHHHHHH................', // 6
    '..........HHHHHHHHHHHHHHHH.................', // 7
    '..........HHHHHHHHHHHHHHH..................', // 8
    '..........HSSSSSSSSSSSSSHH.................', // 9
    '..........HSSSSSSSSSSSSSSH.................', // 10
    '..........HSSSSSSSSSSSSSH..................', // 11
    '..........SSRRSSSSSSSRRSS..................', // 12: eyebrows
    '..........SSWWWESSSSSEWWWS.................', // 13: eyes
    '..........SSSWWESSSSSEWWSS.................', // 14: eyes lower
    '...........SSSSSSsSSSSSSSS.................', // 15
    '...........SSSSSSSsSSSSSS..................', // 16: nose
    '...........SSSSSSSsSSSSSS..................', // 17
    '............SSSSsMMMMsSSSS.................', // 18: mouth
    '............SSSSSSSSSSSS...................', // 19
    '.............SSSSSSSSSS....................', // 20: chin
    '.............SSSSSSSSS.....................', // 21
    '..............SSSSSSSS.....................', // 22: neck
    '..............SSSSSSSS.....................', // 23
    '.............BBTTTTTTTBB...................', // 24: collar
    '............BBBTTTtTTTBBBB.................', // 25
    '...........BBBBBBBBBBBBBBB.................', // 26
    '..........BBBBBBBBBBBBBBBBB................', // 27
    '.........BBBBBBBBBBBBBBBBBBB...............', // 28
    '........ABBBBBBBBBBBBBBBBBBA...............', // 29
    '........ABBBBBBBBBBBBBBBBbBA..............', // 30
    '.......AABBBBBBBBBBBBBBBBBAA...............', // 31
    '.......AABBBBBBBBBBBBBBBbBAA...............', // 32
    '........ABBBBBBBBBBBBBBbBBA................', // 33
    '........ABBBBBBBBBBBBBBbBBA................', // 34
    '........ABBBBBBBBBBBBBBBBBA................', // 35
    '.........SBBBBBBBBBBBBBBBS.................', // 36: hands
    '.........SBBBBBBBBBBBBBBBS.................', // 37
    '..........sBBBBBBBBBBBBs..................', // 38
    '...........PPPPPPPPPPPPPP..................', // 39
    '...........PPPPPPPPPPPPPP..................', // 40
    '...........PPPPPPPPPPPPPP..................', // 41
    '...........PPPPP..PPPPPP..................', // 42
    '...........PPPPP..PPPPPP..................', // 43
    '...........PPPPP..PPPPP...................', // 44
    '...........PPPP....PPPP...................', // 45
    '...........PPPP....PPPP...................', // 46
    '...........PPPP....PPPP...................', // 47
    '..........FFFFF...FFFFF...................', // 48
    '..........FFfFF...FFfFF...................', // 49
    '..........FFFFF...FFFFF...................', // 50
    '..........................................', // 51
    '..........................................', // 52
    '..........................................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'H': 'rgb(82, 60, 40)',
    'h': 'rgb(105, 80, 55)',
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(62, 45, 28)',
    'M': 'rgb(195, 130, 110)',
    'B': 'rgb(51, 64, 89)',
    'b': 'rgb(38, 48, 70)',
    'T': 'rgb(230, 230, 235)',
    't': 'rgb(200, 200, 210)',
    'A': 'rgb(51, 64, 89)',
    'P': PANTS_NAVY,
    'F': SHOES,
    'f': SHOES_HI,
  });
}

// ── 8. Product Manager ♀ — Black woman, polo, natural hair (afro), confident ──

function buildProductManager(): PixelList {
  // H=hair(afro), h=highlight, S=skin, s=shadow, W=eye, E=eye
  // O=polo, o=shadow, C=collar, A=arm, P=pants, F=shoes
  // R=eyebrow, L=lip
  const grid = [
    '..........................................', // 0
    '............HHHHHHHHHHHHHH.................', // 1: afro top
    '..........HHHHHhHHHhHHHHHH................', // 2
    '.........HHHhHHHHHHHHhHHHHH...............', // 3
    '........HHHHHhHHHHHHhHHHHHH...............', // 4
    '........HHHHHHHHHHHHHHHHHhH...............', // 5
    '........HHHhHHHHHHHHHHhHHHH...............', // 6
    '........HHHHHHHHHHHHHHHHHHH................', // 7
    '........HHHSSSSSSSSSSSSHHH.................', // 8
    '........HHSSSSSSSSSSSSSSHH.................', // 9
    '........HHSSSSSSSSSSSSSSHH.................', // 10
    '........HHSRRSSSSSSSSRRSHH.................', // 11: eyebrows
    '.........HSWWWESSSSSEWWWSH.................', // 12: eyes
    '.........HSSWWESSSSSEWWSH..................', // 13: eyes lower
    '..........SSSSSSSsSSSSSS...................', // 14
    '..........SSSSSSSsSSSSSS...................', // 15: nose
    '..........SSSSSSsSSSSSS....................', // 16
    '...........SSSSsLLLsSSSS..................', // 17: mouth
    '...........SSSSSSSSSSSS...................', // 18
    '............SSSSSSSSSS.....................', // 19: chin
    '............SSSSSSSSS......................', // 20
    '.............SSSSSSSS......................', // 21: neck
    '.............SSSSSSSS......................', // 22
    '............OOCCCCCCOOO....................', // 23: polo collar
    '...........OOOOOOOOOOOOO...................', // 24
    '..........OOOOOOOOOOOOOOO..................', // 25
    '.........OOOOOOOOOOOOOOOOO.................', // 26
    '........AOOOOOOOOOOOOOOOOA.................', // 27
    '........AOOOOOOOOOOOOOOOoA................', // 28
    '.......AAOOOOOOOOOOOOOOOoOAA...............', // 29
    '.......AAOoOOOOOOOOOOOoOOAA................', // 30
    '........AOoOOOOOOOOOOOoOA.................', // 31
    '........AOOOOOOOOOOOOOOOOA.................', // 32
    '.........OOOOOOOOOOOOOOO...................', // 33
    '.........SOOOOOOOOOOOOOS...................', // 34: hands
    '.........SOOOOOOOOOOOOOS...................', // 35
    '..........sOOOOOOOOOOOs....................', // 36
    '...........PPPPPPPPPPPP....................', // 37
    '...........PPPPPPPPPPPP....................', // 38
    '...........PPPPPPPPPPPP....................', // 39
    '...........PPPPP..PPPPP....................', // 40
    '...........PPPPP..PPPPP....................', // 41
    '...........PPPPP..PPPPP....................', // 42
    '...........PPPP....PPPP....................', // 43
    '...........PPPP....PPPP....................', // 44
    '...........PPPP....PPPP....................', // 45
    '..........FFFFF...FFFFF....................', // 46
    '..........FFfFF...FFfFF....................', // 47
    '..........FFFFF...FFFFF....................', // 48
    '..........................................', // 49
    '..........................................', // 50
    '..........................................', // 51
    '..........................................', // 52
    '..........................................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'H': 'rgb(31, 26, 22)',
    'h': 'rgb(48, 40, 34)',
    'S': SKIN_DARK,
    's': SKIN_DARK_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(22, 18, 14)',
    'L': 'rgb(120, 65, 50)',
    'O': 'rgb(64, 128, 153)',
    'o': 'rgb(46, 102, 128)',
    'C': 'rgb(64, 128, 153)',
    'A': 'rgb(64, 128, 153)',
    'P': 'rgb(51, 51, 64)',
    'F': SHOES,
    'f': SHOES_HI,
  });
}

// ── 9. DevOps ♂ — White man, flannel/plaid, baseball cap, cargo vibe ──

function buildDevops(): PixelList {
  // C=cap, c=cap brim, H=hair ginger, S=skin, s=shadow
  // W=eye, E=eye, R=beard(ginger), r=beard shadow
  // X=flannel red, x=flannel green stripe, A=arm, P=jeans, Q=boots
  // M=mouth, B=eyebrow
  const grid = [
    '..........................................', // 0
    '.............CCCCCCCCCCCC..................', // 1: cap top
    '............CCCCCCCCCCCCC..................', // 2
    '...........CCCCCCCCCCCCCC..................', // 3
    '...........CCCCCCCCCCCCCC..................', // 4
    '..........ccccccccccccccccc................', // 5: cap brim
    '..........ccccccccccccccccc................', // 6
    '..........HHSSSSSSSSSSSHH..................', // 7: hair + forehead
    '..........HHSSSSSSSSSSSHH..................', // 8
    '..........HHSSSSSSSSSSSHH..................', // 9
    '..........RRBBSSSSSSBBRRR.................', // 10: eyebrows + beard starts
    '..........RRSWWWESSSEWWWR.................', // 11: eyes + beard
    '..........RRSSWWESSSEWWRR.................', // 12
    '..........RRSSSSSsSSSRRR..................', // 13: beard sides
    '..........RRSSSSSsSSSRRR..................', // 14: nose + beard
    '..........RRRRRRRRRRRrRR..................', // 15: big beard
    '..........RRRRRRMMMRRRRR...................', // 16: mouth in beard
    '...........RRRRRRRRRRRR....................', // 17: beard bottom
    '............RRRRRRRRRR.....................', // 18: beard tapers
    '.............RRRRRRRR......................', // 19
    '..............SSSSSS.......................', // 20: neck
    '..............SSSSSS.......................', // 21
    '.............XXxXXxXXXX....................', // 22: flannel collar
    '............XXxXXxXXxXXX...................', // 23
    '...........XXxXXxXXxXXXX..................', // 24
    '..........XXxXXxXXxXXxXXX.................', // 25
    '.........XXxXXxXXxXXxXXXXX................', // 26
    '........AXxXXxXXxXXxXXxXXA................', // 27
    '........AXxXXxXXxXXxXXxXxA................', // 28
    '.......AAXxXXxXXxXXxXXxXxAA...............', // 29
    '.......AAXxXXxXXxXXxXXxXXAA...............', // 30
    '........AXXxXXxXXxXXxXXXA.................', // 31
    '........AXXxXXxXXxXXxXXXA.................', // 32
    '.........XXxXXxXXxXXxXXX..................', // 33
    '.........SXXxXXxXXxXXXXS..................', // 34: hands
    '.........SXXxXXxXXxXXXXS..................', // 35
    '..........sXXXXXXXXXXXs...................', // 36
    '...........PPPPPPPPPPPP...................', // 37
    '...........PPPPPPPPPPPP...................', // 38
    '...........PPPPPPPPPPPP...................', // 39
    '...........PPPPPP.PPPPP...................', // 40
    '...........PPPPP..PPPPP...................', // 41
    '...........PPPPP..PPPPP...................', // 42
    '...........PPPP....PPPP...................', // 43
    '...........PPPP....PPPP...................', // 44
    '...........PPPP....PPPP...................', // 45
    '..........QQQQQ...QQQQQ...................', // 46: boots
    '..........QQQQQ...QQQQQ...................', // 47
    '..........QQQQQ...QQQQQ...................', // 48
    '..........................................', // 49
    '..........................................', // 50
    '..........................................', // 51
    '..........................................', // 52
    '..........................................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'C': 'rgb(64, 77, 115)',
    'c': 'rgb(50, 60, 95)',
    'H': 'rgb(191, 102, 38)',
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'B': 'rgb(160, 85, 32)',
    'R': 'rgb(179, 77, 31)',
    'r': 'rgb(148, 60, 24)',
    'M': 'rgb(195, 140, 120)',
    'X': 'rgb(153, 64, 51)',
    'x': 'rgb(38, 51, 38)',
    'A': 'rgb(153, 64, 51)',
    'P': 'rgb(64, 77, 115)',
    'Q': 'rgb(77, 56, 38)',
  });
}

// ── 10. Database Guru — East Asian, non-binary, purple wizard hat/robe ──

function buildDatabaseGuru(): PixelList {
  // Z=wizard hat, z=hat band/stars, H=hair, S=skin, s=shadow
  // W=eye white, E=eye, D=robe, d=robe shadow, V=gold clasp
  // A=arm(wide sleeves), F=shoes, R=eyebrow, L=lip
  const grid = [
    '..........................................', // 0
    '....................Z.....................', // 1: hat tip
    '...................ZZZ....................', // 2
    '..................ZZZZZ...................', // 3
    '.................ZZZZZZZ..................', // 4
    '................ZZZZZZZZZ.................', // 5
    '...............ZZZZZZZZZZZ................', // 6
    '..............ZZZZZZZZZZZZZ...............', // 7
    '.............ZZZZZZZZZZZZZZZ..............', // 8
    '............ZZZZZZZZZZZZZZZzZ.............', // 9
    '...........zzzzzzzzzzzzzzzzzzz............', // 10: hat brim + stars
    '...........zzzzzzzzzzzzzzzzzzz............', // 11
    '...........HHHHHHHHHHHHHHHHH...............', // 12: hair under hat
    '..........HHHHHHHHHHHHHHHHHHH..............', // 13
    '..........HHSSSSSSSSSSSSSHH................', // 14
    '..........HHSSSSSSSSSSSSSHH................', // 15
    '..........HSRRSSSSSSSRRSSH................', // 16: eyebrows
    '..........HSWWWESSSSSEWWWH.................', // 17: eyes
    '..........HSSWWESSSSSEWWSH.................', // 18: eyes lower
    '...........SSSSSSSsSSSSSS..................', // 19
    '...........SSSSSSSsSSSSSS..................', // 20: nose
    '...........SSSSSSSsSSSSSS..................', // 21
    '............SSSSsLLLsSSSS.................', // 22: mouth
    '............SSSSSSSSSSSS...................', // 23
    '.............SSSSSSSSSS....................', // 24: chin
    '..............SSSSSSSS.....................', // 25: neck
    '.............DDVVVVVVVDD...................', // 26: robe collar + clasp
    '............DDDDDDDDDDDDD.................', // 27
    '...........DDDDDDDDDDDDDDD................', // 28
    '..........DDDDDDDDDDDDDDDDD...............', // 29
    '.........DDDDDDDDDDDDDDDDDDD..............', // 30
    '........ADDDDDDDDDDDDDDDDDA...............', // 31
    '........ADDDDDDDDDDDDDDDDdDA...............', // 32
    '.......AADDDDDDDDDDDDDDDDdDAA...............', // 33
    '.......AADDDDDDDDDDDDDDdDDDAA...............', // 34
    '........ADDDDDDDDDDDDDDdDDA................', // 35
    '........ADDDDDDDDDDDDDDdDDA................', // 36
    '.........SDDDDDDDDDDDDDS..................', // 37: hands
    '.........SDDDDDDDDDDDDDS..................', // 38
    '..........DDDDDDDDDDDDD...................', // 39: robe skirt
    '..........DDDDDDDDDDDDD...................', // 40
    '..........DDDDDDDDDDDDD...................', // 41
    '..........DDDDDDDDDDDDD...................', // 42
    '..........DDDDDDddDDDDDD...................', // 43
    '..........DDDDDDDDDDDDD...................', // 44
    '..........DDDDDDDDDDDDD...................', // 45
    '..........DDDDDDDDDDDDD...................', // 46
    '..........DDDDDDDDDDDDD...................', // 47: robe hem
    '...........FFFFF.FFFFF.....................', // 48: shoes peek
    '...........FFFFF.FFFFF.....................', // 49
    '..........................................', // 50
    '..........................................', // 51
    '..........................................', // 52
    '..........................................', // 53
    '..........................................', // 54
    '..........................................', // 55
    '..........................................', // 56
    '..........................................', // 57
    '..........................................', // 58
    '..........................................', // 59
  ];
  return fromGrid(grid, {
    'Z': 'rgb(102, 51, 153)',
    'z': 'rgb(128, 77, 179)',
    'H': 'rgb(26, 22, 20)',
    'S': SKIN_EAST,
    's': SKIN_EAST_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(20, 16, 12)',
    'L': 'rgb(190, 110, 100)',
    'D': 'rgb(38, 31, 46)',
    'd': 'rgb(51, 38, 64)',
    'V': 'rgb(191, 153, 51)',
    'A': 'rgb(38, 31, 46)',
    'F': SHOES,
  });
}

// ══════════════════════════════════════════════════════════════
//  DOG CHARACTERS — ~60 wide × 33 tall
// ══════════════════════════════════════════════════════════════

// ── 11. Dachshund — "Elvito (Señor)": VERY long body, VERY short stubby legs ──

function buildDachshund(): PixelList {
  // B=brown body, D=dark brown, L=light belly/tan, N=nose, E=eye, T=tail
  // b=body shadow, H=ear(floppy,dark), W=eye white, C=collar red, M=muzzle tan
  //
  // Side profile: elongated skull flows smoothly into snout.
  // Floppy ears hang DOWN from mid-head to below jaw.
  // Eye sits high. Tiny stubby legs. Looong body.
  const grid = [
    '............................................................', // 0
    '............................................................', // 1
    '............................................BBBBBBB.........', // 2: top of skull
    '............................................BBBBBBBB........', // 3: skull
    '............................................BWBBBBBBB.......', // 4: eye high on head
    '............................................HBEBBBBBB.......', // 5: ear starts + pupil
    '............................................HBBBBBBBBBB.....', // 6: skull into snout
    '............................................HBBBBBMMMNN.....', // 7: snout to nose
    '..T.........................................HBBBBBBBMMM.....', // 8: lower jaw + muzzle
    '..TT........................................HBBBBBBBB.......', // 9: ear hangs down
    '...T........................................HHBBBBBBB.......', // 10: ear continues
    '....BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBCBBBBBB........', // 11: body + collar
    '....BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBCBBBBB..........', // 12: body + collar
    '...BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB...........', // 13
    '...BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBb...........',  // 14
    '...BBBLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLBBBBBBb.............',  // 15: belly
    '...BBBLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLBBBBb...............',  // 16
    '...BBbLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLBBBb................',  // 17
    '....BB.................................BB...................', // 18: legs (short stubby!)
    '....BB.................................BB...................', // 19
    '....DD.................................DD...................', // 20: paws
    '....DD.................................DD...................', // 21
    '............................................................', // 22
    '............................................................', // 23
    '............................................................', // 24
    '............................................................', // 25
    '............................................................', // 26
    '............................................................', // 27
    '............................................................', // 28
    '............................................................', // 29
    '............................................................', // 30
    '............................................................', // 31
    '............................................................', // 32
  ];
  return fromGrid(grid, {
    'B': 'rgb(184, 107, 46)',
    'b': 'rgb(155, 88, 35)',
    'D': 'rgb(140, 77, 31)',
    'L': 'rgb(217, 165, 100)',
    'H': 'rgb(140, 77, 31)',
    'M': 'rgb(210, 155, 90)',
    'T': 'rgb(140, 77, 31)',
    'E': DOG_EYE,
    'W': 'rgb(230, 230, 230)',
    'N': DOG_NOSE,
    'C': 'rgb(180, 50, 40)',
  });
}

// ── 12. Steve ❤️ — Red Heeler, THREE LEGS (missing one hind leg)
//    Athletic medium build, pointed ears, white forehead dot, auburn + white speckles ──

function buildCattleDog(): PixelList {
  // A=auburn body, D=dark auburn, W=white speckle, F=white forehead dot
  // E=eye, N=nose, T=tail, L=tan legs, P=dark paws, B=body shadow
  // C=collar, Q=eye white, M=mouth/muzzle tan
  const grid = [
    '............................................................', // 0
    '....................AA...AA..................................',  // 1: pointed ears (tall!)
    '...................AAAA.AAAA.................................',  // 2
    '...................AAAAAAAAAAA...............................',  // 3: head top
    '..................AAAAAAAAAAAA...............................',  // 4
    '..................AAAFFAAAAAA................................',  // 5: white forehead dot
    '..................AAAFFAAAAAA................................',  // 6
    '.................AAQAAAAAAQAA................................',  // 7: eyes
    '.................AAEAAAAAAEAA................................',  // 8
    '..................AAMMMMMMA..................................',  // 9: muzzle
    '..................AAMMNMMMA..................................',  // 10: nose
    '...................AMMMMMA...................................',  // 11: lower muzzle
    '...................AAAAAAA...................................',  // 12: chin
    '....................CCCCC....................................',  // 13: collar
    '....................CCCCC....................................',  // 14
    '...T..........AAAAAAAAAAAAAAA................................',  // 15: body top + tail curled up
    '...TT........AWDAWDAWDAWDAAAA...............................',  // 16: body + speckles
    '....TTAAA...AAWDAWDAWDAWDAAAA...............................',  // 17: tail connects to body
    '.....AAAA..AAADWADWADWADAAAAA................................',  // 18
    '......AAAAAAAWDAWDAWDAWDAAAA.................................',  // 19
    '......AAAAAADWADWADWADAAAAAA.................................',  // 20
    '.......AAAAAWDAWDAWDAWDAAAA.................................',  // 21
    '.......AAAAAADWADWADWAAAAAAB.................................',  // 22
    '........AAAAAAAAAAAAAAAAB....................................',  // 23: body tapers
    '........L..............LL...................................',  // 24: THREE legs (1 back + 2 front)
    '........L..............LL...................................',  // 25
    '........L..............LL...................................',  // 26
    '........L..............LL...................................',  // 27
    '........L..............LL...................................',  // 28
    '........PP.............PP...................................',  // 29: paws
    '........PP.............PP...................................',  // 30
    '............................................................', // 31
    '............................................................', // 32
  ];
  return fromGrid(grid, {
    'A': 'rgb(179, 89, 51)',
    'D': 'rgb(148, 66, 36)',
    'W': 'rgb(230, 220, 210)',
    'F': 'rgb(240, 235, 230)',
    'B': 'rgb(150, 72, 42)',
    'T': 'rgb(148, 66, 36)',
    'E': DOG_EYE,
    'Q': 'rgb(220, 215, 210)',
    'N': DOG_NOSE,
    'M': 'rgb(210, 170, 120)',
    'L': 'rgb(210, 170, 120)',
    'P': 'rgb(120, 80, 50)',
    'C': 'rgb(180, 50, 40)',
  });
}

// ── 13. Black Schnauzer "Hoku" — Compact square body, prominent beard + eyebrows ──

function buildSchnauzerBlack(): PixelList {
  // B=black body, G=gray beard, D=darker black, E=eye, N=nose
  // R=bushy brows, T=tail, b=body shadow, W=brow highlight
  const grid = [
    '............................................................', // 0
    '.....................BB...BB.................................',  // 1: perky folded ears
    '.....................BBB.BBB.................................',  // 2
    '....................BBBBBBBBB................................',  // 3: head top
    '....................BBBBBBBBB................................',  // 4
    '...................BBBBBBBBBB................................',  // 5
    '...................RRBBBBBRRB................................',  // 6: BUSHY eyebrows
    '...................RRWBBBBWRR................................',  // 7
    '..................BBEBBBBBEBN................................',  // 8: eyes + nose
    '..................BBBBBBBBBN.................................',  // 9
    '...................GGGGGGGGG.................................',  // 10: beard starts
    '..................GGGGGGGGGGG................................',  // 11: big bushy beard!
    '..................GGGGGGGGGGG................................',  // 12: beard hangs down
    '.................GGGGGGGGGGG.................................',  // 13
    '...T.............BBBBBBBBBBB.................................',  // 14: body starts + tail up
    '...TT..........BBBBBBBBBBBBB................................',  // 15
    '....TTB......BBBBBBBBBBBBBBB................................',  // 16
    '.....BBBB..BBBBBBBBBBBBBBBBB................................',  // 17
    '......BBBBBBBBBBBBBBBBBBBBB.................................',  // 18
    '......BBBBBbBBBBbBBBBBBBBBb.................................',  // 19: body texture
    '.......BBBBBBBBBBBBBBBBBBb..................................',  // 20
    '.......BBBBBBBBBBBBBBBBB....................................',  // 21
    '........GG............GG....................................',  // 22: legs (gray lower)
    '........GG............GG....................................',  // 23
    '........GG............GG....................................',  // 24
    '........GG............GG....................................',  // 25
    '........GG............GG....................................',  // 26
    '........GG............GG....................................',  // 27
    '........DD............DD....................................',  // 28: paws
    '........DD............DD....................................',  // 29
    '............................................................', // 30
    '............................................................', // 31
    '............................................................', // 32
  ];
  return fromGrid(grid, {
    'B': 'rgb(31, 31, 38)',
    'b': 'rgb(22, 22, 28)',
    'D': 'rgb(20, 20, 26)',
    'G': 'rgb(89, 89, 102)',
    'R': 'rgb(77, 77, 89)',
    'W': 'rgb(60, 60, 70)',
    'E': DOG_EYE,
    'N': DOG_NOSE,
    'T': 'rgb(31, 31, 38)',
  });
}

// ── 14. Pepper Schnauzer "Kai" — Salt & pepper, compact square body, big beard ──

function buildSchnauzerPepper(): PixelList {
  // M=mid gray, L=light salt, D=dark pepper, G=light beard, R=brows
  // E=eye, N=nose, T=tail, b=shadow, W=brow highlight
  const grid = [
    '............................................................', // 0
    '.....................MM...MM.................................',  // 1: perky folded ears
    '.....................MMM.MMM.................................',  // 2
    '....................MMMMMMMMM................................',  // 3: head top
    '....................MMMMMMMMM................................',  // 4
    '...................MMMMMMMMMM................................',  // 5
    '...................RRMMMMMRRM................................',  // 6: BUSHY eyebrows
    '...................RRWMMMMWRR................................',  // 7
    '..................MMEMMMMMEDN................................',  // 8: eyes + nose
    '..................MMMMMMMMMN.................................',  // 9
    '...................GGGGGGGGG.................................',  // 10: beard starts
    '..................GGGGGGGGGGG................................',  // 11: big bushy beard
    '..................GGGGGGGGGGG................................',  // 12
    '.................GGGGGGGGGGG.................................',  // 13
    '...T.............LDMLMDMLMD..................................',  // 14: body starts + tail
    '...TT..........LDMLMDMLMDMM.................................',  // 15: salt-pepper pattern
    '....TTM......MLDMLMDMLMDMMM.................................',  // 16
    '.....MLML..MLMDMLMDMLMDMMMM.................................',  // 17
    '......MLMDMLMDMLMDMLMDMMMM..................................',  // 18
    '......MLMDMLbDMLbDMLMDMMMb..................................',  // 19: body texture
    '.......MLMDMLMDMLMDMLMMM....................................',  // 20
    '.......MMLMDMLMDMLMDMM......................................',  // 21
    '........LL............LL....................................',  // 22: legs
    '........LL............LL....................................',  // 23
    '........LL............LL....................................',  // 24
    '........LL............LL....................................',  // 25
    '........LL............LL....................................',  // 26
    '........LL............LL....................................',  // 27
    '........DD............DD....................................',  // 28: paws
    '........DD............DD....................................',  // 29
    '............................................................', // 30
    '............................................................', // 31
    '............................................................', // 32
  ];
  return fromGrid(grid, {
    'M': 'rgb(97, 97, 107)',
    'L': 'rgb(150, 150, 158)',
    'D': 'rgb(56, 56, 64)',
    'G': 'rgb(170, 170, 178)',
    'R': 'rgb(130, 130, 140)',
    'W': 'rgb(110, 110, 120)',
    'b': 'rgb(80, 80, 90)',
    'E': DOG_EYE,
    'N': DOG_NOSE,
    'T': 'rgb(97, 97, 107)',
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

// ── Blink Animation — eye pixels replaced with skin color ────

const CHAR_SKIN: Partial<Record<CharacterType, string>> = {
  architect: SKIN_DARK,
  leadEngineer: SKIN_LIGHT,
  engManager: SKIN_EAST,
  backendEngineer: SKIN_MED,
  frontendEngineer: SKIN_LIGHT,
  uxDesigner: SKIN_OLIVE,
  projectManager: SKIN_LIGHT,
  productManager: SKIN_DARK,
  devops: SKIN_LIGHT,
  databaseGuru: SKIN_EAST,
};

const blinkCache = new Map<CharacterType, CachedSprite>();

function buildBlinkSprite(type: CharacterType): CachedSprite | null {
  const skinColor = CHAR_SKIN[type];
  if (!skinColor) return null; // dogs don't blink

  const pixels = getPixels(type);
  const blinkPixels: PixelList = pixels.map(([x, y, color]) => {
    if (color === EYE_W || color === EYE_B) return [x, y, skinColor];
    return [x, y, color];
  });

  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const [x, y] of blinkPixels) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }
  const w = (maxX - minX + 1) * PIXEL_SIZE;
  const h = (maxY - minY + 1) * PIXEL_SIZE;
  const canvas = createOffscreen(w, h);
  const ctx = canvas.getContext('2d')!;
  for (const [x, y, color] of blinkPixels) {
    (ctx as CanvasRenderingContext2D).fillStyle = color;
    (ctx as CanvasRenderingContext2D).fillRect(
      (x - minX) * PIXEL_SIZE, (y - minY) * PIXEL_SIZE, PIXEL_SIZE, PIXEL_SIZE
    );
  }
  return { canvas, width: w, height: h };
}

function getCachedBlinkSprite(type: CharacterType): CachedSprite | null {
  if (!CHAR_SKIN[type]) return null;
  let cached = blinkCache.get(type);
  if (cached) return cached;
  cached = buildBlinkSprite(type)!;
  if (cached) blinkCache.set(type, cached);
  return cached;
}

// ── Idle Animation Timing ────────────────────────────────────

/** Get animation state for a given timestamp. */
export function getIdleAnimation(time: number): { breathOffset: number; isBlinking: boolean } {
  // Breathing: gentle sine bob, 2s cycle, 1px amplitude
  const breathPhase = (time % 2000) / 2000;
  const breathOffset = Math.sin(breathPhase * Math.PI * 2) > 0.3 ? 1 : 0;

  // Blink: 150ms closed eyes every ~3.5s
  const isBlinking = (time % 3500) < 150;

  return { breathOffset, isBlinking };
}

/** Get the correct sprite for a character at a given time (normal or blink). */
export function getCharacterSprite(type: CharacterType, time?: number): CachedSprite {
  if (time != null) {
    const { isBlinking } = getIdleAnimation(time);
    if (isBlinking) {
      const blink = getCachedBlinkSprite(type);
      if (blink) return blink;
    }
  }
  return getCachedSprite(type);
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

/**
 * Render a character with idle animation (breathing bob + blink).
 * Pass Date.now() or performance.now() for time.
 */
export function renderCharacterAnimated(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number,
  y: number,
  time: number,
  alpha: number = 1
): void {
  const { breathOffset, isBlinking } = getIdleAnimation(time);

  const sprite = isBlinking
    ? (getCachedBlinkSprite(type) ?? getCachedSprite(type))
    : getCachedSprite(type);

  if (alpha < 1) {
    ctx.save();
    ctx.globalAlpha = alpha;
  }

  ctx.save();
  ctx.translate(x, y - breathOffset);
  ctx.scale(1, -1);
  ctx.drawImage(sprite.canvas, -sprite.width / 2, -sprite.height / 2);
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
