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
];

export const DEFAULT_VIEW: OfficeView = 'office';

// ── Door ─────────────────────────────────────────────────────

// Main entrance — right side of the main office
export const DOOR_POSITION: Point = { x: 770, y: 200 };

// ── Color palette ────────────────────────────────────────────

const COLORS = {
  // Floors
  mainOfficeCarpet: 'rgb(52, 56, 68)',     // Blue-grey corporate carpet
  strategyCarpet:   'rgb(48, 52, 64)',     // Slightly darker blue carpet
  kitchenTile:      'rgb(58, 54, 50)',     // Warm kitchen tile
  breakWood:        'rgb(56, 48, 42)',     // Warm wood flooring

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
export function getViewForArea(_areaType: OfficeAreaType): OfficeView {
  return 'office';
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
