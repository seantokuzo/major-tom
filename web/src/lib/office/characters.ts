// Character catalog — 10 tech specialists + 4 dogs

import type { CharacterConfig, CharacterType } from './types';

export const CHARACTER_CATALOG: CharacterConfig[] = [
  // ── Humans ──────────────────────────────────────────────────
  {
    type: 'architect',
    displayName: 'Architect',
    spriteColor: 'rgb(51, 51, 64)',       // dark blazer
    breakBehaviors: ['breakRoom', 'kitchen', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'leadEngineer',
    displayName: 'Lead Engineer',
    spriteColor: 'rgb(64, 140, 217)',     // blue hoodie
    breakBehaviors: ['breakRoom', 'kitchen', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'engManager',
    displayName: 'Eng Manager',
    spriteColor: 'rgb(77, 128, 179)',     // professional blouse
    breakBehaviors: ['breakRoom', 'kitchen'],
    needsBlanket: false,
  },
  {
    type: 'backendEngineer',
    displayName: 'Backend Engineer',
    spriteColor: 'rgb(46, 102, 64)',      // dark green hoodie
    breakBehaviors: ['breakRoom', 'kitchen', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'frontendEngineer',
    displayName: 'Frontend Engineer',
    spriteColor: 'rgb(217, 115, 166)',    // colorful top
    breakBehaviors: ['breakRoom', 'kitchen', 'rollercoaster'],
    needsBlanket: false,
  },
  {
    type: 'uxDesigner',
    displayName: 'UX Designer',
    spriteColor: 'rgb(64, 64, 77)',       // turtleneck
    breakBehaviors: ['breakRoom', 'kitchen', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'projectManager',
    displayName: 'Project Manager',
    spriteColor: 'rgb(51, 64, 89)',       // blazer
    breakBehaviors: ['breakRoom', 'kitchen', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'productManager',
    displayName: 'Product Manager',
    spriteColor: 'rgb(64, 128, 153)',     // polo shirt
    breakBehaviors: ['breakRoom', 'kitchen'],
    needsBlanket: false,
  },
  {
    type: 'devops',
    displayName: 'DevOps',
    spriteColor: 'rgb(153, 64, 51)',      // flannel/plaid
    breakBehaviors: ['breakRoom', 'kitchen', 'gym', 'rollercoaster'],
    needsBlanket: false,
  },
  {
    type: 'databaseGuru',
    displayName: 'Database Guru',
    spriteColor: 'rgb(102, 51, 153)',     // purple wizard hat
    breakBehaviors: ['breakRoom', 'kitchen', 'rollercoaster'],
    needsBlanket: false,
  },

  // ── Dogs ────────────────────────────────────────────────────
  {
    type: 'dachshund',
    displayName: 'Dachshund',
    spriteColor: 'rgb(184, 107, 46)',
    breakBehaviors: ['dogCorner', 'dogPark', 'kitchen'],
    needsBlanket: true,
  },
  {
    type: 'cattleDog',
    displayName: 'Steve',
    spriteColor: 'rgb(179, 89, 51)',      // auburn/red heeler
    breakBehaviors: ['dogCorner', 'dogPark', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'schnauzerBlack',
    displayName: 'Black Schnauzer',
    spriteColor: 'rgb(38, 38, 51)',
    breakBehaviors: ['dogCorner', 'dogPark', 'breakRoom'],
    needsBlanket: false,
  },
  {
    type: 'schnauzerPepper',
    displayName: 'Pepper Schnauzer',
    spriteColor: 'rgb(89, 89, 102)',
    breakBehaviors: ['dogCorner', 'dogPark', 'breakRoom'],
    needsBlanket: false,
  },
];

const configByType = new Map<CharacterType, CharacterConfig>(
  CHARACTER_CATALOG.map((c) => [c.type, c])
);

export function getCharacterConfig(type: CharacterType): CharacterConfig {
  const config = configByType.get(type);
  if (!config) throw new Error(`Missing CharacterConfig for ${type}`);
  return config;
}
