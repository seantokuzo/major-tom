// Office types — ported from iOS AgentState.swift + CharacterConfig.swift

// ── Enums ────────────────────────────────────────────────────

export type AgentStatus = 'spawning' | 'walking' | 'working' | 'idle' | 'celebrating' | 'leaving';

export type CharacterType =
  | 'dev'
  | 'officeWorker'
  | 'pm'
  | 'clown'
  | 'frankenstein'
  | 'dachshund'
  | 'cattleDog'
  | 'schnauzerBlack'
  | 'schnauzerPepper';

export const ALL_CHARACTER_TYPES: CharacterType[] = [
  'dev',
  'officeWorker',
  'pm',
  'clown',
  'frankenstein',
  'dachshund',
  'cattleDog',
  'schnauzerBlack',
  'schnauzerPepper',
];

export type BreakDestination =
  | 'breakRoom'
  | 'kitchen'
  | 'dogCorner'
  | 'dogPark'
  | 'gym'
  | 'rollercoaster';

export type OfficeAreaType =
  | 'mainFloor'
  | 'serverRoom'
  | 'breakRoom'
  | 'kitchen'
  | 'dogCorner'
  | 'dogPark'
  | 'gym'
  | 'rollercoaster';

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

export interface OfficeAgent {
  id: string;
  name: string;
  role: string;
  characterType: CharacterType;
  status: AgentStatus;
  currentTask: string | null;
  deskIndex: number | null;
  spawnedAt: Date;
}

export interface Desk {
  id: number;
  position: Point;
  occupantId: string | null;
}

export interface OfficeArea {
  name: string;
  type: OfficeAreaType;
  bounds: Rect;
  capacity: number;
  color: string;
}
