// Theme Engine — Day/night cycle + seasonal themes
// Manages office visual theming based on real clock time and calendar month.

// ── Time of Day ─────────────────────────────────────────────

export type TimeOfDay = 'dawn' | 'day' | 'dusk' | 'night';

/** Core time-of-day ranges (hour boundaries):
 *  dawn  5–7   | day  7–18  | dusk  18–20  | night  20–5 */
export function getTimeOfDay(date: Date = new Date()): TimeOfDay {
  const h = date.getHours();
  const m = date.getMinutes();
  const t = h + m / 60; // fractional hour
  if (t >= 5 && t < 7) return 'dawn';
  if (t >= 7 && t < 18) return 'day';
  if (t >= 18 && t < 20) return 'dusk';
  return 'night';
}

// ── Season ──────────────────────────────────────────────────

export type Season = 'spring' | 'summer' | 'autumn' | 'winter';

export function getSeason(date: Date = new Date()): Season {
  const m = date.getMonth(); // 0-indexed
  if (m >= 2 && m <= 4) return 'spring';
  if (m >= 5 && m <= 7) return 'summer';
  if (m >= 8 && m <= 10) return 'autumn';
  return 'winter';
}

/** Whether it's December (for holiday decorations) */
export function isHolidaySeason(date: Date = new Date()): boolean {
  return date.getMonth() === 11;
}

// ── Color Palette ───────────────────────────────────────────

export interface ThemePalette {
  /** RGBA overlay applied to the entire canvas */
  overlay: string;
  /** Tint multiplier for floor colors (CSS filter-like) */
  floorTint: string;
  /** Wall tint */
  wallTint: string;
  /** Window gradient colors [top, bottom] */
  windowGradient: [string, string];
  /** Monitor glow intensity (0-1, brighter at night) */
  monitorGlow: number;
  /** Whether desk lamps should be on */
  lampsOn: boolean;
  /** Star field visibility (0-1) */
  starField: number;
}

const PALETTES: Record<TimeOfDay, ThemePalette> = {
  dawn: {
    overlay: 'rgba(255, 180, 100, 0.06)',
    floorTint: 'rgba(255, 180, 100, 0.04)',
    wallTint: 'rgba(255, 160, 80, 0.05)',
    windowGradient: ['rgba(255, 140, 60, 0.5)', 'rgba(255, 200, 120, 0.3)'],
    monitorGlow: 0.5,
    lampsOn: false,
    starField: 0,
  },
  day: {
    overlay: 'rgba(0, 0, 0, 0)',
    floorTint: 'rgba(0, 0, 0, 0)',
    wallTint: 'rgba(0, 0, 0, 0)',
    windowGradient: ['rgba(135, 200, 255, 0.3)', 'rgba(200, 230, 255, 0.2)'],
    monitorGlow: 0.3,
    lampsOn: false,
    starField: 0,
  },
  dusk: {
    overlay: 'rgba(255, 150, 50, 0.07)',
    floorTint: 'rgba(255, 150, 50, 0.05)',
    wallTint: 'rgba(255, 120, 40, 0.06)',
    windowGradient: ['rgba(255, 100, 50, 0.5)', 'rgba(255, 160, 80, 0.3)'],
    monitorGlow: 0.6,
    lampsOn: false,
    starField: 0,
  },
  night: {
    overlay: 'rgba(30, 40, 80, 0.12)',
    floorTint: 'rgba(20, 30, 60, 0.08)',
    wallTint: 'rgba(20, 30, 70, 0.10)',
    windowGradient: ['rgba(10, 15, 40, 0.6)', 'rgba(20, 25, 50, 0.5)'],
    monitorGlow: 1.0,
    lampsOn: true,
    starField: 0.8,
  },
};

// ── Seasonal Tints ──────────────────────────────────────────

export interface SeasonalOverlay {
  /** Additional color tint for the season */
  tint: string;
  /** Plant color override */
  plantColor: string;
  /** Whether to show snow on window sills */
  snow: boolean;
  /** Holiday decorations (December only) */
  holiday: boolean;
}

const SEASONAL_OVERLAYS: Record<Season, SeasonalOverlay> = {
  spring: {
    tint: 'rgba(100, 200, 100, 0.03)',
    plantColor: 'rgb(60, 140, 50)',
    snow: false,
    holiday: false,
  },
  summer: {
    tint: 'rgba(255, 230, 150, 0.03)',
    plantColor: 'rgb(52, 120, 48)',
    snow: false,
    holiday: false,
  },
  autumn: {
    tint: 'rgba(200, 140, 60, 0.04)',
    plantColor: 'rgb(180, 120, 50)',
    snow: false,
    holiday: false,
  },
  winter: {
    tint: 'rgba(180, 200, 240, 0.04)',
    plantColor: 'rgb(40, 80, 45)',
    snow: true,
    holiday: false,  // set dynamically based on month
  },
};

// ── Interpolation ───────────────────────────────────────────

/** Parse rgba string to components */
function parseRGBA(s: string): [number, number, number, number] {
  const m = s.match(/[\d.]+/g);
  if (!m || m.length < 4) return [0, 0, 0, 0];
  return [Number(m[0]), Number(m[1]), Number(m[2]), Number(m[3])];
}

