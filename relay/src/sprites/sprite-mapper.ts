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

// ── Role → CharacterType mapping (locked in spec) ──────────
// From the spec: "locked role→CharacterType table"
// Each role maps to a specific human CharacterType sprite.
// Dogs are NEVER used as agent sprites.

const ROLE_CHARACTER_MAP: Record<CanonicalRole, string> = {
  researcher: 'scientist',
  architect: 'architect',
  qa: 'inspector',
  devops: 'mechanic',
  frontend: 'frontendDev',
  backend: 'backendDev',
  lead: 'teamLead',
  engineer: 'engineer',
};

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
   * Resolve a canonical role to a CharacterType string.
   * Implements role-stable binding: the first spawn for a role in a session
   * locks the CharacterType for that role for the session's lifetime.
   *
   * @param role - Canonical role (e.g. 'frontend')
   * @param sessionBindings - Current role→CharacterType bindings for the session
   * @returns The CharacterType to use and whether this is a new binding
   */
  resolveCharacterType(
    role: string,
    sessionBindings: Record<string, string>,
  ): { characterType: string; isNew: boolean } {
    // If we already have a binding for this role in this session, reuse it
    const existing = sessionBindings[role];
    if (existing) {
      return { characterType: existing, isNew: false };
    }

    // Look up the canonical mapping. If the role isn't recognized (shouldn't happen
    // if classifyRole was used, but defensive), fall back to 'engineer' CharacterType.
    const canonicalRole = CANONICAL_ROLES.includes(role as CanonicalRole)
      ? (role as CanonicalRole)
      : 'engineer';
    const characterType = ROLE_CHARACTER_MAP[canonicalRole];

    return { characterType, isNew: true };
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
   * Orchestrates role classification, character resolution, and desk allocation.
   *
   * @param agentId - The agent's unique ID
   * @param task - The agent's task description
   * @param sessionBindings - Current role→CharacterType bindings for the session
   * @param currentMappings - Current active mappings for desk allocation
   * @returns The new mapping and whether the role binding is new
   */
  createMapping(
    agentId: string,
    task: string,
    sessionBindings: Record<string, string>,
    currentMappings: PersistedSpriteMapping[],
  ): { mapping: PersistedSpriteMapping; role: CanonicalRole; isNewBinding: boolean } {
    const role = this.classifyRole(task);
    const { characterType, isNew } = this.resolveCharacterType(role, sessionBindings);
    const deskIndex = this.allocateDesk(currentMappings);
    const spriteHandle = `sprite-${randomUUID().slice(0, 8)}`;

    const mapping: PersistedSpriteMapping = {
      spriteHandle,
      agentId,
      role,
      characterType,
      deskIndex,
      linkedAt: new Date().toISOString(),
    };

    logger.info(
      { agentId, role, characterType, deskIndex, spriteHandle, isNewBinding: isNew },
      'Sprite mapping created',
    );

    return { mapping, role, isNewBinding: isNew };
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
      nextDeskIndex: 0,
    };
  }
}
