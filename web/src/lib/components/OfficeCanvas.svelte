<script lang="ts">
  import { SCENE_WIDTH, SCENE_HEIGHT, AREAS, DOOR_POSITION } from '../office/layout';
  import { renderCharacterAnimated, getCharacterSize } from '../office/pixel-art';
  import type { OfficeEngine, EngineAgent } from '../office/engine';
  import type { OfficeArea, Furniture } from '../office/types';

  interface Props {
    engine: OfficeEngine;
    desks: Array<{ id: number; position: { x: number; y: number }; occupantId: string | null; label?: string; width?: number; height?: number }>;
    onAgentClick?: (agentId: string) => void;
  }

  let { engine, desks, onAgentClick }: Props = $props();

  let canvasEl: HTMLCanvasElement | undefined = $state();
  let containerEl: HTMLDivElement | undefined = $state();
  let scale = $state(1);
  let isMobile = $state(false);

  // Mobile room canvases — keyed by area type
  let roomCanvasEls: Record<string, HTMLCanvasElement | undefined> = $state({});

  // Room display order for mobile layout
  const ROOM_ORDER: Array<{ type: string; label: string }> = [
    { type: 'mainOffice', label: 'Main Office' },
    { type: 'strategyRoom', label: 'Strategy Room' },
    { type: 'breakRoom', label: 'Break Room' },
    { type: 'kitchen', label: 'Kitchen' },
  ];

  // ── Responsive scaling ─────────────────────────────────────

  function updateScale() {
    if (!containerEl) return;
    // Use window.innerWidth for mobile detection — the container itself may be
    // inflated by the canvas dimensions, giving a false reading.
    isMobile = window.innerWidth < 640;
    if (!isMobile) {
      const { clientWidth, clientHeight } = containerEl;
      const scaleX = clientWidth / SCENE_WIDTH;
      const scaleY = clientHeight / SCENE_HEIGHT;
      scale = Math.min(scaleX, scaleY);
    }
  }

  $effect(() => {
    if (!containerEl) return;
    const observer = new ResizeObserver(() => updateScale());
    observer.observe(containerEl);
    // Also listen for window resize to catch viewport changes (e.g. orientation)
    window.addEventListener('resize', updateScale);
    updateScale();
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', updateScale);
    };
  });

  // ── Engine render loop ─────────────────────────────────────

  $effect(() => {
    if (isMobile) {
      // Mobile: render each room canvas separately
      engine.onRender = () => {
        for (const room of ROOM_ORDER) {
          const canvas = roomCanvasEls[room.type];
          if (!canvas) continue;
          const ctx = canvas.getContext('2d');
          if (!ctx) continue;
          const area = AREAS.find(a => a.type === room.type);
          if (!area) continue;
          renderRoom(ctx, engine, area);
        }
      };

      engine.start();

      return () => {
        engine.onRender = null;
        engine.stop();
      };
    } else {
      if (!canvasEl) return;
      const ctx = canvasEl.getContext('2d');
      if (!ctx) return;

      engine.onRender = () => {
        renderScene(ctx, engine);
      };

      engine.start();

      return () => {
        engine.onRender = null;
        engine.stop();
      };
    }
  });

  // ── Click handler ──────────────────────────────────────────

  function safeRoundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
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

  function handleClick(event: MouseEvent) {
    if (!canvasEl || !onAgentClick) return;
    const rect = canvasEl.getBoundingClientRect();
    const x = (event.clientX - rect.left) / scale;
    const y = (event.clientY - rect.top) / scale;

    const agent = engine.getAgentAtPoint({ x, y });
    if (agent) {
      onAgentClick(agent.id);
    }
  }

  function handleRoomClick(event: MouseEvent, area: OfficeArea) {
    if (!onAgentClick) return;
    const canvas = event.currentTarget as HTMLCanvasElement;
    const rect = canvas.getBoundingClientRect();
    const roomScale = rect.width / area.bounds.width;
    // Convert click coords back to scene space
    const sceneX = (event.clientX - rect.left) / roomScale + area.bounds.x;
    const sceneY = (event.clientY - rect.top) / roomScale + area.bounds.y;

    const agent = engine.getAgentAtPoint({ x: sceneX, y: sceneY });
    if (agent) {
      onAgentClick(agent.id);
    }
  }

  // ── Pixel art helper ─────────────────────────────────────

  /** Draw a single "pixel" at grid position — the foundation of all pixel art */
  function px(ctx: CanvasRenderingContext2D, baseX: number, baseY: number, col: number, row: number, color: string, size: number = 2) {
    ctx.fillStyle = color;
    ctx.fillRect(baseX + col * size, baseY + row * size, size, size);
  }

  // ── Floor pattern rendering ────────────────────────────────

  function drawFloorPattern(ctx: CanvasRenderingContext2D, area: OfficeArea) {
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
    }

    ctx.restore();
  }

  // ── Wall rendering ─────────────────────────────────────────

  function drawWalls(ctx: CanvasRenderingContext2D) {
    const wallThickness = 5;
    const wallColor = 'rgb(72, 72, 82)';
    const wallHighlight = 'rgb(82, 82, 92)';
    const wallShadow = 'rgb(55, 55, 65)';

    // ── Outer walls ──
    // Top wall
    ctx.fillStyle = wallColor;
    ctx.fillRect(0, 0, 800, wallThickness);
    ctx.fillStyle = wallHighlight;
    ctx.fillRect(0, 0, 800, 1);

    // Left wall
    ctx.fillStyle = wallColor;
    ctx.fillRect(0, 0, wallThickness, 600);
    ctx.fillStyle = wallHighlight;
    ctx.fillRect(0, 0, 1, 600);

    // Right wall (with door gap)
    ctx.fillStyle = wallColor;
    ctx.fillRect(795, 0, wallThickness, 180);   // above door
    ctx.fillStyle = wallColor;
    ctx.fillRect(795, 225, wallThickness, 175);  // between door and break room
    ctx.fillStyle = wallColor;
    ctx.fillRect(795, 400, wallThickness, 200); // break room right wall

    // Bottom wall
    ctx.fillStyle = wallColor;
    ctx.fillRect(0, 595, 800, wallThickness);
    ctx.fillStyle = wallShadow;
    ctx.fillRect(0, 599, 800, 1);

    // ── Interior walls ──

    // Vertical divider: strategy room / kitchen | main office
    // With doorway gaps
    ctx.fillStyle = wallColor;
    ctx.fillRect(225, 0, wallThickness, 120);      // top portion
    ctx.fillStyle = wallHighlight;
    ctx.fillRect(225, 0, 1, 120);
    // Doorway gap (120-150) — strategy room to main office
    ctx.fillStyle = wallColor;
    ctx.fillRect(225, 155, wallThickness, 45);     // between doors
    ctx.fillStyle = wallHighlight;
    ctx.fillRect(225, 155, 1, 45);
    // Doorway gap (200-230) — where vertical wall meets horizontal
    ctx.fillStyle = wallColor;
    ctx.fillRect(225, 240, wallThickness, 60);     // kitchen portion
    ctx.fillStyle = wallHighlight;
    ctx.fillRect(225, 240, 1, 60);
    // Doorway gap (300-330) — kitchen to main office
    ctx.fillStyle = wallColor;
    ctx.fillRect(225, 335, wallThickness, 65);     // bottom of kitchen wall
    ctx.fillStyle = wallHighlight;
    ctx.fillRect(225, 335, 1, 65);

    // Horizontal divider: strategy room | kitchen
    ctx.fillStyle = wallColor;
    ctx.fillRect(0, 195, 140, wallThickness);      // left of doorway
    ctx.fillStyle = wallShadow;
    ctx.fillRect(0, 195, 140, 1);
    // Doorway gap
    ctx.fillStyle = wallColor;
    ctx.fillRect(175, 195, 55, wallThickness);     // right of doorway
    ctx.fillStyle = wallShadow;
    ctx.fillRect(175, 195, 55, 1);

    // Horizontal divider: main office + kitchen | break room
    ctx.fillStyle = wallColor;
    ctx.fillRect(0, 395, 200, wallThickness);      // left portion (under kitchen)
    ctx.fillStyle = wallShadow;
    ctx.fillRect(0, 395, 200, 1);
    // Doorway gap from kitchen to break room
    ctx.fillStyle = wallColor;
    ctx.fillRect(240, 395, 260, wallThickness);    // middle portion
    ctx.fillStyle = wallShadow;
    ctx.fillRect(240, 395, 260, 1);
    // Doorway gap from main office to break room
    ctx.fillStyle = wallColor;
    ctx.fillRect(540, 395, 260, wallThickness);    // right portion
    ctx.fillStyle = wallShadow;
    ctx.fillRect(540, 395, 260, 1);

    // ── Doorway floor markers (subtle) ──
    const doorwayColor = 'rgba(120, 95, 65, 0.15)';
    ctx.fillStyle = doorwayColor;
    // Strategy room to main office
    ctx.fillRect(225, 120, wallThickness, 35);
    // Kitchen to main office
    ctx.fillRect(225, 300, wallThickness, 35);
    // Strategy to kitchen
    ctx.fillRect(140, 195, 35, wallThickness);
    // Kitchen to break room
    ctx.fillRect(200, 395, 40, wallThickness);
    // Main office to break room
    ctx.fillRect(500, 395, 40, wallThickness);
    // Main entrance door
    ctx.fillRect(795, 180, wallThickness, 45);
  }

  // ── Pixel art furniture renderers ──────────────────────────

  function drawFurniture(ctx: CanvasRenderingContext2D, item: Furniture) {
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
        // Walls rendered by drawWalls, skip
        break;
    }
  }

  // ── Individual furniture pixel art renderers ───────────────

  function drawDeskWithMonitor(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
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

  function drawOfficeChair(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawMeetingTable(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
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

  function drawMeetingChair(ctx: CanvasRenderingContext2D, x: number, y: number) {
    // Small top-down chair
    ctx.fillStyle = 'rgb(55, 55, 65)';
    safeRoundRect(ctx, x, y, 16, 14, 3);
    ctx.fill();
    // Seat cushion
    ctx.fillStyle = 'rgb(65, 65, 78)';
    safeRoundRect(ctx, x + 2, y + 2, 12, 10, 2);
    ctx.fill();
  }

  function drawWhiteboard(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
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

  function drawFridge(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawMicrowave(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawToaster(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawKitchenCounter(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
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

  function drawSink(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawCoffeeMachine(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawCouch(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, color: string) {
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

  function drawBeanBag(ctx: CanvasRenderingContext2D, x: number, y: number, color: string) {
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

  function drawPlant(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawFern(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawWaterCooler(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawPrinter(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawTvScreen(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
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

  function drawPingPongTable(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawGameConsole(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawArcadeMachine(ctx: CanvasRenderingContext2D, x: number, y: number, color: string) {
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

  function drawClock(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawPictureFrame(ctx: CanvasRenderingContext2D, x: number, y: number) {
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

  function drawSimpleDesk(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
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
  function drawAnimatedMonitor(
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
  function drawAnimatedTv(
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
  function drawAnimatedArcade(
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

  /** Track toaster fire state: maps toaster key → { startTime, fireAt, fireEnd } */
  const toasterFireState = new Map<string, { startTime: number; fireAt: number; fireEnd: number }>();

  function drawToasterFire(
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

  function drawPingPongBall(
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
      const tableCenterX = 370;
      const tableCenterY = 468;
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
      // Ping pong: 0→1→0 triangle wave
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

  // ── Mobile room rendering ──────────────────────────────────

  function isAgentInArea(agent: EngineAgent, area: OfficeArea, padding: number = 20): boolean {
    const ax = agent.position.x;
    const ay = agent.position.y;
    const b = area.bounds;
    return ax >= b.x - padding && ax <= b.x + b.width + padding &&
           ay >= b.y - padding && ay <= b.y + b.height + padding;
  }

  function renderRoom(ctx: CanvasRenderingContext2D, eng: OfficeEngine, area: OfficeArea) {
    const now = performance.now();
    const b = area.bounds;

    // Clear canvas
    ctx.fillStyle = 'rgb(20, 20, 26)';
    ctx.fillRect(0, 0, b.width, b.height);

    ctx.save();
    // Shift coordinate system so room renders at (0,0)
    ctx.translate(-b.x, -b.y);

    // Floor
    ctx.fillStyle = area.color;
    ctx.fillRect(b.x, b.y, b.width, b.height);

    // Floor pattern
    drawFloorPattern(ctx, area);

    // Room label (subtle, in corner)
    ctx.fillStyle = 'rgba(160, 160, 170, 0.25)';
    ctx.font = '8px Menlo, monospace';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText(area.name.toUpperCase(), b.x + 8, b.y + 8);

    // Furniture with animated overlays
    if (area.furniture) {
      for (const item of area.furniture) {
        if (item.type === 'tvScreen') {
          drawAnimatedTv(ctx, item.position.x, item.position.y, item.width, item.height, eng, now);
        } else if (item.type === 'arcadeMachine') {
          drawFurniture(ctx, item);
          drawAnimatedArcade(ctx, item.position.x, item.position.y, item.width, item.height, eng, now, item.color);
        } else {
          drawFurniture(ctx, item);
        }

        if (item.type === 'toaster') {
          drawToasterFire(ctx, item.position.x, item.position.y, eng, now);
        }
      }
    }

    // Desks (only for mainOffice)
    if (area.type === 'mainOffice') {
      for (const d of desks) {
        renderDesk(ctx, d);

        const isOccupiedWorking = d.occupantId !== null &&
          eng.agents.get(d.occupantId)?.animation.type === 'work-shake';

        const deskFurniturePositions = [
          { fx: 280, fy: 45, fw: 56 },
          { fx: 420, fy: 45, fw: 56 },
          { fx: 560, fy: 45, fw: 56 },
          { fx: 280, fy: 165, fw: 56 },
          { fx: 420, fy: 165, fw: 56 },
          { fx: 560, fy: 165, fw: 56 },
        ];

        if (d.id >= 0 && d.id < deskFurniturePositions.length) {
          const fp = deskFurniturePositions[d.id];
          const mw = 16, mh = 10;
          const mx = fp.fx + (fp.fw - mw) / 2;
          const my = fp.fy + 6;
          drawAnimatedMonitor(ctx, mx, my, mw, mh, isOccupiedWorking, now);
        }
      }

      // Door (only in mainOffice)
      renderDoor(ctx);
    }

    // Agents within this room
    for (const agent of eng.agents.values()) {
      if (isAgentInArea(agent, area)) {
        renderAgent(ctx, agent);
      }
    }

    // Ping pong ball (only for breakRoom)
    if (area.type === 'breakRoom') {
      drawPingPongBall(ctx, eng, now);
    }

    ctx.restore();

    // Draw subtle border around room canvas
    ctx.strokeStyle = 'rgba(100, 100, 120, 0.4)';
    ctx.lineWidth = 1;
    ctx.strokeRect(0, 0, b.width, b.height);

    // Reset text baseline
    ctx.textBaseline = 'alphabetic';
  }

  // ── Main rendering ─────────────────────────────────────────

  function renderScene(ctx: CanvasRenderingContext2D, eng: OfficeEngine) {
    const now = performance.now();

    // Clear with dark background (visible in gaps)
    ctx.fillStyle = 'rgb(20, 20, 26)';
    ctx.fillRect(0, 0, SCENE_WIDTH, SCENE_HEIGHT);

    // Draw all area floors
    for (const area of AREAS) {
      const { x, y, width, height } = area.bounds;

      // Fill floor
      ctx.fillStyle = area.color;
      ctx.fillRect(x, y, width, height);

      // Floor pattern overlay
      drawFloorPattern(ctx, area);
    }

    // Draw walls (on top of floors but below furniture)
    drawWalls(ctx);

    // Draw area labels (subtle, in corner)
    for (const area of AREAS) {
      const { x, y } = area.bounds;
      ctx.fillStyle = 'rgba(160, 160, 170, 0.25)';
      ctx.font = '8px Menlo, monospace';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'top';
      ctx.fillText(area.name.toUpperCase(), x + 8, y + 8);
    }

    // Draw furniture for all areas, with animated overlays
    for (const area of AREAS) {
      if (!area.furniture) continue;
      for (const item of area.furniture) {
        if (item.type === 'tvScreen') {
          // Draw animated TV instead of static
          drawAnimatedTv(ctx, item.position.x, item.position.y, item.width, item.height, eng, now);
        } else if (item.type === 'arcadeMachine') {
          // Draw static arcade body, then animated screen overlay
          drawFurniture(ctx, item);
          drawAnimatedArcade(ctx, item.position.x, item.position.y, item.width, item.height, eng, now, item.color);
        } else {
          drawFurniture(ctx, item);
        }

        // Toaster fire overlay
        if (item.type === 'toaster') {
          drawToasterFire(ctx, item.position.x, item.position.y, eng, now);
        }
      }
    }

    // Draw desks (agent assignment targets) with animated monitors
    for (const d of desks) {
      renderDesk(ctx, d);

      // Animated monitor overlay on desk monitors in the main office furniture
      // Check if this desk's occupant is working (has 'work-shake' animation)
      const isOccupiedWorking = d.occupantId !== null &&
        eng.agents.get(d.occupantId)?.animation.type === 'work-shake';

      // The desk monitor is embedded in the deskWithMonitor furniture items
      // Match desk positions to corresponding deskWithMonitor furniture
      // Desks: Row 1 seats at y=85, desks at y=45. Row 2 seats at y=205, desks at y=165
      // Monitor positions: centered on desk furniture
      const deskFurniturePositions = [
        { fx: 280, fy: 45, fw: 56 },  // Desk 0
        { fx: 420, fy: 45, fw: 56 },  // Desk 1
        { fx: 560, fy: 45, fw: 56 },  // Desk 2
        { fx: 280, fy: 165, fw: 56 }, // Desk 3
        { fx: 420, fy: 165, fw: 56 }, // Desk 4
        { fx: 560, fy: 165, fw: 56 }, // Desk 5
      ];

      if (d.id >= 0 && d.id < deskFurniturePositions.length) {
        const fp = deskFurniturePositions[d.id];
        const mw = 16, mh = 10;
        const mx = fp.fx + (fp.fw - mw) / 2;
        const my = fp.fy + 6;
        drawAnimatedMonitor(ctx, mx, my, mw, mh, isOccupiedWorking, now);
      }
    }

    // Draw door
    renderDoor(ctx);

    // Draw all agents (single view — no filtering)
    for (const agent of eng.agents.values()) {
      renderAgent(ctx, agent);
    }

    // Draw ping pong ball on top of agents
    drawPingPongBall(ctx, eng, now);

    // Reset text baseline
    ctx.textBaseline = 'alphabetic';
  }

  function renderDesk(ctx: CanvasRenderingContext2D, d: { id: number; position: { x: number; y: number }; occupantId: string | null; label?: string; width?: number; height?: number }) {
    const { x, y } = d.position;
    const isOccupied = d.occupantId !== null;
    const dw = d.width ?? 40;
    const dh = d.height ?? 25;
    const dx = x - dw / 2;
    const dy = y - dh / 2;

    // Desk body
    safeRoundRect(ctx, dx, dy, dw, dh, 3);
    if (isOccupied) {
      ctx.fillStyle = 'rgb(140, 105, 72)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(242, 180, 80, 0.5)';
      ctx.lineWidth = 1.5;
      ctx.stroke();
    } else {
      ctx.fillStyle = 'rgb(115, 85, 58)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(100, 80, 55, 0.5)';
      ctx.lineWidth = 1;
      ctx.stroke();
    }

    // Top highlight
    ctx.fillStyle = 'rgba(255, 255, 255, 0.06)';
    ctx.fillRect(dx + 2, dy + 1, dw - 4, 2);

    // Monitor on desk (tiny rectangle)
    if (!isOccupied) {
      ctx.fillStyle = 'rgba(40, 50, 60, 0.4)';
      ctx.fillRect(x - 4, dy + 3, 8, 5);
    }

    // Name label below desk
    if (d.label) {
      ctx.fillStyle = isOccupied ? 'rgba(242, 200, 120, 0.7)' : 'rgba(160, 150, 130, 0.5)';
      ctx.font = '7px Menlo, monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.fillText(d.label, x, dy + dh + 3);
    }
  }

  function renderDoor(ctx: CanvasRenderingContext2D) {
    const dx = DOOR_POSITION.x;
    const dy = DOOR_POSITION.y;
    const dw = 10;
    const dh = 36;

    // Door frame
    ctx.fillStyle = 'rgb(120, 95, 65)';
    ctx.fillRect(dx - 1, dy - dh / 2, dw + 2, dh);

    // Door panel
    ctx.fillStyle = 'rgb(140, 110, 72)';
    ctx.fillRect(dx, dy - dh / 2 + 1, dw, dh - 2);

    // Door handle
    ctx.fillStyle = 'rgb(200, 180, 120)';
    ctx.beginPath();
    ctx.arc(dx + 3, dy, 2, 0, Math.PI * 2);
    ctx.fill();

    // Label
    ctx.fillStyle = 'rgba(242, 200, 120, 0.6)';
    ctx.font = 'bold 6px Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.save();
    ctx.translate(dx + dw / 2, dy);
    ctx.rotate(-Math.PI / 2);
    ctx.fillText('EXIT', 0, 0);
    ctx.restore();
  }

  function drawSpeechBubble(ctx: CanvasRenderingContext2D, agent: EngineAgent) {
    if (!agent.speechBubble) return;

    const now = performance.now();
    const elapsed = now - agent.speechBubble.startTime;
    const remaining = agent.speechBubble.duration - elapsed;
    if (remaining <= 0) return;

    // Calculate alpha — full opacity, fade out in last 500ms
    const fadeStart = 500;
    const alpha = remaining < fadeStart ? remaining / fadeStart : 1;

    const x = agent.position.x + agent.animOffset.x;
    const y = agent.position.y + agent.animOffset.y;
    const size = getCharacterSize(agent.characterType);

    ctx.save();
    ctx.globalAlpha = alpha * agent.alpha;

    // Measure text to size the bubble
    ctx.font = '7px Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const textWidth = ctx.measureText(agent.speechBubble.text).width;

    const padH = 6;
    const padV = 4;
    const bubbleW = textWidth + padH * 2;
    const bubbleH = 12 + padV * 2;
    const bubbleX = x - bubbleW / 2;
    const bubbleY = y - size.height / 2 - 14 - bubbleH; // above name + status dot
    const tailSize = 4;

    // Bubble background
    safeRoundRect(ctx, bubbleX, bubbleY, bubbleW, bubbleH, 4);
    ctx.fillStyle = 'rgb(240, 240, 245)';
    ctx.fill();
    ctx.strokeStyle = 'rgb(60, 60, 70)';
    ctx.lineWidth = 1;
    ctx.stroke();

    // Tail triangle pointing down to agent
    ctx.beginPath();
    ctx.moveTo(x - tailSize, bubbleY + bubbleH);
    ctx.lineTo(x, bubbleY + bubbleH + tailSize);
    ctx.lineTo(x + tailSize, bubbleY + bubbleH);
    ctx.closePath();
    ctx.fillStyle = 'rgb(240, 240, 245)';
    ctx.fill();
    // Tail border (just the two angled sides)
    ctx.beginPath();
    ctx.moveTo(x - tailSize, bubbleY + bubbleH);
    ctx.lineTo(x, bubbleY + bubbleH + tailSize);
    ctx.lineTo(x + tailSize, bubbleY + bubbleH);
    ctx.strokeStyle = 'rgb(60, 60, 70)';
    ctx.lineWidth = 1;
    ctx.stroke();
    // Cover the border line where tail meets bubble
    ctx.fillStyle = 'rgb(240, 240, 245)';
    ctx.fillRect(x - tailSize + 1, bubbleY + bubbleH - 1, tailSize * 2 - 2, 2);

    // Text
    ctx.fillStyle = 'rgb(30, 30, 40)';
    ctx.fillText(agent.speechBubble.text, x, bubbleY + bubbleH / 2);

    ctx.restore();
  }

  function renderAgent(ctx: CanvasRenderingContext2D, agent: EngineAgent) {
    const x = agent.position.x + agent.animOffset.x;
    const y = agent.position.y + agent.animOffset.y;
    const now = performance.now();

    // Draw sprite with rotation if celebrating
    if (agent.rotation !== 0) {
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(agent.rotation);
      renderCharacterAnimated(ctx, agent.characterType, 0, 0, now, agent.alpha,
        agent.facing, agent.isMoving, agent.walkPhase, agent.idleActivity);
      ctx.restore();
    } else {
      renderCharacterAnimated(ctx, agent.characterType, x, y, now, agent.alpha,
        agent.facing, agent.isMoving, agent.walkPhase, agent.idleActivity);
    }

    if (agent.alpha <= 0) return;

    const prevAlpha = ctx.globalAlpha;
    ctx.globalAlpha = agent.alpha;

    // Name label above sprite
    const size = getCharacterSize(agent.characterType);
    ctx.fillStyle = 'white';
    ctx.font = '9px Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillText(agent.name, x, y - size.height / 2 - 4);

    // Idle activity label below sprite
    if (agent.idleActivity) {
      ctx.fillStyle = 'rgba(242, 191, 77, 0.7)';
      ctx.font = '7px Menlo, monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.fillText(agent.idleActivity, x, y + size.height / 2 + 2);
    }

    // Status dot
    ctx.beginPath();
    ctx.arc(x, y - size.height / 2 - 10, 3, 0, Math.PI * 2);
    ctx.fillStyle = agent.statusColor;
    ctx.fill();

    ctx.globalAlpha = prevAlpha;

    // Speech bubble (drawn after restoring alpha so it has its own fade logic)
    drawSpeechBubble(ctx, agent);
  }
</script>

<div class="office-wrapper">
  <div class="office-container" bind:this={containerEl}>
    {#if isMobile}
      <!-- Mobile: stacked room canvases -->
      <div class="mobile-room-stack">
        {#each ROOM_ORDER as room}
          {@const area = AREAS.find(a => a.type === room.type)}
          {#if area}
            <div class="mobile-room-section">
              <div class="mobile-room-label">{room.label}</div>
              <canvas
                bind:this={roomCanvasEls[room.type]}
                width={area.bounds.width}
                height={area.bounds.height}
                style="width: 100%;"
                onclick={(e) => handleRoomClick(e, area)}
                role="application"
                tabindex="0"
                aria-label="{room.label} — click agents to inspect"
              ></canvas>
            </div>
          {/if}
        {/each}
      </div>
    {:else}
      <!-- Desktop: single unified canvas -->
      <canvas
        bind:this={canvasEl}
        width={SCENE_WIDTH}
        height={SCENE_HEIGHT}
        style="width: {SCENE_WIDTH * scale}px; height: {SCENE_HEIGHT * scale}px;"
        onclick={handleClick}
        role="application"
        tabindex="0"
        aria-label="Office visualization — click agents to inspect"
      ></canvas>
    {/if}
  </div>
</div>

<style>
  .office-wrapper {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
    background: rgb(20, 20, 26);
  }

  .office-container {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgb(20, 20, 26);
    overflow: hidden;
    min-height: 0;
  }

  canvas {
    cursor: pointer;
    image-rendering: pixelated;
  }

  /* ── Mobile stacked layout ── */

  .mobile-room-stack {
    width: 100%;
    height: 100%;
    overflow-y: auto;
    overflow-x: hidden;
    -webkit-overflow-scrolling: touch;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 4px;
  }

  .mobile-room-section {
    flex-shrink: 0;
  }

  .mobile-room-label {
    font-family: Menlo, monospace;
    font-size: 10px;
    color: rgba(200, 200, 210, 0.6);
    text-transform: uppercase;
    letter-spacing: 1px;
    padding: 4px 4px 2px;
  }

  .mobile-room-section canvas {
    display: block;
    width: 100%;
    height: auto;
    border-radius: 2px;
  }
</style>
