// Office layout — Pixel art tech startup office
// Top-down pixel art floor plan
//
// Canvas coordinate system: origin at top-left, Y increases downward.
// Scene is 800x600 pixels.
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

export const SCENE_WIDTH = 800;
export const SCENE_HEIGHT = 600;

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
    id: 'themePark',
    label: 'Theme Park',
    areas: ['mainPlaza', 'rollerCoasterZone', 'arcadeHall'],
  },
];

export const DEFAULT_VIEW: OfficeView = 'office';

// ── Door ─────────────────────────────────────────────────────

// Main entrance — right side of the main office
export const DOOR_POSITION: Point = { x: 770, y: 200 };

/** Per-view door/entrance positions */
export const VIEW_DOOR_POSITIONS: Record<OfficeView, Point> = {
  office: { x: 770, y: 200 },
  dogPark: { x: 10, y: 300 },
  gym: { x: 10, y: 300 },
  themePark: { x: 400, y: 10 },
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
  themePark: [
    { type: 'mainPlaza', label: 'Main Plaza' },
    { type: 'rollerCoasterZone', label: 'Roller Coaster' },
    { type: 'arcadeHall', label: 'Arcade Hall' },
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

  // Floors — Theme Park
  parkCobblestone:  'rgb(140, 135, 125)',  // Cobblestone pathways
  parkConcrete:     'rgb(120, 115, 110)',  // Ride zones concrete

  // Walls
  wall:             'rgb(72, 72, 82)',     // Interior walls
  wallHighlight:    'rgb(82, 82, 92)',     // Wall edge highlight
  doorFrame:        'rgb(120, 95, 65)',    // Door frames

  // Furniture
  deskWood:         'rgb(130, 95, 62)',    // Desk surface
  deskDark:         'rgb(95, 68, 42)',     // Desk shadow
  plant:            'rgb(52, 82, 48)',     // Office plants
};

// ── Areas ────────────────────────────────────────────────────

export const AREAS: OfficeArea[] = [
  // ── Strategy Room (top-left) ─────────────────────────────
  {
    type: 'strategyRoom',
    name: 'Strategy Room',
    bounds: { x: 5, y: 5, width: 220, height: 190 },
    capacity: 6,
    color: COLORS.strategyCarpet,
    view: 'office',
    floorPattern: 'carpet',
    furniture: [
      // Whiteboard on top wall
      { type: 'whiteboard', position: { x: 30, y: 10 }, width: 120, height: 14, color: 'rgb(235, 235, 240)' },

      // Meeting table (large, center of room)
      { type: 'meetingTable', position: { x: 55, y: 70 }, width: 120, height: 60, color: 'rgb(100, 78, 52)' },

      // Chairs around table
      { type: 'meetingChair', position: { x: 70, y: 55 }, width: 16, height: 14, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 110, y: 55 }, width: 16, height: 14, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 150, y: 55 }, width: 16, height: 14, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 70, y: 135 }, width: 16, height: 14, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 110, y: 135 }, width: 16, height: 14, color: 'rgb(60, 60, 70)' },
      { type: 'meetingChair', position: { x: 150, y: 135 }, width: 16, height: 14, color: 'rgb(60, 60, 70)' },

      // Clock on wall
      { type: 'clock', position: { x: 185, y: 14 }, width: 18, height: 18, color: 'rgb(220, 220, 230)' },

      // Plant in corner
      { type: 'plant', position: { x: 12, y: 165 }, width: 14, height: 14, color: COLORS.plant },
    ],
  },

  // ── Kitchen (bottom-left) ────────────────────────────────
  {
    type: 'kitchen',
    name: 'Kitchen',
    bounds: { x: 5, y: 205, width: 220, height: 190 },
    capacity: 4,
    color: COLORS.kitchenTile,
    view: 'office',
    floorPattern: 'tile',
    furniture: [
      // Kitchen counter along top wall (L-shape)
      { type: 'kitchenCounter', position: { x: 10, y: 210 }, width: 180, height: 22, color: 'rgb(88, 88, 92)' },
      { type: 'kitchenCounter', position: { x: 10, y: 210 }, width: 22, height: 80, color: 'rgb(88, 88, 92)' },

      // Sink on counter
      { type: 'sink', position: { x: 50, y: 212 }, width: 24, height: 16, color: 'rgb(160, 165, 175)' },

      // Coffee machine on counter
      { type: 'coffeeMachine', position: { x: 100, y: 212 }, width: 20, height: 16, color: 'rgb(45, 38, 35)' },

      // Microwave on counter
      { type: 'microwave', position: { x: 140, y: 212 }, width: 22, height: 16, color: 'rgb(58, 58, 64)' },

      // Fridge (tall, right side)
      { type: 'fridge', position: { x: 195, y: 210 }, width: 24, height: 44, color: 'rgb(200, 205, 210)' },

      // Toaster on counter
      { type: 'toaster', position: { x: 14, y: 240 }, width: 14, height: 12, color: 'rgb(180, 170, 155)' },

      // Small dining table
      { type: 'desk', position: { x: 80, y: 310, }, width: 70, height: 36, color: 'rgb(110, 82, 56)' },

      // Plants
      { type: 'plant', position: { x: 200, y: 370 }, width: 14, height: 14, color: COLORS.plant },
      { type: 'fern', position: { x: 12, y: 370 }, width: 16, height: 14, color: 'rgb(42, 92, 52)' },
    ],
  },

  // ── Main Office (right side, large) ──────────────────────
  {
    type: 'mainOffice',
    name: 'Main Office',
    bounds: { x: 235, y: 5, width: 560, height: 390 },
    capacity: 10,
    color: COLORS.mainOfficeCarpet,
    view: 'office',
    floorPattern: 'carpet',
    furniture: [
      // ── Desk row 1 (top row, 3 desks) ──
      { type: 'deskWithMonitor', position: { x: 280, y: 45 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 298, y: 80 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      { type: 'deskWithMonitor', position: { x: 420, y: 45 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 438, y: 80 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      { type: 'deskWithMonitor', position: { x: 560, y: 45 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 578, y: 80 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      // ── Desk row 2 (bottom row, 3 desks) ──
      { type: 'deskWithMonitor', position: { x: 280, y: 165 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 298, y: 200 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      { type: 'deskWithMonitor', position: { x: 420, y: 165 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 438, y: 200 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      { type: 'deskWithMonitor', position: { x: 560, y: 165 }, width: 56, height: 30, color: COLORS.deskWood },
      { type: 'officeChair', position: { x: 578, y: 200 }, width: 18, height: 16, color: 'rgb(55, 55, 65)' },

      // ── Office amenities ──
      // Water cooler (bottom right)
      { type: 'waterCooler', position: { x: 750, y: 30 }, width: 16, height: 28, color: 'rgb(100, 160, 220)' },

      // Printer
      { type: 'printer', position: { x: 700, y: 120 }, width: 36, height: 24, color: 'rgb(78, 78, 82)' },

      // Plants and ferns
      { type: 'plant', position: { x: 245, y: 12 }, width: 14, height: 14, color: COLORS.plant },
      { type: 'fern', position: { x: 680, y: 12 }, width: 16, height: 14, color: 'rgb(42, 92, 52)' },
      { type: 'plant', position: { x: 245, y: 260 }, width: 14, height: 14, color: COLORS.plant },
      { type: 'fern', position: { x: 750, y: 300 }, width: 16, height: 14, color: 'rgb(42, 92, 52)' },

      // Picture frames on top wall
      { type: 'pictureFrame', position: { x: 370, y: 10 }, width: 20, height: 16, color: 'rgb(140, 110, 70)' },
      { type: 'pictureFrame', position: { x: 510, y: 10 }, width: 20, height: 16, color: 'rgb(140, 110, 70)' },
      { type: 'pictureFrame', position: { x: 650, y: 10 }, width: 20, height: 16, color: 'rgb(140, 110, 70)' },

      // Clock on wall
      { type: 'clock', position: { x: 440, y: 10 }, width: 18, height: 18, color: 'rgb(220, 220, 230)' },

      // Door on right wall
      { type: 'door', position: { x: 760, y: 185 }, width: 10, height: 36, color: COLORS.doorFrame, label: 'DOOR' },
    ],
  },

  // ── Break Room (bottom, full width) ──────────────────────
  {
    type: 'breakRoom',
    name: 'Break Room',
    bounds: { x: 5, y: 405, width: 790, height: 190 },
    capacity: 8,
    color: COLORS.breakWood,
    view: 'office',
    floorPattern: 'wood',
    furniture: [
      // TV on top wall
      { type: 'tvScreen', position: { x: 60, y: 410 }, width: 60, height: 10, color: 'rgb(25, 25, 35)' },

      // Game console under TV
      { type: 'gameConsole', position: { x: 75, y: 425 }, width: 28, height: 12, color: 'rgb(30, 30, 40)' },

      // Couch facing TV
      { type: 'couch', position: { x: 45, y: 460 }, width: 90, height: 28, color: 'rgb(82, 62, 48)' },

      // Bean bags
      { type: 'beanBag', position: { x: 155, y: 470 }, width: 26, height: 24, color: 'rgb(140, 70, 55)' },
      { type: 'beanBag', position: { x: 190, y: 458 }, width: 26, height: 24, color: 'rgb(55, 90, 140)' },

      // Ping pong table (center)
      { type: 'pingPongTable', position: { x: 320, y: 440 }, width: 100, height: 56, color: 'rgb(30, 100, 60)' },

      // Arcade machine (right side)
      { type: 'arcadeMachine', position: { x: 530, y: 412 }, width: 30, height: 44, color: 'rgb(40, 35, 90)' },

      // Second arcade machine
      { type: 'arcadeMachine', position: { x: 570, y: 412 }, width: 30, height: 44, color: 'rgb(90, 35, 40)' },

      // Plants
      { type: 'plant', position: { x: 12, y: 565 }, width: 14, height: 14, color: COLORS.plant },
      { type: 'fern', position: { x: 770, y: 565 }, width: 16, height: 14, color: 'rgb(42, 92, 52)' },
      { type: 'plant', position: { x: 770, y: 415 }, width: 14, height: 14, color: COLORS.plant },

      // Extra couch in the right area
      { type: 'couch', position: { x: 650, y: 460 }, width: 70, height: 28, color: 'rgb(72, 55, 50)' },

      // Small coffee table
      { type: 'desk', position: { x: 660, y: 500 }, width: 50, height: 24, color: 'rgb(100, 75, 50)' },
    ],
  },

  // ════════════════════════════════════════════════════════════
  // DOG PARK
  // ════════════════════════════════════════════════════════════

  // ── Dog Park Field (left ~60%, large grassy area) ──────────
  {
    type: 'dogParkField',
    name: 'Dog Park Field',
    bounds: { x: 5, y: 5, width: 480, height: 590 },
    capacity: 8,
    color: COLORS.parkGrass,
    view: 'dogPark',
    floorPattern: 'grass',
    furniture: [
      // Trees
      { type: 'tree', position: { x: 40, y: 30 }, width: 40, height: 50, color: 'rgb(45, 90, 35)' },
      { type: 'tree', position: { x: 350, y: 80 }, width: 36, height: 46, color: 'rgb(50, 95, 40)' },

      // Fire hydrant
      { type: 'fireHydrant', position: { x: 120, y: 100 }, width: 14, height: 20, color: 'rgb(200, 50, 40)' },

      // Dog bowl
      { type: 'dogBowl', position: { x: 200, y: 60 }, width: 16, height: 10, color: 'rgb(160, 160, 170)' },

      // Ball launcher
      { type: 'ballLauncher', position: { x: 280, y: 200 }, width: 24, height: 24, color: 'rgb(220, 140, 40)' },

      // Park benches
      { type: 'bench', position: { x: 60, y: 350 }, width: 50, height: 16, color: 'rgb(110, 80, 50)' },
      { type: 'bench', position: { x: 300, y: 450 }, width: 50, height: 16, color: 'rgb(110, 80, 50)' },

      // Fence along the right edge
      { type: 'fence', position: { x: 475, y: 10 }, width: 8, height: 580, color: 'rgb(160, 130, 80)' },

      // Door / entrance gate
      { type: 'door', position: { x: 5, y: 285 }, width: 10, height: 36, color: COLORS.doorFrame, label: 'GATE' },
    ],
  },

  // ── Agility Course (bottom-right quarter) ──────────────────
  {
    type: 'agilityCourse',
    name: 'Agility Course',
    bounds: { x: 495, y: 310, width: 300, height: 285 },
    capacity: 4,
    color: COLORS.parkGrassDark,
    view: 'dogPark',
    floorPattern: 'grass',
    furniture: [
      // Agility hoops
      { type: 'agilityHoop', position: { x: 530, y: 370 }, width: 24, height: 30, color: 'rgb(200, 60, 60)' },
      { type: 'agilityHoop', position: { x: 640, y: 370 }, width: 24, height: 30, color: 'rgb(60, 60, 200)' },

      // Agility ramp
      { type: 'agilityRamp', position: { x: 570, y: 450 }, width: 40, height: 20, color: 'rgb(180, 140, 60)' },

      // Fences (course boundary)
      { type: 'fence', position: { x: 500, y: 315 }, width: 290, height: 6, color: 'rgb(160, 130, 80)' },
      { type: 'fence', position: { x: 500, y: 585 }, width: 290, height: 6, color: 'rgb(160, 130, 80)' },
      { type: 'fence', position: { x: 500, y: 315 }, width: 6, height: 280, color: 'rgb(160, 130, 80)' },
    ],
  },

  // ── Dog Pond (top-right quarter) ───────────────────────────
  {
    type: 'dogPondArea',
    name: 'Dog Pond',
    bounds: { x: 495, y: 5, width: 300, height: 295 },
    capacity: 4,
    color: COLORS.pondBlue,
    view: 'dogPark',
    floorPattern: 'concrete',
    furniture: [
      // Pond water (large)
      { type: 'pondWater', position: { x: 530, y: 50 }, width: 200, height: 150, color: 'rgb(50, 100, 140)' },

      // Tree
      { type: 'tree', position: { x: 750, y: 30 }, width: 36, height: 46, color: 'rgb(48, 92, 38)' },

      // Bench by the pond
      { type: 'bench', position: { x: 540, y: 230 }, width: 50, height: 16, color: 'rgb(110, 80, 50)' },

      // Dog house
      { type: 'dogHouse', position: { x: 720, y: 220 }, width: 36, height: 32, color: 'rgb(140, 90, 50)' },
    ],
  },

  // ════════════════════════════════════════════════════════════
  // GYM
  // ════════════════════════════════════════════════════════════

  // ── Gym Floor (left ~60%, main weight room) ────────────────
  {
    type: 'gymFloor',
    name: 'Gym Floor',
    bounds: { x: 5, y: 5, width: 480, height: 590 },
    capacity: 8,
    color: COLORS.gymWood,
    view: 'gym',
    floorPattern: 'wood',
    furniture: [
      // Treadmills in a row
      { type: 'treadmill', position: { x: 100, y: 30 }, width: 36, height: 50, color: 'rgb(50, 50, 55)' },
      { type: 'treadmill', position: { x: 160, y: 30 }, width: 36, height: 50, color: 'rgb(50, 50, 55)' },
      { type: 'treadmill', position: { x: 220, y: 30 }, width: 36, height: 50, color: 'rgb(50, 50, 55)' },

      // Weight rack
      { type: 'weightRack', position: { x: 350, y: 150 }, width: 80, height: 30, color: 'rgb(70, 70, 75)' },

      // Punching bag
      { type: 'punchingBag', position: { x: 200, y: 300 }, width: 20, height: 40, color: 'rgb(140, 50, 40)' },

      // Mirror on wall (left side)
      { type: 'mirror', position: { x: 12, y: 130 }, width: 8, height: 160, color: 'rgb(180, 200, 220)' },

      // Water fountain
      { type: 'waterFountain', position: { x: 420, y: 30 }, width: 20, height: 24, color: 'rgb(160, 170, 180)' },

      // Door
      { type: 'door', position: { x: 5, y: 285 }, width: 10, height: 36, color: COLORS.doorFrame, label: 'DOOR' },
    ],
  },

  // ── Yoga Studio (bottom-right) ─────────────────────────────
  {
    type: 'yogaStudio',
    name: 'Yoga Studio',
    bounds: { x: 495, y: 310, width: 300, height: 285 },
    capacity: 4,
    color: COLORS.gymTile,
    view: 'gym',
    floorPattern: 'tile',
    furniture: [
      // Yoga mats
      { type: 'yogaMat', position: { x: 520, y: 370 }, width: 40, height: 60, color: 'rgb(120, 60, 140)' },
      { type: 'yogaMat', position: { x: 590, y: 370 }, width: 40, height: 60, color: 'rgb(60, 140, 120)' },
      { type: 'yogaMat', position: { x: 660, y: 370 }, width: 40, height: 60, color: 'rgb(140, 120, 60)' },

      // Exercise ball
      { type: 'exerciseBall', position: { x: 740, y: 380 }, width: 26, height: 26, color: 'rgb(200, 80, 80)' },

      // Mirror on top wall
      { type: 'mirror', position: { x: 520, y: 315 }, width: 200, height: 8, color: 'rgb(180, 200, 220)' },
    ],
  },

  // ── Locker Room (top-right) ────────────────────────────────
  {
    type: 'lockerRoom',
    name: 'Locker Room',
    bounds: { x: 495, y: 5, width: 300, height: 295 },
    capacity: 4,
    color: COLORS.gymTileDark,
    view: 'gym',
    floorPattern: 'tile',
    furniture: [
      // Lockers
      { type: 'locker', position: { x: 740, y: 20 }, width: 30, height: 40, color: 'rgb(100, 110, 130)' },
      { type: 'locker', position: { x: 740, y: 70 }, width: 30, height: 40, color: 'rgb(100, 110, 130)' },
      { type: 'locker', position: { x: 740, y: 120 }, width: 30, height: 40, color: 'rgb(110, 100, 130)' },

      // Water fountain
      { type: 'waterFountain', position: { x: 520, y: 20 }, width: 20, height: 24, color: 'rgb(160, 170, 180)' },

      // Bench
      { type: 'bench', position: { x: 560, y: 180 }, width: 60, height: 16, color: 'rgb(110, 80, 50)' },

      // Mirror
      { type: 'mirror', position: { x: 560, y: 240 }, width: 80, height: 8, color: 'rgb(180, 200, 220)' },
    ],
  },

  // ════════════════════════════════════════════════════════════
  // THEME PARK
  // ════════════════════════════════════════════════════════════

  // ── Main Plaza (top half of canvas) ────────────────────────
  {
    type: 'mainPlaza',
    name: 'Main Plaza',
    bounds: { x: 5, y: 5, width: 790, height: 290 },
    capacity: 8,
    color: COLORS.parkCobblestone,
    view: 'themePark',
    floorPattern: 'cobblestone',
    furniture: [
      // Ticket booth
      { type: 'ticketBooth', position: { x: 60, y: 40 }, width: 50, height: 40, color: 'rgb(180, 50, 50)' },

      // Hot dog stand
      { type: 'hotDogStand', position: { x: 300, y: 120 }, width: 50, height: 36, color: 'rgb(200, 160, 40)' },

      // Cotton candy cart
      { type: 'cottonCandyCart', position: { x: 480, y: 120 }, width: 44, height: 36, color: 'rgb(240, 140, 200)' },

      // Balloon cart
      { type: 'balloonCart', position: { x: 650, y: 50 }, width: 36, height: 40, color: 'rgb(80, 160, 220)' },

      // Benches
      { type: 'bench', position: { x: 200, y: 230 }, width: 50, height: 16, color: 'rgb(110, 80, 50)' },
      { type: 'bench', position: { x: 550, y: 230 }, width: 50, height: 16, color: 'rgb(110, 80, 50)' },

      // Door / entrance gate (top center)
      { type: 'door', position: { x: 395, y: 5 }, width: 36, height: 10, color: COLORS.doorFrame, label: 'GATE' },
    ],
  },

  // ── Roller Coaster Zone (bottom-left) ──────────────────────
  {
    type: 'rollerCoasterZone',
    name: 'Roller Coaster Zone',
    bounds: { x: 5, y: 305, width: 390, height: 290 },
    capacity: 6,
    color: COLORS.parkConcrete,
    view: 'themePark',
    floorPattern: 'concrete',
    furniture: [
      // Roller coaster track (large)
      { type: 'rollerCoasterTrack', position: { x: 30, y: 330 }, width: 250, height: 120, color: 'rgb(180, 50, 50)' },

      // Ferris wheel
      { type: 'ferrisWheel', position: { x: 280, y: 400 }, width: 100, height: 100, color: 'rgb(220, 180, 60)' },
    ],
  },

  // ── Arcade Hall (bottom-right) ─────────────────────────────
  {
    type: 'arcadeHall',
    name: 'Arcade Hall',
    bounds: { x: 405, y: 305, width: 390, height: 290 },
    capacity: 6,
    color: COLORS.parkCobblestone,
    view: 'themePark',
    floorPattern: 'cobblestone',
    furniture: [
      // Carousel
      { type: 'carousel', position: { x: 500, y: 370 }, width: 120, height: 120, color: 'rgb(200, 160, 80)' },

      // Arcade machines
      { type: 'arcadeMachine', position: { x: 660, y: 330 }, width: 30, height: 44, color: 'rgb(40, 35, 90)' },
      { type: 'arcadeMachine', position: { x: 710, y: 330 }, width: 30, height: 44, color: 'rgb(90, 35, 40)' },

      // Ticket booth
      { type: 'ticketBooth', position: { x: 430, y: 520 }, width: 50, height: 40, color: 'rgb(180, 50, 50)' },
    ],
  },
];

// ── Desks (agent assignment targets) ─────────────────────────
// 6 desks in a 2x3 grid in the main office.
// Agents sit just below their desk.

export const DESKS: Desk[] = [
  // Row 1
  { id: 0, position: { x: 308, y: 85 }, occupantId: null, label: 'Desk 1' },
  { id: 1, position: { x: 448, y: 85 }, occupantId: null, label: 'Desk 2' },
  { id: 2, position: { x: 588, y: 85 }, occupantId: null, label: 'Desk 3' },
  // Row 2
  { id: 3, position: { x: 308, y: 205 }, occupantId: null, label: 'Desk 4' },
  { id: 4, position: { x: 448, y: 205 }, occupantId: null, label: 'Desk 5' },
  { id: 5, position: { x: 588, y: 205 }, occupantId: null, label: 'Desk 6' },
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
