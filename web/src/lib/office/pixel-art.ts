// Pixel art builder — ported from iOS PixelArtBuilder.swift
// All 9 characters rendered to Canvas via offscreen caching.
// Pixel coordinates from iOS are used directly (auto-centered per character).

import type { CharacterType } from './types';

const PIXEL_SIZE = 2;

// ── Color Palette ────────────────────────────────────────────

// Skin tones
const skin = 'rgb(242, 204, 166)';
const skinShadow = 'rgb(217, 179, 140)';

// Hair
const hairBrown = 'rgb(102, 64, 38)';
const hairBlack = 'rgb(38, 31, 26)';

// Clothing
const hoodieBlue = 'rgb(64, 140, 217)';
const hoodieDark = 'rgb(46, 107, 173)';
const shirtWhite = 'rgb(230, 230, 235)';
const shirtGray = 'rgb(191, 191, 199)';
const tieRed = 'rgb(217, 51, 51)';
const pantsNavy = 'rgb(38, 46, 77)';
const pantsDark = 'rgb(51, 51, 64)';
const shoes = 'rgb(56, 46, 38)';

// Tech
const screenGlow = 'rgb(102, 217, 255)';
const headphoneBlack = 'rgb(31, 31, 38)';

// PM
const pmKhaki = 'rgb(209, 191, 153)';
const pmShirt = 'rgb(89, 153, 204)';
const clipboard = 'rgb(179, 140, 89)';
const clipboardPage = 'rgb(242, 237, 224)';
const boltGray = 'rgb(179, 184, 191)';

// Clown
const clownRed = 'rgb(242, 38, 38)';
const clownYellow = 'rgb(255, 230, 51)';
const clownGreen = 'rgb(51, 217, 102)';
const clownPurple = 'rgb(166, 64, 230)';
const clownOrange = 'rgb(255, 140, 38)';
const clownPink = 'rgb(242, 102, 153)';
const noseRed = 'rgb(242, 51, 51)';
const clownFace = 'rgb(242, 235, 230)';

// Frankenstein
const frankGreen = 'rgb(115, 191, 102)';
const frankDarkGreen = 'rgb(89, 153, 77)';
const stitchBlack = 'rgb(38, 38, 38)';
const frankJacket = 'rgb(64, 56, 51)';

// Dog colors
const dachshundBrown = 'rgb(184, 107, 46)';
const dachshundDark = 'rgb(140, 77, 31)';
const dachshundBelly = 'rgb(217, 153, 89)';

const cattleBlue = 'rgb(102, 128, 166)';
const cattleDarkBlue = 'rgb(77, 97, 128)';
const cattleRed = 'rgb(204, 89, 64)';
const cattleTan = 'rgb(217, 184, 140)';

const schnauzerDark = 'rgb(31, 31, 38)';
const schnauzerBeard = 'rgb(64, 64, 77)';
const pepperLight = 'rgb(140, 140, 148)';
const pepperMid = 'rgb(97, 97, 107)';
const pepperDark = 'rgb(56, 56, 64)';

// Eyes
const eyeWhite = 'rgb(242, 242, 242)';
const eyeBlack = 'rgb(26, 26, 31)';
const dogEye = 'rgb(51, 31, 20)';
const dogNose = 'rgb(26, 20, 15)';

// Hair part line (office worker)
const hairPart = 'rgb(64, 51, 46)';

// ── Pixel Drawing Helpers ────────────────────────────────────

type PixelList = Array<[number, number, string]>;

function px(pixels: PixelList, x: number, y: number, color: string) {
  pixels.push([x, y, color]);
}

function hRun(pixels: PixelList, x: number, y: number, count: number, color: string) {
  for (let i = 0; i < count; i++) pixels.push([x + i, y, color]);
}

function vRun(pixels: PixelList, x: number, y: number, count: number, color: string) {
  for (let i = 0; i < count; i++) pixels.push([x, y + i, color]);
}

function rect(pixels: PixelList, x: number, y: number, w: number, h: number, color: string) {
  for (let row = 0; row < h; row++) {
    for (let col = 0; col < w; col++) {
      pixels.push([x + col, y + row, color]);
    }
  }
}

// ── Character Builders ───────────────────────────────────────

