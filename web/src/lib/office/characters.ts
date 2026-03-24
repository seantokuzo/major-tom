// Character catalog — 10 tech specialists + 4 dogs

import type { BreakDestination, CharacterConfig, CharacterType, OfficeView } from './types';

export const CHARACTER_CATALOG: CharacterConfig[] = [
  // ── Humans ──────────────────────────────────────────────────
  {
    type: 'architect',
    displayName: 'Architect',
    spriteColor: 'rgb(51, 51, 64)',
    breakBehaviors: ['strategyRoom', 'kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'leadEngineer',
    displayName: 'Lead Engineer',
    spriteColor: 'rgb(64, 140, 217)',
    breakBehaviors: ['strategyRoom', 'kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'engManager',
    displayName: 'Eng Manager',
    spriteColor: 'rgb(77, 128, 179)',
    breakBehaviors: ['strategyRoom', 'kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'backendEngineer',
    displayName: 'Backend Engineer',
    spriteColor: 'rgb(46, 102, 64)',
    breakBehaviors: ['kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'frontendEngineer',
    displayName: 'Frontend Engineer',
    spriteColor: 'rgb(217, 115, 166)',
    breakBehaviors: ['kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'uxDesigner',
    displayName: 'UX Designer',
    spriteColor: 'rgb(64, 64, 77)',
    breakBehaviors: ['strategyRoom', 'kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'projectManager',
    displayName: 'Project Manager',
    spriteColor: 'rgb(51, 64, 89)',
    breakBehaviors: ['strategyRoom', 'kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'productManager',
    displayName: 'Product Manager',
    spriteColor: 'rgb(64, 128, 153)',
    breakBehaviors: ['strategyRoom', 'kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'devops',
    displayName: 'DevOps',
    spriteColor: 'rgb(153, 64, 51)',
    breakBehaviors: ['kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'databaseGuru',
    displayName: 'Database Guru',
    spriteColor: 'rgb(102, 51, 153)',
    breakBehaviors: ['kitchen', 'breakRoom'],
    needsBlanket: false,
  },

  // ── Dogs ────────────────────────────────────────────────────
  {
    type: 'dachshund',
    displayName: 'Elvito (Senor)',
    spriteColor: 'rgb(184, 107, 46)',
    breakBehaviors: ['kitchen', 'breakRoom'],
    needsBlanket: true,
  },
  {
    type: 'cattleDog',
    displayName: 'Steve',
    spriteColor: 'rgb(179, 89, 51)',
    breakBehaviors: ['kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'schnauzerBlack',
    displayName: 'Hoku',
    spriteColor: 'rgb(38, 38, 51)',
    breakBehaviors: ['kitchen', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'schnauzerPepper',
    displayName: 'Kai',
    spriteColor: 'rgb(89, 89, 102)',
    breakBehaviors: ['kitchen', 'breakRoom'],
    needsBlanket: false,
  },
];

// ── View preferences ────────────────────────────────────────

/** Extra break destinations available per view — humans */
export const VIEW_BREAK_DESTINATIONS_HUMAN: Record<OfficeView, BreakDestination[]> = {
  office: ['strategyRoom', 'kitchen', 'breakRoom'],
  dogPark: ['dogParkField', 'dogPondArea'],
  gym: ['gymFloor', 'yogaStudio', 'lockerRoom'],
  themePark: ['mainPlaza', 'rollerCoasterZone', 'arcadeHall'],
};

/** Extra break destinations available per view — dogs */
export const VIEW_BREAK_DESTINATIONS_DOG: Record<OfficeView, BreakDestination[]> = {
  office: ['kitchen', 'breakRoom'],
  dogPark: ['dogParkField', 'agilityCourse', 'dogPondArea'],
  gym: ['gymFloor', 'yogaStudio'],
  themePark: ['mainPlaza', 'arcadeHall'],
};

/** Preferred views per character type — everyone can visit the dog park */
export const CHARACTER_VIEW_PREFERENCES: Record<CharacterType, OfficeView[]> = {
  // Humans can visit gym, theme park, and dog park on breaks
  architect:        ['office', 'dogPark', 'gym', 'themePark'],
  leadEngineer:     ['office', 'dogPark', 'gym', 'themePark'],
  engManager:       ['office', 'dogPark', 'gym', 'themePark'],
  backendEngineer:  ['office', 'dogPark', 'gym'],
  frontendEngineer: ['office', 'dogPark', 'themePark'],
  uxDesigner:       ['office', 'dogPark', 'themePark'],
  projectManager:   ['office', 'dogPark', 'gym'],
  productManager:   ['office', 'dogPark', 'themePark'],
  devops:           ['office', 'dogPark', 'gym'],
  databaseGuru:     ['office', 'dogPark', 'gym'],
  // Dogs strongly prefer the dog park (no gym access)
  dachshund:        ['office', 'dogPark', 'themePark'],
  cattleDog:        ['office', 'dogPark', 'themePark'],
  schnauzerBlack:   ['office', 'dogPark', 'themePark'],
  schnauzerPepper:  ['office', 'dogPark', 'themePark'],
};

const configByType = new Map<CharacterType, CharacterConfig>(
  CHARACTER_CATALOG.map((c) => [c.type, c])
);

export const DOG_TYPES: ReadonlySet<CharacterType> = new Set<CharacterType>([
  'dachshund', 'cattleDog', 'schnauzerBlack', 'schnauzerPepper',
]);

export function getCharacterConfig(type: CharacterType): CharacterConfig {
  const config = configByType.get(type);
  if (!config) throw new Error(`Missing CharacterConfig for ${type}`);
  return config;
}
