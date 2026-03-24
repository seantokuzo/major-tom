// Office layout — Pixel art tech startup office
// Top-down pixel art floor plan
//
// Canvas coordinate system: origin at top-left, Y increases downward.
// Scene is 1000x750 pixels.
//
// +------------------+----------------------------------------+
// |  STRATEGY ROOM   |          MAIN OFFICE                   |
// |                  |   (6 desks, plants, printer, etc.)     |
// +------------------+                                        |
// |  KITCHEN         |                                        |
// |                  |                                        |
// +------------------+----------------------------------------+
// |                    BREAK ROOM                             |
// +-----------------------------------------------------------+

import type { Desk, Furniture, OfficeArea, OfficeAreaType, OfficeView, OfficeViewConfig, Point } from './types';
import { ALL_CHARACTER_TYPES, ALL_BEDROOM_AREAS } from './types';
import { CHARACTER_CATALOG } from './characters';

export const SCENE_WIDTH = 1000;
export const SCENE_HEIGHT = 750;

// ── Views ────────────────────────────────────────────────────

export const OFFICE_VIEWS: OfficeViewConfig[] = [
  {
    id: 'office',
    label: 'Office',
    areas: ['mainOffice', 'strategyRoom', 'kitchen', 'breakRoom'],
  },
  {
    id: 'dogPark',
    label: 'Dog Park',
    areas: ['dogParkField', 'agilityCourse', 'dogPondArea'],
  },
  {
    id: 'gym',
    label: 'Gym',
    areas: ['gymFloor', 'yogaStudio', 'lockerRoom'],
  },
  {
    id: 'spriteStreet',
    label: 'Sprite St.',
    areas: ALL_BEDROOM_AREAS,
  },
];

export const DEFAULT_VIEW: OfficeView = 'office';

// ── Door ─────────────────────────────────────────────────────

// Main entrance — right side of the main office
export const DOOR_POSITION: Point = { x: 965, y: 250 };

/** Per-view door/entrance positions */
export const VIEW_DOOR_POSITIONS: Record<OfficeView, Point> = {
  office: { x: 965, y: 250 },
  dogPark: { x: 12, y: 375 },
  gym: { x: 12, y: 375 },
  spriteStreet: { x: 500, y: 12 },
};

/** Per-view room order for mobile layout */
export const VIEW_ROOM_ORDERS: Record<OfficeView, Array<{ type: string; label: string }>> = {
  office: [
    { type: 'mainOffice', label: 'Main Office' },
    { type: 'strategyRoom', label: 'Strategy Room' },
    { type: 'breakRoom', label: 'Break Room' },
    { type: 'kitchen', label: 'Kitchen' },
  ],
  dogPark: [
    { type: 'dogParkField', label: 'Dog Park' },
    { type: 'agilityCourse', label: 'Agility Course' },
    { type: 'dogPondArea', label: 'Dog Pond' },
  ],
  gym: [
    { type: 'gymFloor', label: 'Gym Floor' },
    { type: 'yogaStudio', label: 'Yoga Studio' },
    { type: 'lockerRoom', label: 'Locker Room' },
  ],
  spriteStreet: [
    { type: 'bedroomRow1Col1', label: 'Architect' },
    { type: 'bedroomRow1Col2', label: 'Lead Engineer' },
    { type: 'bedroomRow1Col3', label: 'Eng Manager' },
    { type: 'bedroomRow1Col4', label: 'Backend Engineer' },
    { type: 'bedroomRow1Col5', label: 'Frontend Engineer' },
    { type: 'bedroomRow1Col6', label: 'UX Designer' },
    { type: 'bedroomRow1Col7', label: 'Project Manager' },
    { type: 'bedroomRow2Col1', label: 'Product Manager' },
    { type: 'bedroomRow2Col2', label: 'DevOps' },
    { type: 'bedroomRow2Col3', label: 'Database Guru' },
    { type: 'bedroomRow2Col4', label: 'Elvito (Senor)' },
    { type: 'bedroomRow2Col5', label: 'Steve' },
    { type: 'bedroomRow2Col6', label: 'Hoku' },
    { type: 'bedroomRow2Col7', label: 'Kai' },
  ],
};

