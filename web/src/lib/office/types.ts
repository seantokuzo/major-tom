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
  | 'breakRoom'
  // Dog Park
  | 'dogParkField'
  | 'agilityCourse'
  | 'dogPondArea'
  // Gym
  | 'gymFloor'
  | 'yogaStudio'
  | 'lockerRoom'
  // Theme Park
  | 'mainPlaza'
  | 'rollerCoasterZone'
  | 'arcadeHall';

export type OfficeAreaType =
  | 'mainOffice'
  | 'strategyRoom'
  | 'kitchen'
  | 'breakRoom'
  // Dog Park
  | 'dogParkField'
  | 'agilityCourse'
  | 'dogPondArea'
  // Gym
  | 'gymFloor'
  | 'yogaStudio'
  | 'lockerRoom'
  // Theme Park
  | 'mainPlaza'
  | 'rollerCoasterZone'
  | 'arcadeHall';

/** Office view — multiple themed views */
export type OfficeView = 'office' | 'dogPark' | 'gym' | 'themePark';

export interface OfficeViewConfig {
  id: OfficeView;
  label: string;
  /** Which area types are visible in this view */
  areas: OfficeAreaType[];
}

// ── Furniture types for richer rendering ─────────────────────

export type FurnitureType =
  // Office
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
  | 'wallSegment'
  // Dog Park
  | 'dogBowl'
  | 'fireHydrant'
  | 'dogHouse'
  | 'agilityHoop'
  | 'agilityRamp'
  | 'pondWater'
  | 'tree'
  | 'bench'
  | 'fence'
  | 'ballLauncher'
  // Gym
  | 'treadmill'
  | 'weightRack'
  | 'punchingBag'
  | 'yogaMat'
  | 'exerciseBall'
  | 'locker'
  | 'mirror'
  | 'waterFountain'
  // Theme Park
  | 'rollerCoasterTrack'
  | 'ferrisWheel'
  | 'hotDogStand'
  | 'cottonCandyCart'
  | 'ticketBooth'
  | 'balloonCart'
  | 'carousel';

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

// ── Dog Park Activities ──────────────────────────────────────

/** Dog Park idle activities — humans */
export const DOG_PARK_HUMAN_ACTIVITIES: Record<string, IdleActivity[]> = {
  dogParkField: [
    { label: 'Throwing ball', area: 'dogParkField', target: { x: 300, y: 200 } },
    { label: 'Sitting on bench', area: 'dogParkField', target: { x: 420, y: 330 } },
    { label: 'Reading on bench', area: 'dogParkField', target: { x: 140, y: 330 } },
    { label: 'Chatting with dog owner', area: 'dogParkField', target: { x: 250, y: 280 } },
  ],
  agilityCourse: [
    { label: 'Coaching agility run', area: 'agilityCourse', target: { x: 200, y: 470 } },
    { label: 'Setting up hoops', area: 'agilityCourse', target: { x: 100, y: 450 } },
    { label: 'Cheering from sideline', area: 'agilityCourse', target: { x: 350, y: 540 } },
  ],
  dogPondArea: [
    { label: 'Watching dogs swim', area: 'dogPondArea', target: { x: 660, y: 250 } },
    { label: 'Sitting by the pond', area: 'dogPondArea', target: { x: 640, y: 400 } },
  ],
};

/** Dog Park idle activities — dogs */
export const DOG_PARK_DOG_ACTIVITIES: Record<string, IdleActivity[]> = {
  dogParkField: [
    { label: 'Playing fetch', area: 'dogParkField', target: { x: 350, y: 180 } },
    { label: 'Sniffing fire hydrant', area: 'dogParkField', target: { x: 80, y: 120 } },
    { label: 'Chasing squirrel', area: 'dogParkField', target: { x: 480, y: 100 } },
    { label: 'Rolling in grass', area: 'dogParkField', target: { x: 250, y: 250 } },
    { label: 'Drinking water', area: 'dogParkField', target: { x: 200, y: 80 } },
    { label: 'Napping under tree', area: 'dogParkField', target: { x: 500, y: 60 } },
  ],
  agilityCourse: [
    { label: 'Running agility course', area: 'agilityCourse', target: { x: 200, y: 480 } },
    { label: 'Jumping through hoop', area: 'agilityCourse', target: { x: 100, y: 460 } },
    { label: 'Running up ramp', area: 'agilityCourse', target: { x: 280, y: 460 } },
  ],
  dogPondArea: [
    { label: 'Swimming in pond', area: 'dogPondArea', target: { x: 670, y: 200 } },
    { label: 'Shaking off water', area: 'dogPondArea', target: { x: 620, y: 300 } },
    { label: 'Chasing ducks', area: 'dogPondArea', target: { x: 680, y: 150 } },
  ],
};

// ── Gym Activities ───────────────────────────────────────────

