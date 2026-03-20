// Office state — Svelte 5 runes-based state management
// Ported from iOS OfficeViewModel.swift

import type { OfficeAgent, CharacterType, Desk, OfficeAreaType, BreakDestination } from './types';
import { ALL_CHARACTER_TYPES } from './types';
import { DESKS, DOOR_POSITION, randomPosition } from './layout';
import { getCharacterConfig } from './characters';
import { OfficeEngine } from './engine';
import type { AnimationType } from './engine';

// ── Status colors ────────────────────────────────────────────

export const STATUS_COLORS: Record<string, string> = {
  spawning: 'rgb(153, 153, 153)',
  walking: 'rgb(102, 179, 255)',
  working: 'rgb(77, 217, 115)',
  idle: 'rgb(242, 191, 77)',
  celebrating: 'rgb(242, 166, 64)',
  leaving: 'rgb(179, 77, 77)',
};

// ── Break destination → area type mapping ────────────────────

const BREAK_TO_AREA: Record<BreakDestination, OfficeAreaType> = {
  breakRoom: 'breakRoom',
  kitchen: 'kitchen',
  dogCorner: 'dogCorner',
  dogPark: 'dogPark',
  gym: 'gym',
  rollercoaster: 'rollercoaster',
};

// ── Office State ─────────────────────────────────────────────

export interface OfficeState {
  agents: OfficeAgent[];
  desks: Desk[];
  selectedAgentId: string | null;
  engine: OfficeEngine;

  readonly selectedAgent: OfficeAgent | null;

  handleSpawn(id: string, role: string, task: string): void;
  handleWorking(id: string, task: string): void;
  handleIdle(id: string): void;
  handleComplete(id: string, result: string): void;
  handleDismissed(id: string): void;
  reset(): void;

  selectAgent(id: string): void;
  dismissInspector(): void;
  renameAgent(id: string, newName: string): void;
}