// ── Color palette ────────────────────────────────────────────

const COLORS = {
  // Floors — Office
  mainOfficeCarpet: 'rgb(52, 56, 68)',     // Blue-grey corporate carpet
  strategyCarpet:   'rgb(48, 52, 64)',     // Slightly darker blue carpet
  kitchenTile:      'rgb(58, 54, 50)',     // Warm kitchen tile
  breakWood:        'rgb(56, 48, 42)',     // Warm wood flooring

  // Floors — Dog Park
  parkGrass:        'rgb(62, 105, 48)',    // Lush green grass
  parkGrassDark:    'rgb(52, 90, 40)',     // Darker grass (agility course)
  pondBlue:         'rgb(60, 110, 140)',   // Pond water area

  // Floors — Gym
  gymWood:          'rgb(120, 90, 60)',    // Gym hardwood floor
  gymTile:          'rgb(180, 185, 190)',  // Clean studio/locker tile
  gymTileDark:      'rgb(160, 165, 172)',  // Slightly darker tile

  // Floors — Sprite Street
  bedroomWood:      'rgb(72, 58, 48)',     // Warm bedroom wood

  // Walls
  wall:             'rgb(72, 72, 82)',     // Interior walls
  wallHighlight:    'rgb(82, 82, 92)',     // Wall edge highlight
  doorFrame:        'rgb(120, 95, 65)',    // Door frames

  // Furniture
  deskWood:         'rgb(130, 95, 62)',    // Desk surface
  deskDark:         'rgb(95, 68, 42)',     // Desk shadow
  plant:            'rgb(52, 82, 48)',     // Office plants
};

// ── Sprite Street bedroom generator ──────────────────────────

/** Rug color palette — muted, cozy tones per bedroom */
const RUG_COLORS = [
  'rgba(140, 80, 70, 0.5)',   // terracotta
  'rgba(70, 100, 140, 0.5)',  // dusty blue
  'rgba(100, 130, 80, 0.5)',  // sage green
  'rgba(130, 100, 70, 0.5)',  // tan
  'rgba(120, 80, 120, 0.5)',  // muted plum
  'rgba(80, 120, 120, 0.5)',  // teal
  'rgba(140, 120, 70, 0.5)',  // gold
  'rgba(90, 90, 130, 0.5)',   // slate
  'rgba(130, 90, 90, 0.5)',   // dusty rose
  'rgba(80, 110, 100, 0.5)',  // sea green
  'rgba(120, 100, 80, 0.5)',  // warm brown
  'rgba(100, 80, 110, 0.5)',  // lavender
  'rgba(110, 110, 90, 0.5)',  // olive
  'rgba(90, 100, 120, 0.5)',  // steel blue
];

/** Build a character config lookup by type for bedroom colors */
const charConfigByType = new Map(CHARACTER_CATALOG.map(c => [c.type, c]));

function generateBedrooms(): OfficeArea[] {
  const areas: OfficeArea[] = [];
  const COL_W = 140;   // column width (135 room + 5 gap)
  const ROW_H = 370;   // row height (365 room + 5 gap)
  const ROOM_W = 135;
  const ROOM_H = 365;

  for (let row = 0; row < 2; row++) {
    for (let col = 0; col < 7; col++) {
      const idx = row * 7 + col;
      const charType = ALL_CHARACTER_TYPES[idx];
      const charConfig = charConfigByType.get(charType);
      const displayName = charConfig?.displayName ?? charType;
      const spriteColor = charConfig?.spriteColor ?? 'rgb(100, 100, 120)';
      const areaType = `bedroomRow${row + 1}Col${col + 1}` as OfficeAreaType;

      const bx = 5 + col * COL_W;
      const by = row === 0 ? 5 : 5 + ROW_H;

      const furniture: Furniture[] = [
        // Bed — centered horizontally near the top of the room
        { type: 'bed', position: { x: bx + 35, y: bx > 0 ? by + 60 : by + 60 }, width: 65, height: 80, color: spriteColor },
        // Mirror on top wall
        { type: 'mirror', position: { x: bx + 50, y: by + 8 }, width: 35, height: 8, color: 'rgb(180, 200, 220)' },
        // Closet — left side of room
        { type: 'closet', position: { x: bx + 8, y: by + 190 }, width: 35, height: 55, color: 'rgb(140, 110, 75)' },
        // Rug — center of room, flat/non-blocking
        { type: 'rug', position: { x: bx + 30, y: by + 270 }, width: 75, height: 50, color: RUG_COLORS[idx] },
      ];

      // Fix bed y position consistently
      furniture[0] = { type: 'bed', position: { x: bx + 35, y: by + 60 }, width: 65, height: 80, color: spriteColor };

      areas.push({
        type: areaType,
        name: `${displayName}'s Room`,
        bounds: { x: bx, y: by, width: ROOM_W, height: ROOM_H },
        capacity: 2,
        color: COLORS.bedroomWood,
        view: 'spriteStreet',
        floorPattern: 'wood',
        furniture,
      });
    }
  }

  return areas;
}

