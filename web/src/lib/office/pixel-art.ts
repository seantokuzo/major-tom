// Pixel art builder — 10 tech specialists + 4 dogs
// Each character defined as an ASCII grid + color palette.
// Humans: ~42×60 logical pixels (SNES-quality 16-bit).
// Dogs: ~60×33 logical pixels.
// Rendered to Canvas via offscreen caching.

import type { CharacterType } from './types';
import type { FacingDirection } from './engine';

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

// ── Shared Constants ────────────────────────────────────────

// Skin tones
const SKIN_DARK    = 'rgb(139, 90, 56)';
const SKIN_DARK_SH = 'rgb(115, 72, 43)';
const SKIN_MED     = 'rgb(198, 145, 100)';
const SKIN_MED_SH  = 'rgb(170, 120, 80)';
const SKIN_LIGHT   = 'rgb(235, 200, 168)';
const SKIN_LIGHT_SH = 'rgb(205, 170, 140)';
const SKIN_TAN     = 'rgb(180, 130, 80)';
const SKIN_TAN_SH  = 'rgb(150, 105, 65)';

// Eyes (used by creatures and humans for blink)
const EYE_W = 'rgb(242, 242, 242)';
const EYE_B = 'rgb(26, 26, 31)';

// Dog colors
const DOG_EYE  = 'rgb(51, 31, 20)';
const DOG_NOSE = 'rgb(26, 20, 15)';

// ══════════════════════════════════════════════════════════════
//  HUMAN CHARACTERS — ~42 wide × 60 tall (SNES-quality 16-bit)
// ══════════════════════════════════════════════════════════════

// ── 1. Architect — Black woman, neat bun, glasses, dark blazer ──

function buildArchitect(): PixelList {
  // S=skin, s=skin shadow, H=hair dark, h=hair highlight
  // W=eye white, E=eye pupil, G=glasses frame, B=blazer, b=blazer shadow
  // C=collar white, T=trousers, t=trouser shadow, P=shoe, M=mouth, N=nose
  const grid = [
    '..........................................',
    '..............HHHHHH....................',
    '.............HHHHHHHH...................',
    '.............HHHhHHHH...................',
    '..............HHHHHH....................',
    '...............HHHH.....................',
    '.............HHHHHHHH...................',
    '............HHHHHHHHHH..................',
    '...........HHHHHHHHHHHH.................',
    '...........HHHHHHHHHHHH.................',
    '...........HSSSSSSSSSSH.................',
    '...........HSSSSSSSSSSH.................',
    '..........GGWWGSSSSGWWGG................',
    '..........GSWEGSSSSGEWSG................',
    '..........GGWWGSSSSGWWGG................',
    '...........SSSSSNSSSSS..................',
    '...........SSSSSSSSSSS..................',
    '...........SSSsMMsMSSS..................',
    '...........SSSSSMSSSS...................',
    '............SSSsSsSSSs..................',
    '.............SsSSSsSs...................',
    '..............SCCCS.....................',
    '.............CCCCCCC....................',
    '............BBBCCCBBB...................',
    '...........BBBBBBBBBBB..................',
    '..........BBBBBBBBBBBB..................',
    '..........BBBBBBBBBBBBb.................',
    '.........BBBBBBBBBBBBBb.................',
    '.........BBBBBBBBBBBBBb.................',
    '........SBBBBBBBBBBBBBbS................',
    '........SSBBBBBBBBBBBbSS................',
    '........SSSBBBBBBBBBbSSS................',
    '.........SSsBBBBBBBbsSS.................',
    '.........sSSBBBBBBBSSs..................',
    '..........SSBBBBBBBS....................',
    '..........SSBBBBBBBSS...................',
    '...........SBBBBBBS.....................',
    '...........TBBBBBBT.....................',
    '...........TTTTTTTTT....................',
    '...........TTTTTTTTT....................',
    '...........TTTTTTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTT.TTTTt...................',
    '...........TTTT.TTTT....................',
    '...........TTTT.TTTT....................',
    '...........PPPP.PPPP....................',
    '...........PPPP.PPPP....................',
    '..........PPPPP.PPPPP...................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'S': SKIN_DARK,
    's': SKIN_DARK_SH,
    'H': 'rgb(38, 28, 20)',
    'h': 'rgb(58, 42, 32)',
    'W': EYE_W,
    'E': EYE_B,
    'G': 'rgb(140, 140, 150)',
    'B': 'rgb(51, 51, 64)',
    'b': 'rgb(38, 38, 50)',
    'C': 'rgb(240, 240, 245)',
    'T': 'rgb(45, 45, 55)',
    't': 'rgb(35, 35, 45)',
    'P': 'rgb(30, 30, 35)',
    'M': 'rgb(160, 70, 60)',
    'N': SKIN_DARK_SH,
  });
}

// ── 2. Lead Engineer — White man, messy brown hair, hoodie, headphones, beard stubble ──

function buildLeadEngineer(): PixelList {
  // S=skin, s=skin shadow, H=hair brown, h=hair highlight, D=headphone band
  // d=headphone ear cups, W=eye white, E=eye pupil, K=hoodie, k=hoodie shadow
  // J=jeans, j=jeans shadow, P=sneakers, p=sneaker shadow, w=sneaker stripe
  // M=mouth, N=nose shadow, Z=stubble
  const grid = [
    '..........................................',
    '...........HHhHHHhH.....................',
    '..........HHHhHhHHHH....................',
    '.........HhHHHHHHHhHH...................',
    '.........HHHHHHHHHHHh...................',
    '........DDHHHHHHHHHHDD..................',
    '........DHHHHHHHHHHHDD..................',
    '........DHHHHHHHHHHHD...................',
    '.......ddHSSSSSSSSSHdd..................',
    '.......ddSSSSSSSSSSSdd..................',
    '.......ddSSWWSSSSWWSSd..................',
    '.......ddSSWESSSSEWSS...................',
    '........SSSSWWSSWWSSS...................',
    '........SSSSSsNsSSSss...................',
    '........SSSSSSsSSSSSs...................',
    '........ZSZSSSMSSSZSs...................',
    '........ZZSZZZSZZZSS....................',
    '.........ZSZZSZZSZZS....................',
    '..........SSSSSSSSS.....................',
    '...........SSSSSS.......................',
    '...........KKKKKK.......................',
    '..........KKKKKKKK......................',
    '.........KKKKKKKKKK.....................',
    '........KKKKKKKKKKKK....................',
    '........KKKKKKKKKKKKk...................',
    '.......KKKKKKKKKKKKKk...................',
    '.......KKKKKKKKKKKKKk...................',
    '......SKKKKKKKKKKKKKkS..................',
    '......SSKKKKKKKKKKKkSS..................',
    '......SSSKKKKKKKKKkSSS..................',
    '.......SSsKKKKKKKksSS...................',
    '.......sSSkKKKKKkSSs....................',
    '........SSkKKKKKkSS.....................',
    '........sSKKKKKKKSs.....................',
    '.........SKKKKKKS.......................',
    '..........KKKKKK........................',
    '..........JJJJJJJ.......................',
    '..........JJJJJJJJ......................',
    '..........JJJJjJJJJ.....................',
    '..........JJJJjJJJJ.....................',
    '..........JJJJjJJJj.....................',
    '..........JJJJjJJJj.....................',
    '..........JJJJjJJJj.....................',
    '..........JJJJjJJJj.....................',
    '..........JJJJjJJJj.....................',
    '..........JJJJjJJJj.....................',
    '..........JJJj.JJJj.....................',
    '..........JJJj.JJJj.....................',
    '..........JJJj.JJJj.....................',
    '..........JJJj.JJJj.....................',
    '..........PPPp.PPPp.....................',
    '.........PPPPP.PPPPP....................',
    '.........PPwPP.PPwPP....................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'H': 'rgb(100, 70, 42)',
    'h': 'rgb(130, 95, 60)',
    'D': 'rgb(50, 50, 55)',
    'd': 'rgb(40, 40, 48)',
    'W': EYE_W,
    'E': EYE_B,
    'K': 'rgb(64, 140, 217)',
    'k': 'rgb(48, 110, 180)',
    'J': 'rgb(70, 90, 130)',
    'j': 'rgb(55, 72, 108)',
    'P': 'rgb(60, 60, 65)',
    'p': 'rgb(45, 45, 50)',
    'w': 'rgb(220, 220, 225)',
    'M': 'rgb(195, 145, 120)',
    'N': SKIN_LIGHT_SH,
    'Z': 'rgb(170, 145, 125)',
  });
}

// ── 3. Engineering Manager — Asian woman, shoulder-length black hair, blouse + headset ──

function buildEngManager(): PixelList {
  // S=skin, s=skin shadow, H=hair, h=hair highlight, W=eye white, E=eye pupil
  // A=headset, B=blouse, b=blouse shadow, T=trousers, t=trouser shadow
  // P=heels, M=mouth shadow, N=nose shadow, L=lips
  const grid = [
    '..........................................',
    '.............HHHHHHHHH...................',
    '............HHHHHHHHHH...................',
    '...........HHHHHHHHHHHh.................',
    '...........HHHHHHHHHHHh.................',
    '...........HHHHHHHHHHH..................',
    '...........HHSSSSSSSHH..................',
    '..........HHSSSSSSSSHH..................',
    '..........HHSSSSSSSSHH..................',
    '..........HSSSWWSSWWSH..................',
    '..........HSSSWESSEESH..................',
    '.........AHSSSWWSSWWSHH.................',
    '.........AHSSSSSNSSSSHH.................',
    '.........ASSSSSSSSSSSSH.................',
    '..........SSSSSLLLSSSH..................',
    '..........SSSSsSsSsSHH..................',
    '..........HSSSSSSSSHH...................',
    '..........HHSSSSSSHHH...................',
    '..........HH.SSSSS.HH..................',
    '..........HH..SSS..HH..................',
    '..........HH.BBBBB.HH..................',
    '.........HH.BBBBBBB.HH.................',
    '.........H.BBBBBBBBB.H.................',
    '..........BBBBBBBBBBB...................',
    '.........BBBBBBBBBBBBb..................',
    '.........BBBBBBBBBBBBb..................',
    '........SBBBBBBBBBBBBbS.................',
    '........SSBBBBBBBBBBbSS.................',
    '........SSSBBBBBBBBbSSS.................',
    '.........SSsBBBBBBbsSS..................',
    '.........sSSBBBBBBSSs...................',
    '..........SSBBBBBBSs....................',
    '..........SSBBBBBBSS....................',
    '..........SSBBBBBBS.....................',
    '...........TTTTTTT......................',
    '...........TTTTTTTT.....................',
    '...........TTTTtTTTT....................',
    '...........TTTTtTTTT....................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTTtTTTTt...................',
    '...........TTTT.TTTTt...................',
    '...........TTTT.TTTT....................',
    '...........TTTT.TTTT....................',
    '...........PPPP.PPPP....................',
    '...........PPP...PPP....................',
    '...........PPP...PPP....................',
    '..........PPPP..PPPP....................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'S': SKIN_MED,
    's': SKIN_MED_SH,
    'H': 'rgb(30, 25, 22)',
    'h': 'rgb(50, 42, 38)',
    'W': EYE_W,
    'E': EYE_B,
    'A': 'rgb(55, 55, 60)',
    'B': 'rgb(77, 128, 179)',
    'b': 'rgb(60, 100, 148)',
    'T': 'rgb(45, 45, 55)',
    't': 'rgb(35, 35, 45)',
    'P': 'rgb(30, 30, 35)',
    'L': 'rgb(180, 100, 90)',
    'N': SKIN_MED_SH,
  });
}

