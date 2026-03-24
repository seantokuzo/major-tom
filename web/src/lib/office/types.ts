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
    { label: 'Planning at whiteboard', area: 'strategyRoom', target: { x: 112, y: 62 } },
    { label: 'Discussing strategy', area: 'strategyRoom', target: { x: 143, y: 138 } },
    { label: 'Reviewing architecture', area: 'strategyRoom', target: { x: 175, y: 138 } },
    { label: 'Brainstorming', area: 'strategyRoom', target: { x: 88, y: 62 } },
  ],
  kitchen: [
    { label: 'Making coffee', area: 'kitchen', target: { x: 137, y: 290 } },
    { label: 'Toasting bread', area: 'kitchen', target: { x: 25, y: 316 } },
    { label: 'Raiding the fridge', area: 'kitchen', target: { x: 252, y: 310 } },
    { label: 'Doing dishes', area: 'kitchen', target: { x: 76, y: 290 } },
    { label: 'Microwaving lunch', area: 'kitchen', target: { x: 188, y: 290 } },
  ],
  breakRoom: [
    { label: 'Playing ping pong', area: 'breakRoom', target: { x: 480, y: 579 } },
    { label: 'Playing video games', area: 'breakRoom', target: { x: 112, y: 555 } },
    { label: 'Watching TV', area: 'breakRoom', target: { x: 112, y: 555 } },
    { label: 'Napping on couch', area: 'breakRoom', target: { x: 110, y: 582 } },
    { label: 'Chilling in bean bag', area: 'breakRoom', target: { x: 215, y: 594 } },
  ],
};

/** Idle activities available per area — dogs */
export const DOG_IDLE_ACTIVITIES: Record<string, IdleActivity[]> = {
  kitchen: [
    { label: 'Begging for scraps', area: 'kitchen', target: { x: 142, y: 420 } },
    { label: 'Sniffing the floor', area: 'kitchen', target: { x: 75, y: 400 } },
    { label: 'Staring at the fridge', area: 'kitchen', target: { x: 252, y: 310 } },
  ],
  breakRoom: [
    { label: 'Napping on couch', area: 'breakRoom', target: { x: 110, y: 582 } },
    { label: 'Watching TV (confused)', area: 'breakRoom', target: { x: 112, y: 555 } },
    { label: 'Chasing ping pong ball', area: 'breakRoom', target: { x: 480, y: 620 } },
  ],
};

// ── Dog Park Activities ──────────────────────────────────────

/** Dog Park idle activities — humans */
export const DOG_PARK_HUMAN_ACTIVITIES: Record<string, IdleActivity[]> = {
  dogParkField: [
    { label: 'Throwing ball', area: 'dogParkField', target: { x: 375, y: 250 } },
    { label: 'Sitting on bench', area: 'dogParkField', target: { x: 525, y: 412 } },
    { label: 'Reading on bench', area: 'dogParkField', target: { x: 175, y: 412 } },
    { label: 'Chatting with dog owner', area: 'dogParkField', target: { x: 312, y: 350 } },
  ],
  agilityCourse: [
    { label: 'Coaching agility run', area: 'agilityCourse', target: { x: 700, y: 588 } },
    { label: 'Setting up hoops', area: 'agilityCourse', target: { x: 680, y: 562 } },
    { label: 'Cheering from sideline', area: 'agilityCourse', target: { x: 850, y: 675 } },
  ],
  dogPondArea: [
    { label: 'Watching dogs swim', area: 'dogPondArea', target: { x: 825, y: 312 } },
    { label: 'Sitting by the pond', area: 'dogPondArea', target: { x: 700, y: 310 } },
  ],
};

/** Dog Park idle activities — dogs */
export const DOG_PARK_DOG_ACTIVITIES: Record<string, IdleActivity[]> = {
  dogParkField: [
    { label: 'Playing fetch', area: 'dogParkField', target: { x: 438, y: 225 } },
    { label: 'Sniffing fire hydrant', area: 'dogParkField', target: { x: 100, y: 150 } },
    { label: 'Chasing squirrel', area: 'dogParkField', target: { x: 500, y: 125 } },
    { label: 'Rolling in grass', area: 'dogParkField', target: { x: 312, y: 312 } },
    { label: 'Drinking water', area: 'dogParkField', target: { x: 250, y: 100 } },
    { label: 'Napping under tree', area: 'dogParkField', target: { x: 475, y: 75 } },
  ],
  agilityCourse: [
    { label: 'Running agility course', area: 'agilityCourse', target: { x: 750, y: 600 } },
    { label: 'Jumping through hoop', area: 'agilityCourse', target: { x: 680, y: 575 } },
    { label: 'Running up ramp', area: 'agilityCourse', target: { x: 737, y: 575 } },
  ],
  dogPondArea: [
    { label: 'Swimming in pond', area: 'dogPondArea', target: { x: 788, y: 156 } },
    { label: 'Shaking off water', area: 'dogPondArea', target: { x: 725, y: 280 } },
    { label: 'Chasing ducks', area: 'dogPondArea', target: { x: 800, y: 125 } },
  ],
};

// ── Gym Activities ───────────────────────────────────────────

