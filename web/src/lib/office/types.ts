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
}

/** Idle activities available per area — humans */
export const HUMAN_IDLE_ACTIVITIES: Record<string, IdleActivity[]> = {
  strategyRoom: [
    { label: 'Planning at whiteboard', area: 'strategyRoom' },
    { label: 'Discussing strategy', area: 'strategyRoom' },
    { label: 'Reviewing architecture', area: 'strategyRoom' },
    { label: 'Brainstorming', area: 'strategyRoom' },
  ],
  kitchen: [
    { label: 'Making coffee', area: 'kitchen' },
    { label: 'Toasting bread', area: 'kitchen' },
    { label: 'Raiding the fridge', area: 'kitchen' },
    { label: 'Doing dishes', area: 'kitchen' },
    { label: 'Microwaving lunch', area: 'kitchen' },
  ],
  breakRoom: [
    { label: 'Playing ping pong', area: 'breakRoom' },
    { label: 'Playing video games', area: 'breakRoom' },
    { label: 'Watching TV', area: 'breakRoom' },
    { label: 'Napping on couch', area: 'breakRoom' },
    { label: 'Chilling in bean bag', area: 'breakRoom' },
  ],
};

/** Idle activities available per area — dogs */
export const DOG_IDLE_ACTIVITIES: Record<string, IdleActivity[]> = {
  kitchen: [
    { label: 'Begging for scraps', area: 'kitchen' },
    { label: 'Sniffing the floor', area: 'kitchen' },
    { label: 'Staring at the fridge', area: 'kitchen' },
  ],
  breakRoom: [
    { label: 'Napping on couch', area: 'breakRoom' },
    { label: 'Watching TV (confused)', area: 'breakRoom' },
    { label: 'Chasing ping pong ball', area: 'breakRoom' },
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