export function createOfficeState(): OfficeState {
  let agents = $state<OfficeAgent[]>([]);
  let desks = $state<Desk[]>(DESKS.map((d) => ({ ...d, occupantId: null })));
  let selectedAgentId = $state<string | null>(null);
  let nextCharacterIndex = 0;

  const engine = new OfficeEngine();

  const selectedAgent = $derived.by(() => {
    if (!selectedAgentId) return null;
    return agents.find((a) => a.id === selectedAgentId) ?? null;
  });

  // ── Character / Desk Assignment ────────────────────────────

  function assignNextCharacterType(): CharacterType {
    const type = ALL_CHARACTER_TYPES[nextCharacterIndex % ALL_CHARACTER_TYPES.length];
    nextCharacterIndex++;
    return type;
  }

  function assignNextAvailableDesk(agentId: string): number | null {
    const idx = desks.findIndex((d) => d.occupantId === null);
    if (idx === -1) return null;
    desks[idx].occupantId = agentId;
    return idx;
  }

  function releaseDesk(agentId: string): void {
    const idx = desks.findIndex((d) => d.occupantId === agentId);
    if (idx !== -1) desks[idx].occupantId = null;
  }

  function removeAgent(id: string): void {
    releaseDesk(id);
    engine.removeAgent(id);
    agents = agents.filter((a) => a.id !== id);
    if (selectedAgentId === id) selectedAgentId = null;
  }

  // ── Lifecycle Handlers ─────────────────────────────────────

  function handleSpawn(id: string, role: string, task: string): void {
    if (agents.some((a) => a.id === id)) return;

    const characterType = assignNextCharacterType();
    const deskIndex = assignNextAvailableDesk(id);

    const agent: OfficeAgent = {
      id,
      name: role.charAt(0).toUpperCase() + role.slice(1),
      role,
      characterType,
      status: 'spawning',
      currentTask: task,
      deskIndex,
      spawnedAt: new Date(),
    };

    agents.push(agent);

    // Add to engine at door position
    engine.addAgent(id, characterType, agent.name, DOOR_POSITION);
    engine.setStatusColor(id, STATUS_COLORS.spawning);

    // No desk available — park near the door in idle state
    if (deskIndex === null) {
      agent.status = 'idle';
      engine.setStatusColor(id, STATUS_COLORS.idle);
      engine.setAnimation(id, 'idle-bob');
      agents = [...agents];
      return;
    }

    // Desk assigned, walk to desk
    {
      const deskPos = desks[deskIndex].position;
      // Sit slightly below the desk
      const seatPos = { x: deskPos.x, y: deskPos.y + 20 };
      engine.moveAgent(id, seatPos, 1500);

      // Set walking status immediately
      agent.status = 'walking';
      engine.setStatusColor(id, STATUS_COLORS.walking);
      agents = [...agents];
    }
  }

  function handleWorking(id: string, task: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    agent.status = 'working';
    agent.currentTask = task;
    agents = [...agents];

    engine.setStatusColor(id, STATUS_COLORS.working);
    engine.setAnimation(id, 'work-shake');
  }

  function handleIdle(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    // Don't set status to 'idle' yet — agent needs to walk to break spot first.
    // Keep previous status during the walk so the inspector badge stays accurate.
    agent.currentTask = null;
    agents = [...agents];

    // Pick a random break destination from the character's config
    const config = getCharacterConfig(agent.characterType);
    const breakDest = config.breakBehaviors[
      Math.floor(Math.random() * config.breakBehaviors.length)
    ];
    const areaType = BREAK_TO_AREA[breakDest];
    const pos = randomPosition(areaType);

    engine.setStatusColor(id, STATUS_COLORS.walking);
    engine.setAnimation(id, 'none');
    engine.moveAgent(id, pos, 2000);

    // After arrival, set idle status and start idle animation.
    // Guard: if the agent transitioned to another state before timeout fires, bail out.
    setTimeout(() => {
      const current = agents.find((a) => a.id === id);
      if (!current) return;
      if (current.status === 'working' || current.status === 'celebrating' || current.status === 'leaving') return;

      current.status = 'idle';
      agents = [...agents];
      engine.setStatusColor(id, STATUS_COLORS.idle);
      // Dachshund shivers, others bob
      const anim: AnimationType =
        agent.characterType === 'dachshund' ? 'shiver' : 'idle-bob';
      engine.setAnimation(id, anim);
    }, 2100);
  }

  function handleComplete(id: string, result: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    agent.status = 'celebrating';
    agent.currentTask = result;
    agents = [...agents];

    engine.setStatusColor(id, STATUS_COLORS.celebrating);
    engine.setAnimation(id, 'celebrate');

    // After celebration, walk to door and leave
    setTimeout(() => {
      const a = agents.find((a) => a.id === id);
      if (!a) return;
      a.status = 'leaving';
      agents = [...agents];
      releaseDesk(id);

      engine.setStatusColor(id, STATUS_COLORS.leaving);
      engine.setAnimation(id, 'none');
      engine.moveAgent(id, DOOR_POSITION, 1500);

      // Fade out and remove
      setTimeout(() => {
        engine.setAnimation(id, 'fade-out');
        setTimeout(() => removeAgent(id), 600);
      }, 1500);
    }, 2000);
  }

  function handleDismissed(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    agent.status = 'leaving';
    agent.currentTask = null;
    agents = [...agents];
    releaseDesk(id);

    engine.setStatusColor(id, STATUS_COLORS.leaving);
    engine.setAnimation(id, 'none');
    engine.moveAgent(id, DOOR_POSITION, 1500);

    setTimeout(() => {
      engine.setAnimation(id, 'fade-out');
      setTimeout(() => removeAgent(id), 600);
    }, 1500);
  }

  return {
    get agents() { return agents; },
    get desks() { return desks; },
    get selectedAgentId() { return selectedAgentId; },
    set selectedAgentId(v) { selectedAgentId = v; },
    get selectedAgent() { return selectedAgent; },
    engine,

    handleSpawn,
    handleWorking,
    handleIdle,
    handleComplete,
    handleDismissed,
    reset() {
      agents = [];
      desks = DESKS.map((d) => ({ ...d, occupantId: null }));
      selectedAgentId = null;
      nextCharacterIndex = 0;
      engine.clear();
    },

    selectAgent(id: string) { selectedAgentId = id; },
    dismissInspector() { selectedAgentId = null; },
    renameAgent(id: string, newName: string) {
      const agent = agents.find((a) => a.id === id);
      if (agent) {
        agent.name = newName;
        agents = [...agents];
        engine.updateName(id, newName);
      }
    },
  };
}