/** Interpolate between two RGBA strings */
function lerpRGBA(a: string, b: string, t: number): string {
  const [ar, ag, ab, aa] = parseRGBA(a);
  const [br, bg, bb, ba] = parseRGBA(b);
  const r = Math.round(ar + (br - ar) * t);
  const g = Math.round(ag + (bg - ag) * t);
  const bl = Math.round(ab + (bb - ab) * t);
  const al = aa + (ba - aa) * t;
  return `rgba(${r}, ${g}, ${bl}, ${al.toFixed(3)})`;
}

/** Interpolate between two palettes */
function lerpPalette(a: ThemePalette, b: ThemePalette, t: number): ThemePalette {
  return {
    overlay: lerpRGBA(a.overlay, b.overlay, t),
    floorTint: lerpRGBA(a.floorTint, b.floorTint, t),
    wallTint: lerpRGBA(a.wallTint, b.wallTint, t),
    windowGradient: [
      lerpRGBA(a.windowGradient[0], b.windowGradient[0], t),
      lerpRGBA(a.windowGradient[1], b.windowGradient[1], t),
    ],
    monitorGlow: a.monitorGlow + (b.monitorGlow - a.monitorGlow) * t,
    lampsOn: t > 0.5 ? b.lampsOn : a.lampsOn,
    starField: a.starField + (b.starField - a.starField) * t,
  };
}

// ── Transition calculation ──────────────────────────────────

/** Transition boundaries (fractional hours) and their durations */
const TRANSITIONS: { from: TimeOfDay; to: TimeOfDay; startHour: number; endHour: number }[] = [
  { from: 'night', to: 'dawn', startHour: 4.5, endHour: 5.5 },
  { from: 'dawn', to: 'day', startHour: 6.5, endHour: 7.5 },
  { from: 'day', to: 'dusk', startHour: 17.5, endHour: 18.5 },
  { from: 'dusk', to: 'night', startHour: 19.5, endHour: 20.5 },
];

/** Get the current palette, smoothly interpolated during transition windows */
function getCurrentPalette(date: Date = new Date()): ThemePalette {
  const h = date.getHours();
  const m = date.getMinutes();
  const t = h + m / 60;

  for (const tr of TRANSITIONS) {
    if (t >= tr.startHour && t <= tr.endHour) {
      const progress = (t - tr.startHour) / (tr.endHour - tr.startHour);
      return lerpPalette(PALETTES[tr.from], PALETTES[tr.to], progress);
    }
  }

  return PALETTES[getTimeOfDay(date)];
}

// ── Theme State ─────────────────────────────────────────────

export interface ThemeState {
  timeOfDay: TimeOfDay;
  season: Season;
  palette: ThemePalette;
  seasonal: SeasonalOverlay;
  /** Stable star positions (generated once, reused across frames) */
  stars: Array<{ x: number; y: number; size: number; brightness: number }>;
}

/** Generate random star positions for the star field */
function generateStars(count: number): ThemeState['stars'] {
  const stars: ThemeState['stars'] = [];
  for (let i = 0; i < count; i++) {
    stars.push({
      x: Math.random(),
      y: Math.random(),
      size: 1 + Math.random() * 1.5,
      brightness: 0.3 + Math.random() * 0.7,
    });
  }
  return stars;
}

// ── Theme Engine Class ──────────────────────────────────────

export class ThemeEngine {
  private _state: ThemeState;
  private _updateInterval: ReturnType<typeof setInterval> | null = null;

  constructor() {
    const now = new Date();
    const season = getSeason(now);
    const seasonal = { ...SEASONAL_OVERLAYS[season] };
    if (season === 'winter' && isHolidaySeason(now)) {
      seasonal.holiday = true;
    }

    this._state = {
      timeOfDay: getTimeOfDay(now),
      season,
      palette: getCurrentPalette(now),
      seasonal,
      stars: generateStars(40),
    };
  }

  get state(): ThemeState {
    return this._state;
  }

  /** Start automatic updates (every 30 seconds) */
  start(): void {
    if (this._updateInterval) return;
    this._updateInterval = setInterval(() => this.update(), 30_000);
  }

  /** Stop automatic updates */
  stop(): void {
    if (this._updateInterval) {
      clearInterval(this._updateInterval);
      this._updateInterval = null;
    }
  }

  /** Recalculate theme state from current time */
  update(): void {
    const now = new Date();
    const season = getSeason(now);
    const seasonal = { ...SEASONAL_OVERLAYS[season] };
    if (season === 'winter' && isHolidaySeason(now)) {
      seasonal.holiday = true;
    }

    this._state = {
      ...this._state,
      timeOfDay: getTimeOfDay(now),
      season,
      palette: getCurrentPalette(now),
      seasonal,
    };
  }

  // ── Canvas Drawing Helpers ──────────────────────────────────