/** Gym idle activities — humans */
export const GYM_HUMAN_ACTIVITIES: Record<string, IdleActivity[]> = {
  gymFloor: [
    { label: 'Running on treadmill', area: 'gymFloor', target: { x: 300, y: 60 } },
    { label: 'Lifting weights', area: 'gymFloor', target: { x: 450, y: 200 } },
    { label: 'Boxing punching bag', area: 'gymFloor', target: { x: 350, y: 300 } },
    { label: 'Checking mirror form', area: 'gymFloor', target: { x: 260, y: 200 } },
    { label: 'Spotting a friend', area: 'gymFloor', target: { x: 470, y: 200 } },
  ],
  yogaStudio: [
    { label: 'Doing yoga', area: 'yogaStudio', target: { x: 100, y: 470 } },
    { label: 'Stretching', area: 'yogaStudio', target: { x: 200, y: 470 } },
    { label: 'Balancing on exercise ball', area: 'yogaStudio', target: { x: 300, y: 480 } },
    { label: 'Meditating', area: 'yogaStudio', target: { x: 150, y: 530 } },
  ],
  lockerRoom: [
    { label: 'Getting water', area: 'lockerRoom', target: { x: 660, y: 400 } },
    { label: 'Checking locker', area: 'lockerRoom', target: { x: 620, y: 150 } },
    { label: 'Fixing hair in mirror', area: 'lockerRoom', target: { x: 660, y: 250 } },
  ],
};

/** Gym idle activities — dogs */
export const GYM_DOG_ACTIVITIES: Record<string, IdleActivity[]> = {
  gymFloor: [
    { label: 'Running on treadmill (slowly)', area: 'gymFloor', target: { x: 380, y: 60 } },
    { label: 'Napping on weight bench', area: 'gymFloor', target: { x: 450, y: 220 } },
    { label: 'Barking at punching bag', area: 'gymFloor', target: { x: 370, y: 300 } },
  ],
  yogaStudio: [
    { label: 'Downward dog (for real)', area: 'yogaStudio', target: { x: 120, y: 480 } },
    { label: 'Rolling on yoga mat', area: 'yogaStudio', target: { x: 200, y: 490 } },
    { label: 'Chewing exercise ball', area: 'yogaStudio', target: { x: 310, y: 480 } },
  ],
  lockerRoom: [
    { label: 'Drinking from fountain', area: 'lockerRoom', target: { x: 660, y: 420 } },
    { label: 'Sniffing lockers', area: 'lockerRoom', target: { x: 620, y: 170 } },
  ],
};

// ── Theme Park Activities ────────────────────────────────────

/** Theme Park idle activities — humans */
export const THEME_PARK_HUMAN_ACTIVITIES: Record<string, IdleActivity[]> = {
  mainPlaza: [
    { label: 'Eating hot dog', area: 'mainPlaza', target: { x: 350, y: 200 } },
    { label: 'Getting cotton candy', area: 'mainPlaza', target: { x: 200, y: 200 } },
    { label: 'Buying tickets', area: 'mainPlaza', target: { x: 100, y: 100 } },
    { label: 'Getting balloons', area: 'mainPlaza', target: { x: 450, y: 100 } },
    { label: 'Taking a selfie', area: 'mainPlaza', target: { x: 300, y: 300 } },
  ],
  rollerCoasterZone: [
    { label: 'Riding roller coaster', area: 'rollerCoasterZone', target: { x: 280, y: 470 } },
    { label: 'Watching ferris wheel', area: 'rollerCoasterZone', target: { x: 450, y: 480 } },
    { label: 'Waiting in line', area: 'rollerCoasterZone', target: { x: 200, y: 540 } },
  ],
  arcadeHall: [
    { label: 'Playing carnival games', area: 'arcadeHall', target: { x: 660, y: 200 } },
    { label: 'Riding carousel', area: 'arcadeHall', target: { x: 680, y: 400 } },
    { label: 'Winning prizes', area: 'arcadeHall', target: { x: 650, y: 300 } },
  ],
};

/** Theme Park idle activities — dogs */
export const THEME_PARK_DOG_ACTIVITIES: Record<string, IdleActivity[]> = {
  mainPlaza: [
    { label: 'Begging for hot dog', area: 'mainPlaza', target: { x: 360, y: 220 } },
    { label: 'Tangled in balloon strings', area: 'mainPlaza', target: { x: 460, y: 120 } },
    { label: 'Sniffing cotton candy', area: 'mainPlaza', target: { x: 210, y: 220 } },
    { label: 'Chasing pigeons', area: 'mainPlaza', target: { x: 300, y: 280 } },
  ],
  rollerCoasterZone: [
    { label: 'Watching coaster (scared)', area: 'rollerCoasterZone', target: { x: 300, y: 540 } },
    { label: 'Barking at ferris wheel', area: 'rollerCoasterZone', target: { x: 460, y: 500 } },
  ],
  arcadeHall: [
    { label: 'Chasing carousel horses', area: 'arcadeHall', target: { x: 690, y: 420 } },
    { label: 'Napping under game booth', area: 'arcadeHall', target: { x: 660, y: 220 } },
    { label: 'Stealing prizes', area: 'arcadeHall', target: { x: 650, y: 320 } },
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
  floorPattern?: 'carpet' | 'tile' | 'wood' | 'concrete' | 'grass' | 'cobblestone';
  /** Furniture items in this area */
  furniture?: Furniture[];
}
