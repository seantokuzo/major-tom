// A* grid-based pathfinding for office agents
// Builds a per-view walkability grid from areas + furniture data, with doorways punched through walls.

import type { Point, OfficeView } from './types';
import { SCENE_WIDTH, SCENE_HEIGHT, getAreasForView } from './layout';

// ── Grid Constants ────────────────────────────────────────────

const CELL_SIZE = 8; // pixels per grid cell
const GRID_W = Math.ceil(SCENE_WIDTH / CELL_SIZE);   // 125
const GRID_H = Math.ceil(SCENE_HEIGHT / CELL_SIZE);   // 94

/** Cost multiplier for diagonal steps (sqrt(2)) */
const DIAG_COST = 1.4142135623730951;

// ── Doorway Definitions ───────────────────────────────────────
// Each doorway is a rectangular region in pixel coordinates that
// should be marked walkable even though it sits in a wall zone.

interface DoorwayDef {
  x: number;
  y: number;
  width: number;
  height: number;
}

const VIEW_DOORWAYS: Record<OfficeView, DoorwayDef[]> = {
  office: [
    // Strategy Room <-> Main Office (vertical wall at x=275, around y=180)
    { x: 272, y: 160, width: 20, height: 40 },
    // Kitchen <-> Main Office (vertical wall at x=275, around y=560)
    { x: 272, y: 540, width: 20, height: 40 },
    // Strategy Room <-> Kitchen (horizontal wall at y=375, around x=120)
    { x: 120, y: 372, width: 40, height: 20 },
    // Main Office <-> Break Room (vertical wall at x=670, around y=350)
    { x: 667, y: 340, width: 20, height: 40 },
    // Main entrance (right wall of main office, the DOOR furniture area)
    { x: 650, y: 380, width: 20, height: 50 },
  ],
  dogPark: [
    // Dog Park Field <-> Agility Course (vertical split around x=610)
    { x: 598, y: 500, width: 25, height: 45 },
    // Dog Park Field <-> Dog Pond (vertical split around x=610)
    { x: 598, y: 190, width: 25, height: 45 },
    // Agility Course <-> Dog Pond (horizontal split around y=385)
    { x: 750, y: 378, width: 45, height: 25 },
  ],
  gym: [
    // Gym Floor <-> Yoga Studio (vertical split around x=610)
    { x: 598, y: 500, width: 25, height: 45 },
    // Gym Floor <-> Locker Room (vertical split around x=610)
    { x: 598, y: 190, width: 25, height: 45 },
    // Yoga Studio <-> Locker Room (horizontal split around y=385)
    { x: 750, y: 378, width: 45, height: 25 },
  ],
  spriteStreet: (() => {
    // Generate doorways for the 7×2 bedroom grid
    const doorways: DoorwayDef[] = [];
    const COL_W = 140;
    const ROW_H = 370;

    // Horizontal doorways between row 1 and row 2 (7 doorways, one per column)
    for (let col = 0; col < 7; col++) {
      const cx = 5 + col * COL_W + 55; // center of column
      doorways.push({ x: cx, y: ROW_H - 2, width: 25, height: 20 });
    }

    // Vertical doorways between adjacent columns in row 1
    for (let col = 0; col < 6; col++) {
      const wallX = 5 + (col + 1) * COL_W - 3;
      doorways.push({ x: wallX, y: 160, width: 20, height: 35 });
    }

    // Vertical doorways between adjacent columns in row 2
    for (let col = 0; col < 6; col++) {
      const wallX = 5 + (col + 1) * COL_W - 3;
      doorways.push({ x: wallX, y: ROW_H + 160, width: 20, height: 35 });
    }

    return doorways;
  })(),
};

// Furniture types that should NOT block movement (wall decorations, flat items)
const NON_BLOCKING_FURNITURE = new Set([
  'clock',
  'pictureFrame',
  'whiteboard',
  'tvScreen',
  'door',         // the door graphic itself is not an obstacle
  'mirror',       // wall-mounted
  'pondWater',    // flat ground feature
  'rug',          // flat floor decoration
]);

