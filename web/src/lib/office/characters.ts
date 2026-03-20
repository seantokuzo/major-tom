// Character catalog — ported from iOS CharacterConfig.swift / CharacterCatalog

import type { CharacterConfig, CharacterType } from './types';

export const CHARACTER_CATALOG: CharacterConfig[] = [
  // Humans
  {
    type: 'dev',
    displayName: 'Developer',
    spriteColor: 'rgb(77, 179, 242)',
    breakBehaviors: ['breakRoom', 'kitchen', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'officeWorker',
    displayName: 'Office Worker',
    spriteColor: 'rgb(140, 204, 115)',
    breakBehaviors: ['breakRoom', 'kitchen'],
    needsBlanket: false,
  },
  {
    type: 'pm',
    displayName: 'Project Manager',
    spriteColor: 'rgb(242, 191, 77)',
    breakBehaviors: ['breakRoom', 'kitchen', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'clown',
    displayName: 'Office Clown',
    spriteColor: 'rgb(242, 102, 153)',
    breakBehaviors: ['breakRoom', 'kitchen', 'rollercoaster', 'gym'],
    needsBlanket: false,
  },
  {
    type: 'frankenstein',
    displayName: 'Frankenstein',
    spriteColor: 'rgb(128, 217, 128)',
    breakBehaviors: ['breakRoom', 'gym', 'rollercoaster'],
    needsBlanket: false,
  },
  // Dogs
  {
    type: 'dachshund',
    displayName: 'Dachshund',
    spriteColor: 'rgb(191, 115, 51)',
    breakBehaviors: ['dogCorner', 'dogPark', 'kitchen'],
    needsBlanket: true,
  },
  {
    type: 'cattleDog',
    displayName: 'Cattle Dog',
    spriteColor: 'rgb(217, 89, 64)',
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
