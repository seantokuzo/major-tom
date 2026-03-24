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
  // Sprite Street bedrooms (7 columns × 2 rows = 14 rooms)
  | 'bedroomRow1Col1' | 'bedroomRow1Col2' | 'bedroomRow1Col3' | 'bedroomRow1Col4' | 'bedroomRow1Col5' | 'bedroomRow1Col6' | 'bedroomRow1Col7'
  | 'bedroomRow2Col1' | 'bedroomRow2Col2' | 'bedroomRow2Col3' | 'bedroomRow2Col4' | 'bedroomRow2Col5' | 'bedroomRow2Col6' | 'bedroomRow2Col7';

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
  // Sprite Street bedrooms (7 columns × 2 rows = 14 rooms)
  | 'bedroomRow1Col1' | 'bedroomRow1Col2' | 'bedroomRow1Col3' | 'bedroomRow1Col4' | 'bedroomRow1Col5' | 'bedroomRow1Col6' | 'bedroomRow1Col7'
  | 'bedroomRow2Col1' | 'bedroomRow2Col2' | 'bedroomRow2Col3' | 'bedroomRow2Col4' | 'bedroomRow2Col5' | 'bedroomRow2Col6' | 'bedroomRow2Col7';

/** Office view — multiple themed views */
export type OfficeView = 'office' | 'dogPark' | 'gym' | 'spriteStreet';

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
  // Sprite Street bedrooms
  | 'bed'
  | 'closet'
  | 'rug';

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

// ── Sprite Street Activities ─────────────────────────────────

/** All bedroom area types for iteration */
export const ALL_BEDROOM_AREAS: OfficeAreaType[] = [
  'bedroomRow1Col1', 'bedroomRow1Col2', 'bedroomRow1Col3', 'bedroomRow1Col4', 'bedroomRow1Col5', 'bedroomRow1Col6', 'bedroomRow1Col7',
  'bedroomRow2Col1', 'bedroomRow2Col2', 'bedroomRow2Col3', 'bedroomRow2Col4', 'bedroomRow2Col5', 'bedroomRow2Col6', 'bedroomRow2Col7',
];

/** Map character type to their personal bedroom */
export const CHARACTER_BEDROOM: Record<CharacterType, OfficeAreaType> = {
  architect:        'bedroomRow1Col1',
  leadEngineer:     'bedroomRow1Col2',
  engManager:       'bedroomRow1Col3',
  backendEngineer:  'bedroomRow1Col4',
  frontendEngineer: 'bedroomRow1Col5',
  uxDesigner:       'bedroomRow1Col6',
  projectManager:   'bedroomRow1Col7',
  productManager:   'bedroomRow2Col1',
  devops:           'bedroomRow2Col2',
  databaseGuru:     'bedroomRow2Col3',
  dachshund:        'bedroomRow2Col4',
  cattleDog:        'bedroomRow2Col5',
  schnauzerBlack:   'bedroomRow2Col6',
  schnauzerPepper:  'bedroomRow2Col7',
};

/**
 * Generate Sprite St. activities for a bedroom.
 * Activities use positions relative to the bedroom grid cell.
 * Column width ~135px, row height ~365px — positions are within each bedroom.
 */
function bedroomActivities(area: OfficeAreaType, baseX: number, baseY: number): IdleActivity[] {
  return [
    { label: 'Napping in bed',     area, target: { x: baseX + 95, y: baseY + 45 } },
    { label: 'Reading in bed',     area, target: { x: baseX + 95, y: baseY + 35 } },
    { label: 'Checking closet',    area, target: { x: baseX + 25, y: baseY + 80 } },
    { label: 'Looking in mirror',  area, target: { x: baseX + 45, y: baseY + 20 } },
    { label: 'Relaxing at home',   area, target: { x: baseX + 68, y: baseY + 80 } },
  ];
}

function bedroomDogActivities(area: OfficeAreaType, baseX: number, baseY: number): IdleActivity[] {
  return [
    { label: 'Napping on bed',        area, target: { x: baseX + 95, y: baseY + 45 } },
    { label: 'Hiding under bed',      area, target: { x: baseX + 95, y: baseY + 60 } },
    { label: 'Scratching at closet',  area, target: { x: baseX + 25, y: baseY + 80 } },
  ];
}

/** Sprite St. idle activities — humans (keyed by bedroom area type) */
export const SPRITE_ST_HUMAN_ACTIVITIES: Record<string, IdleActivity[]> = (() => {
  const result: Record<string, IdleActivity[]> = {};
  const colW = 140;
  const rowH = 115;
  for (let row = 0; row < 2; row++) {
    for (let col = 0; col < 7; col++) {
      const areaKey = `bedroomRow${row + 1}Col${col + 1}`;
      const baseX = 5 + col * colW;
      const baseY = row === 0 ? 5 : 5 + rowH;
      result[areaKey] = bedroomActivities(areaKey as OfficeAreaType, baseX, baseY);
    }
  }
  return result;
})();

/** Sprite St. idle activities — dogs (keyed by bedroom area type) */
export const SPRITE_ST_DOG_ACTIVITIES: Record<string, IdleActivity[]> = (() => {
  const result: Record<string, IdleActivity[]> = {};
  const colW = 140;
  const rowH = 115;
  for (let row = 0; row < 2; row++) {
    for (let col = 0; col < 7; col++) {
      const areaKey = `bedroomRow${row + 1}Col${col + 1}`;
      const baseX = 5 + col * colW;
      const baseY = row === 0 ? 5 : 5 + rowH;
      result[areaKey] = bedroomDogActivities(areaKey as OfficeAreaType, baseX, baseY);
    }
  }
  return result;
})();

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
  floorPattern?: 'carpet' | 'tile' | 'wood' | 'concrete' | 'grass';
  /** Furniture items in this area */
  furniture?: Furniture[];
}