/** Gym idle activities — humans */
export const GYM_HUMAN_ACTIVITIES: Record<string, IdleActivity[]> = {
  gymFloor: [
    { label: 'Running on treadmill', area: 'gymFloor', target: { x: 250, y: 75 } },
    { label: 'Lifting weights', area: 'gymFloor', target: { x: 488, y: 250 } },
    { label: 'Boxing punching bag', area: 'gymFloor', target: { x: 275, y: 375 } },
    { label: 'Checking mirror form', area: 'gymFloor', target: { x: 50, y: 250 } },
    { label: 'Spotting a friend', area: 'gymFloor', target: { x: 500, y: 250 } },
  ],
  yogaStudio: [
    { label: 'Doing yoga', area: 'yogaStudio', target: { x: 675, y: 500 } },
    { label: 'Stretching', area: 'yogaStudio', target: { x: 762, y: 500 } },
    { label: 'Balancing on exercise ball', area: 'yogaStudio', target: { x: 940, y: 500 } },
    { label: 'Meditating', area: 'yogaStudio', target: { x: 725, y: 575 } },
  ],
  lockerRoom: [
    { label: 'Getting water', area: 'lockerRoom', target: { x: 675, y: 55 } },
    { label: 'Checking locker', area: 'lockerRoom', target: { x: 950, y: 100 } },
    { label: 'Fixing hair in mirror', area: 'lockerRoom', target: { x: 750, y: 312 } },
  ],
};

/** Gym idle activities — dogs */
export const GYM_DOG_ACTIVITIES: Record<string, IdleActivity[]> = {
  gymFloor: [
    { label: 'Running on treadmill (slowly)', area: 'gymFloor', target: { x: 300, y: 75 } },
    { label: 'Napping on weight bench', area: 'gymFloor', target: { x: 488, y: 275 } },
    { label: 'Barking at punching bag', area: 'gymFloor', target: { x: 275, y: 400 } },
  ],
  yogaStudio: [
    { label: 'Downward dog (for real)', area: 'yogaStudio', target: { x: 675, y: 525 } },
    { label: 'Rolling on yoga mat', area: 'yogaStudio', target: { x: 762, y: 525 } },
    { label: 'Chewing exercise ball', area: 'yogaStudio', target: { x: 940, y: 512 } },
  ],
  lockerRoom: [
    { label: 'Drinking from fountain', area: 'lockerRoom', target: { x: 675, y: 55 } },
    { label: 'Sniffing lockers', area: 'lockerRoom', target: { x: 950, y: 130 } },
  ],
};

// ── Theme Park Activities ────────────────────────────────────

/** Theme Park idle activities — humans */
export const THEME_PARK_HUMAN_ACTIVITIES: Record<string, IdleActivity[]> = {
  mainPlaza: [
    { label: 'Eating hot dog', area: 'mainPlaza', target: { x: 438, y: 200 } },
    { label: 'Getting cotton candy', area: 'mainPlaza', target: { x: 625, y: 200 } },
    { label: 'Buying tickets', area: 'mainPlaza', target: { x: 125, y: 100 } },
    { label: 'Getting balloons', area: 'mainPlaza', target: { x: 835, y: 125 } },
    { label: 'Taking a selfie', area: 'mainPlaza', target: { x: 500, y: 300 } },
  ],
  rollerCoasterZone: [
    { label: 'Riding roller coaster', area: 'rollerCoasterZone', target: { x: 200, y: 588 } },
    { label: 'Watching ferris wheel', area: 'rollerCoasterZone', target: { x: 412, y: 600 } },
    { label: 'Waiting in line', area: 'rollerCoasterZone', target: { x: 150, y: 650 } },
  ],
  arcadeHall: [
    { label: 'Playing carnival games', area: 'arcadeHall', target: { x: 850, y: 450 } },
    { label: 'Riding carousel', area: 'arcadeHall', target: { x: 700, y: 537 } },
    { label: 'Winning prizes', area: 'arcadeHall', target: { x: 560, y: 675 } },
  ],
};

/** Theme Park idle activities — dogs */
export const THEME_PARK_DOG_ACTIVITIES: Record<string, IdleActivity[]> = {
  mainPlaza: [
    { label: 'Begging for hot dog', area: 'mainPlaza', target: { x: 440, y: 210 } },
    { label: 'Tangled in balloon strings', area: 'mainPlaza', target: { x: 840, y: 130 } },
    { label: 'Sniffing cotton candy', area: 'mainPlaza', target: { x: 628, y: 210 } },
    { label: 'Chasing pigeons', area: 'mainPlaza', target: { x: 500, y: 280 } },
  ],
  rollerCoasterZone: [
    { label: 'Watching coaster (scared)', area: 'rollerCoasterZone', target: { x: 200, y: 650 } },
    { label: 'Barking at ferris wheel', area: 'rollerCoasterZone', target: { x: 412, y: 625 } },
  ],
  arcadeHall: [
    { label: 'Chasing carousel horses', area: 'arcadeHall', target: { x: 700, y: 550 } },
    { label: 'Napping under game booth', area: 'arcadeHall', target: { x: 850, y: 475 } },
    { label: 'Stealing prizes', area: 'arcadeHall', target: { x: 560, y: 680 } },
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