  /** Draw the theme overlay on top of the entire scene */
  drawOverlay(ctx: CanvasRenderingContext2D, width: number, height: number): void {
    const { palette, seasonal } = this._state;

    // Time-of-day overlay
    ctx.fillStyle = palette.overlay;
    ctx.fillRect(0, 0, width, height);

    // Seasonal tint
    ctx.fillStyle = seasonal.tint;
    ctx.fillRect(0, 0, width, height);
  }

  /** Draw star field through windows (night only) */
  drawStarField(ctx: CanvasRenderingContext2D, windowX: number, windowY: number, windowW: number, windowH: number): void {
    const { palette, stars } = this._state;
    if (palette.starField <= 0) return;

    ctx.save();
    ctx.beginPath();
    ctx.rect(windowX, windowY, windowW, windowH);
    ctx.clip();

    for (const star of stars) {
      const sx = windowX + star.x * windowW;
      const sy = windowY + star.y * windowH;
      const alpha = star.brightness * palette.starField;
      // Twinkle effect — subtle sine wave
      const twinkle = 0.7 + 0.3 * Math.sin(performance.now() * 0.001 + star.x * 100);

      ctx.fillStyle = `rgba(255, 255, 240, ${(alpha * twinkle).toFixed(3)})`;
      ctx.beginPath();
      ctx.arc(sx, sy, star.size, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.restore();
  }

  /** Draw a themed window with time-of-day gradient */
  drawWindow(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    const { palette, seasonal } = this._state;

    // Window background gradient
    const grad = ctx.createLinearGradient(x, y, x, y + h);
    grad.addColorStop(0, palette.windowGradient[0]);
    grad.addColorStop(1, palette.windowGradient[1]);
    ctx.fillStyle = grad;
    ctx.fillRect(x, y, w, h);

    // Stars through window at night
    this.drawStarField(ctx, x, y, w, h);

    // Snow on window sill
    if (seasonal.snow) {
      ctx.fillStyle = 'rgba(240, 245, 255, 0.7)';
      ctx.fillRect(x, y + h - 3, w, 3);
      // Small snow mounds
      for (let sx = x + 4; sx < x + w - 4; sx += 8 + Math.random() * 6) {
        const moundW = 6 + Math.random() * 4;
        ctx.beginPath();
        ctx.ellipse(sx, y + h - 3, moundW / 2, 2 + Math.random(), 0, 0, Math.PI, true);
        ctx.fill();
      }
    }

    // Window frame
    ctx.strokeStyle = 'rgba(100, 100, 120, 0.5)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x, y, w, h);
  }

  /** Draw a desk lamp (visible when lampsOn) */
  drawDeskLamp(ctx: CanvasRenderingContext2D, x: number, y: number): void {
    const { palette } = this._state;
    if (!palette.lampsOn) return;

    // Lamp glow circle
    const grad = ctx.createRadialGradient(x, y - 6, 2, x, y - 6, 20);
    grad.addColorStop(0, 'rgba(255, 220, 150, 0.25)');
    grad.addColorStop(1, 'rgba(255, 220, 150, 0)');
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(x, y - 6, 20, 0, Math.PI * 2);
    ctx.fill();

    // Lamp base
    ctx.fillStyle = 'rgb(80, 80, 90)';
    ctx.fillRect(x - 3, y - 2, 6, 4);

    // Lamp arm
    ctx.strokeStyle = 'rgb(100, 100, 110)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(x, y - 2);
    ctx.lineTo(x - 2, y - 10);
    ctx.stroke();

    // Lamp shade
    ctx.fillStyle = 'rgb(200, 180, 140)';
    ctx.beginPath();
    ctx.moveTo(x - 6, y - 10);
    ctx.lineTo(x + 4, y - 10);
    ctx.lineTo(x + 2, y - 14);
    ctx.lineTo(x - 4, y - 14);
    ctx.closePath();
    ctx.fill();

    // Lamp light (small bright spot)
    ctx.fillStyle = 'rgba(255, 240, 200, 0.8)';
    ctx.beginPath();
    ctx.arc(x - 1, y - 10, 1.5, 0, Math.PI * 2);
    ctx.fill();
  }

  /** Draw holiday decorations (December only) */
  drawHolidayDecor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number): void {
    const { seasonal } = this._state;
    if (!seasonal.holiday) return;

    // String of lights along the top
    const colors = ['rgb(255, 50, 50)', 'rgb(50, 255, 50)', 'rgb(50, 100, 255)', 'rgb(255, 200, 50)'];
    for (let lx = x + 6; lx < x + width - 6; lx += 10) {
      const ci = Math.floor((lx - x) / 10) % colors.length;
      // Wire
      ctx.strokeStyle = 'rgba(100, 100, 100, 0.4)';
      ctx.lineWidth = 0.5;
      ctx.beginPath();
      ctx.moveTo(lx, y);
      ctx.lineTo(lx + 10, y);
      ctx.stroke();
      // Bulb
      const pulse = 0.6 + 0.4 * Math.sin(performance.now() * 0.003 + lx * 0.5);
      ctx.fillStyle = colors[ci];
      ctx.globalAlpha = pulse;
      ctx.beginPath();
      ctx.arc(lx, y + 3, 2, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }
}