function buildDev(): PixelList {
  const p: PixelList = [];
  const ox = -8, oy = -8;

  // Hair
  hRun(p, ox + 5, oy + 15, 6, hairBrown);
  hRun(p, ox + 4, oy + 14, 8, hairBrown);

  // Head/face
  rect(p, ox + 5, oy + 11, 6, 3, skin);
  px(p, ox + 6, oy + 12, eyeWhite);
  px(p, ox + 7, oy + 12, eyeBlack);
  px(p, ox + 9, oy + 12, eyeWhite);
  px(p, ox + 10, oy + 12, eyeBlack);
  hRun(p, ox + 7, oy + 11, 2, skinShadow);

  // Headphones
  px(p, ox + 4, oy + 13, headphoneBlack);
  px(p, ox + 4, oy + 12, headphoneBlack);
  px(p, ox + 11, oy + 13, headphoneBlack);
  px(p, ox + 11, oy + 12, headphoneBlack);
  hRun(p, ox + 5, oy + 15, 6, headphoneBlack);

  // Hoodie body
  rect(p, ox + 4, oy + 5, 8, 6, hoodieBlue);
  hRun(p, ox + 6, oy + 6, 4, hoodieDark);
  px(p, ox + 7, oy + 10, shirtWhite);
  px(p, ox + 9, oy + 10, shirtWhite);

  // Arms
  vRun(p, ox + 3, oy + 5, 5, hoodieBlue);
  vRun(p, ox + 12, oy + 5, 5, hoodieBlue);
  px(p, ox + 3, oy + 5, skin);
  px(p, ox + 12, oy + 5, skin);

  // Pants
  rect(p, ox + 5, oy + 2, 3, 3, pantsDark);
  rect(p, ox + 8, oy + 2, 3, 3, pantsDark);

  // Shoes
  hRun(p, ox + 4, oy + 1, 4, shoes);
  hRun(p, ox + 8, oy + 1, 4, shoes);

  // Laptop glow
  hRun(p, ox + 6, oy + 7, 4, screenGlow);

  return p;
}

function buildOfficeWorker(): PixelList {
  const p: PixelList = [];
  const ox = -8, oy = -8;

  hRun(p, ox + 5, oy + 15, 6, hairBlack);
  hRun(p, ox + 4, oy + 14, 8, hairBlack);
  px(p, ox + 7, oy + 14, hairPart);

  rect(p, ox + 5, oy + 11, 6, 3, skin);
  px(p, ox + 6, oy + 12, eyeWhite);
  px(p, ox + 7, oy + 12, eyeBlack);
  px(p, ox + 9, oy + 12, eyeWhite);
  px(p, ox + 10, oy + 12, eyeBlack);
  hRun(p, ox + 7, oy + 11, 2, skinShadow);

  rect(p, ox + 4, oy + 5, 8, 6, shirtWhite);
  vRun(p, ox + 8, oy + 5, 6, shirtGray);
  px(p, ox + 8, oy + 10, tieRed);
  px(p, ox + 8, oy + 9, tieRed);
  px(p, ox + 7, oy + 8, tieRed);
  px(p, ox + 8, oy + 8, tieRed);
  px(p, ox + 9, oy + 8, tieRed);
  px(p, ox + 8, oy + 7, tieRed);
  px(p, ox + 8, oy + 6, tieRed);

  vRun(p, ox + 3, oy + 5, 5, shirtWhite);
  vRun(p, ox + 12, oy + 5, 5, shirtWhite);
  px(p, ox + 3, oy + 5, skin);
  px(p, ox + 12, oy + 5, skin);

  rect(p, ox + 5, oy + 2, 3, 3, pantsNavy);
  rect(p, ox + 8, oy + 2, 3, 3, pantsNavy);

  hRun(p, ox + 4, oy + 1, 4, shoes);
  hRun(p, ox + 8, oy + 1, 4, shoes);

  return p;
}

function buildPM(): PixelList {
  const p: PixelList = [];
  const ox = -8, oy = -8;

  hRun(p, ox + 5, oy + 15, 6, hairBrown);
  hRun(p, ox + 4, oy + 14, 8, hairBrown);
  px(p, ox + 4, oy + 13, hairBrown);

  rect(p, ox + 5, oy + 11, 6, 3, skin);
  px(p, ox + 6, oy + 12, eyeWhite);
  px(p, ox + 7, oy + 12, eyeBlack);
  px(p, ox + 9, oy + 12, eyeWhite);
  px(p, ox + 10, oy + 12, eyeBlack);
  px(p, ox + 7, oy + 11, skinShadow);
  px(p, ox + 9, oy + 11, skinShadow);

  rect(p, ox + 4, oy + 5, 8, 6, pmShirt);
  px(p, ox + 6, oy + 10, shirtWhite);
  px(p, ox + 10, oy + 10, shirtWhite);

  vRun(p, ox + 3, oy + 5, 5, pmShirt);
  vRun(p, ox + 12, oy + 5, 5, pmShirt);
  px(p, ox + 3, oy + 5, skin);
  px(p, ox + 12, oy + 5, skin);

  // Clipboard
  rect(p, ox + 1, oy + 5, 2, 4, clipboard);
  rect(p, ox + 1, oy + 6, 2, 2, clipboardPage);
  px(p, ox + 1, oy + 9, boltGray);
  px(p, ox + 2, oy + 9, boltGray);

  rect(p, ox + 5, oy + 2, 3, 3, pmKhaki);
  rect(p, ox + 8, oy + 2, 3, 3, pmKhaki);

  hRun(p, ox + 4, oy + 1, 4, shoes);
  hRun(p, ox + 8, oy + 1, 4, shoes);

  return p;
}

