// Furniture rendering functions — extracted from OfficeCanvas.svelte
// Pure pixel-art drawing logic for all office furniture, floors, and walls.

import type { OfficeEngine } from './engine';
import type { OfficeArea, Furniture } from './types';

// ── Helper functions ───────────────────────────────────────────

export function safeRoundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  if (typeof ctx.roundRect === 'function') {
    ctx.roundRect(x, y, w, h, r);
  } else {
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.arcTo(x + w, y, x + w, y + r, r);
    ctx.lineTo(x + w, y + h - r);
    ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
    ctx.lineTo(x + r, y + h);
    ctx.arcTo(x, y + h, x, y + h - r, r);
    ctx.lineTo(x, y + r);
    ctx.arcTo(x, y, x + r, y, r);
    ctx.closePath();
  }
}

/** Draw a single "pixel" at grid position — the foundation of all pixel art */
export function px(ctx: CanvasRenderingContext2D, baseX: number, baseY: number, col: number, row: number, color: string, size: number = 2) {
  ctx.fillStyle = color;
  ctx.fillRect(baseX + col * size, baseY + row * size, size, size);
}

// ── Floor pattern rendering ────────────────────────────────────

export function drawFloorPattern(ctx: CanvasRenderingContext2D, area: OfficeArea) {
  const { x, y, width, height } = area.bounds;
  const pattern = area.floorPattern ?? 'carpet';

  ctx.save();
  ctx.beginPath();
  ctx.rect(x, y, width, height);
  ctx.clip();

  switch (pattern) {
    case 'carpet': {
      // Subtle carpet texture — tiny repeating pattern
      for (let px = x; px < x + width; px += 8) {
        for (let py = y; py < y + height; py += 8) {
          if ((px + py) % 16 === 0) {
            ctx.fillStyle = 'rgba(255, 255, 255, 0.015)';
            ctx.fillRect(px, py, 2, 2);
          }
          if ((px + py + 4) % 24 === 0) {
            ctx.fillStyle = 'rgba(0, 0, 0, 0.02)';
            ctx.fillRect(px + 2, py + 2, 2, 2);
          }
        }
      }
      break;
    }
    case 'tile': {
      // Clean tile grid
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
      ctx.lineWidth = 1;
      for (let tileX = x; tileX < x + width; tileX += 24) {
        ctx.beginPath();
        ctx.moveTo(tileX, y);
        ctx.lineTo(tileX, y + height);
        ctx.stroke();
      }
      for (let tileY = y; tileY < y + height; tileY += 24) {
        ctx.beginPath();
        ctx.moveTo(x, tileY);
        ctx.lineTo(x + width, tileY);
        ctx.stroke();
      }
      // Subtle alternating brightness
      for (let tileX = x; tileX < x + width; tileX += 24) {
        for (let tileY = y; tileY < y + height; tileY += 24) {
          if (((tileX - x) / 24 + (tileY - y) / 24) % 2 === 0) {
            ctx.fillStyle = 'rgba(255, 255, 255, 0.012)';
            ctx.fillRect(tileX + 1, tileY + 1, 22, 22);
          }
        }
      }
      break;
    }
    case 'wood': {
      // Horizontal plank lines with subtle grain
      for (let py = y; py < y + height; py += 12) {
        // Plank gap
        ctx.fillStyle = 'rgba(0, 0, 0, 0.08)';
        ctx.fillRect(x, py, width, 1);
        // Subtle grain within plank
        ctx.fillStyle = 'rgba(180, 140, 90, 0.03)';
        for (let gx = x; gx < x + width; gx += 6) {
          const offset = Math.sin((gx + py) * 0.15) * 2;
          ctx.fillRect(gx, py + 3 + offset, 4, 1);
        }
      }
      // Vertical board join lines (staggered)
      for (let py = y; py < y + height; py += 24) {
        const stagger = ((py - y) / 12) % 2 === 0 ? 0 : 40;
        for (let joinX = x + 80 + stagger; joinX < x + width; joinX += 80) {
          ctx.fillStyle = 'rgba(0, 0, 0, 0.06)';
          ctx.fillRect(joinX, py, 1, 12);
        }
      }
      break;
    }
    case 'concrete': {
      // Speckled texture
      ctx.fillStyle = 'rgba(255, 255, 255, 0.01)';
      for (let i = 0; i < width * height * 0.002; i++) {
        const randX = x + Math.random() * width;
        const randY = y + Math.random() * height;
        ctx.fillRect(randX, randY, 1, 1);
      }
      break;
    }
    case 'grass': {
      // Natural grass texture — varied green tufts
      for (let gx = x; gx < x + width; gx += 6) {
        for (let gy = y; gy < y + height; gy += 6) {
          const seed = (gx * 13 + gy * 7) % 17;
          if (seed < 5) {
            ctx.fillStyle = 'rgba(80, 160, 60, 0.06)';
            ctx.fillRect(gx, gy, 2, 3);
          } else if (seed < 9) {
            ctx.fillStyle = 'rgba(40, 120, 30, 0.05)';
            ctx.fillRect(gx + 1, gy, 1, 2);
          } else if (seed < 12) {
            ctx.fillStyle = 'rgba(100, 180, 70, 0.04)';
            ctx.fillRect(gx, gy + 1, 3, 1);
          }
        }
      }
      // Occasional tiny flowers/clover
      for (let fx = x + 10; fx < x + width - 10; fx += 40) {
        for (let fy = y + 10; fy < y + height - 10; fy += 35) {
          const seed = (fx * 7 + fy * 3) % 11;
          if (seed < 3) {
            ctx.fillStyle = 'rgba(255, 255, 200, 0.08)';
            ctx.fillRect(fx, fy, 2, 2);
          }
        }
      }
      break;
    }
  }

  ctx.restore();
}

// ── Wall rendering ─────────────────────────────────────────────

export function drawOfficeWalls(ctx: CanvasRenderingContext2D) {
  const wallThickness = 5;
  const wallColor = 'rgb(72, 72, 82)';
  const wallHighlight = 'rgb(82, 82, 92)';
  const wallShadow = 'rgb(55, 55, 65)';

  // ── Outer walls ──
  // Top wall
  ctx.fillStyle = wallColor;
  ctx.fillRect(0, 0, 1000, wallThickness);
  ctx.fillStyle = wallHighlight;
  ctx.fillRect(0, 0, 1000, 1);

  // Left wall
  ctx.fillStyle = wallColor;
  ctx.fillRect(0, 0, wallThickness, 750);
  ctx.fillStyle = wallHighlight;
  ctx.fillRect(0, 0, 1, 750);

  // Right wall (no door gap — door is on interior wall now)
  ctx.fillStyle = wallColor;
  ctx.fillRect(995, 0, wallThickness, 750);

  // Bottom wall
  ctx.fillStyle = wallColor;
  ctx.fillRect(0, 745, 1000, wallThickness);
  ctx.fillStyle = wallShadow;
  ctx.fillRect(0, 749, 1000, 1);

  // ── Interior walls ──

  // Vertical divider: left column (strategy/kitchen) | main office (at x=275)
  ctx.fillStyle = wallColor;
  ctx.fillRect(275, 0, wallThickness, 160);       // above strategy→office doorway
  ctx.fillStyle = wallHighlight;
  ctx.fillRect(275, 0, 1, 160);
  // Doorway gap (160-200) — strategy room to main office
  ctx.fillStyle = wallColor;
  ctx.fillRect(275, 200, wallThickness, 172);     // between doorways
  ctx.fillStyle = wallHighlight;
  ctx.fillRect(275, 200, 1, 172);
  // Meets horizontal wall at y=375
  ctx.fillStyle = wallColor;
  ctx.fillRect(275, 380, wallThickness, 160);     // above kitchen→office doorway
  ctx.fillStyle = wallHighlight;
  ctx.fillRect(275, 380, 1, 160);
  // Doorway gap (540-580) — kitchen to main office
  ctx.fillStyle = wallColor;
  ctx.fillRect(275, 580, wallThickness, 170);     // bottom of wall
  ctx.fillStyle = wallHighlight;
  ctx.fillRect(275, 580, 1, 170);

  // Vertical divider: main office | break room (at x=670)
  ctx.fillStyle = wallColor;
  ctx.fillRect(670, 0, wallThickness, 340);       // above doorway
  ctx.fillStyle = wallHighlight;
  ctx.fillRect(670, 0, 1, 340);
  // Doorway gap (340-380) — main office to break room
  ctx.fillStyle = wallColor;
  ctx.fillRect(670, 380, wallThickness, 370);     // below doorway
  ctx.fillStyle = wallHighlight;
  ctx.fillRect(670, 380, 1, 370);

  // Horizontal divider: strategy room | kitchen (at y=375)
  ctx.fillStyle = wallColor;
  ctx.fillRect(0, 375, 120, wallThickness);       // left of doorway
  ctx.fillStyle = wallShadow;
  ctx.fillRect(0, 375, 120, 1);
  // Doorway gap (120-160)
  ctx.fillStyle = wallColor;
  ctx.fillRect(160, 375, 120, wallThickness);     // right of doorway to vertical wall
  ctx.fillStyle = wallShadow;
  ctx.fillRect(160, 375, 120, 1);

  // ── Doorway floor markers (subtle) ──
  const doorwayColor = 'rgba(120, 95, 65, 0.15)';
  ctx.fillStyle = doorwayColor;
  // Strategy room to main office
  ctx.fillRect(275, 160, wallThickness, 40);
  // Kitchen to main office
  ctx.fillRect(275, 540, wallThickness, 40);
  // Strategy to kitchen
  ctx.fillRect(120, 375, 40, wallThickness);
  // Main office to break room
  ctx.fillRect(670, 340, wallThickness, 40);
}

// ── Furniture dispatch ─────────────────────────────────────────

