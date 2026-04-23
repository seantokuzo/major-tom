// SpriteMapper — Role classifier + mapping manager for sprite-agent wiring.
//
// Responsibilities:
// 1. Classify agent task descriptions into canonical roles (8 roles)
// 2. Resolve roles to CharacterTypes with per-session role-stable binding
// 3. Allocate desk positions for working sprites
//
// The role classification regex table mirrors the one in claude-cli.adapter.ts
// and fleet/worker.ts but is now the canonical source. Those will be updated
// to delegate here in a future cleanup.

import { randomUUID } from 'node:crypto';
import { logger } from '../utils/logger.js';
import type { PersistedSpriteMapping, PersistedSpriteMappingFile } from './sprite-mapping-persistence.js';

// ── Canonical roles ────────────────────────────────────────

export const CANONICAL_ROLES = [
  'researcher',
  'architect',
  'qa',
  'devops',
  'frontend',
  'backend',
  'lead',
  'engineer',
] as const;

export type CanonicalRole = typeof CANONICAL_ROLES[number];

// ── Character pool (randomized assignment) ─────────────────
// Post-QA-FIXES #9: character assignment is randomized per spawn,
// decoupled from canonical role. The previous role→CharacterType lock
// ("researcher is always the botanist") was scrapped in favor of a
// "who am I gonna get?!" roll each spawn. Canonical roles still drive
// labels, aura colors, and classification — just not character choice.
//
// Source of truth for the pool: iOS `CharacterCatalog` crew entries
// (ios/MajorTom/Features/Office/Models/CharacterConfig.swift). Dogs
// are NEVER used as agent sprites (they live at tab scope as pets).
//
// Keep this list in lockstep with the iOS CharacterType enum's non-dog
// cases. If iOS ships a new crew character, add it here in the same
// PR so the relay can assign it.

export const CHARACTER_POOL: readonly string[] = [
  'alienDiplomat',
  'backendEngineer',
  'botanist',
  'bowenYang',
  'captain',
  'chef',
  'claudimusPrime',
  'doctor',
  'dwight',
  'frontendDev',
  'kendrick',
  'mechanic',
  'pm',
  'prince',
] as const;

// ── Role classification regex patterns ─────────────────────
// Priority order: first match wins. More specific roles before generic.

const ROLE_KEYWORDS: [RegExp, CanonicalRole][] = [
  [/\b(explore|search|find|grep|look|read|glob|discover)\b/i, 'researcher'],
  [/\b(plan|design|architect|strategy|blueprint)\b/i, 'architect'],
  [/\b(test|validate|verify|assert|spec)\b/i, 'qa'],
  [/\b(build|compile|deploy|docker|ci|infrastructure)\b/i, 'devops'],
  [/\b(style|css|ui|ux|layout|component|svelte|react|frontend)\b/i, 'frontend'],
  [/\b(api|server|database|backend|relay|endpoint|route)\b/i, 'backend'],
  [/\b(review|refactor|fix|lint|cleanup)\b/i, 'lead'],
  [/\b(write|implement|create|add|update|edit)\b/i, 'engineer'],
];

// ── Max desks per office ───────────────────────────────────

const MAX_DESKS = 6;

// ── SpriteMapper class ─────────────────────────────────────

export class SpriteMapper {
  /**
   * Classify a task description into one of 8 canonical roles.
   * Uses regex pattern matching against the task text.
   * Falls back to 'engineer' if no patterns match.
   */
  classifyRole(task: string): CanonicalRole {
    for (const [pattern, role] of ROLE_KEYWORDS) {
      if (pattern.test(task)) return role;
    }
    return 'engineer';
  }

  /**
   * Pick a CharacterType for a new sprite via randomization — post-QA-FIXES
   * #9 semantics. Avoids characters already in use by active mappings until
   * the pool is exhausted, then falls back to a random pick with duplicates
   * allowed (>14 concurrent sprites is deep in overflow territory anyway).
   *
   * Role is intentionally NOT consulted — every spawn is a fresh roll. Label,
   * aura, and other role-derived UX still flow from canonicalRole; character
   * choice is decoupled.
   *
   * @param currentMappings - Active mappings in the session (dup-avoidance).
   * @returns The chosen CharacterType string.
   */
  resolveCharacterType(
    currentMappings: PersistedSpriteMapping[],
  ): { characterType: string } {
    const inUse = new Set(currentMappings.map((m) => m.characterType));
    const available = CHARACTER_POOL.filter((c) => !inUse.has(c));

    // Non-null assertion inside both branches: CHARACTER_POOL is a non-empty
    // readonly array (14 entries), so randomElement is safe. `available`
    // might be empty when every pool member is already claimed — in that
    // case we roll from the full pool and accept a duplicate.
    const source = available.length > 0 ? available : CHARACTER_POOL;
    const characterType = source[Math.floor(Math.random() * source.length)]!;
    return { characterType };
  }

  /**
   * Allocate the next available desk index for a new agent sprite.
   * Desks are numbered 0-5 (MAX_DESKS). Returns -1 if all desks are occupied
   * (overflow -- sprite placed in open floor space by the iOS client).
   */
  allocateDesk(currentMappings: PersistedSpriteMapping[]): number {
    const occupied = new Set(currentMappings.map(m => m.deskIndex));
    for (let i = 0; i < MAX_DESKS; i++) {
      if (!occupied.has(i)) return i;
    }
    return -1; // Overflow
  }

  /**
   * Create a full sprite mapping for a newly spawned agent.
   * Orchestrates role classification, character resolution (random pick
   * avoiding active-roster dupes), and desk allocation.
   *
   * @param agentId - The agent's unique ID.
   * @param task - The agent's task description (used for role classification).
   * @param currentMappings - Current active mappings for desk + character dup
   *   avoidance. Pass the full session roster so the dup-avoid window is
   *   per-session (prevents the same character appearing twice at once).
   * @param parentId - Optional parent subagent id for nested spawns.
   */
  createMapping(
    agentId: string,
    task: string,
    currentMappings: PersistedSpriteMapping[],
    parentId?: string,
  ): { mapping: PersistedSpriteMapping; role: CanonicalRole } {
    const role = this.classifyRole(task);
    const { characterType } = this.resolveCharacterType(currentMappings);
    const deskIndex = this.allocateDesk(currentMappings);
    const spriteHandle = `sprite-${randomUUID().slice(0, 8)}`;

    const mapping: PersistedSpriteMapping = {
      spriteHandle,
      subagentId: agentId,
      canonicalRole: role,
      characterType,
      task,
      parentId,
      deskIndex,
      linkedAt: new Date().toISOString(),
    };

    logger.info(
      { subagentId: agentId, canonicalRole: role, characterType, deskIndex, spriteHandle },
      'Sprite mapping created',
    );

    return { mapping, role };
  }

  /**
   * Build an empty persisted mapping file for a new session.
   */
  createEmptyFile(sessionId: string): PersistedSpriteMappingFile {
    return {
      version: 1,
      sessionId,
      updatedAt: new Date().toISOString(),
      roleBindings: {},
      mappings: [],
    };
  }
}