// ── Grid Construction ─────────────────────────────────────────

/** Lazily-cached per-view grids: true = walkable */
const gridCache = new Map<OfficeView, boolean[]>();

function idx(gx: number, gy: number): number {
  return gy * GRID_W + gx;
}

function toGrid(px: number, py: number): [number, number] {
  return [Math.floor(px / CELL_SIZE), Math.floor(py / CELL_SIZE)];
}

function toPixel(gx: number, gy: number): Point {
  return { x: gx * CELL_SIZE + CELL_SIZE / 2, y: gy * CELL_SIZE + CELL_SIZE / 2 };
}

function clampGrid(gx: number, gy: number): [number, number] {
  return [
    Math.max(0, Math.min(GRID_W - 1, gx)),
    Math.max(0, Math.min(GRID_H - 1, gy)),
  ];
}

/** Mark a rectangular region (pixel coords) as walkable or blocked on a specific grid */
function fillRect(
  targetGrid: boolean[],
  px: number, py: number, pw: number, ph: number,
  walkable: boolean,
): void {
  const [x0, y0] = clampGrid(...toGrid(px, py));
  const [x1, y1] = clampGrid(...toGrid(px + pw - 1, py + ph - 1));
  for (let gy = y0; gy <= y1; gy++) {
    for (let gx = x0; gx <= x1; gx++) {
      targetGrid[idx(gx, gy)] = walkable;
    }
  }
}

const WALL_PAD = 5;
const FURN_PAD = 4;

/** Build (or return cached) walkability grid for a view */
function getGrid(view: OfficeView): boolean[] {
  const cached = gridCache.get(view);
  if (cached) return cached;

  const viewGrid: boolean[] = new Array(GRID_W * GRID_H).fill(false);

  // Step 1: Everything starts blocked (already false)

  // Step 2: Mark area interiors as walkable (with ~5px wall padding)
  const areas = getAreasForView(view);
  for (const area of areas) {
    const { x, y, width, height } = area.bounds;
    fillRect(
      viewGrid,
      x + WALL_PAD,
      y + WALL_PAD,
      width - WALL_PAD * 2,
      height - WALL_PAD * 2,
      true,
    );
  }

  // Step 3: Block furniture (with ~4px padding around each piece)
  for (const area of areas) {
    if (!area.furniture) continue;
    for (const f of area.furniture) {
      if (NON_BLOCKING_FURNITURE.has(f.type)) continue;
      fillRect(
        viewGrid,
        f.position.x - FURN_PAD,
        f.position.y - FURN_PAD,
        f.width + FURN_PAD * 2,
        f.height + FURN_PAD * 2,
        false,
      );
    }
  }

  // Step 4: Punch doorways through walls
  const doorways = VIEW_DOORWAYS[view] ?? [];
  for (const d of doorways) {
    fillRect(viewGrid, d.x, d.y, d.width, d.height, true);
  }

  gridCache.set(view, viewGrid);
  return viewGrid;
}

// ── A* Implementation ─────────────────────────────────────────

// 8-directional neighbours: [dx, dy]
const DIRS: [number, number][] = [
  [1, 0], [-1, 0], [0, 1], [0, -1],   // cardinal
  [1, 1], [1, -1], [-1, 1], [-1, -1], // diagonal
];

/** Binary min-heap for A* open set */
class MinHeap {
  private data: number[] = [];
  private costs: Float64Array;

  constructor(maxSize: number) {
    this.costs = new Float64Array(maxSize);
  }

  get length(): number {
    return this.data.length;
  }

  setCost(node: number, cost: number): void {
    this.costs[node] = cost;
  }

  push(node: number): void {
    this.data.push(node);
    this.bubbleUp(this.data.length - 1);
  }