function buildClown(): PixelList {
  const p: PixelList = [];
  const ox = -8, oy = -8;

  // Rainbow hair
  hRun(p, ox + 4, oy + 15, 2, clownRed);
  hRun(p, ox + 6, oy + 15, 2, clownOrange);
  hRun(p, ox + 8, oy + 15, 2, clownYellow);
  hRun(p, ox + 10, oy + 15, 2, clownGreen);
  hRun(p, ox + 3, oy + 14, 2, clownRed);
  hRun(p, ox + 5, oy + 14, 2, clownOrange);
  hRun(p, ox + 7, oy + 14, 2, clownYellow);
  hRun(p, ox + 9, oy + 14, 2, clownGreen);
  hRun(p, ox + 11, oy + 14, 2, clownPurple);
  px(p, ox + 3, oy + 15, clownPurple);
  px(p, ox + 12, oy + 15, clownPurple);

  rect(p, ox + 5, oy + 11, 6, 3, clownFace);
  px(p, ox + 6, oy + 12, eyeBlack);
  px(p, ox + 10, oy + 12, eyeBlack);
  px(p, ox + 7, oy + 12, noseRed);
  px(p, ox + 8, oy + 12, noseRed);
  px(p, ox + 7, oy + 11, noseRed);
  px(p, ox + 8, oy + 11, noseRed);
  px(p, ox + 6, oy + 11, clownRed);
  px(p, ox + 10, oy + 11, clownRed);

  rect(p, ox + 4, oy + 7, 4, 4, clownYellow);
  rect(p, ox + 8, oy + 7, 4, 4, clownPurple);
  rect(p, ox + 4, oy + 5, 4, 2, clownGreen);
  rect(p, ox + 8, oy + 5, 4, 2, clownOrange);
  px(p, ox + 8, oy + 9, clownRed);
  px(p, ox + 8, oy + 7, clownGreen);

  vRun(p, ox + 3, oy + 5, 5, clownPink);
  vRun(p, ox + 12, oy + 5, 5, clownPink);
  px(p, ox + 2, oy + 5, shirtWhite);
  px(p, ox + 3, oy + 5, shirtWhite);
  px(p, ox + 12, oy + 5, shirtWhite);
  px(p, ox + 13, oy + 5, shirtWhite);

  rect(p, ox + 5, oy + 2, 3, 3, clownPurple);
  rect(p, ox + 8, oy + 2, 3, 3, clownYellow);

  hRun(p, ox + 3, oy + 1, 5, clownRed);
  hRun(p, ox + 8, oy + 1, 5, clownRed);

  return p;
}

function buildFrankenstein(): PixelList {
  const p: PixelList = [];
  const ox = -8, oy = -8;

  hRun(p, ox + 4, oy + 15, 8, hairBlack);
  hRun(p, ox + 4, oy + 14, 8, hairBlack);

  rect(p, ox + 4, oy + 11, 8, 3, frankGreen);
  hRun(p, ox + 4, oy + 13, 8, frankDarkGreen);
  px(p, ox + 5, oy + 12, eyeWhite);
  px(p, ox + 6, oy + 12, eyeBlack);
  px(p, ox + 9, oy + 12, eyeBlack);
  px(p, ox + 10, oy + 12, eyeWhite);
  hRun(p, ox + 5, oy + 11, 6, stitchBlack);
  vRun(p, ox + 8, oy + 11, 3, stitchBlack);

  // Neck bolts
  px(p, ox + 3, oy + 12, boltGray);
  px(p, ox + 12, oy + 12, boltGray);
  px(p, ox + 3, oy + 11, boltGray);
  px(p, ox + 12, oy + 11, boltGray);

  rect(p, ox + 3, oy + 5, 10, 6, frankJacket);
  vRun(p, ox + 7, oy + 5, 6, frankDarkGreen);
  vRun(p, ox + 8, oy + 5, 6, frankDarkGreen);

  vRun(p, ox + 2, oy + 5, 5, frankJacket);
  vRun(p, ox + 13, oy + 5, 5, frankJacket);
  px(p, ox + 2, oy + 5, frankGreen);
  px(p, ox + 13, oy + 5, frankGreen);

  rect(p, ox + 4, oy + 2, 4, 3, pantsDark);
  rect(p, ox + 8, oy + 2, 4, 3, pantsDark);

  hRun(p, ox + 3, oy + 1, 5, shoes);
  hRun(p, ox + 8, oy + 1, 5, shoes);

  return p;
}