// ── 4. Backend Engineer — South Asian man, short dark hair, dark green hoodie ──

function buildBackendEngineer(): PixelList {
  // S=skin, s=skin shadow, H=hair, W=eye white, E=eye pupil
  // K=hoodie green, k=hoodie shadow, J=jeans, j=jeans shadow
  // P=sneakers, p=sneaker shadow, w=sneaker stripe, M=mouth, G=green glow
  const grid = [
    '..........................................',
    '............HHHHHHHHH....................',
    '...........HHHHHHHHHHH...................',
    '...........HHHHHHHHHHHH.................',
    '..........HHHHHHHHHHHH..................',
    '..........HHHHHHHHHHHH..................',
    '..........HHSSSSSSSSHH..................',
    '..........HSSSSSSSSSHH..................',
    '..........HSSSSSSSSSSH..................',
    '..........SSSWWSSSWWSS..................',
    '..........SSSWESGSEESS..................',
    '..........SSSWWSSSWWSS..................',
    '..........SSSSSSNSSSS...................',
    '..........SSSSSsSSSSSs..................',
    '...........SSSSMSSSs....................',
    '...........SSSSSSSSS....................',
    '...........sSSSSSSSs....................',
    '............SSSSSSS.....................',
    '.............SSSSS......................',
    '.............KKKKK......................',
    '............KKKKKKK.....................',
    '...........KKKKKKKKK....................',
    '..........KKKKKKKKKKK...................',
    '..........KKKKKKKKKKKk..................',
    '.........KKKKKKKKKKKKk..................',
    '.........KKKKKKKKKKKKk..................',
    '........SKKKKKKKKKKKKkS.................',
    '........SSKKKKKKKKKKkSS.................',
    '........SSSKKKKKKKKkSSS.................',
    '.........SSsKKKKKKksSS..................',
    '.........sSSKKKKKKSSs...................',
    '..........SSKKKKKKSs....................',
    '..........sSKKKKKKSs....................',
    '..........SSKKKKKKS.....................',
    '...........KKKKKK.......................',
    '...........JJJJJJJ......................',
    '...........JJJJJJJJ.....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJj.JJJj....................',
    '...........JJJj.JJJj....................',
    '...........JJJj.JJJj....................',
    '...........JJJ..JJJj....................',
    '...........PPP..PPPp....................',
    '..........PPPP..PPPPp...................',
    '..........PPwP..PPwPp...................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'S': SKIN_TAN,
    's': SKIN_TAN_SH,
    'H': 'rgb(28, 22, 18)',
    'W': EYE_W,
    'E': EYE_B,
    'G': 'rgb(100, 200, 120)',
    'K': 'rgb(46, 102, 64)',
    'k': 'rgb(34, 80, 48)',
    'J': 'rgb(55, 60, 80)',
    'j': 'rgb(42, 46, 65)',
    'P': 'rgb(55, 55, 60)',
    'p': 'rgb(42, 42, 48)',
    'w': 'rgb(200, 200, 205)',
    'M': 'rgb(155, 100, 65)',
    'N': SKIN_TAN_SH,
  });
}

// ── 5. Frontend Engineer — White woman, short bob with pink streak, colorful top ──

function buildFrontendEngineer(): PixelList {
  // S=skin, s=skin shadow, H=hair dark, R=pink streak, W=eye white, E=eye pupil
  // B=colorful top, b=top shadow, J=jeans, j=jeans shadow
  // P=colorful sneakers, p=sneaker accent teal, L=lips
  const grid = [
    '..........................................',
    '............HHHHHHHH.....................',
    '...........HHHHHHHHHHH..................',
    '..........HHHRHHHHHHHH..................',
    '..........HHHRHHHHHHHH..................',
    '..........HHHRHHHHHHHHH.................',
    '.........HHHRHSSSSSSHHH.................',
    '.........HHHRSSSSSSSHH..................',
    '.........HHHSSSSSSSSHH..................',
    '.........HHSSWWSSSWWSHH.................',
    '.........HHSSWESSSEWSHH.................',
    '.........HHSSWWSSSWWSHH.................',
    '.........HHSSSSSNSSSSHR.................',
    '.........HHSSSSSSSSSSHH.................',
    '.........HHSSSSLLSSSSH..................',
    '.........HHSSSSSLSSSSH..................',
    '..........HSSSSSSSSSH...................',
    '..........HHsSSSSSsHH...................',
    '..........HH.SSSSS.HH..................',
    '...........H..SSS..H....................',
    '..............BBBBB.....................',
    '.............BBBBBBB....................',
    '............BBBBBBBBB...................',
    '...........BBBBBBBBBBb..................',
    '..........BBBBBBBBBBBb..................',
    '..........BBBBBBBBBBBb..................',
    '.........SBBBBBBBBBBBbS.................',
    '.........SSBBBBBBBBBbSS.................',
    '.........SSSBBBBBBBbSSS.................',
    '..........SSsBBBBBbsSS..................',
    '..........sSSBBBBBSSs...................',
    '...........SSBBBBBSs....................',
    '...........SSBBBBBSS....................',
    '...........SSBBBBBS.....................',
    '............BBBBBBB.....................',
    '...........JJJJJJJJ.....................',
    '...........JJJJJJJJ.....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJJjJJJj....................',
    '...........JJJj.JJJj....................',
    '...........JJJj.JJJj....................',
    '...........JJJj.JJJj....................',
    '...........JJJ..JJJj....................',
    '...........PPP..PPPp....................',
    '..........pPPP..PPPpp...................',
    '..........pPPP..PPPpp...................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'H': 'rgb(55, 40, 35)',
    'R': 'rgb(230, 100, 160)',
    'W': EYE_W,
    'E': EYE_B,
    'B': 'rgb(217, 115, 166)',
    'b': 'rgb(185, 90, 140)',
    'J': 'rgb(70, 90, 130)',
    'j': 'rgb(55, 72, 108)',
    'P': 'rgb(230, 120, 170)',
    'p': 'rgb(100, 200, 180)',
    'L': 'rgb(200, 110, 100)',
    'N': SKIN_LIGHT_SH,
  });
}

// ── 6. UX Designer — Latina woman, dark hair, beret, turtleneck ──

function buildUxDesigner(): PixelList {
  // R=beret red, r=beret shadow, H=hair dark, h=hair shadow
  // S=skin, s=skin shadow, W=eye white, E=eye pupil
  // T=turtleneck charcoal, t=turtleneck shadow, L=lip color
  // P=pants dark, p=pants shadow, B=boot, b=boot shadow
  const grid = [
    '..........................................',
    '...............RRRRRR....................',
    '..............RRRRRRRRR..................',
    '.............RRRRRRRRRRr.................',
    '.............rRRRRRRRRRr.................',
    '............HHHHHHHHHHHH.................',
    '...........HHHHHHHHHHHHHH................',
    '..........HHHHHSSSSSSHHHHh...............',
    '..........HHHHSSSSSSSSHHH................',
    '.........HHHHSSSSSSSSSHHH................',
    '.........HHHWWWSSSSSWWWHH................',
    '.........HHHWEESSSSSEEWHH................',
    '.........HHHWWWSSSSWWWsHH................',
    '.........HHHsSSSSSSSSSsHH................',
    '..........HHsSSSLLSSSsHH.................',
    '..........HHsSSSSSSSSsHH.................',
    '..........HHHsSSSSSSsHHH.................',
    '...........HHHsSSSSSHHH..................',
    '...........HHHhsSSshHHH..................',
    '............HHhTTTThHH...................',
    '...........TTTTTTTTTTTTT.................',
    '..........TTTTTTTTTTTTTTt................',
    '.........TTTTTTTTTTTTTTTt................',
    '.........tTTTTTTTTTTTTTTt................',
    '........StTTTTTTTTTTTTTTtS...............',
    '........SStTTTTTTTTTTTTtSS...............',
    '........SStTTTTTTTTTTTTtSS...............',
    '.........StTTTTTTTTTTTTtS................',
    '.........StTTTTTTTTTTTTtS................',
    '.........sstTTTTTTTTTTtss................',
    '..........stTTTTTTTTTTts.................',
    '..........ssttTTTTTTttss.................',
    '..........PPPPPPPPPPPPPP.................',
    '.........PPPPPPPPPPPPPPPP................',
    '.........PPPPPPPPPPPPPPPp................',
    '.........PPPPPPpPPPPPPPPp................',
    '.........PPPPPPpPPPPPPPPp................',
    '.........PPPPPPpPPPPPPPPp................',
    '..........PPPPPpPPPPPPPp.................',
    '..........PPPPPppPPPPPPp.................',
    '..........PPPPPppPPPPPPp.................',
    '..........PPPPPppPPPPPPp.................',
    '..........PPPPp..PPPPPp..................',
    '..........PPPPp..PPPPPp..................',
    '..........PPPPp..PPPPPp..................',
    '..........PPPPp..PPPPPp..................',
    '..........PPPPp..PPPPPp..................',
    '..........BBBBb..BBBBBb..................',
    '..........BBBBb..BBBBBb..................',
    '.........BBBBBb..BBBBBBb.................',
    '.........BBBBBb..BBBBBBb.................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'R': 'rgb(180, 50, 50)',
    'r': 'rgb(140, 38, 38)',
    'H': 'rgb(38, 28, 22)',
    'h': 'rgb(26, 18, 14)',
    'S': SKIN_MED,
    's': SKIN_MED_SH,
    'W': EYE_W,
    'E': EYE_B,
    'L': 'rgb(170, 75, 80)',
    'T': 'rgb(64, 64, 77)',
    't': 'rgb(48, 48, 58)',
    'P': 'rgb(45, 45, 55)',
    'p': 'rgb(32, 32, 40)',
    'B': 'rgb(50, 40, 35)',
    'b': 'rgb(35, 28, 24)',
  });
}

// ── 7. Project Manager — White woman, blonde ponytail, blazer, clipboard ──