export function drawFurniture(ctx: CanvasRenderingContext2D, item: Furniture) {
  const { x, y } = item.position;

  switch (item.type) {
    case 'deskWithMonitor':
      drawDeskWithMonitor(ctx, x, y, item.width, item.height);
      break;
    case 'officeChair':
      drawOfficeChair(ctx, x, y);
      break;
    case 'meetingTable':
      drawMeetingTable(ctx, x, y, item.width, item.height);
      break;
    case 'meetingChair':
      drawMeetingChair(ctx, x, y);
      break;
    case 'whiteboard':
      drawWhiteboard(ctx, x, y, item.width, item.height);
      break;
    case 'fridge':
      drawFridge(ctx, x, y);
      break;
    case 'microwave':
      drawMicrowave(ctx, x, y);
      break;
    case 'toaster':
      drawToaster(ctx, x, y);
      break;
    case 'kitchenCounter':
      drawKitchenCounter(ctx, x, y, item.width, item.height);
      break;
    case 'sink':
      drawSink(ctx, x, y);
      break;
    case 'coffeeMachine':
      drawCoffeeMachine(ctx, x, y);
      break;
    case 'couch':
      drawCouch(ctx, x, y, item.width, item.height, item.color);
      break;
    case 'beanBag':
      drawBeanBag(ctx, x, y, item.color);
      break;
    case 'plant':
      drawPlant(ctx, x, y);
      break;
    case 'fern':
      drawFern(ctx, x, y);
      break;
    case 'waterCooler':
      drawWaterCooler(ctx, x, y);
      break;
    case 'printer':
      drawPrinter(ctx, x, y);
      break;
    case 'tvScreen':
      drawTvScreen(ctx, x, y, item.width, item.height);
      break;
    case 'pingPongTable':
      drawPingPongTable(ctx, x, y);
      break;
    case 'gameConsole':
      drawGameConsole(ctx, x, y);
      break;
    case 'arcadeMachine':
      drawArcadeMachine(ctx, x, y, item.color);
      break;
    case 'clock':
      drawClock(ctx, x, y);
      break;
    case 'pictureFrame':
      drawPictureFrame(ctx, x, y);
      break;
    case 'desk':
      drawSimpleDesk(ctx, x, y, item.width, item.height);
      break;
    case 'door':
      // Doors rendered by wall system, skip
      break;
    case 'wallSegment':
      // Walls rendered by drawOfficeWalls, skip
      break;
    // ── Dog Park ──
    case 'dogBowl':
      drawDogBowl(ctx, x, y);
      break;
    case 'fireHydrant':
      drawFireHydrant(ctx, x, y);
      break;
    case 'dogHouse':
      drawDogHouse(ctx, x, y);
      break;
    case 'agilityHoop':
      drawAgilityHoop(ctx, x, y);
      break;
    case 'agilityRamp':
      drawAgilityRamp(ctx, x, y);
      break;
    case 'pondWater':
      drawPondWater(ctx, x, y, item.width, item.height);
      break;
    case 'tree':
      drawTree(ctx, x, y);
      break;
    case 'bench':
      drawBench(ctx, x, y);
      break;
    case 'fence':
      drawFence(ctx, x, y, item.width, item.height);
      break;
    case 'ballLauncher':
      drawBallLauncher(ctx, x, y);
      break;
    // ── Gym ──
    case 'treadmill':
      drawTreadmill(ctx, x, y);
      break;
    case 'weightRack':
      drawWeightRack(ctx, x, y);
      break;
    case 'punchingBag':
      drawPunchingBag(ctx, x, y);
      break;
    case 'yogaMat':
      drawYogaMat(ctx, x, y);
      break;
    case 'exerciseBall':
      drawExerciseBall(ctx, x, y);
      break;
    case 'locker':
      drawLocker(ctx, x, y);
      break;
    case 'mirror':
      drawMirror(ctx, x, y, item.width, item.height);
      break;
    case 'waterFountain':
      drawWaterFountain(ctx, x, y);
      break;
    // ── Sprite Street bedrooms ──
    case 'bed':
      drawBed(ctx, x, y, item.width, item.height, item.color);
      break;
    case 'closet':
      drawCloset(ctx, x, y, item.width, item.height);
      break;
    case 'rug':
      drawRug(ctx, x, y, item.width, item.height, item.color);
      break;
  }
}

// ── Individual furniture pixel art renderers ───────────────────

export function drawDeskWithMonitor(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  const s = 2; // pixel size

  // Desk surface — warm wood
  ctx.fillStyle = 'rgb(140, 100, 60)';
  ctx.fillRect(x, y, w, h);
  // Top edge highlight
  ctx.fillStyle = 'rgb(160, 120, 75)';
  ctx.fillRect(x, y, w, s);
  // Bottom shadow
  ctx.fillStyle = 'rgb(110, 78, 48)';
  ctx.fillRect(x, y + h - s, w, s);
  // Left/right edges
  ctx.fillStyle = 'rgb(120, 85, 52)';
  ctx.fillRect(x, y, s, h);
  ctx.fillRect(x + w - s, y, s, h);

  // Monitor — centered on desk
  const mw = 20; // monitor width
  const mh = 14; // monitor height
  const mx = x + (w - mw) / 2;
  const my = y + 4;

  // Monitor stand
  ctx.fillStyle = 'rgb(50, 50, 55)';
  ctx.fillRect(mx + mw / 2 - 3, my + mh, 6, 4);
  ctx.fillRect(mx + mw / 2 - 5, my + mh + 3, 10, s);

  // Monitor frame
  ctx.fillStyle = 'rgb(35, 35, 42)';
  ctx.fillRect(mx, my, mw, mh);

  // Screen (light blue glow)
  ctx.fillStyle = 'rgb(80, 120, 180)';
  ctx.fillRect(mx + s, my + s, mw - s * 2, mh - s * 2);

  // Screen content — tiny "code" lines
  ctx.fillStyle = 'rgb(140, 200, 255)';
  ctx.fillRect(mx + 4, my + 4, 8, 1);
  ctx.fillStyle = 'rgb(120, 230, 160)';
  ctx.fillRect(mx + 4, my + 6, 6, 1);
  ctx.fillStyle = 'rgb(255, 200, 100)';
  ctx.fillRect(mx + 4, my + 8, 10, 1);

  // Keyboard
  const kw = 14;
  const kx = x + (w - kw) / 2;
  const ky = y + h - 8;
  ctx.fillStyle = 'rgb(60, 60, 68)';
  ctx.fillRect(kx, ky, kw, 6);
  // Key dots
  ctx.fillStyle = 'rgb(80, 80, 90)';
  for (let ki = 0; ki < 3; ki++) {
    for (let kj = 0; kj < 5; kj++) {
      ctx.fillRect(kx + 2 + kj * s + kj, ky + 1 + ki * s, 1, 1);
    }
  }
}

export function drawOfficeChair(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const s = 2;
  // Seat (top-down view — circle-ish)
  ctx.fillStyle = 'rgb(50, 50, 60)';
  ctx.beginPath();
  ctx.arc(x + 9, y + 8, 7, 0, Math.PI * 2);
  ctx.fill();
  // Seat highlight
  ctx.fillStyle = 'rgb(65, 65, 75)';
  ctx.beginPath();
  ctx.arc(x + 8, y + 7, 4, 0, Math.PI * 2);
  ctx.fill();
  // Chair base star (5 tiny legs)
  ctx.fillStyle = 'rgb(40, 40, 48)';
  px(ctx, x, y, 0, 7, 'rgb(40, 40, 48)', s);  // left leg
  px(ctx, x, y, 8, 7, 'rgb(40, 40, 48)', s);  // right leg
  px(ctx, x, y, 4, 0, 'rgb(40, 40, 48)', s);  // top leg
  px(ctx, x, y, 4, 7, 'rgb(40, 40, 48)', s);  // bottom leg (center support)
}

export function drawMeetingTable(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  // Table surface — rounded rectangle, dark wood
  ctx.fillStyle = 'rgb(100, 75, 48)';
  safeRoundRect(ctx, x, y, w, h, 6);
  ctx.fill();

  // Top highlight
  ctx.fillStyle = 'rgb(120, 90, 58)';
  safeRoundRect(ctx, x + 2, y + 1, w - 4, 3, 2);
  ctx.fill();

  // Center line (decorative inlay)
  ctx.fillStyle = 'rgb(85, 62, 38)';
  ctx.fillRect(x + 10, y + h / 2 - 1, w - 20, 2);

  // Subtle wood grain
  ctx.fillStyle = 'rgba(140, 110, 70, 0.1)';
  for (let gy = y + 6; gy < y + h - 4; gy += 5) {
    ctx.fillRect(x + 4, gy, w - 8, 1);
  }

  // Border
  ctx.strokeStyle = 'rgba(70, 50, 30, 0.5)';
  ctx.lineWidth = 1;
  safeRoundRect(ctx, x, y, w, h, 6);
  ctx.stroke();
}

export function drawMeetingChair(ctx: CanvasRenderingContext2D, x: number, y: number) {
  // Small top-down chair
  ctx.fillStyle = 'rgb(55, 55, 65)';
  safeRoundRect(ctx, x, y, 16, 14, 3);
  ctx.fill();
  // Seat cushion
  ctx.fillStyle = 'rgb(65, 65, 78)';
  safeRoundRect(ctx, x + 2, y + 2, 12, 10, 2);
  ctx.fill();
}

export function drawWhiteboard(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  // Frame
  ctx.fillStyle = 'rgb(180, 175, 170)';
  ctx.fillRect(x, y, w, h);

  // White surface
  ctx.fillStyle = 'rgb(240, 240, 245)';
  ctx.fillRect(x + 2, y + 2, w - 4, h - 4);

  // Colorful "writing" scribbles
  const colors = ['rgb(220, 60, 60)', 'rgb(50, 100, 200)', 'rgb(40, 160, 80)', 'rgb(200, 140, 30)'];
  for (let i = 0; i < 4; i++) {
    ctx.fillStyle = colors[i];
    const lineY = y + 3 + i * 2;
    const lineW = 10 + (i * 7) % 20;
    const lineX = x + 4 + (i * 13) % (w - lineW - 8);
    ctx.fillRect(lineX, lineY, lineW, 1);
  }

  // Marker tray at bottom
  ctx.fillStyle = 'rgb(160, 155, 150)';
  ctx.fillRect(x + 10, y + h - 3, w - 20, 2);

  // Tiny markers in tray
  ctx.fillStyle = 'rgb(200, 50, 50)';
  ctx.fillRect(x + 15, y + h - 3, 4, 2);
  ctx.fillStyle = 'rgb(50, 50, 200)';
  ctx.fillRect(x + 21, y + h - 3, 4, 2);
  ctx.fillStyle = 'rgb(50, 150, 50)';
  ctx.fillRect(x + 27, y + h - 3, 4, 2);
}

export function drawFridge(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 24, h = 44;
  // Body
  ctx.fillStyle = 'rgb(205, 210, 215)';
  ctx.fillRect(x, y, w, h);
  // Door line (horizontal split)
  ctx.fillStyle = 'rgb(170, 175, 180)';
  ctx.fillRect(x, y + 16, w, 2);
  // Left edge shadow
  ctx.fillStyle = 'rgb(180, 185, 190)';
  ctx.fillRect(x, y, 2, h);
  // Right edge highlight
  ctx.fillStyle = 'rgb(220, 225, 230)';
  ctx.fillRect(x + w - 2, y, 2, h);
  // Handle (freezer)
  ctx.fillStyle = 'rgb(150, 155, 160)';
  ctx.fillRect(x + w - 5, y + 5, 2, 8);
  // Handle (fridge)
  ctx.fillRect(x + w - 5, y + 22, 2, 12);
  // Top highlight
  ctx.fillStyle = 'rgb(225, 230, 235)';
  ctx.fillRect(x + 2, y, w - 4, 2);
  // Bottom shadow
  ctx.fillStyle = 'rgb(160, 165, 170)';
  ctx.fillRect(x + 2, y + h - 2, w - 4, 2);
}

export function drawMicrowave(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 22, h = 16;
  // Body
  ctx.fillStyle = 'rgb(55, 55, 62)';
  ctx.fillRect(x, y, w, h);
  // Window
  ctx.fillStyle = 'rgb(30, 40, 50)';
  ctx.fillRect(x + 2, y + 2, 14, h - 4);
  // Window reflection
  ctx.fillStyle = 'rgba(100, 140, 180, 0.15)';
  ctx.fillRect(x + 3, y + 3, 6, 4);
  // Control panel
  ctx.fillStyle = 'rgb(45, 45, 52)';
  ctx.fillRect(x + 17, y + 2, 4, h - 4);
  // Buttons
  ctx.fillStyle = 'rgb(80, 200, 80)';
  ctx.fillRect(x + 18, y + 4, 2, 2);
  ctx.fillStyle = 'rgb(200, 80, 80)';
  ctx.fillRect(x + 18, y + 8, 2, 2);
  // Handle
  ctx.fillStyle = 'rgb(100, 100, 110)';
  ctx.fillRect(x + 16, y + 4, 1, h - 8);
}