  pop(): number {
    const top = this.data[0];
    const last = this.data.pop()!;
    if (this.data.length > 0) {
      this.data[0] = last;
      this.sinkDown(0);
    }
    return top;
  }

  private bubbleUp(i: number): void {
    const { data, costs } = this;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (costs[data[i]] >= costs[data[parent]]) break;
      [data[i], data[parent]] = [data[parent], data[i]];
      i = parent;
    }
  }

  private sinkDown(i: number): void {
    const { data, costs } = this;
    const len = data.length;
    while (true) {
      let smallest = i;
      const left = 2 * i + 1;
      const right = 2 * i + 2;
      if (left < len && costs[data[left]] < costs[data[smallest]]) smallest = left;
      if (right < len && costs[data[right]] < costs[data[smallest]]) smallest = right;
      if (smallest === i) break;
      [data[i], data[smallest]] = [data[smallest], data[i]];
      i = smallest;
    }
  }
}

/** Euclidean heuristic between two grid cells */
function heuristic(ax: number, ay: number, bx: number, by: number): number {
  const dx = ax - bx;
  const dy = ay - by;
  return Math.sqrt(dx * dx + dy * dy);
}

/** Raw A* on the grid. Returns path as array of grid [gx, gy] pairs, or null. */
function astarGrid(
  sx: number, sy: number,
  ex: number, ey: number,
  viewGrid: boolean[],
): [number, number][] | null {
  const totalCells = GRID_W * GRID_H;
  const startIdx = idx(sx, sy);
  const endIdx = idx(ex, ey);

  if (startIdx === endIdx) return [[ex, ey]];

  const gScore = new Float32Array(totalCells).fill(Infinity);
  const cameFrom = new Int32Array(totalCells).fill(-1);
  const closed = new Uint8Array(totalCells);

  gScore[startIdx] = 0;

  const open = new MinHeap(totalCells);
  open.setCost(startIdx, heuristic(sx, sy, ex, ey));
  open.push(startIdx);

  while (open.length > 0) {
    const current = open.pop();
    if (current === endIdx) {
      // Reconstruct
      const path: [number, number][] = [];
      let c = current;
      while (c !== -1) {
        path.push([c % GRID_W, Math.floor(c / GRID_W)]);
        c = cameFrom[c];
      }
      path.reverse();
      return path;
    }

    if (closed[current]) continue;
    closed[current] = 1;

    const cx = current % GRID_W;
    const cy = Math.floor(current / GRID_W);
    const currentG = gScore[current];

    for (const [ddx, ddy] of DIRS) {
      const nx = cx + ddx;
      const ny = cy + ddy;
      if (nx < 0 || nx >= GRID_W || ny < 0 || ny >= GRID_H) continue;

      const ni = idx(nx, ny);
      if (closed[ni] || !viewGrid[ni]) continue;

      // For diagonal moves, check that both adjacent cardinal cells are walkable
      // to prevent cutting corners through blocked cells
      if (ddx !== 0 && ddy !== 0) {
        if (!viewGrid[idx(cx + ddx, cy)] || !viewGrid[idx(cx, cy + ddy)]) continue;
      }

      const moveCost = (ddx !== 0 && ddy !== 0) ? DIAG_COST : 1;
      const tentativeG = currentG + moveCost;

      if (tentativeG < gScore[ni]) {
        gScore[ni] = tentativeG;
        cameFrom[ni] = current;
        const f = tentativeG + heuristic(nx, ny, ex, ey);
        open.setCost(ni, f);
        open.push(ni);
      }
    }
  }

  return null; // no path
}

// ── Path Smoothing ────────────────────────────────────────────

/**
 * Remove intermediate waypoints that lie on a straight line.
 * Checks collinearity by comparing direction vectors.
 */
