// Office types — Cute creatures + dogs
// ported from iOS AgentState.swift + CharacterConfig.swift

// ── Enums ────────────────────────────────────────────────────

export type AgentStatus = 'spawning' | 'walking' | 'working' | 'idle' | 'celebrating' | 'leaving';

export type CharacterType =
  // Humans — tech specialists
  | 'architect'
  | 'leadEngineer'
  | 'engManager'
  | 'backendEngineer'
  | 'frontendEngineer'
  | 'uxDesigner'
  | 'projectManager'
  | 'productManager'
  | 'devops'
  | 'databaseGuru'
  // Dogs
  | 'dachshund'
  | 'cattleDog'
  | 'schnauzerBlack'
  | 'schnauzerPepper';

export const ALL_CHARACTER_TYPES: CharacterType[] = [
  'architect',
  'leadEngineer',
  'engManager',
  'backendEngineer',
  'frontendEngineer',
  'uxDesigner',
  'projectManager',
  'productManager',
  'devops',
  'databaseGuru',
  'dachshund',
  'cattleDog',
  'schnauzerBlack',
  'schnauzerPepper',
];

export type BreakDestination =
  | 'strategyRoom'
  | 'kitchen'
  | 'breakRoom';

export type OfficeAreaType =
  | 'mainOffice'
  | 'strategyRoom'
  | 'kitchen'
  | 'breakRoom';

/** Office view — single unified view */
export type OfficeView = 'office';

export interface OfficeViewConfig {
  id: OfficeView;
  label: string;
  /** Which area types are visible in this view */
  areas: OfficeAreaType[];
}

// ── Furniture types for richer rendering ─────────────────────

export type FurnitureType =
  | 'desk'
  | 'deskWithMonitor'
  | 'officeChair'
  | 'meetingTable'
  | 'meetingChair'
  | 'whiteboard'
  | 'fridge'
  | 'microwave'
  | 'toaster'
  | 'kitchenCounter'
  | 'sink'
  | 'coffeeMachine'
  | 'couch'
  | 'beanBag'
  | 'plant'
  | 'fern'
  | 'waterCooler'
  | 'printer'
  | 'tvScreen'
  | 'pingPongTable'
  | 'gameConsole'
  | 'arcadeMachine'
  | 'clock'
  | 'pictureFrame'
  | 'door'
  | 'wallSegment';

export interface Furniture {
  type: FurnitureType;
  position: Point;
  width: number;
  height: number;
  color: string;
  label?: string;
  /** Optional rotation in radians */
  rotation?: number;
}

// ── Interfaces ───────────────────────────────────────────────

export interface CharacterConfig {
  type: CharacterType;
  displayName: string;
  /** CSS color string, e.g. "rgb(77, 179, 242)" */
  spriteColor: string;
  breakBehaviors: BreakDestination[];
  needsBlanket: boolean;
}

export interface Point {
  x: number;
  y: number;
}

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

// ── Idle Activities ──────────────────────────────────────────

export interface IdleActivity {
  label: string;
  area: OfficeAreaType;
  /** Specific position near furniture — agent walks here instead of random room spot */
  target?: Point;
}

/** Idle activities available per area — humans */
export const HUMAN_IDLE_ACTIVITIES: Record<string, IdleActivity[]> = {
  strategyRoom: [
    { label: 'Planning at whiteboard', area: 'strategyRoom', target: { x: 90, y: 50 } },
    { label: 'Discussing strategy', area: 'strategyRoom', target: { x: 115, y: 110 } },
    { label: 'Reviewing architecture', area: 'strategyRoom', target: { x: 140, y: 110 } },
    { label: 'Brainstorming', area: 'strategyRoom', target: { x: 70, y: 50 } },
  ],
  kitchen: [
    { label: 'Making coffee', area: 'kitchen', target: { x: 110, y: 235 } },
    { label: 'Toasting bread', area: 'kitchen', target: { x: 20, y: 258 } },
    { label: 'Raiding the fridge', area: 'kitchen', target: { x: 207, y: 260 } },
    { label: 'Doing dishes', area: 'kitchen', target: { x: 62, y: 235 } },
    { label: 'Microwaving lunch', area: 'kitchen', target: { x: 151, y: 235 } },
  ],
  breakRoom: [
    { label: 'Playing ping pong', area: 'breakRoom', target: { x: 370, y: 468 } },
    { label: 'Playing video games', area: 'breakRoom', target: { x: 90, y: 450 } },
    { label: 'Watching TV', area: 'breakRoom', target: { x: 90, y: 450 } },
    { label: 'Napping on couch', area: 'breakRoom', target: { x: 90, y: 475 } },
    { label: 'Chilling in bean bag', area: 'breakRoom', target: { x: 170, y: 478 } },
  ],
};

/** Idle activities available per area — dogs */
export const DOG_IDLE_ACTIVITIES: Record<string, IdleActivity[]> = {
  kitchen: [
    { label: 'Begging for scraps', area: 'kitchen', target: { x: 115, y: 340 } },
    { label: 'Sniffing the floor', area: 'kitchen', target: { x: 60, y: 320 } },
    { label: 'Staring at the fridge', area: 'kitchen', target: { x: 207, y: 260 } },
  ],
  breakRoom: [
    { label: 'Napping on couch', area: 'breakRoom', target: { x: 90, y: 475 } },
    { label: 'Watching TV (confused)', area: 'breakRoom', target: { x: 90, y: 450 } },
    { label: 'Chasing ping pong ball', area: 'breakRoom', target: { x: 370, y: 500 } },
  ],
};

// ── Interfaces ───────────────────────────────────────────────

export interface OfficeAgent {
  id: string;
  name: string;
  role: string;
  characterType: CharacterType;
  status: AgentStatus;
  currentTask: string | null;
  deskIndex: number | null;
  spawnedAt: Date;
  /** Current idle activity label (null when working/walking) */
  idleActivity: string | null;
}

export interface Desk {
  id: number;
  position: Point;
  occupantId: string | null;
  /** Name label for who sits here */
  label?: string;
  /** Width override */
  width?: number;
  /** Height override */
  height?: number;
}

export interface OfficeArea {
  name: string;
  type: OfficeAreaType;
  bounds: Rect;
  capacity: number;
  color: string;
  /** Which view this area belongs to */
  view: OfficeView;
  /** Optional floor pattern */
  floorPattern?: 'carpet' | 'tile' | 'wood' | 'concrete';
  /** Furniture items in this area */
  furniture?: Furniture[];
}