export function drawToaster(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 14, h = 12;
  // Body
  ctx.fillStyle = 'rgb(190, 180, 165)';
  ctx.fillRect(x, y + 2, w, h - 2);
  // Top edge
  ctx.fillStyle = 'rgb(200, 192, 178)';
  ctx.fillRect(x, y + 2, w, 2);
  // Bread slots
  ctx.fillStyle = 'rgb(140, 130, 115)';
  ctx.fillRect(x + 2, y, 4, 4);
  ctx.fillRect(x + 8, y, 4, 4);
  // Bread peeking out
  ctx.fillStyle = 'rgb(210, 180, 130)';
  ctx.fillRect(x + 3, y, 2, 2);
  ctx.fillRect(x + 9, y, 2, 2);
  // Lever
  ctx.fillStyle = 'rgb(140, 140, 150)';
  ctx.fillRect(x + w - 2, y + 5, 2, 4);
  // Shadow
  ctx.fillStyle = 'rgb(170, 160, 145)';
  ctx.fillRect(x, y + h - 2, w, 2);
}

export function drawKitchenCounter(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  // Counter surface
  ctx.fillStyle = 'rgb(88, 88, 92)';
  ctx.fillRect(x, y, w, h);
  // Top edge highlight
  ctx.fillStyle = 'rgb(100, 100, 105)';
  ctx.fillRect(x, y, w, 2);
  // Front edge shadow
  ctx.fillStyle = 'rgb(68, 68, 72)';
  ctx.fillRect(x, y + h - 2, w, 2);
  // Cabinet doors below (subtle lines)
  ctx.strokeStyle = 'rgba(60, 60, 65, 0.5)';
  ctx.lineWidth = 1;
  for (let cx = x + 20; cx < x + w; cx += 20) {
    ctx.beginPath();
    ctx.moveTo(cx, y + 4);
    ctx.lineTo(cx, y + h - 2);
    ctx.stroke();
  }
}

export function drawSink(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 24, h = 16;
  // Basin (dark oval)
  ctx.fillStyle = 'rgb(120, 125, 135)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2 - 1, h / 2 - 1, 0, 0, Math.PI * 2);
  ctx.fill();
  // Inner basin
  ctx.fillStyle = 'rgb(90, 95, 105)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2 - 3, h / 2 - 3, 0, 0, Math.PI * 2);
  ctx.fill();
  // Drain
  ctx.fillStyle = 'rgb(60, 65, 70)';
  ctx.beginPath();
  ctx.arc(x + w / 2, y + h / 2, 2, 0, Math.PI * 2);
  ctx.fill();
  // Faucet
  ctx.fillStyle = 'rgb(170, 175, 185)';
  ctx.fillRect(x + w / 2 - 1, y - 2, 3, 4);
  ctx.fillRect(x + w / 2 - 3, y - 2, 7, 2);
}

export function drawCoffeeMachine(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 20, h = 16;
  // Body
  ctx.fillStyle = 'rgb(42, 36, 32)';
  ctx.fillRect(x, y, w, h);
  // Top
  ctx.fillStyle = 'rgb(52, 45, 40)';
  ctx.fillRect(x, y, w, 3);
  // Water reservoir (back, translucent)
  ctx.fillStyle = 'rgba(80, 130, 180, 0.3)';
  ctx.fillRect(x + 1, y + 1, 6, h - 4);
  // Coffee pot area
  ctx.fillStyle = 'rgb(30, 28, 26)';
  ctx.fillRect(x + 8, y + 6, 10, 8);
  // Coffee pot (glass with dark liquid)
  ctx.fillStyle = 'rgba(120, 160, 200, 0.2)';
  ctx.fillRect(x + 9, y + 7, 8, 6);
  ctx.fillStyle = 'rgb(60, 30, 15)';
  ctx.fillRect(x + 9, y + 9, 8, 4);
  // LED indicator
  ctx.fillStyle = 'rgb(80, 220, 80)';
  ctx.fillRect(x + 2, y + h - 3, 2, 2);
}

export function drawCouch(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, color: string) {
  // Parse the color to create variations
  // Back rest (top)
  ctx.fillStyle = color;
  safeRoundRect(ctx, x, y, w, h, 4);
  ctx.fill();

  // Seat cushion area (slightly lighter)
  ctx.fillStyle = 'rgba(255, 255, 255, 0.06)';
  safeRoundRect(ctx, x + 3, y + 4, w - 6, h - 7, 2);
  ctx.fill();

  // Cushion divider lines
  ctx.strokeStyle = 'rgba(0, 0, 0, 0.15)';
  ctx.lineWidth = 1;
  const cushionCount = Math.max(2, Math.floor(w / 30));
  const cushionW = (w - 6) / cushionCount;
  for (let i = 1; i < cushionCount; i++) {
    ctx.beginPath();
    ctx.moveTo(x + 3 + cushionW * i, y + 5);
    ctx.lineTo(x + 3 + cushionW * i, y + h - 4);
    ctx.stroke();
  }

  // Armrests
  ctx.fillStyle = 'rgba(0, 0, 0, 0.12)';
  safeRoundRect(ctx, x, y, 5, h, 2);
  ctx.fill();
  safeRoundRect(ctx, x + w - 5, y, 5, h, 2);
  ctx.fill();

  // Border
  ctx.strokeStyle = 'rgba(0, 0, 0, 0.2)';
  ctx.lineWidth = 1;
  safeRoundRect(ctx, x, y, w, h, 4);
  ctx.stroke();
}

export function drawBeanBag(ctx: CanvasRenderingContext2D, x: number, y: number, color: string) {
  const w = 26, h = 24;
  // Squishy irregular shape
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(x + 5, y + h);
  ctx.quadraticCurveTo(x - 2, y + h / 2, x + 4, y + 2);
  ctx.quadraticCurveTo(x + w / 2, y - 3, x + w - 4, y + 2);
  ctx.quadraticCurveTo(x + w + 2, y + h / 2, x + w - 5, y + h);
  ctx.quadraticCurveTo(x + w / 2, y + h + 2, x + 5, y + h);
  ctx.fill();

  // Highlight
  ctx.fillStyle = 'rgba(255, 255, 255, 0.1)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2 - 2, y + h / 2 - 3, 6, 4, -0.2, 0, Math.PI * 2);
  ctx.fill();

  // Wrinkle lines
  ctx.strokeStyle = 'rgba(0, 0, 0, 0.1)';
  ctx.lineWidth = 0.5;
  ctx.beginPath();
  ctx.moveTo(x + 8, y + 8);
  ctx.quadraticCurveTo(x + 13, y + 12, x + 18, y + 9);
  ctx.stroke();
}