function buildDachshund(): PixelList {
  const p: PixelList = [];
  const ox = -11, oy = -5;

  // Ears
  vRun(p, ox + 17, oy + 5, 3, dachshundDark);
  vRun(p, ox + 20, oy + 5, 3, dachshundDark);

  // Head
  rect(p, ox + 17, oy + 7, 4, 3, dachshundBrown);
  px(p, ox + 18, oy + 10, dachshundBrown);
  px(p, ox + 19, oy + 10, dachshundBrown);
  px(p, ox + 21, oy + 8, dachshundBrown);
  px(p, ox + 21, oy + 7, dachshundBrown);
  px(p, ox + 22, oy + 8, dogNose);
  px(p, ox + 19, oy + 9, dogEye);

  // Long body
  rect(p, ox + 4, oy + 5, 13, 4, dachshundBrown);
  hRun(p, ox + 5, oy + 5, 11, dachshundBelly);

  // Tail
  px(p, ox + 3, oy + 7, dachshundBrown);
  px(p, ox + 2, oy + 8, dachshundBrown);
  px(p, ox + 2, oy + 9, dachshundDark);

  // Front legs
  vRun(p, ox + 14, oy + 3, 2, dachshundBrown);
  vRun(p, ox + 16, oy + 3, 2, dachshundBrown);
  // Back legs
  vRun(p, ox + 5, oy + 3, 2, dachshundBrown);
  vRun(p, ox + 7, oy + 3, 2, dachshundBrown);

  // Paws
  px(p, ox + 14, oy + 3, dachshundDark);
  px(p, ox + 16, oy + 3, dachshundDark);
  px(p, ox + 5, oy + 3, dachshundDark);
  px(p, ox + 7, oy + 3, dachshundDark);

  return p;
}

function buildCattleDog(): PixelList {
  const p: PixelList = [];
  const ox = -9, oy = -6;

  // Pointed ears
  px(p, ox + 13, oy + 12, cattleBlue);
  px(p, ox + 16, oy + 12, cattleBlue);
  px(p, ox + 13, oy + 11, cattleBlue);
  px(p, ox + 14, oy + 11, cattleBlue);
  px(p, ox + 15, oy + 11, cattleBlue);
  px(p, ox + 16, oy + 11, cattleBlue);

  // Head
  rect(p, ox + 13, oy + 8, 5, 3, cattleBlue);
  px(p, ox + 15, oy + 9, cattleTan);
  px(p, ox + 15, oy + 8, cattleTan);
  px(p, ox + 16, oy + 8, cattleTan);
  px(p, ox + 14, oy + 9, dogEye);
  px(p, ox + 16, oy + 9, dogEye);
  px(p, ox + 17, oy + 8, dogNose);

  // Body
  rect(p, ox + 4, oy + 5, 10, 4, cattleBlue);
  // Speckle
  px(p, ox + 5, oy + 7, cattleDarkBlue);
  px(p, ox + 7, oy + 8, cattleDarkBlue);
  px(p, ox + 9, oy + 6, cattleDarkBlue);
  px(p, ox + 11, oy + 7, cattleDarkBlue);
  px(p, ox + 6, oy + 5, cattleRed);
  px(p, ox + 8, oy + 7, cattleRed);
  px(p, ox + 10, oy + 5, cattleRed);
  px(p, ox + 12, oy + 6, cattleRed);
  hRun(p, ox + 5, oy + 5, 8, cattleTan);

  // Tail
  px(p, ox + 3, oy + 7, cattleBlue);
  px(p, ox + 2, oy + 8, cattleBlue);
  px(p, ox + 1, oy + 8, cattleDarkBlue);

  // Legs
  vRun(p, ox + 5, oy + 3, 2, cattleTan);
  vRun(p, ox + 7, oy + 3, 2, cattleTan);
  vRun(p, ox + 11, oy + 3, 2, cattleTan);
  vRun(p, ox + 13, oy + 3, 2, cattleTan);

  // Paws
  px(p, ox + 5, oy + 3, cattleDarkBlue);
  px(p, ox + 7, oy + 3, cattleDarkBlue);
  px(p, ox + 11, oy + 3, cattleDarkBlue);
  px(p, ox + 13, oy + 3, cattleDarkBlue);

  return p;
}