function smoothPath(path: Point[]): Point[] {
  if (path.length <= 2) return path;

  const result: Point[] = [path[0]];

  for (let i = 1; i < path.length - 1; i++) {
    const prev = result[result.length - 1];
    const curr = path[i];
    const next = path[i + 1];

    // Direction from prev→curr vs prev→next
    const dx1 = curr.x - prev.x;
    const dy1 = curr.y - prev.y;
    const dx2 = next.x - prev.x;
    const dy2 = next.y - prev.y;

    // Cross product: if zero, points are collinear
    const cross = dx1 * dy2 - dy1 * dx2;
    if (Math.abs(cross) > 0.001) {
      result.push(curr);
    }
  }

  result.push(path[path.length - 1]);
  return result;
}

// ── Public API ────────────────────────────────────────────────

/**
 * Find a walkable grid cell nearest to the given pixel point.
 * Uses BFS expanding outward from the target cell.
 */
export function findNearestWalkable(point: Point, view: OfficeView = 'office'): Point {
  const viewGrid = getGrid(view);
  const [gx, gy] = clampGrid(...toGrid(point.x, point.y));
  if (viewGrid[idx(gx, gy)]) return toPixel(gx, gy);

  // BFS outward
  const visited = new Set<number>();
  const queue: [number, number][] = [[gx, gy]];
  visited.add(idx(gx, gy));

  while (queue.length > 0) {
    const [cx, cy] = queue.shift()!;
    for (const [ddx, ddy] of DIRS) {
      const nx = cx + ddx;
      const ny = cy + ddy;
      if (nx < 0 || nx >= GRID_W || ny < 0 || ny >= GRID_H) continue;
      const ni = idx(nx, ny);
      if (visited.has(ni)) continue;
      visited.add(ni);
      if (viewGrid[ni]) return toPixel(nx, ny);
      queue.push([nx, ny]);
    }
  }

  // Fallback (should never happen)
  return { ...point };
}

/**
 * Check if a pixel point is on a walkable grid cell.
 */
export function isWalkable(point: Point, view: OfficeView = 'office'): boolean {
  const viewGrid = getGrid(view);
  const [gx, gy] = clampGrid(...toGrid(point.x, point.y));
  return viewGrid[idx(gx, gy)];
}

/**
 * Find a path from one pixel position to another using A*.
 * Returns an array of waypoints in canvas pixel coordinates.
 * Returns empty array if no path is found.
 * Start and end points are snapped to nearest walkable cells if needed.
 */
export function findPath(from: Point, to: Point, view: OfficeView = 'office'): Point[] {
  const viewGrid = getGrid(view);

  // Snap to walkable cells
  const startWalkable = findNearestWalkable(from, view);
  const endWalkable = findNearestWalkable(to, view);

  const [sx, sy] = clampGrid(...toGrid(startWalkable.x, startWalkable.y));
  const [ex, ey] = clampGrid(...toGrid(endWalkable.x, endWalkable.y));

  // Already there?
  if (sx === ex && sy === ey) return [toPixel(ex, ey)];

  const gridPath = astarGrid(sx, sy, ex, ey, viewGrid);
  if (!gridPath) return []; // no path found

  // Convert grid cells to pixel coordinates
  const pixelPath = gridPath.map(([gx, gy]) => toPixel(gx, gy));

  // Smooth out redundant collinear waypoints
  return smoothPath(pixelPath);
}

/**
 * Calculate total distance of a path (in pixels).
 */
export function pathLength(path: Point[]): number {
  let total = 0;
  for (let i = 1; i < path.length; i++) {
    const dx = path[i].x - path[i - 1].x;
    const dy = path[i].y - path[i - 1].y;
    total += Math.sqrt(dx * dx + dy * dy);
  }
  return total;
}

/**
 * Calculate duration (ms) to traverse a path at a given speed (px/s).
 */
export function pathDuration(path: Point[], speed: number): number {
  if (path.length === 0) return 0;
  return (pathLength(path) / speed) * 1000;
}
