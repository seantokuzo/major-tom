// Office layout — ported from iOS OfficeLayout.swift
// IMPORTANT: All Y coordinates are INVERTED from SpriteKit (bottom-left origin)
// to Canvas (top-left origin). Formula: canvasY = 600 - spriteKitY

import type { Desk, OfficeArea, OfficeAreaType, Point, Rect } from './types';

export const SCENE_WIDTH = 800;
export const SCENE_HEIGHT = 600;

/** Convert a SpriteKit Y coordinate to Canvas Y coordinate */
function invertY(spriteKitY: number): number {
  return SCENE_HEIGHT - spriteKitY;
}

/** Convert a SpriteKit rect (origin at bottom-left of rect, in bottom-left scene)
 *  to Canvas rect (origin at top-left of rect, in top-left scene) */
function invertRect(x: number, skY: number, w: number, h: number): Rect {
  // In SpriteKit, (x, skY) is the bottom-left of the rect
  // In Canvas, we need the top-left: canvasY = 600 - (skY + h)
  return { x, y: SCENE_HEIGHT - skY - h, width: w, height: h };
}

// ── Door ─────────────────────────────────────────────────────

// iOS: CGPoint(x: 750, y: 500) → Canvas: (750, 100)
export const DOOR_POSITION: Point = { x: 750, y: invertY(500) };

// ── Areas ────────────────────────────────────────────────────

export const AREAS: OfficeArea[] = [
  {
    type: 'mainFloor',
    name: 'Main Floor',
    bounds: invertRect(200, 300, 600, 300),
    capacity: 8,
    color: 'rgb(46, 46, 56)',
  },
  {
    type: 'serverRoom',
    name: 'Server Room',
    bounds: invertRect(0, 400, 200, 200),
    capacity: 1,
    color: 'rgb(38, 51, 64)',
  },
  {
    type: 'breakRoom',
    name: 'Break Room',
    bounds: invertRect(0, 200, 200, 200),
    capacity: 4,
    color: 'rgb(56, 46, 51)',
  },
  {
    type: 'kitchen',
    name: 'Kitchen',
    bounds: invertRect(200, 100, 250, 200),
    capacity: 3,
    color: 'rgb(51, 51, 46)',
  },
  {
    type: 'dogCorner',
    name: 'Dog Corner',
    bounds: invertRect(450, 100, 350, 200),
    capacity: 4,
    color: 'rgb(51, 46, 38)',
  },
  {
    type: 'gym',
    name: 'Gym',
    bounds: invertRect(0, 0, 250, 100),
    capacity: 3,
    color: 'rgb(51, 38, 51)',
  },
  {
    type: 'dogPark',
    name: 'Dog Park',
    bounds: invertRect(250, 0, 250, 100),
    capacity: 4,
    color: 'rgb(38, 56, 38)',
  },
  {
    type: 'rollercoaster',
    name: 'Rollercoaster',
    bounds: invertRect(500, 0, 300, 100),
    capacity: 2,
    color: 'rgb(64, 46, 46)',
  },
];

// ── Desks ────────────────────────────────────────────────────

export const DESKS: Desk[] = [
  // Row 1 (top row in SpriteKit, stays top in canvas after inversion)
  { id: 0, position: { x: 300, y: invertY(520) }, occupantId: null },
  { id: 1, position: { x: 450, y: invertY(520) }, occupantId: null },
  { id: 2, position: { x: 600, y: invertY(520) }, occupantId: null },
  // Row 2
  { id: 3, position: { x: 300, y: invertY(440) }, occupantId: null },
  { id: 4, position: { x: 450, y: invertY(440) }, occupantId: null },
  { id: 5, position: { x: 600, y: invertY(440) }, occupantId: null },
  // Row 3
  { id: 6, position: { x: 300, y: invertY(360) }, occupantId: null },
  { id: 7, position: { x: 450, y: invertY(360) }, occupantId: null },
];

// ── Helpers ──────────────────────────────────────────────────

const areasByType = new Map<OfficeAreaType, OfficeArea>(
  AREAS.map((a) => [a.type, a])
);

/** Get a random position within an area (with padding from edges). */
export function randomPosition(areaType: OfficeAreaType): Point {
  const area = areasByType.get(areaType);
  if (!area) return DOOR_POSITION;

  const { x, y, width, height } = area.bounds;
  return {
    x: x + 30 + Math.random() * (width - 60),
    y: y + 20 + Math.random() * (height - 40),
  };
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