function buildSchnauzer(isBlack: boolean): PixelList {
  const p: PixelList = [];
  const ox = -9, oy = -6;

  const bodyMain = isBlack ? schnauzerDark : pepperMid;
  const bodyAccent = isBlack ? schnauzerBeard : pepperLight;
  const bodyDark = isBlack ? 'rgb(20, 20, 26)' : pepperDark;
  const beardColor = isBlack ? schnauzerBeard : pepperLight;
  const browColor = isBlack ? schnauzerBeard : pepperLight;

  // Ears
  px(p, ox + 13, oy + 12, bodyMain);
  px(p, ox + 14, oy + 12, bodyMain);
  px(p, ox + 16, oy + 12, bodyMain);
  px(p, ox + 17, oy + 12, bodyMain);

  // Head
  rect(p, ox + 13, oy + 8, 5, 4, bodyMain);
  hRun(p, ox + 13, oy + 11, 2, browColor);
  hRun(p, ox + 16, oy + 11, 2, browColor);
  px(p, ox + 14, oy + 10, dogEye);
  px(p, ox + 16, oy + 10, dogEye);
  px(p, ox + 18, oy + 9, dogNose);
  px(p, ox + 18, oy + 8, dogNose);
  // Beard
  rect(p, ox + 15, oy + 6, 3, 2, beardColor);
  px(p, ox + 16, oy + 5, beardColor);

  // Body
  rect(p, ox + 4, oy + 5, 10, 4, bodyMain);
  if (!isBlack) {
    hRun(p, ox + 5, oy + 5, 8, pepperLight);
    px(p, ox + 6, oy + 7, pepperDark);
    px(p, ox + 8, oy + 8, pepperLight);
    px(p, ox + 10, oy + 6, pepperDark);
    px(p, ox + 12, oy + 7, pepperLight);
  } else {
    px(p, ox + 6, oy + 7, bodyDark);
    px(p, ox + 9, oy + 6, bodyDark);
  }

  // Tail
  px(p, ox + 3, oy + 8, bodyMain);
  px(p, ox + 3, oy + 9, bodyMain);

  // Legs
  vRun(p, ox + 5, oy + 2, 3, bodyAccent);
  vRun(p, ox + 7, oy + 2, 3, bodyAccent);
  vRun(p, ox + 11, oy + 2, 3, bodyAccent);
  vRun(p, ox + 13, oy + 2, 3, bodyAccent);

  // Paws
  px(p, ox + 5, oy + 2, bodyDark);
  px(p, ox + 7, oy + 2, bodyDark);
  px(p, ox + 11, oy + 2, bodyDark);
  px(p, ox + 13, oy + 2, bodyDark);

  return p;
}

// ── Pixel List → Canvas ──────────────────────────────────────

interface CachedSprite {
  canvas: OffscreenCanvas;
  /** Offset from the logical center to the canvas top-left corner */
  offsetX: number;
  offsetY: number;
  width: number;
  height: number;
}

const spriteCache = new Map<CharacterType, CachedSprite>();

function getPixels(type: CharacterType): PixelList {
  switch (type) {
    case 'dev':
      return buildDev();
    case 'officeWorker':
      return buildOfficeWorker();
    case 'pm':
      return buildPM();
    case 'clown':
      return buildClown();
    case 'frankenstein':
      return buildFrankenstein();
    case 'dachshund':
      return buildDachshund();
    case 'cattleDog':
      return buildCattleDog();
    case 'schnauzerBlack':
      return buildSchnauzer(true);
    case 'schnauzerPepper':
      return buildSchnauzer(false);
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

  const canvas = new OffscreenCanvas(w, h);
  const ctx = canvas.getContext('2d')!;

  for (const [x, y, color] of pixels) {
    ctx.fillStyle = color;
    ctx.fillRect((x - minX) * PIXEL_SIZE, (y - minY) * PIXEL_SIZE, PIXEL_SIZE, PIXEL_SIZE);
  }

  // The original pixel data is centered at (0,0). The bounding box's center
  // in pixel coords is ((minX+maxX)/2, (minY+maxY)/2). We need the offset
  // from center to the top-left of the cached canvas.
  const centerPxX = (minX + maxX + 1) / 2;
  const centerPxY = (minY + maxY + 1) / 2;

  return {
    canvas,
    offsetX: centerPxX * PIXEL_SIZE - w / 2,
    offsetY: centerPxY * PIXEL_SIZE - h / 2,
    width: w,
    height: h,
  };
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