export function drawPlant(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const s = 2;
  // Pot (terra cotta)
  ctx.fillStyle = 'rgb(160, 90, 50)';
  ctx.fillRect(x + 3, y + 8, 8, 6);
  // Pot rim
  ctx.fillStyle = 'rgb(180, 105, 60)';
  ctx.fillRect(x + 2, y + 7, 10, 2);
  // Pot shadow
  ctx.fillStyle = 'rgb(130, 70, 38)';
  ctx.fillRect(x + 3, y + 12, 8, 2);

  // Leaves (multiple green circles for bushy look)
  ctx.fillStyle = 'rgb(55, 120, 50)';
  ctx.beginPath();
  ctx.arc(x + 7, y + 5, 5, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = 'rgb(65, 140, 55)';
  ctx.beginPath();
  ctx.arc(x + 4, y + 3, 3, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = 'rgb(45, 105, 42)';
  ctx.beginPath();
  ctx.arc(x + 10, y + 4, 3.5, 0, Math.PI * 2);
  ctx.fill();
  // Highlight leaf
  ctx.fillStyle = 'rgb(80, 160, 65)';
  ctx.beginPath();
  ctx.arc(x + 6, y + 2, 2, 0, Math.PI * 2);
  ctx.fill();
}

export function drawFern(ctx: CanvasRenderingContext2D, x: number, y: number) {
  // Pot
  ctx.fillStyle = 'rgb(90, 90, 95)';
  ctx.fillRect(x + 4, y + 9, 8, 5);
  ctx.fillStyle = 'rgb(100, 100, 108)';
  ctx.fillRect(x + 3, y + 8, 10, 2);

  // Fern fronds — drooping arcs
  ctx.strokeStyle = 'rgb(50, 110, 55)';
  ctx.lineWidth = 2;
  // Left frond
  ctx.beginPath();
  ctx.moveTo(x + 8, y + 6);
  ctx.quadraticCurveTo(x - 2, y + 2, x, y + 10);
  ctx.stroke();
  // Right frond
  ctx.beginPath();
  ctx.moveTo(x + 8, y + 6);
  ctx.quadraticCurveTo(x + 18, y + 2, x + 16, y + 10);
  ctx.stroke();
  // Center fronds
  ctx.strokeStyle = 'rgb(60, 130, 60)';
  ctx.beginPath();
  ctx.moveTo(x + 8, y + 6);
  ctx.quadraticCurveTo(x + 4, y - 2, x + 2, y + 4);
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(x + 8, y + 6);
  ctx.quadraticCurveTo(x + 12, y - 2, x + 14, y + 4);
  ctx.stroke();
  // Top
  ctx.fillStyle = 'rgb(55, 125, 52)';
  ctx.beginPath();
  ctx.arc(x + 8, y + 4, 3, 0, Math.PI * 2);
  ctx.fill();
}

export function drawWaterCooler(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 16, h = 28;
  // Base/stand
  ctx.fillStyle = 'rgb(180, 180, 190)';
  ctx.fillRect(x + 2, y + 16, 12, 12);
  // Base highlight
  ctx.fillStyle = 'rgb(195, 195, 205)';
  ctx.fillRect(x + 2, y + 16, 12, 2);
  // Tap area
  ctx.fillStyle = 'rgb(160, 160, 170)';
  ctx.fillRect(x + 5, y + 20, 6, 4);
  // Tap
  ctx.fillStyle = 'rgb(100, 160, 220)';
  ctx.fillRect(x + 6, y + 21, 2, 2);
  ctx.fillStyle = 'rgb(220, 80, 80)';
  ctx.fillRect(x + 9, y + 21, 2, 2);

  // Water jug (on top)
  ctx.fillStyle = 'rgba(100, 160, 220, 0.35)';
  ctx.beginPath();
  ctx.moveTo(x + 4, y + 16);
  ctx.lineTo(x + 3, y + 4);
  ctx.quadraticCurveTo(x + 8, y - 1, x + 13, y + 4);
  ctx.lineTo(x + 12, y + 16);
  ctx.closePath();
  ctx.fill();
  // Water level line
  ctx.fillStyle = 'rgba(80, 140, 200, 0.25)';
  ctx.fillRect(x + 4, y + 6, 8, 8);
  // Jug cap
  ctx.fillStyle = 'rgb(180, 180, 190)';
  ctx.fillRect(x + 6, y, 4, 3);
}

export function drawPrinter(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 36, h = 24;
  // Body
  ctx.fillStyle = 'rgb(78, 78, 85)';
  safeRoundRect(ctx, x, y + 4, w, h - 4, 2);
  ctx.fill();
  // Top surface
  ctx.fillStyle = 'rgb(88, 88, 95)';
  ctx.fillRect(x + 1, y + 4, w - 2, 3);
  // Paper input tray (top)
  ctx.fillStyle = 'rgb(220, 220, 225)';
  ctx.fillRect(x + 6, y, 24, 6);
  ctx.fillStyle = 'rgb(240, 240, 245)';
  ctx.fillRect(x + 8, y + 1, 20, 3);
  // Paper output tray (front)
  ctx.fillStyle = 'rgb(90, 90, 98)';
  ctx.fillRect(x + 4, y + h - 2, 28, 4);
  ctx.fillStyle = 'rgb(235, 235, 240)';
  ctx.fillRect(x + 8, y + h - 1, 20, 2);
  // Control panel
  ctx.fillStyle = 'rgb(50, 50, 58)';
  ctx.fillRect(x + w - 10, y + 8, 8, 6);
  // LED
  ctx.fillStyle = 'rgb(80, 220, 80)';
  ctx.fillRect(x + w - 8, y + 10, 2, 2);
  // Border
  ctx.strokeStyle = 'rgba(50, 50, 55, 0.5)';
  ctx.lineWidth = 1;
  safeRoundRect(ctx, x, y + 4, w, h - 4, 2);
  ctx.stroke();
}

export function drawTvScreen(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  // Outer bezel (dark frame)
  ctx.fillStyle = 'rgb(25, 25, 32)';
  ctx.fillRect(x, y, w, h);
  // Screen
  ctx.fillStyle = 'rgb(40, 50, 70)';
  ctx.fillRect(x + 2, y + 2, w - 4, h - 4);
  // Screen content — colorful pixels (showing a game/show)
  const screenColors = [
    'rgb(200, 60, 60)', 'rgb(60, 180, 80)', 'rgb(60, 100, 220)',
    'rgb(220, 180, 40)', 'rgb(180, 60, 200)', 'rgb(60, 200, 200)',
  ];
  for (let sx = x + 3; sx < x + w - 3; sx += 4) {
    for (let sy = y + 3; sy < y + h - 3; sy += 3) {
      const ci = (Math.floor((sx * 7 + sy * 13) / 4)) % screenColors.length;
      ctx.fillStyle = screenColors[ci];
      ctx.globalAlpha = 0.3 + ((sx + sy) % 3) * 0.15;
      ctx.fillRect(sx, sy, 3, 2);
    }
  }
  ctx.globalAlpha = 1;
  // Screen glow
  ctx.fillStyle = 'rgba(100, 140, 200, 0.06)';
  ctx.fillRect(x - 2, y + h, w + 4, 4);
}

export function drawPingPongTable(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 100, h = 56;
  // Table surface (green)
  ctx.fillStyle = 'rgb(30, 110, 60)';
  safeRoundRect(ctx, x, y, w, h, 2);
  ctx.fill();
  // Table edge
  ctx.strokeStyle = 'rgb(20, 70, 40)';
  ctx.lineWidth = 2;
  safeRoundRect(ctx, x, y, w, h, 2);
  ctx.stroke();
  // White border line
  ctx.strokeStyle = 'rgb(220, 220, 220)';
  ctx.lineWidth = 1;
  ctx.strokeRect(x + 3, y + 3, w - 6, h - 6);
  // Center line (net)
  ctx.fillStyle = 'rgb(200, 200, 205)';
  ctx.fillRect(x + w / 2 - 1, y + 1, 2, h - 2);
  // Net posts
  ctx.fillStyle = 'rgb(150, 150, 160)';
  ctx.fillRect(x + w / 2 - 2, y, 4, 3);
  ctx.fillRect(x + w / 2 - 2, y + h - 3, 4, 3);
  // Table legs (visible at corners)
  ctx.fillStyle = 'rgb(60, 60, 68)';
  ctx.fillRect(x + 2, y + h, 3, 4);
  ctx.fillRect(x + w - 5, y + h, 3, 4);
}

export function drawGameConsole(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 28, h = 12;
  // Console body
  ctx.fillStyle = 'rgb(30, 30, 38)';
  safeRoundRect(ctx, x, y, w, h, 2);
  ctx.fill();
  // Top highlight
  ctx.fillStyle = 'rgb(40, 40, 50)';
  ctx.fillRect(x + 2, y + 1, w - 4, 2);
  // Disc drive line
  ctx.fillStyle = 'rgb(22, 22, 28)';
  ctx.fillRect(x + 3, y + 5, 14, 1);
  // Power LED
  ctx.fillStyle = 'rgb(60, 160, 255)';
  ctx.fillRect(x + w - 6, y + 4, 2, 2);
  // Eject button
  ctx.fillStyle = 'rgb(50, 50, 60)';
  ctx.fillRect(x + w - 6, y + 7, 3, 2);

  // Controller 1 (left)
  ctx.fillStyle = 'rgb(45, 45, 55)';
  ctx.beginPath();
  ctx.arc(x - 6, y + h + 6, 5, 0, Math.PI * 2);
  ctx.fill();
  // D-pad
  ctx.fillStyle = 'rgb(60, 60, 70)';
  ctx.fillRect(x - 7, y + h + 5, 3, 1);
  ctx.fillRect(x - 6, y + h + 4, 1, 3);

  // Controller 2 (right)
  ctx.fillStyle = 'rgb(45, 45, 55)';
  ctx.beginPath();
  ctx.arc(x + w + 6, y + h + 6, 5, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = 'rgb(60, 60, 70)';
  ctx.fillRect(x + w + 5, y + h + 5, 3, 1);
  ctx.fillRect(x + w + 6, y + h + 4, 1, 3);

  // Controller cables
  ctx.strokeStyle = 'rgb(40, 40, 48)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(x + 3, y + h);
  ctx.quadraticCurveTo(x - 2, y + h + 2, x - 3, y + h + 3);
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(x + w - 3, y + h);
  ctx.quadraticCurveTo(x + w + 2, y + h + 2, x + w + 3, y + h + 3);
  ctx.stroke();
}

export function drawArcadeMachine(ctx: CanvasRenderingContext2D, x: number, y: number, color: string) {
  const w = 30, h = 44;
  // Body
  ctx.fillStyle = color;
  safeRoundRect(ctx, x, y, w, h, 3);
  ctx.fill();

  // Screen area (upper portion)
  ctx.fillStyle = 'rgb(15, 15, 20)';
  ctx.fillRect(x + 3, y + 3, w - 6, 18);

  // Screen content — retro game graphics
  ctx.fillStyle = 'rgb(60, 200, 60)';
  ctx.fillRect(x + 6, y + 12, 4, 4);  // player
  ctx.fillStyle = 'rgb(200, 60, 60)';
  ctx.fillRect(x + 16, y + 8, 4, 3);   // enemy
  ctx.fillRect(x + 10, y + 5, 3, 3);   // enemy
  ctx.fillStyle = 'rgb(255, 220, 60)';
  ctx.fillRect(x + 14, y + 14, 2, 2);  // coin

  // Marquee (top decoration)
  ctx.fillStyle = 'rgb(230, 200, 60)';
  ctx.fillRect(x + 4, y + 2, w - 8, 2);

  // Control panel
  ctx.fillStyle = 'rgb(50, 50, 55)';
  ctx.fillRect(x + 2, y + 22, w - 4, 10);
  // Joystick
  ctx.fillStyle = 'rgb(30, 30, 35)';
  ctx.beginPath();
  ctx.arc(x + 10, y + 27, 3, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = 'rgb(180, 40, 40)';
  ctx.beginPath();
  ctx.arc(x + 10, y + 27, 2, 0, Math.PI * 2);
  ctx.fill();
  // Buttons
  ctx.fillStyle = 'rgb(220, 60, 60)';
  ctx.beginPath();
  ctx.arc(x + 19, y + 25, 2, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = 'rgb(60, 60, 220)';
  ctx.beginPath();
  ctx.arc(x + 24, y + 27, 2, 0, Math.PI * 2);
  ctx.fill();

  // Coin slot area
  ctx.fillStyle = 'rgb(35, 35, 42)';
  ctx.fillRect(x + 8, y + 34, 14, 6);
  ctx.fillStyle = 'rgb(180, 160, 60)';
  ctx.fillRect(x + 12, y + 36, 6, 2);

  // Border
  ctx.strokeStyle = 'rgba(0, 0, 0, 0.3)';
  ctx.lineWidth = 1;
  safeRoundRect(ctx, x, y, w, h, 3);
  ctx.stroke();
}

export function drawClock(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const cx = x + 9, cy = y + 9, r = 8;
  // Clock face
  ctx.fillStyle = 'rgb(235, 235, 240)';
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();
  // Border
  ctx.strokeStyle = 'rgb(120, 120, 130)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.stroke();
  // Hour marks
  ctx.fillStyle = 'rgb(60, 60, 70)';
  for (let i = 0; i < 12; i++) {
    const angle = (i * Math.PI * 2) / 12 - Math.PI / 2;
    const markR = r - 2;
    ctx.fillRect(cx + Math.cos(angle) * markR - 0.5, cy + Math.sin(angle) * markR - 0.5, 1, 1);
  }
  // Hour hand
  ctx.strokeStyle = 'rgb(40, 40, 50)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(cx + 3, cy - 3);
  ctx.stroke();
  // Minute hand
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(cx - 1, cy - 5);
  ctx.stroke();
  // Center dot
  ctx.fillStyle = 'rgb(180, 50, 50)';
  ctx.beginPath();
  ctx.arc(cx, cy, 1, 0, Math.PI * 2);
  ctx.fill();
}

export function drawPictureFrame(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 20, h = 16;
  // Frame
  ctx.fillStyle = 'rgb(140, 110, 70)';
  ctx.fillRect(x, y, w, h);
  // Inner frame
  ctx.fillStyle = 'rgb(160, 130, 85)';
  ctx.fillRect(x + 1, y + 1, w - 2, h - 2);
  // "Picture" — abstract art
  ctx.fillStyle = 'rgb(180, 200, 220)';
  ctx.fillRect(x + 2, y + 2, w - 4, h - 4);
  // Abstract shapes
  ctx.fillStyle = 'rgb(100, 140, 180)';
  ctx.fillRect(x + 4, y + 5, 6, 4);
  ctx.fillStyle = 'rgb(200, 160, 80)';
  ctx.fillRect(x + 11, y + 4, 5, 6);
  ctx.fillStyle = 'rgb(160, 80, 80)';
  ctx.beginPath();
  ctx.arc(x + 7, y + 5, 2, 0, Math.PI * 2);
  ctx.fill();
  // Frame shadow
  ctx.fillStyle = 'rgba(0, 0, 0, 0.15)';
  ctx.fillRect(x + 1, y + h - 1, w - 1, 1);
  ctx.fillRect(x + w - 1, y + 1, 1, h - 1);
}

export function drawSimpleDesk(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  // Basic desk/table
  ctx.fillStyle = 'rgb(130, 95, 62)';
  safeRoundRect(ctx, x, y, w, h, 2);
  ctx.fill();
  // Highlight
  ctx.fillStyle = 'rgba(255, 255, 255, 0.06)';
  ctx.fillRect(x + 1, y, w - 2, 2);
  // Shadow
  ctx.fillStyle = 'rgba(0, 0, 0, 0.12)';
  ctx.fillRect(x + 1, y + h - 2, w - 2, 2);
  // Border
  ctx.strokeStyle = 'rgba(80, 60, 40, 0.4)';
  ctx.lineWidth = 1;
  safeRoundRect(ctx, x, y, w, h, 2);
  ctx.stroke();
}

// ── Animated screen content ──────────────────────────────────

/**
 * Draw animated "code" scrolling on a desk monitor when an agent is working.
 * When no occupant, show a subtle screensaver with color cycling.
 */
export function drawAnimatedMonitor(
  ctx: CanvasRenderingContext2D,
  mx: number, my: number, mw: number, mh: number,
  isOccupiedWorking: boolean, now: number
) {
  // Screen background
  ctx.fillStyle = 'rgb(18, 22, 30)';
  ctx.fillRect(mx, my, mw, mh);

  if (isOccupiedWorking) {
    // Scrolling code lines
    const scrollSpeed = 0.02; // pixels per ms
    const scrollOffset = (now * scrollSpeed) % 40; // cycle every 40 virtual lines
    const lineColors = [
      'rgb(120, 220, 150)', // green
      'rgb(100, 160, 240)', // blue
      'rgb(220, 220, 240)', // white
      'rgb(200, 180, 100)', // yellow
      'rgb(180, 120, 220)', // purple
    ];

    ctx.save();
    ctx.beginPath();
    ctx.rect(mx, my, mw, mh);
    ctx.clip();

    for (let i = 0; i < 8; i++) {
      const lineY = my + (i * 4 - scrollOffset % 4);
      if (lineY < my - 2 || lineY > my + mh) continue;

      const colorIdx = (i + Math.floor(scrollOffset / 4)) % lineColors.length;
      ctx.fillStyle = lineColors[colorIdx];

      // Vary line width for "code" look
      const seed = (i * 7 + Math.floor(now / 2000)) % 5;
      const lineW = 3 + seed * 2;
      const lineX = mx + 1 + (seed % 3);
      ctx.fillRect(lineX, lineY, Math.min(lineW, mw - 2), 1);

      // Sometimes a second segment (indented code)
      if (seed > 2) {
        ctx.fillStyle = lineColors[(colorIdx + 2) % lineColors.length];
        ctx.fillRect(lineX + lineW + 1, lineY, Math.min(3, mw - lineX - lineW - 2), 1);
      }
    }
    ctx.restore();
  } else {
    // Screensaver — subtle color cycling
    const hue = (now * 0.02) % 360;
    const r = Math.floor(40 + 20 * Math.sin((hue * Math.PI) / 180));
    const g = Math.floor(40 + 20 * Math.sin(((hue + 120) * Math.PI) / 180));
    const b = Math.floor(40 + 20 * Math.sin(((hue + 240) * Math.PI) / 180));
    ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
    ctx.fillRect(mx + 1, my + 1, mw - 2, mh - 2);

    // Floating pixel (screensaver dot)
    const dotX = mx + 2 + ((now * 0.015) % (mw - 4));
    const dotY = my + 2 + Math.sin(now * 0.003) * ((mh - 4) / 2) + (mh - 4) / 2;
    ctx.fillStyle = `rgb(${r + 60}, ${g + 60}, ${b + 60})`;
    ctx.fillRect(Math.floor(dotX), Math.floor(dotY), 2, 2);
  }
}

/**
 * Draw animated TV screen content based on nearby agent activities.
 */
export function drawAnimatedTv(
  ctx: CanvasRenderingContext2D,
  x: number, y: number, w: number, h: number,
  eng: OfficeEngine, now: number
) {
  // Check if any agent nearby is watching TV or playing games
  let hasViewer = false;
  let isGaming = false;
  for (const agent of eng.agents.values()) {
    if (!agent.idleActivity) continue;
    const dx = Math.abs(agent.position.x - (x + w / 2));
    const dy = Math.abs(agent.position.y - (y + h / 2));
    if (dx < 120 && dy < 80) {
      if (agent.idleActivity.includes('TV') || agent.idleActivity.includes('Watching')) {
        hasViewer = true;
      }
      if (agent.idleActivity.includes('video games')) {
        isGaming = true;
        hasViewer = true;
      }
    }
  }

  // Outer bezel
  ctx.fillStyle = 'rgb(25, 25, 32)';
  ctx.fillRect(x, y, w, h);

  // Screen area
  const sx = x + 2, sy = y + 2, sw = w - 4, sh = h - 4;

  if (isGaming) {
    // Pong game!
    ctx.fillStyle = 'rgb(10, 10, 20)';
    ctx.fillRect(sx, sy, sw, sh);

    // Paddles
    const paddle1Y = sy + 1 + Math.sin(now * 0.004) * (sh / 2 - 2) + sh / 2 - 2;
    const paddle2Y = sy + 1 + Math.sin(now * 0.005 + 1) * (sh / 2 - 2) + sh / 2 - 2;
    ctx.fillStyle = 'rgb(220, 220, 240)';
    ctx.fillRect(sx + 1, Math.floor(paddle1Y), 1, 3);
    ctx.fillRect(sx + sw - 2, Math.floor(paddle2Y), 1, 3);

    // Ball
    const ballPeriod = 1500;
    const ballT = (now % ballPeriod) / ballPeriod;
    const ballX = sx + 2 + ballT * (sw - 4);
    const ballY = sy + 1 + Math.sin(ballT * Math.PI * 3) * (sh / 2 - 1) + sh / 2 - 1;
    ctx.fillRect(Math.floor(ballX), Math.floor(ballY), 1, 1);

    // Center line (dashed)
    ctx.fillStyle = 'rgba(220, 220, 240, 0.3)';
    for (let dy2 = sy; dy2 < sy + sh; dy2 += 2) {
      ctx.fillRect(sx + Math.floor(sw / 2), dy2, 1, 1);
    }
  } else if (hasViewer) {
    // Animated colored bars (TV show)
    ctx.fillStyle = 'rgb(10, 10, 20)';
    ctx.fillRect(sx, sy, sw, sh);

    const barColors = [
      'rgb(200, 60, 60)', 'rgb(60, 180, 80)', 'rgb(60, 100, 220)',
      'rgb(220, 180, 40)', 'rgb(180, 60, 200)', 'rgb(60, 200, 200)',
    ];
    const barShift = Math.floor(now / 800) % barColors.length;
    const barW = Math.max(2, Math.floor(sw / barColors.length));
    for (let i = 0; i < barColors.length; i++) {
      const ci = (i + barShift) % barColors.length;
      ctx.fillStyle = barColors[ci];
      ctx.globalAlpha = 0.6 + Math.sin(now * 0.003 + i) * 0.2;
      ctx.fillRect(sx + i * barW, sy, barW, sh);
    }
    ctx.globalAlpha = 1;
  } else {
    // Static noise / standby
    ctx.fillStyle = 'rgb(30, 35, 50)';
    ctx.fillRect(sx, sy, sw, sh);
    // Dim static pixels
    for (let px2 = sx; px2 < sx + sw; px2 += 3) {
      for (let py2 = sy; py2 < sy + sh; py2 += 2) {
        const bright = 20 + ((px2 * 17 + py2 * 31 + Math.floor(now / 200)) % 30);
        ctx.fillStyle = `rgb(${bright}, ${bright}, ${bright + 10})`;
        ctx.fillRect(px2, py2, 2, 1);
      }
    }
  }

  // Screen glow
  ctx.fillStyle = 'rgba(100, 140, 200, 0.06)';
  ctx.fillRect(x - 2, y + h, w + 4, 4);
}

/**
 * Draw animated arcade machine screen.
 */
export function drawAnimatedArcade(
  ctx: CanvasRenderingContext2D,
  x: number, y: number, w: number, _h: number,
  eng: OfficeEngine, now: number, cabinetColor: string
) {
  // Check if any agent nearby is playing
  let hasPlayer = false;
  for (const agent of eng.agents.values()) {
    if (!agent.idleActivity) continue;
    const dx2 = Math.abs(agent.position.x - (x + w / 2));
    const dy2 = Math.abs(agent.position.y - (y + 22)); // control panel area
    if (dx2 < 40 && dy2 < 50 && agent.idleActivity.includes('video games')) {
      hasPlayer = true;
      break;
    }
  }

  // Screen area (upper portion of arcade — same position as static version)
  const sx = x + 3, sy = y + 3, sw = w - 6, sh = 18;

  ctx.fillStyle = 'rgb(15, 15, 20)';
  ctx.fillRect(sx, sy, sw, sh);

  if (hasPlayer) {
    // Active game: moving sprites
    const playerX = sx + 2 + Math.sin(now * 0.003) * 4 + 4;
    const playerY = sy + sh - 6;
    ctx.fillStyle = 'rgb(60, 220, 60)';
    ctx.fillRect(Math.floor(playerX), playerY, 4, 4);

    // Enemies moving
    for (let i = 0; i < 3; i++) {
      const ex = sx + 4 + ((now * 0.02 + i * 50) % (sw - 8));
      const ey = sy + 3 + i * 4;
      ctx.fillStyle = i % 2 === 0 ? 'rgb(220, 60, 60)' : 'rgb(220, 160, 40)';
      ctx.fillRect(Math.floor(ex), ey, 3, 3);
    }

    // Bullets
    const bulletY = playerY - 3 - ((now * 0.05) % 10);
    if (bulletY > sy) {
      ctx.fillStyle = 'rgb(255, 255, 100)';
      ctx.fillRect(Math.floor(playerX) + 1, Math.floor(bulletY), 1, 2);
    }

    // Score
    ctx.fillStyle = 'rgb(255, 255, 255)';
    ctx.fillRect(sx + 1, sy + 1, 6, 1);
  } else {
    // Attract screen — "INSERT COIN" blinking
    const blink = Math.floor(now / 600) % 2 === 0;
    if (blink) {
      // Simple text approximation with tiny pixel blocks
      ctx.fillStyle = 'rgb(255, 220, 60)';
      // "INSERT" - tiny block letters at top
      ctx.fillRect(sx + 3, sy + 3, 1, 3);  // I
      ctx.fillRect(sx + 5, sy + 3, 3, 1);  // N top
      ctx.fillRect(sx + 5, sy + 5, 3, 1);  // N bot
      ctx.fillRect(sx + 5, sy + 3, 1, 3);  // N left
      ctx.fillRect(sx + 7, sy + 3, 1, 3);  // N right
      // "COIN" below
      ctx.fillRect(sx + 3, sy + 8, 3, 1);  // C top
      ctx.fillRect(sx + 3, sy + 10, 3, 1); // C bot
      ctx.fillRect(sx + 3, sy + 8, 1, 3);  // C left
      ctx.fillRect(sx + 8, sy + 8, 1, 3);  // O left
      ctx.fillRect(sx + 10, sy + 8, 1, 3); // O right
      ctx.fillRect(sx + 8, sy + 8, 3, 1);  // O top
      ctx.fillRect(sx + 8, sy + 10, 3, 1); // O bot
    }

    // Color cycling border effect
    const hue = (now * 0.05) % 360;
    const r = Math.floor(128 + 127 * Math.sin((hue * Math.PI) / 180));
    const g = Math.floor(128 + 127 * Math.sin(((hue + 120) * Math.PI) / 180));
    const b = Math.floor(128 + 127 * Math.sin(((hue + 240) * Math.PI) / 180));
    ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, 0.4)`;
    ctx.lineWidth = 1;
    ctx.strokeRect(sx, sy, sw, sh);
  }
}

// ── Toaster fire animation ────────────────────────────────────

/** Track toaster fire state: maps toaster key -> { startTime, fireAt, fireEnd } */
const toasterFireState = new Map<string, { startTime: number; fireAt: number; fireEnd: number }>();

export function drawToasterFire(
  ctx: CanvasRenderingContext2D,
  toasterX: number, toasterY: number,
  eng: OfficeEngine, now: number
) {
  // Check if any agent nearby has "Toasting bread" activity
  let hasToaster = false;
  for (const agent of eng.agents.values()) {
    if (agent.idleActivity === 'Toasting bread') {
      const dx2 = Math.abs(agent.position.x - (toasterX + 7));
      const dy2 = Math.abs(agent.position.y - (toasterY + 6));
      if (dx2 < 60 && dy2 < 60) {
        hasToaster = true;
        break;
      }
    }
  }

  const key = `${toasterX},${toasterY}`;

  if (hasToaster) {
    let state = toasterFireState.get(key);
    if (!state) {
      // Start tracking — fire triggers after 5-10 seconds
      const fireDelay = 5000 + Math.random() * 5000;
      state = {
        startTime: now,
        fireAt: now + fireDelay,
        fireEnd: now + fireDelay + 3000 + Math.random() * 1000,
      };
      toasterFireState.set(key, state);
    }

    if (now >= state.fireAt && now < state.fireEnd) {
      // Draw fire! Flickering orange/red/yellow pixels rising
      const fireProgress = (now - state.fireAt) / (state.fireEnd - state.fireAt);
      const intensity = fireProgress < 0.3
        ? fireProgress / 0.3
        : fireProgress > 0.7
          ? 1 - (fireProgress - 0.7) / 0.3
          : 1;

      const fireColors = [
        'rgb(255, 100, 20)',
        'rgb(255, 160, 30)',
        'rgb(255, 60, 10)',
        'rgb(255, 200, 50)',
        'rgb(220, 40, 10)',
      ];

      // Fire particles rising from each slot
      for (let slot = 0; slot < 2; slot++) {
        const slotX = toasterX + 3 + slot * 6;
        for (let p = 0; p < 4; p++) {
          const seed = slot * 4 + p;
          const particlePhase = ((now * 0.005 + seed * 0.7) % 1);
          const py2 = toasterY - 2 - particlePhase * 10 * intensity;
          const px2 = slotX + Math.sin(now * 0.01 + seed * 2) * 2;
          const alpha = (1 - particlePhase) * intensity;
          if (alpha <= 0) continue;

          ctx.globalAlpha = alpha;
          ctx.fillStyle = fireColors[seed % fireColors.length];
          ctx.fillRect(Math.floor(px2), Math.floor(py2), 2, 2);
        }
      }

      // Glow effect beneath fire
      ctx.globalAlpha = 0.15 * intensity;
      ctx.fillStyle = 'rgb(255, 120, 30)';
      ctx.fillRect(toasterX - 2, toasterY - 4, 18, 6);
      ctx.globalAlpha = 1;
    } else if (now >= state.fireEnd) {
      // Fire is done, reset for next cycle
      const fireDelay = 5000 + Math.random() * 5000;
      state.startTime = now;
      state.fireAt = now + fireDelay;
      state.fireEnd = now + fireDelay + 3000 + Math.random() * 1000;
    }
  } else {
    toasterFireState.delete(key);
  }
}

// ── Ping pong ball animation ────────────────────────────────

export function drawPingPongBall(
  ctx: CanvasRenderingContext2D,
  eng: OfficeEngine, now: number
) {
  // Find paired agents at ping pong table
  for (const agent of eng.agents.values()) {
    if (!agent.pairedWith) continue;
    const partner = eng.agents.get(agent.pairedWith);
    if (!partner) continue;
    // Only draw once per pair (lower ID draws)
    if (agent.id > partner.id) continue;

    // Check they're in the ping pong area (break room, near table)
    const tableCenterX = 480;
    const tableCenterY = 579;
    const avgX = (agent.position.x + partner.position.x) / 2;
    const avgY = (agent.position.y + partner.position.y) / 2;
    if (Math.abs(avgX - tableCenterX) > 100 || Math.abs(avgY - tableCenterY) > 60) continue;

    // Ball bouncing between the two agents
    const leftX = Math.min(agent.position.x, partner.position.x) + 5;
    const rightX = Math.max(agent.position.x, partner.position.x) - 5;
    const speed = 200; // px/s
    const range = rightX - leftX;
    if (range <= 0) continue;

    const period = (range * 2) / speed; // time for full round trip
    const t = ((now / 1000) % period) / period;
    // Ping pong: 0->1->0 triangle wave
    const ballT = t < 0.5 ? t * 2 : 2 - t * 2;
    const ballX = leftX + ballT * range;
    const ballY = tableCenterY + Math.sin(now * 0.008) * 2; // slight wobble

    // Draw ball
    ctx.fillStyle = 'rgb(255, 255, 255)';
    ctx.beginPath();
    ctx.arc(Math.floor(ballX), Math.floor(ballY), 2, 0, Math.PI * 2);
    ctx.fill();

    // Ball shadow
    ctx.fillStyle = 'rgba(0, 0, 0, 0.15)';
    ctx.beginPath();
    ctx.ellipse(Math.floor(ballX), Math.floor(ballY) + 3, 2, 1, 0, 0, Math.PI * 2);
    ctx.fill();
  }
}

// ══════════════════════════════════════════════════════════════════
// ── Dog Park furniture renderers ─────────────────────────────────
// ══════════════════════════════════════════════════════════════════

export function drawDogBowl(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 16, h = 10;
  // Bowl outer rim
  ctx.fillStyle = 'rgb(180, 60, 60)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2);
  ctx.fill();
  // Inner bowl
  ctx.fillStyle = 'rgb(160, 45, 45)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2 - 2, h / 2 - 2, 0, 0, Math.PI * 2);
  ctx.fill();
  // Water surface
  ctx.fillStyle = 'rgba(80, 140, 220, 0.6)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2 + 1, w / 2 - 3, h / 2 - 3, 0, 0, Math.PI * 2);
  ctx.fill();
  // Water shine
  ctx.fillStyle = 'rgba(160, 210, 255, 0.3)';
  ctx.fillRect(x + 4, y + 3, 3, 1);
  // Rim highlight
  ctx.fillStyle = 'rgb(200, 80, 80)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + 2, w / 2 - 1, 2, 0, Math.PI, Math.PI * 2);
  ctx.fill();
}

export function drawFireHydrant(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 14, h = 22;
  // Base plate
  ctx.fillStyle = 'rgb(160, 30, 30)';
  ctx.fillRect(x + 1, y + h - 4, w - 2, 4);
  // Body
  ctx.fillStyle = 'rgb(200, 40, 40)';
  ctx.fillRect(x + 3, y + 6, 8, h - 10);
  // Top dome
  ctx.fillStyle = 'rgb(210, 50, 50)';
  safeRoundRect(ctx, x + 2, y, 10, 8, 3);
  ctx.fill();
  // Cap on top
  ctx.fillStyle = 'rgb(180, 35, 35)';
  ctx.fillRect(x + 4, y - 1, 6, 3);
  // Side nozzles
  ctx.fillStyle = 'rgb(180, 35, 35)';
  ctx.fillRect(x, y + 8, 4, 4);
  ctx.fillRect(x + w - 4, y + 8, 4, 4);
  // Nozzle caps
  ctx.fillStyle = 'rgb(160, 160, 170)';
  ctx.fillRect(x, y + 9, 2, 2);
  ctx.fillRect(x + w - 2, y + 9, 2, 2);
  // Body highlight
  ctx.fillStyle = 'rgb(230, 70, 70)';
  ctx.fillRect(x + 4, y + 7, 2, h - 12);
  // Center bolt
  ctx.fillStyle = 'rgb(160, 160, 170)';
  ctx.fillRect(x + 6, y + 12, 2, 2);
  // Shadow
  ctx.fillStyle = 'rgb(140, 25, 25)';
  ctx.fillRect(x + 9, y + 7, 1, h - 12);
}

export function drawDogHouse(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 36, h = 30;
  // Body (front face)
  ctx.fillStyle = 'rgb(160, 110, 60)';
  ctx.fillRect(x + 2, y + 10, w - 4, h - 10);
  // Roof — A-frame triangle
  ctx.fillStyle = 'rgb(140, 50, 40)';
  ctx.beginPath();
  ctx.moveTo(x, y + 12);
  ctx.lineTo(x + w / 2, y);
  ctx.lineTo(x + w, y + 12);
  ctx.closePath();
  ctx.fill();
  // Roof highlight
  ctx.fillStyle = 'rgb(160, 65, 50)';
  ctx.beginPath();
  ctx.moveTo(x + 2, y + 12);
  ctx.lineTo(x + w / 2, y + 2);
  ctx.lineTo(x + w / 2, y);
  ctx.lineTo(x, y + 12);
  ctx.closePath();
  ctx.fill();
  // Doorway (dark arch)
  ctx.fillStyle = 'rgb(40, 30, 20)';
  ctx.beginPath();
  ctx.arc(x + w / 2, y + h - 8, 8, Math.PI, Math.PI * 2);
  ctx.fillRect(x + w / 2 - 8, y + h - 8, 16, 8);
  ctx.fill();
  // Wood plank lines
  ctx.fillStyle = 'rgba(0, 0, 0, 0.1)';
  ctx.fillRect(x + 2, y + 16, w - 4, 1);
  ctx.fillRect(x + 2, y + 22, w - 4, 1);
  // Name plate above door
  ctx.fillStyle = 'rgb(200, 180, 140)';
  ctx.fillRect(x + w / 2 - 6, y + 11, 12, 4);
  // Shadow under house
  ctx.fillStyle = 'rgba(0, 0, 0, 0.15)';
  ctx.fillRect(x + 3, y + h, w - 6, 2);
}

export function drawAgilityHoop(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 24, h = 32;
  // Stands (two vertical posts)
  ctx.fillStyle = 'rgb(180, 140, 60)';
  ctx.fillRect(x + 2, y + 8, 4, h - 8);
  ctx.fillRect(x + w - 6, y + 8, 4, h - 8);
  // Base plates
  ctx.fillStyle = 'rgb(150, 115, 50)';
  ctx.fillRect(x, y + h - 3, 8, 3);
  ctx.fillRect(x + w - 8, y + h - 3, 8, 3);
  // Hoop ring (circle)
  ctx.strokeStyle = 'rgb(220, 80, 40)';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.arc(x + w / 2, y + 10, 9, 0, Math.PI * 2);
  ctx.stroke();
  // Inner hoop highlight
  ctx.strokeStyle = 'rgb(240, 120, 60)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.arc(x + w / 2, y + 10, 7, 0, Math.PI * 2);
  ctx.stroke();
  // Cross-bars connecting posts to hoop
  ctx.fillStyle = 'rgb(180, 140, 60)';
  ctx.fillRect(x + 5, y + 8, 3, 2);
  ctx.fillRect(x + w - 8, y + 8, 3, 2);
}

export function drawAgilityRamp(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 40, h = 24;
  // Ramp surface — triangle shape
  ctx.fillStyle = 'rgb(120, 160, 60)';
  ctx.beginPath();
  ctx.moveTo(x, y + h);
  ctx.lineTo(x + w / 2, y);
  ctx.lineTo(x + w, y + h);
  ctx.closePath();
  ctx.fill();
  // Ramp highlight (left face)
  ctx.fillStyle = 'rgb(140, 180, 70)';
  ctx.beginPath();
  ctx.moveTo(x, y + h);
  ctx.lineTo(x + w / 2, y);
  ctx.lineTo(x + w / 2, y + h);
  ctx.closePath();
  ctx.fill();
  // Grip strips (horizontal lines on surface)
  ctx.fillStyle = 'rgba(0, 0, 0, 0.15)';
  for (let i = 1; i < 5; i++) {
    const stripY = y + (h * i) / 5;
    const leftEdge = x + (w / 2) * (1 - i / 5);
    const rightEdge = x + w - (w / 2) * (1 - i / 5);
    ctx.fillRect(leftEdge + 2, stripY, rightEdge - leftEdge - 4, 1);
  }
  // Base
  ctx.fillStyle = 'rgb(100, 140, 50)';
  ctx.fillRect(x, y + h - 2, w, 2);
}

export function drawPondWater(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  // Water body (organic oval shape)
  ctx.fillStyle = 'rgb(50, 100, 160)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2);
  ctx.fill();
  // Deeper center
  ctx.fillStyle = 'rgb(35, 80, 140)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2 + 2, w / 3, h / 3, 0, 0, Math.PI * 2);
  ctx.fill();
  // Shore/edge highlight
  ctx.strokeStyle = 'rgb(90, 140, 80)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2 + 1, h / 2 + 1, 0, 0, Math.PI * 2);
  ctx.stroke();
  // Ripple lines
  ctx.strokeStyle = 'rgba(120, 180, 220, 0.3)';
  ctx.lineWidth = 1;
  for (let i = 0; i < 3; i++) {
    const rx = x + w * 0.3 + i * w * 0.15;
    const ry = y + h * 0.35 + i * 4;
    ctx.beginPath();
    ctx.ellipse(rx, ry, 6 + i * 2, 2, 0.2, 0, Math.PI * 2);
    ctx.stroke();
  }
  // Lily pad
  ctx.fillStyle = 'rgb(60, 130, 50)';
  ctx.beginPath();
  ctx.arc(x + w * 0.65, y + h * 0.4, 4, 0.3, Math.PI * 2);
  ctx.fill();
  // Tiny flower on lily pad
  ctx.fillStyle = 'rgb(240, 200, 220)';
  ctx.fillRect(x + w * 0.65 - 1, y + h * 0.4 - 1, 2, 2);
}

export function drawTree(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const trunkW = 8, trunkH = 16;
  const crownR = 16;
  // Shadow on ground
  ctx.fillStyle = 'rgba(0, 0, 0, 0.1)';
  ctx.beginPath();
  ctx.ellipse(x + trunkW / 2, y + trunkH + crownR + 2, crownR - 2, 4, 0, 0, Math.PI * 2);
  ctx.fill();
  // Trunk
  ctx.fillStyle = 'rgb(110, 80, 45)';
  ctx.fillRect(x, y + crownR, trunkW, trunkH);
  // Trunk bark detail
  ctx.fillStyle = 'rgb(90, 65, 35)';
  ctx.fillRect(x + 2, y + crownR + 3, 2, 4);
  ctx.fillRect(x + 5, y + crownR + 8, 2, 3);
  // Trunk highlight
  ctx.fillStyle = 'rgb(130, 95, 55)';
  ctx.fillRect(x, y + crownR, 2, trunkH);
  // Crown (layered circles for depth)
  ctx.fillStyle = 'rgb(45, 110, 40)';
  ctx.beginPath();
  ctx.arc(x + trunkW / 2, y + crownR / 2, crownR, 0, Math.PI * 2);
  ctx.fill();
  // Lighter layer
  ctx.fillStyle = 'rgb(60, 135, 50)';
  ctx.beginPath();
  ctx.arc(x + trunkW / 2 - 3, y + crownR / 2 - 2, crownR - 4, 0, Math.PI * 2);
  ctx.fill();
  // Highlight spots
  ctx.fillStyle = 'rgb(80, 160, 65)';
  ctx.beginPath();
  ctx.arc(x + trunkW / 2 - 5, y + crownR / 2 - 5, 5, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(x + trunkW / 2 + 4, y + crownR / 2 - 3, 4, 0, Math.PI * 2);
  ctx.fill();
}

export function drawBench(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 40, h = 18;
  // Legs (dark metal)
  ctx.fillStyle = 'rgb(60, 60, 65)';
  ctx.fillRect(x + 3, y + 8, 3, h - 8);
  ctx.fillRect(x + w - 6, y + 8, 3, h - 8);
  // Seat slats (warm wood)
  ctx.fillStyle = 'rgb(150, 110, 60)';
  ctx.fillRect(x, y + 6, w, 4);
  // Slat gap
  ctx.fillStyle = 'rgb(120, 85, 45)';
  ctx.fillRect(x, y + 8, w, 1);
  // Seat highlight
  ctx.fillStyle = 'rgb(170, 130, 75)';
  ctx.fillRect(x + 1, y + 6, w - 2, 1);
  // Back rest slats
  ctx.fillStyle = 'rgb(145, 105, 55)';
  ctx.fillRect(x + 2, y, w - 4, 3);
  ctx.fillRect(x + 2, y + 3, w - 4, 2);
  // Back rest highlight
  ctx.fillStyle = 'rgb(165, 125, 70)';
  ctx.fillRect(x + 3, y, w - 6, 1);
  // Foot pads
  ctx.fillStyle = 'rgb(50, 50, 55)';
  ctx.fillRect(x + 2, y + h - 1, 5, 1);
  ctx.fillRect(x + w - 7, y + h - 1, 5, 1);
}

export function drawFence(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  const postSpacing = 16;
  const postW = 4;
  const railH = 3;
  // Posts
  ctx.fillStyle = 'rgb(140, 105, 60)';
  for (let px2 = x; px2 < x + w; px2 += postSpacing) {
    ctx.fillRect(px2, y, postW, h);
    // Post cap
    ctx.fillStyle = 'rgb(160, 120, 70)';
    ctx.fillRect(px2 - 1, y - 2, postW + 2, 3);
    ctx.fillStyle = 'rgb(140, 105, 60)';
  }
  // Top rail
  ctx.fillStyle = 'rgb(150, 115, 65)';
  ctx.fillRect(x, y + 4, w, railH);
  // Bottom rail
  ctx.fillRect(x, y + h - 6, w, railH);
  // Rail highlights
  ctx.fillStyle = 'rgb(170, 135, 80)';
  ctx.fillRect(x, y + 4, w, 1);
  ctx.fillRect(x, y + h - 6, w, 1);
  // Rail shadows
  ctx.fillStyle = 'rgb(120, 88, 48)';
  ctx.fillRect(x, y + 4 + railH - 1, w, 1);
  ctx.fillRect(x, y + h - 6 + railH - 1, w, 1);
}

export function drawBallLauncher(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 20, h = 24;
  // Base/body (boxy machine)
  ctx.fillStyle = 'rgb(70, 130, 70)';
  safeRoundRect(ctx, x + 2, y + 8, w - 4, h - 8, 2);
  ctx.fill();
  // Body highlight
  ctx.fillStyle = 'rgb(85, 150, 85)';
  ctx.fillRect(x + 3, y + 9, w - 6, 2);
  // Launch tube (angled up)
  ctx.fillStyle = 'rgb(80, 80, 88)';
  ctx.save();
  ctx.translate(x + w / 2, y + 10);
  ctx.rotate(-0.4);
  ctx.fillRect(-3, -12, 6, 14);
  // Tube opening
  ctx.fillStyle = 'rgb(50, 50, 58)';
  ctx.fillRect(-2, -12, 4, 2);
  ctx.restore();
  // Tennis ball in hopper (visible through slot)
  ctx.fillStyle = 'rgb(200, 220, 50)';
  ctx.beginPath();
  ctx.arc(x + w / 2, y + 18, 3, 0, Math.PI * 2);
  ctx.fill();
  // Ball highlight
  ctx.fillStyle = 'rgb(230, 245, 80)';
  ctx.fillRect(x + w / 2 - 1, y + 16, 2, 1);
  // Control panel
  ctx.fillStyle = 'rgb(55, 55, 62)';
  ctx.fillRect(x + 4, y + h - 5, 6, 4);
  // LED
  ctx.fillStyle = 'rgb(80, 220, 80)';
  ctx.fillRect(x + 5, y + h - 4, 2, 2);
  // Feet
  ctx.fillStyle = 'rgb(60, 60, 68)';
  ctx.fillRect(x + 2, y + h, 4, 2);
  ctx.fillRect(x + w - 6, y + h, 4, 2);
}

// ══════════════════════════════════════════════════════════════════
// ── Gym furniture renderers ──────────────────────────────────────
// ══════════════════════════════════════════════════════════════════

export function drawTreadmill(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 36, h = 20;
  // Belt surface (dark rubber)
  ctx.fillStyle = 'rgb(45, 45, 50)';
  safeRoundRect(ctx, x, y + 6, w, h - 6, 2);
  ctx.fill();
  // Belt track lines
  ctx.fillStyle = 'rgb(55, 55, 60)';
  for (let i = 0; i < 4; i++) {
    ctx.fillRect(x + 2, y + 9 + i * 3, w - 4, 1);
  }
  // Side rails
  ctx.fillStyle = 'rgb(160, 160, 170)';
  ctx.fillRect(x, y + 6, 2, h - 6);
  ctx.fillRect(x + w - 2, y + 6, 2, h - 6);
  // Uprights (handlebars)
  ctx.fillStyle = 'rgb(140, 140, 150)';
  ctx.fillRect(x + 2, y, 3, 8);
  ctx.fillRect(x + w - 5, y, 3, 8);
  // Console/screen at top
  ctx.fillStyle = 'rgb(30, 30, 38)';
  ctx.fillRect(x + 8, y - 2, 20, 6);
  // Screen glow
  ctx.fillStyle = 'rgb(60, 180, 80)';
  ctx.fillRect(x + 10, y - 1, 16, 4);
  // Speed readout
  ctx.fillStyle = 'rgb(40, 140, 60)';
  ctx.fillRect(x + 12, y, 4, 2);
  ctx.fillRect(x + 18, y, 6, 2);
  // Handle bar across top
  ctx.fillStyle = 'rgb(150, 150, 160)';
  ctx.fillRect(x + 4, y, w - 8, 2);
}

export function drawWeightRack(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 32, h = 36;
  // Frame (metal uprights)
  ctx.fillStyle = 'rgb(100, 100, 110)';
  ctx.fillRect(x, y, 3, h);
  ctx.fillRect(x + w - 3, y, 3, h);
  // Shelves (3 tiers)
  ctx.fillStyle = 'rgb(90, 90, 100)';
  for (let i = 0; i < 3; i++) {
    const sy = y + 4 + i * 11;
    ctx.fillRect(x + 2, sy, w - 4, 2);
  }
  // Dumbbells on shelves (pairs, different sizes)
  const dbColors = ['rgb(60, 60, 68)', 'rgb(70, 70, 78)', 'rgb(55, 55, 63)'];
  for (let i = 0; i < 3; i++) {
    const sy = y + 2 + i * 11;
    const dbW = 8 - i;
    ctx.fillStyle = dbColors[i];
    // Left dumbbell
    ctx.fillRect(x + 5, sy, dbW, 3);
    // Handle
    ctx.fillStyle = 'rgb(140, 140, 150)';
    ctx.fillRect(x + 5 + 2, sy + 1, dbW - 4, 1);
    // Right dumbbell
    ctx.fillStyle = dbColors[i];
    ctx.fillRect(x + w - 5 - dbW, sy, dbW, 3);
    ctx.fillStyle = 'rgb(140, 140, 150)';
    ctx.fillRect(x + w - 5 - dbW + 2, sy + 1, dbW - 4, 1);
  }
  // Frame top bar
  ctx.fillStyle = 'rgb(110, 110, 120)';
  ctx.fillRect(x, y, w, 2);
  // Frame shadow
  ctx.fillStyle = 'rgb(80, 80, 90)';
  ctx.fillRect(x + 1, y + h - 1, w - 2, 1);
}

export function drawPunchingBag(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 18, h = 30;
  // Ceiling mount chain
  ctx.fillStyle = 'rgb(140, 140, 150)';
  ctx.fillRect(x + w / 2 - 1, y, 2, 6);
  // Chain links
  ctx.fillStyle = 'rgb(120, 120, 130)';
  ctx.fillRect(x + w / 2 - 2, y + 1, 1, 2);
  ctx.fillRect(x + w / 2 + 1, y + 3, 1, 2);
  // Bag top (narrower)
  ctx.fillStyle = 'rgb(160, 50, 40)';
  safeRoundRect(ctx, x + 3, y + 5, w - 6, 6, 3);
  ctx.fill();
  // Bag body (main cylinder)
  ctx.fillStyle = 'rgb(170, 55, 45)';
  safeRoundRect(ctx, x + 1, y + 9, w - 2, h - 14, 4);
  ctx.fill();
  // Bag bottom (rounded)
  ctx.fillStyle = 'rgb(155, 48, 38)';
  safeRoundRect(ctx, x + 2, y + h - 8, w - 4, 8, 4);
  ctx.fill();
  // Highlight stripe
  ctx.fillStyle = 'rgb(190, 70, 60)';
  ctx.fillRect(x + 3, y + 10, 3, h - 16);
  // Seam line
  ctx.fillStyle = 'rgba(0, 0, 0, 0.15)';
  ctx.fillRect(x + w / 2, y + 7, 1, h - 12);
  // Shadow
  ctx.fillStyle = 'rgb(140, 42, 32)';
  ctx.fillRect(x + w - 4, y + 10, 2, h - 16);
}

export function drawYogaMat(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 36, h = 14;
  // Mat body (flat rectangle)
  ctx.fillStyle = 'rgb(120, 80, 160)';
  safeRoundRect(ctx, x, y, w, h, 2);
  ctx.fill();
  // Mat texture — subtle grid
  ctx.fillStyle = 'rgba(255, 255, 255, 0.04)';
  for (let mx2 = x + 3; mx2 < x + w - 2; mx2 += 4) {
    ctx.fillRect(mx2, y + 1, 1, h - 2);
  }
  for (let my = y + 3; my < y + h - 2; my += 3) {
    ctx.fillRect(x + 1, my, w - 2, 1);
  }
  // Edge highlight
  ctx.fillStyle = 'rgb(140, 95, 180)';
  ctx.fillRect(x + 1, y, w - 2, 1);
  // Edge shadow
  ctx.fillStyle = 'rgb(100, 65, 140)';
  ctx.fillRect(x + 1, y + h - 1, w - 2, 1);
  // Rolled end (if mat is partially rolled)
  ctx.fillStyle = 'rgb(110, 72, 150)';
  ctx.beginPath();
  ctx.ellipse(x + w - 2, y + h / 2, 3, h / 2, 0, 0, Math.PI * 2);
  ctx.fill();
}

export function drawExerciseBall(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const r = 14;
  // Shadow
  ctx.fillStyle = 'rgba(0, 0, 0, 0.12)';
  ctx.beginPath();
  ctx.ellipse(x + r, y + r * 2, r - 2, 3, 0, 0, Math.PI * 2);
  ctx.fill();
  // Ball body
  ctx.fillStyle = 'rgb(70, 140, 200)';
  ctx.beginPath();
  ctx.arc(x + r, y + r, r, 0, Math.PI * 2);
  ctx.fill();
  // Highlight (upper left)
  ctx.fillStyle = 'rgb(100, 170, 230)';
  ctx.beginPath();
  ctx.arc(x + r - 4, y + r - 4, r / 2, 0, Math.PI * 2);
  ctx.fill();
  // Specular
  ctx.fillStyle = 'rgba(255, 255, 255, 0.2)';
  ctx.beginPath();
  ctx.arc(x + r - 5, y + r - 6, 3, 0, Math.PI * 2);
  ctx.fill();
  // Equator stripe (subtle)
  ctx.strokeStyle = 'rgba(50, 120, 180, 0.4)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.ellipse(x + r, y + r, r - 1, r / 3, 0, 0, Math.PI * 2);
  ctx.stroke();
  // Bottom shading
  ctx.fillStyle = 'rgb(55, 115, 170)';
  ctx.beginPath();
  ctx.arc(x + r + 2, y + r + 4, r / 2, 0, Math.PI * 2);
  ctx.fill();
}

export function drawLocker(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 16, h = 36;
  // Body
  ctx.fillStyle = 'rgb(140, 150, 165)';
  ctx.fillRect(x, y, w, h);
  // Door panel (inset)
  ctx.fillStyle = 'rgb(150, 160, 175)';
  ctx.fillRect(x + 2, y + 2, w - 4, h - 4);
  // Vent slits at top
  ctx.fillStyle = 'rgb(110, 120, 135)';
  for (let i = 0; i < 3; i++) {
    ctx.fillRect(x + 4, y + 4 + i * 3, w - 8, 1);
  }
  // Handle
  ctx.fillStyle = 'rgb(180, 180, 190)';
  ctx.fillRect(x + w - 5, y + h / 2 - 3, 2, 6);
  // Lock
  ctx.fillStyle = 'rgb(200, 180, 60)';
  ctx.fillRect(x + w - 5, y + h / 2, 2, 2);
  // Number plate
  ctx.fillStyle = 'rgb(200, 200, 210)';
  ctx.fillRect(x + 4, y + 14, 6, 4);
  // Top edge highlight
  ctx.fillStyle = 'rgb(160, 170, 185)';
  ctx.fillRect(x, y, w, 1);
  // Bottom shadow
  ctx.fillStyle = 'rgb(120, 130, 145)';
  ctx.fillRect(x, y + h - 1, w, 1);
  // Side shadow
  ctx.fillStyle = 'rgb(125, 135, 150)';
  ctx.fillRect(x + w - 1, y, 1, h);
}

export function drawMirror(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  // Frame
  ctx.fillStyle = 'rgb(160, 160, 170)';
  ctx.fillRect(x, y, w, h);
  // Mirror surface (reflective light blue)
  ctx.fillStyle = 'rgb(180, 200, 220)';
  ctx.fillRect(x + 2, y + 2, w - 4, h - 4);
  // Reflection streaks
  ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
  ctx.fillRect(x + 4, y + 3, 2, h - 8);
  ctx.fillRect(x + 8, y + 4, 1, h - 10);
  // Bottom reflection (darker)
  ctx.fillStyle = 'rgba(150, 170, 190, 0.3)';
  ctx.fillRect(x + 2, y + h - 6, w - 4, 3);
  // Frame highlight
  ctx.fillStyle = 'rgb(175, 175, 185)';
  ctx.fillRect(x, y, w, 1);
  ctx.fillRect(x, y, 1, h);
  // Frame shadow
  ctx.fillStyle = 'rgb(140, 140, 150)';
  ctx.fillRect(x + w - 1, y, 1, h);
  ctx.fillRect(x, y + h - 1, w, 1);
}

export function drawWaterFountain(ctx: CanvasRenderingContext2D, x: number, y: number) {
  const w = 16, h = 24;
  // Wall mount plate
  ctx.fillStyle = 'rgb(160, 165, 175)';
  ctx.fillRect(x + 1, y, w - 2, 4);
  // Body
  ctx.fillStyle = 'rgb(180, 185, 195)';
  safeRoundRect(ctx, x, y + 3, w, h - 6, 3);
  ctx.fill();
  // Basin (top bowl)
  ctx.fillStyle = 'rgb(150, 155, 165)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + 8, w / 2 - 1, 4, 0, 0, Math.PI * 2);
  ctx.fill();
  // Water in basin
  ctx.fillStyle = 'rgba(80, 150, 220, 0.4)';
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + 9, w / 2 - 3, 2, 0, 0, Math.PI * 2);
  ctx.fill();
  // Spout
  ctx.fillStyle = 'rgb(170, 175, 185)';
  ctx.fillRect(x + w / 2 - 2, y + 4, 4, 3);
  // Water arc (tiny)
  ctx.strokeStyle = 'rgba(100, 180, 240, 0.5)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.arc(x + w / 2 + 2, y + 5, 3, Math.PI * 0.8, Math.PI * 1.5);
  ctx.stroke();
  // Push button
  ctx.fillStyle = 'rgb(200, 200, 210)';
  ctx.fillRect(x + w - 4, y + 12, 3, 3);
  // Drain
  ctx.fillStyle = 'rgb(100, 105, 115)';
  ctx.beginPath();
  ctx.arc(x + w / 2, y + h - 6, 2, 0, Math.PI * 2);
  ctx.fill();
  // Bottom edge
  ctx.fillStyle = 'rgb(150, 155, 165)';
  ctx.fillRect(x + 2, y + h - 3, w - 4, 2);
}

// ══════════════════════════════════════════════════════════════════
// ── Sprite Street bedroom furniture renderers ────────────────────
// ══════════════════════════════════════════════════════════════════

/** Bed — rectangular with pillow, colored blanket */
function drawBed(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, color: string) {
  // Bed frame (dark wood)
  ctx.fillStyle = 'rgb(90, 65, 40)';
  ctx.fillRect(x, y, w, h);
  // Mattress (slightly inset)
  ctx.fillStyle = 'rgb(230, 225, 215)';
  ctx.fillRect(x + 3, y + 3, w - 6, h - 6);
  // Blanket (bottom 60%, colored to sprite)
  ctx.fillStyle = color;
  ctx.fillRect(x + 3, y + h * 0.4, w - 6, h * 0.6 - 3);
  // Blanket fold line
  ctx.fillStyle = 'rgba(0,0,0,0.15)';
  ctx.fillRect(x + 3, y + h * 0.4, w - 6, 2);
  // Pillow (top)
  ctx.fillStyle = 'rgb(240, 238, 230)';
  ctx.fillRect(x + 6, y + 6, w - 12, h * 0.3);
  // Pillow shadow
  ctx.fillStyle = 'rgba(0,0,0,0.08)';
  ctx.fillRect(x + 6, y + 6 + h * 0.25, w - 12, 2);
}

/** Closet — tall rectangle with doors and knob */
function drawCloset(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  // Body
  ctx.fillStyle = 'rgb(140, 110, 75)';
  ctx.fillRect(x, y, w, h);
  // Top edge
  ctx.fillStyle = 'rgb(160, 130, 90)';
  ctx.fillRect(x, y, w, 2);
  // Door divider line (center vertical)
  ctx.fillStyle = 'rgb(110, 85, 55)';
  ctx.fillRect(x + w / 2 - 1, y + 4, 2, h - 8);
  // Door knobs
  ctx.fillStyle = 'rgb(200, 180, 120)';
  ctx.fillRect(x + w / 2 - 4, y + h / 2, 2, 3);
  ctx.fillRect(x + w / 2 + 2, y + h / 2, 2, 3);
  // Shadow at bottom
  ctx.fillStyle = 'rgba(0,0,0,0.12)';
  ctx.fillRect(x, y + h - 2, w, 2);
}

/** Rug — flat colored rectangle (non-blocking) */
function drawRug(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, color: string) {
  // Rug body
  ctx.fillStyle = color;
  ctx.fillRect(x, y, w, h);
  // Border (slightly darker)
  ctx.strokeStyle = 'rgba(0,0,0,0.2)';
  ctx.lineWidth = 1;
  ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
  // Inner pattern line
  ctx.strokeStyle = 'rgba(255,255,255,0.15)';
  ctx.strokeRect(x + 3.5, y + 3.5, w - 7, h - 7);
}