function buildProjectManager(): PixelList {
  // H=hair blonde, h=hair shadow, S=skin, s=skin shadow
  // W=eye white, E=eye pupil, L=lip
  // Z=blazer navy, z=blazer shadow, I=shirt white
  // P=pants dark, p=pants shadow, O=shoe, o=shoe shadow
  // C=clipboard, c=clipboard detail
  const grid = [
    '..........................................',
    '..........................................',
    '..............HHHHHH.....................',
    '.............HHHHHHHH....................',
    '............HHHHHHHHHh...................',
    '............HHHHHHHHHHH..................',
    '...........HHHHHHHHHHHhHH...............',
    '...........HHSSSSSSSHHHHH................',
    '..........HHSSSSSSSSSHHHH................',
    '..........HHSSSSSSSSSHHH.................',
    '..........HWWWSSSSWWWHHH.................',
    '..........HWEESSSSEEWHHH.................',
    '..........HWWWSSSSWWWhHH.................',
    '..........HsSSSSSSSSshHH.................',
    '...........sSSSLLSSSSsH..................',
    '...........sSSSSSSSSSsH..................',
    '...........ssSSSSSSSssHH.................',
    '............ssSSSSSssHHH.................',
    '.............sSSSSSs.HHH.................',
    '.............sIIIIs..HHH.................',
    '...........ZZIIIIIZZZHH..................',
    '..........ZZZZIIIIZZZZh..................',
    '.........ZZZZZIIIIZZZZZh.................',
    '.........zZZZZIIIIZZZZZz.................',
    '........SzZZZZIIIIZZZZZzS................',
    '........SSzZZZIIIIZZZZzSS................',
    '........SSzZZZZIIZZZZZzCC................',
    '.........SzZZZZIIZZZZZzCC................',
    '.........szZZZZIIZZZZZzCc................',
    '.........sszZZZIIZZZZzsCc................',
    '..........szZZZIIZZZZzs..................',
    '..........szzZZIIZZZzzs..................',
    '..........PPPPPPPPPPPPPP.................',
    '.........PPPPPPPPPPPPPPPP................',
    '.........PPPPPPpPPPPPPPPp................',
    '.........PPPPPPpPPPPPPPPp................',
    '.........PPPPPPpPPPPPPPPp................',
    '..........PPPPPpPPPPPPPp.................',
    '..........PPPPPppPPPPPPp.................',
    '..........PPPPPppPPPPPPp.................',
    '..........PPPPPppPPPPPPp.................',
    '..........PPPPPppPPPPPPp.................',
    '..........PPPPp..PPPPPp..................',
    '..........PPPPp..PPPPPp..................',
    '..........PPPPp..PPPPPp..................',
    '..........PPPPp..PPPPPp..................',
    '..........PPPPp..PPPPPp..................',
    '..........OOOOo..OOOOOo..................',
    '.........OOOOOo..OOOOOOo.................',
    '.........OOOOOo..OOOOOOo.................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'H': 'rgb(220, 190, 120)',
    'h': 'rgb(185, 155, 90)',
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'L': 'rgb(195, 110, 110)',
    'Z': 'rgb(51, 64, 89)',
    'z': 'rgb(36, 46, 66)',
    'I': 'rgb(235, 235, 240)',
    'P': 'rgb(50, 50, 60)',
    'p': 'rgb(35, 35, 44)',
    'O': 'rgb(45, 40, 50)',
    'o': 'rgb(30, 26, 35)',
    'C': 'rgb(180, 160, 120)',
    'c': 'rgb(140, 125, 90)',
  });
}

// ── 8. Product Manager — Black man, clean-cut, polo shirt ──

function buildProductManager(): PixelList {
  // H=hair dark, S=skin, s=skin shadow, W=eye white, E=eye pupil
  // T=polo teal, t=polo shadow, K=polo collar, L=lip
  // Q=khaki pants, q=khaki shadow, N=sneaker, n=sneaker shadow
  // G=sneaker sole white
  const grid = [
    '..........................................',
    '..........................................',
    '..............HHHHHH.....................',
    '.............HHHHHHHHH...................',
    '............HHHHHHHHHHH..................',
    '............HHHHHHHHHHHH.................',
    '...........HHHHSSSSSSHHH.................',
    '...........HHHSSSSSSSSHH.................',
    '..........HHHSSSSSSSSSHH.................',
    '..........HHWWWSSSSWWWHH.................',
    '..........HHWEESSSSEEWH..................',
    '..........HHWWWSSSSSWWHH.................',
    '..........HHsSSSSSSSSsHH.................',
    '...........sSSSSSSSSSSs..................',
    '...........sSSSSLLSSSss..................',
    '...........sSSSSSSSSSss..................',
    '...........ssSSSSSSSSs...................',
    '............ssSSSSSss....................',
    '.............sSSSSs......................',
    '.............KKKKKK......................',
    '............KTTTTTTK.....................',
    '...........TTTTTTTTTTT...................',
    '..........TTTTTTTTTTTTt..................',
    '.........TTTTTTTTTTTTTTt.................',
    '........StTTTTTTTTTTTTtS.................',
    '........SStTTTTTTTTTTTtSS................',
    '........SStTTTTTTTTTTTtSS................',
    '.........StTTTTTTTTTTTtS.................',
    '.........StTTTTTTTTTTTtS.................',
    '.........sstTTTTTTTTTtss.................',
    '..........stTTTTTTTTTts..................',
    '..........ssttTTTTTttss..................',
    '..........QQQQQQQQQQQQ...................',
    '.........QQQQQQQQQQQQQq..................',
    '.........QQQQQQqQQQQQQQq.................',
    '.........QQQQQQqQQQQQQQq.................',
    '.........QQQQQQqQQQQQQQq.................',
    '..........QQQQQqQQQQQQq..................',
    '..........QQQQQqqQQQQQq..................',
    '..........QQQQQqqQQQQQq..................',
    '..........QQQQQqqQQQQQq..................',
    '..........QQQQq..QQQQQq..................',
    '..........QQQQq..QQQQQq..................',
    '..........QQQQq..QQQQQq..................',
    '..........QQQQq..QQQQQq..................',
    '..........QQQQq..QQQQQq..................',
    '..........NNNNn..NNNNNn..................',
    '..........NNNNn..NNNNNn..................',
    '.........NNNNNn..NNNNNNn.................',
    '.........GGGGGn..GGGGGGn.................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'H': 'rgb(26, 20, 16)',
    'S': SKIN_DARK,
    's': SKIN_DARK_SH,
    'W': EYE_W,
    'E': EYE_B,
    'L': 'rgb(120, 65, 50)',
    'T': 'rgb(64, 128, 153)',
    't': 'rgb(46, 100, 122)',
    'K': 'rgb(50, 105, 130)',
    'Q': 'rgb(195, 175, 140)',
    'q': 'rgb(165, 148, 115)',
    'N': 'rgb(60, 62, 68)',
    'n': 'rgb(42, 44, 50)',
    'G': 'rgb(230, 230, 235)',
  });
}

// ── 9. DevOps — White man, big red/ginger beard, flannel shirt ──

function buildDevops(): PixelList {
  // H=hair ginger, h=hair shadow, S=skin, s=skin shadow
  // W=eye white, E=eye pupil, R=beard ginger, r=beard shadow
  // F=flannel main, f=flannel shadow, X=flannel cross-hatch dark
  // J=jeans, j=jeans shadow, B=boot, b=boot shadow
  const grid = [
    '..........................................',
    '..........................................',
    '..............HHHHHH.....................',
    '.............HHHHHHHH....................',
    '............HHHHHHHHHH...................',
    '............HHHHHHHHHHh..................',
    '...........HHHHHHHHHHHh..................',
    '...........HHHSSSSSSSHHH.................',
    '..........HHHSSSSSSSSSHH.................',
    '..........HHWWWSSSSWWWHH.................',
    '..........HHWEESSSSEEWH..................',
    '..........HHWWWSSSSSWWHH.................',
    '..........RRsSSSSSSSSsRR.................',
    '.........RRRsSSSSSSSSsRRR................',
    '.........RRRRsSSSSSSSRRRR................',
    '........RRRRRRRRRRRRRRRRRr...............',
    '........RRRRRRRRRRRRRRRRRr...............',
    '........rRRRRRRRRRRRRRRRRr...............',
    '.........rRRRRRRRRRRRRRRr................',
    '..........rRRRRRRRRRRRRr.................',
    '...........rrRRRRRRRRrr..................',
    '............rRRRRRRRr....................',
    '............FFFFFFFFFFF..................',
    '...........FFXFFFFXFFFFf.................',
    '..........FFFFFXFFFFFFFFf................',
    '.........FFFXFFFFXFFFXFFFf...............',
    '........SfFFFFFFFFFFFFFFfS...............',
    '........SsfFXFFFFXFFFFXfsS...............',
    '........SsfFFFFXFFFFFFFFsS...............',
    '.........sfFXFFFFXFFFXFfs................',
    '.........ssfFFFFFFFFFFfss................',
    '..........sfFXFFFFXFFfs..................',
    '..........ssFFFFFFFFFFss.................',
    '.........JJJJJJJJJJJJJJJj................',
    '.........JJJJJJJJJJJJJJJj................',
    '.........JJJJJJjJJJJJJJJj................',
    '.........JJJJJJjJJJJJJJJj................',
    '.........JJJJJJjJJJJJJJJj................',
    '..........JJJJJjJJJJJJJj.................',
    '..........JJJJJjjJJJJJJj.................',
    '..........JJJJJjjJJJJJJj.................',
    '..........JJJJJjjJJJJJJj.................',
    '..........JJJJj..JJJJJj..................',
    '..........JJJJj..JJJJJj..................',
    '..........JJJJj..JJJJJj..................',
    '..........JJJJj..JJJJJj..................',
    '..........BBBBBb.BBBBBBb.................',
    '..........BBBBBb.BBBBBBb.................',
    '.........BBBBBBb.BBBBBBBb................',
    '.........BBBBBBb.BBBBBBBb................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'H': 'rgb(190, 100, 40)',
    'h': 'rgb(155, 78, 28)',
    'S': SKIN_LIGHT,
    's': SKIN_LIGHT_SH,
    'W': EYE_W,
    'E': EYE_B,
    'R': 'rgb(190, 100, 40)',
    'r': 'rgb(155, 78, 28)',
    'F': 'rgb(153, 64, 51)',
    'f': 'rgb(120, 48, 38)',
    'X': 'rgb(90, 38, 30)',
    'J': 'rgb(70, 90, 130)',
    'j': 'rgb(50, 66, 100)',
    'B': 'rgb(65, 50, 35)',
    'b': 'rgb(45, 34, 24)',
  });
}

// ── 10. Database Guru — Asian woman, purple wizard hat, dark robe ──