// ── Areas ────────────────────────────────────────────────────

export const AREAS: OfficeArea[] = [
  // ── Strategy Room (top-left) ─────────────────────────────
  {
    type: 'strategyRoom',
    name: 'Strategy Room',
    bounds: { x: 5, y: 5, width: 265, height: 235 },
    capacity: 6,
    color: COLORS.strategyCarpet,
    view: 'office',
    floorPattern: 'carpet',
    furniture: [
      // Whiteboard on top wall
      { type: 'whiteboard', position: { x: 38, y: 12 }, width: 150, height: 16, color: 'rgb(235, 235, 240)' },

      // Meeting table (large, center of room)
      { type: 'meetingTable', position: { x: 68, y: 88 }, width: 150, height: 75, color: 'rgb(100, 78, 52)' },

      // Chairs around table
      { type: 'meetingChair', position: { x: 88, y: 69 }, width: 18, height: 16, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 138, y: 69 }, width: 18, height: 16, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 188, y: 69 }, width: 18, height: 16, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 88, y: 169 }, width: 18, height: 16, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 138, y: 169 }, width: 18, height: 16, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 188, y: 169 }, width: 18, height: 16, color: 'rgb(60, 60, 70)' },

      // Clock on wall
      { type: 'clock', position: { x: 231, y: 18 }, width: 20, height: 20, color: 'rgb(220, 220, 230)' },

      // Plant in corner
      { type: 'plant', position: { x: 15, y: 206 }, width: 16, height: 16, color: COLORS.plant },
    ],
  },

  // ── Kitchen (bottom-left) ────────────────────────────────
  {
    type: 'kitchen',
    name: 'Kitchen',
    bounds: { x: 5, y: 250, width: 265, height: 235 },
    capacity: 4,
    color: COLORS.kitchenTile,
    view: 'office',
    floorPattern: 'tile',
    furniture: [
      // Kitchen counter along top wall (L-shape)
      { type: 'kitchenCounter', position: { x: 12, y: 256 }, width: 220, height: 26, color: 'rgb(88, 88, 92)' },
      { type: 'kitchenCounter', position: { x: 12, y: 256 }, width: 26, height: 100, color: 'rgb(88, 88, 92)' },

      // Sink on counter
      { type: 'sink', position: { x: 62, y: 258 }, width: 28, height: 18, color: 'rgb(160, 165, 175)' },

      // Coffee machine on counter
      { type: 'coffeeMachine', position: { x: 125, y: 258 }, width: 24, height: 18, color: 'rgb(45, 38, 35)' },

      // Microwave on counter
      { type: 'microwave', position: { x: 175, y: 258 }, width: 26, height: 18, color: 'rgb(58, 58, 64)' },

      // Fridge (tall, right side)
      { type: 'fridge', position: { x: 238, y: 256 }, width: 28, height: 52, color: 'rgb(200, 205, 210)' },

      // Toaster on counter
      { type: 'toaster', position: { x: 18, y: 294 }, width: 16, height: 14, color: 'rgb(180, 170, 155)' },

      // Small dining table
      { type: 'desk', position: { x: 100, y: 388 }, width: 85, height: 44, color: 'rgb(110, 82, 56)' },

      // Plants
      { type: 'plant', position: { x: 245, y: 460 }, width: 16, height: 16, color: COLORS.plant },
      { type: 'fern', position: { x: 15, y: 460 }, width: 18, height: 16, color: 'rgb(42, 92, 52)' },
    ],
  },

  // ── Main Office (right side, large) ──────────────────────
  {
    type: 'mainOffice',
    name: 'Main Office',
    bounds: { x: 280, y: 5, width: 715, height: 480 },
    capacity: 10,
    color: COLORS.mainOfficeCarpet,
    view: 'office',
    floorPattern: 'carpet',
    furniture: [
      // ── Decorative items on top wall (above desks) ──
      // Picture frames
      { type: 'pictureFrame', position: { x: 490, y: 15 }, width: 22, height: 18, color: 'rgb(140, 110, 70)' },
      { type: 'pictureFrame', position: { x: 630, y: 15 }, width: 22, height: 18, color: 'rgb(140, 110, 70)' },
      { type: 'pictureFrame', position: { x: 800, y: 15 }, width: 22, height: 18, color: 'rgb(140, 110, 70)' },

      // Clock on wall
      { type: 'clock', position: { x: 560, y: 15 }, width: 20, height: 20, color: 'rgb(220, 220, 230)' },

      // ── Desk row 1 (top row, 3 desks) ──
      { type: 'deskWithMonitor', position: { x: 400, y: 100 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 418, y: 140 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      { type: 'deskWithMonitor', position: { x: 560, y: 100 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 578, y: 140 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      { type: 'deskWithMonitor', position: { x: 720, y: 100 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 738, y: 140 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      // ── Desk row 2 (bottom row, 3 desks) ──
      { type: 'deskWithMonitor', position: { x: 400, y: 260 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 418, y: 300 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      { type: 'deskWithMonitor', position: { x: 560, y: 260 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 578, y: 300 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      { type: 'deskWithMonitor', position: { x: 720, y: 260 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 738, y: 300 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      // ── Office amenities ──
      // Water cooler (top right)
      { type: 'waterCooler', position: { x: 950, y: 40 }, width: 18, height: 32, color: 'rgb(100, 160, 220)' },

      // Printer
      { type: 'printer', position: { x: 900, y: 180 }, width: 40, height: 28, color: 'rgb(78, 78, 82)' },

      // Plants and ferns in corners
      { type: 'plant', position: { x: 290, y: 15 }, width: 16, height: 16, color: COLORS.plant },
      { type: 'fern', position: { x: 870, y: 15 }, width: 18, height: 16, color: 'rgb(42, 92, 52)' },
      { type: 'plant', position: { x: 290, y: 440 }, width: 16, height: 16, color: COLORS.plant },
      { type: 'fern', position: { x: 950, y: 400 }, width: 18, height: 16, color: 'rgb(42, 92, 52)' },

      // Door on right wall
      { type: 'door', position: { x: 960, y: 230 }, width: 10, height: 40, color: COLORS.doorFrame, label: 'DOOR' },
    ],
  },

  // ── Break Room (bottom, full width) ──────────────────────
  {
    type: 'breakRoom',
    name: 'Break Room',
    bounds: { x: 5, y: 495, width: 990, height: 250 },
    capacity: 8,
    color: COLORS.breakWood,
    view: 'office',
    floorPattern: 'wood',
    furniture: [
      // TV on top wall
      { type: 'tvScreen', position: { x: 75, y: 505 }, width: 75, height: 12, color: 'rgb(25, 25, 35)' },

      // Game console under TV
      { type: 'gameConsole', position: { x: 94, y: 522 }, width: 34, height: 14, color: 'rgb(30, 30, 40)' },

      // Couch facing TV (with more space)
      { type: 'couch', position: { x: 55, y: 565 }, width: 110, height: 34, color: 'rgb(82, 62, 48)' },

      // Bean bags (spaced out more)
      { type: 'beanBag', position: { x: 195, y: 580 }, width: 30, height: 28, color: 'rgb(140, 70, 55)' },
      { type: 'beanBag', position: { x: 240, y: 560 }, width: 30, height: 28, color: 'rgb(55, 90, 140)' },

      // Ping pong table (centered in room)
      { type: 'pingPongTable', position: { x: 420, y: 545 }, width: 120, height: 68, color: 'rgb(30, 100, 60)' },

      // Arcade machines (right-center)
      { type: 'arcadeMachine', position: { x: 660, y: 510 }, width: 34, height: 50, color: 'rgb(40, 35, 90)' },
      { type: 'arcadeMachine', position: { x: 710, y: 510 }, width: 34, height: 50, color: 'rgb(90, 35, 40)' },

      // Plants in corners
      { type: 'plant', position: { x: 15, y: 715 }, width: 16, height: 16, color: COLORS.plant },
      { type: 'fern', position: { x: 965, y: 715 }, width: 18, height: 16, color: 'rgb(42, 92, 52)' },
      { type: 'plant', position: { x: 965, y: 505 }, width: 16, height: 16, color: COLORS.plant },

      // Extra couch in the right area
      { type: 'couch', position: { x: 810, y: 570 }, width: 85, height: 34, color: 'rgb(72, 55, 50)' },

      // Small coffee table
      { type: 'desk', position: { x: 825, y: 620 }, width: 60, height: 28, color: 'rgb(100, 75, 50)' },
    ],
  },

  // ════════════════════════════════════════════════════════════
  // DOG PARK
  // ════════════════════════════════════════════════════════════

  // ── Dog Park Field (left ~60%, large grassy area) ──────────
  {
    type: 'dogParkField',
    name: 'Dog Park Field',
    bounds: { x: 5, y: 5, width: 600, height: 740 },
    capacity: 8,
    color: COLORS.parkGrass,
    view: 'dogPark',
    floorPattern: 'grass',
    furniture: [
      // Trees
      { type: 'tree', position: { x: 50, y: 38 }, width: 50, height: 62, color: 'rgb(45, 90, 35)' },
      { type: 'tree', position: { x: 438, y: 100 }, width: 45, height: 58, color: 'rgb(50, 95, 40)' },

      // Fire hydrant
      { type: 'fireHydrant', position: { x: 150, y: 125 }, width: 18, height: 25, color: 'rgb(200, 50, 40)' },

      // Dog bowl
      { type: 'dogBowl', position: { x: 250, y: 75 }, width: 20, height: 12, color: 'rgb(160, 160, 170)' },

      // Ball launcher
      { type: 'ballLauncher', position: { x: 350, y: 250 }, width: 30, height: 30, color: 'rgb(220, 140, 40)' },

      // Park benches
      { type: 'bench', position: { x: 75, y: 438 }, width: 62, height: 20, color: 'rgb(110, 80, 50)' },
      { type: 'bench', position: { x: 375, y: 562 }, width: 62, height: 20, color: 'rgb(110, 80, 50)' },

      // Fence along the right edge
      { type: 'fence', position: { x: 594, y: 12 }, width: 10, height: 726, color: 'rgb(160, 130, 80)' },

      // Door / entrance gate
      { type: 'door', position: { x: 5, y: 356 }, width: 12, height: 45, color: COLORS.doorFrame, label: 'GATE' },
    ],
  },

  // ── Agility Course (bottom-right quarter) ──────────────────
  {
    type: 'agilityCourse',
    name: 'Agility Course',
    bounds: { x: 615, y: 390, width: 380, height: 355 },
    capacity: 4,
    color: COLORS.parkGrassDark,
    view: 'dogPark',
    floorPattern: 'grass',
    furniture: [
      // Agility hoops
      { type: 'agilityHoop', position: { x: 662, y: 462 }, width: 30, height: 38, color: 'rgb(200, 60, 60)' },
      { type: 'agilityHoop', position: { x: 800, y: 462 }, width: 30, height: 38, color: 'rgb(60, 60, 200)' },

      // Agility ramp
      { type: 'agilityRamp', position: { x: 712, y: 562 }, width: 50, height: 25, color: 'rgb(180, 140, 60)' },

      // Fences (course boundary)
      { type: 'fence', position: { x: 620, y: 394 }, width: 370, height: 8, color: 'rgb(160, 130, 80)' },
      { type: 'fence', position: { x: 620, y: 732 }, width: 370, height: 8, color: 'rgb(160, 130, 80)' },
      { type: 'fence', position: { x: 620, y: 394 }, width: 8, height: 350, color: 'rgb(160, 130, 80)' },
    ],
  },

  // ── Dog Pond (top-right quarter) ───────────────────────────
  {
    type: 'dogPondArea',
    name: 'Dog Pond',
    bounds: { x: 615, y: 5, width: 380, height: 375 },
    capacity: 4,
    color: COLORS.pondBlue,
    view: 'dogPark',
    floorPattern: 'concrete',
    furniture: [
      // Pond water (large)
      { type: 'pondWater', position: { x: 662, y: 62 }, width: 250, height: 188, color: 'rgb(50, 100, 140)' },

      // Tree
      { type: 'tree', position: { x: 938, y: 38 }, width: 45, height: 58, color: 'rgb(48, 92, 38)' },

      // Bench by the pond
      { type: 'bench', position: { x: 675, y: 288 }, width: 62, height: 20, color: 'rgb(110, 80, 50)' },

      // Dog house
      { type: 'dogHouse', position: { x: 900, y: 275 }, width: 45, height: 40, color: 'rgb(140, 90, 50)' },
    ],
  },

  // ════════════════════════════════════════════════════════════
  // GYM
  // ════════════════════════════════════════════════════════════

  // ── Gym Floor (left ~60%, main weight room) ────────────────
  {
    type: 'gymFloor',
    name: 'Gym Floor',
    bounds: { x: 5, y: 5, width: 600, height: 740 },
    capacity: 8,
    color: COLORS.gymWood,
    view: 'gym',
    floorPattern: 'wood',
    furniture: [
      // Treadmills in a row
      { type: 'treadmill', position: { x: 125, y: 38 }, width: 45, height: 62, color: 'rgb(50, 50, 55)' },
      { type: 'treadmill', position: { x: 200, y: 38 }, width: 45, height: 62, color: 'rgb(50, 50, 55)' },
      { type: 'treadmill', position: { x: 275, y: 38 }, width: 45, height: 62, color: 'rgb(50, 50, 55)' },

      // Weight rack
      { type: 'weightRack', position: { x: 438, y: 188 }, width: 100, height: 38, color: 'rgb(70, 70, 75)' },

      // Punching bag
      { type: 'punchingBag', position: { x: 250, y: 375 }, width: 25, height: 50, color: 'rgb(140, 50, 40)' },

      // Mirror on wall (left side)
      { type: 'mirror', position: { x: 15, y: 162 }, width: 10, height: 200, color: 'rgb(180, 200, 220)' },

      // Water fountain
      { type: 'waterFountain', position: { x: 525, y: 38 }, width: 25, height: 30, color: 'rgb(160, 170, 180)' },

      // Door
      { type: 'door', position: { x: 5, y: 356 }, width: 12, height: 45, color: COLORS.doorFrame, label: 'DOOR' },
    ],
  },

  // ── Yoga Studio (bottom-right) ─────────────────────────────
  {
    type: 'yogaStudio',
    name: 'Yoga Studio',
    bounds: { x: 615, y: 390, width: 380, height: 355 },
    capacity: 4,
    color: COLORS.gymTile,
    view: 'gym',
    floorPattern: 'tile',
    furniture: [
      // Yoga mats
      { type: 'yogaMat', position: { x: 650, y: 462 }, width: 50, height: 75, color: 'rgb(120, 60, 140)' },
      { type: 'yogaMat', position: { x: 738, y: 462 }, width: 50, height: 75, color: 'rgb(60, 140, 120)' },
      { type: 'yogaMat', position: { x: 825, y: 462 }, width: 50, height: 75, color: 'rgb(140, 120, 60)' },

      // Exercise ball
      { type: 'exerciseBall', position: { x: 925, y: 475 }, width: 32, height: 32, color: 'rgb(200, 80, 80)' },

      // Mirror on top wall
      { type: 'mirror', position: { x: 650, y: 394 }, width: 250, height: 10, color: 'rgb(180, 200, 220)' },
    ],
  },

  // ── Locker Room (top-right) ────────────────────────────────
  {
    type: 'lockerRoom',
    name: 'Locker Room',
    bounds: { x: 615, y: 5, width: 380, height: 375 },
    capacity: 4,
    color: COLORS.gymTileDark,
    view: 'gym',
    floorPattern: 'tile',
    furniture: [
      // Lockers
      { type: 'locker', position: { x: 925, y: 25 }, width: 38, height: 50, color: 'rgb(100, 110, 130)' },
      { type: 'locker', position: { x: 925, y: 88 }, width: 38, height: 50, color: 'rgb(100, 110, 130)' },
      { type: 'locker', position: { x: 925, y: 150 }, width: 38, height: 50, color: 'rgb(110, 100, 130)' },

      // Water fountain
      { type: 'waterFountain', position: { x: 650, y: 25 }, width: 25, height: 30, color: 'rgb(160, 170, 180)' },

      // Bench
      { type: 'bench', position: { x: 700, y: 225 }, width: 75, height: 20, color: 'rgb(110, 80, 50)' },

      // Mirror
      { type: 'mirror', position: { x: 700, y: 300 }, width: 100, height: 10, color: 'rgb(180, 200, 220)' },
    ],
  },

  // ════════════════════════════════════════════════════════════
  // SPRITE STREET — personal bedrooms (7 cols × 2 rows)
  // ════════════════════════════════════════════════════════════
  ...generateBedrooms(),
];

// ── Desks (agent assignment targets) ─────────────────────────
// 6 desks in a 2x3 grid in the main office.
// Agents sit just below their desk.

export const DESKS: Desk[] = [
  // Row 1
  { id: 0, position: { x: 428, y: 145 }, occupantId: null, label: 'Desk 1' },
  { id: 1, position: { x: 588, y: 145 }, occupantId: null, label: 'Desk 2' },
  { id: 2, position: { x: 748, y: 145 }, occupantId: null, label: 'Desk 3' },
  // Row 2
  { id: 3, position: { x: 428, y: 305 }, occupantId: null, label: 'Desk 4' },
  { id: 4, position: { x: 588, y: 305 }, occupantId: null, label: 'Desk 5' },
  { id: 5, position: { x: 748, y: 305 }, occupantId: null, label: 'Desk 6' },
];

// ── View-filtered accessors ──────────────────────────────────

const areasByType = new Map<OfficeAreaType, OfficeArea>(
  AREAS.map((a) => [a.type, a])
);

const areasByView = new Map<OfficeView, OfficeArea[]>();
for (const area of AREAS) {
  const list = areasByView.get(area.view) ?? [];
  list.push(area);
  areasByView.set(area.view, list);
}

/** Get all areas for a specific view */
export function getAreasForView(view: OfficeView): OfficeArea[] {
  return areasByView.get(view) ?? [];
}

/** Get a random position within an area (with padding from edges). */
export function randomPosition(areaType: OfficeAreaType): Point {
  const area = areasByType.get(areaType);
  if (!area) return DOOR_POSITION;

  const { x, y, width, height } = area.bounds;
  return {
    x: x + 30 + Math.random() * (width - 60),
    y: y + 30 + Math.random() * (height - 60),
  };
}

/** Get the view that contains this area type */
export function getViewForArea(areaType: OfficeAreaType): OfficeView {
  const area = areasByType.get(areaType);
  return area?.view ?? 'office';
}

/** Get the area at a given point. */
export function getAreaAtPoint(point: Point): OfficeArea | null {
  return (
    AREAS.find(
      (a) =>
        point.x >= a.bounds.x &&
        point.x <= a.bounds.x + a.bounds.width &&
        point.y >= a.bounds.y &&
        point.y <= a.bounds.y + a.bounds.height
    ) ?? null
  );
}