function buildDatabaseGuru(): PixelList {
  // V=wizard hat purple, v=hat shadow, K=hat band/stars accent
  // H=hair dark, h=hair shadow, S=skin, s=skin shadow
  // W=eye white, E=eye pupil, L=lip
  // D=robe dark, d=robe shadow, G=robe highlight trim
  // O=shoe, o=shoe shadow
  const grid = [
    '..........................................',
    '...................V......................',
    '..................VV......................',
    '..................VV......................',
    '.................VVV......................',
    '.................VVVV.....................',
    '................VVVVV.....................',
    '................VVVVVv....................',
    '...............VVVKVVv....................',
    '...............VVVVVVVv...................',
    '..............VVVVKVVVv...................',
    '..............VVVVVVVVVv..................',
    '.............VVVVVVVVVVv..................',
    '............VVVVVVVVVVVVv.................',
    '...........vvvVVVVVVVVvvvv................',
    '...........HHHHHHHHHHHHHH................',
    '..........HHHHHSSSSSSHHHHh...............',
    '..........HHHHSSSSSSSSHH.................',
    '..........HHHSSSSSSSSSHHH................',
    '.........HHHWWWSSSSWWWHHH................',
    '.........HHHWEESSSSEEWHHH................',
    '.........HHHWWWSSSSWWWhHH................',
    '.........HHHsSSSSSSSSsHH.................',
    '..........HHsSSSLLSSSsH..................',
    '..........HHsSSSSSSSSsH..................',
    '..........HHHsSSSSSSsHH..................',
    '...........HHsSSSSSsHH...................',
    '............ssSSSss......................',
    '............DDDDDDD......................',
    '...........GDDDDDDDDG...................',
    '..........GDDDDDDDDDDDG.................',
    '.........GDDDDDDDDDDDDDDGd...............',
    '.........dDDDDDDDDDDDDDDDd...............',
    '........DdDDDDDDDDDDDDDDDdD..............',
    '........DDdDDDDDDDDDDDDDdDD..............',
    '........DDdDDDDDDDDDDDDDdDD..............',
    '.........DdDDDDDDDDDDDDDdD...............',
    '.........SdDDDDDDDDDDDDDdS...............',
    '.........ssdDDDDDDDDDDdss................',
    '..........sdDDDDDDDDDDds.................',
    '..........GDDDDDDDDDDDDG................',
    '..........GDDDDDDDDDDDDG................',
    '..........GDDDDDDDDDDDDdG................',
    '..........GDDDDDdDDDDDDdG................',
    '..........GDDDDDdDDDDDDdG................',
    '..........GDDDDDdDDDDDDdG................',
    '.........GGDDDDDdDDDDDDdGG...............',
    '.........GGDDDDDddDDDDDdGG...............',
    '.........GGGDDDDddDDDDdGGG...............',
    '..........GGGGGGGGGGGGGGG................',
    '...........OOOOo..OOOOOo.................',
    '...........OOOOo..OOOOOo.................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
    '..........................................',
  ];
  return fromGrid(grid, {
    'V': 'rgb(102, 51, 153)',
    'v': 'rgb(75, 36, 115)',
    'K': 'rgb(200, 180, 80)',
    'H': 'rgb(30, 24, 20)',
    'h': 'rgb(20, 16, 12)',
    'S': SKIN_MED,
    's': SKIN_MED_SH,
    'W': EYE_W,
    'E': EYE_B,
    'L': 'rgb(170, 90, 85)',
    'D': 'rgb(51, 38, 77)',
    'd': 'rgb(36, 26, 56)',
    'G': 'rgb(85, 65, 120)',
    'O': 'rgb(40, 30, 45)',
    'o': 'rgb(28, 20, 32)',
  });
}

// ══════════════════════════════════════════════════════════════
//  DOG CHARACTERS — ~60 wide × 33 tall
// ══════════════════════════════════════════════════════════════

// ── Dachshund "Elvito (Señor)" — Long body, stubby legs, side profile ──

function buildDachshund(): PixelList {
  // Side profile facing right. Compact elongated body, big floppy ear, stubby legs.
  // B=brown body, b=shadow, D=dark paws, L=tan belly, H=floppy ear
  // M=muzzle, T=tail, E=eye pupil, W=eye white, N=nose, C=collar red
  const grid = [
    '............................................................', // 0
    '............................................................', // 1
    '............................................................', // 2
    '............................................................', // 3
    '............................................................', // 4
    '.............................................BBBBB..........', // 5: skull top
    '............................................BBBBBBB.........', // 6: skull
    '............................................BBBWBBBB........', // 7: eye white(W)
    '...........................................HBBBEBBBBB.......', // 8: floppy ear(H) + pupil(E)
    '..........................................HHBBBBBBBBB.......', // 9: ear droops, snout
    '..........................................HHBBBBMMMNN.......', // 10: muzzle(M) + nose(N)
    '..............TT..........................HHBBBBBBMM........', // 11: tail + lower jaw
    '...............TT.........................HBBBBBBB..........', // 12: tail + ear bottom
    '................TBBBBBBBBBBBBBBBBBBBBBBBBBCCBBB.............', // 13: body + collar(C)
    '................BBBBBBBBBBBBBBBBBBBBBBBBBCCBBB..............', // 14: body + collar
    '................BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.............', // 15: body full
    '................BBBBBBBBBBBBBBBBBBBBBBBBBBBBBb..............', // 16: body shadow(b)
    '................BBbLLLLLLLLLLLLLLLLLLLBBBBb.................', // 17: belly(L)
    '.................BbLLLLLLLLLLLLLLLLLBBBb....................', // 18: belly tapers
    '..................BB...................BB...................', // 19: stubby legs
    '..................DD...................DD...................', // 20: paws(D)
    '............................................................', // 21
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

// ── Steve — Red Heeler, THREE LEGS (missing one hind leg)
//    Athletic medium build, pointed ears, white forehead dot, auburn + white speckles ──

function buildCattleDog(): PixelList {
  // 3/4 profile. Athletic build, pointed ears, 3 legs, organic speckle.
  // A=auburn, D=dark auburn, W=white speckle, F=forehead dot
  // E=eye, N=nose, T=tail, L=leg tan, P=paws, B=body shadow
  // C=collar, Q=eye white, M=muzzle tan
  const grid = [
    '.............................................................', // 0
    '....................AA...AA..................................',  // 1: pointed ears
    '...................AAAA.AAAA.................................',  // 2
    '...................AAAAAAAAAAA...............................',  // 3: head
    '..................AAAAAAAAAAAA...............................',  // 4
    '..................AAAFFAAAAAA................................',  // 5: forehead dot(F)
    '..................AAAFFAAAAAA................................',  // 6
    '.................AAQAAAAAAQAA................................',  // 7: eyes(Q=white)
    '.................AAEAAAAAAEAA................................',  // 8: eyes(E=dark)
    '..................AAMMMMMMA..................................',  // 9: muzzle
    '..................AAMMNMMMA..................................',  // 10: nose(N)
    '...................AMMMMMA...................................',  // 11
    '...................AAAAAAA...................................',  // 12: chin
    '....................CCCCC....................................',  // 13: collar(C)
    '....................CCCCC....................................',  // 14
    '...T..........AAAAAAAAAAAAAAA................................',  // 15: body + tail
    '...TT........AAWAADAAWADAAAAA................................',  // 16: organic speckle
    '....TTAAA...AADAAWAAWAAADAAA.................................',  // 17: tail connects
    '.....AAAA..AAADWAAAAADWAAAAA.................................',  // 18
    '......AAAAAAADAAWAADAWADAAA..................................',  // 19
    '......AAAAAADWAAAAWADAAAAAA..................................',  // 20
    '.......AAAAAWDAAADAAWADAAA...................................',  // 21
    '.......AAAAAAAAAAAAAAAAAAB...................................',  // 22: body bottom
    '........AAAAAAAAAAAAAAAAB....................................',  // 23: tapers
    '........L..............LL....................................',  // 24: 3 legs
    '........L..............LL....................................',  // 25
    '........L..............LL....................................',  // 26
    '........PP.............PP....................................',  // 27: paws
    '.............................................................', // 28
    '.............................................................', // 29
    '.............................................................', // 30
    '.............................................................', // 31
    '.............................................................', // 32
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

// ── Black Schnauzer "Hoku" — Compact square body, prominent beard + eyebrows ──

function buildSchnauzerBlack(): PixelList {
  // Side profile. Folded ear, bushy brows, big beard, gray highlights for visibility.
  // B=black body, g=gray highlight, G=beard gray, D=dark paws, E=eye, N=nose
  // R=bushy brows, T=tail, b=body shadow, W=brow highlight
  const grid = [
    '.............................................................', // 0
    '....................BBBBB....................................',  // 1: single folded ear
    '...................BBBBBBB...................................',  // 2: ear widens
    '...................BBBBBBBBB.................................',  // 3: ear into skull
    '..................BBBBBBBBB..................................',  // 4: skull
    '..................BBBBBBBBB..................................',  // 5
    '...................RRBBBBBBB.................................',  // 6: bushy brows(R)
    '..................RRWBBBBBBB.................................',  // 7: brow + eye white(W)
    '..................BBEBBBBBBN.................................',  // 8: eye(E) + nose(N)
    '..................BBBBBBBBN..................................',  // 9: jaw
    '...................GGGGGGG...................................',  // 10: beard starts
    '..................GGGGGGGGGGG................................',  // 11: big bushy beard
    '..................GGGGGGGGGGG................................',  // 12: beard
    '.................GGGGGGGGGGG.................................',  // 13: beard hangs
    '...T.............BBBBBBBBBBB.................................',  // 14: body + tail
    '...TT..........BBBBBBBBBBBBBg................................',  // 15: gray highlight(g)
    '....TTB......BBBBBBBBBBBBBBBg................................',  // 16
    '.....BBBB..BBBBBBBBBBBBBBBBBg................................',  // 17
    '......BBBBBBBBBBBBBBBBBBBBBg.................................',  // 18
    '......BBBBBgBBBBgBBBBBBBBBg..................................',  // 19: body texture
    '.......BBBBBBBBBBBBBBBBBBg...................................',  // 20
    '.......BBBBBBBBBBBBBBBBBg....................................',  // 21: body bottom
    '........GG............GG.....................................',  // 22: gray legs
    '........GG............GG.....................................',  // 23
    '........GG............GG.....................................',  // 24
    '........DD............DD.....................................',  // 25: paws
    '.............................................................', // 26
    '.............................................................', // 27
    '.............................................................', // 28
    '.............................................................', // 29
    '.............................................................', // 30
    '.............................................................', // 31
    '.............................................................', // 32
  ];
  return fromGrid(grid, {
    'B': 'rgb(36, 36, 44)',
    'b': 'rgb(22, 22, 28)',
    'g': 'rgb(58, 58, 68)',
    'D': 'rgb(20, 20, 26)',
    'G': 'rgb(100, 100, 115)',
    'R': 'rgb(82, 82, 95)',
    'W': 'rgb(65, 65, 78)',
    'E': DOG_EYE,
    'N': DOG_NOSE,
    'T': 'rgb(36, 36, 44)',
  });
}

// ── Pepper Schnauzer "Kai" — Salt & pepper, compact square body, big beard ──

function buildSchnauzerPepper(): PixelList {
  // Side profile. Same structure as black schnauzer, salt & pepper coloring.
  // M=mid gray, L=light salt, D=dark pepper, G=beard, R=brows
  // E=eye, N=nose, T=tail, b=shadow, W=brow highlight
  const grid = [
    '.............................................................', // 0
    '....................MMMMM....................................',  // 1: single folded ear
    '...................MMMMMMM...................................',  // 2: ear widens
    '...................MMMMMMMMM.................................',  // 3: ear into skull
    '..................MMMMMMMMM..................................',  // 4: skull
    '..................MMMMMMMMM..................................',  // 5
    '...................RRMMMMMMM.................................',  // 6: bushy brows(R)
    '..................RRWMMMMMML.................................',  // 7: brow + eye white(W)
    '..................MMEMMMMMLN.................................',  // 8: eye(E) + nose(N)
    '..................MMMMMMMMN..................................',  // 9: jaw
    '...................GGGGGGG...................................',  // 10: beard starts
    '..................GGGGGGGGGGG................................',  // 11: big bushy beard
    '..................GGGGGGGGGGG................................',  // 12: beard
    '.................GGGGGGGGGGG.................................',  // 13: beard hangs
    '...T.............MDMMLMDMMDL.................................',  // 14: body + tail
    '...TT..........MDMMDLMMDLMMLb................................',  // 15: organic salt-pepper
    '....TTM......MMDLMMMDMLDMMMLD................................',  // 16
    '.....MMMM..MMLDMMMDLMMMDMMML.................................',  // 17
    '......MMMMMDMMLDMMMLDMMMMML..................................',  // 18
    '......MMLDMbMDMbMLDMLDMMMb...................................',  // 19: body texture
    '.......MMDLMMMLDMMDMMLMMb....................................',  // 20
    '.......MMDLMMMLDMMDLMMM......................................',  // 21: body bottom
    '........LL............LL.....................................',  // 22: light legs
    '........LL............LL.....................................',  // 23
    '........LL............LL.....................................',  // 24
    '........DD............DD.....................................',  // 25: paws
    '.............................................................', // 26
    '.............................................................', // 27
    '.............................................................', // 28
    '.............................................................', // 29
    '.............................................................', // 30
    '.............................................................', // 31
    '.............................................................', // 32
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
    // Humans
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
    // Dogs
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

// ── Blink Animation — eye pixels replaced with body color ────

const CHAR_BLINK_COLOR: Partial<Record<CharacterType, string>> = {
  // Humans — blink to skin tone
  architect:        SKIN_DARK,
  leadEngineer:     SKIN_LIGHT,
  engManager:       SKIN_MED,
  backendEngineer:  SKIN_TAN,
  frontendEngineer: SKIN_LIGHT,
  uxDesigner:       SKIN_MED,
  projectManager:   SKIN_LIGHT,
  productManager:   SKIN_DARK,
  devops:           SKIN_LIGHT,
  databaseGuru:     SKIN_MED,
};

const blinkCache = new Map<CharacterType, CachedSprite>();

function getCachedWritingSprite(_type: CharacterType): CachedSprite | null {
  // No creatures have writing poses yet — always returns null
  return null;
}

function buildBlinkSprite(type: CharacterType): CachedSprite | null {
  const skinColor = CHAR_BLINK_COLOR[type];
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
  if (!CHAR_BLINK_COLOR[type]) return null;
  let cached = blinkCache.get(type);
  if (cached) return cached;
  cached = buildBlinkSprite(type)!;
  if (cached) blinkCache.set(type, cached);
  return cached;
}

// ── Idle Animation Timing ────────────────────────────────────

/** Get animation state for a given timestamp. */
export function getIdleAnimation(time: number): { breathOffset: number; isBlinking: boolean; isWriting: boolean } {
  // Breathing: gentle sine, 3s cycle, very subtle (0 or 1px)
  const breathPhase = (time % 3000) / 3000;
  const breathOffset = Math.sin(breathPhase * Math.PI * 2) > 0.4 ? 1 : 0;

  // Blink: 150ms closed eyes every ~3.5s
  const isBlinking = (time % 3500) < 150;

  // Clipboard writing cycle: 2s looking forward, 1.5s writing, repeating (3.5s total)
  const writeCycle = 3500;
  const writePhase = time % writeCycle;
  const isWriting = writePhase >= 2000; // last 1.5s of cycle = writing

  return { breathOffset, isBlinking, isWriting };
}

// ── Idle Overlay Animations ─────────────────────────────────
// Subtle per-pixel overlay animations drawn ON TOP of the cached sprite.
// These create natural idle movement without re-rendering the full sprite.

/** Feature positions in grid coordinates (row, col) for overlay animations. */
interface HumanFeatures {
  /** Grid dimensions [rows, cols] for coordinate conversion */
  gridSize: [number, number];
  /** Left hand position (row, col) — for subtle fidget */
  leftHand: [number, number];
  /** Right hand position (row, col) */
  rightHand: [number, number];
  /** Skin/clothing color to use for hand fidget overlay */
  handColor: string;
  /** Body color for arm area overlays */
  bodyColor: string;
}

// ── Body Part Positions for Walking / Back / Sitting / Typing ──

/** Extended body part map for directional + walking animations */
interface HumanBodyParts {
  /** Grid row range for face area (eyes, nose, mouth) [startRow, endRow] */
  faceRows: [number, number];
  /** Grid col range for face area [startCol, endCol] */
  faceCols: [number, number];
  /** Hair color to cover face for back view */
  hairColor: string;
  /** Skin color */
  skinColor: string;
  /** Left leg area: [startRow, endRow, startCol, endCol] */
  leftLeg: [number, number, number, number];
  /** Right leg area: [startRow, endRow, startCol, endCol] */
  rightLeg: [number, number, number, number];
  /** Pant/trouser color */
  pantColor: string;
  /** Pant shadow color */
  pantShadow: string;
  /** Shoe color */
  shoeColor: string;
  /** Left arm area: [startRow, endRow, startCol, endCol] */
  leftArm: [number, number, number, number];
  /** Right arm area: [startRow, endRow, startCol, endCol] */
  rightArm: [number, number, number, number];
  /** Top/shirt color for arm area */
  topColor: string;
}

/** Body part positions for each human character.
 *  Positions are in grid row/col (0-indexed, top-to-bottom rows).
 *  Derived from manual inspection of each character's ASCII grid. */
const HUMAN_BODY_PARTS: Partial<Record<CharacterType, HumanBodyParts>> = {
  architect: {
    faceRows: [10, 20], faceCols: [11, 23],
    hairColor: 'rgb(38, 28, 20)', skinColor: SKIN_DARK,
    leftLeg: [38, 52, 11, 14], rightLeg: [38, 52, 15, 19],
    pantColor: 'rgb(45, 45, 55)', pantShadow: 'rgb(35, 35, 45)',
    shoeColor: 'rgb(30, 30, 35)',
    leftArm: [29, 34, 8, 10], rightArm: [29, 34, 22, 24],
    topColor: 'rgb(51, 51, 64)',
  },
  leadEngineer: {
    faceRows: [8, 18], faceCols: [10, 24],
    hairColor: 'rgb(100, 70, 42)', skinColor: SKIN_LIGHT,
    leftLeg: [36, 50, 10, 13], rightLeg: [36, 50, 14, 18],
    pantColor: 'rgb(70, 90, 130)', pantShadow: 'rgb(55, 72, 108)',
    shoeColor: 'rgb(60, 60, 65)',
    leftArm: [28, 33, 6, 8], rightArm: [28, 33, 22, 24],
    topColor: 'rgb(64, 140, 217)',
  },
  engManager: {
    faceRows: [6, 19], faceCols: [11, 23],
    hairColor: 'rgb(30, 25, 22)', skinColor: SKIN_MED,
    leftLeg: [34, 49, 11, 14], rightLeg: [34, 49, 15, 19],
    pantColor: 'rgb(45, 45, 55)', pantShadow: 'rgb(35, 35, 45)',
    shoeColor: 'rgb(30, 30, 35)',
    leftArm: [27, 33, 8, 10], rightArm: [27, 33, 22, 24],
    topColor: 'rgb(77, 128, 179)',
  },
  backendEngineer: {
    faceRows: [6, 18], faceCols: [10, 23],
    hairColor: 'rgb(28, 22, 18)', skinColor: SKIN_TAN,
    leftLeg: [35, 51, 11, 14], rightLeg: [35, 51, 15, 18],
    pantColor: 'rgb(55, 60, 80)', pantShadow: 'rgb(42, 46, 65)',
    shoeColor: 'rgb(55, 55, 60)',
    leftArm: [27, 33, 8, 10], rightArm: [27, 33, 22, 24],
    topColor: 'rgb(46, 102, 64)',
  },
  frontendEngineer: {
    faceRows: [6, 19], faceCols: [9, 24],
    hairColor: 'rgb(55, 40, 35)', skinColor: SKIN_LIGHT,
    leftLeg: [35, 50, 11, 14], rightLeg: [35, 50, 15, 18],
    pantColor: 'rgb(70, 90, 130)', pantShadow: 'rgb(55, 72, 108)',
    shoeColor: 'rgb(230, 120, 170)',
    leftArm: [27, 33, 8, 10], rightArm: [27, 33, 22, 24],
    topColor: 'rgb(217, 115, 166)',
  },
  uxDesigner: {
    faceRows: [7, 22], faceCols: [10, 26],
    hairColor: 'rgb(38, 28, 22)', skinColor: SKIN_MED,
    leftLeg: [36, 53, 10, 14], rightLeg: [36, 53, 16, 20],
    pantColor: 'rgb(45, 45, 55)', pantShadow: 'rgb(32, 32, 40)',
    shoeColor: 'rgb(50, 40, 35)',
    leftArm: [28, 35, 8, 10], rightArm: [28, 35, 24, 26],
    topColor: 'rgb(64, 64, 77)',
  },
  projectManager: {
    faceRows: [7, 19], faceCols: [10, 24],
    hairColor: 'rgb(220, 190, 120)', skinColor: SKIN_LIGHT,
    leftLeg: [35, 50, 10, 14], rightLeg: [35, 50, 16, 20],
    pantColor: 'rgb(50, 50, 60)', pantShadow: 'rgb(35, 35, 44)',
    shoeColor: 'rgb(45, 40, 50)',
    leftArm: [27, 33, 8, 10], rightArm: [27, 33, 24, 26],
    topColor: 'rgb(51, 64, 89)',
  },
  productManager: {
    faceRows: [6, 18], faceCols: [10, 24],
    hairColor: 'rgb(26, 20, 16)', skinColor: SKIN_DARK,
    leftLeg: [32, 49, 10, 14], rightLeg: [32, 49, 16, 20],
    pantColor: 'rgb(195, 175, 140)', pantShadow: 'rgb(165, 148, 115)',
    shoeColor: 'rgb(60, 62, 68)',
    leftArm: [26, 32, 8, 10], rightArm: [26, 32, 22, 24],
    topColor: 'rgb(64, 128, 153)',
  },
  devops: {
    faceRows: [7, 21], faceCols: [10, 24],
    hairColor: 'rgb(190, 100, 40)', skinColor: SKIN_LIGHT,
    leftLeg: [34, 50, 10, 14], rightLeg: [34, 50, 16, 20],
    pantColor: 'rgb(70, 90, 130)', pantShadow: 'rgb(50, 66, 100)',
    shoeColor: 'rgb(65, 50, 35)',
    leftArm: [27, 33, 8, 10], rightArm: [27, 33, 24, 26],
    topColor: 'rgb(153, 64, 51)',
  },
  databaseGuru: {
    faceRows: [16, 28], faceCols: [10, 24],
    hairColor: 'rgb(30, 24, 20)', skinColor: SKIN_MED,
    leftLeg: [40, 52, 10, 14], rightLeg: [40, 52, 16, 20],
    pantColor: 'rgb(51, 38, 77)', pantShadow: 'rgb(36, 26, 56)',
    shoeColor: 'rgb(40, 30, 45)',
    leftArm: [34, 39, 8, 10], rightArm: [34, 39, 24, 26],
    topColor: 'rgb(51, 38, 77)',
  },
};

/** Dog body parts for walking animation */
interface DogBodyParts {
  /** Grid dimensions */
  gridSize: [number, number];
  /** Front-left leg area [startRow, endRow, startCol, endCol] */
  frontLeftLeg: [number, number, number, number];
  /** Front-right leg area (second front leg, may overlap) */
  frontRightLeg: [number, number, number, number];
  /** Back-left leg area */
  backLeftLeg: [number, number, number, number];
  /** Back-right leg area */
  backRightLeg: [number, number, number, number];
  /** Leg color */
  legColor: string;
  /** Paw color */
  pawColor: string;
  /** Body color (for clearing) */
  bodyColor: string;
}

const DOG_BODY_PARTS: Partial<Record<CharacterType, DogBodyParts>> = {
  dachshund: {
    gridSize: [33, 60],
    // Stubby legs at rows 19-20, back at cols 18-19, front at cols 39-40
    frontLeftLeg: [19, 20, 39, 39], frontRightLeg: [19, 20, 40, 40],
    backLeftLeg: [19, 20, 18, 18], backRightLeg: [19, 20, 19, 19],
    legColor: 'rgb(184, 107, 46)', pawColor: 'rgb(140, 77, 31)',
    bodyColor: 'rgb(184, 107, 46)',
  },
  cattleDog: {
    gridSize: [33, 61],
    // 3 legs: rows 24-27, back L at col 8, front LL at cols 22-23
    frontLeftLeg: [24, 27, 22, 22], frontRightLeg: [24, 27, 23, 23],
    backLeftLeg: [24, 27, 8, 8], backRightLeg: [24, 27, 8, 8], // only 1 back leg
    legColor: 'rgb(210, 170, 120)', pawColor: 'rgb(120, 80, 50)',
    bodyColor: 'rgb(179, 89, 51)',
  },
  schnauzerBlack: {
    gridSize: [33, 61],
    // Legs rows 22-25, at cols 8-9 and 22-23
    frontLeftLeg: [22, 25, 22, 22], frontRightLeg: [22, 25, 23, 23],
    backLeftLeg: [22, 25, 8, 8], backRightLeg: [22, 25, 9, 9],
    legColor: 'rgb(100, 100, 115)', pawColor: 'rgb(20, 20, 26)',
    bodyColor: 'rgb(36, 36, 44)',
  },
  schnauzerPepper: {
    gridSize: [33, 61],
    // Same layout as black schnauzer
    frontLeftLeg: [22, 25, 22, 22], frontRightLeg: [22, 25, 23, 23],
    backLeftLeg: [22, 25, 8, 8], backRightLeg: [22, 25, 9, 9],
    legColor: 'rgb(150, 150, 158)', pawColor: 'rgb(56, 56, 64)',
    bodyColor: 'rgb(97, 97, 107)',
  },
};

interface DogFeatures {
  gridSize: [number, number];
  /** Tail tip position (row, col) */
  tailTip: [number, number];
  /** Tail base position (row, col) — for connecting wag */
  tailBase: [number, number];
  /** Tail color */
  tailColor: string;
  /** Background color to erase old tail position */
  bgColor: string;
  /** Ear positions — left and right (row, col) */
  earLeft: [number, number];
  earRight: [number, number];
  /** Ear color */
  earColor: string;
}

const HUMAN_FEATURES: Partial<Record<CharacterType, HumanFeatures>> = {
  architect:        { gridSize: [60, 42], leftHand: [30, 8],  rightHand: [30, 24], handColor: SKIN_DARK,  bodyColor: 'rgb(51, 51, 64)' },
  leadEngineer:     { gridSize: [60, 42], leftHand: [29, 6],  rightHand: [29, 24], handColor: SKIN_LIGHT, bodyColor: 'rgb(64, 140, 217)' },
  engManager:       { gridSize: [60, 42], leftHand: [29, 8],  rightHand: [29, 24], handColor: SKIN_MED,   bodyColor: 'rgb(77, 128, 179)' },
  backendEngineer:  { gridSize: [60, 42], leftHand: [29, 8],  rightHand: [29, 23], handColor: SKIN_TAN,   bodyColor: 'rgb(46, 102, 64)' },
  frontendEngineer: { gridSize: [60, 42], leftHand: [29, 8],  rightHand: [29, 24], handColor: SKIN_LIGHT, bodyColor: 'rgb(80, 60, 100)' },
  uxDesigner:       { gridSize: [60, 42], leftHand: [29, 8],  rightHand: [29, 24], handColor: SKIN_MED,   bodyColor: 'rgb(64, 64, 77)' },
  projectManager:   { gridSize: [60, 42], leftHand: [29, 8],  rightHand: [29, 24], handColor: SKIN_LIGHT, bodyColor: 'rgb(51, 64, 89)' },
  productManager:   { gridSize: [60, 42], leftHand: [29, 8],  rightHand: [29, 24], handColor: SKIN_DARK,  bodyColor: 'rgb(64, 128, 153)' },
  devops:           { gridSize: [60, 42], leftHand: [29, 8],  rightHand: [29, 24], handColor: SKIN_LIGHT, bodyColor: 'rgb(153, 64, 51)' },
  databaseGuru:     { gridSize: [60, 42], leftHand: [29, 8],  rightHand: [29, 24], handColor: SKIN_MED,   bodyColor: 'rgb(102, 51, 153)' },
};

const DOG_FEATURES: Partial<Record<CharacterType, DogFeatures>> = {
  dachshund: {
    gridSize: [33, 60],
    tailTip: [11, 14], tailBase: [13, 16],
    tailColor: 'rgb(140, 77, 31)', bgColor: 'rgb(0, 0, 0)',
    earLeft: [8, 43], earRight: [9, 42],
    earColor: 'rgb(140, 77, 31)',
  },
  cattleDog: {
    gridSize: [33, 61],
    tailTip: [15, 3], tailBase: [17, 4],
    tailColor: 'rgb(179, 89, 51)', bgColor: 'rgb(0, 0, 0)',
    earLeft: [1, 20], earRight: [1, 24],
    earColor: 'rgb(179, 89, 51)',
  },
  schnauzerBlack: {
    gridSize: [33, 61],
    tailTip: [14, 3], tailBase: [16, 4],
    tailColor: 'rgb(36, 36, 44)', bgColor: 'rgb(0, 0, 0)',
    earLeft: [1, 20], earRight: [2, 19],
    earColor: 'rgb(36, 36, 44)',
  },
  schnauzerPepper: {
    gridSize: [33, 61],
    tailTip: [14, 3], tailBase: [16, 4],
    tailColor: 'rgb(97, 97, 107)', bgColor: 'rgb(0, 0, 0)',
    earLeft: [1, 20], earRight: [2, 19],
    earColor: 'rgb(97, 97, 107)',
  },
};

/**
 * Convert a grid (row, col) position to canvas pixel coordinates
 * relative to the sprite's center point (x, y).
 * The sprite uses Y-up internally but is flipped when rendered.
 */
function gridToCanvas(
  row: number, col: number,
  gridRows: number, gridCols: number,
  spriteW: number, spriteH: number,
): { cx: number; cy: number } {
  const gcx = Math.floor(gridCols / 2);
  const gcy = Math.floor(gridRows / 2);
  // Grid coordinates (Y-up)
  const gx = col - gcx;
  const gy = (gridRows - 1 - row) - gcy;
  // In sprite bitmap
  // We need minX/minY but can approximate: sprite is tightly bounded,
  // so minX ≈ -(spriteW/2) in grid coords, minY ≈ -(spriteH/2)
  // Actually px = gx - minX, py = gy - minY
  // After flip: canvasX = -spriteW/2 + px, canvasY = spriteH/2 - py - 1
  // Since minX ≈ first non-empty col - gcx and similar, we approximate:
  // The sprite canvas is exactly spriteW x spriteH, pixel (0,0) is the top-left
  // of the bounding box. We know the grid center maps to roughly sprite center.
  // More precisely: canvasRelX ≈ gx (since sprite center ≈ grid center)
  //                 canvasRelY ≈ -gy (flipped)
  return { cx: gx, cy: -gy };
}

/**
 * Apply subtle human idle overlay animations.
 * Called after the base sprite is drawn. Draws small pixel patches
 * over the cached sprite to create weight shift and arm fidget.
 */
function applyHumanIdleOverlay(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number, y: number,
  time: number,
): void {
  const features = HUMAN_FEATURES[type];
  if (!features) return;

  // Weight shift: very subtle horizontal sway, ~4s cycle, ±0.5px
  const swayPhase = (time % 4200) / 4200;
  const sway = Math.sin(swayPhase * Math.PI * 2) * 0.5;

  // Apply sway by shifting the whole sprite slightly — we do this by
  // drawing a 1px-wide strip of background on one side and the sprite edge
  // color on the other. But actually, since we're just overlaying, the
  // simplest effective approach is to NOT shift the sprite but instead
  // create the illusion with a subtle shadow/highlight shift.
  // We'll skip the sway for now as it requires sub-pixel rendering.

  // Arm fidget: every 8-12s, one hand shifts 1px for ~400ms
  // Use a pseudo-random period based on character type hash
  const typeHash = type.charCodeAt(0) + type.charCodeAt(1) * 7;
  const fidgetPeriod = 8000 + (typeHash % 4000); // 8-12s
  const fidgetPhase = time % fidgetPeriod;
  const isFidgeting = fidgetPhase < 400;

  if (isFidgeting) {
    const sprite = getCachedSprite(type);
    const [fRows, fCols] = features.gridSize;
    // Alternate which hand fidgets
    const useLeft = Math.floor(time / fidgetPeriod) % 2 === 0;
    const hand = useLeft ? features.leftHand : features.rightHand;
    const pos = gridToCanvas(hand[0], hand[1], fRows, fCols, sprite.width, sprite.height);

    // Draw a small colored patch 1px above the hand position (hand moves up slightly)
    ctx.fillStyle = features.handColor;
    ctx.fillRect(x + pos.cx, y + pos.cy - 1, 2, 1);
    // Cover old position with body color
    ctx.fillStyle = features.bodyColor;
    ctx.fillRect(x + pos.cx, y + pos.cy + 1, 2, 1);
  }

  // Weight shift via very subtle body lean — shift a column of pixels
  if (Math.abs(sway) > 0.3) {
    // No-op: sub-pixel sway not visible at 1px scale. The breathing
    // and blink already provide enough human idle variety.
  }
}

/**
 * Apply subtle dog idle overlay animations.
 * Tail wag, ear twitch, drawn as pixel patches over the cached sprite.
 */
function applyDogIdleOverlay(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number, y: number,
  time: number,
): void {
  const features = DOG_FEATURES[type];
  if (!features) return;

  const sprite = getCachedSprite(type);
  const [fRows, fCols] = features.gridSize;

  // Tail wag: oscillate tail tip position, ~1.5s cycle
  const wagPhase = (time % 1500) / 1500;
  const wagOffset = Math.round(Math.sin(wagPhase * Math.PI * 2) * 2); // ±2px

  const tailTip = gridToCanvas(features.tailTip[0], features.tailTip[1], fRows, fCols, sprite.width, sprite.height);
  const tailBase = gridToCanvas(features.tailBase[0], features.tailBase[1], fRows, fCols, sprite.width, sprite.height);

  // Clear the tail tip area and redraw offset
  // Erase old tail tip (draw transparent/background)
  ctx.clearRect(x + tailTip.cx - 2, y + tailTip.cy - 1, 5, 3);
  // Draw wagging tail tip at new position
  ctx.fillStyle = features.tailColor;
  ctx.fillRect(x + tailTip.cx + wagOffset, y + tailTip.cy, 2, 1);
  ctx.fillRect(x + tailTip.cx + wagOffset, y + tailTip.cy - 1, 2, 1);

  // Also shift the tail mid-section slightly
  const midWag = Math.round(wagOffset * 0.5);
  ctx.clearRect(x + tailBase.cx - 2, y + tailBase.cy - 1, 5, 3);
  ctx.fillStyle = features.tailColor;
  ctx.fillRect(x + tailBase.cx + midWag, y + tailBase.cy, 2, 1);

  // Ear twitch: quick shift every 5-8s, 200ms duration
  const typeHash = type.charCodeAt(0) + type.charCodeAt(2) * 11;
  const earPeriod = 5000 + (typeHash % 3000); // 5-8s
  const earPhase = time % earPeriod;
  const isEarTwitch = earPhase < 200;

  if (isEarTwitch) {
    const earL = gridToCanvas(features.earLeft[0], features.earLeft[1], fRows, fCols, sprite.width, sprite.height);
    const earR = gridToCanvas(features.earRight[0], features.earRight[1], fRows, fCols, sprite.width, sprite.height);

    // Twitch ears up by 1px
    ctx.fillStyle = features.earColor;
    ctx.fillRect(x + earL.cx, y + earL.cy - 1, 3, 1);
    ctx.fillRect(x + earR.cx, y + earR.cy - 1, 3, 1);
  }
}

// ── Walking Animation Overlays ────────────────────────────────
// Draw leg/arm movement on top of the cached sprite when isMoving=true.
// walkPhase is 0-1 cycling at ~3Hz from the engine.

/**
 * Apply human walking animation overlay.
 * Alternates legs and arms based on walkPhase.
 * After the base sprite is drawn (Y-flipped), overlays are in normal canvas space.
 */
function applyHumanWalkOverlay(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number, y: number,
  walkPhase: number,
): void {
  const parts = HUMAN_BODY_PARTS[type];
  if (!parts) return;

  const sprite = getCachedSprite(type);
  const [gridRows, gridCols] = [parts.leftLeg[0], parts.leftLeg[0]]; // just need gridSize from HUMAN_FEATURES
  const features = HUMAN_FEATURES[type];
  if (!features) return;
  const [fRows, fCols] = features.gridSize;

  // Phase: sin wave gives smooth leg alternation
  const legStep = Math.sin(walkPhase * Math.PI * 2);
  const legShift = Math.round(legStep * 2); // ±2px vertical shift

  // Convert leg positions to canvas coordinates
  // Left leg: middle row of leg area
  const leftLegMidRow = Math.floor((parts.leftLeg[0] + parts.leftLeg[1]) / 2);
  const leftLegMidCol = Math.floor((parts.leftLeg[2] + parts.leftLeg[3]) / 2);
  const rightLegMidRow = Math.floor((parts.rightLeg[0] + parts.rightLeg[1]) / 2);
  const rightLegMidCol = Math.floor((parts.rightLeg[2] + parts.rightLeg[3]) / 2);

  const leftPos = gridToCanvas(leftLegMidRow, leftLegMidCol, fRows, fCols, sprite.width, sprite.height);
  const rightPos = gridToCanvas(rightLegMidRow, rightLegMidCol, fRows, fCols, sprite.width, sprite.height);

  // Leg width and height in pixels (approximate from grid area)
  const legW = parts.leftLeg[3] - parts.leftLeg[2] + 1;
  const legH = 4; // visible shift area

  // Left leg shifts down when legShift > 0, right leg shifts up
  // Draw pant-colored rectangles to extend/retract legs
  if (legShift > 0) {
    // Left leg forward (extends down)
    ctx.fillStyle = parts.pantColor;
    ctx.fillRect(x + leftPos.cx - 1, y + leftPos.cy + legH, legW, legShift);
    // Right leg back (cover bottom of right leg)
    ctx.fillStyle = parts.pantShadow;
    ctx.fillRect(x + rightPos.cx - 1, y + rightPos.cy + legH - legShift, legW, legShift);
  } else if (legShift < 0) {
    // Right leg forward (extends down)
    ctx.fillStyle = parts.pantColor;
    ctx.fillRect(x + rightPos.cx - 1, y + rightPos.cy + legH, legW, -legShift);
    // Left leg back
    ctx.fillStyle = parts.pantShadow;
    ctx.fillRect(x + leftPos.cx - 1, y + leftPos.cy + legH + legShift, legW, -legShift);
  }

  // Arm swing: opposite to legs, smaller shift (±1px)
  const armShift = Math.round(legStep * 1);
  if (armShift !== 0) {
    const leftArmRow = Math.floor((parts.leftArm[0] + parts.leftArm[1]) / 2);
    const leftArmCol = Math.floor((parts.leftArm[2] + parts.leftArm[3]) / 2);
    const rightArmRow = Math.floor((parts.rightArm[0] + parts.rightArm[1]) / 2);
    const rightArmCol = Math.floor((parts.rightArm[2] + parts.rightArm[3]) / 2);

    const leftArmPos = gridToCanvas(leftArmRow, leftArmCol, fRows, fCols, sprite.width, sprite.height);
    const rightArmPos = gridToCanvas(rightArmRow, rightArmCol, fRows, fCols, sprite.width, sprite.height);

    // Arms swing opposite to legs
    ctx.fillStyle = parts.skinColor;
    if (armShift > 0) {
      // Left arm back (up in canvas = negative Y), right arm forward (down)
      ctx.fillRect(x + leftArmPos.cx, y + leftArmPos.cy - 1, 2, 1);
      ctx.fillStyle = parts.topColor;
      ctx.fillRect(x + leftArmPos.cx, y + leftArmPos.cy + 2, 2, 1);
      ctx.fillStyle = parts.skinColor;
      ctx.fillRect(x + rightArmPos.cx, y + rightArmPos.cy + 2, 2, 1);
    } else {
      ctx.fillRect(x + rightArmPos.cx, y + rightArmPos.cy - 1, 2, 1);
      ctx.fillStyle = parts.topColor;
      ctx.fillRect(x + rightArmPos.cx, y + rightArmPos.cy + 2, 2, 1);
      ctx.fillStyle = parts.skinColor;
      ctx.fillRect(x + leftArmPos.cx, y + leftArmPos.cy + 2, 2, 1);
    }
  }
}

/**
 * Apply dog walking (trot) animation overlay.
 * Diagonal pairs move together: front-left + back-right, then front-right + back-left.
 */
function applyDogWalkOverlay(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number, y: number,
  walkPhase: number,
): void {
  const parts = DOG_BODY_PARTS[type];
  const features = DOG_FEATURES[type];
  if (!parts || !features) return;

  const sprite = getCachedSprite(type);
  const [fRows, fCols] = features.gridSize;

  const trotStep = Math.sin(walkPhase * Math.PI * 2);
  const legShift = Math.round(trotStep * 2); // ±2px forward/back

  // Helper to get canvas position for a leg area center
  const legPos = (leg: [number, number, number, number]) => {
    const midRow = Math.floor((leg[0] + leg[1]) / 2);
    const midCol = Math.floor((leg[2] + leg[3]) / 2);
    return gridToCanvas(midRow, midCol, fRows, fCols, sprite.width, sprite.height);
  };

  const fl = legPos(parts.frontLeftLeg);
  const fr = legPos(parts.frontRightLeg);
  const bl = legPos(parts.backLeftLeg);
  const br = legPos(parts.backRightLeg);
  const legW = 2;
  const legH = 3;

  // Diagonal pair 1: front-left + back-right shift forward
  // Diagonal pair 2: front-right + back-left shift backward
  // "Forward" for a side-view dog is horizontal shift
  ctx.fillStyle = parts.legColor;
  if (legShift > 0) {
    // Pair 1 forward
    ctx.fillRect(x + fl.cx + legShift, y + fl.cy, legW, legH);
    ctx.fillRect(x + br.cx + legShift, y + br.cy, legW, legH);
    // Pair 2 back
    ctx.fillStyle = parts.pawColor;
    ctx.fillRect(x + fr.cx - legShift, y + fr.cy + legH - 1, legW, 1);
    ctx.fillRect(x + bl.cx - legShift, y + bl.cy + legH - 1, legW, 1);
  } else if (legShift < 0) {
    // Pair 2 forward
    ctx.fillRect(x + fr.cx - legShift, y + fr.cy, legW, legH);
    ctx.fillRect(x + bl.cx - legShift, y + bl.cy, legW, legH);
    // Pair 1 back
    ctx.fillStyle = parts.pawColor;
    ctx.fillRect(x + fl.cx + legShift, y + fl.cy + legH - 1, legW, 1);
    ctx.fillRect(x + br.cx + legShift, y + br.cy + legH - 1, legW, 1);
  }

  // Ears bounce slightly on each step (1px up at peak)
  const earBounce = Math.abs(trotStep) > 0.7 ? 1 : 0;
  if (earBounce > 0) {
    const earL = gridToCanvas(features.earLeft[0], features.earLeft[1], fRows, fCols, sprite.width, sprite.height);
    const earR = gridToCanvas(features.earRight[0], features.earRight[1], fRows, fCols, sprite.width, sprite.height);
    ctx.fillStyle = features.earColor;
    ctx.fillRect(x + earL.cx, y + earL.cy - 1, 3, 1);
    ctx.fillRect(x + earR.cx, y + earR.cy - 1, 3, 1);
  }
}

// ── Back-Facing Overlay (facing='up') ────────────────────────
// Draw hair color over the face area to show back of head.

function applyBackFacingOverlay(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number, y: number,
): void {
  const parts = HUMAN_BODY_PARTS[type];
  const features = HUMAN_FEATURES[type];
  if (!parts || !features) return;

  const sprite = getCachedSprite(type);
  const [fRows, fCols] = features.gridSize;

  // Cover the face area with hair color
  const faceTopLeft = gridToCanvas(parts.faceRows[0], parts.faceCols[0], fRows, fCols, sprite.width, sprite.height);
  const faceBottomRight = gridToCanvas(parts.faceRows[1], parts.faceCols[1], fRows, fCols, sprite.width, sprite.height);

  // gridToCanvas returns cx, cy relative to sprite center
  // faceRows[0] is top row (smaller number = higher in grid = higher on screen after flip)
  // After Y-flip: top row -> lower cy value (more negative / higher on screen)
  const faceX = x + Math.min(faceTopLeft.cx, faceBottomRight.cx);
  const faceY = y + Math.min(faceTopLeft.cy, faceBottomRight.cy);
  const faceW = Math.abs(faceBottomRight.cx - faceTopLeft.cx) + 1;
  const faceH = Math.abs(faceBottomRight.cy - faceTopLeft.cy) + 1;

  ctx.fillStyle = parts.hairColor;
  ctx.fillRect(faceX, faceY, faceW, faceH);
}

// ── Sitting Pose Overlay ─────────────────────────────────────
// When agent is at a desk/couch/bean bag, modify lower body for seated look.

/** Activities that indicate a sitting pose */
const SITTING_ACTIVITIES = [
  'desk', 'couch', 'bean bag', 'Watching TV', 'Playing video games',
  'Napping', 'Planning at whiteboard',
];

function isSittingActivity(activity: string | null | undefined): boolean {
  if (!activity) return false;
  const lower = activity.toLowerCase();
  return SITTING_ACTIVITIES.some(s => lower.includes(s.toLowerCase()));
}

/**
 * Apply sitting pose overlay — shorten visible legs and draw bent-knee effect.
 */
function applySittingOverlay(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number, y: number,
): void {
  const parts = HUMAN_BODY_PARTS[type];
  const features = HUMAN_FEATURES[type];
  if (!parts || !features) return;

  const sprite = getCachedSprite(type);
  const [fRows, fCols] = features.gridSize;

  // Clear the lower half of legs (below knee) and redraw shorter
  // Knee is roughly midpoint of leg area
  const kneeRow = Math.floor((parts.leftLeg[0] + parts.leftLeg[1]) / 2) + 2;
  const legBottomRow = parts.leftLeg[1];

  // Convert knee and bottom positions
  const kneeLeft = gridToCanvas(kneeRow, parts.leftLeg[2], fRows, fCols, sprite.width, sprite.height);
  const kneeRight = gridToCanvas(kneeRow, parts.rightLeg[2], fRows, fCols, sprite.width, sprite.height);
  const bottomLeft = gridToCanvas(legBottomRow, parts.leftLeg[2], fRows, fCols, sprite.width, sprite.height);
  const bottomRight = gridToCanvas(legBottomRow, parts.rightLeg[2], fRows, fCols, sprite.width, sprite.height);

  const legW = parts.leftLeg[3] - parts.leftLeg[2] + 1;
  // Clear lower legs (from knee to bottom)
  const clearY = Math.min(kneeLeft.cy, bottomLeft.cy);
  const clearH = Math.abs(bottomLeft.cy - kneeLeft.cy) + 2;

  // Clear both legs below knee
  ctx.clearRect(x + kneeLeft.cx - 1, y + clearY, legW + 2, clearH);
  ctx.clearRect(x + kneeRight.cx - 1, y + clearY, legW + 2, clearH);

  // Draw bent legs extending horizontally (forward) from knee
  ctx.fillStyle = parts.pantColor;
  // Left leg bends forward (horizontal bar from knee)
  ctx.fillRect(x + kneeLeft.cx - 1, y + kneeLeft.cy, legW + 3, 3);
  // Right leg bends forward
  ctx.fillRect(x + kneeRight.cx - 1, y + kneeRight.cy, legW + 3, 3);

  // Small shoe at end of bent leg
  ctx.fillStyle = parts.shoeColor;
  ctx.fillRect(x + kneeLeft.cx + legW + 1, y + kneeLeft.cy + 1, 2, 2);
  ctx.fillRect(x + kneeRight.cx + legW + 1, y + kneeRight.cy + 1, 2, 2);
}

// ── Typing Animation Overlay ─────────────────────────────────
// Rapid hand movement when animation type is 'work-shake'.

function applyTypingOverlay(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number, y: number,
  time: number,
): void {
  const parts = HUMAN_BODY_PARTS[type];
  const features = HUMAN_FEATURES[type];
  if (!parts || !features) return;

  const sprite = getCachedSprite(type);
  const [fRows, fCols] = features.gridSize;

  // Alternate hand positions every ~200ms
  const typingPhase = Math.floor(time / 200) % 2;

  // Get hand positions from the existing features
  const leftHandPos = gridToCanvas(features.leftHand[0], features.leftHand[1], fRows, fCols, sprite.width, sprite.height);
  const rightHandPos = gridToCanvas(features.rightHand[0], features.rightHand[1], fRows, fCols, sprite.width, sprite.height);

  // Typing: hands alternate up/down 1px rapidly
  ctx.fillStyle = features.handColor;
  if (typingPhase === 0) {
    ctx.fillRect(x + leftHandPos.cx, y + leftHandPos.cy - 1, 2, 1);
    ctx.fillRect(x + rightHandPos.cx, y + rightHandPos.cy + 1, 2, 1);
  } else {
    ctx.fillRect(x + leftHandPos.cx, y + leftHandPos.cy + 1, 2, 1);
    ctx.fillRect(x + rightHandPos.cx, y + rightHandPos.cy - 1, 2, 1);
  }

  // Cover the original hand positions with body color to complete the shift illusion
  ctx.fillStyle = features.bodyColor;
  if (typingPhase === 0) {
    ctx.fillRect(x + leftHandPos.cx, y + leftHandPos.cy + 1, 2, 1);
    ctx.fillRect(x + rightHandPos.cx, y + rightHandPos.cy - 1, 2, 1);
  } else {
    ctx.fillRect(x + leftHandPos.cx, y + leftHandPos.cy - 1, 2, 1);
    ctx.fillRect(x + rightHandPos.cx, y + rightHandPos.cy + 1, 2, 1);
  }
}

/** Get the correct sprite for a character at a given time (normal, blink, or writing). */
export function getCharacterSprite(type: CharacterType, time?: number): CachedSprite {
  if (time != null) {
    const { isBlinking, isWriting } = getIdleAnimation(time);

    // Writing animation — writing pose overrides blink (no creatures have this yet)
    if (isWriting) {
      const writing = getCachedWritingSprite(type);
      if (writing) return writing;
    }

    if (isBlinking && !isWriting) {
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
 * Render a character with idle animation (breathing + blink + overlays).
 * Pass Date.now() or performance.now() for time.
 *
 * Idle animations are rendered as pixel-level overlays on top of the
 * cached sprite — no full re-render needed. Humans get weight shifting
 * and arm fidgets; dogs get tail wags and ear twitches.
 */
export function renderCharacterAnimated(
  ctx: CanvasRenderingContext2D,
  type: CharacterType,
  x: number,
  y: number,
  time: number,
  alpha: number = 1,
  facing: FacingDirection = 'down',
  isMoving: boolean = false,
  walkPhase: number = 0,
  idleActivity?: string | null,
): void {
  const { breathOffset, isBlinking, isWriting } = getIdleAnimation(time);
  const isDog = !!DOG_FEATURES[type];
  const isWorkingAtDesk = idleActivity && isSittingActivity(idleActivity) && !isMoving;

  // Breathing only when idle (not moving)
  const activeBreathOffset = isMoving ? 0 : breathOffset;

  // Pick sprite variant (blink / normal)
  let sprite: CachedSprite;
  if (!isMoving && isWriting) {
    sprite = getCachedWritingSprite(type) ?? getCachedSprite(type);
  } else if (!isMoving && isBlinking && facing === 'down') {
    sprite = getCachedBlinkSprite(type) ?? getCachedSprite(type);
  } else {
    sprite = getCachedSprite(type);
  }

  if (alpha < 1) {
    ctx.save();
    ctx.globalAlpha = alpha;
  }

  // ── Draw base sprite ──
  ctx.save();
  ctx.translate(x, y - activeBreathOffset);

  // Side-facing: mirror for left/right
  if (facing === 'left') {
    // Mirror horizontally — flip around the center point
    ctx.scale(-1, -1); // flip both X (mirror) and Y (SpriteKit→Canvas)
  } else if (facing === 'right') {
    // Normal X, flip Y
    ctx.scale(1, -1);
  } else {
    // Front (down) or back (up) — same base sprite orientation
    ctx.scale(1, -1);
  }

  ctx.drawImage(sprite.canvas, -sprite.width / 2, -sprite.height / 2);
  ctx.restore();

  // ── Effective draw position for overlays ──
  const drawY = y - activeBreathOffset;

  // ── Back-facing overlay (facing='up') ──
  // Covers face with hair to show back of head
  if (facing === 'up' && !isDog) {
    applyBackFacingOverlay(ctx, type, x, drawY);
  }

  // ── Walking animation ──
  if (isMoving) {
    if (isDog) {
      applyDogWalkOverlay(ctx, type, x, drawY, walkPhase);
    } else {
      applyHumanWalkOverlay(ctx, type, x, drawY, walkPhase);
    }
  }

  // ── Sitting pose (only when not moving, for seated activities) ──
  if (isWorkingAtDesk && !isDog) {
    applySittingOverlay(ctx, type, x, drawY);
  }

  // ── Typing animation (work-shake at desk, facing up) ──
  if (!isMoving && facing === 'up' && !isDog && idleActivity) {
    const lower = idleActivity.toLowerCase();
    if (lower.includes('desk') || lower.includes('working') || lower.includes('coding')) {
      applyTypingOverlay(ctx, type, x, drawY, time);
    }
  }

  // ── Idle overlays (only when not moving and facing front) ──
  if (!isMoving && facing === 'down') {
    if (isDog) {
      applyDogIdleOverlay(ctx, type, x, drawY, time);
    } else {
      applyHumanIdleOverlay(ctx, type, x, drawY, time);
    }
  }

  // ── Dog idle overlays for non-front facing (tail wag still applies) ──
  if (!isMoving && isDog && facing !== 'down') {
    applyDogIdleOverlay(ctx, type, x, drawY, time);
  }

  if (alpha < 1) {
    ctx.restore();
  }
}

/** Get the rendered size of a character sprite for hit testing. */
export function getCharacterSize(type: CharacterType): { width: number; height: number } {
  const sprite = getCachedSprite(type);
  return { width: sprite.width, height: sprite.height };
}
